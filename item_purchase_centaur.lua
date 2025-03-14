
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
					"item_recipe_9ball",

				"item_mushroom",
				"item_mushroom",
				"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_recipe_anchor",

				"item_aunt_clothes",
				"item_aunt_clothes",
				"item_cat_ear",
				"item_cat_foot",
					"item_recipe_yuemianzhinu",
				"item_cake",
				"item_rocket_diagram",
					"item_recipe_hetongtuijinzhuangzhi",
					"item_recipe_yuemianjidongzhuangzhi",

				"item_ice_block",
					"item_recipe_wanmeitiaoyuezhuangzhi",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",

				"item_god_hand",
				"item_god_hand",
				"item_recipe_loneliness",

					"item_recipe_wanbaochui2",

				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
					"item_recipe_yuetufensuijvren",

				"item_huanyingzhifeng",
				"item_huanyingzhifeng",
					"item_recipe_UFO",

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
