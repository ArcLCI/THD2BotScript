require(GetScriptDirectory() .. "/thd2_item_purchase")

local tableItemsToBuy = {
	"item_horse_red",
	"item_wind_gun",
	"item_cirno_claymore",
	"item_anchor",
	"item_ganggenier",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_wanbaochui2",
	"item_camera",
	"item_sampan",
	"item_recipe_ertianyiliu",
	"item_trinity",
	"item_loneliness",
}

----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1, 999999999)
	end

	local randIndex = RandomInt(1, 3)
	local tableEdible = {
		"item_mushroom_pie_immediate",
		"item_mushroom_kebab_immediate",
		"item_mushroom_soup_immediate",
	}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(tableItemsToBuy) < next_purchase then
		table.insert(tableItemsToBuy, tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy, seed_id)

	-- 相机成装后，风枪已完成前期过渡职责，及时出售以释放装备位。
	local bot = GetBot()
	local windGunSlot = bot:FindItemSlot("item_wind_gun")
	local cameraSlot = bot:FindItemSlot("item_camera")
	if windGunSlot >= 0 and cameraSlot >= 0 then
		bot:ActionImmediate_SellItem(bot:GetItemInSlot(windGunSlot))
	end
end

----------------------------------------------------------------------------------------------------
