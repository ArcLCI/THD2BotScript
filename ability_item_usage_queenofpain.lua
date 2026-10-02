require(GetScriptDirectory()..'/thd2_item_usage')
local Sagume = require(GetScriptDirectory()..'/THDFuncLib/heroes/sagume/sagume_combat')

-- 技能、专属装备与中立装备共用一个动作入口，避免同轮互相覆盖。
function AbilityUsageThink()
	local bot = GetBot()
	if bot == nil then return end
	-- 独立调度也接入同帧去重的物品入口，保护窗口由共享模块复核。
	if ConsiderSharedResourceItems(bot) then return end
	Sagume.Think(bot)
end
