local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')

local AvoidancePath = {}

-- 每个 Bot 只保留一个 generation；目标或塔区变化后晚到回调会被直接丢弃。

local function Now()
	if type(DotaTime) == 'function' then
		local ok, value = pcall(DotaTime)
		if ok and type(value) == 'number' then return value end
	end
	return 0
end

local function GetPlayerID(bot)
	local ok, value = pcall(function() return bot:GetPlayerID() end)
	return ok and value or -1
end

local function GetTeam(bot)
	local ok, value = pcall(function() return bot:GetTeam() end)
	return ok and value or -1
end

local function Log(bot, phase, generation, api, stage, extra)
	if api == 'none' and Config.DEBUG_LOG ~= true then return end
	print(string.format(
		'[BOT][AvoidanceDev] run=%s phase=%s team=%s player=%s generation=%s zone=path api=%s stage=%s game_time=%.3f %s',
		tostring(Config.RUN_ID or 'unset'), tostring(phase or 'runtime'), tostring(GetTeam(bot)),
		tostring(GetPlayerID(bot)), tostring(generation or 0), tostring(api), tostring(stage), Now(),
		tostring(extra or '')))
end

local function GetState(bot)
	if bot.THD_AvoidancePathState == nil then
		bot.THD_AvoidancePathState = {
			generation = 0,
			status = 'idle',
			pending = nil,
			waypoints = nil,
			failureReason = nil,
			distance = nil,
			nativeRequestID = nil,
			requestSignature = nil,
			requestZoneKeys = {},
			lastPathSnapshot = nil,
			lastExecuteAt = -90,
			waypointIndex = 1,
			nativeExecution = false,
			actionCount = 0,
			totalActionCount = 0,
			requestDestination = nil,
		}
	end
	return bot.THD_AvoidancePathState
end

local function Quantize(value)
	return math.floor((tonumber(value) or 0) / 16 + 0.5)
end

function AvoidancePath.MakeRequestSignature(destination, zones)
	if destination == nil then return 'destination:none' end
	local zoneParts = {}
	for _, zone in ipairs(zones or {}) do
		local center = zone.center or {}
		table.insert(zoneParts, string.format('%s:%d:%d:%d', tostring(zone.key or 'unknown'),
			Quantize(center.x), Quantize(center.y), Quantize(zone.effectiveRadius or zone.radius)))
	end
	table.sort(zoneParts)
	return string.format('destination:%d:%d|zones:%s', Quantize(destination.x),
		Quantize(destination.y), table.concat(zoneParts, ','))
end

function AvoidancePath.IsRequestCurrent(bot, destination, zones)
	if bot == nil or bot.THD_AvoidancePathState == nil then return false end
	return GetState(bot).requestSignature == AvoidancePath.MakeRequestSignature(destination, zones)
end

local function MakeZoneKeySet(zones)
	local result = {}
	for _, zone in ipairs(zones or {}) do
		result[tostring(zone.key or 'unknown')] = true
	end
	return result
end

local function FormatRequestZones(zones)
	local parts = {}
	local now = Now()
	for _, zone in ipairs(zones or {}) do
		local center = zone.center or {}
		table.insert(parts, string.format('%s@%.0f,%.0f:r%.0f:age=%.3f',
			tostring(zone.key or 'unknown'), center.x or 0, center.y or 0,
			zone.effectiveRadius or zone.radius or 0, math.max(0, now - (zone.lastSeenAt or now))))
	end
	return #parts > 0 and table.concat(parts, '|') or 'none'
end

function AvoidancePath.RequestIncludesZone(bot, key)
	if bot == nil or bot.THD_AvoidancePathState == nil then return false end
	local keys = GetState(bot).requestZoneKeys or {}
	return keys[tostring(key or 'unknown')] == true
end

function AvoidancePath.IsCurrentPathUsable(bot, destination, zones)
	if bot == nil or destination == nil or bot.THD_AvoidancePathState == nil then return false end
	local state = GetState(bot)
	if state.status ~= 'ready' and state.status ~= 'following' then return false end
	if state.requestDestination == nil
		or Geometry.Distance(state.requestDestination, destination) > 80
	then
		return false
	end
	local ok, current = pcall(function() return bot:GetLocation() end)
	if not ok or current == nil then return false end
	local remaining = {}
	local firstIndex = state.status == 'following' and math.max(1, state.waypointIndex or 1) or 1
	for index = firstIndex, #(state.waypoints or {}) do
		table.insert(remaining, state.waypoints[index])
	end
	if #remaining == 0 then return false end
	return Geometry.ValidatePath(current, remaining, zones or {}, Config.PATH_CLEARANCE_TOLERANCE)
end

local function SelectNextWaypoint(state, current)
	local index = math.max(1, state.waypointIndex or 1)
	local target = state.waypoints and state.waypoints[index] or nil
	if state.status == 'following' and not state.nativeExecution
	and target ~= nil and Geometry.Distance(current, target) <= 120 then
		index = index + 1
		target = state.waypoints[index]
	end
	return index, target
end

function AvoidancePath.ValidateCurrentSegment(bot, zones, margin)
	if bot == nil or bot.THD_AvoidancePathState == nil then
		return false, 'missing_path_state', nil
	end
	local state = GetState(bot)
	state.executionZones, state.executionMargin = zones, margin
	if state.status ~= 'ready' and state.status ~= 'following' then
		return false, 'path_not_executable', nil
	end
	local ok, current = pcall(function() return bot:GetLocation() end)
	if not ok or current == nil then return false, 'missing_current_location', nil end
	local waypointIndex, target = SelectNextWaypoint(state, current)
	local details = {
		current = current,
		target = target,
		waypointIndex = waypointIndex,
	}
	if target == nil then return true, 'complete', details end
	local safe, reason, zone = Geometry.ValidateMovementSegment(current, target, zones or {}, margin)
	details.zone = zone
	if safe then safe, reason = Geometry.ValidateLocalTerrainSegment(current, target, false) end
	return safe, reason, details
end

local Native
local function NativeAdapter()
	if Native == nil and (Config.USE_NATIVE_PATH or Config.EXECUTE_NATIVE_PATH) then
		Native = require(GetScriptDirectory()..'/THDFuncLib/avoidance_native_path')
	end
	return Native
end

local function RecordFailure(state)
	state.failedAttempts = math.min(Config.PATH_FAILURE_MAX_ATTEMPTS, (state.failedAttempts or 0) + 1)
	state.nextRetryAt = Now() + Config.PATH_FAILURE_RETRY_TIME * (2 ^ (state.failedAttempts - 1))
end

function AvoidancePath.NoteExecutionFailure(bot, reason)
	local state = GetState(bot)
	-- 构造成功但地形/实际线段不可执行也消耗同一预算，不能逐帧重建同一条坏路线。
	RecordFailure(state)
	Log(bot, 'runtime', state.generation, 'none', 'request-policy', string.format(
		'result=execution_failed reason=%s failed_attempts=%d next_retry_at=%.3f',
		tostring(reason), state.failedAttempts, state.nextRetryAt))
end

local function BuildLuaFallback(bot, state, startLocation, destination, zones, phase)
	local routeMargin = math.max(0, tonumber(Config.LUA_ROUTE_SAFETY_MARGIN) or 0)
	local waypoints, reason = Geometry.BuildFallbackWaypoints(startLocation, destination, zones,
		routeMargin)
	if waypoints == nil then
		state.status = 'failed'
		state.failureReason = reason or 'lua_fallback_failed'
		state.waypoints = nil
		RecordFailure(state)
		Log(bot, phase, state.generation, 'none', 'fallback', string.format(
			'result=lua_path_failed reason=%s failed_attempts=%d next_retry_at=%.3f exhausted=%d',
			tostring(state.failureReason), state.failedAttempts, state.nextRetryAt,
			state.failedAttempts >= Config.PATH_FAILURE_MAX_ATTEMPTS and 1 or 0))
		return false
	end
	state.status = 'ready'
	state.failureReason = nil
	state.waypoints = waypoints
	state.distance = nil
	Log(bot, phase, state.generation, 'none', 'fallback', string.format(
		'result=lua_path reason=%s waypoint_count=%d route_margin=%.1f start_x=%.1f start_y=%.1f destination_x=%.1f destination_y=%.1f',
		tostring(reason), #waypoints, routeMargin, startLocation.x or 0, startLocation.y or 0,
		destination.x or 0, destination.y or 0))
	return true
end

function AvoidancePath.CanRequest(bot, startLocation, destination, zones)
	local state = GetState(bot)
	local signature = AvoidancePath.MakeRequestSignature(destination, zones)
	if state.retrySignature ~= signature or state.retryOrigin == nil
	or Geometry.Distance(startLocation, state.retryOrigin) >= Config.RECOVERY_PROGRESS_DISTANCE then
		state.retrySignature = signature
		state.retryOrigin = Geometry.MakeVector(startLocation.x, startLocation.y, startLocation.z)
		state.failedAttempts, state.nextRetryAt = 0, -90
	end
	local reason = (state.failedAttempts or 0) >= Config.PATH_FAILURE_MAX_ATTEMPTS and 'retry_exhausted'
		or (Now() < (state.nextRetryAt or -90) and 'retry_backoff' or nil)
	if reason ~= nil and Now() - (state.lastRetryLogAt or -90) >= 1.0 then
		state.lastRetryLogAt = Now()
		Log(bot, 'runtime', state.generation, 'none', 'request-policy', string.format(
			'result=%s failed_attempts=%d next_retry_at=%.3f', reason, state.failedAttempts, state.nextRetryAt))
	end
	return reason == nil, reason
end

function AvoidancePath.Request(bot, startLocation, destination, zones, phase)
	if bot == nil or startLocation == nil or destination == nil then return false, 'missing_argument' end
	local allowed, reason = AvoidancePath.CanRequest(bot, startLocation, destination, zones)
	if not allowed then return false, reason end
	local state = GetState(bot)
	state.generation = state.generation + 1
	bot.THD_TowerEscapeGeneration = state.generation
	state.status = 'pending'
	state.waypoints = nil
	state.failureReason = nil
	state.distance = nil
	state.nativeRequestID = nil
	state.waypointIndex = 1
	state.nativeExecution = false
	state.actionCount = 0
	state.totalActionCount = state.totalActionCount or 0
	state.requestDestination = Geometry.MakeVector(destination.x or 0, destination.y or 0,
		destination.z or 0)
	state.requestSignature = AvoidancePath.MakeRequestSignature(destination, zones)
	state.requestZoneKeys = MakeZoneKeySet(zones)
	state.executionZones, state.executionMargin = zones or {}, Config.LUA_ROUTE_SAFETY_MARGIN
	state.pending = {
		generation = state.generation,
		requestedAt = Now(),
		start = startLocation,
		destination = destination,
		zones = zones or {},
	}
	-- 按路径代数记录真正送入构造器的完整集合，不能从后来的重入反推当时视野。
	Log(bot, phase, state.generation, 'none', 'request', string.format(
		'result=created zone_count=%d zones=%s start_x=%.1f start_y=%.1f destination_x=%.1f destination_y=%.1f',
		#(zones or {}), FormatRequestZones(zones), startLocation.x or 0, startLocation.y or 0,
		destination.x or 0, destination.y or 0))

	local adapter = NativeAdapter()
	if Config.USE_NATIVE_PATH == true and adapter ~= nil then
		local accepted, nativeReason = adapter.Request(bot, state.generation, startLocation, destination, zones or {}, phase)
		if accepted then return true, nativeReason end
	end
	state.pending = nil
	return BuildLuaFallback(bot, state, startLocation, destination, zones or {}, phase), 'lua_fallback'
end

function AvoidancePath.Poll(bot)
	if bot == nil then return 'idle', nil, 'missing_bot' end
	local state = GetState(bot)
	if state.status == 'pending' and Native ~= nil then
		local result = Native.Poll(bot)
		if result.generation == state.generation then
			state.nativeRequestID = result.nativeRequestID
			if result.status == 'timeout' then
				local request = state.pending
				state.pending = nil
				BuildLuaFallback(bot, state, request.start, request.destination, request.zones, 'runtime')
			elseif result.status == 'ready' or result.status == 'failed' then
				state.status, state.waypoints = result.status, result.waypoints
				state.distance, state.failureReason = result.distance, result.failureReason
				state.pending = nil
			end
		end
	end
	return state.status, state.waypoints, state.failureReason
end

local function Advance(bot, phase)
	local state = GetState(bot)
	if state.nativeExecution then return true, 'native_following' end
	if state.waypoints == nil or state.waypoints[state.waypointIndex or 1] == nil then
		return false, 'missing_waypoint'
	end
	local safe, reason, details = AvoidancePath.ValidateCurrentSegment(bot, state.executionZones or {},
		state.executionMargin or Config.LUA_ROUTE_SAFETY_MARGIN)
	if not safe then return false, reason end
	local index, target = details.waypointIndex, details.target
	if target == nil then state.status = 'complete'; return true, 'complete' end
	-- 校验和执行使用同一选择结果；仍由控制器提供本帧完整几何及拒绝后的恢复策略。
	state.waypointIndex = index
	if Now() - (state.lastExecuteAt or -90) < Config.NATIVE_ACTION_INTERVAL then return true, 'throttled' end
	local adapter = NativeAdapter()
	local native = state.status == 'ready' and adapter ~= nil
		and adapter.Execute(bot, state.waypoints, state.generation, phase)
	if not native then
		if type(bot.Action_MoveToLocation) ~= 'function' then return false, 'move_unavailable' end
		local accepted,issued=Actions.Move(bot,target,24,'move',false,'path_'..tostring(state.generation))
		if not accepted then return false,'action_protected' end
		if not issued then return true,'reused' end
		bot.THD_AvoidanceOwnedMove = {target = target, generation = state.generation}
	end
	state.lastExecuteAt = Now()
	state.actionCount = (state.actionCount or 0) + 1
	state.totalActionCount = (state.totalActionCount or 0) + 1
	state.status, state.nativeExecution = 'following', native == true
	if not native then
		Log(bot, phase, state.generation, 'none', 'execute', string.format(
			'action=MoveToLocation action_count=%d waypoint_index=%d target_x=%.1f target_y=%.1f',
			state.actionCount, index, target.x or 0, target.y or 0))
	end
	return true, native and 'native_path' or 'waypoint_following'
end

function AvoidancePath.Execute(bot, phase)
	if bot == nil then return false, 'missing_bot' end
	local state = GetState(bot)
	if state.status ~= 'ready' or type(state.waypoints) ~= 'table' or #state.waypoints == 0 then
		return false, 'path_not_ready'
	end
	local ok, reason = Advance(bot, phase)
	return ok, reason == 'waypoint_following' and 'waypoint_fallback' or reason
end

function AvoidancePath.Continue(bot)
	if bot == nil then return false, 'missing_bot' end
	if GetState(bot).status ~= 'following' then return false, 'not_following' end
	local ok, reason = Advance(bot, 'runtime')
	return ok, reason == 'throttled' and 'waypoint_following' or reason
end

function AvoidancePath.MarkNeedsRepath(bot, reason)
	if bot == nil then return end
	if Native ~= nil then Native.Cancel(bot) end
	local state = GetState(bot)
	local invalidated = state.requestSignature ~= nil or state.status ~= 'idle'
	if invalidated then
		state.lastPathSnapshot = {
			status = state.status,
			generation = state.generation,
			requestSignature = state.requestSignature,
			requestZoneKeys = state.requestZoneKeys or {},
			waypointIndex = state.waypointIndex,
			activeWaypoint = state.waypoints and state.waypoints[state.waypointIndex or 1] or nil,
		}
		state.generation = state.generation + 1
		bot.THD_TowerEscapeGeneration = state.generation
		Log(bot, 'runtime', state.generation, 'none', 'repath',
			'result=invalidated reason=' .. tostring(reason or 'unknown'))
	end
	state.status = 'idle'
	state.pending = nil
	state.waypoints = nil
	state.failureReason = reason
	state.requestSignature = nil
	state.requestZoneKeys = {}
	state.requestDestination = nil
end

function AvoidancePath.Cancel(bot, reason)
	if bot == nil then return end
	if Native ~= nil then Native.Cancel(bot) end
	local state = GetState(bot)
	state.generation = state.generation + 1
	bot.THD_TowerEscapeGeneration = state.generation
	state.status = 'idle'
	state.pending = nil
	state.waypoints = nil
	state.failureReason = reason
	state.distance = nil
	state.nativeRequestID = nil
	state.requestSignature = nil
	state.requestZoneKeys = {}
	state.lastPathSnapshot = nil
	state.waypointIndex = 1
	state.nativeExecution = false
	state.actionCount = 0
	state.totalActionCount = 0
	state.requestDestination = nil
	state.retrySignature, state.retryOrigin = nil, nil
	state.failedAttempts, state.nextRetryAt = 0, -90
end

function AvoidancePath.GetState(bot)
	if bot == nil then return {status = 'idle', generation = 0} end
	local state = GetState(bot)
	local activeWaypoint = state.waypoints and state.waypoints[state.waypointIndex or 1] or nil
	return {
		status = state.status,
		generation = state.generation,
		failureReason = state.failureReason,
		failedAttempts = state.failedAttempts or 0,
		nextRetryAt = state.nextRetryAt,
		nativeRequestID = state.nativeRequestID,
		requestSignature = state.requestSignature,
		requestZoneKeys = state.requestZoneKeys or {},
		lastPathSnapshot = state.lastPathSnapshot,
		activeWaypoint = activeWaypoint,
		waypointCount = type(state.waypoints) == 'table' and #state.waypoints or 0,
		waypointIndex = state.waypointIndex,
		nativeExecution = state.nativeExecution,
		actionCount = state.actionCount,
		totalActionCount = state.totalActionCount,
	}
end

return AvoidancePath
