local Tasks = require(GetScriptDirectory()..'/THDFuncLib/mode_task')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local TeiBackstep = require(GetScriptDirectory()..'/THDFuncLib/tei_backstep')
local Kasen = require(GetScriptDirectory()..'/THDFuncLib/kasen_state')
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
if not avoidanceEnabled and not isTei and not Kasen.IsHero(bot) then
	-- 默认关闭时不注册回调，避免仅因文件存在就覆盖 Valve 原生 EVASIVE_MANEUVERS。
	GetDesire = nil
	OnStart = nil
	OnEnd = nil
	Think = nil
	return
end

if bot == nil or not bot:IsHero() or bot:IsIllusion() then return end

local pendingSource=nil
local function EvaluateDesire()
	pendingSource=nil
	-- 华扇只为可立即执行的候选及已提交施法生命周期取得高优先级。
	local kasenDesire = Kasen.GetDesire(bot)
	if kasenDesire > BOT_MODE_DESIRE_NONE then pendingSource='kasen';return kasenDesire end
	-- 短转身任务须先于通用动作锁取得模式，否则Valve攻击会不断覆盖转身。
	local teiDesire = TeiBackstep.GetDesire(bot)
	if teiDesire > BOT_MODE_DESIRE_NONE then pendingSource='tei';return teiDesire end
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
	if probeDesire ~= nil and probeDesire > BOT_MODE_DESIRE_NONE then pendingSource='probe';CandidateDebug.Note('probe_desire'); return probeDesire end
	local desire = Skill.GetDesire(bot)
	if Skill.IsActive(bot) then
		pendingSource='skill'
		Controller.YieldToSkill(bot)
		return desire
	end
	pendingSource='tower'
	return Controller.GetDesire(bot)
end

function GetDesire()
	local score=EvaluateDesire()
	local active=Tasks.Active(bot,'evasive_maneuvers')
	local source=pendingSource or (active and active.kind)
	if score<=0 or source==nil then Tasks.Release(bot,'evasive_maneuvers','provider_released');return 0 end
	-- 路径、危险源和无进展预算仍由对应provider复核；路由层只交接候选所有权。
	local state=source=='kasen' and bot.THD_KasenAction or source=='skill' and bot.THD_SkillAvoidance or source=='tei' and bot.THD_TeiBackstep or bot.THD_AvoidanceControllerState or {}
	return Tasks.Offer(bot,'evasive_maneuvers',score,{kind=source,reason=source,
		snapshot={generation=state.generation,phase=state.phase,location=state.target or state.recoveryTarget}})
end

function OnStart()
	Tasks.Start(bot,'evasive_maneuvers')
	if Kasen.IsActive(bot) or Kasen.IsProtected(bot) then return end
	if TeiBackstep.IsActive(bot) or not avoidanceEnabled then return end
	if Probe ~= nil then Probe.OnStart(bot) end
	if not Skill.IsActive(bot) then Controller.OnStart(bot) end
end

function OnEnd()
	Tasks.Release(bot,'evasive_maneuvers','mode_end')
	if Kasen.OnEnd(bot) then return end
	if TeiBackstep.OnEnd(bot) or not avoidanceEnabled then return end
	if Probe ~= nil then Probe.OnEnd(bot) end
	Skill.OnEnd(bot)
	Controller.OnEnd(bot)
end

function Think()
	-- 即使任务候选已失效，也不能让规避移动覆盖正在引导或自锁的技能。
	if Kasen.IsProtected(bot) then Kasen.Update(bot); return end
	local task=Tasks.Commit(bot,'evasive_maneuvers')
	if task==nil then return end
	if task.kind=='kasen' then Kasen.Think(bot);return end
	if TeiBackstep.Think(bot) then return end
	if J.IsTeiActionProtected(bot) then return end
	if not avoidanceEnabled then return end
	-- 技能规避分支也必须保护探女已提交动作的前摇与确认。
	if bot.THD_SagumeActionUntil ~= nil and DotaTime() < bot.THD_SagumeActionUntil then
		local util = require(GetScriptDirectory()..'/THDFuncLib/sagume_util')
		if util.Update(bot) then return end
	end
	if task.kind=='probe' and Probe~=nil then Probe.Think(bot);return end
	if task.kind=='skill' then if Skill.IsActive(bot) then Skill.Think(bot) end;return end
	if task.kind=='tower' then Controller.Think(bot) end
end

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('evasive_maneuvers', GetDesire)
