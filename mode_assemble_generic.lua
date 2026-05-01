local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')

local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

function GetDesire()
    if not bot:IsAlive() then return BOT_MODE_DESIRE_NONE end
    return BOT_MODE_DESIRE_NONE
end

function OnEnd()
end

function Think()
end