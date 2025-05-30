
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_quelling_blade",

                "item_pant",
				"item_pant",
				"item_violin",
				"item_paper_mask",

				"item_recipe_gap_creator",

				"item_violin",
				"item_knife",
				"item_wind_amulet",
				"item_screw_driver",
				"item_recipe_inaba_illusion_weapon",

				"item_mushroom",
				"item_catnip",
					"item_recipe_mushroom_pie",
				"item_wind_lace",
				"item_sailor_suit",
					"item_recipe_mystia_wings",
				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_cat_foot",
					"item_recipe_brother_sharp",

				"item_tengu_fan",
				"item_tengu_fan",
					"item_recipe_camera",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

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
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase and npcBot:GetGold() > npcBot:GetBuybackCost() + 540 then
		table.insert(tableItemsToBuy,tableEdible[2])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
