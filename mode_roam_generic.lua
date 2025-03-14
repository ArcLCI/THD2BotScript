
require(GetScriptDirectory() ..  "/thd2_item_function")

local bot = GetBot();

local botName = bot:GetUnitName()

local droppedCheck = -90;
local pickedItem = nil;
local debug_printed = false;

function GetDesire()

	if not debug_printed then
		print('roam_generic_ok')
		debug_printed = true
	end

	if not bot:IsAlive() or bot:GetCurrentActionType() == BOT_ACTION_TYPE_DELAY then
		return BOT_MODE_DESIRE_NONE;
	end

	if DotaTime() >= droppedCheck + 2.0 then
			local item = nil;
			local dropped = GetDroppedItemList();
			for _,drop in pairs(dropped) do
				if GetUnitToLocationDistance(bot, drop.location) <= 900 and GetSwitchableInventoryAmount(bot) > 0 then		--pickup item_kusanagi
					if drop.item:GetName() == "item_kusanagi" then
						--print("item == item_kusanagi")
						item = drop;
						break;
					end
				end
			end

			if item ~= nil then
				pickedItem = item;
				return BOT_MODE_DESIRE_VERYHIGH;
			end

			droppedCheck = DotaTime();
		end

	return 0;

end

function OnEnd()

	pickedItem = nil;

end

function Think()

	if pickedItem ~= nil then
		--if not pickedItem.item:IsNull() then  print(botName.." picking up item "..pickedItem.item:GetName()); end
		if GetUnitToLocationDistance(bot, pickedItem.location) > 500 then
			bot:Action_MoveToLocation(pickedItem.location);
			return
		else
			if pickedItem.item:GetName() == "item_kusanagi" and GetUnitToLocationDistance(bot, pickedItem.location) <= 150 then
				local emptyBackpackSlot = GetEmptyBackpackSlot(bot)
				local lessValItem = GetMainInvLessValItemSlot(bot)
				if emptyBackpackSlot ~= -1 and lessValItem ~= -1 then
					bot:ActionImmediate_SwapItems( lessValItem, emptyBackpackSlot );
				end
			end
			--print("Distance: "..GetUnitToLocationDistance(bot, pickedItem.location))
			bot:Action_PickUpItem(pickedItem.item);
			return
		end
	end

end