
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				-- "item_quelling_blade",
				-- "item_sailor_suit",
				-- "item_wind_amulet",
				-- "item_throwing_knive",
				-- "item_rocket_diagram",

				"item_violin",
				"item_rocket_diagram",
				"item_juice",
				"item_recipe_grudge_bow",
				"item_gran_grimoire",
				"item_recipe_nuetrident",

				"item_recipe_travel_boots",

				"item_bloodthirstiest",

				"item_violin",
				"item_knife",
				"item_wind_amulet",
				"item_quelling_blade",
				"item_screw_driver",
				"item_recipe_inaba_illusion_weapon",

				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
					"item_recipe_yuetufensuijvren",

				"item_tengu_fan",
				"item_ice_block",
					"item_recipe_laevateinn",
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
