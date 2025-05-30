local Item = {}

Item['sCanNotSwitchItems'] = {
    'item_aegis',
    --'item_refresher_shard',
    --'item_cheese',
    --'item_bloodstone',
    'item_gem',
	'item_kusanagi',
	'item_mushroom_kebab_immediate',
	'item_mushroom_pie_immediate',
	'item_mushroom_soup_immediate',
}

local tCanNotSwitchItemList = {}
for _, sItem in pairs( Item['sCanNotSwitchItems'] )
do
	tCanNotSwitchItemList[sItem] = true
end

function IsCanNotSwitchItem( sItemName )

	return tCanNotSwitchItemList[sItemName] == true

end

function GetEmptyInventoryAmount( bot )

	local amount = 0
	for i = 0, 8
	do
		local item = bot:GetItemInSlot( i )
		if item == nil
		then
			amount = amount + 1
		end
	end

	return amount

end

function GetSwitchableInventoryAmount( bot )

	local amount = 0

	if GetEmptyBackpackSlot(bot) >0 then
		for i = 0, 5
		do
			local item = bot:GetItemInSlot( i )
			if item == nil
				or not IsCanNotSwitchItem( item:GetName() )
			then
				amount = amount + 1
			end
		end
	end

	return amount

end

function GetMainInvLessValItemSlot( bot )

	local minPrice = 10000
	local minSlot = - 1
	for i = 0, 5
	do
		local item = bot:GetItemInSlot( i )

		if item == nil
		then
			return i
		end

		if item ~= nil
			and not IsCanNotSwitchItem( item:GetName() )
		then
			local cost = GetItemCost( item:GetName() )
			if cost < minPrice then
				minPrice = cost
				minSlot = i
			end
		end
	end

	return minSlot

end

function GetEmptyBackpackSlot( bot )

	local emptySlot = -1
	for i = 6, 8
	do
		local item = bot:GetItemInSlot( i )
		if item == nil and bot:GetItemSlotType(i) == ITEM_SLOT_TYPE_BACKPACK
		then
			emptySlot = i
			break
		end
	end

	return emptySlot

end