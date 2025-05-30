
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
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	local randIndex = RandomInt(1,3)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase and npcBot:GetGold() > npcBot:GetBuybackCost() + 540 then
		table.insert(tableItemsToBuy,tableEdible[2])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
