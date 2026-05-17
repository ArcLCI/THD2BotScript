require(GetScriptDirectory() ..  "/thd2_item_recipe_list")

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

local invalid_item_aliases = {
	item_frozen = "item_frozen_frog",
}

local function NormalizePurchaseItemName(itemName)
	return invalid_item_aliases[itemName] or itemName
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

	local sNextItem = NormalizePurchaseItemName(tableItemsToBuyFullList[GetNowEquipment(runnerSeed)])
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
			sNextItem = NormalizePurchaseItemName(tableItemsToBuyFullList[nextPurchase])
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