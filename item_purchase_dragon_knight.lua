
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
				
				"item_mushroom",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_jiaokeshu",
					"item_recipe_touhou_banana",
					"item_wind_amulet",
"item_recipe_horse_red",	
				"item_sailor_suit",
				"item_pant",
					"item_recipe_diary",
					
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
					
				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",
					
				"item_frog",
				"item_ice_block",
				"item_ice_block",
				"item_recipe_frozen",
				
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_green",
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_blue",
					"item_recipe_horse_king",

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
