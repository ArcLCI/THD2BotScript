
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_cake",
				"item_juice",
				"item_recipe_harvest_cradle",

				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",

				"item_recipe_gap_creator",

				"item_recipe_yuetufensuijvren",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",

				"item_zun_hat",
				"item_bird",
				"item_glue",
					"item_recipe_tsundere",

				"item_silver_knife",
				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
					"item_recipe_teeth",

				"item_recipe_wanbaochui2",

				"item_paper_mask",
				"item_cat_foot",
				"item_silver_knife",
					"item_recipe_ganggenier",

				"item_knife",
				"item_scissors",
					"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",
				"item_knife",
					"item_recipe_watermelon",
				"item_screw_driver",
					"item_recipe_cirno_claymore",
						"item_recipe_ertianyiliu",

			};


----------------------------------------------------------------------------------------------------

local seed_id = nil

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
