
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_mushroom",
				"item_catnip",
				"item_recipe_mushroom_pie",
				"item_cat_ear",
				"item_wind_amulet",
				"item_screw_driver",

				"item_knife",
				"item_rocket_diagram",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",

					"item_recipe_travel_boots",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
					"item_recipe_ganggenier",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",

				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_wrench",
				"item_recipe_sampan",

				"item_recipe_wanbaochui2",

				"item_magic_guide_book",
				"item_gran_grimoire",
				"item_sake",
					"item_recipe_yukkuri_stick",

				"item_knife",
				"item_recipe_watermelon",
				"item_screw_driver",
				"item_recipe_cirno_claymore",
					"item_recipe_ertianyiliu",

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
