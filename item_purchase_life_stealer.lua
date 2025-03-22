
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_mushroom",
				"item_mushroom",
				"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_recipe_anchor",

				"item_recipe_gap_creator",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
				"item_recipe_ganggenier",

				"item_god_hand",
				"item_god_hand",
				"item_recipe_loneliness",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_sailor_suit",
				"item_juice",
				"item_aunt_clothes",
					"item_recipe_ghost_balloon",
				"item_swimming_suit",
						"item_recipe_xuenvdeweijin",

				"item_god_hand",
				"item_god_hand",
				"item_recipe_loneliness",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

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
