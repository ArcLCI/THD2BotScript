require(GetScriptDirectory()..'/thd2_item_purchase')
local U = require(GetScriptDirectory()..'/THDFuncLib/sagume_util')
local Profile = require(GetScriptDirectory()..'/THDFuncLib/bot_profile')

local routes = {
	damage = {
		{buy={'item_nuetrident'}, result='item_nuetrident'},
		-- 输出路线提前买经卷前置，省去镜子的独立过渡投入。
		{buy={'item_eyunzhifu'}, result='item_eyunzhifu'},
		{buy={'item_wanbaochui'}, result='item_wanbaochui'},
		{buy={'item_tentacle'}, result='item_tentacle'},
		{buy={'item_recipe_morenjingjuan'}, result='item_morenjingjuan'},
		-- 已经由用户实战确认额外攻击触发法球，用月兔承担多目标输出格。
		{buy={'item_inaba_illusion_weapon'}, result='item_inaba_illusion_weapon'},
		-- 已持有格斗扫把时走压缩包配方，避免重新购买整套鞋。
		{buy={'item_horse_king_compressor','item_recipe_horse_king'}, result='item_horse_king'},
		-- 先取得必中与额外伤害，再投入三位一体的高价升级。
		{buy={'item_ganggenier'}, result='item_ganggenier'},
		-- 冈格尼尔完成后已有六件，先永久化万宝槌，再购买七星剑。
		{buy={'item_recipe_wanbaochui2'}, permanent=true},
		-- 三位一体有替代配方；复用七星剑，不展开默认的饕餮叉勺路线。
		{buy={'item_sss'}, result='item_sss'},
		{buy={'item_recipe_trinity'}, result='item_trinity'},
		-- 复用已经买到的炽热彗星，只补另两个前置，最终会自动合成。
		{buy={'item_wanmeitiaoyuezhuangzhi'}, result='item_wanmeitiaoyuezhuangzhi'},
		{buy={'item_gap_creator'}, result='item_nb9ball'},
	},
	support = {
		{buy={'item_hakurei_ticket'}, result='item_hakurei_ticket'},
		{buy={'item_tentacle'}, result='item_tentacle'},
		{buy={'item_green_dam'}, result='item_green_dam'},
		{buy={'item_yukkuri_stick'}, result='item_yukkuri_stick'},
		{buy={'item_eyunzhifu','item_recipe_morenjingjuan'}, result='item_morenjingjuan'},
		{buy={'item_wanbaochui2'}, permanent=true},
	},
}
local items={'item_horse_red'}
local seed,stage,waiting,nextIndex=nil,0,{result='item_horse_red'},nil

local function Assembled(bot,gate)
	if gate == nil then return true end
	if gate.permanent then
		if U.Item(bot,'item_wanbaochui2',true) then return false end
		return U.Safe(false,function()
			local index=bot:GetModifierByName('modifier_item_wanbaochui')
			return index>=0 and bot:GetModifierStackCount(index)==99
		end)
	end
	return U.Item(bot,gate.result,true)~=nil
end

function ItemPurchaseThink()
	local bot=GetBot()
	if bot==nil or bot:IsIllusion() then return end
	if seed==nil then seed=RandomInt(1,999999999) end
	local count=#GetFullPurchaseList(items)
	if nextIndex and nextIndex>count then
		-- 成功购买不等于合成/消耗成功，确认主包、背包、仓库与永久槌状态。
		if not Assembled(bot,waiting) then
			bot:SetNextItemPurchaseValue(0)
			U.Log(bot,'purchase_wait',{reason=waiting.permanent and 'permanent_scepter' or waiting.result},10)
			return
		end
		if not bot.THD_SagumePurchaseProfile then
			local profile=Profile.GetProfile(bot)
			bot.THD_SagumePurchaseProfile=routes[profile] and profile or 'damage'
			U.Log(bot,'profile_locked',{reason=profile or 'missing_marker_fallback'})
		end
		local entry=routes[bot.THD_SagumePurchaseProfile][stage+1]
		if not entry then
			-- 继续进入共享购买器，保留已有战术消耗品补货。
			waiting=nil
			ConsiderItemPurchase(items,seed)
			return
		end
		stage=stage+1
		waiting=entry
		for _,id in ipairs(entry.buy) do items[#items+1]=id end
	end
	local result=ConsiderItemPurchase(items,seed)
	if result and result>0 then nextIndex=result end
end
