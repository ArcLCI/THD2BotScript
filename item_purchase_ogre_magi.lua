
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {
	"item_9ball",
	"item_third_eyes",
	"item_ice_block",
	"item_recipe_wanmeitiaoyuezhuangzhi",
	"item_qijizhixing",
	"item_phoenix_wing",
	"item_zun_glasses",
	"item_recipe_tuzhushen",
	"item_nuclear_stick",
	"item_pomojinlingli",
	"item_loneliness",
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
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(tableItemsToBuy) < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)

	if npcBot:FindItemSlot("item_pomojinlingli") >=0 and npcBot:FindItemSlot("item_third_eyes") >=0 then
		npcBot:ActionImmediate_SellItem(npcBot:GetItemInSlot(npcBot:FindItemSlot("item_third_eyes")))
	end
end

----------------------------------------------------------------------------------------------------
