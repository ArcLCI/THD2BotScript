local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
require(GetScriptDirectory() .. "/thd2_item_function")

local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local Timer = require(GetScriptDirectory()..'/thd2_timer')
local FlandreUltimate = require(GetScriptDirectory()..'/THDFuncLib/flandre_ultimate')
local SunnyUltimate = require(GetScriptDirectory()..'/THDFuncLib/sunny_ultimate')
local YuukaCombo = require(GetScriptDirectory()..'/THDFuncLib/yuuka_combo')
local NitoriPoke = require(GetScriptDirectory()..'/THDFuncLib/nitori_poke')
local Consumables = require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')

local Auxiliary = {}

local ROAM_DESIRE_INTERVAL = 1.0
local ROAM_DESIRE_LATE_INTERVAL = 5.0
local ROAM_DESIRE_STAGGER = 0.09
local ROAM_LATE_GAME_TIME = 25 * 60

local KUSANAGI_ITEM_NAME = "item_kusanagi"
local KUSANAGI_DROP_RETRY_INTERVAL = 1.0
local KUSANAGI_DROP_TIMEOUT = 3.0
local KUSANAGI_RETRY_COOLDOWN = 10.0
local KUSANAGI_RECOVERY_GRACE = 2.0
local KUSANAGI_RECOVERY_PICKUP_RADIUS = 500
local KUSANAGI_DISPLACEMENT_PROTECTED_ITEMS = {
	item_ward_observer = true,
	item_ward_sentry = true,
	item_jiduzhixinyan = true,
}

local bot = GetBot()
local botName = bot:GetUnitName()
local cAbility = nil
local ConsiderHeroSpecificRoaming = {}
local HeroSpecificProvider = {}
local cachedProvider = 'none'

local droppedCheck = -90
local pickedItem = nil
local debugPrinted = false
local edibleCheck = 900
local edibleItem = nil
local edibleItemSlot = -1
local itemEdibleNames = {
	"item_mushroom_kebab_immediate",
	"item_mushroom_pie_immediate",
	"item_mushroom_soup_immediate",
}

local displacedItem = nil
local displacedItemDropTime = -90
local displacedItemStartTime = -90
local blockedKusanagiItem = nil
local blockedKusanagiUntil = -90

local function IsItemInBotInventory(item)
	if item == nil then return false end
	for slot = 0, 8 do
		if bot:GetItemInSlot(slot) == item then return true end
	end
	return false
end

local function HasKusanagiInInventory()
	return bot:FindItemSlot(KUSANAGI_ITEM_NAME) >= 0
end

local function FindDroppedItemByHandle(item)
	if item == nil then return nil end
	for _, drop in pairs(GetDroppedItemList()) do
		if drop ~= nil and drop.item == item then return drop end
	end
	return nil
end

local function ClearDisplacedItem()
	displacedItem = nil
	displacedItemDropTime = -90
	displacedItemStartTime = -90
end

local function GetLeastValuableRecoverableItemSlot()
	local minPrice = 10000
	local minSlot = -1
	for slot = 0, 8 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil
			and not IsCanNotSwitchItem(item:GetName())
			and not KUSANAGI_DISPLACEMENT_PROTECTED_ITEMS[item:GetName()]
		then
			local cost = GetItemCost(item:GetName())
			if cost < minPrice then
				minPrice = cost
				minSlot = slot
			end
		end
	end
	return minSlot
end

local function GetKusanagiMainSlot(unit)
	unit = unit or bot
	local minPrice = 10000
	local minSlot = -1
	for slot = 0, 5 do
		local item = unit:GetItemInSlot(slot)
		if item == nil then return slot end
		if not IsCanNotSwitchItem(item:GetName())
			and not KUSANAGI_DISPLACEMENT_PROTECTED_ITEMS[item:GetName()]
		then
			local cost = GetItemCost(item:GetName())
			if cost < minPrice then
				minPrice = cost
				minSlot = slot
			end
		end
	end
	return minSlot
end

local function CanMakeKusanagiMainSlot(unit)
	return GetKusanagiMainSlot(unit) ~= -1
end

local function GetPlayerID(unit)
	if unit == nil or unit.GetPlayerID == nil then return -1 end
	local ok, playerID = pcall(function() return unit:GetPlayerID() end)
	return ok and playerID or -1
end

local function GetKusanagiClaimant(location)
	local candidates = {}
	local seen = {}
	local teamPlayers = nil
	if GetTeamPlayers ~= nil then
		local team = bot.GetTeam ~= nil and bot:GetTeam() or nil
		local ok, result = pcall(function() return GetTeamPlayers(team) end)
		if ok and type(result) == 'table' then teamPlayers = result end
	end
	local teamSize = teamPlayers ~= nil and #teamPlayers or 0
	if teamSize <= 0 then teamSize = 5 end
	if GetTeamMember ~= nil then
		for index = 1, teamSize do
			local ok, member = pcall(function() return GetTeamMember(index) end)
			if ok and member ~= nil then table.insert(candidates, member) end
		end
	end
	table.insert(candidates, bot)

	local claimant = nil
	local claimantDistance = math.huge
	local claimantID = math.huge
	for _, member in ipairs(candidates) do
		local memberID = GetPlayerID(member)
		local key = memberID >= 0 and ('player:' .. tostring(memberID)) or tostring(member)
		if not seen[key] then
			seen[key] = true
			local alive = member.IsAlive == nil or member:IsAlive()
			local isBot = member.IsBot == nil or member:IsBot()
			local distance = GetUnitToLocationDistance(member, location)
			if alive and isBot and distance <= 900 and CanMakeKusanagiMainSlot(member)
				and (distance < claimantDistance
					or (distance == claimantDistance and memberID < claimantID))
			then
				claimant = member
				claimantDistance = distance
				claimantID = memberID
			end
		end
	end
	return claimant
end

local function CheckHighPriorityChannelAbility(abilityName)
	if cAbility == nil then cAbility = bot:GetAbilityByName(abilityName) end
	if J.IsAbilityInChannelPhase(cAbility) then
		return BOT_MODE_DESIRE_ABSOLUTE
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_mirana'] = function()
	return CheckHighPriorityChannelAbility("ability_thdots_reisenOld03")
end
HeroSpecificProvider['npc_dota_hero_mirana'] = 'channel_reisen'

ConsiderHeroSpecificRoaming['npc_dota_hero_naga_siren'] = function()
	return FlandreUltimate.GetModeDesire(bot)
end
HeroSpecificProvider['npc_dota_hero_naga_siren'] = 'flandre_ultimate'

ConsiderHeroSpecificRoaming['npc_dota_hero_rattletrap'] = function()
	return SunnyUltimate.GetModeDesire(bot)
end
HeroSpecificProvider['npc_dota_hero_rattletrap'] = 'sunny_ultimate'

ConsiderHeroSpecificRoaming['npc_dota_hero_venomancer'] = function()
	return YuukaCombo.GetModeDesire(bot)
end
HeroSpecificProvider['npc_dota_hero_venomancer'] = 'yuuka_combo'

ConsiderHeroSpecificRoaming['npc_dota_hero_spectre'] = function()
	return NitoriPoke.GetModeDesire(bot)
end
HeroSpecificProvider['npc_dota_hero_spectre'] = 'nitori_poke'

local function ScanEdibleItem()
	if DotaTime() < edibleCheck + 2.0 then return end
	local item = nil
	local breakLoop = false
	for slot = 6, 8 do
		item = bot:GetItemInSlot(slot)
		if item ~= nil then
			for _, itemName in pairs(itemEdibleNames) do
				if item:GetName() == itemName then
					edibleItemSlot = slot
					breakLoop = true
					break
				end
			end
			if breakLoop then break end
		end
	end
	edibleItem = breakLoop and item or nil
	edibleCheck = DotaTime()
end

local function ScanKusanagi()
	if DotaTime() < droppedCheck + 2.0 then return BOT_MODE_DESIRE_NONE end
	if blockedKusanagiItem ~= nil and DotaTime() >= blockedKusanagiUntil then
		blockedKusanagiItem = nil
		blockedKusanagiUntil = -90
	end

	for _, drop in pairs(GetDroppedItemList()) do
		if drop.item ~= nil
			and drop.item ~= blockedKusanagiItem
			and drop.item:GetName() == KUSANAGI_ITEM_NAME
			and GetKusanagiClaimant(drop.location) == bot
		then
			pickedItem = drop
			return BOT_MODE_DESIRE_VERYHIGH
		end
	end
	droppedCheck = DotaTime()
	return BOT_MODE_DESIRE_NONE
end

local function ComputeDesire()
	cachedProvider = 'none'
	if not Utils.AllowModeDesire(bot, 'roam') then CandidateDebug.Note('mode_switch_lock'); return BOT_MODE_DESIRE_NONE end
	botName = bot:GetUnitName()

	if not debugPrinted then
		print('roam_generic_ok')
		print(_VERSION)
		debugPrinted = true
	end

	if not bot:IsAlive() or bot:GetCurrentActionType() == BOT_ACTION_TYPE_DELAY then
		CandidateDebug.Note('dead_or_delay_action')
		return BOT_MODE_DESIRE_NONE
	end

	local roamDesireInterval = ROAM_DESIRE_INTERVAL
	if DotaTime() > ROAM_LATE_GAME_TIME then roamDesireInterval = ROAM_DESIRE_LATE_INTERVAL end
	if DotaTime() > 30 * 60
		and not J.IsRoshanCommitmentActive(bot)
		and not J.Utils.IsTeamPushingSecondTierOrHighGround(bot)
		and #bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) == 0
	then
		roamDesireInterval = 7.0
	end
	if not Timer.ShouldRunBotTask(bot, 'roam_desire', roamDesireInterval, ROAM_DESIRE_STAGGER) then
		CandidateDebug.Note('scan_throttled')
		return BOT_MODE_DESIRE_NONE
	end

	ScanEdibleItem()
	if edibleItem ~= nil and bot:HasModifier("modifier_fountain_aura_buff") then
		cachedProvider = 'edible_swap'
		CandidateDebug.Note('edible_swap')
		return BOT_MODE_DESIRE_VERYHIGH + 0.1
	end
	local desire = ScanKusanagi()
	if desire > BOT_MODE_DESIRE_NONE then cachedProvider = 'kusanagi_pickup' end
	CandidateDebug.Note('no_item_task_or_kusanagi')
	return desire
end

function Auxiliary.GetDesire()
	local specialRoaming = ConsiderHeroSpecificRoaming[bot:GetUnitName()]
	if specialRoaming ~= nil then
		local desire = specialRoaming()
		if desire ~= nil and desire > 0 then
			CandidateDebug.Note('hero_auxiliary')
			return desire, HeroSpecificProvider[bot:GetUnitName()] or 'hero_specific'
		end
	end

	if pickedItem ~= nil and HasKusanagiInInventory() then pickedItem = nil end
	local shouldYieldToRetreat = J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
	if displacedItem ~= nil and pickedItem == nil then
		if IsItemInBotInventory(displacedItem) then
			if DotaTime() >= displacedItemStartTime + KUSANAGI_DROP_TIMEOUT then ClearDisplacedItem() end
		elseif not HasKusanagiInInventory() then
			local droppedItem = FindDroppedItemByHandle(displacedItem)
			if droppedItem ~= nil
				and GetUnitToLocationDistance(bot, droppedItem.location) <= KUSANAGI_RECOVERY_PICKUP_RADIUS
			then
				CandidateDebug.Note('item_recovery_near')
				return BOT_MODE_DESIRE_ABSOLUTE * 0.98, 'kusanagi_recovery'
			end
			if droppedItem ~= nil and not shouldYieldToRetreat then CandidateDebug.Note('item_recovery'); return BOT_MODE_DESIRE_VERYHIGH, 'kusanagi_recovery' end
			if droppedItem == nil and DotaTime() <= displacedItemDropTime + KUSANAGI_RECOVERY_GRACE then
				CandidateDebug.Note('item_recovery_grace')
				return BOT_MODE_DESIRE_VERYHIGH, 'kusanagi_recovery'
			end
			if droppedItem ~= nil then CandidateDebug.Note('item_recovery_retreat'); return BOT_MODE_DESIRE_NONE end
			ClearDisplacedItem()
		end
	end

	if shouldYieldToRetreat then
		pickedItem = nil
		CandidateDebug.Note('high_retreat')
		return BOT_MODE_DESIRE_NONE
	end
	local desire = Utils.GetCachedModeDesire(bot, 'roam_auxiliary', ComputeDesire)
	if desire == nil or desire <= BOT_MODE_DESIRE_NONE then return BOT_MODE_DESIRE_NONE, 'none' end
	return desire, cachedProvider
end

local function TryHandleDisplacedItem()
	if displacedItem == nil then return false end
	if HasKusanagiInInventory() then
		pickedItem = nil
		return false
	end

	local shouldYieldToRetreat = J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
	if shouldYieldToRetreat then pickedItem = nil end
	if J.CanNotUseAction(bot) then return true end

	if pickedItem ~= nil then
		local currentDroppedItem = FindDroppedItemByHandle(pickedItem.item)
		if currentDroppedItem == nil then
			pickedItem = nil
		elseif IsItemInBotInventory(displacedItem) then
			if DotaTime() >= displacedItemStartTime + KUSANAGI_DROP_TIMEOUT then
				blockedKusanagiItem = pickedItem.item
				blockedKusanagiUntil = DotaTime() + KUSANAGI_RETRY_COOLDOWN
				pickedItem = nil
				ClearDisplacedItem()
				return false
			end
			if DotaTime() >= displacedItemDropTime + KUSANAGI_DROP_RETRY_INTERVAL then
				displacedItemDropTime = DotaTime()
				bot:Action_DropItem(displacedItem, bot:GetLocation())
			end
			return true
		else
			pickedItem = currentDroppedItem
			if GetUnitToLocationDistance(bot, pickedItem.location) > KUSANAGI_RECOVERY_PICKUP_RADIUS then
				J.ActionMoveToLocation(bot, "roam_pick_item", pickedItem.location, 0.5)
				return true
			end

			local emptyBackpackSlot = GetEmptyBackpackSlot(bot)
			local lessValItem = GetKusanagiMainSlot()
			if lessValItem == -1 then
				pickedItem = nil
				return true
			end
			local lessValItemHandle = bot:GetItemInSlot(lessValItem)
			if lessValItemHandle ~= nil and emptyBackpackSlot == -1 then
				pickedItem = nil
				return true
			end
			if emptyBackpackSlot ~= -1 and lessValItemHandle ~= nil then
				bot:ActionImmediate_SwapItems(lessValItem, emptyBackpackSlot)
			end
			bot:Action_PickUpItem(pickedItem.item)
			return true
		end
	end

	if IsItemInBotInventory(displacedItem) then
		if DotaTime() >= displacedItemStartTime + KUSANAGI_DROP_TIMEOUT then
			ClearDisplacedItem()
			return false
		end
		return true
	end

	local droppedItem = FindDroppedItemByHandle(displacedItem)
	if droppedItem == nil then
		if DotaTime() > displacedItemDropTime + KUSANAGI_RECOVERY_GRACE then
			ClearDisplacedItem()
			return false
		end
		return true
	end

	local distance = GetUnitToLocationDistance(bot, droppedItem.location)
	if distance > KUSANAGI_RECOVERY_PICKUP_RADIUS then
		if not shouldYieldToRetreat then
			J.ActionMoveToLocation(bot, "roam_recover_kusanagi_item", droppedItem.location, 0.5)
		end
	elseif GetEmptyInventoryAmount(bot) > 0 then
		bot:Action_PickUpItem(droppedItem.item)
	end
	return true
end

function Auxiliary.Think()
	-- 消耗品租约活跃时，草薙剑回收与食用物交换必须让行，避免双方争抢同一主背包格。
	if Consumables.GetState(bot) ~= nil then
		if Consumables.Think(bot) then return end
	end
	-- 临时腾格恢复必须优先，避免英雄专用 Think 覆盖拾取或回收动作。
	if TryHandleDisplacedItem() then return end
	if NitoriPoke.Think(bot) then return end
	if YuukaCombo.Think(bot) then return end
	if FlandreUltimate.Think(bot) then return end
	if SunnyUltimate.Think(bot) then return end
	if CheckHighPriorityChannelAbility("ability_thdots_reisenOld03") > 0 then return end
	if not Timer.ShouldRunBotTask(bot, 'roam_auxiliary_think', 0.25, 0.04) then return end
	if J.CanNotUseAction(bot) then return end
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then
		pickedItem = nil
		return
	end

	if edibleItem ~= nil then
		local lessValItem = GetMainInvLessValItemSlot(bot)
		if lessValItem ~= -1 and edibleItemSlot ~= -1 and bot:HasModifier("modifier_fountain_aura_buff") then
			bot:ActionImmediate_SwapItems(lessValItem, edibleItemSlot)
		end
	end

	if pickedItem == nil then return end
	local currentDroppedItem = FindDroppedItemByHandle(pickedItem.item)
	if currentDroppedItem == nil then
		pickedItem = nil
		return
	end
	pickedItem = currentDroppedItem

	if GetUnitToLocationDistance(bot, pickedItem.location) > 500 then
		J.ActionMoveToLocation(bot, "roam_pick_item", pickedItem.location, 0.5)
		return
	end
	if GetUnitToLocationDistance(bot, pickedItem.location) <= 150 then
		local emptyBackpackSlot = GetEmptyBackpackSlot(bot)
		local lessValItem = GetKusanagiMainSlot()
		if lessValItem == -1 then
			pickedItem = nil
			return
		end

		local lessValItemHandle = bot:GetItemInSlot(lessValItem)
		if lessValItemHandle ~= nil and emptyBackpackSlot == -1 then
			if displacedItem == nil then
				local displacedSlot = GetLeastValuableRecoverableItemSlot()
				if displacedSlot == -1 then
					pickedItem = nil
					return
				end

				-- 九格全满时先临时丢下最低价值物品，兑换后再自动捡回。
				displacedItem = bot:GetItemInSlot(displacedSlot)
				displacedItemDropTime = DotaTime()
				displacedItemStartTime = displacedItemDropTime
				bot:Action_DropItem(displacedItem, bot:GetLocation())
			elseif IsItemInBotInventory(displacedItem)
				and DotaTime() >= displacedItemDropTime + KUSANAGI_DROP_RETRY_INTERVAL
			then
				displacedItemDropTime = DotaTime()
				bot:Action_DropItem(displacedItem, bot:GetLocation())
			end
			return
		end
		if emptyBackpackSlot ~= -1 and lessValItemHandle ~= nil then
			bot:ActionImmediate_SwapItems(lessValItem, emptyBackpackSlot)
		end
	end
	bot:Action_PickUpItem(pickedItem.item)
end

function Auxiliary.OnStart() end

function Auxiliary.OnEnd()
	pickedItem = nil
	NitoriPoke.OnEnd(bot)
end

return Auxiliary
