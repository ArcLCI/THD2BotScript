
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_quelling_blade",
				"item_knife",
				"item_wind_amulet",

				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",

				"item_pant",
				"item_pant",
				"item_violin",
				"item_paper_mask",

				"item_frog",
				"item_juice",
				"item_magic_guide_book",
					"item_recipe_eyunzhifu",
					"item_recipe_morenjingjuan",

				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
				"item_cat_foot",
				"item_frog",
					"item_recipe_dummy_doll1",

				"item_violin",
				"item_screw_driver",
					"item_recipe_inaba_illusion_weapon",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_horse_king_compressor",
				"item_recipe_horse_king",

				"item_huanyingzhifeng",
				"item_huanyingzhifeng",
					"item_recipe_UFO",
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
