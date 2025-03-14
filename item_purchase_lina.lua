
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
				"item_wind_amulet",
				"item_recipe_horse_red",
				
				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",
				
				"item_knife",
				"item_rocket_diagram",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
				
				"item_baozi",
				"item_sake",	
				"item_ice_block",
					"item_recipe_hakurei_amulet",

				"item_gran_grimoire",
				"item_gran_grimoire",
				"item_recipe_bagua",
				
				"item_cat_ear",
				"item_cherry_leaf",
				"item_sailor_suit",
				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
					"item_recipe_jiao_shou",
				"item_wing",
					"item_recipe_zaiezhizhurenxing",
				
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
