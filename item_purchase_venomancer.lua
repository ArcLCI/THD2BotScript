
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
    "item_9ball",
    "item_flower_umbrella",
	"item_dragon_star",
    "item_ice_block",
    "item_recipe_wanmeitiaoyuezhuangzhi",
	"item_laevateinn",
	"item_wanbaochui",
	"item_cirno_claymore",
	"item_recipe_wanbaochui2",
	"item_sampan",
    "item_recipe_ertianyiliu",
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
