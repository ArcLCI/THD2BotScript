
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

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",

								"item_recipe_gap_creator",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

				"item_magic_guide_book",
				"item_gran_grimoire",
				"item_sake",
					"item_recipe_yukkuri_stick",

				"item_recipe_wanbaochui2",

				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_baozi",
				"item_sake",
					"item_recipe_picnic_basket",
				"item_zun_hat",
						"item_recipe_nuclear_stick",

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
