
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
				
				"item_mushroom",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_jiaokeshu",
					"item_recipe_touhou_banana",
					"item_recipe_9ball",
				"item_sailor_suit",
				"item_pant",
					
				"item_bloodthirstiest",
					"item_recipe_diary",
				
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				
				"item_ice_block",
					"item_recipe_wanmeitiaoyuezhuangzhi",
				
				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",
				
				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
					"item_recipe_yuetufensuijvren",		
				
				"item_tengu_fan",
				"item_ice_block",
					"item_recipe_laevateinn",
				
				"item_tengu_fan",
				"item_tengu_fan",
				"item_recipe_camera",
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
