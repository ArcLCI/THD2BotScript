require(GetScriptDirectory() .. "/thd2_item_purchase")

local tableItemsToBuy = {
	"item_horse_red",
	"item_yatagarasu",
	"item_yukkuri_stick",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_tsundere",
	"item_nuclear_stick",
	"item_bagua",
	"item_wanbaochui2",
	"item_sss",
	"item_recipe_trinity",
}

local seedID = nil
local nextPurchase = -1
local yatagarasuSold = false

local function HasItem(bot, itemName)
	return bot:FindItemSlot(itemName) >= 0
end

local function SellItem(bot, itemName)
	local slot = bot:FindItemSlot(itemName)
	if slot < 0 then return false end
	local item = bot:GetItemInSlot(slot)
	if item == nil then return false end
	bot:ActionImmediate_SellItem(item)
	return true
end

local function TrySellTransitionItems(bot)
	-- 八卦炉完成后让八咫乌退出最终六格，为七星剑和三位一体卷轴预留主装备栏。
	if not yatagarasuSold and HasItem(bot, "item_bagua") then
		yatagarasuSold = true
		if SellItem(bot, "item_yatagarasu") then return true end
	end
	return false
end

function ItemPurchaseThink()
	if seedID == nil then seedID = RandomInt(1, 999999999) end
	local bot = GetBot()
	if TrySellTransitionItems(bot) then return end

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
