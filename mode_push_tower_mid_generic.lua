local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local Push = require( GetScriptDirectory()..'/THDFuncLib/aba_push')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
if bot.PushLaneDesire == nil then bot.PushLaneDesire = {0, 0, 0} end

function GetDesire()
	-- 撤退与高地授权统一交由共享入口即时审查，避免提前返回使授权无法刷新。
    bot.PushLaneDesire[LANE_MID] = Push.GetPushDesire(bot, LANE_MID)
    return bot.PushLaneDesire[LANE_MID]
end
function OnStart() Utils.NoteModeStart(bot, 'push_mid'); Push.OnStart(bot, LANE_MID) end
function Think() Push.PushThink(bot, LANE_MID) end
function OnEnd() Push.OnEnd(bot, LANE_MID) end

GetDesire = Actions.GuardDesire(bot,BOT_MODE_PUSH_TOWER_MID,GetDesire)

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('push_mid', GetDesire)
