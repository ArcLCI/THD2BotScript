
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {}

if RandomInt(1,100) > 20 then
	tableItemsToBuy = {
	"item_pad",
	"item_cirno_claymore",
	"item_smash_stick",
	"item_recipe_yuetufensuijvren",
	"item_dragon_star",
	"item_aghanims_shard",
	"item_ganggenier",
	"item_sampan",
	"item_camera",
	"item_recipe_ertianyiliu",
	"item_loneliness",
}
else
	tableItemsToBuy = {
	"item_pad",
	"item_yueyaomishi",
	"item_nuclear_stick",
	"item_smash_stick",
	"item_recipe_yuetufensuijvren",
	"item_dragon_star",
	"item_aghanims_shard",
	"item_wanbaochui",
    "item_bagua",
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
	local randIndex = RandomInt(1,2)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(tableItemsToBuy) < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
