
require(GetScriptDirectory() ..  "/thd2_item_purchase")

ItemSold = 0
local tableItemsToBuy = {
				"item_broom",

				"item_swimming_suit",
				"item_cherry_leaf",
				"item_pant",
					"item_recipe_guilty_mask",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
						"item_recipe_third_eyes",

					"item_recipe_gap_creator",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",

				"item_cat_ear",
				"item_cherry_leaf",
				"item_sailor_suit",
				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
					"item_recipe_jiao_shou",
				"item_wing",
					"item_recipe_zaiezhizhurenxing",

				"item_baozi",
				"item_sake",
				"item_zun_hat",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
				"item_mushroom",
				"item_cookbook",
					"item_recipe_mushroom_soup",
					"item_recipe_nuclear_stick",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

					"item_recipe_wanbaochui2",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

				"item_frog",
				"item_juice",
				"item_magic_guide_book",
					"item_recipe_eyunzhifu",
				"item_gran_grimoire",
					"item_recipe_pomojinlingli",

			};


----------------------------------------------------------------------------------------------------

local seed_id = nil

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	ConsiderItemPurchase(tableItemsToBuy,seed_id)

	if npcBot:FindItemSlot("item_loneliness") >=0 and ItemSold == 0 then
		npcBot:ActionImmediate_SellItem(npcBot:GetItemInSlot(npcBot:FindItemSlot("item_third_eyes")))
		ItemSold = 1
	end
end

----------------------------------------------------------------------------------------------------
