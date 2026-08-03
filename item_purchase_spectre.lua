require(GetScriptDirectory() .. "/thd2_item_purchase")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

-- 输出先用船桨与血晶石取得暴击、吸血，再完成楼观剑和莱瓦汀以放大高基础攻击。
-- 普通万宝槌保留到六格后永久化；腾格后合成二天一流，饕餮叉勺最后原位升级三位一体。
local damageItems = {
	"item_horse_red",
	"item_quant",
	"item_bloodthirstiest",
	"item_dragon_star",
	"item_wanbaochui",
	"item_wrench",
	"item_recipe_sampan",
	"item_tengu_fan",
	"item_ice_block",
	"item_recipe_laevateinn",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_ganggenier",
	"item_recipe_wanbaochui2",
	"item_cirno_claymore",
	"item_recipe_ertianyiliu",
	"item_glutton_spork",
	"item_recipe_trinity",
}

-- 法术输出用格斗扫把补足前期机动，再完成七星剑与破魔净灵札；中期把扫把压成炽热彗星。
-- 七星剑本身可由最终配方原位升级三位一体，不再重复购买饕餮叉勺。
local spellDamageItems = {
	"item_horse_red",
	"item_cht",
	"item_naginata",
	"item_pomojinlingli",
	"item_nuclear_stick",
	"item_horse_king_compressor",
	"item_recipe_horse_king",
	"item_bagua",
	"item_yukkuri_stick",
	"item_recipe_trinity",
}

local seed_id = nil
local next_purchase = -1

local function GetBuildProfile(bot)
	local profile = BotProfile.GetProfile(bot)
	if profile ~= BotProfile.DAMAGE and profile ~= BotProfile.DAMAGE_SPELL then
		return BotProfile.DAMAGE
	end
	return profile
end

local function CopyList(source)
	local result = {}
	for _, itemName in ipairs(source) do
		table.insert(result, itemName)
	end
	return result
end

local function GetPurchaseListWithOptionalEdible(itemsToBuy)
	if not (DotaTime() > 0 and next_purchase > 0
	and GetEquipmentMaxNum(itemsToBuy) < next_purchase)
	then
		return itemsToBuy
	end

	-- 食物只追加到临时副本，双定位的标准路线保持不可变。
	local result = CopyList(itemsToBuy)
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

	local profile = GetBuildProfile(GetBot())
	local itemsToBuy = profile == BotProfile.DAMAGE_SPELL and spellDamageItems or damageItems
	next_purchase = ConsiderItemPurchase(GetPurchaseListWithOptionalEdible(itemsToBuy), seed_id)
end

----------------------------------------------------------------------------------------------------
