
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {
				"item_broom",

				"item_candle",
				"item_mushroom",
				"item_mushroom",
				"item_recipe_peach",

					"item_recipe_gap_creator",

				"item_mushroom",
				"item_mushroom",
				"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_recipe_anchor",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
				"item_recipe_ganggenier",

				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
					"item_recipe_yuetufensuijvren",

				"item_god_hand",
				"item_god_hand",
				"item_recipe_loneliness",

				"item_frog",
				"item_ice_block",
				"item_ice_block",
				"item_recipe_frozen",

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
