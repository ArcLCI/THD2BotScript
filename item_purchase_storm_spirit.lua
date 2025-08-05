
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
	"item_horse_red",
	"item_wind_gun",
	"item_tentacle",
	"item_dummy_doll1",
	"item_eyunzhifu",
	"item_recipe_morenjingjuan",
	"item_nuclear_stick",
	"item_violin",
	"item_screw_driver",
	"item_recipe_inaba_illusion_weapon",
	"item_wanbaochui2",
	"item_ganggenier",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
}

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
