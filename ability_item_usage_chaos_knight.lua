require(GetScriptDirectory() .. '/thd2_item_usage')
local Mokou = require(GetScriptDirectory() .. '/THDFuncLib/heroes/mokou/mokou_state')

function AbilityUsageThink()
	local bot = GetBot()
	-- 先维护已提交动作；变蛋/位移期间不让物品入口覆盖命令。
	local state = Mokou.Update(bot)
	if Mokou.IsProtected(bot) then return end
	-- 致命命中窗口独立于普通技能0.25秒调度，只在可自伤致死时启用短周期观察。
	if Mokou.PrepareImminent(bot) then return end
	if state ~= nil then return end
	if not IsBotAwake(bot) then return end
	if Mokou.Prepare(bot) then return end
	ConsiderNeutralItems()
end
