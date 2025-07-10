
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_mushroom",
				"item_mushroom",
				"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_recipe_anchor",

				"item_ice_block",
				"item_knife",
					"item_recipe_dragon_star",

				"item_paper_mask",
				"item_cat_foot",
				"item_silver_knife",
				"item_recipe_ganggenier",

				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
					"item_recipe_yuetufensuijvren",

				"item_horse_king_compressor",
				"item_recipe_horse_king",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_tengu_fan",
				"item_tengu_fan",
				"item_recipe_camera",
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
