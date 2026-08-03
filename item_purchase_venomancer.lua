require(GetScriptDirectory() .. "/thd2_item_purchase")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

-- 花阵前排：低价承伤与团队保护先成型，终局三位一体后再将完美跳跃升级为牛逼跳跃。
local frontlineItems = {
	"item_9ball",
	"item_phoenix_wing",
	"item_flower_umbrella",
	"item_dragon_star",
	"item_ice_block",
	"item_recipe_wanmeitiaoyuezhuangzhi",
	"item_nuclear_stick",
	"item_wanbaochui2",
	"item_loneliness",
	"item_esdw",
	"item_recipe_trinity",
	"item_horse_king",
	"item_gap_creator",
}

-- 输出核心：白楼剑与三位一体完成后，最后将完美跳跃升级为牛逼跳跃。
local damageItems = {
	"item_9ball",
	"item_watermelon",
	"item_flower_umbrella",
	"item_ice_block",
	"item_recipe_wanmeitiaoyuezhuangzhi",
	"item_screw_driver",
	"item_recipe_cirno_claymore",
	"item_dragon_star",
	"item_wanbaochui2",
	"item_laevateinn",
	"item_sampan",
	"item_recipe_ertianyiliu",
	"item_glutton_spork",
	"item_recipe_trinity",
	"item_horse_king",
	"item_gap_creator",
}

local seed_id = nil
local next_purchase = -1
local frontlineFinalizeSlot = nil

local function GetBuildProfile(bot)
	-- 标记缺失或非法时固定走前排路线，不能从技能等级反推定位。
	return BotProfile.GetProfileOrDefault(bot, BotProfile.FRONTLINE)
end

local function FindEmptyMainSlot(bot)
	for slot = 0, 5 do
		if bot:GetItemInSlot(slot) == nil then return slot end
	end
	return nil
end

local function TryFinalizeFrontlineInventory(bot)
	local trinitySlot = bot:FindItemSlot("item_trinity")
	if trinitySlot < 0 then return false end

	local dragonSlot = bot:FindItemSlot("item_dragon_star")
	if dragonSlot >= 0 then
		local dragonStar = bot:GetItemInSlot(dragonSlot)
		if dragonStar == nil then return true end
		frontlineFinalizeSlot = dragonSlot
		bot:ActionImmediate_SellItem(dragonStar)
		-- 出售失败时本轮停止，下一次购买 Think 会再次尝试。
		if bot:FindItemSlot("item_dragon_star") >= 0 then return true end
		trinitySlot = bot:FindItemSlot("item_trinity")
		if trinitySlot >= 6 then
			bot:ActionImmediate_SwapItems(trinitySlot, frontlineFinalizeSlot)
		end
		return true
	end

	if trinitySlot >= 6 then
		local destination = frontlineFinalizeSlot
		if destination == nil or destination < 0 or destination > 5
		or bot:GetItemInSlot(destination) ~= nil
		then
			destination = FindEmptyMainSlot(bot)
		end
		if destination ~= nil then
			bot:ActionImmediate_SwapItems(trinitySlot, destination)
			return true
		end
	end
	return false
end

local function GetPurchaseListWithOptionalEdible(itemsToBuy)
	if not (DotaTime() > 0 and next_purchase > 0
	and GetEquipmentMaxNum(itemsToBuy) < next_purchase)
	then
		return itemsToBuy
	end

	local result = {}
	for _, itemName in ipairs(itemsToBuy) do table.insert(result, itemName) end
	local edible = {
		"item_mushroom_pie_immediate",
		"item_mushroom_kebab_immediate",
		"item_mushroom_soup_immediate",
	}
	table.insert(result, edible[RandomInt(1, 3)])
	return result
end

function ItemPurchaseThink()
	if seed_id == nil then seed_id = RandomInt(1, 999999999) end

	local bot = GetBot()
	local profile = GetBuildProfile(bot)
	local itemsToBuy = profile == BotProfile.DAMAGE and damageItems or frontlineItems
	if profile == BotProfile.FRONTLINE and TryFinalizeFrontlineInventory(bot) then return end

	next_purchase = ConsiderItemPurchase(GetPurchaseListWithOptionalEdible(itemsToBuy), seed_id)
end

----------------------------------------------------------------------------------------------------
