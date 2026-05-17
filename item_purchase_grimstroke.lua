
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
	"item_horse_red",
	"item_nuetrident",
	"item_nuclear_stick",
	"item_ganggenier",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_camera",
	"item_frozen_frog",
}

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
		table.insert(tableItemsToBuy,tableEdible[2])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
