
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_mushroom",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_jiaokeshu",
					"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
					"item_recipe_quant",
					"item_recipe_anchor",

					"item_recipe_gap_creator",

				"item_bloodthirstiest",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
					"item_recipe_yuetufensuijvren",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_wind_amulet",
				"item_sailor_suit",
				"item_pant",
					"item_recipe_diary",

				"item_tengu_fan",
				"item_ice_block",
					"item_recipe_laevateinn",

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
