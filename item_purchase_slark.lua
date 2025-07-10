
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {}

if RandomInt(1,100) > 50 then
	tableItemsToBuy = {
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",

				"item_knife",
					"item_recipe_watermelon",
				"item_screw_driver",
					"item_recipe_cirno_claymore",

				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
					"item_recipe_yuetufensuijvren",

				"item_knife",
				"item_ice_block",
					"item_recipe_dragon_star",

				"item_aghanims_shard",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
				"item_recipe_ganggenier",

				"item_knife",
				"item_scissors",
					"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",

				"item_tengu_fan",
				"item_tengu_fan",
				"item_recipe_camera",

				"item_recipe_ertianyiliu",

				"item_god_hand",
				"item_god_hand",
				"item_recipe_loneliness",
			}
else
	tableItemsToBuy = {
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",

				"item_juice",
				"item_bird",
				"item_aunt_clothes",
				"item_sake",
				"item_sake",
					"item_recipe_yueyaomishi",

				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_baozi",
				"item_sake",
				"item_zun_hat",
					"item_recipe_nuclear_stick",

				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
					"item_recipe_yuetufensuijvren",

				"item_knife",
				"item_ice_block",
					"item_recipe_dragon_star",

				"item_aghanims_shard",

                "item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",

				"item_gran_grimoire",
                "item_gran_grimoire",
                "item_recipe_bagua",

                "item_recipe_wanbaochui2",

				"item_god_hand",
				"item_god_hand",
				"item_recipe_loneliness",
			}
end

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
