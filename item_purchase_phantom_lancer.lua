
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_green",
				
				"item_tengu_fan",
				"item_tengu_fan",
					"item_recipe_camera",
				
				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
					"item_recipe_yuetufensuijvren",
				
				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					
				"item_bloodthirstiest",
				
					"item_recipe_wanbaochui2",
				
				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
					"item_recipe_ganggenier",
				
				"item_frog",
				"item_ice_block",
				"item_ice_block",
					"item_recipe_frozen",
				
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_blue",
					"item_recipe_horse_king",
				
				"item_tengu_fan",
				"item_ice_block",
					"item_recipe_laevateinn",
				
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
