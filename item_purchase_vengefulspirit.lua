
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
				"item_bird",
					"item_recipe_cishidaishouji",
					
				"item_bloodthirstiest",
				
				"item_violin",
				"item_knife",
				"item_wind_amulet",
				"item_quelling_blade",
				"item_screw_driver",
				"item_recipe_inaba_illusion_weapon",
				
				"item_tengu_fan",
				"item_tengu_fan",
					"item_recipe_camera",
					
				"item_frog",
				"item_ice_block",
				"item_ice_block",
					"item_recipe_frozen",
				
				"item_baozi",
				"item_sake",
				"item_ice_block",
					"item_recipe_hakurei_amulet",
				
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
