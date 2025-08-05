
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {}

if RandomInt(1,100) < 70 then
	tableItemsToBuy = {
	"item_horse_red",
	"item_rocket",
	"item_nuetrident",
	"item_tentacle",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_eyunzhifu",
	"item_recipe_morenjingjuan",
	"item_ganggenier",
	"item_bagua"
}
else
	tableItemsToBuy = {
	"item_horse_red",
	"item_rocket",
	"item_moon_bow",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_bagua",
	"item_yukkuri_stick",
	"item_wanbaochui2",
	"item_loneliness",
}
end


----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	local randIndex = RandomInt(2,3)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(tableItemsToBuy) < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)

	if npcBot:FindItemSlot("item_bagua") >=0 and npcBot:FindItemSlot("item_leiyunzhiyuchuan") >=0 then
		npcBot:ActionImmediate_SellItem(npcBot:GetItemInSlot(npcBot:FindItemSlot("item_leiyunzhiyuchuan")))
	end
end

----------------------------------------------------------------------------------------------------
