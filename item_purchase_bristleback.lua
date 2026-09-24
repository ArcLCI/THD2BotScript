require(GetScriptDirectory() .. '/thd2_item_purchase')
local Kasen = require(GetScriptDirectory() .. '/THDFuncLib/kasen_state')
local Actions = require(GetScriptDirectory() .. '/THDFuncLib/action_intent')
local Consumables = require(GetScriptDirectory() .. '/THDFuncLib/consumable_inventory')
local Towers = require(GetScriptDirectory() .. '/THDFuncLib/tower_safety')
local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/avoidance_geometry')

-- 累积前缀始终保留已买组件的位置；确认门槛只暂停下一阶段，不重置通用购买序号。
local stages = {
	{'item_9ball', 'item_phoenix_wing', 'item_ice_block', 'item_recipe_wanmeitiaoyuezhuangzhi',
	 'item_esdw', 'item_dragon_star', 'item_flower_umbrella', 'item_wanbaochui2'},
	{'item_recipe_trinity'},
	{'item_horse_king', 'item_gap_creator'},
	{'item_loneliness'},
}
local prefixes, ends = {}, {}
local cumulative = {}
for stage, items in ipairs(stages) do
	for _, name in ipairs(items) do table.insert(cumulative, name) end
	prefixes[stage] = {}
	for _, name in ipairs(cumulative) do table.insert(prefixes[stage], name) end
	ends[stage] = #GetFullPurchaseList(prefixes[stage])
end
local seed

local function Slot(bot, name)
	for slot = 0, 14 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and item:GetName() == name then return slot end
	end
	return -1
end

local function Empty(bot, first, last)
	for slot = first, last do if bot:GetItemInSlot(slot) == nil then return slot end end
	return -1
end

local function Confirmed(bot, stage)
	if stage == 1 then
		local index = bot:GetModifierByName('modifier_item_wanbaochui')
		return type(index) == 'number' and index >= 0 and bot:GetModifierStackCount(index) == 99
	elseif stage == 2 then return Slot(bot, 'item_trinity') >= 0
	elseif stage == 3 then return Slot(bot, 'item_nb9ball') >= 0
	end
	return Slot(bot, 'item_loneliness') >= 0
end

local function SafeInventory(bot)
	if not bot:IsAlive() or Actions.Protected(bot) or Kasen.IsActive(bot)
	or bot:WasRecentlyDamagedByAnyHero(5) or bot:WasRecentlyDamagedByTower(5)
	or #CachedGetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE) > 0
	or Consumables.GetState(bot) ~= nil then return false end
	local observation = Towers.Observe(bot, 'kasen_inventory')
	if not observation.available then return false end
	for _, tower in ipairs(observation.towers) do
		if Geometry.PointInCircle(bot:GetLocation(), tower, 96) then return false end
	end
	return true
end

local function Swap(bot, from, to, reason)
	local incoming = bot:GetItemInSlot(from)
	if from >= 6 and from <= 8 and to <= 5 and incoming ~= nil then
		bot.THD_KasenItemReadyAt = bot.THD_KasenItemReadyAt or {}
		bot.THD_KasenItemReadyAt[incoming:GetName()] = DotaTime() + 6.25
	end
	bot:ActionImmediate_SwapItems(from, to)
	bot.THD_KasenInventoryUntil = DotaTime() + 0.75
	Kasen.Log(bot, 'inventory', reason)
end

local function ManageInventory(bot, state, cursor)
	if DotaTime() < (bot.THD_KasenInventoryUntil or -90) then return true end
	if DotaTime() < (state.nextManage or -90) then return false end
	state.nextManage = DotaTime() + 0.5
	if not SafeInventory(bot) then return false end
	local wing = Slot(bot, 'item_phoenix_wing')
	local gap, jump = Slot(bot, 'item_gap_creator'), Slot(bot, 'item_nb9ball')
	local main = Empty(bot, 0, 5)
	-- 合成后先恢复过渡时移出的凤凰翼，再放入最终第六件；不出售任何底材。
	if state.wingMoved and (jump >= 0 or DotaTime() > (state.restoreAt or 0)) then
		if wing >= 0 and wing <= 5 then state.wingMoved = nil
		elseif wing >= 6 and wing <= 8 and main >= 0 then
			Swap(bot, wing, main, 'restore_phoenix'); state.restoreAt = DotaTime() + 2; return true
		elseif wing >= 6 and wing <= 8 and state.vacated ~= nil then
			local occupant = bot:GetItemInSlot(state.vacated)
			-- 若未合成，只换回本模块临时放入的间隙发生器，不覆盖其他库存任务。
			if occupant ~= nil and occupant:GetName() == 'item_gap_creator' then
				Swap(bot, wing, state.vacated, 'restore_after_pending'); state.restoreAt = DotaTime() + 3; return true
			end
		end
	end
	-- 优先让永久槌在主包触发消耗，升级成品回主包后才参与主动决策。
	for _, name in ipairs({'item_wanbaochui2','item_nb9ball','item_trinity','item_loneliness'}) do
		local slot = Slot(bot, name)
		if slot >= 6 and slot <= 8 and main >= 0 then Swap(bot, slot, main, 'promote_' .. name); return true end
	end
	-- 牛逼跳跃的第三件需要临时空位。等待到货后才移动凤凰翼，最多停留两秒再尝试恢复。
	if jump < 0 and cursor > ends[2] and gap >= 6 and gap <= 8
	and wing >= 0 and wing <= 5 and not state.wingMoved then
		state.wingMoved, state.vacated, state.restoreAt = true, wing, DotaTime() + 2
		Swap(bot, gap, wing, 'assemble_nb9ball'); return true
	end
	-- 第六格中的永久槌/升级卷轴也可能在副包等待；空位可直接提升，不碰储藏处远程换位。
	if main >= 0 then
		for slot = 6, 8 do
			local item = bot:GetItemInSlot(slot)
			if item ~= nil and (item:GetName() ~= 'item_phoenix_wing' or not state.wingMoved) then
				Swap(bot, slot, main, 'promote_component'); return true
			end
		end
	end
	return false
end

function ItemPurchaseThink()
	local bot = GetBot()
	if not Kasen.IsHero(bot) then return end
	if seed == nil then seed = RandomInt(1, 999999999) end
	bot.THD_KasenPurchase = bot.THD_KasenPurchase or {stage=1, nextLog=-90}
	local state = bot.THD_KasenPurchase
	local cursor = GetNowEquipment(bot:GetPlayerID() * 100 + bot:GetTeam())
	if ManageInventory(bot, state, cursor) then return end
	-- 购买成功即由通用购买器推进；运输/合成未确认只能等待，绝不回退或再买。
	while state.stage < #stages and cursor > ends[state.stage] do
		if not Confirmed(bot, state.stage) then
			bot:SetNextItemPurchaseValue(0)
			if DotaTime() >= state.nextLog then
				Kasen.Log(bot, 'purchase_wait', 'stage_' .. state.stage)
				state.nextLog = DotaTime() + 15
			end
			return
		end
		Kasen.Log(bot, 'purchase_confirm', 'stage_' .. state.stage)
		state.stage = state.stage + 1
	end
	-- 火凤凰之翼尚未恢复时先完成恢复，不抢买最终装备占用空位。
	if state.stage == 4 and state.wingMoved then return end
	ConsiderItemPurchase(prefixes[state.stage], seed)
end
