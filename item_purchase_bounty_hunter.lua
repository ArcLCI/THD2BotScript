require(GetScriptDirectory() .. "/thd2_item_purchase")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

-- 狼群前排：花伞强化狼群与队伍，优先完成炽热彗星接近目标，八辐法轮最终升级三位一体。
local frontlineItems = {
	"item_horse_red",
	"item_flower_umbrella",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_dragon_star",
	"item_wanbaochui2",
	"item_loneliness",
	"item_tsundere",
	"item_esdw",
	"item_recipe_trinity",
}

-- 物理核心：白楼剑与相机先建立单体输出，冈格尼尔补全伤增幅和必中，再合成二天一流扩大强势期。
local carryItems = {
	"item_horse_red",
	"item_autumn_leaves",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_cirno_claymore",
	"item_camera",
	"item_ganggenier",
	"item_sampan", -- 楼观剑，不是念缚灵的船钩。
	"item_recipe_ertianyiliu",
	"item_dragon_star",
	"item_wanbaochui2",
	"item_glutton_spork",
	"item_recipe_trinity",
}

local seed_id = nil
local next_purchase = -1
local ERTIANYILIU_RECIPE_COST = 5000

local function GetBuildProfile(bot)
	local profile = BotProfile.GetProfile(bot)
	if profile ~= nil then return profile end

	-- 新物理加点与前排加点会出现相同技能等级组合；标记尚未同步时采用默认前排路线。
	return BotProfile.FRONTLINE
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
	if profile == BotProfile.FRONTLINE then
		return false
	end

	-- 楼观剑进入背包后继续保留小叶打钱，攒够二天一流配方费才出售，缩短输出真空期。
	if bot:GetGold() >= ERTIANYILIU_RECIPE_COST
	and HasItem(bot, "item_cirno_claymore")
	and HasItem(bot, "item_sampan")
	and SellItem(bot, "item_autumn_leaves")
	then
		return true
	end
	return false
end

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1, 999999999)
	end

	local bot = GetBot()
	local profile = GetBuildProfile(bot)
	local itemsToBuy = profile == BotProfile.DAMAGE and carryItems or frontlineItems
	-- 先释放装备位，下一次购买 Think 再买配方并立即合成二天一流。
	if TryMakeRoomForUpgrade(bot, profile) then return end

	local randIndex = RandomInt(1, 3)
	local tableEdible = {
		"item_mushroom_pie_immediate",
		"item_mushroom_kebab_immediate",
		"item_mushroom_soup_immediate",
	}
	if DotaTime() > 0 and next_purchase > 0 and GetEquipmentMaxNum(itemsToBuy) < next_purchase then
		table.insert(itemsToBuy, tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(itemsToBuy, seed_id)
end

----------------------------------------------------------------------------------------------------
