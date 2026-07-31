local Retreat = require(GetScriptDirectory()..'/THDFuncLib/aba_retreat')

if not Retreat.IsEnabled() then
	-- 不注册同名回调，完整保留引擎内置的 Valve 撤退模式；nil 返回值并不代表回退。
	GetDesire = nil
	return
end

local bot = GetBot()
if bot == nil or not bot:IsHero() or bot:IsIllusion() then return end

function GetDesire()
	-- 撤退模式不能抢占传送、技能前摇或持续施法；这些生命周期由原控制逻辑完整保护。
	if not bot:IsAlive()
	or bot:HasModifier('modifier_teleporting')
	or bot:IsCastingAbility()
	or bot:IsUsingAbility()
	or bot:IsChanneling()
	then
		return BOT_MODE_DESIRE_NONE
	end

	return Retreat.GetDesire(bot) or BOT_MODE_DESIRE_NONE
end
