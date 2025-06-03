
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",
				"item_quelling_blade",

				"item_knife",
				"item_wind_amulet",

				"item_knife",
				"item_recipe_watermelon",
				"item_screw_driver",
				"item_recipe_cirno_claymore",

				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
					"item_recipe_quant",
					"item_recipe_anchor",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
					"item_recipe_ganggenier",

				"item_horse_king_compressor",
					"item_recipe_horse_king",

				--月兔幻觉兵器
				"item_violin",
				"item_screw_driver",
					"item_recipe_inaba_illusion_weapon",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

				"item_knife",
				"item_scissors",
					"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",
					"item_recipe_ertianyiliu",

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
