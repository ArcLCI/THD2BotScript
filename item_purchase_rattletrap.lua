require(GetScriptDirectory() .. "/thd2_item_purchase")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

local frontlineItems = {
	"item_broom",
	"item_third_eyes",
	"item_recipe_gap_creator",
	"item_phoenix_wing",
	"item_nuclear_stick",
	"item_wanbaochui2",
	"item_bagua",
	"item_loneliness",
}

local supportItems = {
	"item_broom",
	"item_third_eyes",
	"item_recipe_gap_creator",
	"item_tuzhushen",
	"item_yukkuri_stick",
	"item_flower_umbrella",
	"item_nuclear_stick",
	"item_wanbaochui2",
	"item_esdw",
	"item_recipe_trinity",
}

local seed_id = nil
local next_purchase = -1
local supportFinalizeSlot = nil

local function GetBuildProfile(bot)
	-- 标记缺失或等级非法时固定走前排路线，避免用技能等级反推定位。
	return BotProfile.GetProfileOrDefault(bot, BotProfile.FRONTLINE)
end

local function TryFinalizeSupportInventory(bot)
	local esdwSlot = bot:FindItemSlot("item_esdw")
	if esdwSlot < 0 then return false end

	local thirdEyesSlot = bot:FindItemSlot("item_third_eyes")
	if thirdEyesSlot >= 0 then
		local thirdEyes = bot:GetItemInSlot(thirdEyesSlot)
		if thirdEyes == nil then return true end
		supportFinalizeSlot = thirdEyesSlot
		bot:ActionImmediate_SellItem(thirdEyes)
		if bot:FindItemSlot("item_third_eyes") >= 0 then return true end
		local currentEsdwSlot = bot:FindItemSlot("item_esdw")
		if currentEsdwSlot >= 6 then
			bot:ActionImmediate_SwapItems(currentEsdwSlot, supportFinalizeSlot)
		end
		return true
	end

	if esdwSlot >= 6 then
		local destination = supportFinalizeSlot
		if destination == nil or destination < 0 or destination > 5 then
			for slot = 0, 5 do
				if bot:GetItemInSlot(slot) == nil then destination = slot break end
			end
		end
		if destination ~= nil then
			bot:ActionImmediate_SwapItems(esdwSlot, destination)
			return true
		end
	end
	return false
end

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1, 999999999)
	end

	local bot = GetBot()
	local profile = GetBuildProfile(bot)
	local itemsToBuy = profile == BotProfile.SUPPORT and supportItems or frontlineItems
	if profile == BotProfile.SUPPORT and TryFinalizeSupportInventory(bot) then return end

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
