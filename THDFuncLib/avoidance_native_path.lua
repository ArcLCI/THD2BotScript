local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Adapter = {}
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
	if bot.THD_AvoidanceNativePathState == nil then
		bot.THD_AvoidanceNativePathState = {generation = 0, status = 'idle'}
	end
	return bot.THD_AvoidanceNativePathState
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

function Adapter.Request(bot, generation, startLocation, destination, zones, phase)
	local state = GetState(bot)
	state.generation, state.status = generation, 'pending'
	state.waypoints, state.failureReason, state.nativeRequestID = nil, nil, nil
	state.pending = {requestedAt = Now(), start = startLocation, destination = destination, zones = zones}
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
		return false, 'native_lua_error'
	end
	state.nativeRequestID = requestID
	Log(bot, phase, generation, 'GeneratePath', 'after-call',
		'result=returned request_type=' .. type(requestID) .. ' request=' .. tostring(requestID))
	if type(requestID) ~= 'number' then
		state.pending = nil
		return false, 'native_request_not_number'
	end
	requestResolved = true
	if deferred ~= nil then
		callback(unpack(deferred.args, 1, deferred.count))
	end
	return true, 'native_pending'
end

function Adapter.Poll(bot)
	local state = GetState(bot)
	if state.status == 'pending' and state.pending ~= nil
	and Now() - state.pending.requestedAt >= Config.PATH_TIMEOUT then
		state.pending, state.status = nil, 'timeout'
		Log(bot, 'runtime', state.generation, 'GeneratePath', 'callback', 'result=timeout')
	end
	return state
end

function Adapter.Cancel(bot)
	-- 删除 pending，旧回调即使迟到也只能命中 stale_callback。
	local state = GetState(bot)
	state.pending, state.status = nil, 'idle'
end

function Adapter.Execute(bot, waypoints, generation, phase)
	if Config.EXECUTE_NATIVE_PATH ~= true or type(bot.Action_MovePath) ~= 'function' then return false end
	Log(bot, phase, generation, 'Action_MovePath', 'before-call', 'waypoint_count=' .. tostring(#waypoints))
	local ok, err = pcall(function() return bot:Action_MovePath(waypoints) end)
	Log(bot, phase, generation, 'Action_MovePath', 'after-call', ok and 'result=returned' or ('result=lua-error error=' .. tostring(err)))
	return ok
end

return Adapter
