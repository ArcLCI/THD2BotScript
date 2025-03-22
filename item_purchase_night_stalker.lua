
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",

				"item_recipe_gap_creator",

				"item_wind_lace",
				"item_sailor_suit",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
					"item_recipe_mystia_wings",
				"item_ice_block",
					"item_recipe_bone_flute",

				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
					"item_paper_mask",
						"item_recipe_zuzhoumujian",
				"item_hammer",
						"item_recipe_feixiangjian",

				"item_scissors",
				"item_sailor_suit",
					"item_recipe_frock",


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
