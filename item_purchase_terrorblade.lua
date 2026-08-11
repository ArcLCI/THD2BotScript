require(GetScriptDirectory() .. "/thd2_item_purchase")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

-- 橙固定走物理核心：保留小叶到二天一流卷轴可买，三位一体完成后再用相机替换乳牙。
local damageItems = {
	"item_horse_red",
	"item_autumn_leaves",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_teeth",
	"item_dragon_star",
	"item_wanbaochui2",
	"item_cirno_claymore",
	"item_sampan",
	"item_recipe_ertianyiliu",
	"item_ganggenier",
	"item_glutton_spork",
	"item_recipe_trinity",
	"item_camera",
}

local itemsByProfile = {
	[BotProfile.DAMAGE] = damageItems,
}

local seed_id = nil
local next_purchase = -1
local ERTIANYILIU_RECIPE_COST = 5000

local function GetBuildProfile(bot)
	local profile = BotProfile.GetProfileOrDefault(bot, BotProfile.DAMAGE)
	return itemsByProfile[profile] ~= nil and profile or BotProfile.DAMAGE
end

local function HasItem(bot, itemName)
	return bot:FindItemSlot(itemName) >= 0
end

local function TrySellOwnedItem(bot, itemName)
	local slot = bot:FindItemSlot(itemName)
	if slot < 0 then return false end

	local item = bot:GetItemInSlot(slot)
	if item ~= nil then
		bot:ActionImmediate_SellItem(item)
	end
	-- 找到待售物品后无论出售是否成功都停止本轮；物品仍在时下一轮自然重试。
	return true
end

local function TryMakeRoomForErTianYiLiu(bot)
	if bot:GetGold() < ERTIANYILIU_RECIPE_COST
	or not HasItem(bot, "item_cirno_claymore")
	or not HasItem(bot, "item_sampan")
	then
		return false
	end

	return TrySellOwnedItem(bot, "item_autumn_leaves")
end

local function TryMakeRoomForCamera(bot)
	if not HasItem(bot, "item_trinity") then return false end
	return TrySellOwnedItem(bot, "item_teeth")
end

function ItemPurchaseThink()
	if seed_id == nil then seed_id = RandomInt(1, 999999999) end

	local bot = GetBot()
	local profile = GetBuildProfile(bot)
	local itemsToBuy = itemsByProfile[profile] or damageItems

	-- 两次出售都是购买状态机的一部分：出售动作与后续卷轴/相机购买分属不同 Think。
	if TryMakeRoomForErTianYiLiu(bot) then return end
	if TryMakeRoomForCamera(bot) then return end

	next_purchase = ConsiderItemPurchase(itemsToBuy, seed_id)
end

----------------------------------------------------------------------------------------------------
