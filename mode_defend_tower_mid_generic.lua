local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Defend = require( GetScriptDirectory()..'/THDFuncLib/aba_defend')

local bot = GetBot()
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end
function GetDesire() return Patch741DesireChange(Defend.GetDefendDesire(bot, LANE_MID)) end
function OnEnd() Defend.OnEnd(bot, LANE_MID) end