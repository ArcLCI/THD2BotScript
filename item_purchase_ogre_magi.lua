
require(GetScriptDirectory() ..  "/thd2_item_purchase")

ItemSold = 0
local tableItemsToBuy = {
				"item_broom",
					"item_recipe_9ball",

				"item_swimming_suit",
				"item_cherry_leaf",
				"item_pant",
					"item_recipe_guilty_mask",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
						"item_recipe_third_eyes",

				"item_ice_block",
					"item_recipe_wanmeitiaoyuezhuangzhi",

				"item_baozi",
				"item_zun_hat",
				"item_pant",
					"item_recipe_qijizhixing",

				"item_wing",
				"item_swimming_suit",
				"item_candle",
					"item_recipe_phoenix_wing",

				"item_cherry_leaf",
				"item_pant",
				"item_hunting_cap",
					"item_recipe_zun_glasses",
					"item_recipe_tuzhushen",

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

				"item_frog",
				"item_juice",
				"item_magic_guide_book",
					"item_recipe_eyunzhifu",
				"item_gran_grimoire",
					"item_recipe_pomojinlingli",

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
	local npcBot = GetBot()
	ConsiderItemPurchase(tableItemsToBuy,seed_id)

	if npcBot:FindItemSlot("item_pomojinlingli") >=0 and ItemSold == 0 then
		local item_xinyan = IsItemAvailable( "item_third_eyes" )
		if item_xinyan~=nil and item_xinyan:IsFullyCastable() then
			npcBot:ActionImmediate_SellItem(npcBot:GetItemInSlot(npcBot:FindItemSlot("item_third_eyes")))
			ItemSold = 1
		end
	end
end

----------------------------------------------------------------------------------------------------
