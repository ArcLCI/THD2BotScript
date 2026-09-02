local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Controller = require(GetScriptDirectory()..'/THDFuncLib/avoidance_controller')
local Probe = require(GetScriptDirectory()..'/THDFuncLib/avoidance_native_probe')

local bot = GetBot()
Probe.OnModeLoaded(bot)

if not Config.IsModeOverrideEnabled() and not Config.IsAnyProbeEnabled() then
	-- 默认关闭时不注册回调，避免仅因文件存在就覆盖 Valve 原生 EVASIVE_MANEUVERS。
	GetDesire = nil
	OnStart = nil
	OnEnd = nil
	Think = nil
	return
end

if bot == nil or not bot:IsHero() or bot:IsIllusion() then return end

function GetDesire()
	local probeDesire = Probe.GetDesire(bot)
	if probeDesire ~= nil and probeDesire > BOT_MODE_DESIRE_NONE then CandidateDebug.Note('probe_desire'); return probeDesire end
	return Controller.GetDesire(bot)
end

function OnStart()
	Probe.OnStart(bot)
	Controller.OnStart(bot)
end

function OnEnd()
	Probe.OnEnd(bot)
	Controller.OnEnd(bot)
end

function Think()
	if Probe.Think(bot) then return end
	Controller.Think(bot)
end

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('evasive_maneuvers', GetDesire)
