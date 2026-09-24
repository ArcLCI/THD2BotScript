require(GetScriptDirectory() .. '/thd2_item_usage')
local J = require(GetScriptDirectory() .. '/THDFuncLib/thd_func')
local Kasen = require(GetScriptDirectory() .. '/THDFuncLib/kasen_state')

function AbilityUsageThink()
	local bot = GetBot()
	if not Kasen.IsHero(bot) then return end
	-- 先清理生命周期，再进入通用不可行动判断，避免自锁结束后残留任务。
	Kasen.Update(bot)
	-- 华扇内部独立调度紧急0.10秒/普通0.20秒，不能先被共享IsBotAwake挡住。
	if not bot:IsAlive() then return end
	local consumed, allowNeutral = Kasen.Consider(bot)
	if consumed or J.CanNotUseAction(bot) then return end
	if allowNeutral and ConsiderNeutralItems ~= nil then ConsiderNeutralItems() end
end
