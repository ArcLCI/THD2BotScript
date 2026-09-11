require(GetScriptDirectory()..'/thd2_item_usage')
local Sagume = require(GetScriptDirectory()..'/THDFuncLib/sagume_combat')

-- 技能、专属装备与中立装备共用一个动作入口，避免同轮互相覆盖。
function AbilityUsageThink()
	local bot = GetBot()
	if bot == nil then return end
	Sagume.Think(bot)
end
