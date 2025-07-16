
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

function ConsiderItemPurchase(tableItemsToBuy,runnerSeedID)
	
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
	if ( #tableItemsToBuy < GetNowEquipment(runnerSeed) )
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

	local sNextItem = tableItemsToBuy[GetNowEquipment(runnerSeed)]

	if ( npcBot:GetGold() >= GetItemCost( sNextItem ) )
	then
		print(npcBot:GetPlayerID().."[ItemPurchase] purchasing "..sNextItem)
		npcBot:ActionImmediate_PurchaseItem( sNextItem )
		nextPurchase = NextEquipment(runnerSeed)
		sNextItem = tableItemsToBuy[nextPurchase]
		if sNextItem ~= nil then
			npcBot:SetNextItemPurchaseValue( GetItemCost( sNextItem ) )
			print(npcBot:GetPlayerID().."[ItemPurchase] purchased "..sNextItem)
		end

		last_purchased[runnerSeedID] = true
	else
		last_purchased[runnerSeedID] = false
	end
	if nextPurchase ~= nil then
		return nextPurchase
	end
	return -1
end