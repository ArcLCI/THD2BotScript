
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_swimming_suit",
				"item_cherry_leaf",
				"item_pant",
					"item_recipe_guilty_mask",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
						"item_recipe_third_eyes",

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

				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
				"item_wind_lace",
				"item_sailor_suit",
					"item_recipe_mystia_wings",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_cat_foot",
					"item_recipe_brother_sharp",

				"item_cat_ear",
				"item_cherry_leaf",
				"item_sailor_suit",
				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
					"item_recipe_jiao_shou",
				"item_wing",
					"item_recipe_zaiezhizhurenxing",

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
