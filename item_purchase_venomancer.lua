
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
			    "item_recipe_9ball",

				"item_bird",
		        "item_sailor_suit",
		    	"item_recipe_umbrella",
                "item_sailor_suit",
				"item_juice",
				"item_aunt_clothes",
					"item_recipe_ghost_balloon",
                "item_violin",
                    "item_recipe_flower_umbrella",

				"item_ice_block",
				"item_knife",
					"item_recipe_dragon_star",

                "item_ice_block",
			    "item_recipe_wanmeitiaoyuezhuangzhi",

				"item_bloodthirstiest",
				"item_tengu_fan",
				"item_ice_block",
					"item_recipe_laevateinn",

				"item_cat_foot",
		        "item_paper_mask",
		        "item_rocket_diagram",
		        "item_zun_hat",
		        	"item_recipe_wanbaochui",

				"item_knife",
				"item_recipe_watermelon",
				"item_screw_driver",
				"item_recipe_cirno_claymore",

                    "item_recipe_wanbaochui2",

                "item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_wrench",
				"item_recipe_sampan",

                "item_recipe_ertianyiliu",

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
