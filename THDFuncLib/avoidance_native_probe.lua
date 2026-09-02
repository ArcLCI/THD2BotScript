local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')

local Probe = {}

-- P0E–P5 每次只开放当前阶段所需的一个新原生能力，仓库默认永远关闭。

local states = {}

local function Now()
	local ok, value = pcall(DotaTime)
	return ok and type(value) == 'number' and value or 0
end

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if not ok or value == nil then return defaultValue end
	return value
end

local function GetPlayerID(bot)
	return Safe(-1, function() return bot:GetPlayerID() end)
end

local function GetState(bot)
	local playerID = GetPlayerID(bot)
	if states[playerID] == nil then
		states[playerID] = {
			status = 'idle', step = 0, startedAt = nil, handle = nil,
			secondHandle = nil, requestID = nil, waypoints = nil,
			actionCount = 0, minClearance = math.huge,
			phase = tonumber(Config.PROBE_PHASE) or 0,
		}
	end
	return states[playerID]
end

local function GetFirstBotPlayerID(team)
	local players = Safe({}, function() return GetTeamPlayers(team) end) or {}
	for _, playerID in ipairs(players) do
		if Safe(false, function() return IsPlayerBot(playerID) end) then return playerID end
	end
	return nil
end

local function IsTargetBot(bot)
	if bot == nil then return false end
	local team = Safe(-1, function() return bot:GetTeam() end)
	-- 生产逃生可开放双方；高风险原生探针必须保留独立的单队门禁并在缺失时关闭。
	local targetTeam = Config.PROBE_TARGET_TEAM or Config.TARGET_TEAM
	if targetTeam == nil or team ~= targetTeam then return false end
	return GetPlayerID(bot) == GetFirstBotPlayerID(team)
end

local function IsSafeProbeLocation(bot)
	if Safe(false, function() return bot:HasModifier('modifier_fountain_aura_buff') end) then return true end
	return Safe(math.huge, function() return bot:DistanceFromFountain() end) <= 1500
end

local function Log(bot, api, stage, extra)
	local state = GetState(bot)
	print(string.format(
		'[BOT][AvoidanceDev] run=%s phase=P%s team=%s player=%s generation=0 zone=probe-%s api=%s stage=%s %s',
		tostring(Config.RUN_ID or 'unset'), state.phase == 0 and '0E' or tostring(state.phase),
		tostring(Safe(-1, function() return bot:GetTeam() end)), tostring(GetPlayerID(bot)),
		tostring(state.phase), tostring(api), tostring(stage), tostring(extra or '')))
end

local function BuildScenario(bot)
	local startLocation = bot:GetLocation()
	local ancient = Safe(nil, function() return GetAncient(bot:GetTeam()) end)
	local destination = ancient ~= nil and Safe(nil, function() return ancient:GetLocation() end) or nil
	if destination == nil then
		destination = Geometry.MakeVector((startLocation.x or 0) + 1200, startLocation.y or 0, startLocation.z or 0)
	end
	local dx = (destination.x or 0) - (startLocation.x or 0)
	local dy = (destination.y or 0) - (startLocation.y or 0)
	local length = math.max(1, math.sqrt(dx * dx + dy * dy))
	destination = Geometry.MakeVector(
		(startLocation.x or 0) + dx / length * 1200,
		(startLocation.y or 0) + dy / length * 1200,
		startLocation.z or destination.z or 0)
	local center = Geometry.MakeVector(
		((startLocation.x or 0) + (destination.x or 0)) / 2,
		((startLocation.y or 0) + (destination.y or 0)) / 2,
		startLocation.z or 0)
	return startLocation, destination, center, 260
end

local function BuildOpenPathScenario()
	-- P4 不移动 Bot，因此用中路开阔区域隔离验证圆区是否真正影响 GeneratePath。
	local candidates = {
		{-4200, -3800, -1800, -1400},
		{-3600, -3200, -1200, -800},
		{-3000, -2600, -600, -200},
	}
	for _, candidate in ipairs(candidates) do
		local startLocation = Geometry.MakeVector(candidate[1], candidate[2], 0)
		local destination = Geometry.MakeVector(candidate[3], candidate[4], 0)
		local startPassable = Safe(false, function() return IsLocationPassable(startLocation) end)
		local destinationPassable = Safe(false, function() return IsLocationPassable(destination) end)
		if startPassable and destinationPassable then
			return startLocation, destination, 360
		end
	end
	return nil, nil, 360
end

local function AddZone(bot, center, radius, duration, label)
	local vector = Geometry.MakeVector(center.x or 0, center.y or 0, radius)
	Log(bot, 'AddAvoidanceZone', 'before-call', string.format(
		'label=%s center_x=%.1f center_y=%.1f radius=%.1f duration=%.2f',
		tostring(label), center.x or 0, center.y or 0, radius, duration))
	local ok, handle = pcall(function() return AddAvoidanceZone(vector, duration) end)
	if not ok then
		Log(bot, 'AddAvoidanceZone', 'after-call', 'result=lua-error error=' .. tostring(handle))
		return nil
	end
	Log(bot, 'AddAvoidanceZone', 'after-call',
		'result=returned handle_type=' .. type(handle) .. ' handle=' .. tostring(handle))
	return type(handle) == 'number' and handle or nil
end

local function RemoveZone(bot, handle, label)
	Log(bot, 'RemoveAvoidanceZone', 'before-call',
		'label=' .. tostring(label) .. ' handle=' .. tostring(handle))
	local ok, err = pcall(function() return RemoveAvoidanceZone(handle) end)
	if not ok then
		Log(bot, 'RemoveAvoidanceZone', 'after-call', 'result=lua-error error=' .. tostring(err))
		return false
	end
	Log(bot, 'RemoveAvoidanceZone', 'after-call', 'result=returned label=' .. tostring(label))
	return true
end

local function DescribeWaypoints(waypoints)
	if type(waypoints) ~= 'table' then return '' end
	local parts = {}
	local limit = math.min(#waypoints, 12)
	for i = 1, limit do
		local waypoint = waypoints[i]
		local x = Safe(nil, function() return waypoint.x end)
		local y = Safe(nil, function() return waypoint.y end)
		local z = Safe(nil, function() return waypoint.z end)
		parts[#parts + 1] = string.format(
			'waypoint_%d_type=%s waypoint_%d_x=%s waypoint_%d_y=%s waypoint_%d_z=%s',
			i, type(waypoint), i, tostring(x), i, tostring(y), i, tostring(z))
	end
	if #waypoints > limit then parts[#parts + 1] = 'waypoints_truncated=' .. tostring(#waypoints - limit) end
	return table.concat(parts, ' ')
end

local function DescribeCallbackArgs(...)
	local parts = {}
	local count = select('#', ...)
	for i = 1, count do
		local value = select(i, ...)
		local valueType = type(value)
		parts[#parts + 1] = string.format('arg_%d_type=%s', i, valueType)
		if valueType == 'number' or valueType == 'string' or valueType == 'boolean' then
			parts[#parts + 1] = string.format('arg_%d_value=%s', i, tostring(value))
		elseif valueType == 'table' or valueType == 'userdata' then
			local x = Safe(nil, function() return value.x end)
			local y = Safe(nil, function() return value.y end)
			local z = Safe(nil, function() return value.z end)
			if type(x) == 'number' or type(y) == 'number' or type(z) == 'number' then
				parts[#parts + 1] = string.format(
					'arg_%d_x=%s arg_%d_y=%s arg_%d_z=%s',
					i, tostring(x), i, tostring(y), i, tostring(z))
			elseif valueType == 'table' then
				parts[#parts + 1] = string.format('arg_%d_count=%d %s',
					i, #value, DescribeWaypoints(value))
			end
		end
	end
	return count, table.concat(parts, ' ')
end

local function DecodeCallbackArgs(rawArgs, argCount)
	if type(rawArgs) ~= 'table' or type(argCount) ~= 'number' then
		return nil, nil, nil, 'invalid_raw_args'
	end
	if argCount >= 3 and type(rawArgs[1]) == 'number'
	and type(rawArgs[2]) == 'number' and type(rawArgs[3]) == 'table'
	then
		return rawArgs[1], rawArgs[2], rawArgs[3], 'distance_request_waypoints'
	end
	if argCount >= 2 and type(rawArgs[1]) == 'number' and type(rawArgs[2]) == 'table' then
		return rawArgs[1], nil, rawArgs[2], 'distance_waypoints'
	end
	return rawArgs[1], rawArgs[2], rawArgs[3], 'unsupported'
end

local function Generate(bot, startLocation, destination, explicitZones, label, callback)
	local requestedAt = Now()
	local requestID = nil
	local requestResolved = false
	local deferred = nil
	Log(bot, 'GeneratePath', 'before-call',
		'label=' .. tostring(label) .. ' explicit_zone_count=' .. tostring(#(explicitZones or {})))
	local function Dispatch(latency, ...)
		local argCount, argDescription = DescribeCallbackArgs(...)
		local rawArgs = {...}
		local distance, callbackRequestID, waypoints, contract = DecodeCallbackArgs(rawArgs, argCount)
		Log(bot, 'GeneratePath', 'callback',
			'label=' .. tostring(label) .. ' distance_type=' .. type(distance)
			.. ' distance=' .. tostring(distance)
			.. ' callback_request_type=' .. type(callbackRequestID)
			.. ' callback_request=' .. tostring(callbackRequestID)
			.. ' waypoint_type=' .. type(waypoints)
			.. ' waypoint_count=' .. tostring(type(waypoints) == 'table' and #waypoints or -1)
			.. ' contract=' .. tostring(contract)
			.. string.format(' latency=%.3f raw_arg_count=%d ', latency, argCount)
			.. argDescription)
		callback(distance, waypoints, latency, rawArgs, argCount,
			callbackRequestID, contract, requestID)
	end
	local function NativeCallback(...)
		local latency = math.max(0, Now() - requestedAt)
		if not requestResolved then
			deferred = {latency = latency, count = select('#', ...), args = {...}}
			return
		end
		Dispatch(latency, ...)
	end
	local ok
	ok, requestID = pcall(function()
		return GeneratePath(startLocation, destination, explicitZones or {}, NativeCallback)
	end)
	if not ok then
		Log(bot, 'GeneratePath', 'after-call', 'result=lua-error error=' .. tostring(requestID))
		return nil
	end
	Log(bot, 'GeneratePath', 'after-call',
		'result=returned request_type=' .. type(requestID) .. ' request=' .. tostring(requestID))
	requestResolved = true
	if deferred ~= nil then
		Dispatch(deferred.latency, unpack(deferred.args, 1, deferred.count))
	end
	return requestID
end

function Probe.OnModeLoaded(bot)
	if not Config.IsAnyProbeEnabled() or not IsTargetBot(bot) then return false end
	local state = GetState(bot)
	if state.status ~= 'idle' then return false end
	state.status = 'loaded'
	state.startedAt = Now()
	Log(bot, 'none', 'loaded', 'result=mode_file_loaded')
	return true
end

function Probe.IsEnabled()
	return Config.IsAnyProbeEnabled()
end

function Probe.GetDesire(bot)
	if not Probe.IsEnabled() or not IsTargetBot(bot) or not IsSafeProbeLocation(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	local state = GetState(bot)
	if state.status == 'complete' or state.status == 'failed' then return BOT_MODE_DESIRE_NONE end
	if state.status == 'idle' then Probe.OnModeLoaded(bot) end
	if state.phase == 0 then bot.THD_AvoidanceModeLoadProbeActive = true end
	if state.phase == 5 then bot.THD_TowerEscapeActive = true end
	return BOT_MODE_DESIRE_ABSOLUTE
end

function Probe.OnStart(bot)
	if not Probe.IsEnabled() or not IsTargetBot(bot) then return end
	Log(bot, 'none', 'selected', 'result=evasive_mode_selected')
end

local function Complete(bot, result)
	local state = GetState(bot)
	state.status = 'complete'
	if state.phase == 0 then bot.THD_AvoidanceModeLoadProbeActive = false end
	if state.phase == 5 then bot.THD_TowerEscapeActive = false end
	Log(bot, 'none', 'complete', 'result=' .. tostring(result or 'passed'))
end

local function Fail(bot, reason)
	local state = GetState(bot)
	state.status = 'failed'
	if state.phase == 0 then bot.THD_AvoidanceModeLoadProbeActive = false end
	if state.phase == 5 then bot.THD_TowerEscapeActive = false end
	Log(bot, 'none', 'complete', 'result=failed reason=' .. tostring(reason))
end

local function ThinkPhaseOne(bot, state)
	if state.step == 0 then
		local _, _, center, radius = BuildScenario(bot)
		state.handle = AddZone(bot, center, radius, Config.NATIVE_ZONE_TTL, 'natural-expiry')
		if state.handle == nil then return Fail(bot, 'add_failed') end
		state.step = 1
		state.startedAt = Now()
	elseif state.step == 1 and Now() - state.startedAt >= Config.NATIVE_ZONE_TTL + 0.25 then
		Complete(bot, 'add_returned_and_ttl_elapsed')
	end
end

local function ThinkPhaseTwo(bot, state)
	local _, _, center, radius = BuildScenario(bot)
	if state.step == 0 then
		state.handle = AddZone(bot, center, radius, Config.NATIVE_ZONE_TTL, 'short-natural-expiry')
		if state.handle == nil then return Fail(bot, 'short_add_failed') end
		state.startedAt = Now()
		state.step = 1
	elseif state.step == 1 and Now() - state.startedAt >= Config.NATIVE_ZONE_TTL + 0.25 then
		Log(bot, 'none', 'complete', 'result=lua_ttl_elapsed label=short-natural-expiry')
		state.secondHandle = AddZone(bot, center, radius, 10.0, 'manual-remove')
		if state.secondHandle == nil then return Fail(bot, 'remove_add_failed') end
		state.startedAt = Now()
		state.step = 2
	elseif state.step == 2 and Now() - state.startedAt >= 1.0 then
		if not RemoveZone(bot, state.secondHandle, 'manual-remove') then return Fail(bot, 'remove_failed') end
		Complete(bot, 'ttl_and_remove_returned')
	end
end

local function SubmitPhaseThreeRequest(bot, state, sequence)
	local timeout = tonumber(Config.PATH_TIMEOUT) or 0.25
	local startLocation, destination = BuildScenario(bot)
	state.step = sequence == 1 and 1 or 3
	state.startedAt = Now()
	local label = 'empty-zones-' .. tostring(sequence)
	state.requestID = Generate(bot, startLocation, destination, {}, label,
	function(distance, waypoints, latency, rawArgs, argCount, callbackRequestID, contract, expectedRequestID)
		if state.status == 'complete' or state.status == 'failed' then
			Log(bot, 'GeneratePath', 'fallback',
				string.format('result=late_callback_ignored latency=%.3f', latency or -1))
			return
		end
		if type(latency) ~= 'number' or latency > timeout then
			return Fail(bot, 'callback_late latency=' .. tostring(latency))
		end
		if type(distance) ~= 'number' or type(rawArgs) ~= 'table' or type(argCount) ~= 'number'
		or (contract ~= 'distance_waypoints' and contract ~= 'distance_request_waypoints')
		or type(waypoints) ~= 'table'
		then
			return Fail(bot, 'callback_contract_invalid')
		end
		if distance <= 0 or #waypoints == 0 then return Fail(bot, 'pathfind_failed') end
		if callbackRequestID ~= nil
		and (type(callbackRequestID) ~= 'number' or type(expectedRequestID) ~= 'number'
			or callbackRequestID ~= expectedRequestID)
		then
			return Fail(bot, 'callback_request_mismatch')
		end
		if sequence == 1 then
			state.firstRequestID = expectedRequestID
			state.step = 2
			state.startedAt = Now()
			Log(bot, 'none', 'complete', 'result=first_callback_normalized request='
				.. tostring(expectedRequestID) .. ' callback_contract=' .. tostring(contract)
				.. ' token_present=' .. tostring(callbackRequestID ~= nil)
				.. ' waypoint_count=' .. tostring(#waypoints))
			return
		end
		Complete(bot, 'two_empty_zone_callbacks first_request=' .. tostring(state.firstRequestID)
			.. ' second_request=' .. tostring(expectedRequestID)
			.. ' token_reused=' .. tostring(expectedRequestID == state.firstRequestID)
			.. ' callback_contract=' .. tostring(contract)
			.. ' token_present=' .. tostring(callbackRequestID ~= nil)
			.. ' waypoint_count=' .. tostring(#waypoints))
	end)
	if type(state.requestID) ~= 'number' then Fail(bot, 'generate_request_not_number') end
end

local function ThinkPhaseThree(bot, state)
	local timeout = tonumber(Config.PATH_TIMEOUT) or 0.25
	if state.step == 0 then
		SubmitPhaseThreeRequest(bot, state, 1)
	elseif state.step == 2 then
		SubmitPhaseThreeRequest(bot, state, 2)
	elseif (state.step == 1 or state.step == 3) and Now() - state.startedAt >= timeout then
		Fail(bot, string.format('callback_timeout elapsed=%.3f', Now() - state.startedAt))
	end
end

local function BuildMidPathZone(startLocation, waypoints, radius)
	if startLocation == nil or type(waypoints) ~= 'table' or #waypoints == 0 then return nil end
	local totalDistance = 0
	local previous = startLocation
	for _, waypoint in ipairs(waypoints) do
		totalDistance = totalDistance + Geometry.Distance(previous, waypoint)
		previous = waypoint
	end
	if totalDistance <= (radius + 64) * 2 then return nil end
	local targetDistance = totalDistance * 0.5
	local traversed = 0
	previous = startLocation
	for _, waypoint in ipairs(waypoints) do
		local segmentLength = Geometry.Distance(previous, waypoint)
		if traversed + segmentLength >= targetDistance and segmentLength > 0 then
			local ratio = (targetDistance - traversed) / segmentLength
			return Geometry.MakeVector(
				(previous.x or 0) + ((waypoint.x or 0) - (previous.x or 0)) * ratio,
				(previous.y or 0) + ((waypoint.y or 0) - (previous.y or 0)) * ratio,
				(previous.z or 0) + ((waypoint.z or 0) - (previous.z or 0)) * ratio)
		end
		traversed = traversed + segmentLength
		previous = waypoint
	end
	return nil
end

local function ThinkPhaseFourOrFive(bot, state, execute)
	if state.step ~= 0 then
		if execute and state.step == 3 then
			local distance = Geometry.Distance(bot:GetLocation(), state.destination)
			local clearance = Geometry.Distance(bot:GetLocation(), state.zoneCenter)
			state.trajectorySamples = (state.trajectorySamples or 0) + 1
			state.minClearance = math.min(state.minClearance or math.huge, clearance)
			if distance <= (state.initialMoveDistance or distance) - 32 then state.progressMade = true end
			if clearance < state.zoneRadius - Config.PATH_CLEARANCE_TOLERANCE then
				return Fail(bot, 'executed_trajectory_inside_zone')
			end
			if distance <= 180 then
				if state.progressMade ~= true then return Fail(bot, 'move_path_no_progress') end
				return Complete(bot, 'move_path_arrived path_source=' .. tostring(state.pathSource)
					.. ' min_clearance=' .. tostring(state.minClearance)
					.. ' trajectory_samples=' .. tostring(state.trajectorySamples)
					.. ' action_count=' .. tostring(state.actionCount))
			end
			if Now() - state.startedAt >= 8.0 then return Fail(bot, 'move_path_timeout') end
			return
		end
		if (state.step == 1 or state.step == 2)
		and state.status ~= 'complete' and state.status ~= 'failed'
		and Now() - state.startedAt >= Config.PATH_TIMEOUT
		then
			Fail(bot, 'path_callback_timeout step=' .. tostring(state.step))
		end
		return
	end
	local startLocation, destination, _, radius = BuildScenario(bot)
	if not execute then
		startLocation, destination, radius = BuildOpenPathScenario()
		if startLocation == nil or destination == nil then
			return Fail(bot, 'open_path_scenario_unavailable')
		end
	end
	Log(bot, 'none', 'scenario', string.format(
		'execute=%s start_x=%.1f start_y=%.1f destination_x=%.1f destination_y=%.1f radius=%.1f',
		tostring(execute), startLocation.x or 0, startLocation.y or 0,
		destination.x or 0, destination.y or 0, radius))
	state.step = 1
	state.startedAt = Now()
	state.requestID = Generate(bot, startLocation, destination, {}, 'baseline', function(baselineDistance, baselineWaypoints)
		if type(baselineDistance) ~= 'number' or baselineDistance <= 0
		or type(baselineWaypoints) ~= 'table' or #baselineWaypoints == 0
		then
			return Fail(bot, 'baseline_invalid')
		end
		local center = BuildMidPathZone(startLocation, baselineWaypoints, radius)
		if center == nil then return Fail(bot, 'baseline_too_short_for_zone') end
		local zone = {key = 'probe-zone', center = center, effectiveRadius = radius}
		local baselineClear, baselineReason = Geometry.ValidatePath(startLocation,
			baselineWaypoints, {zone}, Config.PATH_CLEARANCE_TOLERANCE)
		if baselineClear then return Fail(bot, 'baseline_does_not_cross_zone') end
		Log(bot, 'none', 'complete', 'result=baseline_crosses_zone reason='
			.. tostring(baselineReason) .. ' distance=' .. tostring(baselineDistance)
			.. ' waypoint_count=' .. tostring(#baselineWaypoints))
		state.handle = AddZone(bot, center, radius, 10.0, 'path-obstacle')
		if state.handle == nil then return Fail(bot, 'path_zone_add_failed') end
		state.step = 2
		state.startedAt = Now()
		-- Add 创建的是全局区域；返回句柄只用于 Remove，不属于 tAvoidanceZones。
		state.requestID = Generate(bot, startLocation, destination, {}, 'avoidance', function(avoidanceDistance, waypoints)
			if type(avoidanceDistance) ~= 'number' or avoidanceDistance <= 0
			or type(waypoints) ~= 'table' or #waypoints == 0
			then
				return Fail(bot, 'avoidance_path_invalid')
			end
			local pathSource = 'native'
			local valid, reason = Geometry.ValidatePath(startLocation, waypoints, {zone},
				Config.PATH_CLEARANCE_TOLERANCE)
			local pathNotLonger = type(baselineDistance) == 'number'
				and type(avoidanceDistance) == 'number' and avoidanceDistance <= baselineDistance
			if execute and (not valid or pathNotLonger) then
				-- P4 已验证原生区域寻路；P5 只隔离验证 Action_MovePath，可使用已验证的 Lua waypoint 降级。
				local fallback, fallbackReason = Geometry.BuildFallbackWaypoints(startLocation,
					destination, {zone}, Config.PATH_CLEARANCE_TOLERANCE)
				local fallbackValid, fallbackValidationReason = Geometry.ValidatePath(startLocation,
					fallback, {zone}, Config.PATH_CLEARANCE_TOLERANCE)
				local fallbackDestination = type(fallback) == 'table' and fallback[#fallback] or nil
				if not fallbackValid or fallbackDestination == nil
				or Geometry.Distance(fallbackDestination, destination) > 180
				then
					return Fail(bot, 'move_path_fallback_invalid native_reason=' .. tostring(reason)
						.. ' fallback_reason=' .. tostring(fallbackReason)
						.. ' validation_reason=' .. tostring(fallbackValidationReason))
				end
				waypoints = fallback
				pathSource = 'lua_fallback'
				Log(bot, 'none', 'fallback', 'result=lua_waypoints native_reason=' .. tostring(reason)
					.. ' native_not_longer=' .. tostring(pathNotLonger)
					.. ' fallback_reason=' .. tostring(fallbackReason)
					.. ' waypoint_count=' .. tostring(#waypoints))
			elseif not valid then
				return Fail(bot, 'avoidance_clearance_' .. tostring(reason))
			elseif pathNotLonger then
				return Fail(bot, 'avoidance_path_not_longer')
			end
			if not execute then
				return Complete(bot, 'baseline_and_avoidance_callbacks baseline_distance='
					.. tostring(baselineDistance) .. ' avoidance_distance=' .. tostring(avoidanceDistance)
					.. ' waypoint_count=' .. tostring(#waypoints))
			end
			local actionTypeBefore = Safe(-1, function() return bot:GetCurrentActionType() end)
			Log(bot, 'Action_MovePath', 'before-call', 'path_source=' .. tostring(pathSource)
				.. ' waypoint_count=' .. tostring(#waypoints)
				.. ' current_action_type=' .. tostring(actionTypeBefore))
			local ok, err = pcall(function() return bot:Action_MovePath(waypoints) end)
			if not ok then
				Log(bot, 'Action_MovePath', 'after-call', 'result=lua-error error=' .. tostring(err))
				return Fail(bot, 'move_path_failed')
			end
			local actionTypeAfter = Safe(-1, function() return bot:GetCurrentActionType() end)
			Log(bot, 'Action_MovePath', 'after-call', 'result=returned current_action_type='
				.. tostring(actionTypeAfter))
			state.actionCount = (state.actionCount or 0) + 1
			state.destination = destination
			state.zoneCenter = center
			state.zoneRadius = radius
			state.pathSource = pathSource
			state.initialMoveDistance = Geometry.Distance(bot:GetLocation(), destination)
			state.progressMade = false
			state.trajectorySamples = 0
			state.startedAt = Now()
			state.step = 3
			state.status = 'moving'
		end)
		if state.requestID == nil then Fail(bot, 'avoidance_generate_failed') end
	end)
	if state.requestID == nil then Fail(bot, 'baseline_generate_failed') end
end

function Probe.Think(bot)
	if not Probe.IsEnabled() or not IsTargetBot(bot) then return false end
	local state = GetState(bot)
	if state.status == 'complete' or state.status == 'failed' then return false end
	if state.phase == 0 then
		if state.step == 0 then
			Log(bot, 'none', 'execute', 'result=think_entered')
			state.step = 1
			state.startedAt = Now()
		elseif Now() - state.startedAt >= Config.PROBE_MODE_LOAD_HOLD then
			Complete(bot, 'mode_load_think_and_sample_hold')
		end
	elseif state.phase == 1 then
		ThinkPhaseOne(bot, state)
	elseif state.phase == 2 then
		ThinkPhaseTwo(bot, state)
	elseif state.phase == 3 then
		ThinkPhaseThree(bot, state)
	elseif state.phase == 4 then
		ThinkPhaseFourOrFive(bot, state, false)
	elseif state.phase == 5 then
		ThinkPhaseFourOrFive(bot, state, true)
	else
		Fail(bot, 'unknown_probe_phase')
	end
	return true
end

function Probe.OnEnd(bot)
	if Probe.IsEnabled() and IsTargetBot(bot) then
		if GetState(bot).phase == 0 then bot.THD_AvoidanceModeLoadProbeActive = false end
		if GetState(bot).phase == 5 then bot.THD_TowerEscapeActive = false end
		Log(bot, 'none', 'mode-end', 'result=evasive_mode_end')
	end
end

function Probe.GetState(bot)
	local state = GetState(bot)
	return {
		status = state.status,
		step = state.step,
		phase = state.phase,
		handle = state.handle,
		requestID = state.requestID,
		actionCount = state.actionCount,
	}
end

return Probe
