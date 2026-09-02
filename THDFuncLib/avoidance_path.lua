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

function AvoidancePath.ValidateCurrentSegment(bot, zones, margin)
	if bot == nil or bot.THD_AvoidancePathState == nil then
		return false, 'missing_path_state', nil
	end
	local state = GetState(bot)
	if state.status ~= 'ready' and state.status ~= 'following' then
		return false, 'path_not_executable', nil
	end
	local ok, current = pcall(function() return bot:GetLocation() end)
	if not ok or current == nil then return false, 'missing_current_location', nil end
	local waypointIndex = math.max(1, state.waypointIndex or 1)
	local target = state.waypoints and state.waypoints[waypointIndex] or nil
	if state.status == 'following' and not state.nativeExecution
	and target ~= nil and Geometry.Distance(current, target) <= 120
	then
		-- 与 Continue 同步只前进一个索引，确保复核的正是本帧可能下单的 waypoint。
		waypointIndex = waypointIndex + 1
		target = state.waypoints[waypointIndex]
	end
	local details = {
		current = current,
		target = target,
		waypointIndex = waypointIndex,
	}
	if target == nil then return true, 'complete', details end
	local safe, reason, zone = Geometry.ValidateMovementSegment(current, target, zones or {}, margin)
	details.zone = zone
	return safe, reason, details
end

local function NormalizeWaypoints(value)
	if type(value) ~= 'table' then return nil end
	local result = {}
	for _, rawWaypoint in ipairs(value) do
		local waypoint = type(rawWaypoint) == 'table' and (rawWaypoint.location or rawWaypoint) or rawWaypoint
		if waypoint ~= nil and waypoint.x ~= nil and waypoint.y ~= nil then
			table.insert(result, Geometry.MakeVector(waypoint.x, waypoint.y, waypoint.z or 0))
		end
	end
	if #result == 0 then return nil end
	return result
end

local function DecodeNativeCallback(...)
	local count = select('#', ...)
	local raw = {...}
	if count >= 3 and type(raw[1]) == 'number'
	and type(raw[2]) == 'number' and type(raw[3]) == 'table'
	then
		return raw[1], raw[2], raw[3], 'distance_request_waypoints'
	end
	if count >= 2 and type(raw[1]) == 'number' and type(raw[2]) == 'table' then
		return raw[1], nil, raw[2], 'distance_waypoints'
	end
	return raw[1], raw[2], raw[3], 'unsupported'
end

local function FinishWithWaypoints(bot, generation, distance, callbackRequestID, rawWaypoints, phase, contract)
	local state = GetState(bot)
	if generation ~= state.generation or state.pending == nil then
		Log(bot, phase, generation, 'GeneratePath', 'callback', 'result=stale_callback')
		return
	end
	if contract ~= 'distance_waypoints' and contract ~= 'distance_request_waypoints' then
		state.status = 'failed'
		state.failureReason = 'callback_contract_invalid'
		state.pending = nil
		Log(bot, phase, generation, 'GeneratePath', 'callback',
			'result=invalid reason=' .. tostring(state.failureReason)
			.. ' contract=' .. tostring(contract)
			.. ' expected_request=' .. tostring(state.nativeRequestID)
			.. ' callback_request=' .. tostring(callbackRequestID))
		return
	end
	if callbackRequestID ~= nil
	and (type(callbackRequestID) ~= 'number' or callbackRequestID ~= state.nativeRequestID)
	then
		state.status = 'failed'
		state.failureReason = 'callback_request_mismatch'
		state.pending = nil
		Log(bot, phase, generation, 'GeneratePath', 'callback',
			'result=invalid reason=' .. tostring(state.failureReason)
			.. ' contract=' .. tostring(contract)
			.. ' expected_request=' .. tostring(state.nativeRequestID)
			.. ' callback_request=' .. tostring(callbackRequestID))
		return
	end
	if type(distance) ~= 'number' or distance <= 0
	or type(rawWaypoints) ~= 'table' or #rawWaypoints == 0
	then
		state.status = 'failed'
		state.failureReason = 'pathfind_failed'
		state.pending = nil
		Log(bot, phase, generation, 'GeneratePath', 'callback',
			'result=invalid reason=' .. tostring(state.failureReason)
			.. ' distance=' .. tostring(distance)
			.. ' waypoint_count=' .. tostring(type(rawWaypoints) == 'table' and #rawWaypoints or -1))
		return
	end
	local waypoints = NormalizeWaypoints(rawWaypoints)
	local request = state.pending
	local valid, reason = Geometry.ValidatePath(request.start, waypoints, request.zones,
		Config.PATH_CLEARANCE_TOLERANCE)
	if not valid then
		state.status = 'failed'
		state.failureReason = reason or 'invalid_native_path'
		state.pending = nil
		Log(bot, phase, generation, 'GeneratePath', 'callback',
			'result=invalid distance_type=' .. type(distance) .. ' waypoint_type=' .. type(rawWaypoints)
			.. ' reason=' .. tostring(state.failureReason))
		return
	end
	state.status = 'ready'
	state.distance = distance
	state.waypoints = waypoints
	state.failureReason = nil
	state.pending = nil
	Log(bot, phase, generation, 'GeneratePath', 'callback',
		'result=ready distance=' .. tostring(distance) .. ' waypoint_count=' .. tostring(#waypoints))
end

local function BuildLuaFallback(bot, state, startLocation, destination, zones, phase)
	local routeMargin = math.max(0, tonumber(Config.LUA_ROUTE_SAFETY_MARGIN) or 0)
	local waypoints, reason = Geometry.BuildFallbackWaypoints(startLocation, destination, zones,
		routeMargin)
	if waypoints == nil then
		state.status = 'failed'
		state.failureReason = reason or 'lua_fallback_failed'
		state.waypoints = nil
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

function AvoidancePath.Request(bot, startLocation, destination, zones, phase)
	if bot == nil or startLocation == nil or destination == nil then return false, 'missing_argument' end
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

	if Config.USE_NATIVE_PATH ~= true or type(GeneratePath) ~= 'function' then
		state.pending = nil
		return BuildLuaFallback(bot, state, startLocation, destination, zones or {}, phase), 'lua_fallback'
	end

	local generation = state.generation
	local requestResolved = false
	local deferred = nil
	local callback = function(...)
		if not requestResolved then
			deferred = {count = select('#', ...), args = {...}}
			return
		end
		local distance, callbackRequestID, waypoints, contract = DecodeNativeCallback(...)
		FinishWithWaypoints(bot, generation, distance, callbackRequestID, waypoints,
			phase or 'runtime', contract)
	end
	Log(bot, phase, generation, 'GeneratePath', 'before-call',
		'explicit_zone_count=0 global_zones=registered')
	local ok, requestID = pcall(function()
		-- AddAvoidanceZone 的全局区域会被自动采用；整数句柄只供 Remove 使用。
		return GeneratePath(startLocation, destination, {}, callback)
	end)
	if not ok then
		Log(bot, phase, generation, 'GeneratePath', 'after-call',
			'result=lua-error error=' .. tostring(requestID))
		state.pending = nil
		return BuildLuaFallback(bot, state, startLocation, destination, zones or {}, phase), 'native_lua_error'
	end
	state.nativeRequestID = requestID
	Log(bot, phase, generation, 'GeneratePath', 'after-call',
		'result=returned request_type=' .. type(requestID) .. ' request=' .. tostring(requestID))
	if type(requestID) ~= 'number' then
		state.pending = nil
		return BuildLuaFallback(bot, state, startLocation, destination, zones or {}, phase),
			'native_request_not_number'
	end
	requestResolved = true
	if deferred ~= nil then
		callback(unpack(deferred.args, 1, deferred.count))
	end
	return true, 'native_pending'
end

function AvoidancePath.Poll(bot)
	if bot == nil then return 'idle', nil, 'missing_bot' end
	local state = GetState(bot)
	if state.status == 'pending' and state.pending ~= nil
	and Now() - state.pending.requestedAt >= Config.PATH_TIMEOUT
	then
		local request = state.pending
		state.pending = nil
		Log(bot, 'runtime', state.generation, 'GeneratePath', 'callback', 'result=timeout')
		BuildLuaFallback(bot, state, request.start, request.destination, request.zones, 'runtime')
	end
	return state.status, state.waypoints, state.failureReason
end

function AvoidancePath.Execute(bot, phase)
	if bot == nil then return false, 'missing_bot' end
	local state = GetState(bot)
	if state.status ~= 'ready' or type(state.waypoints) ~= 'table' or #state.waypoints == 0 then
		return false, 'path_not_ready'
	end
	local now = Now()
	if now - (state.lastExecuteAt or -90) < Config.NATIVE_ACTION_INTERVAL then
		return true, 'throttled'
	end
	state.lastExecuteAt = now
	if Config.EXECUTE_NATIVE_PATH == true and type(bot.Action_MovePath) == 'function' then
		Log(bot, phase, state.generation, 'Action_MovePath', 'before-call',
			'waypoint_count=' .. tostring(#state.waypoints))
		local ok, err = pcall(function() return bot:Action_MovePath(state.waypoints) end)
		if ok then
			state.actionCount = (state.actionCount or 0) + 1
			state.totalActionCount = (state.totalActionCount or 0) + 1
			Log(bot, phase, state.generation, 'Action_MovePath', 'after-call', 'result=returned')
			state.status = 'following'
			state.nativeExecution = true
			return true, 'native_path'
		end
		Log(bot, phase, state.generation, 'Action_MovePath', 'after-call',
			'result=lua-error error=' .. tostring(err))
	end
	if type(bot.Action_MoveToLocation) ~= 'function' then return false, 'move_unavailable' end
	state.waypointIndex = math.max(1, state.waypointIndex or 1)
	local target = state.waypoints[state.waypointIndex]
	bot:Action_MoveToLocation(target)
	state.actionCount = (state.actionCount or 0) + 1
	state.totalActionCount = (state.totalActionCount or 0) + 1
	Log(bot, phase, state.generation, 'none', 'execute', string.format(
		'action=MoveToLocation action_count=%d waypoint_index=%d target_x=%.1f target_y=%.1f',
		state.actionCount, state.waypointIndex, target.x or 0, target.y or 0))
	state.status = 'following'
	state.nativeExecution = false
	return true, 'waypoint_fallback'
end

function AvoidancePath.Continue(bot)
	if bot == nil then return false, 'missing_bot' end
	local state = GetState(bot)
	if state.status ~= 'following' then return false, 'not_following' end
	if state.nativeExecution then return true, 'native_following' end
	local target = state.waypoints and state.waypoints[state.waypointIndex or 1] or nil
	if target == nil then return false, 'missing_waypoint' end
	local location = bot:GetLocation()
	if Geometry.Distance(location, target) <= 120 then
		state.waypointIndex = (state.waypointIndex or 1) + 1
		target = state.waypoints[state.waypointIndex]
		if target == nil then
			state.status = 'complete'
			return true, 'complete'
		end
	end
	if Now() - (state.lastExecuteAt or -90) >= Config.NATIVE_ACTION_INTERVAL then
		state.lastExecuteAt = Now()
		bot:Action_MoveToLocation(target)
		state.actionCount = (state.actionCount or 0) + 1
		state.totalActionCount = (state.totalActionCount or 0) + 1
		Log(bot, 'runtime', state.generation, 'none', 'execute', string.format(
			'action=MoveToLocation action_count=%d waypoint_index=%d target_x=%.1f target_y=%.1f',
			state.actionCount, state.waypointIndex or 1, target.x or 0, target.y or 0))
	end
	return true, 'waypoint_following'
end

function AvoidancePath.MarkNeedsRepath(bot, reason)
	if bot == nil then return end
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
end

function AvoidancePath.GetState(bot)
	if bot == nil then return {status = 'idle', generation = 0} end
	local state = GetState(bot)
	local activeWaypoint = state.waypoints and state.waypoints[state.waypointIndex or 1] or nil
	return {
		status = state.status,
		generation = state.generation,
		failureReason = state.failureReason,
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
