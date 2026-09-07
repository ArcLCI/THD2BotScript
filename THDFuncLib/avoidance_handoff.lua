local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Handoff = {}

-- 生产交接只有冻结目标和有界续发；日志、时钟与动作保护由控制器显式传入。
function Handoff.New(services)
local Now, Safe, Log = services.Now, services.Safe, services.Log
local IsProtectedAction = services.IsProtectedAction
local Probe
local function ResetModeHandoff(state)
	state.handoffPending = false
	state.handoffModeEnded = false
	state.handoffStartedAt = nil
	state.handoffReleaseReason = nil
	state.handoffStaleLogged = false
	state.handoffFallbackAllowed = false
	state.handoffFallbackTarget = nil
	state.handoffFallbackLastActionAt = -90
	state.handoffFallbackActionCount = 0
	state.handoffFallbackUnavailableLogged = false
	state.handoffFallbackProgressLocation = nil
	state.handoffFallbackProgressAt = nil
	state.handoffFallbackRetargetCount = 0
	state.handoffFallbackStallProbeStartedAt = nil
	state.handoffFallbackStallProbeLastActionAt = -90
	state.handoffFallbackStallProbeComplete = false
	state.handoffFallbackTravel = 0
	state.handoffFallbackLastLocation = nil
end

local function SnapshotLocation(location)
	if location == nil then return nil end
	return Geometry.MakeVector(tonumber(location.x) or 0, tonumber(location.y) or 0,
		tonumber(location.z) or 0)
end

local function IsHandoffFallbackCandidate(candidate, rejectedTarget)
	if candidate == nil then return false end
	local rejectDistance = math.max(0,
		tonumber(Config.HANDOFF_FALLBACK_RETARGET_MIN_DISTANCE) or 240)
	if rejectedTarget ~= nil
	and Geometry.Distance(candidate, rejectedTarget) < rejectDistance
	then
		return false
	end
	return type(IsLocationPassable) ~= 'function'
		or Safe(false, function() return IsLocationPassable(candidate) end)
end

local function BuildHandoffFallbackTarget(bot, preferredLocation, rejectedTarget, zones)
	local current = Safe(nil, function() return bot:GetLocation() end)
	if current == nil then return nil end
	local reachDistance = math.max(0, tonumber(Config.HANDOFF_FALLBACK_REACH_DISTANCE) or 180)
	local maxDistance = math.max(reachDistance + 1, tonumber(Config.HANDOFF_FALLBACK_STEP_DISTANCE) or 900)
	local function Accept(candidate)
		return Geometry.Distance(current, candidate) <= maxDistance + 0.1
			and IsHandoffFallbackCandidate(candidate, rejectedTarget)
			and Geometry.ValidateMovementSegment(current, candidate, zones or {}, 64)
	end
	if preferredLocation ~= nil and Geometry.Distance(current, preferredLocation) > maxDistance then
		local scale = maxDistance / Geometry.Distance(current, preferredLocation)
		preferredLocation = Geometry.MakeVector(current.x + (preferredLocation.x - current.x) * scale,
			current.y + (preferredLocation.y - current.y) * scale, current.z)
	end
	if preferredLocation ~= nil
	and Geometry.Distance(current, preferredLocation) > reachDistance
	and Accept(preferredLocation)
	then
		return SnapshotLocation(preferredLocation)
	end
	local ancient = Safe(nil, function() return GetAncient(bot:GetTeam()) end)
	local ancientLocation = ancient ~= nil
		and Safe(nil, function() return ancient:GetLocation() end) or nil
	if ancientLocation == nil then return nil end
	local dx = (ancientLocation.x or 0) - (current.x or 0)
	local dy = (ancientLocation.y or 0) - (current.y or 0)
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= reachDistance then return nil end
	local directionX, directionY = dx / length, dy / length
	local sideX, sideY = -directionY, directionX
	local stepDistance = math.min(length,
		math.max(reachDistance + 1, tonumber(Config.HANDOFF_FALLBACK_STEP_DISTANCE) or 900))
	for _, scale in ipairs({1.0, 0.75, 0.50}) do
		for _, sideOffset in ipairs({0, 160, -160, 320, -320}) do
			local candidate = Geometry.MakeVector(
				(current.x or 0) + directionX * stepDistance * scale + sideX * sideOffset,
				(current.y or 0) + directionY * stepDistance * scale + sideY * sideOffset,
				current.z or ancientLocation.z or 0)
			if Accept(candidate) then
				return candidate
			end
		end
	end
	return nil
end

local function ResetHandoffFallbackProgress(state, current, now)
	state.handoffFallbackProgressLocation = SnapshotLocation(current)
	state.handoffFallbackProgressAt = now
end

local function StopHandoffFallback(bot, state, reason)
	if state.handoffFallbackAllowed ~= true then return end
	state.handoffFallbackAllowed = false
	state.handoffFallbackTarget = nil
	Log(bot, state, 'mode-handoff', 'fallback_stopped', string.format(
		'reason=%s held_for=%.3f travel=%.1f fallback_action_count=%d', tostring(reason),
		math.max(0, Now() - (state.handoffStartedAt or Now())),
		state.handoffFallbackTravel or 0, state.handoffFallbackActionCount or 0))
end

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
		tonumber(Config.HANDOFF_FALLBACK_PROGRESS_DISTANCE) or 48)
	if displacement >= progressDistance then
		ResetHandoffFallbackProgress(state, current, now)
		return false
	end
	local stalledFor = math.max(0, now - state.handoffFallbackProgressAt)
	if stalledFor < (tonumber(Config.HANDOFF_FALLBACK_STALL_TIME) or 1.5) then
		return false
	end
	StopHandoffFallback(bot, state, 'no_progress')
	return false
end

local function ObserveModeHandoff(bot, state)
	if state.handoffPending ~= true or state.handoffStartedAt == nil then return end
	local now = Now()
	local heldFor = math.max(0, now - state.handoffStartedAt)
	local activeMode = Safe(BOT_MODE_NONE, function() return bot:GetActiveMode() end)
	local activeDesire = tonumber(Safe(0, function() return bot:GetActiveModeDesire() end)) or 0
	local stillEvasive = BOT_MODE_EVASIVE_MANEUVERS ~= nil
		and activeMode == BOT_MODE_EVASIVE_MANEUVERS
	-- 活动模式已经切离即可证明交接完成；部分实机切换不会回调本模式 OnEnd。
	if not stillEvasive then
		StopHandoffFallback(bot, state, 'mode_changed')
		Log(bot, state, 'mode-handoff', 'completed',
			string.format('held_for=%.3f release_reason=%s next_mode=%s next_desire=%.3f mode_end_seen=%d fallback_action_count=%d fallback_retarget_count=%d',
				heldFor, tostring(state.handoffReleaseReason), tostring(activeMode), activeDesire,
				state.handoffModeEnded == true and 1 or 0,
				state.handoffFallbackActionCount or 0,
				state.handoffFallbackRetargetCount or 0))
		ResetModeHandoff(state)
		return
	end
	if state.handoffStaleLogged ~= true
	and heldFor >= (tonumber(Config.MODE_HANDOFF_STALE_TIME) or 1.0)
	then
		state.handoffStaleLogged = true
		Log(bot, state, 'mode-handoff', 'stale',
			string.format('held_for=%.3f release_reason=%s active_mode=%s active_desire=%.3f mode_end_seen=%d fallback_allowed=%d',
				heldFor, tostring(state.handoffReleaseReason), tostring(activeMode), activeDesire,
				state.handoffModeEnded == true and 1 or 0,
				state.handoffFallbackAllowed == true and 1 or 0))
	end
end

local function ExecuteModeHandoffFallback(bot, state)
	if Config.HANDOFF_FALLBACK_ENABLED ~= true
	or state.handoffPending ~= true
	or state.handoffFallbackAllowed ~= true
	or state.handoffStartedAt == nil
	then
		return false
	end
	local now = Now()
	local heldFor = math.max(0, now - state.handoffStartedAt)
	if heldFor >= (tonumber(Config.HANDOFF_FALLBACK_MAX_TIME) or 4.0) then
		StopHandoffFallback(bot, state, 'time_budget')
		return false
	end
	if heldFor < (tonumber(Config.HANDOFF_FALLBACK_START_TIME) or 1.0) then return false end
	local activeMode = Safe(BOT_MODE_NONE, function() return bot:GetActiveMode() end)
	local activeDesire = tonumber(Safe(0, function() return bot:GetActiveModeDesire() end)) or 0
	if BOT_MODE_EVASIVE_MANEUVERS == nil
	or activeMode ~= BOT_MODE_EVASIVE_MANEUVERS
	or activeDesire > BOT_MODE_DESIRE_NONE
	then
		StopHandoffFallback(bot, state, 'active_task')
		return false
	end
	-- 只填补无动作窗口，不覆盖已经开始的施法、TP、持续施法或攻击。
	if IsProtectedAction(bot)
	or Safe(0, function() return bot:NumQueuedActions() end) > 0 then
		StopHandoffFallback(bot, state, 'protected_or_attacking')
		state.handoffFallbackProgressLocation = nil
		state.handoffFallbackProgressAt = nil
		return true
	end
	-- 攻击/攻击移动订单不能被交接补步覆盖；状态读取失败也不能当成“未攻击”。
	local actionType = Safe(nil, function() return bot:GetCurrentActionType() end)
	if type(actionType) ~= 'number' or type(BOT_ACTION_TYPE_ATTACK) ~= 'number'
	or type(BOT_ACTION_TYPE_ATTACKMOVE) ~= 'number' then
		StopHandoffFallback(bot, state, 'attack_state_unavailable')
		return false
	end
	if actionType == BOT_ACTION_TYPE_ATTACK or actionType == BOT_ACTION_TYPE_ATTACKMOVE then
		StopHandoffFallback(bot, state, 'attack_action')
		return true
	end
	local current = Safe(nil, function() return bot:GetLocation() end)
	if current == nil then return false end
	if state.handoffFallbackLastLocation ~= nil then
		state.handoffFallbackTravel = (state.handoffFallbackTravel or 0)
			+ Geometry.Distance(current, state.handoffFallbackLastLocation)
	end
	state.handoffFallbackLastLocation = SnapshotLocation(current)
	if (state.handoffFallbackTravel or 0) >= (tonumber(Config.HANDOFF_FALLBACK_MAX_TRAVEL) or 1200) then
		StopHandoffFallback(bot, state, 'travel_budget')
		return false
	end
	local reachDistance = math.max(0, tonumber(Config.HANDOFF_FALLBACK_REACH_DISTANCE) or 180)
	if state.handoffFallbackTarget == nil
	or Geometry.Distance(current, state.handoffFallbackTarget) <= reachDistance
	then
		StopHandoffFallback(bot, state, state.handoffFallbackTarget == nil and 'no_local_target' or 'arrived')
		return false
	end
	local scan = state.lastScan
	if scan == nil or now - (state.lastScanAt or -90) > 0.75
	or not Geometry.ValidateMovementSegment(current, state.handoffFallbackTarget,
		scan.visibleTowers or scan.allZones or {}, 64) then
		StopHandoffFallback(bot, state, 'unsafe_or_stale_segment')
		return false
	end
	local probeHolding, probeRetargeted = false, false
	if Probe ~= nil then probeHolding, probeRetargeted = Probe.Execute(bot, state, current, now, heldFor) end
	if probeHolding then return true end
	if not probeRetargeted then
		if Probe ~= nil then Probe.Retarget(bot, state, current, now, heldFor)
		else RetargetStalledHandoffFallback(bot, state, current, now, heldFor) end
	end
	if state.handoffFallbackAllowed ~= true then return false end
	if now - (state.handoffFallbackLastActionAt or -90)
		< (tonumber(Config.HANDOFF_FALLBACK_ACTION_INTERVAL) or 0.75)
	then
		return true
	end
	if type(bot.Action_MoveToLocation) ~= 'function' then return false end
	state.handoffFallbackLastActionAt = now
	bot:Action_MoveToLocation(state.handoffFallbackTarget)
	state.handoffFallbackActionCount = (state.handoffFallbackActionCount or 0) + 1
	Log(bot, state, 'mode-handoff', 'fallback_move', string.format(
		'held_for=%.3f fallback_action_count=%d current_x=%.1f current_y=%.1f target_x=%.1f target_y=%.1f travel=%.1f',
		heldFor, state.handoffFallbackActionCount, current.x or 0, current.y or 0,
		state.handoffFallbackTarget.x or 0, state.handoffFallbackTarget.y or 0,
		state.handoffFallbackTravel or 0))
	return true
end

local function Reacquire(bot, state)
	if state.handoffPending == true then
		local heldFor = state.handoffStartedAt ~= nil
			and math.max(0, Now() - state.handoffStartedAt) or 0
		Log(bot, state, 'mode-handoff', 'reacquired',
			string.format('held_for=%.3f previous_release_reason=%s fallback_action_count=%d fallback_retarget_count=%d',
				heldFor, tostring(state.handoffReleaseReason),
				state.handoffFallbackActionCount or 0,
				state.handoffFallbackRetargetCount or 0))
		ResetModeHandoff(state)
	end
end

local function Begin(bot, state, reason, handoffAnchor, handoffZones, now)
	state.handoffPending = true
	state.handoffModeEnded = false
	state.handoffStartedAt = now
	state.handoffReleaseReason = reason or 'released'
	state.handoffStaleLogged = false
	state.handoffFallbackAllowed = reason == 'clearance_confirmed'
	state.handoffFallbackTarget = state.handoffFallbackAllowed
		and BuildHandoffFallbackTarget(bot, handoffAnchor, nil, handoffZones) or nil
	state.handoffFallbackTravel = 0
	state.handoffFallbackLastLocation = SnapshotLocation(bot:GetLocation())
	state.handoffFallbackLastActionAt = -90
	state.handoffFallbackActionCount = 0
	state.handoffFallbackUnavailableLogged = false
	state.handoffFallbackProgressLocation = nil
	state.handoffFallbackProgressAt = nil
	state.handoffFallbackRetargetCount = 0
	local fallbackTarget = state.handoffFallbackTarget or {}
	local releaseLocation = bot:GetLocation()
	Log(bot, state, 'mode-handoff', 'pending',
		'release_reason=' .. tostring(state.handoffReleaseReason)
			.. ' fallback_allowed=' .. tostring(state.handoffFallbackAllowed and 1 or 0)
			.. string.format(' fallback_target_x=%.1f fallback_target_y=%.1f release_x=%.1f release_y=%.1f fallback_target_distance=%.1f',
				fallbackTarget.x or 0, fallbackTarget.y or 0, releaseLocation.x, releaseLocation.y,
				state.handoffFallbackTarget ~= nil and Geometry.Distance(releaseLocation, fallbackTarget) or -1))
end

local function OnEnd(bot, state)
	if state.handoffPending == true then
		state.handoffModeEnded = true
		local heldFor = state.handoffStartedAt ~= nil
			and math.max(0, Now() - state.handoffStartedAt) or 0
		Log(bot, state, 'mode-handoff', 'mode_end',
			string.format('held_for=%.3f release_reason=%s fallback_action_count=%d fallback_retarget_count=%d',
				heldFor, tostring(state.handoffReleaseReason),
				state.handoffFallbackActionCount or 0,
				state.handoffFallbackRetargetCount or 0))
		StopHandoffFallback(bot, state, 'mode_ended')
	end
	Log(bot, state, 'mode-end', 'yielded', '')
end

if Config.HANDOFF_FALLBACK_STALL_PROBE == true then
	Probe = require(GetScriptDirectory()..'/THDFuncLib/avoidance_handoff_probe').New({
		Now = Now, Safe = Safe, Log = Log, SnapshotLocation = SnapshotLocation,
		ResetProgress = ResetHandoffFallbackProgress, Stop = StopHandoffFallback,
		BuildTarget = BuildHandoffFallbackTarget,
	})
end
return {Reset = ResetModeHandoff, Begin = Begin, Reacquire = Reacquire, OnEnd = OnEnd, Stop = StopHandoffFallback,
	Observe = ObserveModeHandoff, Execute = ExecuteModeHandoffFallback}
end

return Handoff
