require(GetScriptDirectory() .. "/thd2_item_purchase")

local tableItemsToBuy = {
	"item_horse_red",
	"item_inaba_illusion_weapon",
	"item_anchor",
	"item_dragon_star",
	"item_ganggenier",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_wanbaochui2",
	"item_yukkuri_stick",
	"item_glutton_spork",
	"item_recipe_trinity",
}

local seedID = nil
local nextPurchase = -1

local function HasItem(bot, itemName)
	return bot:FindItemSlot(itemName) >= 0
end

local function TryEquipTrinity(bot)
	local trinitySlot = bot:FindItemSlot("item_trinity")
	if trinitySlot < 6 or trinitySlot > 8 then return false end
	for slot = 0, 5 do
		if bot:GetItemInSlot(slot) == nil then
			bot:ActionImmediate_SwapItems(trinitySlot, slot)
			return true
		end
	end
	return false
end

local function TrySellAnchorForTrinity(bot)
	local anchorSlot = bot:FindItemSlot("item_anchor")
	if anchorSlot < 0 then return false end

	-- 饕餮叉勺是三位一体的第一件下位；买到后船锚完成过渡职责并让出装备格。
	if HasItem(bot, "item_yukkuri_stick")
	and (HasItem(bot, "item_glutton_spork") or HasItem(bot, "item_trinity"))
	then
		local anchor = bot:GetItemInSlot(anchorSlot)
		if anchor ~= nil then
			bot:ActionImmediate_SellItem(anchor)
			return true
		end
	end

	return false
end

function ItemPurchaseThink()
	if seedID == nil then seedID = RandomInt(1, 999999999) end

	local bot = GetBot()
	if TryEquipTrinity(bot) then return end
	if TrySellAnchorForTrinity(bot) then return end

	local tableEdible = {
		"item_mushroom_pie_immediate",
		"item_mushroom_kebab_immediate",
		"item_mushroom_soup_immediate",
	}
	if DotaTime() > 0
	and nextPurchase > 0
	and GetEquipmentMaxNum(tableItemsToBuy) < nextPurchase
	then
		table.insert(tableItemsToBuy, tableEdible[RandomInt(1, 3)])
	end

	nextPurchase = ConsiderItemPurchase(tableItemsToBuy, seedID)
end

----------------------------------------------------------------------------------------------------
