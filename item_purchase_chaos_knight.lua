require(GetScriptDirectory() .. '/thd2_item_purchase')

-- 持续输出：先完成叉勺续航，末期复用已有成品升级，始终只占六个最终装备位。
local damageItems = {
	'item_horse_red',
	'item_naginata', 'item_hoshiguma_cup',
	'item_dragon_star',
	'item_wanbaochui', -- 先有续航和驱散，再通过万宝槌缩短Q冷却。
	'item_yuetufensuijvren',
	'item_recipe_wanbaochui2', -- 复用已有万宝槌永久化，释放装备位，不重复购买成品。
	'item_autumn_leaves',
	'item_camera',
	'item_horse_king_compressor', 'item_recipe_horse_king',
	'item_recipe_trinity',
	'item_wanmeitiaoyuezhuangzhi', 'item_gap_creator',
}
local seedID

function ItemPurchaseThink()
	local bot = GetBot()
	if bot == nil or bot:IsIllusion() then return end
	if seedID == nil then seedID = RandomInt(1, 999999999) end
	ConsiderItemPurchase(damageItems, seedID)
end
