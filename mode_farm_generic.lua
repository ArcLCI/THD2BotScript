local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')

local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

function GetDesire()
    if not bot:IsAlive() then CandidateDebug.Note('dead'); return BOT_MODE_DESIRE_NONE end
    CandidateDebug.Note('disabled_constant_zero')
    return BOT_MODE_DESIRE_NONE
end

function OnEnd()
end

function Think()
end

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('farm', GetDesire)
