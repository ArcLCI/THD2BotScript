
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
					
				"item_mushroom",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_jiaokeshu",
					"item_recipe_touhou_banana",

				"item_recipe_gap_creator",
				
				"item_knife",
				"item_scissors",
					"item_recipe_quant",
					"item_recipe_anchor",
					
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
						"item_recipe_yuetufensuijvren",
				
				"item_tengu_fan",
				"item_tengu_fan",
				"item_recipe_camera",
				
				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				
				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",
				
				"item_wind_amulet",
				"item_sailor_suit",
				"item_pant",
					"item_recipe_diary",
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
