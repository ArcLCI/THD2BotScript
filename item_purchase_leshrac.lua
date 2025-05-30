
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_cherry_branch",
				"item_cherry_branch",
				"item_cherry_branch",
                "item_gran_grimoire",

				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_baozi",
				"item_sake",
				"item_zun_hat",
					"item_recipe_nuclear_stick",

                "item_horse_king_compressor",
				"item_recipe_horse_king",

				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_sailor_suit",
					"item_recipe_jiao_shou",
				"item_wing",
					"item_recipe_zaiezhizhurenxing",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

				"item_baozi",
				"item_sake",
				"item_ice_block",
					"item_recipe_hakurei_amulet",

			}

local tableEatSTR = {"item_mushroom","item_cherry_branch","item_recipe_mushroom_kebab"}


----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1
local first_buy = false
local last_buy = false

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	if first_buy and #tableItemsToBuy < NextEquipment(seed_id) then
		last_buy = true
		for _,item in pairs(tableEatSTR)
		do
			table.insert(tableItemsToBuy,item)
		end
	end
	ConsiderItemPurchase(tableItemsToBuy,seed_id)
	first_buy = true
end

function GetLastBuyStatus()
	return last_buy
end
----------------------------------------------------------------------------------------------------