local Tasks = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_task')
local ExecutionConfig = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local NativePushObserver = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/native_push_observer')
local NativeBuildingGuard = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/native_push_guard')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_candidate_debug')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local TeiBackstep = require(GetScriptDirectory()..'/THDFuncLib/heroes/tei/tei_backstep')
local TeiBurst = require(GetScriptDirectory()..'/THDFuncLib/heroes/tei/tei_burst')
local TeiEngagement = require(GetScriptDirectory()..'/THDFuncLib/heroes/tei/tei_engagement')
local Kasen = require(GetScriptDirectory()..'/THDFuncLib/heroes/kasen/kasen_state')
local Mokou = require(GetScriptDirectory()..'/THDFuncLib/heroes/mokou/mokou_state')
local Config = require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_config')
local Controller = require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_controller')
local Skill = require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/skill_avoidance')
local Probe
if Config.IsAnyProbeEnabled() then
	Probe = require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_native_probe')
end

local SourceObserver = Config.SOURCE_OBSERVATION_ENABLED and require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/skill_circle_observer') or nil
local bot = GetBot()
if bot ~= nil then
	print(string.format('[BOT][SkillAvoidance] run=%s team=%s player=%s event=loaded enabled=%d', tostring(Config.RUN_ID), tostring(bot:GetTeam()), tostring(bot:GetPlayerID()), Config.ENABLED and Config.SKILL_AVOIDANCE_ENABLED and 1 or 0))
end
if SourceObserver ~= nil then SourceObserver.OnLoaded(bot) end
if Probe ~= nil then Probe.OnModeLoaded(bot) end

local avoidanceEnabled = Config.IsModeOverrideEnabled() or (Config.ENABLED and Config.SKILL_AVOIDANCE_ENABLED) or Config.IsAnyProbeEnabled()
local isTei = bot ~= nil and bot:GetUnitName() == 'npc_dota_hero_gyrocopter'
if bot == nil or not bot:IsHero() or bot:IsIllusion() then return end

local pendingSource=nil
local function EvaluateDesire()
	pendingSource=nil
	local burstDesire=TeiBurst.GetDesire(bot)
	if burstDesire>BOT_MODE_DESIRE_NONE then pendingSource='tei_burst';return burstDesire end
	local engagementDesire=TeiEngagement.GetDesire(bot)
	if engagementDesire>BOT_MODE_DESIRE_NONE then pendingSource='tei_engagement';return engagementDesire end
	local mokouDesire = Mokou.GetDesire(bot)
	if mokouDesire > BOT_MODE_DESIRE_NONE then pendingSource='mokou';return mokouDesire end
	-- 华扇只为可立即执行的候选及已提交施法生命周期取得高优先级。
	local kasenDesire = Kasen.GetDesire(bot)
	if kasenDesire > BOT_MODE_DESIRE_NONE then pendingSource='kasen';return kasenDesire end
	-- 短转身任务须先于通用动作锁取得模式，否则Valve攻击会不断覆盖转身。
	local teiDesire = TeiBackstep.GetDesire(bot)
	if teiDesire > BOT_MODE_DESIRE_NONE then pendingSource='tei';return teiDesire end
	if bot:IsAlive() then
		local mode=bot:GetActiveMode()
		local active=Tasks.Active(bot,'evasive_maneuvers')
		local push=mode==BOT_MODE_PUSH_TOWER_TOP or mode==BOT_MODE_PUSH_TOWER_MID or mode==BOT_MODE_PUSH_TOWER_BOT
		-- 原生推进入口没有Lua Think可早退，用独立无动作守护保护已提交前摇/引导。
		if (push or (mode==BOT_MODE_EVASIVE_MANEUVERS and active and active.kind=='native_push_guard'))
		and Actions.Protected(bot,nil,true) then
			pendingSource='native_push_guard'
			-- 已提交生命周期使用极小独占余量，避免与原生紧急模式1.0平分后被换单。
			return BOT_MODE_DESIRE_ABSOLUTE+0.01
		end
	end
	local buildingStop=NativeBuildingGuard.StopDesire(bot)
	if buildingStop>0 then pendingSource='native_building_guard';return buildingStop end
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
	-- 对照基线不新建自定义塔区任务；已经提交的显式逃生仍完成原生命周期。
	if not Controller.IsActionLocked(bot) then return BOT_MODE_DESIRE_NONE end
	pendingSource='tower'
	return Controller.GetDesire(bot)
end

function GetDesire()
	NativePushObserver.Observe(bot)
	local score=EvaluateDesire()
	local active=Tasks.Active(bot,'evasive_maneuvers')
	local source=pendingSource or (active and active.kind)
	if score<=0 or source==nil then Tasks.Release(bot,'evasive_maneuvers','provider_released');return 0 end
	-- 路径、危险源和无进展预算仍由对应provider复核；路由层只交接候选所有权。
	local state=source=='tei_engagement' and bot.THD_TeiEngagement or source=='tei_burst' and bot.THD_TeiBurst or source=='mokou' and bot.THD_MokouAction or source=='kasen' and bot.THD_KasenAction or source=='skill' and bot.THD_SkillAvoidance or source=='tei' and bot.THD_TeiBackstep or bot.THD_AvoidanceControllerState or {}
	return Tasks.Offer(bot,'evasive_maneuvers',score,{kind=source,reason=source=='mokou' and state.reason or source,
		snapshot={generation=state.generation,phase=state.phase,location=state.location or state.target or state.recoveryTarget}})
end

function OnStart()
	Tasks.Start(bot,'evasive_maneuvers')
	if TeiBurst.IsActive(bot) then return end
	if TeiEngagement.IsActive(bot) then return end
	local task=Tasks.Active(bot,'evasive_maneuvers')
	if task and (task.kind=='native_push_guard' or task.kind=='native_building_guard') then return end
	if bot.THD_MokouAction ~= nil or Mokou.IsProtected(bot) then return end
	if Kasen.IsActive(bot) or Kasen.IsProtected(bot) then return end
	if TeiBackstep.IsActive(bot) or not avoidanceEnabled then return end
	if Probe ~= nil then Probe.OnStart(bot) end
	if not Skill.IsActive(bot) and Controller.IsActionLocked(bot) then Controller.OnStart(bot) end
end

function OnEnd()
	local task=Tasks.Active(bot,'evasive_maneuvers')
	Tasks.Release(bot,'evasive_maneuvers','mode_end')
	if TeiBurst.OnEnd(bot) then return end
	if TeiEngagement.OnEnd(bot) then return end
	if task and (task.kind=='native_push_guard' or task.kind=='native_building_guard') then return end
	if Mokou.OnEnd(bot) then return end
	if Kasen.OnEnd(bot) then return end
	if TeiBackstep.OnEnd(bot) or not avoidanceEnabled then return end
	if Probe ~= nil then Probe.OnEnd(bot) end
	Skill.OnEnd(bot)
	if Controller.IsActionLocked(bot) then Controller.OnEnd(bot) end
end

function Think()
	-- 不依赖任务候选刷新频率，已持有的爆发流程每次模式回调都推进。
	if TeiBurst.Update(bot) then return end
	if TeiEngagement.Update(bot) then return end
	if Mokou.IsProtected(bot) then Mokou.Think(bot); return end
	-- 即使任务候选已失效，也不能让规避移动覆盖正在引导或自锁的技能。
	if Kasen.IsProtected(bot) then Kasen.Update(bot); return end
	local task=Tasks.Commit(bot,'evasive_maneuvers')
	if task==nil then return end
	if task.kind=='native_push_guard' then return end
	if task.kind=='native_building_guard' then NativeBuildingGuard.Think(bot);return end
	if task.kind=='mokou' then Mokou.Think(bot);return end
	if task.kind=='kasen' then Kasen.Think(bot);return end
	if TeiBackstep.Think(bot) then return end
	if J.IsTeiActionProtected(bot) then return end
	if not avoidanceEnabled then return end
	-- 技能规避分支也必须保护探女已提交动作的前摇与确认。
	if bot.THD_SagumeActionUntil ~= nil and DotaTime() < bot.THD_SagumeActionUntil then
		local util = require(GetScriptDirectory()..'/THDFuncLib/heroes/sagume/sagume_util')
		if util.Update(bot) then return end
	end
	if task.kind=='probe' and Probe~=nil then Probe.Think(bot);return end
	if task.kind=='skill' then if Skill.IsActive(bot) then Skill.Think(bot) end;return end
	if task.kind=='tower' then Controller.Think(bot) end
end

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('evasive_maneuvers', GetDesire)
