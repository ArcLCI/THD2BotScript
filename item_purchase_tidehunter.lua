require(GetScriptDirectory() .. "/thd2_item_purchase")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

-- 前排：先建立机动与生存，再用万宝槌强化雾化/鬼神，八辐法轮最终升级三位一体。
local frontlineItems = {
	"item_9ball",
	"item_phoenix_wing",
	"item_ice_block",
	"item_recipe_wanmeitiaoyuezhuangzhi",
	"item_wanbaochui2",
	"item_flower_umbrella",
	"item_dragon_star",
	"item_nuclear_stick",
	"item_loneliness",
	"item_esdw",
	"item_recipe_trinity",
	"item_horse_king",
	"item_gap_creator",
}

-- 输出：粉碎锤升级巨刃保留控制，双剑与三位一体成型后再完成牛逼跳跃。
local damageItems = {
	"item_9ball",
	"item_smash_stick",
	"item_ice_block",
	"item_recipe_wanmeitiaoyuezhuangzhi",
	"item_wanbaochui2",
	"item_dragon_star",
	"item_glutton_spork",
	"item_cirno_claymore",
	"item_pad",
	"item_recipe_yuetufensuijvren",
	"item_ganggenier",
	"item_sampan",
	"item_recipe_ertianyiliu",
	"item_recipe_trinity",
	"item_horse_king",
	"item_gap_creator",
}

local TRINITY_RECIPE_COST = 8400
local seed_id = nil
local next_purchase = -1

local function GetBuildProfile(bot)
	return BotProfile.GetProfileOrDefault(bot, BotProfile.FRONTLINE)
end

local function HasItem(bot, itemName)
	return bot:FindItemSlot(itemName) >= 0
end

local function SellItem(bot, itemName)
	local slot = bot:FindItemSlot(itemName)
	if slot < 0 then return false end
	local item = bot:GetItemInSlot(slot)
	if item == nil then return false end
	bot:ActionImmediate_SellItem(item)
	return true
end

local function TryMakeRoomForUpgrade(bot, profile)
	if profile == BotProfile.DAMAGE then return false end

	-- 八辐法轮和配方费都齐备后才出售火凤凰之翼，缩短前排生存真空期。
	if bot:GetGold() >= TRINITY_RECIPE_COST
	and HasItem(bot, "item_esdw")
	and SellItem(bot, "item_phoenix_wing")
	then
		return true
	end
	return false
end

function ItemPurchaseThink()
	if seed_id == nil then seed_id = RandomInt(1, 999999999) end

	local bot = GetBot()
	local profile = GetBuildProfile(bot)
	local itemsToBuy = profile == BotProfile.DAMAGE and damageItems or frontlineItems
	if TryMakeRoomForUpgrade(bot, profile) then return end

	local tableEdible = {
		"item_mushroom_pie_immediate",
		"item_mushroom_kebab_immediate",
		"item_mushroom_soup_immediate",
	}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(itemsToBuy) < next_purchase then
		table.insert(itemsToBuy, tableEdible[RandomInt(1, 3)])
	end
	next_purchase = ConsiderItemPurchase(itemsToBuy, seed_id)
end
