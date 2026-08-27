require(GetScriptDirectory() .. "/thd2_item_purchase")

local tableItemsToBuy = {
	"item_horse_red",
	"item_mystia_wings",
	"item_inaba_illusion_weapon",
	"item_dragon_star",
	"item_touhou_banana",
	"item_cat_foot",
	"item_recipe_brother_sharp",
	"item_ganggenier",
	"item_wanbaochui2",
	"item_glutton_spork",
	"item_recipe_trinity",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_wanmeitiaoyuezhuangzhi",
	"item_gap_creator",
}

local seedID = nil
local nextPurchase = -1

local function TryEquipFromBackpack(bot, itemName)
	local itemSlot = bot:FindItemSlot(itemName)
	if itemSlot < 6 or itemSlot > 8 then return false end
	for slot = 0, 5 do
		if bot:GetItemInSlot(slot) == nil then
			bot:ActionImmediate_SwapItems(itemSlot, slot)
			return true
		end
	end
	return false
end

function ItemPurchaseThink()
	if seedID == nil then seedID = RandomInt(1, 999999999) end

	local bot = GetBot()
	-- 合成会腾出主装备格；若终装落在背包，下一次购买 Think 立即换回主栏。
	if TryEquipFromBackpack(bot, "item_trinity") then return end
	if TryEquipFromBackpack(bot, "item_nb9ball") then return end

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
