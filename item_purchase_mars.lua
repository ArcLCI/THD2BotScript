
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_cherry_branch",
				"item_cherry_branch",
				"item_cherry_branch",

				"item_recipe_gap_creator",

				"item_gran_grimoire",

				"item_wing",
				"item_swimming_suit",
				"item_candle",
					"item_recipe_phoenix_wing",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_sailor_suit",
				"item_juice",
				"item_aunt_clothes",
					"item_recipe_ghost_balloon",
				"item_swimming_suit",
						"item_recipe_xuenvdeweijin",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

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

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
