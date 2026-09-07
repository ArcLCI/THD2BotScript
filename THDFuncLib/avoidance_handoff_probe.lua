local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_research_config')
local Policy = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Probe = {}
-- 只由显式研究开关加载，保留历史手动卡位和重新选点能力。
function Probe.New(services)
local Now, Safe, Log = services.Now, services.Safe, services.Log
local SnapshotLocation = services.SnapshotLocation
local ResetHandoffFallbackProgress, StopHandoffFallback = services.ResetProgress, services.Stop
local BuildHandoffFallbackTarget = services.BuildTarget
local function RetargetStalledHandoffFallback(bot, state, current, now, heldFor)
	if (state.handoffFallbackActionCount or 0) < 2 then
		if state.handoffFallbackProgressAt == nil then
			ResetHandoffFallbackProgress(state, current, now)
		end
		return false
	end
	if state.handoffFallbackProgressLocation == nil or state.handoffFallbackProgressAt == nil then
		ResetHandoffFallbackProgress(state, current, now)
		return false
	end
	local displacement = Geometry.Distance(current, state.handoffFallbackProgressLocation)
	local progressDistance = math.max(0,
		tonumber(Policy.HANDOFF_FALLBACK_PROGRESS_DISTANCE) or 48)
	if displacement >= progressDistance then
		ResetHandoffFallbackProgress(state, current, now)
		return false
	end
	local stalledFor = math.max(0, now - state.handoffFallbackProgressAt)
	if stalledFor < (tonumber(Policy.HANDOFF_FALLBACK_STALL_TIME) or 1.5) then
		return false
	end
	-- 生产交接不再重新找目标；旧强制卡位流程只允许显式手动探针使用。
	if Config.HANDOFF_FALLBACK_STALL_PROBE ~= true then
		StopHandoffFallback(bot, state, 'no_progress')
		return false
	end
	local oldTarget = SnapshotLocation(state.handoffFallbackTarget)
	Log(bot, state, 'mode-handoff', 'fallback_stalled', string.format(
		'held_for=%.3f stalled_for=%.3f displacement=%.1f target_distance=%.1f fallback_action_count=%d fallback_retarget_count=%d',
		heldFor, stalledFor, displacement,
		oldTarget ~= nil and Geometry.Distance(current, oldTarget) or -1,
		state.handoffFallbackActionCount or 0, state.handoffFallbackRetargetCount or 0))
	local newTarget = BuildHandoffFallbackTarget(bot, nil, oldTarget)
	ResetHandoffFallbackProgress(state, current, now)
	if newTarget == nil then
		Log(bot, state, 'mode-handoff', 'fallback_unavailable',
			string.format('held_for=%.3f reason=stall_retarget', heldFor))
		return false
	end
	state.handoffFallbackTarget = newTarget
	state.handoffFallbackRetargetCount = (state.handoffFallbackRetargetCount or 0) + 1
	state.handoffFallbackUnavailableLogged = false
	Log(bot, state, 'mode-handoff', 'fallback_retarget', string.format(
		'held_for=%.3f fallback_retarget_count=%d old_target_x=%.1f old_target_y=%.1f target_x=%.1f target_y=%.1f',
		heldFor, state.handoffFallbackRetargetCount,
		oldTarget ~= nil and (oldTarget.x or 0) or 0,
		oldTarget ~= nil and (oldTarget.y or 0) or 0,
		newTarget.x or 0, newTarget.y or 0))
	return true
end

local function ExecuteHandoffFallbackStallProbe(bot, state, current, now, heldFor)
	if Config.HANDOFF_FALLBACK_STALL_PROBE ~= true
	or state.handoffFallbackStallProbeComplete == true
	or (state.handoffFallbackActionCount or 0) < 2
	then
		return false, false
	end
	if state.handoffFallbackStallProbeStartedAt == nil then
		state.handoffFallbackStallProbeStartedAt = now
		state.handoffFallbackStallProbeLastActionAt = -90
		ResetHandoffFallbackProgress(state, current, now)
		Log(bot, state, 'mode-handoff', 'fallback_stall_probe_started', string.format(
			'held_for=%.3f fallback_action_count=%d target_x=%.1f target_y=%.1f',
			heldFor, state.handoffFallbackActionCount or 0,
			state.handoffFallbackTarget ~= nil and (state.handoffFallbackTarget.x or 0) or 0,
			state.handoffFallbackTarget ~= nil and (state.handoffFallbackTarget.y or 0) or 0))
	end
	local probeHeldFor = math.max(0, now - state.handoffFallbackStallProbeStartedAt)
	local holdTime = math.max((tonumber(Policy.HANDOFF_FALLBACK_STALL_TIME) or 1.5) + 0.05,
		tonumber(Config.HANDOFF_FALLBACK_STALL_PROBE_HOLD_TIME) or 1.6)
	if probeHeldFor < holdTime then
		-- 仅在手动探针对局中把目标压回当前位置，制造可归因的真实无位移窗口。
		if type(bot.Action_MoveToLocation) == 'function'
		and now - (state.handoffFallbackStallProbeLastActionAt or -90) >= 0.20
		then
			state.handoffFallbackStallProbeLastActionAt = now
			bot:Action_MoveToLocation(current)
		end
		return true, false
	end
	local retargeted = RetargetStalledHandoffFallback(bot, state, current, now, heldFor)
	if retargeted then
		state.handoffFallbackStallProbeComplete = true
		Log(bot, state, 'mode-handoff', 'fallback_stall_probe_completed', string.format(
			'held_for=%.3f probe_held_for=%.3f fallback_retarget_count=%d',
			heldFor, probeHeldFor, state.handoffFallbackRetargetCount or 0))
		return false, true
	end
	state.handoffFallbackStallProbeStartedAt = now
	state.handoffFallbackStallProbeLastActionAt = -90
	ResetHandoffFallbackProgress(state, current, now)
	Log(bot, state, 'mode-handoff', 'fallback_stall_probe_restarted', string.format(
		'held_for=%.3f probe_held_for=%.3f', heldFor, probeHeldFor))
	return true, false
end

return {Execute = ExecuteHandoffFallbackStallProbe, Retarget = RetargetStalledHandoffFallback}
end
return Probe
