
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
	"item_broom",
	"item_rocket",
	"item_wanbaochui",
	"item_recipe_gap_creator",
	"item_bagua",
	"item_yukkuri_stick",
	"item_recipe_wanbaochui2",
	"item_nuclear_stick",
	"item_loneliness",
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
