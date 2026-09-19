local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local TeiBackstep = require(GetScriptDirectory()..'/THDFuncLib/tei_backstep')
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Controller = require(GetScriptDirectory()..'/THDFuncLib/avoidance_controller')
local Skill = require(GetScriptDirectory()..'/THDFuncLib/skill_avoidance')
local Probe
if Config.IsAnyProbeEnabled() then
	Probe = require(GetScriptDirectory()..'/THDFuncLib/avoidance_native_probe')
end

local SourceObserver = Config.SOURCE_OBSERVATION_ENABLED and require(GetScriptDirectory()..'/THDFuncLib/skill_circle_observer') or nil
local bot = GetBot()
if bot ~= nil then
	print(string.format('[BOT][SkillAvoidance] run=%s team=%s player=%s event=loaded enabled=%d', tostring(Config.RUN_ID), tostring(bot:GetTeam()), tostring(bot:GetPlayerID()), Config.ENABLED and Config.SKILL_AVOIDANCE_ENABLED and 1 or 0))
end
if SourceObserver ~= nil then SourceObserver.OnLoaded(bot) end
if Probe ~= nil then Probe.OnModeLoaded(bot) end

local avoidanceEnabled = Config.IsModeOverrideEnabled() or (Config.ENABLED and Config.SKILL_AVOIDANCE_ENABLED) or Config.IsAnyProbeEnabled()
local isTei = bot ~= nil and bot:GetUnitName() == 'npc_dota_hero_gyrocopter'
if not avoidanceEnabled and not isTei then
	-- 默认关闭时不注册回调，避免仅因文件存在就覆盖 Valve 原生 EVASIVE_MANEUVERS。
	GetDesire = nil
	OnStart = nil
	OnEnd = nil
	Think = nil
	return
end

if bot == nil or not bot:IsHero() or bot:IsIllusion() then return end

function GetDesire()
	-- 短转身任务须先于通用动作锁取得模式，否则Valve攻击会不断覆盖转身。
	local teiDesire = TeiBackstep.GetDesire(bot)
	if teiDesire > BOT_MODE_DESIRE_NONE then return teiDesire end
	if J.IsTeiActionProtected(bot) then
		return bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE
	end
	-- 下单尚未进入原生施法状态时，GetDesire 也不能清除其动作。
	if bot.THD_SagumeActionUntil ~= nil and DotaTime() < bot.THD_SagumeActionUntil then
		return bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE
	end
	if not avoidanceEnabled then return BOT_MODE_DESIRE_NONE end
	if SourceObserver ~= nil then SourceObserver.Observe(bot) end
	local probeDesire = Probe ~= nil and Probe.GetDesire(bot) or nil
	if probeDesire ~= nil and probeDesire > BOT_MODE_DESIRE_NONE then CandidateDebug.Note('probe_desire'); return probeDesire end
	local desire = Skill.GetDesire(bot)
	if Skill.IsActive(bot) then
		Controller.YieldToSkill(bot)
		return desire
	end
	return Controller.GetDesire(bot)
end

function OnStart()
	if TeiBackstep.IsActive(bot) or not avoidanceEnabled then return end
	if Probe ~= nil then Probe.OnStart(bot) end
	if not Skill.IsActive(bot) then Controller.OnStart(bot) end
end

function OnEnd()
	if TeiBackstep.OnEnd(bot) or not avoidanceEnabled then return end
	if Probe ~= nil then Probe.OnEnd(bot) end
	Skill.OnEnd(bot)
	Controller.OnEnd(bot)
end

function Think()
	if TeiBackstep.Think(bot) then return end
	if J.IsTeiActionProtected(bot) then return end
	if not avoidanceEnabled then return end
	-- 技能规避分支也必须保护探女已提交动作的前摇与确认。
	if bot.THD_SagumeActionUntil ~= nil and DotaTime() < bot.THD_SagumeActionUntil then
		local util = require(GetScriptDirectory()..'/THDFuncLib/sagume_util')
		if util.Update(bot) then return end
	end
	if Probe ~= nil and Probe.Think(bot) then return end
	if Skill.IsActive(bot) then Skill.Think(bot);return end
	Controller.Think(bot)
end

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('evasive_maneuvers', GetDesire)
