
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
					"item_recipe_horse_red",

				"item_juice",
				"item_bird",
				"item_aunt_clothes",
				"item_sake",
				"item_sake",
					"item_recipe_yueyaomishi",

				"item_swimming_suit",
				"item_cherry_leaf",
				"item_pant",
					"item_recipe_guilty_mask",
				"item_mushroom",
				"item_cherry_branch",
					"item_recipe_mushroom_kebab",
					"item_recipe_third_eyes",

				"item_horse_king_compressor",
					"item_recipe_horse_king",

				"item_gran_grimoire",
				"item_gran_grimoire",
				"item_recipe_bagua",

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
                
                "item_magic_guide_book",
				"item_gran_grimoire",
				"item_sake",
					"item_recipe_yukkuri_stick",

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
    local npcBot = GetBot()
	ConsiderItemPurchase(tableItemsToBuy,seed_id)

    if npcBot:FindItemSlot("item_nuclear_stick") >=0 and ItemSold == 0 then
		local item_xinyan = IsItemAvailable( "item_third_eyes" )
		if item_xinyan~=nil and item_xinyan:IsFullyCastable() then
			npcBot:ActionImmediate_SellItem(npcBot:GetItemInSlot(npcBot:FindItemSlot("item_third_eyes")))
			ItemSold = 1
		end
	end
end

----------------------------------------------------------------------------------------------------