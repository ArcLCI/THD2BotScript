
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_knife",
					"item_recipe_watermelon",
				"item_screw_driver",
					"item_recipe_cirno_claymore",

				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
				"item_wind_lace",
				"item_sailor_suit",
					"item_recipe_mystia_wings",

				"item_paper_mask",
				"item_cat_foot",
				"item_silver_knife",
					"item_recipe_ganggenier",

				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_cat_foot",
					"item_recipe_brother_sharp",

				"item_horse_king_compressor",
					"item_recipe_horse_king",

				"item_silver_knife",
				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
					"item_recipe_teeth",

				"item_knife",
				"item_scissors",
					"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",
					"item_recipe_ertianyiliu",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

			}


----------------------------------------------------------------------------------------------------

local seed_id = nil

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
