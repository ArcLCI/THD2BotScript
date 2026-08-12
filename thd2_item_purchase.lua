require(GetScriptDirectory() ..  "/thd2_item_recipe_list")
local LaneAssignment = require(GetScriptDirectory()..'/THDFuncLib/lane_assignment')
local RoamConfig = require(GetScriptDirectory()..'/THDFuncLib/roam_config')

function FindItem(item_name)
    local npcBot = GetBot()
    for i = 0, 8 do
        local item = npcBot:GetItemInSlot(i)
        if (item ~= nil) then
            if (item:GetName() == item_name) then
				return item
            end
        end
    end
    return
end

function GetEquipmentMaxNum(tPurchaseList)
	return #GetFullPurchaseList(tPurchaseList)
end

local run_checker = {}
local now_equip = {}

function GetNowEquipment(runnerSeed)
	if now_equip[runnerSeed] == nil then
		now_equip[runnerSeed] = 1
	end
	return now_equip[runnerSeed]
end

function NextEquipment(runnerSeed)
	now_equip[runnerSeed] = now_equip[runnerSeed] + 1
	return now_equip[runnerSeed]
end

function FixMultiTriggedScript(runnerSeed)
    local npcBot = GetBot()
	if run_checker[runnerSeed] ~= nil then return run_checker[runnerSeed] end
	print('=========')
	print('New runnerSeed.')
	print(runnerSeed)
	-- trigged from in game must be error.
	if GetGameState() < GAME_STATE_GAME_IN_PROGRESS then
		print('=========')
		print(GameTime())
		print(run_checker[runnerSeed])
		--should run
		run_checker[runnerSeed] = true
	else
		--should not run
		print('error cleared ok')
		run_checker[runnerSeed] = false
	end
	return run_checker[runnerSeed]
end

local runnerSeedIDCounter = {}
local lastrunnerSeedID = {}

local last_purchase = {}
local last_purchased = {}
local purchase_retry_time = {}
local consumable_purchase_retry_time = {}

THD_BOT_EDIBLE_PURCHASE_ENABLED = THD_BOT_EDIBLE_PURCHASE_ENABLED or false
THD_BOT_EDIBLE_PURCHASE_LIMIT = THD_BOT_EDIBLE_PURCHASE_LIMIT or 0
THD_BOT_EDIBLE_PURCHASE_STATS = THD_BOT_EDIBLE_PURCHASE_STATS or {
	blocked = 0,
	allowed = 0,
	byItem = {},
}
local edible_purchase_count = {}
local edible_items = {
	item_mushroom_pie_immediate = true,
	item_mushroom_kebab_immediate = true,
	item_mushroom_soup_immediate = true,
}

local function GetPlayerIDSafe(unit)
	if unit == nil then return -1 end
	local ok, value = pcall(function() return unit:GetPlayerID() end)
	return ok and value or -1
end

local function GetDesignatedConsumableOwner(itemName)
	local preferred = itemName == 'item_smoke_of_deceit'
		and {hard_support = 1, soft_support = 2, off_core = 3}
		or {soft_support = 1, hard_support = 2, off_core = 3}
	local fallback = {mid = 10, safe_core = 11}
	local best, bestRank, bestID = nil, math.huge, math.huge
	local players = GetTeamPlayers(GetTeam()) or {}
	for index = 1, math.max(#players, 5) do
		local member = GetTeamMember(index)
		if member ~= nil and member.IsBot ~= nil and member:IsBot() then
			local position = LaneAssignment.GetAssignedPosition(member)
			-- 辅助位不由 Bot 控制时仍选一个确定的 Bot 兜底，避免整队永远没有补货 owner。
			local rank = preferred[position] or fallback[position] or 20
			local playerID = GetPlayerIDSafe(member)
			if rank ~= nil and (rank < bestRank or (rank == bestRank and playerID < bestID)) then
				best, bestRank, bestID = member, rank, playerID
			end
		end
	end
	return best
end

local function GetTeamItemLocation(itemName)
	local players = GetTeamPlayers(GetTeam()) or {}
	local members = {}
	for index = 1, math.max(#players, 5) do
		local member = GetTeamMember(index)
		if member ~= nil then table.insert(members, member) end
	end
	-- 先检查全队所有可携带槽，不能被较早成员储藏处里的同名物品提前截断。
	for _, member in ipairs(members) do
		for slot = 0, 8 do
			local item = member:GetItemInSlot(slot)
			if item ~= nil and item:GetName() == itemName then return 'carried', member, slot end
		end
	end
	for _, member in ipairs(members) do
		for slot = 9, 14 do
			local item = member:GetItemInSlot(slot)
			if item ~= nil and item:GetName() == itemName then return 'stored', member, slot end
		end
	end
	return nil, nil, -1
end

local function HasCarriedInventorySpace(unit)
	if unit == nil then return false end
	for slot = 0, 8 do
		if unit:GetItemInSlot(slot) == nil then return true end
	end
	return false
end

local function EnemyDraftNeedsDust()
	local registry = RoamConfig.INVISIBILITY_HEROES or {}
	local aliases = RoamConfig.INVISIBILITY_SELECTION_ALIASES or {}
	for _, playerID in pairs(GetTeamPlayers(GetOpposingTeam()) or {}) do
		local heroName = GetSelectedHeroName(playerID)
		local customHero = aliases[heroName]
		if registry[heroName] == true or registry[customHero] == true then return true end
	end
	return false
end

local function TryPurchaseRoamConsumable(npcBot, runnerSeed)
	if RoamConfig.CONSUMABLE_PURCHASE_ENABLED ~= true or DotaTime() < RoamConfig.PICKOFF_START_TIME then return false end
	local desiredItems = {'item_smoke_of_deceit'}
	if EnemyDraftNeedsDust() then table.insert(desiredItems, 'item_dust') end
	for _, itemName in ipairs(desiredItems) do
		local owner = GetDesignatedConsumableOwner(itemName)
		if owner ~= nil and GetPlayerIDSafe(owner) == GetPlayerIDSafe(npcBot) then
			local retryKey = tostring(runnerSeed) .. ':' .. itemName
			local location, holder, slot = GetTeamItemLocation(itemName)
			if location == 'stored' then
				if RealTime() >= (consumable_purchase_retry_time[retryKey] or -9999) then
					consumable_purchase_retry_time[retryKey] = RealTime() + 10
					print(npcBot:GetPlayerID() .. '[ItemPurchase] roam_consumable_wait item=' .. itemName
						.. ' reason=stored holder=' .. tostring(GetPlayerIDSafe(holder)) .. ' slot=' .. tostring(slot))
				end
			elseif location == nil and not HasCarriedInventorySpace(npcBot) then
				if RealTime() >= (consumable_purchase_retry_time[retryKey] or -9999) then
					consumable_purchase_retry_time[retryKey] = RealTime() + 10
					print(npcBot:GetPlayerID() .. '[ItemPurchase] roam_consumable_wait item=' .. itemName
						.. ' reason=owner_inventory_full')
				end
				return false
			elseif location == nil and RealTime() >= (consumable_purchase_retry_time[retryKey] or -9999) then
				local cost = GetItemCost(itemName)
				if npcBot:GetGold() >= cost and GetItemStockCount(itemName) > 0 then
					consumable_purchase_retry_time[retryKey] = RealTime() + 10
					local result = npcBot:ActionImmediate_PurchaseItem(itemName)
					if result == PURCHASE_ITEM_SUCCESS then
						print(npcBot:GetPlayerID() .. '[ItemPurchase] roam_consumable=' .. itemName)
						return true
					end
				end
			end
		end
	end
	return false
end

local function IsEdibleImmediateItem(itemName)
	return edible_items[itemName] == true
end

function SetBotEdiblePurchaseEnabled(enabled)
	THD_BOT_EDIBLE_PURCHASE_ENABLED = enabled == true
	print("[THD][BotEdiblePurchase] enabled=" .. tostring(THD_BOT_EDIBLE_PURCHASE_ENABLED))
end

function SetBotEdiblePurchaseLimit(limit)
	local value = tonumber(limit)
	if value == nil or value < 0 then return false end
	THD_BOT_EDIBLE_PURCHASE_LIMIT = value
	print("[THD][BotEdiblePurchase] limit=" .. tostring(value))
	return true
end

function GetBotEdiblePurchaseStats()
	return THD_BOT_EDIBLE_PURCHASE_STATS
end

local function CanPurchaseEdibleImmediate(runnerSeed, itemName)
	if not IsEdibleImmediateItem(itemName) then return true end
	local stats = THD_BOT_EDIBLE_PURCHASE_STATS
	if THD_BOT_EDIBLE_PURCHASE_ENABLED ~= true then
		stats.blocked = (stats.blocked or 0) + 1
		stats.byItem[itemName] = (stats.byItem[itemName] or 0) + 1
		return false
	end
	edible_purchase_count[runnerSeed] = edible_purchase_count[runnerSeed] or 0
	if edible_purchase_count[runnerSeed] >= (THD_BOT_EDIBLE_PURCHASE_LIMIT or 0) then
		stats.blocked = (stats.blocked or 0) + 1
		stats.byItem[itemName] = (stats.byItem[itemName] or 0) + 1
		return false
	end
	return true
end

function ConsiderItemPurchase(tableItemsToBuy,runnerSeedID)

	local tableItemsToBuyFullList = GetFullPurchaseList(tableItemsToBuy)
	if not tableItemsToBuyFullList then
		return -1
	end

	if not last_purchased[runnerSeedID] then
		if last_purchase[runnerSeedID] == nil then
			last_purchase[runnerSeedID] = RealTime() + GetBot():GetPlayerID()*0.1
		end

		if last_purchase[runnerSeedID] + 5 < RealTime() then
			-- print(runnerSeedID .. ' still thinking.')
			last_purchase[runnerSeedID] = RealTime()
		else
			return -1
		end
	end

	local npcBot = GetBot()
	local nextPurchase

	--basic checking
	if runnerSeedIDCounter[runnerSeedID] == nil then
		print('=========')
		print('New Consider Item Purchase.')
		print(runnerSeedID)
		if(npcBot:IsIllusion()) then
			runnerSeedIDCounter[runnerSeedID] = false
		else
			runnerSeedIDCounter[runnerSeedID] = true
			if lastrunnerSeedID[npcBot:GetPlayerID()] ~= nil then
				runnerSeedIDCounter[lastrunnerSeedID[npcBot:GetPlayerID()]] = false
			end
		end
		lastrunnerSeedID[npcBot:GetPlayerID()] = runnerSeedID
	end

	if runnerSeedIDCounter[runnerSeedID] == false then
		npcBot:SetNextItemPurchaseValue( 0 )
		return -1
	end

	--basic checking end

	local runnerSeed = npcBot:GetPlayerID() *100 + npcBot:GetTeam()
	-- notice: old runnerSeedID will cancel when old entity erased(like medicine R)
	-- don't use SeedID to recognize caster, create own seed instead
	if FixMultiTriggedScript(runnerSeed) == false then
		npcBot:SetNextItemPurchaseValue( 0 )
		return -1
	end
	-- 补货必须先于常规出装完成后的提前返回，才能在整场中后期持续维持烟与粉。
	if TryPurchaseRoamConsumable(npcBot, runnerSeed) then
		last_purchased[runnerSeedID] = false
		return -1
	end

	--print(GetNowEquipment(runnerSeed))
	if ( #tableItemsToBuyFullList < GetNowEquipment(runnerSeed) )
	then
		npcBot:SetNextItemPurchaseValue( 0 )
		return -1
	end

	--prevent drop items from stash
	--[[if not ( GetSwitchableInventoryAmount(npcBot) > 0 )
	then
		npcBot:SetNextItemPurchaseValue( 0 )
		return -1
	end]]--

	local sNextItem = tableItemsToBuyFullList[GetNowEquipment(runnerSeed)]
	if not CanPurchaseEdibleImmediate(runnerSeed, sNextItem) then
		npcBot:SetNextItemPurchaseValue( 0 )
		return -1
	end
	if purchase_retry_time[runnerSeed] ~= nil and RealTime() < purchase_retry_time[runnerSeed] then
		npcBot:SetNextItemPurchaseValue( GetItemCost( sNextItem ) )
		return -1
	end

	if ( npcBot:GetGold() >= GetItemCost( sNextItem ) )
	then
		print(npcBot:GetPlayerID().."[ItemPurchase] purchasing "..sNextItem)
		local purchaseResult = npcBot:ActionImmediate_PurchaseItem( sNextItem )
		if purchaseResult == PURCHASE_ITEM_SUCCESS then
			if IsEdibleImmediateItem(sNextItem) then
				edible_purchase_count[runnerSeed] = (edible_purchase_count[runnerSeed] or 0) + 1
				THD_BOT_EDIBLE_PURCHASE_STATS.allowed = (THD_BOT_EDIBLE_PURCHASE_STATS.allowed or 0) + 1
			end
			nextPurchase = NextEquipment(runnerSeed)
			sNextItem = tableItemsToBuyFullList[nextPurchase]
			if sNextItem ~= nil then
				npcBot:SetNextItemPurchaseValue( GetItemCost( sNextItem ) )
				print(npcBot:GetPlayerID().."[ItemPurchase] purchased "..sNextItem)
			end
			last_purchased[runnerSeedID] = true
		else
			purchase_retry_time[runnerSeed] = RealTime() + 3.0
			last_purchased[runnerSeedID] = false
		end
	else
		last_purchased[runnerSeedID] = false
	end
	if nextPurchase ~= nil then
		return nextPurchase
	end
	return -1
end
