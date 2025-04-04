
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				--扫把+补刀斧转河童手枪
				"item_broom",
				"item_quelling_blade",

				"item_knife",
				"item_wind_amulet",

				"item_knife",
				"item_recipe_watermelon",
				"item_screw_driver",
				"item_recipe_cirno_claymore",

				--隙间鞋
					"item_recipe_gap_creator",

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

				--月兔幻觉兵器
				"item_violin",
				"item_screw_driver",
					"item_recipe_inaba_illusion_weapon",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

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
