
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
				"item_quelling_blade",
					"item_wind_amulet",
"item_recipe_horse_red",

                "item_pant",
				"item_pant",
				"item_violin",
				"item_paper_mask",
				
				"item_violin",
				"item_knife",
				"item_wind_amulet",
				"item_screw_driver",
				"item_recipe_inaba_illusion_weapon",
								
				"item_mushroom",
				"item_catnip",
					"item_recipe_mushroom_pie",
				"item_wind_lace",
				"item_sailor_suit",
					"item_recipe_mystia_wings",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_cat_foot",
					"item_recipe_brother_sharp",
						
				"item_tengu_fan",
				"item_tengu_fan",
					"item_recipe_camera",	
								
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
