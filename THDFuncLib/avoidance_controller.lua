local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local TowerSafety = require(GetScriptDirectory()..'/THDFuncLib/tower_safety')
local ZoneManager = require(GetScriptDirectory()..'/THDFuncLib/avoidance_zone_manager')
local AvoidancePath = require(GetScriptDirectory()..'/THDFuncLib/avoidance_path')
local Pickoff = require(GetScriptDirectory()..'/THDFuncLib/roam_pickoff')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')

local Controller = {}

-- EVASIVE 只拥有防越塔逃生窗口；安全保持结束后立即交还 Valve 模式仲裁。

Controller.IDLE = 'IDLE'
Controller.ESCAPE_DIRECT = 'ESCAPE_DIRECT'
Controller.WAITING_PATH = 'WAITING_PATH'
Controller.FOLLOWING_PATH = 'FOLLOWING_PATH'
Controller.CLEARANCE_HOLD = 'CLEARANCE_HOLD'
Controller.OBJECTIVE_ESCAPE_GRACE = Config.OBJECTIVE_ESCAPE_GRACE

local function Now()
	local ok, value = pcall(DotaTime)
	return ok and type(value) == 'number' and value or 0
end

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if not ok or value == nil then return defaultValue end
	return value
end

local function IsValidBot(bot)
	if bot == nil then return false end
	if bot.IsNull ~= nil and Safe(true, function() return bot:IsNull() end) then return false end
	if bot.IsAlive ~= nil and not Safe(false, function() return bot:IsAlive() end) then return false end
	if bot.IsHero ~= nil and not Safe(false, function() return bot:IsHero() end) then return false end
	if bot.IsIllusion ~= nil and Safe(false, function() return bot:IsIllusion() end) then return false end
	return true
end

local function IsProtectedAction(bot)
	if bot == nil then return false end
	if Safe(false, function() return bot:HasModifier('modifier_teleporting') end)
		or Safe(false, function() return bot:HasModifier('modifier_ability_thdots_chen01') end)
		or Safe(false, function() return bot:IsCastingAbility() end)
		or Safe(false, function() return bot:IsUsingAbility() end)
		or Safe(false, function() return bot:IsChanneling() end)
	then
		return true
	end
	local ability = Safe(nil, function() return bot:GetCurrentActiveAbility() end)
	if ability ~= nil then
		if Safe(false, function() return ability:IsInAbilityPhase() end)
		or Safe(false, function() return ability:IsChanneling() end)
		then
			return true
		end
	end
	return false
end

local function GetState(bot)
	if bot.THD_AvoidanceControllerState == nil then
		bot.THD_AvoidanceControllerState = {
			active = false,
			state = Controller.IDLE,
			startedAt = nil,
			stateChangedAt = nil,
			clearanceSince = nil,
			routeClearSince = nil,
			lastDirectActionAt = -90,
			lastDirectTarget = nil,
			lastReasons = {},
			lastAnchor = nil,
			lastScan = nil,
			actionCount = 0,
			hadContainingZone = false,
			egressCommitActive = false,
			containingZoneLatches = {},
			containingZoneClearSince = {},
			retreatThroughZoneLatches = {},
			handoffPending = false,
			handoffModeEnded = false,
			handoffStartedAt = nil,
			handoffReleaseReason = nil,
			handoffStaleLogged = false,
			handoffFallbackAllowed = false,
			handoffFallbackTarget = nil,
			handoffFallbackLastActionAt = -90,
			handoffFallbackActionCount = 0,
			handoffFallbackUnavailableLogged = false,
			handoffFallbackProgressLocation = nil,
			handoffFallbackProgressAt = nil,
			handoffFallbackRetargetCount = 0,
			handoffFallbackStallProbeStartedAt = nil,
			handoffFallbackStallProbeLastActionAt = -90,
			handoffFallbackStallProbeComplete = false,
			lastTeamfightTowerPolicyLogAt = -90,
			lastTeamfightTowerPolicyResult = nil,
		}
	end
	return bot.THD_AvoidanceControllerState
end

local function Log(bot, state, stage, result, extra)
	if Config.DEBUG_LOG ~= true then return end
	print(string.format(
		'[BOT][AvoidanceDev] run=%s phase=runtime team=%s player=%s generation=%s zone=tower_escape api=none stage=%s result=%s state=%s game_time=%.3f %s',
		tostring(Config.RUN_ID or 'unset'),
		tostring(Safe(-1, function() return bot:GetTeam() end)),
		tostring(Safe(-1, function() return bot:GetPlayerID() end)),
		tostring(bot.THD_TowerEscapeGeneration or 0), tostring(stage), tostring(result),
		tostring(state.state), Now(), 'action_count=' .. tostring(state.actionCount or 0)
			.. ' ' .. tostring(extra or '')))
end

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
	local holdTime = math.max((tonumber(Config.HANDOFF_FALLBACK_STALL_TIME) or 1.5) + 0.05,
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
	local probeHolding, probeRetargeted = ExecuteHandoffFallbackStallProbe(
		bot, state, current, now, heldFor)
	if probeHolding then return true end
	if not probeRetargeted then
		RetargetStalledHandoffFallback(bot, state, current, now, heldFor)
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

local function FormatZones(zones)
	local parts = {}
	for _, zone in ipairs(zones or {}) do
		local center = zone.center or {}
		table.insert(parts, string.format('%s@%.0f,%.0f:r%.0f', tostring(zone.key or 'unknown'),
			center.x or 0, center.y or 0, zone.effectiveRadius or zone.radius or 0))
	end
	return table.concat(parts, '|')
end

local function FormatPathZones(zones, requestZoneKeys, currentLocation)
	local parts = {}
	requestZoneKeys = requestZoneKeys or {}
	for _, zone in ipairs(zones or {}) do
		local center = zone.center or {}
		local radius = tonumber(zone.effectiveRadius or zone.radius) or 0
		local distance = currentLocation ~= nil and Geometry.Distance(currentLocation, center) or 0
		table.insert(parts, string.format(
			'%s@%.0f,%.0f:r%.0f:distance=%.1f:actual=%d:requested=%d',
			tostring(zone.key or 'unknown'), center.x or 0, center.y or 0,
			radius, distance, distance <= radius and 1 or 0,
			requestZoneKeys[tostring(zone.key or 'unknown')] == true and 1 or 0))
	end
	return table.concat(parts, '|')
end

local function SetModeState(bot, state, modeState, reason)
	if state.state == modeState then return end
	state.state = modeState
	state.stateChangedAt = Now()
	Log(bot, state, 'state-change', reason or 'transition', 'next=' .. tostring(modeState))
end

local function SetActive(bot, state, scan)
	if state.active then return end
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
	state.active = true
	state.startedAt = Now()
	state.clearanceSince = nil
	state.routeClearSince = nil
	state.lastReasons = scan.reasons or {}
	state.lastAnchor = scan.anchor
	state.actionCount = 0
	state.hadContainingZone = false
	state.egressCommitActive = false
	state.containingZoneLatches = {}
	state.containingZoneClearSince = {}
	state.retreatThroughZoneLatches = {}
	state.minCenterClearance = math.huge
	bot.THD_TowerEscapeActive = true
	bot.THD_TowerEscapeGeneration = (bot.THD_TowerEscapeGeneration or 0) + 1
	SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'danger_acquired')
	local anchor = scan.anchor or {}
	Log(bot, state, 'lease', 'acquired', 'reasons=' .. table.concat(state.lastReasons, ',')
		.. ' zone_count=' .. tostring(#(scan.allZones or {}))
		.. ' zones=' .. FormatZones(scan.allZones)
		.. string.format(' anchor_x=%.1f anchor_y=%.1f anchor_distance=%.1f anchor_extended=%d',
			anchor.x or 0, anchor.y or 0, scan.anchorDistance or 0, scan.anchorExtended and 1 or 0))
end

local function Clear(bot, state, reason)
	if not state.active then return end
	local now = Now()
	local handoffAnchor = SnapshotLocation(state.lastAnchor)
	local handoffZones = state.lastScan ~= nil
		and (state.lastScan.visibleTowers or state.lastScan.allZones) or {}
	local heldFor = state.startedAt ~= nil and math.max(0, now - state.startedAt) or 0
	local pathSnapshot = AvoidancePath.GetState(bot)
	if reason == 'invalid_bot' or reason == 'feature_disabled' then
		ZoneManager.Reset(bot, 'runtime')
	else
		ZoneManager.ReleaseActive(bot, 'runtime')
	end
	AvoidancePath.Cancel(bot, reason or 'released')
	state.active = false
	state.clearanceSince = nil
	state.routeClearSince = nil
	state.lastReasons = {}
	state.lastAnchor = nil
	state.lastScan = nil
	state.hadContainingZone = false
	state.egressCommitActive = false
	state.containingZoneLatches = {}
	state.containingZoneClearSince = {}
	state.retreatThroughZoneLatches = {}
	bot.THD_TowerEscapeActive = false
	SetModeState(bot, state, Controller.IDLE, reason or 'released')
	Log(bot, state, 'lease', 'released', 'reason=' .. tostring(reason)
		.. string.format(' held_for=%.3f', heldFor)
		.. ' path_action_count=' .. tostring(pathSnapshot.totalActionCount or pathSnapshot.actionCount or 0)
		.. ' min_center_clearance=' .. tostring(state.minCenterClearance or 'none'))
	state.startedAt = nil
	-- 释放租约后继续观察 Valve 模式仲裁，区分正常交接与 desire=0 的 mode 19 残留。
	if reason ~= 'invalid_bot' and reason ~= 'feature_disabled' and IsValidBot(bot) then
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
	else
		ResetModeHandoff(state)
	end
end

local function IsScanClear(scan, containingZones, routeZones)
	return scan ~= nil
		and scan.triggered ~= true
		and #(containingZones or {}) == 0
		and #(routeZones or {}) == 0
		and scan.incomingCount == 0
		and scan.unseenIncoming ~= true
		and scan.recentTowerDamage ~= true
end

local function UpdateClearance(bot, state, scan, containingZones, routeZones)
	if not IsScanClear(scan, containingZones, routeZones) then
		state.clearanceSince = nil
		return false
	end
	if state.clearanceSince == nil then
		state.clearanceSince = Now()
		Log(bot, state, 'clearance-window', 'started',
			'hold_required=' .. tostring(Config.CLEARANCE_HOLD_TIME))
		SetModeState(bot, state, Controller.CLEARANCE_HOLD, 'clearance_started')
	end
	if Now() - state.clearanceSince >= Config.CLEARANCE_HOLD_TIME then
		Clear(bot, state, 'clearance_confirmed')
		return true
	end
	return false
end

local function UniqueZones(first, second)
	local result, seen = {}, {}
	for _, list in ipairs({first or {}, second or {}}) do
		for _, zone in ipairs(list) do
			if zone.key ~= nil and not seen[zone.key] then
				seen[zone.key] = true
				table.insert(result, zone)
			end
		end
	end
	return result
end

local function GetRouteSafetyMargin()
	return math.max(0, tonumber(Config.LUA_ROUTE_SAFETY_MARGIN) or 0)
end

local function RefreshKnownZones(bot, scan)
	ZoneManager.UpsertSnapshots(bot, scan.allZones or {}, Now(), scan.visibleTowers)
	return ZoneManager.GetRecords(bot)
end

local function GetHighLevelTeamfightPriority(bot)
	if Config.HIGH_LEVEL_TEAMFIGHT_TOWER_PRIORITY_ENABLED ~= true then return nil end
	local botLevel = tonumber(Safe(nil, function() return bot:GetLevel() end))
	if botLevel == nil
	or botLevel < (tonumber(Config.HIGH_LEVEL_TEAMFIGHT_MIN_BOT_LEVEL) or 25)
	then
		return nil
	end
	local teamAverageLevel = Wasteland.GetStrictTeamAverageLevel ~= nil
		and tonumber(Safe(nil, function() return Wasteland.GetStrictTeamAverageLevel() end)) or nil
	if teamAverageLevel == nil
	or teamAverageLevel < (tonumber(Config.HIGH_LEVEL_TEAMFIGHT_MIN_TEAM_AVERAGE_LEVEL) or 25)
	then
		return nil
	end
	local location = Safe(nil, function() return bot:GetLocation() end)
	if location == nil or Pickoff.GetTeamfightStatus == nil then return nil end
	local ok, active, details = pcall(Pickoff.GetTeamfightStatus, bot, location)
	if not ok or active ~= true or type(details) ~= 'table' then return nil end
	return {
		botLevel = botLevel,
		teamAverageLevel = teamAverageLevel,
		allyCount = tonumber(details.allyCount) or 0,
		enemyCount = tonumber(details.enemyCount) or 0,
		totalHeroCount = tonumber(details.totalHeroCount) or 0,
	}
end

local function GetHighGroundAssaultAuthorization(bot)
	local authorization = bot ~= nil and bot.THD_HighGroundAssaultAuthorization or nil
	if type(authorization) ~= 'table' then return nil end
	if tonumber(authorization.expiresAt) == nil or Now() > authorization.expiresAt then
		bot.THD_HighGroundAssaultAuthorization = nil
		return nil
	end
	return authorization
end

local function FilterAuthorizedHighGroundZones(zones, authorization, scan)
	if scan ~= nil and (scan.teamfightPriorityBypassCount or 0) > 0 then return {} end
	if authorization == nil then return zones or {} end
	local filtered = {}
	for _, zone in ipairs(zones or {}) do
		local authorizedTower = zone.severity == 'high_ground_tower'
			and authorization.targetLocation ~= nil
			and Geometry.Distance(zone.center, authorization.targetLocation)
				<= (tonumber(authorization.towerBypassRadius) or 0)
		if not authorizedTower then table.insert(filtered, zone) end
	end
	return filtered
end

local function LogTeamfightTowerPolicy(bot, state, scan, context)
	if context == nil or scan == nil then return end
	local bypassCount = tonumber(scan.teamfightPriorityBypassCount) or 0
	local highGroundCount = tonumber(scan.highGroundAttackRangeCount) or 0
	local maxHighGround = math.max(0,
		tonumber(Config.HIGH_LEVEL_TEAMFIGHT_MAX_HIGH_GROUND_TOWERS) or 1)
	local result = bypassCount > 0 and 'teamfight_priority_bypass'
		or (highGroundCount > maxHighGround and 'teamfight_multi_high_ground_escape' or nil)
	if result == nil then return end
	local now = Now()
	local interval = math.max(0.1,
		tonumber(Config.HIGH_LEVEL_TEAMFIGHT_POLICY_LOG_INTERVAL) or 1.0)
	if state.lastTeamfightTowerPolicyResult == result
	and now - (state.lastTeamfightTowerPolicyLogAt or -90) < interval
	then
		return
	end
	state.lastTeamfightTowerPolicyResult = result
	state.lastTeamfightTowerPolicyLogAt = now
	Log(bot, state, 'policy', result, string.format(
		'bot_level=%d team_average_level=%.2f allies=%d enemies=%d total_heroes=%d high_ground_attack_range_count=%d bypassed_tower_count=%d anchor_available=%d ancient_anchor_fallback=%d',
		context.botLevel, context.teamAverageLevel, context.allyCount, context.enemyCount,
		context.totalHeroCount, highGroundCount, bypassCount,
		scan.anchor ~= nil and 1 or 0, scan.multipleHighGroundAnchorFallback == true and 1 or 0))
end

local function GetOwnAncientLocation(bot)
	local ancient = Safe(nil, function() return GetAncient(bot:GetTeam()) end)
	return ancient ~= nil and Safe(nil, function() return ancient:GetLocation() end) or nil
end

local function IsOnOwnAncientSide(location, ancientLocation, zone)
	if location == nil or ancientLocation == nil or zone == nil or zone.center == nil then return false end
	local center = zone.center
	local locationX, locationY = (location.x or 0) - (center.x or 0), (location.y or 0) - (center.y or 0)
	local ancientX, ancientY = (ancientLocation.x or 0) - (center.x or 0), (ancientLocation.y or 0) - (center.y or 0)
	return locationX * ancientX + locationY * ancientY >= 0
end

local function ShouldAcquireRetreatThrough(location, ancientLocation, zone)
	return zone ~= nil and zone.severity == 'high_ground_tower'
		and not IsOnOwnAncientSide(location, ancientLocation, zone)
		and Geometry.SegmentIntersectsCircle(location, ancientLocation, zone, 0)
end

local function GetRouteGeometry(bot, anchor, knownZones, state)
	local location = bot:GetLocation()
	local containing = {}
	local activeKeys = {}
	local latches = state ~= nil and state.containingZoneLatches or nil
	local clearSinceByKey = state ~= nil and state.containingZoneClearSince or nil
	local retreatThroughLatches = state ~= nil and state.retreatThroughZoneLatches or nil
	local ancientLocation = retreatThroughLatches ~= nil and GetOwnAncientLocation(bot) or nil
	local now = Now()
	local pathHandoffMargin = math.max(tonumber(Config.TOWER_EXIT_HYSTERESIS) or 0,
		tonumber(Config.PATH_HANDOFF_CLEARANCE_MARGIN) or 0)
	local pathHandoffHold = math.max(0,
		tonumber(Config.PATH_HANDOFF_CLEARANCE_HOLD_TIME) or 0)
	local geometryZones = {}
	for _, zone in ipairs(knownZones or {}) do
		local key = zone.key or tostring(zone)
		activeKeys[key] = true
		local retreatThrough = retreatThroughLatches ~= nil and retreatThroughLatches[key] == true
		if not retreatThrough and ShouldAcquireRetreatThrough(location, ancientLocation, zone) then
			retreatThrough = true
			retreatThroughLatches[key] = true
			Log(bot, state, 'policy', 'retreat_through_acquired', 'tower=' .. tostring(key))
		elseif retreatThrough
		and IsOnOwnAncientSide(location, ancientLocation, zone)
		and not Geometry.PointInCircle(location, zone, Config.TOWER_EXIT_HYSTERESIS or 0)
		then
			retreatThrough = false
			retreatThroughLatches[key] = nil
			Log(bot, state, 'policy', 'retreat_through_released', 'tower=' .. tostring(key))
		end
		if retreatThrough then
			-- Bot 已在高地塔的敌方一侧时，继续向己方 Ancient 穿过该塔圆，禁止绕回高地。
			if latches ~= nil then latches[key] = nil end
			if clearSinceByKey ~= nil then clearSinceByKey[key] = nil end
		else
			table.insert(geometryZones, zone)
		end
		local inside = Geometry.PointInCircle(location, zone, 0)
		if not retreatThrough and latches ~= nil then
			if inside then
				if clearSinceByKey ~= nil and clearSinceByKey[key] ~= nil then
					Log(bot, state, 'path-policy', 'handoff_clearance_reset', string.format(
						'tower=%s reason=tower_reentry held_for=%.3f', tostring(key),
						math.max(0, now - clearSinceByKey[key])))
				end
				latches[key] = true
				if clearSinceByKey ~= nil then clearSinceByKey[key] = nil end
			elseif latches[key] == true then
				if Geometry.PointInCircle(location, zone, pathHandoffMargin) then
					if clearSinceByKey ~= nil and clearSinceByKey[key] ~= nil then
						Log(bot, state, 'path-policy', 'handoff_clearance_reset', string.format(
							'tower=%s reason=margin_reentry held_for=%.3f', tostring(key),
							math.max(0, now - clearSinceByKey[key])))
						clearSinceByKey[key] = nil
					end
					inside = true
				elseif clearSinceByKey ~= nil then
					if clearSinceByKey[key] == nil then
						clearSinceByKey[key] = now
						Log(bot, state, 'path-policy', 'handoff_clearance_started', string.format(
							'tower=%s margin=%.1f hold_required=%.2f', tostring(key),
							pathHandoffMargin, pathHandoffHold))
					end
					local heldFor = math.max(0, now - clearSinceByKey[key])
					if heldFor < pathHandoffHold then
						inside = true
					else
						latches[key] = nil
						clearSinceByKey[key] = nil
						Log(bot, state, 'path-policy', 'handoff_clearance_confirmed', string.format(
							'tower=%s held_for=%.3f margin=%.1f', tostring(key), heldFor,
							pathHandoffMargin))
					end
				else
					latches[key] = nil
				end
			else
				latches[key] = nil
				if clearSinceByKey ~= nil then clearSinceByKey[key] = nil end
			end
		end
		if not retreatThrough and inside then table.insert(containing, zone) end
	end
	if latches ~= nil then
		for key in pairs(latches) do
			if activeKeys[key] ~= true then
				latches[key] = nil
				if clearSinceByKey ~= nil then clearSinceByKey[key] = nil end
			end
		end
	end
	if retreatThroughLatches ~= nil then
		for key in pairs(retreatThroughLatches) do
			if activeKeys[key] ~= true then retreatThroughLatches[key] = nil end
		end
	end
	-- 普通 MoveToLocation 会受导航网格影响而偏离几何直线；路线判定预留额外净空。
	local routeMargin = GetRouteSafetyMargin()
	local route = anchor ~= nil
		and Geometry.FilterIntersectingZones(location, anchor, geometryZones, routeMargin) or {}
	return containing, route, geometryZones
end

local function BuildMovementGeometry(bot, state, scan, knownZones, authorization, teamfight)
	local records = ZoneManager.GetGeometryRecords(bot)
	local maxHighGround = math.max(0, tonumber(Config.HIGH_LEVEL_TEAMFIGHT_MAX_HIGH_GROUND_TOWERS) or 1)
	local highGroundCount = tonumber(scan.highGroundAttackRangeCount) or 0
	local teamfightBypass = teamfight ~= nil and highGroundCount <= maxHighGround
	local forceMultiHighGround = teamfight ~= nil and highGroundCount > maxHighGround
	local movementAuthorization = authorization
	if forceMultiHighGround then movementAuthorization = nil end
	local allowed = {}
	for _, zone in ipairs(FilterAuthorizedHighGroundZones(records, movementAuthorization, scan)) do
		allowed[zone.key] = true
	end
	local visible, excluded, result = {}, {}, {}
	for _, snapshot in ipairs(scan.visibleTowers or {}) do visible[snapshot.key] = true end
	local location = bot:GetLocation()
	local ancientLocation = GetOwnAncientLocation(bot)
	for _, zone in ipairs(records) do
		local reason
		if teamfightBypass then
			reason = 'teamfight_authorized'
		elseif not allowed[zone.key] then
			reason = 'assault_authorized'
		elseif state.retreatThroughZoneLatches[zone.key] == true
		or ShouldAcquireRetreatThrough(location, ancientLocation, zone) then
			reason = 'retreat_through'
		end
		if reason ~= nil then excluded[zone.key] = reason
		else table.insert(result, zone) end
	end
	-- 只用于已取得租约后的移动；GetDesire/净空释放仍使用原 1 秒活动集合。
	return result, {records = records, visible = visible, excluded = excluded, active = knownZones}
end

local function LogMovementGeometry(bot, state, geometryZones, routeZones, audit, force)
	if Config.DEBUG_LOG ~= true then return end
	local now = Now()
	if not force and now - (state.lastGeometryLogAt or -90)
		< (tonumber(Config.GEOMETRY_SNAPSHOT_LOG_INTERVAL) or 1) then return end
	state.lastGeometryLogAt = now
	local parts = {}
	for _, zone in ipairs(audit.records) do
		table.insert(parts, string.format('%s:source=%s:age=%.3f:decision=%s',
			tostring(zone.key), audit.visible[zone.key] and 'visible' or 'remembered',
			math.max(0, now - (zone.lastSeenAt or now)), audit.excluded[zone.key] or 'included'))
	end
	Log(bot, state, 'geometry-snapshot', force and 'path_request' or 'movement',
		'active_zones=' .. (#audit.active > 0 and FormatZones(audit.active) or 'none')
			.. ' route_zones=' .. (#routeZones > 0 and FormatZones(routeZones) or 'none')
			.. ' geometry_zones=' .. (#geometryZones > 0 and FormatZones(geometryZones) or 'none')
			.. ' observations=' .. (#parts > 0 and table.concat(parts, '|') or 'none'))
end

local function MoveDirect(bot, state, location, reason)
	if location == nil or type(bot.Action_MoveToLocation) ~= 'function' then return false end
	local now = Now()
	if now - (state.lastDirectActionAt or -90) < Config.DIRECT_ACTION_INTERVAL
	and state.lastDirectTarget ~= nil
	and Geometry.Distance(state.lastDirectTarget, location) <= 80
	then
		return true
	end
	state.lastDirectActionAt = now
	state.lastDirectTarget = location
	bot:Action_MoveToLocation(location)
	state.actionCount = (state.actionCount or 0) + 1
	local current = Safe(nil, function() return bot:GetLocation() end) or {}
	Log(bot, state, 'execute', reason or 'direct_move', string.format(
		'current_x=%.1f current_y=%.1f target_x=%.1f target_y=%.1f',
		current.x or 0, current.y or 0, location.x or 0, location.y or 0))
	return true
end

local function RejectUnsafePathSegment(bot, state, anchor, latestZones, routeZones, pathState)
	local safe, reason, details = AvoidancePath.ValidateCurrentSegment(bot, latestZones,
		GetRouteSafetyMargin())
	if safe then return false end
	details = details or {}
	local current = details.current or Safe(nil, function() return bot:GetLocation() end) or {}
	local target = details.target or {}
	local zone = details.zone or {}
	local center = zone.center or {}
	local requested = details.zone ~= nil
		and AvoidancePath.RequestIncludesZone(bot, zone.key) and 1 or 0
	Log(bot, state, 'path-policy', 'waypoint_rejected', string.format(
		'reason=%s path_status=%s previous_path_generation=%s waypoint_index=%s '
			.. 'current_x=%.1f current_y=%.1f waypoint_x=%.1f waypoint_y=%.1f '
			.. 'zone=%s zone_x=%.1f zone_y=%.1f zone_radius=%.1f requested=%d route_margin=%.1f',
		tostring(reason), tostring(pathState.status), tostring(pathState.generation),
		tostring(details.waypointIndex or pathState.waypointIndex or 0),
		current.x or 0, current.y or 0, target.x or 0, target.y or 0,
		tostring(zone.key or 'none'), center.x or 0, center.y or 0,
		zone.effectiveRadius or zone.radius or 0, requested, GetRouteSafetyMargin()))
	AvoidancePath.MarkNeedsRepath(bot, 'unsafe_current_segment')
	SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'unsafe_current_segment')
	local rejectedZones = details.zone ~= nil and {details.zone} or {}
	local escapeZones = UniqueZones(routeZones, rejectedZones)
	local escapePoint = Geometry.FindDirectEscapePoint(current, anchor, latestZones,
		GetRouteSafetyMargin(), escapeZones)
	if escapePoint ~= nil then MoveDirect(bot, state, escapePoint, 'unsafe_path_egress') end
	return true
end

local function ResetRouteClearCommit(bot, state, reason)
	if state.routeClearSince ~= nil then
		Log(bot, state, 'route-clear-commit', 'reset', string.format(
			'reason=%s held_for=%.3f', tostring(reason or 'route_intersection'),
			math.max(0, Now() - state.routeClearSince)))
	end
	state.routeClearSince = nil
end

local function ShouldHoldRouteClearCommit(bot, state)
	if state.egressCommitActive ~= true then return false end
	local now = Now()
	local holdRequired = math.max(0, tonumber(Config.ROUTE_CLEAR_COMMIT_TIME) or 0)
	if state.routeClearSince == nil then
		state.routeClearSince = now
		Log(bot, state, 'route-clear-commit', 'started',
			'hold_required=' .. tostring(holdRequired))
	end
	local heldFor = math.max(0, now - state.routeClearSince)
	if heldFor < holdRequired then return true end
	state.routeClearSince = nil
	state.egressCommitActive = false
	Log(bot, state, 'route-clear-commit', 'confirmed',
		string.format('held_for=%.3f', heldFor))
	return false
end

local function BuildExcludedKeys(containingZones)
	local excluded = {}
	for _, zone in ipairs(containingZones or {}) do excluded[zone.key] = true end
	return excluded
end

function Controller.IsEnabled(bot)
	return Config.IsModeOverrideEnabled()
		and (Config.IsRuntimeTarget == nil or Config.IsRuntimeTarget(bot))
end

function Controller.IsActionLocked(bot)
	if bot == nil then return false end
	local state = bot.THD_AvoidanceControllerState
	return bot.THD_TowerEscapeActive == true
		or (type(state) == 'table' and state.active == true)
end

function Controller.GetDesire(bot)
	if not Controller.IsEnabled(bot) then
		if bot ~= nil and bot.THD_AvoidanceControllerState ~= nil then
			StopHandoffFallback(bot, GetState(bot), 'feature_disabled')
			Clear(bot, GetState(bot), 'feature_disabled')
			if bot.THD_AvoidanceZoneState ~= nil then ZoneManager.Reset(bot, 'runtime') end
		end
		CandidateDebug.Note('feature_disabled')
		return BOT_MODE_DESIRE_NONE
	end
	if not IsValidBot(bot) then
		if bot ~= nil and bot.THD_AvoidanceControllerState ~= nil then
			StopHandoffFallback(bot, GetState(bot), 'invalid_bot')
			Clear(bot, GetState(bot), 'invalid_bot')
			if bot.THD_AvoidanceZoneState ~= nil then ZoneManager.Reset(bot, 'runtime') end
		end
		CandidateDebug.Note('invalid_bot')
		return BOT_MODE_DESIRE_NONE
	end

	local state = GetState(bot)
	ObserveModeHandoff(bot, state)
	local highGroundAuthorization = GetHighGroundAssaultAuthorization(bot)
	local highLevelTeamfight = GetHighLevelTeamfightPriority(bot)
	local scan = TowerSafety.Scan(bot, {
		highGroundAssaultAuthorization = highGroundAuthorization,
		highLevelTeamfight = highLevelTeamfight,
	})
	state.lastScan = scan
	state.lastScanAt = Now()
	LogTeamfightTowerPolicy(bot, state, scan, highLevelTeamfight)
	-- 复用已做过的可见扫描；无租约时只更新数值记忆，不增加 desire。
	local knownZones = RefreshKnownZones(bot, scan)
	if state.active and (scan.teamfightPriorityBypassCount or 0) > 0 then
		Clear(bot, state, 'high_level_teamfight_authorized')
		CandidateDebug.Note('teamfight_authorized')
		return BOT_MODE_DESIRE_NONE
	end
	knownZones = FilterAuthorizedHighGroundZones(knownZones, highGroundAuthorization, scan)
	CandidateDebug.Detail('scan_triggered', scan.triggered)
	CandidateDebug.Detail('anchor_available', scan.anchor ~= nil)
	CandidateDebug.Detail('high_ground_overlap', scan.highGroundAttackRangeCount)
	CandidateDebug.Detail('controller_active', state.active)
	if not state.active then
		if not scan.triggered or scan.anchor == nil then
			CandidateDebug.Note('no_trigger_or_anchor')
			return BOT_MODE_DESIRE_NONE
		end
		SetActive(bot, state, scan)
	else
		state.lastReasons = scan.reasons or state.lastReasons
	end
	local containingZones, routeZones = GetRouteGeometry(bot, state.lastAnchor or scan.anchor, knownZones, state)
	if state.active and highGroundAuthorization ~= nil
	and scan.highGroundAssaultBypassCount > 0
	and IsScanClear(scan, containingZones, routeZones)
	then
		Clear(bot, state, 'high_ground_assault_authorized')
		CandidateDebug.Note('high_ground_authorized')
		return BOT_MODE_DESIRE_NONE
	end
	if state.active and UpdateClearance(bot, state, scan, containingZones, routeZones) then
		CandidateDebug.Note('clearance_confirmed')
		return BOT_MODE_DESIRE_NONE
	end
	CandidateDebug.Note(state.active and 'escape_lease_active' or 'no_escape_lease')
	return state.active and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE
end

function Controller.OnStart(bot)
	if bot == nil then return end
	local state = GetState(bot)
	Log(bot, state, 'mode-start', 'selected', '')
end

function Controller.OnEnd(bot)
	if bot == nil or bot.THD_AvoidanceControllerState == nil then return end
	local state = GetState(bot)
	-- 模式竞争结束不等于危险消失；租约只由同帧安全检查释放。
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

function Controller.Think(bot)
	if not Controller.IsEnabled(bot) or not IsValidBot(bot) then return false end
	local state = GetState(bot)
	ObserveModeHandoff(bot, state)
	if not state.active then return ExecuteModeHandoffFallback(bot, state) end
	local highGroundAuthorization = GetHighGroundAssaultAuthorization(bot)
	local highLevelTeamfight = GetHighLevelTeamfightPriority(bot)
	local scan = TowerSafety.Scan(bot, {
		highGroundAssaultAuthorization = highGroundAuthorization,
		highLevelTeamfight = highLevelTeamfight,
	})
	state.lastScan = scan
	state.lastScanAt = Now()
	LogTeamfightTowerPolicy(bot, state, scan, highLevelTeamfight)
	if (scan.teamfightPriorityBypassCount or 0) > 0 then
		Clear(bot, state, 'high_level_teamfight_authorized')
		return false
	end
	local knownZones = FilterAuthorizedHighGroundZones(
		RefreshKnownZones(bot, scan), highGroundAuthorization, scan)
	local current = bot:GetLocation()
	for _, zone in ipairs(knownZones) do
		state.minCenterClearance = math.min(state.minCenterClearance or math.huge,
			Geometry.Distance(current, zone.center))
	end
	local anchor = state.lastAnchor or scan.anchor
	local containingZones, routeZones = GetRouteGeometry(bot, anchor, knownZones, state)
	if #containingZones > 0 then
		state.hadContainingZone = true
		state.egressCommitActive = true
		ResetRouteClearCommit(bot, state, 'inside_tower_zone')
	elseif state.hadContainingZone then
		-- 离开起点塔圆时刷新一次 1400 距离锚点，之后冻结，避免移动中每帧重提路径。
		state.hadContainingZone = false
		state.egressCommitActive = true
		state.routeClearSince = nil
		state.lastAnchor = scan.anchor or anchor
		anchor = state.lastAnchor
		AvoidancePath.MarkNeedsRepath(bot, 'left_starting_zone')
		containingZones, routeZones = GetRouteGeometry(bot, anchor, knownZones, state)
	elseif anchor ~= nil and Geometry.Distance(bot:GetLocation(), anchor) <= 180
	and (scan.triggered or #routeZones > 0)
	and scan.anchor ~= nil and Geometry.Distance(anchor, scan.anchor) > 80
	then
		state.lastAnchor = scan.anchor
		anchor = state.lastAnchor
		AvoidancePath.MarkNeedsRepath(bot, 'escape_anchor_reached')
		containingZones, routeZones = GetRouteGeometry(bot, anchor, knownZones, state)
	end
	if UpdateClearance(bot, state, scan, containingZones, routeZones) then return true end
	if IsProtectedAction(bot) then
		Log(bot, state, 'execute', 'protected_action', '')
		return true
	end

	local geometryZones, geometryAudit = BuildMovementGeometry(bot, state, scan, knownZones,
		highGroundAuthorization, highLevelTeamfight)
	local movementRouteZones = anchor ~= nil
		and Geometry.FilterIntersectingZones(current, anchor, geometryZones, GetRouteSafetyMargin()) or {}
	LogMovementGeometry(bot, state, geometryZones, movementRouteZones, geometryAudit, false)
	local records = UniqueZones(containingZones, routeZones)
	-- 每帧同步路线塔区，既维持短 TTL，也会在路线清除或进入圆内时提前 Remove。
	ZoneManager.SyncNative(bot, records, BuildExcludedKeys(containingZones), 'runtime')
	if #containingZones > 0 then
		local pathState = AvoidancePath.GetState(bot)
		local pathOwned = state.state == Controller.FOLLOWING_PATH
			or state.state == Controller.WAITING_PATH
		local pathContext = pathState.requestSignature ~= nil and pathState
			or pathState.lastPathSnapshot
		if pathOwned and pathContext ~= nil then
			local currentLocation = Safe(nil, function() return bot:GetLocation() end) or {}
			local waypoint = pathContext.activeWaypoint or {}
			local pathSource = pathState.requestSignature ~= nil and 'active' or 'invalidated'
			Log(bot, state, 'path-policy', 'path_reentry', string.format(
				'path_source=%s path_status=%s previous_path_generation=%s waypoint_index=%s '
					.. 'current_x=%.1f current_y=%.1f waypoint_x=%.1f waypoint_y=%.1f zones=%s',
				tostring(pathSource), tostring(pathContext.status), tostring(pathContext.generation),
				tostring(pathContext.waypointIndex or 0), currentLocation.x or 0,
				currentLocation.y or 0, waypoint.x or 0, waypoint.y or 0,
				FormatPathZones(containingZones, pathContext.requestZoneKeys, currentLocation)))
		end
		SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'inside_tower_zone')
		AvoidancePath.MarkNeedsRepath(bot, 'inside_tower_zone')
		local directMargin = math.max(tonumber(Config.PATH_CLEARANCE_TOLERANCE) or 0,
			tonumber(Config.DIRECT_EGRESS_SAFETY_MARGIN) or 0)
		local escapePoint = Geometry.FindDirectEscapePoint(bot:GetLocation(), anchor,
			geometryZones, directMargin, containingZones)
		if escapePoint ~= nil then return MoveDirect(bot, state, escapePoint, 'direct_egress') end
		-- 候选全部失败时不能再发一条未经检查的 anchor 穿塔命令。
		if anchor ~= nil and Geometry.ValidateMovementSegment(current, anchor, geometryZones, directMargin) then
			return MoveDirect(bot, state, anchor, 'direct_anchor_fallback')
		end
		if Now() - (state.lastNoSafeEgressLogAt or -90) >= 1.0 then
			state.lastNoSafeEgressLogAt = Now()
			Log(bot, state, 'path-policy', 'no_safe_egress_segment', 'new_order_issued=0')
		end
		return true
	end

	if anchor == nil then return false end
	if #movementRouteZones == 0 then
		local pathState = AvoidancePath.GetState(bot)
		if pathState.status == 'pending'
		or pathState.status == 'ready'
		or pathState.status == 'following'
		then
			-- 路线刚变清时必须先废弃旧 waypoint；否则旧的 escape_only 会与锚点命令交替拉扯。
			local previousPathGeneration = pathState.generation
			state.egressCommitActive = true
			state.routeClearSince = nil
			AvoidancePath.MarkNeedsRepath(bot, 'route_clear')
			Log(bot, state, 'path-policy', 'route_clear_invalidated',
				'previous_path_status=' .. tostring(pathState.status)
					.. ' previous_path_generation=' .. tostring(previousPathGeneration)
					.. ' next_path_generation=' .. tostring(bot.THD_TowerEscapeGeneration or 0))
		end
		-- 保留上一条向外命令，只有路线连续稳定后才允许 anchor 接管。
		if ShouldHoldRouteClearCommit(bot, state) then return true end
		if scan.triggered then
			SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'route_clear_danger_active')
		end
		return MoveDirect(bot, state, anchor, 'clear_route_anchor')
	end
	ResetRouteClearCommit(bot, state, 'route_intersection')

	local pathState = AvoidancePath.GetState(bot)
	if pathState.status ~= 'idle'
	and not AvoidancePath.IsRequestCurrent(bot, anchor, geometryZones)
	and not AvoidancePath.IsCurrentPathUsable(bot, anchor, geometryZones)
	then
		AvoidancePath.MarkNeedsRepath(bot, 'path_inputs_changed')
		pathState = AvoidancePath.GetState(bot)
	end
	if pathState.status == 'idle' or pathState.status == 'failed' or pathState.status == 'complete' then
		-- escape_only 会偏离原锚点直线，构造器也必须看到所有有效侧面塔区。
		AvoidancePath.Request(bot, bot:GetLocation(), anchor, geometryZones, 'runtime')
		LogMovementGeometry(bot, state, geometryZones, movementRouteZones, geometryAudit, true)
		pathState = AvoidancePath.GetState(bot)
	end
	if pathState.status == 'pending' then
		SetModeState(bot, state, Controller.WAITING_PATH, 'native_path_pending')
		local fallback = Geometry.BuildFallbackWaypoints(bot:GetLocation(), anchor, geometryZones,
			GetRouteSafetyMargin())
		if type(fallback) == 'table' and fallback[1] ~= nil then
			MoveDirect(bot, state, fallback[1], 'waiting_path_fallback')
		end
		AvoidancePath.Poll(bot)
		return true
	end

	pathState = AvoidancePath.GetState(bot)
	if pathState.status == 'ready' then
		if RejectUnsafePathSegment(bot, state, anchor, geometryZones, movementRouteZones, pathState) then
			return true
		end
		SetModeState(bot, state, Controller.FOLLOWING_PATH, 'path_ready')
		AvoidancePath.Execute(bot, 'runtime')
		return true
	elseif pathState.status == 'following' then
		if RejectUnsafePathSegment(bot, state, anchor, geometryZones, movementRouteZones, pathState) then
			return true
		end
		SetModeState(bot, state, Controller.FOLLOWING_PATH, 'path_following')
		AvoidancePath.Continue(bot)
		return true
	end
	-- 路径候选耗尽时继续远离相交塔圆，不允许直接穿圆冲向 anchor。
	local escapePoint = Geometry.FindDirectEscapePoint(bot:GetLocation(), anchor, geometryZones,
		GetRouteSafetyMargin(), movementRouteZones)
	if escapePoint ~= nil then
		return MoveDirect(bot, state, escapePoint, 'path_unavailable_egress')
	end
	return true
end

function Controller.Reset(bot, reason)
	if bot == nil then return end
	Clear(bot, GetState(bot), reason or 'manual_reset')
	if bot.THD_AvoidanceZoneState ~= nil then ZoneManager.Reset(bot, 'runtime') end
end

function Controller.GetSnapshot(bot)
	if bot == nil then return {active = false, state = Controller.IDLE} end
	local state = GetState(bot)
	local path = AvoidancePath.GetState(bot)
	return {
		active = state.active,
		state = state.state,
		startedAt = state.startedAt,
		clearanceSince = state.clearanceSince,
		routeClearSince = state.routeClearSince,
		egressCommitActive = state.egressCommitActive,
		handoffPending = state.handoffPending,
		handoffModeEnded = state.handoffModeEnded,
		handoffStartedAt = state.handoffStartedAt,
		handoffReleaseReason = state.handoffReleaseReason,
		handoffFallbackAllowed = state.handoffFallbackAllowed,
		handoffFallbackTarget = state.handoffFallbackTarget,
		handoffFallbackActionCount = state.handoffFallbackActionCount,
		handoffFallbackRetargetCount = state.handoffFallbackRetargetCount,
		generation = bot.THD_TowerEscapeGeneration or 0,
		reasons = state.lastReasons,
		anchor = state.lastAnchor,
		pathStatus = path.status,
		pathFailureReason = path.failureReason,
		directActionCount = state.actionCount or 0,
		pathActionCount = path.actionCount or 0,
	}
end

return Controller
