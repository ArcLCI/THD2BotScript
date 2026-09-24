local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Defend = require( GetScriptDirectory()..'/THDFuncLib/aba_defend')

local bot = GetBot()
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end

function GetDesire()
	return Defend.GetDefendDesire(bot,LANE_TOP)
end
function OnStart() Utils.NoteModeStart(bot,'defend_top'); Defend.OnStart(bot,LANE_TOP) end
function OnEnd() Defend.OnEnd(bot,LANE_TOP) end
function Think() Defend.DefendThink(bot, LANE_TOP) end

GetDesire = Actions.GuardDesire(bot,BOT_MODE_DEFEND_TOWER_TOP,GetDesire)

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('defend_top', GetDesire)
