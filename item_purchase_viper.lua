
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",
				
				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",
				
				"item_wing",
				"item_swimming_suit",
				"item_candle",
				"item_recipe_phoenix_wing",
				
				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",
				
				"item_gran_grimoire",
				"item_gran_grimoire",
				"item_recipe_bagua",
				
				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
				"item_recipe_ganggenier",
				
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
