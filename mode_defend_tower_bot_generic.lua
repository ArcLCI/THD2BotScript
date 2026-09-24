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
	return Defend.GetDefendDesire(bot,LANE_BOT)
end
function OnStart() Utils.NoteModeStart(bot,'defend_bot'); Defend.OnStart(bot,LANE_BOT) end
function OnEnd() Defend.OnEnd(bot,LANE_BOT) end
function Think() Defend.DefendThink(bot, LANE_BOT) end

GetDesire = Actions.GuardDesire(bot,BOT_MODE_DEFEND_TOWER_BOT,GetDesire)

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('defend_bot', GetDesire)
