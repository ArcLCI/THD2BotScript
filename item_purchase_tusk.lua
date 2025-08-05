
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
				"item_wind_lace",
					"item_recipe_9ball",
				"item_sailor_suit",
					"item_recipe_mystia_wings",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

				"item_bra",
				"item_baozi",
				"item_glue",
					"item_recipe_pad",
				"item_hammer",
				"item_throwing_knive",
				"item_cherry_leaf",
					"item_recipe_smash_stick",
					"item_recipe_yuetufensuijvren",

				"item_knife",
				"item_scissors",
				"item_recipe_quant",
				"item_wrench",
					"item_recipe_sampan",

				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_cat_foot",
					"item_recipe_brother_sharp",
				"item_ice_block",
					"item_recipe_wanmeitiaoyuezhuangzhi",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_frog",
				"item_ice_block",
				"item_ice_block",
				"item_recipe_frozen",
			}


----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	local randIndex = RandomInt(1,3)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(tableItemsToBuy) < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[2])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
