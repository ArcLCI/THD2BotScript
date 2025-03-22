
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_knife",
				"item_rocket_diagram",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",

					"item_recipe_gap_creator",

				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
				"item_knife",
				"item_rocket_diagram",
					"item_recipe_moon_bow",

				"item_baozi",
				"item_sake",
				"item_ice_block",
					"item_recipe_hakurei_amulet",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

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
