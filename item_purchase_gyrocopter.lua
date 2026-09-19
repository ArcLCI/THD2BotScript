require(GetScriptDirectory() .. '/thd2_item_purchase')

-- 单一物理核心：升级只追加缺件，保留雷云、血晶石和彗星直到合成。
local damageItems = {
	'item_horse_red',
	'item_bloodthirstiest',
	'item_leiyunzhiyuchuan',
	'item_dragon_star',
	'item_zuzhoumujian', 'item_recipe_feixiangjian',
	'item_camera',
	'item_horse_king_compressor', 'item_recipe_horse_king',
	'item_tengu_fan', 'item_ice_block', 'item_recipe_laevateinn',
	'item_frozen_frog',
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
