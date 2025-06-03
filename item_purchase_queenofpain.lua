
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_violin",
				"item_rocket_diagram",
				"item_juice",
				"item_recipe_grudge_bow",
				"item_gran_grimoire",
				"item_recipe_nuetrident",

				"item_recipe_gap_creator",

				"item_frog",
				"item_juice",
				"item_magic_guide_book",
					"item_recipe_eyunzhifu",
				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",
					"item_recipe_morenjingjuan",

				"item_gran_grimoire",
				"item_gran_grimoire",
				"item_recipe_bagua",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_baozi",
				"item_sake",
				"item_ice_block",
					"item_recipe_hakurei_amulet",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

			}


----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	local randIndex = RandomInt(2,3)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
