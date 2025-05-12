
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = { 
				"item_broom",
					"item_recipe_9ball",
				
				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
	
				"item_ice_block",
					"item_recipe_wanmeitiaoyuezhuangzhi",
				
				"item_cat_ear",
				"item_cherry_leaf",
				"item_sailor_suit",
				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
					"item_recipe_jiao_shou",
				"item_wing",
					"item_recipe_zaiezhizhurenxing",

				"item_aghanims_shard",
				
				"item_baozi",
				"item_sake",
				"item_zun_hat",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
					"item_recipe_nuclear_stick",
				
				"item_wind_lace",
				"item_sailor_suit",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
					"item_recipe_mystia_wings",
				"item_ice_block",
					"item_recipe_bone_flute",

				"item_recipe_wanbaochui2",
				
				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",
				
				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",
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
