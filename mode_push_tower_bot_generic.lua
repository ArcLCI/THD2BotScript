local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local Push = require( GetScriptDirectory()..'/THDFuncLib/aba_push')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
if bot.PushLaneDesire == nil then bot.PushLaneDesire = {0, 0, 0} end

function GetDesire()
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then return BOT_MODE_DESIRE_NONE end
    return Utils.GetCachedModeDesire(bot, 'push_bot', function()
        bot.PushLaneDesire[LANE_BOT] = Push.GetPushDesire(bot, LANE_BOT)
        return bot.PushLaneDesire[LANE_BOT]
    end)
end
function OnStart() Utils.NoteModeStart(bot, 'push_bot') end
function Think() Push.PushThink(bot, LANE_BOT) end
