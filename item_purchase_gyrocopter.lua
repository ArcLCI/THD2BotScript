require(GetScriptDirectory() .. '/thd2_item_purchase')

-- 单一物理核心：白楼剑后续补楼观剑合二天，乳牙保留为双增益后的爆发装备。
local damageItems = {
	'item_horse_red',
	'item_bloodthirstiest',
	'item_cirno_claymore',
	'item_dragon_star',
	'item_teeth',
	'item_horse_king_compressor', 'item_recipe_horse_king',
	-- 复用现有白楼剑，不重复展开购买二天一流成品。
	'item_sampan', 'item_recipe_ertianyiliu',
	'item_tengu_fan', 'item_ice_block', 'item_recipe_laevateinn',
	'item_glutton_spork', 'item_recipe_trinity',
	-- 最后用完美跳跃装置和间隙发生器升级现有彗星，不再重复购买彗星。
	'item_wanmeitiaoyuezhuangzhi', 'item_gap_creator',
}
local seedID

function ItemPurchaseThink()
	local bot = GetBot()
	if bot == nil or bot:IsIllusion() then return end
	if seedID == nil then seedID = RandomInt(1, 999999999) end
	ConsiderItemPurchase(damageItems, seedID)
end
