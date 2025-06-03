
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_aunt_clothes",
				"item_aunt_clothes",
				"item_cat_ear",
				"item_cat_foot",
					"item_recipe_yuemianzhinu",

				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
					"item_paper_mask",
						"item_recipe_zuzhoumujian",
				"item_hammer",
						"item_recipe_feixiangjian",

				"item_throwing_knive",
				"item_huanyingzhifeng",
				"item_scissors",
					"item_recipe_autumn_leaves",

				"item_horse_king_compressor",
					"item_recipe_horse_king",

				"item_tengu_fan",
				"item_tengu_fan",
				"item_recipe_camera",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
				"item_cat_foot",
				"item_frog",
					"item_recipe_dummy_doll1",
			}


----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	local randIndex = RandomInt(1,2)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
