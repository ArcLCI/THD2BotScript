
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_mushroom",
				"item_catnip",
				"item_recipe_mushroom_pie",
				"item_cat_ear",
				"item_wind_amulet",
				"item_screw_driver",

				"item_knife",
				"item_recipe_watermelon",
				"item_screw_driver",
				"item_recipe_cirno_claymore",

				"item_horse_king_compressor",
					"item_recipe_horse_king",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
				"item_recipe_ganggenier",

				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_wrench",
				"item_recipe_sampan",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

				"item_recipe_ertianyiliu",

				"item_huanyingzhifeng",
				"item_huanyingzhifeng",
					"item_recipe_UFO",
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
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase and npcBot:GetGold() > npcBot:GetBuybackCost() + 540 then
		table.insert(tableItemsToBuy,tableEdible[2])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
