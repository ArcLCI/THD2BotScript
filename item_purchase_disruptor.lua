
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {
	"item_broom",
	"item_third_eyes",
	"item_recipe_gap_creator",
	"item_wanbaochui",
	"item_zaiezhizhurenxing",
	"item_nuclear_stick",
	"item_bagua",
	"item_recipe_wanbaochui2",
	"item_pomojinlingli",
	"item_esdw",
	"item_recipe_trinity"
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

	if npcBot:FindItemSlot("item_loneliness") >=0 and npcBot:FindItemSlot("item_third_eyes") >=0 then
		npcBot:ActionImmediate_SellItem(npcBot:GetItemInSlot(npcBot:FindItemSlot("item_third_eyes")))
	end
end

----------------------------------------------------------------------------------------------------
