
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {}
if RandomInt(1,100) == 1 then
	tableItemsToBuy ={
		"item_9ball",
		"item_anchor",
		"item_yuemianjidongzhuangzhi",
		"item_ice_block",
		"item_recipe_wanmeitiaoyuezhuangzhi",
		"item_wanbaochui",
		"item_loneliness",
		"item_wanbaochui2",
		"item_yuetufensuijvren",
		"item_UFO"

	}
else
	tableItemsToBuy ={
		"item_9ball",
		"item_tentacle",
		"item_dummy_doll1",
		"item_cishidaishouji",
		"item_ice_block",
		"item_recipe_wanmeitiaoyuezhuangzhi",
		"item_smash_stick",
		"item_eyunzhifu",
		"item_recipe_morenjingjuan",
		"item_pad",
		"item_recipe_yuetufensuijvren",
		"item_wanbaochui2",
		"item_loneliness"
	}
end

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
