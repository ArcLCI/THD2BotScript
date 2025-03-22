
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

					"item_recipe_gap_creator",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_sailor_suit",
				"item_juice",
				"item_aunt_clothes",
					"item_recipe_ghost_balloon",
				"item_swimming_suit",
						"item_recipe_xuenvdeweijin",

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

				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
					"item_cat_foot",
					"item_frog",
						"item_recipe_dummy_doll1",

				"item_wind_lace",
				"item_sailor_suit",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
					"item_recipe_mystia_wings",
				"item_ice_block",
					"item_recipe_bone_flute",

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
