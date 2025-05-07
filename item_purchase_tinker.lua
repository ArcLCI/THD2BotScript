
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",

				"item_juice",
				"item_bird",
				"item_aunt_clothes",
				"item_sake",
				"item_sake",
					"item_recipe_yueyaomishi",
				"item_frog",
				"item_juice",
				"item_magic_guide_book",
					"item_recipe_eyunzhifu",
				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",
					"item_recipe_morenjingjuan",

				"item_recipe_gap_creator",

				"item_gran_grimoire",
				"item_gran_grimoire",
				"item_recipe_bagua",

				"item_tengu_fan",
				"item_tengu_fan",
					"item_recipe_camera",

				"item_baozi",
				"item_sake",
				"item_ice_block",
					"item_recipe_hakurei_amulet",


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
