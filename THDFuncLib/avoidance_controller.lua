local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local TowerSafety = require(GetScriptDirectory()..'/THDFuncLib/tower_safety')
local ZoneManager = require(GetScriptDirectory()..'/THDFuncLib/avoidance_zone_manager')
local AvoidancePath = require(GetScriptDirectory()..'/THDFuncLib/avoidance_path')
local Pickoff = require(GetScriptDirectory()..'/THDFuncLib/roam_pickoff')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')

local Controller = {}
local Handoff

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
			lastTeamfightTowerPolicyLogAt = -90,
			lastTeamfightTowerPolicyResult = nil,
		}
		Handoff.Reset(bot.THD_AvoidanceControllerState)
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

local function SnapshotLocation(location)
	if location == nil then return nil end
	return Geometry.MakeVector(tonumber(location.x) or 0, tonumber(location.y) or 0,
		tonumber(location.z) or 0)
end

Handoff = require(GetScriptDirectory()..'/THDFuncLib/avoidance_handoff').New({
	Now = Now, Safe = Safe, Log = Log, IsProtectedAction = IsProtectedAction,
})

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
	Handoff.Reacquire(bot, state)
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
	state.motionLocation, state.motionAt = nil, nil
	state.minCenterClearance = math.huge
	state.progressLocation, state.progressAt = SnapshotLocation(bot:GetLocation()), Now()
	state.recoveryTarget, state.recoverySince, state.recoverySafeSince = nil, nil, nil
	state.recoveryRequested = false
	state.recoverySignature, state.recoveryOrigin = nil, nil
	state.recoverySearches, state.nextRecoveryAt = 0, -90
	state.failedRecovery = nil
	state.recoveryReach = 48
	state.recoveryRejected = {}
	state.lastDirectTarget, state.lastDirectActionAt = nil, -90
	bot.THD_AvoidanceOwnedMove = nil
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
	if reason == 'invalid_bot' or reason == 'feature_disabled' then state.failedRecovery = nil end
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
	bot.THD_AvoidanceOwnedMove = nil
	state.recoveryTarget, state.recoverySince, state.recoverySafeSince = nil, nil, nil
	state.recoveryRequested = false
	SetModeState(bot, state, Controller.IDLE, reason or 'released')
	Log(bot, state, 'lease', 'released', 'reason=' .. tostring(reason)
		.. string.format(' held_for=%.3f', heldFor)
		.. ' path_action_count=' .. tostring(pathSnapshot.totalActionCount or pathSnapshot.actionCount or 0)
		.. ' min_center_clearance=' .. tostring(state.minCenterClearance or 'none'))
	state.startedAt = nil
	-- 释放租约后继续观察 Valve 模式仲裁，区分正常交接与 desire=0 的 mode 19 残留。
	if reason ~= 'invalid_bot' and reason ~= 'feature_disabled' and IsValidBot(bot) then
		Handoff.Begin(bot, state, reason, handoffAnchor, handoffZones, now)
	else
		Handoff.Reset(state)
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

local function UpdateClearance(bot, state, scan, containingZones, routeZones, geometryZones)
	-- 活动危险过期不能代替几何净空；许可过滤后的记忆圆仍约束安全释放。
	local geometryClear = geometryZones ~= nil
	for _, zone in ipairs(geometryZones or {}) do
		if Geometry.PointInCircle(bot:GetLocation(), zone,
			math.max(0, tonumber(Config.LUA_ROUTE_SAFETY_MARGIN) or 0)) then
			geometryClear = false
			break
		end
	end
	if not geometryClear or not IsScanClear(scan, containingZones, routeZones) then
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
		local current = bot:GetLocation()
		Log(bot, state, 'clearance-window', 'confirmed_geometry', string.format(
			'current_x=%.1f current_y=%.1f margin=%.1f geometry_zones=%s',
			current.x, current.y, math.max(0, tonumber(Config.LUA_ROUTE_SAFETY_MARGIN) or 0),
			#geometryZones > 0 and FormatZones(geometryZones) or 'none'))
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

local function MoveDirect(bot, state, location, reason, partialExit)
	if location == nil or type(bot.Action_MoveToLocation) ~= 'function' then return false end
	local current = bot:GetLocation()
	local validate = partialExit and Geometry.ValidateRecoverySegment or Geometry.ValidateMovementSegment
	if state.movementGeometry == nil or not validate(current, location,
		state.movementGeometry, state.movementMargin) then return false end
	local now = Now()
	if now - (state.lastDirectActionAt or -90) < Config.DIRECT_ACTION_INTERVAL
	and state.lastDirectTarget ~= nil
	and Geometry.Distance(state.lastDirectTarget, location) <= 80
	then
		return true
	end
	if not Geometry.ValidateLocalTerrainSegment(current, location, false) then return false end
	state.lastDirectActionAt = now
	state.lastDirectTarget = location
	bot:Action_MoveToLocation(location)
	bot.THD_AvoidanceOwnedMove = {target = location, generation = bot.THD_TowerEscapeGeneration or 0, partialExit = partialExit == true}
	state.actionCount = (state.actionCount or 0) + 1
	local current = Safe(nil, function() return bot:GetLocation() end) or {}
	Log(bot, state, 'execute', reason or 'direct_move', string.format(
		'current_x=%.1f current_y=%.1f target_x=%.1f target_y=%.1f',
		current.x or 0, current.y or 0, location.x or 0, location.y or 0))
	return true
end

local function StopOwnedMove(bot, state, reason)
	local owned = bot.THD_AvoidanceOwnedMove
	if owned == nil or IsProtectedAction(bot)
	or Safe(-1, function() return bot:NumQueuedActions() end) ~= 0
	or BOT_MODE_EVASIVE_MANEUVERS == nil
	or Safe(-1, function() return bot:GetActiveMode() end) ~= BOT_MODE_EVASIVE_MANEUVERS
	or type(BOT_ACTION_TYPE_MOVE_TO) ~= 'number'
	or Safe(-1, function() return bot:GetCurrentActionType() end) ~= BOT_ACTION_TYPE_MOVE_TO
	or type(bot.Action_ClearActions) ~= 'function' then return false end
	-- 已确认是避塔自己的普通移动；true 立即停止，避免不安全旧命令继续执行。
	bot:Action_ClearActions(true)
	bot.THD_AvoidanceOwnedMove = nil
	state.lastDirectTarget, state.lastDirectActionAt = nil, -90
	Log(bot, state, 'recovery', 'owned_move_stopped', string.format(
		'reason=%s order_generation=%s target_x=%.1f target_y=%.1f',
		tostring(reason), tostring(owned.generation), owned.target.x, owned.target.y))
	return true
end

local function RejectOwnedMovement(bot, state, reason)
	local owned = bot.THD_AvoidanceOwnedMove
	if owned ~= nil then
		-- 保留失败目标供有界恢复排除；不沿用刚被否定的恢复目标。
		table.insert(state.recoveryRejected, SnapshotLocation(owned.target))
		if #state.recoveryRejected > 3 then table.remove(state.recoveryRejected, 1) end
	end
	state.recoveryTarget, state.recoveryPartial = nil, false
	state.recoveryRequested = true
	AvoidancePath.MarkNeedsRepath(bot, reason)
	local stopped = StopOwnedMove(bot, state, reason)
	Log(bot, state, 'recovery', 'replan_deferred', string.format(
		'reason=%s stopped=%d new_order_issued=0', tostring(reason), stopped and 1 or 0))
	-- 本次 Think 到此结束；下一次按最新许可/几何重新搜索，仍遵守原搜索预算。
	return true
end

local function RevalidateOwnedMove(bot, state, current, zones, margin)
	local owned = bot.THD_AvoidanceOwnedMove
	if owned == nil then return false end
	if Safe(-1, function() return bot:GetCurrentActionType() end) ~= BOT_ACTION_TYPE_MOVE_TO then
		-- 其他动作已经接管时，仅清理旧移动归属，不撤销当前动作。
		bot.THD_AvoidanceOwnedMove = nil
		return false
	end
	-- 已到短步容差内交给到点处理停止，不再把零长度剩余段当向内运动。
	if owned.partialExit and Geometry.Distance(current, owned.target) <= (state.recoveryReach or 48) then return false end
	local validate = owned.partialExit and Geometry.ValidateRecoverySegment or Geometry.ValidateMovementSegment
	local safe, reason, zone = validate(current, owned.target, zones, margin)
	if safe then return end
	if Now() - (state.lastUnsafeMoveLogAt or -90) >= 1.0 then
		state.lastUnsafeMoveLogAt = Now()
		Log(bot, state, 'recovery', 'owned_move_rejected', string.format(
			'reason=%s zone_key=%s order_generation=%s current_x=%.1f current_y=%.1f target_x=%.1f target_y=%.1f margin=%.1f',
			tostring(reason), tostring(zone and zone.key or 'none'), tostring(owned.generation),
			current.x, current.y, owned.target.x, owned.target.y, margin))
	end
	return RejectOwnedMovement(bot, state, 'unsafe_current_segment')
end

local function ObserveActualMotion(bot, state, current, zones)
	local previous = state.motionLocation
	local owned = bot.THD_AvoidanceOwnedMove
	state.motionLocation = SnapshotLocation(current)
	local now, before = Now(), state.motionAt
	state.motionAt = now
	if previous == nil or owned == nil or Geometry.Distance(previous, current) < 1
	or Safe(-1, function() return bot:GetCurrentActionType() end) ~= BOT_ACTION_TYPE_MOVE_TO then return false end
	-- 与规划/执行共享当前有效几何，已获穿塔许可的圆不作为移动违例。
	local safe, reason, zone = Geometry.ValidateMovementSegment(previous, current, zones, 0, true)
	local offset = Geometry.SegmentDistanceToPoint(previous, owned.target, current)
	if safe and offset <= 96 then return end
	Log(bot, state, 'trajectory', 'deviation', string.format(
		'reason=%s zone_key=%s dt=%.3f from_x=%.1f from_y=%.1f current_x=%.1f current_y=%.1f target_x=%.1f target_y=%.1f offset=%.1f order_generation=%s action_type=%s queued=%s protected=%d stunned=%d rooted=%d geometry_scope=movement geometry_zones=%s',
		tostring(reason or 'off_segment'), tostring(zone and zone.key or 'none'), now - (before or now),
		previous.x, previous.y, current.x, current.y, owned.target.x, owned.target.y, offset,
		tostring(owned.generation), tostring(Safe(-1, function() return bot:GetCurrentActionType() end)),
		tostring(Safe(-1, function() return bot:NumQueuedActions() end)), IsProtectedAction(bot) and 1 or 0,
		Safe(false, function() return bot:IsStunned() end) and 1 or 0,
		Safe(false, function() return bot:IsRooted() end) and 1 or 0,
		#zones > 0 and FormatZones(zones) or 'none'))
	return RejectOwnedMovement(bot, state, 'actual_motion_deviation')
end

local function ResetProgress(state, current)
	state.progressLocation, state.progressAt = SnapshotLocation(current), Now()
end

local function IsStalled(state, current)
	if state.progressLocation == nil
	or Geometry.Distance(current, state.progressLocation) >= Config.RECOVERY_PROGRESS_DISTANCE then
		ResetProgress(state, current)
	end
	return Now() - state.progressAt >= Config.RECOVERY_STALL_TIME
end

local function TryReleaseRecovery(bot, state, scan, geometryZones)
	if state.recoverySince == nil then return false end
	local safe = not IsProtectedAction(bot) and Safe(-1, function() return bot:NumQueuedActions() end) == 0
		and IsScanClear(scan, {}, {})
	local current = bot:GetLocation()
	for _, zone in ipairs(geometryZones) do
		if Geometry.PointInCircle(current, zone, GetRouteSafetyMargin()) then safe = false; break end
	end
	if not safe then state.recoverySafeSince = nil; return false end
	state.recoverySafeSince = state.recoverySafeSince or Now()
	if Now() - state.recoverySafeSince < Config.CLEARANCE_HOLD_TIME then return false end
	-- 当前位置已确认净空时，不能只因旧锚点直线受阻而继续占绝对欲望。
	StopOwnedMove(bot, state, 'recovery_safe_release')
	Clear(bot, state, 'recovery_safe_release')
	return true
end

local function RecoveryGeometryKey(zones)
	return AvoidancePath.MakeRequestSignature(Geometry.MakeVector(0, 0, 0), zones)
end

local function ReleaseFailedRecovery(bot, state, current, zones)
	-- 无可执行动作不能无限占绝对欲望；失败释放不是净空成功，补步也不得启动。
	StopOwnedMove(bot, state, 'recovery_exhausted')
	state.failedRecovery = {
		origin = SnapshotLocation(current), geometryKey = RecoveryGeometryKey(zones),
		nextProbeAt = Now() + Config.RECOVERY_ADMISSION_INTERVAL,
	}
	Log(bot, state, 'recovery', 'failed_release', string.format(
		'current_x=%.1f current_y=%.1f safe_release=0 retry_at=%.3f',
		current.x, current.y, state.failedRecovery.nextProbeAt))
	Clear(bot, state, 'recovery_exhausted')
	return true
end

local function RecoverMovement(bot, state, current, anchor, zones, margin, reason)
	state.recoverySince = state.recoverySince or Now()
	SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'bounded_recovery')
	local stalled = IsStalled(state, current)
	if stalled and state.recoveryTarget == nil then
		local owned = bot.THD_AvoidanceOwnedMove
		if owned ~= nil then
			table.insert(state.recoveryRejected, SnapshotLocation(owned.target))
			if #state.recoveryRejected > 3 then table.remove(state.recoveryRejected, 1) end
		end
		StopOwnedMove(bot, state, 'no_progress')
	end
	if state.recoveryTarget ~= nil then
		local target = state.recoveryTarget
		local validate = state.recoveryPartial and Geometry.ValidateRecoverySegment or Geometry.ValidateMovementSegment
		local safe = validate(current, target, zones, margin)
		if Geometry.Distance(current, target) <= (state.recoveryPartial and (state.recoveryReach or 48) or 120) then
			-- 到达短步就停止原命令，下一步必须重新选点和校验。
			if state.recoveryPartial then StopOwnedMove(bot, state, 'recovery_step_reached') end
			state.recoveryTarget = nil
			ResetProgress(state, current)
			Log(bot, state, 'recovery', 'target_reached', '')
			return true
		elseif not stalled and safe and MoveDirect(bot, state, target, 'recovery_move', state.recoveryPartial) then
			return true
		end
		table.insert(state.recoveryRejected, SnapshotLocation(target))
		if #state.recoveryRejected > 3 then table.remove(state.recoveryRejected, 1) end
		state.recoveryTarget = nil
		StopOwnedMove(bot, state, stalled and 'no_progress' or 'recovery_target_invalid')
	end
	local signature = AvoidancePath.MakeRequestSignature(anchor, zones) .. ':margin=' .. tostring(margin)
	if state.recoverySignature ~= signature or state.recoveryOrigin == nil
	or Geometry.Distance(current, state.recoveryOrigin) >= Config.RECOVERY_PROGRESS_DISTANCE then
		state.recoverySignature, state.recoveryOrigin = signature, SnapshotLocation(current)
		state.recoverySearches = 0
	end
	if Now() < (state.nextRecoveryAt or -90) then return true end
	state.nextRecoveryAt = Now() + Config.RECOVERY_SEARCH_INTERVAL
	if state.recoverySearches >= Config.RECOVERY_MAX_SEARCHES then
		Log(bot, state, 'recovery', 'blocked', 'reason=search_budget_exhausted new_order_issued=0')
		return ReleaseFailedRecovery(bot, state, current, zones)
	end
	state.recoverySearches = state.recoverySearches + 1
	local target, stats = Geometry.FindRecoveryPoint(current, anchor, zones, margin,
		Config.RECOVERY_MAX_DISTANCE, state.recoveryRejected)
	state.recoveryPartial = false
	local function LogTerrain(samples, kind)
		for _, sample in ipairs(samples or {}) do
			local detail = sample.detail or {}
			local point = detail.point or {}
			Log(bot, state, 'recovery-terrain', 'rejected_sample', string.format(
				'kind=%s reason=%s sample=%d steps=%d sample_x=%.1f sample_y=%.1f target_x=%.1f target_y=%.1f',
				kind, tostring(sample.reason), detail.index or 0, detail.steps or 0,
				point.x or 0, point.y or 0, sample.target.x, sample.target.y))
		end
	end
	LogTerrain(stats.terrainSamples, 'full_exit')
	if target == nil then
		local stepStats
		target, stepStats = Geometry.FindRecoveryStep(current, anchor, zones, margin, state.recoveryRejected)
		state.recoveryPartial = target ~= nil
		LogTerrain(stepStats.terrainSamples, 'short_step')
		Log(bot, state, 'recovery-step', target ~= nil and 'selected' or 'unavailable', string.format(
			'candidates=%d rejected_geometry=%d rejected_terrain=%d rejected_recent=%d',
			stepStats.candidates, stepStats.geometry, stepStats.terrain, stepStats.recent))
	end
	if target == nil then
		-- 标准短步仍无解时追加更细的48候选；不放宽单调向外和邻塔门禁。
		local compactStats
		target, compactStats = Geometry.FindRecoveryStep(current, anchor, zones, margin, state.recoveryRejected, true)
		state.recoveryPartial = target ~= nil
		LogTerrain(compactStats.terrainSamples, 'compact_step')
		Log(bot, state, 'recovery-compact', target ~= nil and 'selected' or 'unavailable', string.format(
			'candidates=%d rejected_geometry=%d rejected_terrain=%d rejected_recent=%d',
			compactStats.candidates, compactStats.geometry, compactStats.terrain, compactStats.recent))
	end
	Log(bot, state, 'recovery', target ~= nil and 'target_selected' or 'no_safe_target', string.format(
		'partial_exit=%s reason=%s search=%d candidates=%d rejected_geometry=%d rejected_terrain=%d rejected_recent=%d rejected_range=%d margin=%.1f current_x=%.1f current_y=%.1f target_x=%.1f target_y=%.1f zones=%s',
		tostring(state.recoveryPartial), tostring(reason), state.recoverySearches, stats.candidates, stats.geometry, stats.terrain,
		stats.recent, stats.range, margin, current.x, current.y, target and target.x or 0, target and target.y or 0,
		#zones > 0 and FormatZones(zones) or 'none'))
	if target ~= nil then
		state.recoveryTarget = SnapshotLocation(target)
		state.recoveryReach = math.min(48, Geometry.Distance(current, target) * 0.25)
		state.recoveryRequested = false
		ResetProgress(state, current)
		AvoidancePath.MarkNeedsRepath(bot, 'recovery_target_selected')
		MoveDirect(bot, state, target, 'recovery_move', state.recoveryPartial)
	end
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
	AvoidancePath.NoteExecutionFailure(bot, reason)
	AvoidancePath.MarkNeedsRepath(bot, 'unsafe_current_segment')
	SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'unsafe_current_segment')
	local rejectedZones = details.zone ~= nil and {details.zone} or {}
	local escapeZones = UniqueZones(routeZones, rejectedZones)
	local escapePoint = Geometry.FindDirectEscapePoint(current, anchor, latestZones,
		GetRouteSafetyMargin(), escapeZones)
	if escapePoint == nil or not MoveDirect(bot, state, escapePoint, 'unsafe_path_egress') then
		RecoverMovement(bot, state, current, anchor, latestZones, GetRouteSafetyMargin(), reason)
	end
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

local function FindRecoveryAdmission(bot, state, scan, knownZones, authorization, teamfight)
	local failed = state.failedRecovery
	local current = bot:GetLocation()
	local zones = BuildMovementGeometry(bot, state, scan, knownZones, authorization, teamfight)
	local geometryKey = RecoveryGeometryKey(zones)
	if Now() < failed.nextProbeAt and geometryKey == failed.geometryKey
	and Geometry.Distance(current, failed.origin) < Config.RECOVERY_PROGRESS_DISTANCE then return nil end
	failed.origin, failed.geometryKey = SnapshotLocation(current), geometryKey
	failed.nextProbeAt = Now() + Config.RECOVERY_ADMISSION_INTERVAL
	-- 只探查48个细步，不在无解时反复新建最高欲望租约；执行前仍重新验证。
	local target, stats = Geometry.FindRecoveryStep(current, scan.anchor, zones,
		GetRouteSafetyMargin(), {}, true)
	Log(bot, state, 'recovery-admission', target ~= nil and 'ready' or 'unavailable', string.format(
		'candidates=%d rejected_geometry=%d rejected_terrain=%d current_x=%.1f current_y=%.1f retry_at=%.3f',
		stats.candidates, stats.geometry, stats.terrain, current.x, current.y, failed.nextProbeAt))
	return target
end

function Controller.GetDesire(bot)
	if not Controller.IsEnabled(bot) then
		if bot ~= nil and bot.THD_AvoidanceControllerState ~= nil then
			Handoff.Stop(bot, GetState(bot), 'feature_disabled')
			Clear(bot, GetState(bot), 'feature_disabled')
			if bot.THD_AvoidanceZoneState ~= nil then ZoneManager.Reset(bot, 'runtime') end
		end
		CandidateDebug.Note('feature_disabled')
		return BOT_MODE_DESIRE_NONE
	end
	if not IsValidBot(bot) then
		if bot ~= nil and bot.THD_AvoidanceControllerState ~= nil then
			Handoff.Stop(bot, GetState(bot), 'invalid_bot')
			Clear(bot, GetState(bot), 'invalid_bot')
			if bot.THD_AvoidanceZoneState ~= nil then ZoneManager.Reset(bot, 'runtime') end
		end
		CandidateDebug.Note('invalid_bot')
		return BOT_MODE_DESIRE_NONE
	end

	local state = GetState(bot)
	Handoff.Observe(bot, state)
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
		local admission
		if state.failedRecovery ~= nil then
			admission = FindRecoveryAdmission(bot, state, scan, knownZones, highGroundAuthorization, highLevelTeamfight)
			if admission == nil then
				CandidateDebug.Note('recovery_admission_wait')
				return BOT_MODE_DESIRE_NONE
			end
		end
		SetActive(bot, state, scan)
		if admission ~= nil then
			state.recoveryTarget, state.recoveryPartial = SnapshotLocation(admission), true
			state.recoveryReach = math.min(48, Geometry.Distance(bot:GetLocation(), admission) * 0.25)
			state.recoverySince = Now()
		end
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
	local geometryZones = BuildMovementGeometry(bot, state, scan, knownZones,
		highGroundAuthorization, highLevelTeamfight)
	if state.active and UpdateClearance(bot, state, scan, containingZones, routeZones, geometryZones) then
		CandidateDebug.Note('clearance_confirmed')
		return BOT_MODE_DESIRE_NONE
	end
	if state.recoverySince ~= nil then
		if TryReleaseRecovery(bot, state, scan, geometryZones) then
			CandidateDebug.Note('recovery_safe_release')
			return BOT_MODE_DESIRE_NONE
		end
		CandidateDebug.Detail('recovery_searches', state.recoverySearches)
		CandidateDebug.Detail('recovery_target', state.recoveryTarget ~= nil)
		CandidateDebug.Detail('recovery_no_progress', Now() - (state.progressAt or Now()))
	end
	CandidateDebug.Note(state.recoverySince ~= nil and 'escape_recovery_active'
		or (state.active and 'escape_lease_active' or 'no_escape_lease'))
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
	Handoff.OnEnd(bot, state)
end

function Controller.Think(bot)
	if not Controller.IsEnabled(bot) or not IsValidBot(bot) then return false end
	local state = GetState(bot)
	Handoff.Observe(bot, state)
	if not state.active then return Handoff.Execute(bot, state) end
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
	local geometryZones, geometryAudit = BuildMovementGeometry(bot, state, scan, knownZones,
		highGroundAuthorization, highLevelTeamfight)
	if UpdateClearance(bot, state, scan, containingZones, routeZones, geometryZones) then return true end
	if IsProtectedAction(bot) or Safe(-1, function() return bot:NumQueuedActions() end) ~= 0
	or Safe(false, function() return bot:IsStunned() end)
	or Safe(false, function() return bot:IsRooted() end) then
		-- 施法/确认队列或控制期间不累计停滞，也不把跨保护窗口位移归给旧命令。
		state.motionLocation, state.motionAt = nil, nil
		ResetProgress(state, current)
		Log(bot, state, 'execute', 'protected_action', '')
		return true
	end

	state.movementGeometry = geometryZones
	state.movementMargin = #containingZones > 0
		and math.max(Config.PATH_CLEARANCE_TOLERANCE, Config.DIRECT_EGRESS_SAFETY_MARGIN)
		or GetRouteSafetyMargin()
	local movementRouteZones = anchor ~= nil
		and Geometry.FilterIntersectingZones(current, anchor, geometryZones, GetRouteSafetyMargin()) or {}
	LogMovementGeometry(bot, state, geometryZones, movementRouteZones, geometryAudit, false)
	if ObserveActualMotion(bot, state, current, geometryZones)
	or RevalidateOwnedMove(bot, state, current, geometryZones, state.movementMargin) then return true end
	if Config.USE_NATIVE_ZONES or Config.USE_NATIVE_REMOVE then
		ZoneManager.SyncNative(bot, UniqueZones(containingZones, routeZones), BuildExcludedKeys(containingZones), 'runtime')
	end
	if TryReleaseRecovery(bot, state, scan, geometryZones) then return true end
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
		if state.recoveryRequested or state.recoveryTarget ~= nil or IsStalled(state, current) then
			return RecoverMovement(bot, state, current, anchor, geometryZones,
				state.movementMargin, 'no_progress_or_recovery_target')
		end
		SetModeState(bot, state, Controller.ESCAPE_DIRECT, 'inside_tower_zone')
		AvoidancePath.MarkNeedsRepath(bot, 'inside_tower_zone')
		local directMargin = math.max(tonumber(Config.PATH_CLEARANCE_TOLERANCE) or 0,
			tonumber(Config.DIRECT_EGRESS_SAFETY_MARGIN) or 0)
		local escapePoint = Geometry.FindDirectEscapePoint(bot:GetLocation(), anchor,
			geometryZones, directMargin, containingZones)
		if escapePoint ~= nil and MoveDirect(bot, state, escapePoint, 'direct_egress') then return true end
		-- 候选全部失败时不能再发一条未经检查的 anchor 穿塔命令。
		if anchor ~= nil and MoveDirect(bot, state, anchor, 'direct_anchor_fallback') then
			return true
		end
		if Now() - (state.lastNoSafeEgressLogAt or -90) >= 1.0 then
			state.lastNoSafeEgressLogAt = Now()
			Log(bot, state, 'path-policy', 'no_safe_egress_segment', 'new_order_issued=0')
		end
		return RecoverMovement(bot, state, current, anchor, geometryZones, directMargin, 'no_safe_egress_segment')
	end

	if state.recoveryRequested or state.recoveryTarget ~= nil or IsStalled(state, current) then
		return RecoverMovement(bot, state, current, anchor, geometryZones,
			state.movementMargin, 'no_progress_or_recovery_target')
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
		if MoveDirect(bot, state, anchor, 'clear_route_anchor') then return true end
		return RecoverMovement(bot, state, current, anchor, geometryZones, GetRouteSafetyMargin(), 'anchor_terrain_blocked')
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
		if AvoidancePath.CanRequest(bot, current, anchor, geometryZones) then
			AvoidancePath.Request(bot, current, anchor, geometryZones, 'runtime')
			LogMovementGeometry(bot, state, geometryZones, movementRouteZones, geometryAudit, true)
		end
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
	if escapePoint ~= nil and MoveDirect(bot, state, escapePoint, 'path_unavailable_egress') then
		return true
	end
	return RecoverMovement(bot, state, current, anchor, geometryZones, GetRouteSafetyMargin(),
		pathState.failureReason or 'path_unavailable')
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
		pathFailedAttempts = path.failedAttempts,
		recoveryTarget = state.recoveryTarget,
		recoverySearches = state.recoverySearches,
		progressAt = state.progressAt,
		directActionCount = state.actionCount or 0,
		pathActionCount = path.actionCount or 0,
	}
end

return Controller
