
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
				
				"item_cherry_leaf",
				"item_pant",
				"item_hunting_cap",
					"item_recipe_zun_glasses",
				
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
				
				"item_gran_grimoire",
				"item_gran_grimoire",
				"item_recipe_bagua",
				
				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",
				
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
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[2])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
