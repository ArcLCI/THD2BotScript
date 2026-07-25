
require(GetScriptDirectory() ..  "/thd2_item_function")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local ROAM_DESIRE_INTERVAL = 1.0
local ROAM_DESIRE_LATE_INTERVAL = 5.0
local ROAM_DESIRE_STAGGER = 0.09
local ROAM_LATE_GAME_TIME = 25 * 60

local bot = GetBot()

local botName = bot:GetUnitName()

local cAbility = nil
local ConsiderHeroSpecificRoaming = {}

local droppedCheck = -90
local pickedItem = nil
local debug_printed = false

local edibleCheck = 900
local edibleItem = nil
local edibleItemSlot = -1

local item_edible_name = {"item_mushroom_kebab_immediate","item_mushroom_pie_immediate","item_mushroom_soup_immediate"}

local function ComputeDesire()
	if not Utils.AllowModeDesire(bot, 'roam') then return BOT_MODE_DESIRE_NONE end
	botName = bot:GetUnitName()

	if not debug_printed then
		print('roam_generic_ok')
		print(_VERSION)
		debug_printed = true
	end

	-- unit special abilities
	local specialRoaming = ConsiderHeroSpecificRoaming[botName]
	if specialRoaming then
		-- return specialRoaming
		local specialDesire = specialRoaming()
		if specialDesire and specialDesire > 0 then
			if specialDesire <= 1 then
				return Clamp(specialDesire, 0, 0.99)
			else
				return specialDesire
			end
		end
	end

	if not bot:IsAlive() or bot:GetCurrentActionType() == BOT_ACTION_TYPE_DELAY then
		return BOT_MODE_DESIRE_NONE
	end

	local roamDesireInterval = ROAM_DESIRE_INTERVAL
	if DotaTime() > ROAM_LATE_GAME_TIME then
		roamDesireInterval = ROAM_DESIRE_LATE_INTERVAL
	end

	if DotaTime() > 30 * 60 and not J.IsDoingRoshan(bot) and not J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
		if #nearbyEnemies == 0 then
			roamDesireInterval = 7.0
		end
	end

	if not Timer.ShouldRunBotTask(bot, 'roam_desire', roamDesireInterval, ROAM_DESIRE_STAGGER) then
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() >= edibleCheck + 2.0 then
		local item = nil
		local npcBot = GetBot()
		local breakLoop = false
    	for i = 6, 8 do
        	item = npcBot:GetItemInSlot(i)
        	if item ~= nil then
				for _, itemName in pairs(item_edible_name) do
					if item:GetName() == itemName then
						breakLoop = true
						break
					end
				end
				if breakLoop then
					edibleItemSlot = i
					break
				end
        	end
    	end
		edibleItem = item
		edibleCheck = DotaTime()
		-- 后期游走欲望检查频率较低，食物扫描后仍需继续检查地上的天丛云剑。
	end

	if edibleItem ~= nil and bot:HasModifier("modifier_fountain_aura_buff") then
		return BOT_MODE_DESIRE_VERYHIGH + 0.1
	end

	if DotaTime() >= droppedCheck + 2.0 then
			local item = nil
			local dropped = GetDroppedItemList()
			for _,drop in pairs(dropped) do
				if GetUnitToLocationDistance(bot, drop.location) <= 900 and GetSwitchableInventoryAmount(bot) > 0 then		--pickup item_kusanagi
					if drop.item:GetName() == "item_kusanagi" then
						--print("item == item_kusanagi")
						item = drop
						break
					end
				end
			end

			if item ~= nil then
				pickedItem = item
				return BOT_MODE_DESIRE_VERYHIGH
			end

			droppedCheck = DotaTime()
		end

	return 0

end

function GetDesire()
	local channelDesire = ConsiderHeroSpecificRoaming[bot:GetUnitName()]
	if channelDesire ~= nil then
		local desire = channelDesire()
		if desire ~= nil and desire > 0 then
			return desire
		end
	end

	return Utils.GetCachedModeDesire(bot, 'roam', ComputeDesire)
end

function OnEnd()

	pickedItem = nil

end

function OnStart() Utils.NoteModeStart(bot, 'roam') end

function Think()
	if CheckHighPriorityChannelAbility("ability_thdots_reisenOld03") > 0 then return end
	if not Timer.ShouldRunBotTask(bot, 'roam_think', 0.25, 0.04) then return end
	if J.CanNotUseAction(bot) then return end
	if edibleItem ~= nil then
		local lessValItem = GetMainInvLessValItemSlot(bot)
		if lessValItem ~= -1 and edibleItemSlot ~= -1 and bot:HasModifier("modifier_fountain_aura_buff") then
			bot:ActionImmediate_SwapItems( lessValItem, edibleItemSlot )
		end
	end

	if pickedItem ~= nil then
		--if not pickedItem.item:IsNull() then  print(botName.." picking up item "..pickedItem.item:GetName()) end
		if GetUnitToLocationDistance(bot, pickedItem.location) > 500 then
			J.ActionMoveToLocation(bot, "roam_pick_item", pickedItem.location, 0.5)
			return
		else
			if pickedItem.item:GetName() == "item_kusanagi" and GetUnitToLocationDistance(bot, pickedItem.location) <= 150 then
				local emptyBackpackSlot = GetEmptyBackpackSlot(bot)
				local lessValItem = GetMainInvLessValItemSlot(bot)
				if emptyBackpackSlot ~= -1 and lessValItem ~= -1 then
					bot:ActionImmediate_SwapItems( lessValItem, emptyBackpackSlot )
				end
			end
			--print("Distance: "..GetUnitToLocationDistance(bot, pickedItem.location))
			bot:Action_PickUpItem(pickedItem.item)
			return
		end
	end

end

------------------------------
-- 持续施法
------------------------------

function CheckHighPriorityChannelAbility(abilityName)
	if cAbility == nil then cAbility = bot:GetAbilityByName(abilityName) end
	if J.IsAbilityInChannelPhase(cAbility) then
		print("now channeling:"..abilityName)
		return BOT_MODE_DESIRE_ABSOLUTE
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_mirana'] = function ()
	return CheckHighPriorityChannelAbility("ability_thdots_reisenOld03")
end

function IsItemAvailable(item_name)
    local npcBot = GetBot()
    for i = 0, 5 do
        local item = npcBot:GetItemInSlot(i)
        if (item ~= nil) then
            if (item:GetName() == item_name) then
				return item
            end
        end
    end
    return nil
end
