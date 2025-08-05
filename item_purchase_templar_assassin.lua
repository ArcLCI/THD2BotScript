
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {}
if RandomInt(1,100) > 50 then
	tableItemsToBuy = {
	"item_horse_red",
	"item_yueyaomishi",
	"item_nuclear_stick",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_dragon_star",
    "item_bagua",
    "item_wanbaochui2",
	"item_loneliness",
	}
else
	tableItemsToBuy = {
	"item_horse_red",
	"item_yueyaomishi",
	"item_nuclear_stick",
    "item_bagua",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_wanbaochui",
	"item_yukkuri_stick",
	"item_recipe_wanbaochui2",
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
	local randIndex = RandomInt(1,3)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(tableItemsToBuy) < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)

end

----------------------------------------------------------------------------------------------------