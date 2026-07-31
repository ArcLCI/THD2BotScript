local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Defend = require( GetScriptDirectory()..'/THDFuncLib/aba_defend')

local bot = GetBot()
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end

function GetDesire()
	if Defend.ShouldYieldToRetreat(bot) then return BOT_MODE_DESIRE_NONE end
	return Utils.GetCachedModeDesire(bot, 'defend_mid', function()
		return Defend.GetDefendDesire(bot, LANE_MID)
	end)
end
function OnStart() Utils.NoteModeStart(bot, 'defend_mid') end
function Think() Defend.DefendThink(bot, LANE_MID) end
