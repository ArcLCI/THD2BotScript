local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local combatPowerOK, CombatPower = pcall(require, GetScriptDirectory()..'/THDFuncLib/combat_power')
if not combatPowerOK or CombatPower == nil then
	CombatPower = {Estimate = function() return 0 end}
end
local laneAssignmentOK, LaneAssignment = pcall(
	require,
	GetScriptDirectory()..'/THDFuncLib/lane_assignment'
)

local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Strategy = {}

-- Wasteland 部署保持开启；Nostalgia 部署必须把本开关设为 false，关闭后完全沿用旧逻辑。
Strategy.ENABLED = true
Strategy.BALANCE_START_TIME = 15 * 60
Strategy.BALANCE_END_TIME = 20 * 60
Strategy.OUTER_TOWER_DEADLINE = 30 * 60
Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND = 20 -- 本轮实机测试：默认团队平均20级上高
Strategy.MIN_EXCEPTION_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND = 20 -- 最低等级检查与本轮默认门槛一致
Strategy.MIN_LEVEL_LEAD = 1.0
Strategy.MIN_KILL_RATIO = 1.25
Strategy.MAX_LEVEL_DEFICIT_FOR_KILL_LEAD = 0.5
Strategy.BALANCED_ROAM_PROPOSAL_DESIRE = 0.82
Strategy.ADVANTAGE_ROAM_PROPOSAL_DESIRE = 0.78
Strategy.ADVANTAGE_OUTER_PUSH_DESIRE = 0.92
Strategy.OUTER_PUSH_START_TIME = 9 * 60
Strategy.OUTER_COMMIT_DURATION = 12.0
Strategy.OUTER_COMMIT_DESIRE = 0.94
Strategy.OUTER_COMMIT_MAX_DURATION = 30.0
Strategy.OBJECTIVE_ASSEMBLE_TIMEOUT = 12.0
Strategy.OBJECTIVE_ASSEMBLE_MAX_TIMEOUT = 30.0
Strategy.OBJECTIVE_ASSEMBLE_ETA_BUFFER = 4.0
Strategy.OBJECTIVE_POST_ASSEMBLE_MAX_DURATION = 30.0
Strategy.OBJECTIVE_ABSOLUTE_MAX_DURATION = 90.0
Strategy.OBJECTIVE_SIEGE_PROGRESS_EXTENSION = 12.0
Strategy.OBJECTIVE_SIEGE_NO_DAMAGE_TIMEOUT = 5.0
Strategy.OBJECTIVE_ASSIGNMENT_STABLE_TIME = 3.0
Strategy.OBJECTIVE_PARTICIPANT_MIN_NO_PROGRESS_TIME = 12.0
Strategy.OBJECTIVE_PARTICIPANT_MAX_NO_PROGRESS_TIME = 30.0
Strategy.OBJECTIVE_PARTICIPANT_PROGRESS_EXTENSION = 12.0
Strategy.OBJECTIVE_NO_PROGRESS_RESELECT_BLOCK_TIME = 12.0
Strategy.OBJECTIVE_MAX_REASSIGNMENTS = 4
Strategy.OBJECTIVE_MIN_HEALTH = 0.60
-- 高地塔已移除叠攻速：统一围攻血线与三秒塔伤容忍，致命/非塔危险仍单独否决。
Strategy.HIGH_GROUND_COMMIT_MIN_HP = 0.40
Strategy.HIGH_GROUND_MAX_TOWER_DAMAGE_RATIO = 0.35
Strategy.OBJECTIVE_APPROACH_PROGRESS_DISTANCE = 300
Strategy.OBJECTIVE_CREEP_PROGRESS_DISTANCE = 250
Strategy.OBJECTIVE_ARRIVAL_DISTANCE = 1600
Strategy.OBJECTIVE_ESCORT_CREEP_DISTANCE = 2000
Strategy.OBJECTIVE_ATTACKABLE_ASSEMBLY_SHORTFALL = 1
Strategy.OBJECTIVE_RETRY_RESET_TIME = 60.0
Strategy.OBJECTIVE_RETRY_MAX_MULTIPLIER = 3
Strategy.OBJECTIVE_HIGH_GROUND_CONTINUATION_DURATION = 30.0
Strategy.OBJECTIVE_RETRY_BASE_DELAYS = {
	assemble_timeout = 6.0,
	base_defense_pressure = 8.0,
	progress_lease_expired = 5.0,
	siege_no_health_drop = 8.0,
	maximum_duration = 6.0,
	insufficient_eligible = 5.0,
	participant_churn = 10.0,
}
Strategy.OBJECTIVE_PROGRESS_LOG_INTERVAL = 2.0
Strategy.OBJECTIVE_HEALTH_LOG_INTERVAL = 1.5
Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL = 2.0
Strategy.BASE_PRESSURE_LAST_SEEN_AGE = 5.0
Strategy.BASE_PRESSURE_RADIUS = 4500
Strategy.BASE_TOWER_CRITICAL_RADIUS = 700
Strategy.BASE_ANCIENT_CRITICAL_RADIUS = 1200
Strategy.HIGH_GROUND_LOCAL_RADIUS = 2000
Strategy.NON_PARTICIPANT_PUSH_DESIRE = 0.02
Strategy.CONVERSION_OPPORTUNITY_DURATION = 12.0
-- 击杀转推外塔时，低于此血量的 Bot 不再继续站在塔前承伤。
Strategy.CONVERSION_PUSH_MIN_HEALTH = 0.45
Strategy.DEBUG = false

Strategy.PHASE_IDLE = 'IDLE'
Strategy.PHASE_ASSEMBLE = 'ASSEMBLE'
Strategy.PHASE_ESCORT = 'ESCORT'
Strategy.PHASE_SIEGE = 'SIEGE'
Strategy.PHASE_DISENGAGE = 'DISENGAGE'

Strategy.ROLE_BUILDING_DAMAGE = 'building_damage'
Strategy.ROLE_FRONTLINE = 'frontline'
Strategy.ROLE_WAVE_CLEAR = 'wave_clear'
Strategy.ROLE_COVER = 'cover'

local objectives = {}
local lastObjectiveReleases = {}
local objectiveRetryState = {}
local objectiveSequence = 0
local conversionOpportunities = {}
local towerSnapshotMilestones = {}
local lastBaseThreatSnapshots = {}
local auditLogTimes = {}
local participantReselectBlocks = {}
local pushContinuations = {}

local OUTER_TOWERS = {}
for _, towerID in ipairs({TOWER_TOP_1, TOWER_TOP_2, TOWER_MID_1, TOWER_MID_2, TOWER_BOT_1, TOWER_BOT_2}) do
	if towerID ~= nil then table.insert(OUTER_TOWERS, towerID) end
end

local LANE_OUTER_TOWERS = {}
if LANE_TOP ~= nil then LANE_OUTER_TOWERS[LANE_TOP] = {TOWER_TOP_1, TOWER_TOP_2} end
if LANE_MID ~= nil then LANE_OUTER_TOWERS[LANE_MID] = {TOWER_MID_1, TOWER_MID_2} end
if LANE_BOT ~= nil then LANE_OUTER_TOWERS[LANE_BOT] = {TOWER_BOT_1, TOWER_BOT_2} end

local BUILDING_DESCRIPTORS = {
	{kind = 'top_t1', tier = 1, lane = LANE_TOP, buildingType = 'tower', id = TOWER_TOP_1},
	{kind = 'top_t2', tier = 2, lane = LANE_TOP, buildingType = 'tower', id = TOWER_TOP_2},
	{kind = 'top_t3', tier = 3, lane = LANE_TOP, buildingType = 'tower', id = TOWER_TOP_3},
	{kind = 'mid_t1', tier = 1, lane = LANE_MID, buildingType = 'tower', id = TOWER_MID_1},
	{kind = 'mid_t2', tier = 2, lane = LANE_MID, buildingType = 'tower', id = TOWER_MID_2},
	{kind = 'mid_t3', tier = 3, lane = LANE_MID, buildingType = 'tower', id = TOWER_MID_3},
	{kind = 'bot_t1', tier = 1, lane = LANE_BOT, buildingType = 'tower', id = TOWER_BOT_1},
	{kind = 'bot_t2', tier = 2, lane = LANE_BOT, buildingType = 'tower', id = TOWER_BOT_2},
	{kind = 'bot_t3', tier = 3, lane = LANE_BOT, buildingType = 'tower', id = TOWER_BOT_3},
	{kind = 'top_melee_rax', tier = 3, lane = LANE_TOP, buildingType = 'barracks', id = BARRACKS_TOP_MELEE},
	{kind = 'top_ranged_rax', tier = 3, lane = LANE_TOP, buildingType = 'barracks', id = BARRACKS_TOP_RANGED},
	{kind = 'mid_melee_rax', tier = 3, lane = LANE_MID, buildingType = 'barracks', id = BARRACKS_MID_MELEE},
	{kind = 'mid_ranged_rax', tier = 3, lane = LANE_MID, buildingType = 'barracks', id = BARRACKS_MID_RANGED},
	{kind = 'bot_melee_rax', tier = 3, lane = LANE_BOT, buildingType = 'barracks', id = BARRACKS_BOT_MELEE},
	{kind = 'bot_ranged_rax', tier = 3, lane = LANE_BOT, buildingType = 'barracks', id = BARRACKS_BOT_RANGED},
	{kind = 'base_t4_1', tier = 4, buildingType = 'tower', id = TOWER_BASE_1},
	{kind = 'base_t4_2', tier = 4, buildingType = 'tower', id = TOWER_BASE_2},
}

local PUSH_MODES = {}
if BOT_MODE_PUSH_TOWER_TOP ~= nil then PUSH_MODES[BOT_MODE_PUSH_TOWER_TOP] = true end
if BOT_MODE_PUSH_TOWER_MID ~= nil then PUSH_MODES[BOT_MODE_PUSH_TOWER_MID] = true end
if BOT_MODE_PUSH_TOWER_BOT ~= nil then PUSH_MODES[BOT_MODE_PUSH_TOWER_BOT] = true end

local DEFEND_MODES = {}
if BOT_MODE_DEFEND_TOWER_TOP ~= nil then DEFEND_MODES[BOT_MODE_DEFEND_TOWER_TOP] = true end
if BOT_MODE_DEFEND_TOWER_MID ~= nil then DEFEND_MODES[BOT_MODE_DEFEND_TOWER_MID] = true end
if BOT_MODE_DEFEND_TOWER_BOT ~= nil then DEFEND_MODES[BOT_MODE_DEFEND_TOWER_BOT] = true end

local CORE_POSITIONS = {safe_core = true, mid = true, off_core = true}
local SUPPORT_POSITIONS = {soft_support = true, hard_support = true}

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function GetTeamKey()
	return Safe(nil, function() return GetTeam() end)
end

local function GetNow()
	return Safe(0, function() return DotaTime() end) or 0
end

local function GetPlayerID(bot)
	return bot ~= nil and Safe(-1, function() return bot:GetPlayerID() end) or -1
end

local function GetHealthFraction(unit)
	if unit == nil then return nil end
	local health = Safe(nil, function() return unit:GetHealth() end)
	local maxHealth = Safe(nil, function() return unit:GetMaxHealth() end)
	if type(health) ~= 'number' or type(maxHealth) ~= 'number' or maxHealth <= 0 then
		return nil
	end
	return math.max(0, math.min(1, health / maxHealth))
end

local function GetVisibleHealthFraction(unit)
	if unit == nil or J.Utils == nil or J.Utils.GetVisibleHealth == nil then return nil end
	local health, maxHealth = J.Utils.GetVisibleHealth(unit)
	if type(health) ~= 'number' or type(maxHealth) ~= 'number' or maxHealth <= 0 then return nil end
	return math.max(0, math.min(1, health / maxHealth))
end

local function CanInspectUnit(unit)
	if unit == nil then return false end
	local ok, visible = pcall(function()
		if unit.IsNull ~= nil and unit:IsNull() then return false end
		if unit.CanBeSeen == nil or not unit:CanBeSeen() then return false end
		return unit.IsAlive == nil or unit:IsAlive()
	end)
	return ok and visible == true
end

local function Debug(bot, message)
	if Strategy.DEBUG ~= true then return end
	-- 基地压力可能由无具体 Bot 的团队快照输出；保留 team 后才能与共享目标严格关联。
	local dotaTime = GetNow()
	local gameTime = Safe(dotaTime, function() return GameTime() end) or dotaTime
	print(string.format('[BOT][Objective] schema=2 team=%s pid=%s %s dota_time=%.1f game_time=%.1f',
		tostring(GetTeamKey()), tostring(GetPlayerID(bot)), tostring(message), dotaTime, gameTime))
end

local function DebugLimited(bot, key, interval, message)
	if Strategy.DEBUG ~= true then return end
	local now = GetNow()
	local auditKey = tostring(GetTeamKey()) .. ':' .. tostring(key)
	if now - (auditLogTimes[auditKey] or -9999) < (interval or Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL) then
		return
	end
	auditLogTimes[auditKey] = now
	Debug(bot, message)
end

local function GetEnemyTower(towerID)
	if towerID == nil then return nil end
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	if enemyTeam == nil then return nil end
	return Safe(nil, function() return GetTower(enemyTeam, towerID) end)
end

local function GetLaneOuterTower(lane)
	for tier, towerID in ipairs(LANE_OUTER_TOWERS[lane] or {}) do
		local tower = GetEnemyTower(towerID)
		if tower ~= nil then return tower, tier, towerID end
	end
	return nil, nil, nil
end

local function IsObjectiveTargetValid(target)
	if target == nil then return false end
	if target.IsNull ~= nil and Safe(true, function() return target:IsNull() end) then return false end
	if target.IsAlive ~= nil and not Safe(false, function() return target:IsAlive() end) then return false end
	return true
end

local function ResolveDescriptorBuilding(team, descriptor)
	if team == nil or descriptor == nil or descriptor.id == nil then return nil end
	if descriptor.buildingType == 'tower' then
		return Safe(nil, function() return GetTower(team, descriptor.id) end)
	end
	if descriptor.buildingType == 'barracks' then
		return Safe(nil, function() return GetBarracks(team, descriptor.id) end)
	end
	return nil
end

local function GetManagedBuildingInfo(target, team)
	if target == nil then return nil end
	team = team or Safe(nil, function() return GetOpposingTeam() end)
	for _, descriptor in ipairs(BUILDING_DESCRIPTORS) do
		if ResolveDescriptorBuilding(team, descriptor) == target then return descriptor end
	end
	local ancient = team ~= nil and Safe(nil, function() return GetAncient(team) end) or nil
	if ancient == target then
		return {kind = 'ancient', tier = 4, buildingType = 'ancient'}
	end
	return nil
end

local function GetTargetKey(target)
	if target == nil then return 'nil' end
	local info = GetManagedBuildingInfo(target)
	local kind = info ~= nil and info.kind or 'building'
	local entityIndex = Safe(nil, function() return target:entindex() end)
	if entityIndex ~= nil then return tostring(kind) .. ':' .. tostring(entityIndex) end
	local name = Safe(nil, function() return target:GetUnitName() end)
	return tostring(kind) .. ':' .. tostring(name or 'unknown')
end

local function GetLocationDistance(first, second)
	if first == nil or second == nil then return math.huge end
	local dx = (first.x or 0) - (second.x or 0)
	local dy = (first.y or 0) - (second.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function Clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function IsOwnBaseBuildingUnderAttack(team)
	if team == nil or J.Utils == nil or J.Utils.IsBuildingAttackedByEnemy == nil then return false end
	for _, descriptor in ipairs(BUILDING_DESCRIPTORS) do
		if descriptor.tier >= 3 then
			local building = ResolveDescriptorBuilding(team, descriptor)
			if building ~= nil
			and Safe(false, function() return J.Utils.IsBuildingAttackedByEnemy(building) ~= nil end)
			then
				return true, descriptor.kind
			end
		end
	end
	local ancient = Safe(nil, function() return GetAncient(team) end)
	if ancient ~= nil
	and Safe(false, function() return J.Utils.IsBuildingAttackedByEnemy(ancient) ~= nil end)
	then
		return true, 'ancient'
	end
	return false, nil
end

local function HasCriticalBaseIntrusion(team, ancient)
	if team == nil or ancient == nil then return true, 'ancient_unknown' end
	for _, towerID in ipairs({TOWER_BASE_1, TOWER_BASE_2}) do
		local tower = towerID ~= nil and Safe(nil, function() return GetTower(team, towerID) end) or nil
		if tower ~= nil
		and (tonumber(Safe(0, function()
			return J.CountLastSeenEnemiesNearLoc(
				tower:GetLocation(), Strategy.BASE_TOWER_CRITICAL_RADIUS,
				Strategy.BASE_PRESSURE_LAST_SEEN_AGE)
		end)) or 0) > 0
		then
			return true, 'base_t4'
		end
	end
	if (tonumber(Safe(0, function()
		return J.CountLastSeenEnemiesNearLoc(
			ancient:GetLocation(), Strategy.BASE_ANCIENT_CRITICAL_RADIUS,
			Strategy.BASE_PRESSURE_LAST_SEEN_AGE)
	end)) or 0) > 0
	then
		return true, 'ancient'
	end
	return false, nil
end

local function BuildBaseThreatSnapshot(now, bot)
	local team = GetTeamKey()
	if team == nil then
		return {
			hardEmergency = true,
			coveredPressure = false,
			status = 'hard',
			reason = 'team_unknown',
			enemyCount = 0,
			effectiveAllyCount = 0,
		}
	end
	local cached = lastBaseThreatSnapshots[team]
	if cached ~= nil and cached.sampledAt == now then return cached end

	local ancient = Safe(nil, function() return GetAncient(team) end)
	if ancient == nil then
		cached = {
			sampledAt = now,
			hardEmergency = true,
			coveredPressure = false,
			status = 'hard',
			reason = 'ancient_unknown',
			enemyCount = 0,
			effectiveAllyCount = 0,
		}
		lastBaseThreatSnapshots[team] = cached
		return cached
	end

	local ancientLocation = Safe(nil, function() return ancient:GetLocation() end)
	if ancientLocation == nil then
		cached = {
			sampledAt = now,
			hardEmergency = true,
			coveredPressure = false,
			status = 'hard',
			reason = 'ancient_location_unknown',
			enemyCount = 0,
			effectiveAllyCount = 0,
		}
		lastBaseThreatSnapshots[team] = cached
		return cached
	end
	local enemyHeroCount = tonumber(Safe(0, function()
		return J.CountLastSeenEnemiesNearLoc(
			ancientLocation, Strategy.BASE_PRESSURE_RADIUS, Strategy.BASE_PRESSURE_LAST_SEEN_AGE)
	end)) or 0
	local enemyTpCount = #(Safe({}, function()
		return J.Utils.GetEnemyIdsInTpToLocation(ancientLocation, Strategy.BASE_PRESSURE_RADIUS)
	end) or {})
	local allyHeroCount = #(Safe({}, function()
		return J.GetAlliesNearLoc(ancientLocation, Strategy.BASE_PRESSURE_RADIUS)
	end) or {})
	local allyTpCount = #(Safe({}, function()
		return J.Utils.GetAllyIdsInTpToLocation(ancientLocation, Strategy.BASE_PRESSURE_RADIUS)
	end) or {})
	local enemyCount = enemyHeroCount + enemyTpCount
	local effectiveAllyCount = allyHeroCount + allyTpCount
	local criticalIntrusion, intrusionReason = HasCriticalBaseIntrusion(team, ancient)
	local buildingUnderAttack, attackedKind = IsOwnBaseBuildingUnderAttack(team)
	local hardEmergency = buildingUnderAttack
		or criticalIntrusion
		or enemyCount > effectiveAllyCount
	local coveredPressure = enemyCount > 0 and not hardEmergency
	local reason = 'none'
	if buildingUnderAttack then
		reason = 'building_attacked_' .. tostring(attackedKind or 'unknown')
	elseif criticalIntrusion then
		reason = 'critical_intrusion_' .. tostring(intrusionReason or 'unknown')
	elseif enemyCount > effectiveAllyCount then
		reason = 'uncovered_' .. tostring(enemyCount) .. '_vs_' .. tostring(effectiveAllyCount)
	elseif coveredPressure then
		reason = 'covered_' .. tostring(enemyCount) .. '_vs_' .. tostring(effectiveAllyCount)
	end

	cached = {
		sampledAt = now,
		enemyHeroCount = enemyHeroCount,
		enemyTpCount = enemyTpCount,
		enemyCount = enemyCount,
		allyHeroCount = allyHeroCount,
		allyTpCount = allyTpCount,
		effectiveAllyCount = effectiveAllyCount,
		criticalIntrusion = criticalIntrusion,
		buildingUnderAttack = buildingUnderAttack,
		hardEmergency = hardEmergency,
		coveredPressure = coveredPressure,
		status = hardEmergency and 'hard' or (coveredPressure and 'covered' or 'none'),
		reason = reason,
	}
	lastBaseThreatSnapshots[team] = cached
	if hardEmergency or coveredPressure then
		DebugLimited(bot, 'base_pressure_' .. cached.status, Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
			string.format('action=base_pressure_%s reason=%s enemy=%s enemy_tp=%s allies=%s ally_tp=%s',
				tostring(cached.status), tostring(reason), tostring(enemyHeroCount), tostring(enemyTpCount),
				tostring(allyHeroCount), tostring(allyTpCount)))
	end
	return cached
end

function Strategy.EvaluateHighGroundPermission(tier, context)
	if Strategy.ENABLED ~= true or (tonumber(tier) or 1) < 3 then return true, 'not_managed_high_ground' end
	context = context or {}
	local averageLevel = tonumber(context.averageLevel or context.allyAverageLevel)
	if averageLevel == nil then return false, 'average_level_unknown' end
	if averageLevel < Strategy.MIN_EXCEPTION_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND then
		return false, 'average_level_below_20'
	end
	local eligibleCount = tonumber(context.initialEligibleCount or context.eligibleCount or context.participantCount) or 0
	if eligibleCount < 4 then return false, 'eligible_below_4' end
	if averageLevel >= Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND then
		return true, 'default_level_20'
	end
	local creepDistance = tonumber(context.alliedCreepDistance or context.allyCreepDistance)
	if creepDistance == nil or creepDistance > Strategy.OBJECTIVE_ESCORT_CREEP_DISTANCE then
		return false, 'allied_creep_not_ready'
	end
	if context.backdoorProtected == true then return false, 'backdoor_protected' end
	local allyCount = tonumber(context.allyCount)
	local enemyCount = tonumber(context.enemyCount)
	if allyCount == nil or enemyCount == nil or allyCount < enemyCount then
		return false, 'local_numbers_disadvantage'
	end
	local allyPower = tonumber(context.allyPower)
	local enemyPower = tonumber(context.enemyPower)
	local localPowerSafe = context.localPowerAdvantage == true
		or (allyPower ~= nil and enemyPower ~= nil and allyPower >= enemyPower)
	if not localPowerSafe then return false, 'local_power_disadvantage' end
	if (tonumber(context.enemyTpCount) or 0) > 0 then return false, 'enemy_tp_incoming' end
	if context.doesTeamHaveAegis ~= true and context.hasAegis ~= true
	and (tonumber(context.enemyAlive) or math.huge) > 1
	then
		return false, 'no_aegis_enemy_alive_above_1'
	end
	return true, 'strict_level_23_exception'
end

local function GetRetryBaseDelay(reason)
	local delays = Strategy.OBJECTIVE_RETRY_BASE_DELAYS or {}
	if type(reason) == 'string' and string.find(reason, 'insufficient_eligible', 1, true) == 1 then
		return tonumber(delays.insufficient_eligible) or 0
	end
	return tonumber(delays[reason]) or 0
end

local function ClearObjectiveRetry(team, targetKey)
	if team == nil or objectiveRetryState[team] == nil then return end
	objectiveRetryState[team][targetKey] = nil
end

local function RecordObjectiveRetry(team, targetKey, reason, now)
	local baseDelay = GetRetryBaseDelay(reason)
	if team == nil or targetKey == nil or baseDelay <= 0 then return nil end
	objectiveRetryState[team] = objectiveRetryState[team] or {}
	local previous = objectiveRetryState[team][targetKey]
	local count = 1
	if reason ~= 'participant_churn'
	and previous ~= nil
	and previous.reason == reason
	and now - (previous.updatedAt or now) <= Strategy.OBJECTIVE_RETRY_RESET_TIME
	then
		count = math.min(Strategy.OBJECTIVE_RETRY_MAX_MULTIPLIER, (previous.count or 1) + 1)
	end
	local entry = {
		reason = reason,
		count = count,
		updatedAt = now,
		retryAfter = now + baseDelay * count,
		blockedLogged = false,
	}
	objectiveRetryState[team][targetKey] = entry
	return entry
end

local function GetObjectiveRetryBlock(team, targetKey, now)
	local entries = team ~= nil and objectiveRetryState[team] or nil
	local entry = entries ~= nil and entries[targetKey] or nil
	if entry == nil or now >= (entry.retryAfter or -9999) then return nil end
	return entry
end

local function GetActiveParticipantReselectBlocks(team, targetKey, now)
	local result = {}
	local targetBlocks = participantReselectBlocks[team] ~= nil
		and participantReselectBlocks[team][targetKey] or nil
	for playerID, blockedUntil in pairs(targetBlocks or {}) do
		if now < blockedUntil then
			result[playerID] = blockedUntil
		else
			targetBlocks[playerID] = nil
		end
	end
	return result
end

local function RecordParticipantReselectBlock(team, targetKey, playerID, blockedUntil)
	if team == nil or targetKey == nil or playerID == nil then return end
	participantReselectBlocks[team] = participantReselectBlocks[team] or {}
	participantReselectBlocks[team][targetKey] = participantReselectBlocks[team][targetKey] or {}
	participantReselectBlocks[team][targetKey][playerID] = blockedUntil
end

local function GetUnitLocation(unit)
	if unit == nil then return nil end
	return Safe(nil, function() return unit:GetLocation() end)
end

local function GetDistanceToLocation(unit, location)
	if unit == nil or location == nil then return math.huge end
	local distance = Safe(nil, function() return GetUnitToLocationDistance(unit, location) end)
	if type(distance) == 'number' then return distance end
	local unitLocation = GetUnitLocation(unit)
	if unitLocation == nil then return math.huge end
	local dx = (unitLocation.x or 0) - (location.x or 0)
	local dy = (unitLocation.y or 0) - (location.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function FormatParticipantIDs(objective)
	local values = {}
	for _, participant in ipairs(objective.participants or {}) do
		table.insert(values, string.format('%s:%s:%.1f', tostring(participant.playerID),
			tostring(participant.role), tonumber(participant.eta) or -1))
	end
	return table.concat(values, ',')
end

local function ClearObjective(team, reason, bot)
	local objective = objectives[team]
	if objective == nil then return nil end
	local now = GetNow()
	objectives[team] = nil
	objective.previousPhase = objective.phase
	objective.phase = Strategy.PHASE_DISENGAGE
	objective.releaseReason = reason or 'released'
	objective.releasedAt = now
	objective.expiresAt = now
	objective.expireAt = now
	local retryEntry = nil
	if objective.releaseReason == 'target_destroyed' then
		ClearObjectiveRetry(team, objective.targetKey)
		if (tonumber(objective.tier) or 1) >= 3
		and objective.targetKind ~= 'ancient'
		and objective.lane ~= nil
		then
			-- 高地建筑拆除后短暂锁住同一路线，等待死亡句柄清理并衔接兵营、T4 或远古。
			pushContinuations[team] = {
				lane = objective.lane,
				fromTargetKey = objective.targetKey,
				createdAt = now,
				expiresAt = now + Strategy.OBJECTIVE_HIGH_GROUND_CONTINUATION_DURATION,
			}
			Debug(bot, string.format('action=objective_continuation_start lane=%s from=%s duration=%.1f',
				tostring(objective.lane), tostring(objective.targetKey),
				Strategy.OBJECTIVE_HIGH_GROUND_CONTINUATION_DURATION))
		else
			pushContinuations[team] = nil
		end
	else
		retryEntry = RecordObjectiveRetry(team, objective.targetKey, objective.releaseReason, now)
	end
	objective.retryAfter = retryEntry ~= nil and retryEntry.retryAfter or nil
	lastObjectiveReleases[team] = objective
	local lastHealthDropAge = objective.lastHealthDropAt ~= nil
		and string.format('%.2f', math.max(0, now - objective.lastHealthDropAt)) or 'na'
	local siegeAttackableAge = objective.siegeAttackableSince ~= nil
		and string.format('%.2f', math.max(0, now - objective.siegeAttackableSince)) or 'na'
	Debug(bot, string.format('action=objective_release id=%s target=%s lane=%s tier=%s source=%s reason=%s elapsed=%.1f phase=%s retry_in=%.1f reassigns=%s last_health_drop_age=%s siege_attackable_age=%s participants=%s',
		tostring(objective.id), tostring(objective.targetKey), tostring(objective.lane), tostring(objective.tier),
		tostring(objective.source), tostring(objective.releaseReason),
		math.max(0, now - (objective.createdAt or now)), tostring(objective.previousPhase),
		retryEntry ~= nil and math.max(0, retryEntry.retryAfter - now) or 0,
		tostring(objective.reassignCount or 0),
		lastHealthDropAge, siegeAttackableAge,
		FormatParticipantIDs(objective)))
	return objective
end

local function GetActualBotAverageLevel(team)
	local players = Safe({}, function() return GetTeamPlayers(team) end) or {}
	local total = 0
	local botCount = 0
	for _, playerID in ipairs(players) do
		local isBot = Safe(nil, function() return IsPlayerBot(playerID) end)
		if type(isBot) ~= 'boolean' then return nil, nil end
		if isBot then
			local level = Safe(nil, function() return GetHeroLevel(playerID) end)
			if type(level) ~= 'number' or level < 1 then return nil, nil end
			total = total + level
			botCount = botCount + 1
		end
	end
	-- 只按当前队伍实际存在的 Bot 计平均值；任一 Bot 等级不可读时继续 fail-closed。
	if botCount == 0 then return nil, 0 end
	return total / botCount, botCount
end

local function CountEnemyOuterTowers()
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	if enemyTeam == nil or #OUTER_TOWERS == 0 then return nil end
	local count = 0
	for _, towerID in ipairs(OUTER_TOWERS) do
		local ok, tower = pcall(function() return GetTower(enemyTeam, towerID) end)
		-- 塔查询失败属于未知状态，不能被误判为六座外塔已经全部拆完。
		if not ok then return nil end
		if tower ~= nil then count = count + 1 end
	end
	return count
end

local function GetAssignedPosition(unit)
	if laneAssignmentOK and LaneAssignment ~= nil and LaneAssignment.GetAssignedPosition ~= nil then
		local position = Safe(nil, function() return LaneAssignment.GetAssignedPosition(unit) end)
		if position ~= nil then return position end
	end
	-- 测试夹具可直接提供 assignedRole；正式运行仍以分路框架为权威。
	return unit ~= nil and unit.assignedRole or nil
end

local function IsAlive(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.IsAlive ~= nil then return Safe(false, function() return unit:IsAlive() end) end
	return false
end

-- 只校验已有短租约，直接读取目标表以免资格检查递归刷新/释放任务。
function Strategy.HasLiveHighGroundAssaultAuthorization(unit)
	local authorization = unit ~= nil and unit.THD_HighGroundAssaultAuthorization or nil
	if type(authorization) ~= 'table' or GetNow() > (authorization.expiresAt or -9999) then return false end
	local objective = objectives[GetTeamKey()]
	return objective ~= nil and objective.id == authorization.objectiveID
		and (objective.phase == Strategy.PHASE_ESCORT or objective.phase == Strategy.PHASE_SIEGE)
		and objective.participantByID[GetPlayerID(unit)] ~= nil
end

local function GetParticipantBlockReason(unit, initialSelection)
	if not IsAlive(unit) then return 'dead' end
	local mode = Safe(BOT_MODE_NONE, function() return unit:GetActiveMode() end)
	-- mode 19 可在租约释放后短暂残留；团队资格只以控制器实际租约为准。
	if Safe(false, function() return J.IsTowerEscapeActive(unit) end) then
		return 'tower_escape'
	end
	if BOT_MODE_ROSHAN ~= nil
	and mode == BOT_MODE_ROSHAN
	and Safe(false, function() return J.IsRoshanCommitmentActive(unit) end)
	then
		return 'roshan'
	end
	-- Roam 与统一推进都是显式团队租约；任一方向都不能把同一 Bot 再分配给另一任务。
	if (BOT_MODE_ROAM ~= nil and mode == BOT_MODE_ROAM)
	or (BOT_MODE_TEAM_ROAM ~= nil and mode == BOT_MODE_TEAM_ROAM)
	then
		return 'roam'
	end
	if DEFEND_MODES[mode] == true
	and Safe(0, function() return unit:GetActiveModeDesire() end) >= 0.8
	then
		return 'base_defense'
	end
	if J.Retreat ~= nil and J.Retreat.ShouldYield ~= nil
	and not Strategy.HasLiveHighGroundAssaultAuthorization(unit)
	and Safe(true, function() return J.Retreat.ShouldYield(unit, J.Retreat.HIGH) end)
	then
		return 'high_retreat'
	end
	if initialSelection then
		if J.CanNotUseAction == nil or Safe(true, function() return J.CanNotUseAction(unit) end) then
			return 'cannot_act'
		end
		local healthFraction = GetVisibleHealthFraction(unit)
		if healthFraction == nil then return 'health_unknown' end
		if healthFraction < Strategy.OBJECTIVE_MIN_HEALTH then return 'health_below_60' end
	end
	return nil
end

local function GetRequiredParticipantCount(tier, eligibleCount)
	tier = tonumber(tier) or 1
	if tier <= 1 then return 2 end
	if tier == 2 then return 3 end
	-- 高地与基地阶段都固定四人；第五名健康 Bot 继续留给防守、发育或其他任务。
	return 4
end

local function GetIncomingTeleportEta(playerID, targetLocation, speed, teleports)
	local best = nil
	for _, teleport in pairs(teleports) do
		if teleport ~= nil and teleport.playerid == playerID and teleport.location ~= nil then
			local landingDistance = GetLocationDistance(teleport.location, targetLocation)
			if landingDistance <= 2600 then
				local remaining = tonumber(teleport.time_remaining) or 3.0
				local eta = math.max(0, remaining) + landingDistance / math.max(1, speed)
				if best == nil or eta < best then best = eta end
			end
		end
	end
	return best
end

local function BuildCandidate(member, playerID, targetLocation, teleports)
	local distance = GetDistanceToLocation(member, targetLocation)
	local speed = math.max(1, Safe(1, function() return member:GetCurrentMovementSpeed() end) or 1)
	local walkEta = distance / speed
	local teleportEta = GetIncomingTeleportEta(playerID, targetLocation, speed, teleports or {})
	return {
		unit = member,
		playerID = playerID,
		position = GetAssignedPosition(member),
		distance = distance,
		walkEta = walkEta,
		teleportEta = teleportEta,
		eta = teleportEta ~= nil and math.min(walkEta, teleportEta) or walkEta,
	}
end

local function GetInitialNoProgressDeadline(assignedAt, eta)
	local window = Clamp(
		(tonumber(eta) or 0) + Strategy.OBJECTIVE_ASSEMBLE_ETA_BUFFER,
		Strategy.OBJECTIVE_PARTICIPANT_MIN_NO_PROGRESS_TIME,
		Strategy.OBJECTIVE_PARTICIPANT_MAX_NO_PROGRESS_TIME
	)
	return assignedAt + window
end

local function GetAssembleWindow(participants)
	local slowestEta = 0
	for _, participant in ipairs(participants or {}) do
		slowestEta = math.max(slowestEta, tonumber(participant.eta) or 0)
	end
	local timeout = slowestEta + Strategy.OBJECTIVE_ASSEMBLE_ETA_BUFFER
	timeout = math.max(Strategy.OBJECTIVE_ASSEMBLE_TIMEOUT, timeout)
	timeout = math.min(Strategy.OBJECTIVE_ASSEMBLE_MAX_TIMEOUT, timeout)
	return timeout, slowestEta
end

local function GetEligibleCandidates(targetLocation)
	local team = GetTeamKey()
	if team == nil then return {} end
	local playerIDs = Safe({}, function() return GetTeamPlayers(team) end) or {}
	local teleports = Safe({}, function() return GetIncomingTeleports() end) or {}
	local candidates = {}
	for index, playerID in ipairs(playerIDs) do
		if Safe(false, function() return IsPlayerBot(playerID) end) == true then
			local member = Safe(nil, function() return GetTeamMember(index) end)
			if member ~= nil and GetParticipantBlockReason(member, true) == nil then
				table.insert(candidates, BuildCandidate(member, playerID, targetLocation, teleports))
			end
		end
	end
	table.sort(candidates, function(first, second)
		if math.abs(first.eta - second.eta) > 0.001 then return first.eta < second.eta end
		return first.playerID < second.playerID
	end)
	return candidates
end

local function GetClosestAlliedCreepDistance(targetLocation)
	if targetLocation == nil or UNIT_LIST_ALLIED_CREEPS == nil then return nil end
	local closest = nil
	for _, creep in pairs(Safe({}, function() return GetUnitList(UNIT_LIST_ALLIED_CREEPS) end) or {}) do
		local visibleHealth = J.Utils ~= nil and J.Utils.GetVisibleHealth ~= nil
			and Safe(nil, function() return J.Utils.GetVisibleHealth(creep) end) or nil
		if visibleHealth ~= nil then
			local distance = GetDistanceToLocation(creep, targetLocation)
			if closest == nil or distance < closest then closest = distance end
		end
	end
	return closest
end

local function HasManagedBackdoorProtection(target)
	-- Bot API 不允许读取不可见建筑的 modifier；不可读时按仍受保护处理。
	if not CanInspectUnit(target) then return true end
	for _, modifierName in ipairs({
		'modifier_fountain_glyph',
		'modifier_backdoor_protection',
		'modifier_backdoor_protection_in_base',
		'modifier_backdoor_protection_active',
	}) do
		if Safe(false, function() return target:HasModifier(modifierName) end) then return true end
	end
	local info = GetManagedBuildingInfo(target)
	if info ~= nil and info.tier >= 2 then
		local antiBackdoorStopped = Safe(nil, function()
			return target:HasModifier('modifier_thdots_anti_bd_stop')
		end)
		return antiBackdoorStopped ~= true
	end
	return false
end

local function SumCombatPower(units)
	local total = 0
	for _, unit in pairs(units or {}) do
		total = total + (tonumber(Safe(0, function() return CombatPower.Estimate(unit) end)) or 0)
	end
	return total
end

function Strategy.GetEligibleParticipantCount(targetOrLocation)
	if not Strategy.IsEnabled() then return 0 end
	local targetLocation = targetOrLocation
	if targetOrLocation ~= nil and targetOrLocation.GetLocation ~= nil then
		targetLocation = GetUnitLocation(targetOrLocation)
	end
	if targetLocation == nil then return 0 end
	return #GetEligibleCandidates(targetLocation)
end

function Strategy.GetHighGroundPermissionContext(target, extra)
	extra = extra or {}
	local context = {}
	for key, value in pairs(extra) do context[key] = value end
	local targetLocation = GetUnitLocation(target)
	if context.averageLevel == nil then
		local team = GetTeamKey()
		context.averageLevel = team ~= nil and GetActualBotAverageLevel(team) or nil
	end
	if context.initialEligibleCount == nil then
		context.initialEligibleCount = Strategy.GetEligibleParticipantCount(targetLocation)
	end
	if context.alliedCreepDistance == nil then
		context.alliedCreepDistance = GetClosestAlliedCreepDistance(targetLocation)
	end
	if context.backdoorProtected == nil then
		context.backdoorProtected = HasManagedBackdoorProtection(target)
	end
	local allies = nil
	local enemies = nil
	if targetLocation ~= nil
	and (context.allyCount == nil or context.enemyCount == nil
		or context.allyPower == nil or context.enemyPower == nil)
	then
		allies = Safe({}, function() return J.GetAlliesNearLoc(targetLocation, Strategy.HIGH_GROUND_LOCAL_RADIUS) end) or {}
		enemies = Safe({}, function() return J.GetEnemiesNearLoc(targetLocation, Strategy.HIGH_GROUND_LOCAL_RADIUS) end) or {}
	end
	context.allyCount = context.allyCount or #(allies or {})
	context.enemyCount = context.enemyCount or #(enemies or {})
	context.allyPower = context.allyPower or SumCombatPower(allies)
	context.enemyPower = context.enemyPower or SumCombatPower(enemies)
	if context.localPowerAdvantage == nil then
		context.localPowerAdvantage = context.allyPower >= context.enemyPower
	end
	if context.enemyTpCount == nil then
		context.enemyTpCount = targetLocation ~= nil and #(Safe({}, function()
			return J.Utils.GetEnemyIdsInTpToLocation(targetLocation, Strategy.HIGH_GROUND_LOCAL_RADIUS)
		end) or {}) or 0
	end
	if context.doesTeamHaveAegis == nil then
		context.doesTeamHaveAegis = Safe(false, function() return J.DoesTeamHaveAegis() end) == true
	end
	if context.enemyAlive == nil then
		context.enemyAlive = tonumber(Safe(nil, function() return J.GetNumOfAliveHeroes(true) end))
	end
	return context
end

local function HasPositionGroup(participants, group)
	for _, participant in ipairs(participants) do
		if group[participant.position] == true then return true end
	end
	return false
end

local function AddFirstMatching(selected, selectedIDs, candidates, predicate)
	for _, candidate in ipairs(candidates) do
		if not selectedIDs[candidate.playerID] and predicate(candidate) then
			table.insert(selected, candidate)
			selectedIDs[candidate.playerID] = true
			return true
		end
	end
	return false
end

local function AssignParticipantRoles(participants)
	for _, participant in ipairs(participants) do participant.role = Strategy.ROLE_COVER end
	local used = {}
	local function AssignFirst(role, predicate)
		for index, participant in ipairs(participants) do
			if not used[index] and predicate(participant) then
				participant.role = role
				used[index] = true
				return true
			end
		end
		return false
	end
	if not AssignFirst(Strategy.ROLE_BUILDING_DAMAGE, function(candidate)
		return CORE_POSITIONS[candidate.position] == true
	end) and #participants > 0 then
		participants[1].role = Strategy.ROLE_BUILDING_DAMAGE
		used[1] = true
	end
	AssignFirst(Strategy.ROLE_FRONTLINE, function(candidate)
		return candidate.position == 'off_core' or candidate.position == 'soft_support'
	end)
	AssignFirst(Strategy.ROLE_WAVE_CLEAR, function(candidate)
		return candidate.position == 'mid' or candidate.position == 'safe_core'
	end)
end

local function BuildParticipantSelection(tier, targetLocation, retained, now, excludedIDs, requiredOverride)
	local allCandidates = GetEligibleCandidates(targetLocation)
	local candidates = {}
	for _, candidate in ipairs(allCandidates) do
		local excludedUntil = excludedIDs ~= nil and excludedIDs[candidate.playerID] or nil
		local excluded = excludedUntil == true
			or (type(excludedUntil) == 'number' and now < excludedUntil)
		if not excluded then
			table.insert(candidates, candidate)
		end
	end
	local retainedOutsideCandidates = 0
	local candidateIDs = {}
	for _, candidate in ipairs(candidates) do candidateIDs[candidate.playerID] = true end
	for _, oldParticipant in ipairs(retained or {}) do
		if not candidateIDs[oldParticipant.playerID] then retainedOutsideCandidates = retainedOutsideCandidates + 1 end
	end
	local eligibleCount = #candidates + retainedOutsideCandidates
	local requiredCount = tonumber(requiredOverride) or GetRequiredParticipantCount(tier, eligibleCount)
	if requiredCount <= 0 or #candidates + retainedOutsideCandidates < requiredCount then
		return nil, requiredCount, eligibleCount
	end

	local candidateByID = {}
	for _, candidate in ipairs(candidates) do candidateByID[candidate.playerID] = candidate end
	local selected = {}
	local selectedIDs = {}
	for _, oldParticipant in ipairs(retained or {}) do
		local candidate = candidateByID[oldParticipant.playerID]
		if candidate == nil and GetParticipantBlockReason(oldParticipant.unit, false) == nil then
			candidate = oldParticipant
		end
		if candidate ~= nil and #selected < requiredCount then
			candidate.assignedAt = oldParticipant.assignedAt or now
			candidate.bestDistance = oldParticipant.bestDistance
			candidate.lastApproachProgressAt = oldParticipant.lastApproachProgressAt
			candidate.noProgressDeadline = oldParticipant.noProgressDeadline
			candidate.teleportGraceUntil = oldParticipant.teleportGraceUntil
			candidate.arrived = oldParticipant.arrived
			table.insert(selected, candidate)
			selectedIDs[candidate.playerID] = true
		end
	end

	local slots = requiredCount - #selected
	if slots > 0 and not HasPositionGroup(selected, CORE_POSITIONS) then
		if AddFirstMatching(selected, selectedIDs, candidates, function(candidate)
			return CORE_POSITIONS[candidate.position] == true
		end) then slots = slots - 1 end
	end
	if slots > 0 and not HasPositionGroup(selected, SUPPORT_POSITIONS) then
		if AddFirstMatching(selected, selectedIDs, candidates, function(candidate)
			return SUPPORT_POSITIONS[candidate.position] == true
		end) then slots = slots - 1 end
	end
	for _, candidate in ipairs(candidates) do
		if slots <= 0 then break end
		if not selectedIDs[candidate.playerID] then
			table.insert(selected, candidate)
			selectedIDs[candidate.playerID] = true
			slots = slots - 1
		end
	end
	for _, participant in ipairs(selected) do
		participant.assignedAt = participant.assignedAt or now
		participant.lastApproachProgressAt = participant.lastApproachProgressAt or now
		participant.bestDistance = participant.bestDistance or participant.distance
		participant.noProgressDeadline = participant.noProgressDeadline
			or GetInitialNoProgressDeadline(participant.assignedAt, participant.eta)
		if participant.teleportEta ~= nil then
			participant.teleportGraceUntil = math.max(
				participant.teleportGraceUntil or now,
				now + participant.teleportEta + Strategy.OBJECTIVE_ASSEMBLE_ETA_BUFFER)
		end
	end
	if #selected < requiredCount then return nil, requiredCount, eligibleCount end
	AssignParticipantRoles(selected)
	return selected, requiredCount, eligibleCount
end

local function RebuildParticipantMap(objective)
	objective.participantByID = {}
	for _, participant in ipairs(objective.participants or {}) do
		objective.participantByID[participant.playerID] = participant
	end
end

local function RefreshParticipantTeleportGrace(participant, targetLocation, now)
	if participant == nil or targetLocation == nil then return end
	local teleports = Safe({}, function() return GetIncomingTeleports() end) or {}
	local speed = math.max(1, Safe(1, function() return participant.unit:GetCurrentMovementSpeed() end) or 1)
	local teleportEta = GetIncomingTeleportEta(participant.playerID, targetLocation, speed, teleports)
	if teleportEta ~= nil then
		participant.teleportEta = teleportEta
		participant.teleportGraceUntil = math.max(
			participant.teleportGraceUntil or now,
			now + teleportEta + Strategy.OBJECTIVE_ASSEMBLE_ETA_BUFFER)
	end
end

function Strategy.ApplyTowerEscapeParticipantGrace(participant, now)
	if type(participant) ~= 'table' then return false end
	now = tonumber(now) or DotaTime()
	if participant.towerEscapeGraceActive ~= true then
		local grace = J.GetTowerEscapeObjectiveGrace ~= nil
			and J.GetTowerEscapeObjectiveGrace() or 2.5
		participant.towerEscapeGraceActive = true
		participant.noProgressDeadline = math.max(participant.noProgressDeadline or now, now) + grace
		participant.towerEscapeGraceDeadline = participant.noProgressDeadline
	end
	return now < (participant.towerEscapeGraceDeadline or participant.noProgressDeadline or now)
end

local function ParticipantNeedsReplacement(participant, objective, now)
	if IsAlive(participant.unit)
	and Safe(false, function() return J.IsTowerEscapeActive(participant.unit) end)
	then
		if Strategy.ApplyTowerEscapeParticipantGrace(participant, now) then return false, nil end
		return true, 'tower_escape_timeout'
	end
	participant.towerEscapeGraceActive = false
	participant.towerEscapeGraceDeadline = nil
	local reason = GetParticipantBlockReason(participant.unit, false)
	if reason ~= nil then return true, reason end
	RefreshParticipantTeleportGrace(participant, GetUnitLocation(objective.target), now)
	local currentDistance = GetDistanceToLocation(participant.unit, GetUnitLocation(objective.target))
	if currentDistance <= Strategy.OBJECTIVE_ARRIVAL_DISTANCE then
		participant.arrived = true
		participant.bestDistance = math.min(participant.bestDistance or currentDistance, currentDistance)
		participant.noProgressDeadline = now + Strategy.OBJECTIVE_PARTICIPANT_PROGRESS_EXTENSION
	elseif (participant.bestDistance or currentDistance) - currentDistance
		>= Strategy.OBJECTIVE_APPROACH_PROGRESS_DISTANCE
	then
		participant.bestDistance = currentDistance
		participant.lastApproachProgressAt = now
		participant.noProgressDeadline = now + Strategy.OBJECTIVE_PARTICIPANT_PROGRESS_EXTENSION
	end
	if not participant.arrived
	and now >= (participant.noProgressDeadline or math.huge)
	and now >= (participant.teleportGraceUntil or -9999)
	then
		return true, 'no_progress'
	end
	return false, nil
end

-- 四人是创建门槛；新鲜可拆窗口内允许三名健康、在场且人数不劣的原成员续攻。
-- 不延长进度/掉血期限，兵线或安全窗口失效后仍按原有规则退出。
local function CanContinueLocalSiege(objective, retained, now)
	if (tonumber(objective.tier) or 0) < 3 or objective.phase ~= Strategy.PHASE_SIEGE
	or objective.defaultHighGroundUnlocked ~= true or #retained < 3
	or now - (objective.lastAttackableObservationAt or -9999) > 1.5
	or now - (objective.lastCreepSupportAt or -9999) > 1.5
	or objective.lastBackdoorProtected ~= false
	or not J.IsValidBuilding(objective.target) or not J.CanBeAttacked(objective.target) then return false end
	local center = GetUnitLocation(objective.target)
	local localCount = 0
	for _, participant in ipairs(retained) do
		if GetParticipantBlockReason(participant.unit, false) == nil
		and (GetVisibleHealthFraction(participant.unit) or 0) > Strategy.HIGH_GROUND_COMMIT_MIN_HP
		and GetDistanceToLocation(participant.unit, center) <= Strategy.OBJECTIVE_ARRIVAL_DISTANCE then
			localCount = localCount + 1
		end
	end
	local enemies = J.GetEnemiesNearLoc(center, Strategy.OBJECTIVE_ARRIVAL_DISTANCE)
	return localCount >= 3 and localCount >= #enemies
end

local function RefreshParticipants(objective, bot)
	if objective == nil then return false end
	local now = GetNow()
	local retained = {}
	local replacementReason = nil
	local excludedIDs = {}
	local removedIDs = {}
	objective.blockedParticipantIDs = objective.blockedParticipantIDs or {}
	local team = GetTeamKey()
	local persistedBlocks = GetActiveParticipantReselectBlocks(team, objective.targetKey, now)
	for playerID, blockedUntil in pairs(persistedBlocks) do
		objective.blockedParticipantIDs[playerID] = blockedUntil
	end
	for playerID, blockedUntil in pairs(objective.blockedParticipantIDs) do
		if now >= blockedUntil then objective.blockedParticipantIDs[playerID] = nil end
	end
	for _, participant in ipairs(objective.participants or {}) do
		local replace, reason = ParticipantNeedsReplacement(participant, objective, now)
		if replace then
			replacementReason = replacementReason or reason
			excludedIDs[participant.playerID] = true
			table.insert(removedIDs, tostring(participant.playerID) .. ':' .. tostring(reason))
			if reason == 'no_progress' then
				objective.blockedParticipantIDs[participant.playerID] = now
					+ Strategy.OBJECTIVE_NO_PROGRESS_RESELECT_BLOCK_TIME
				RecordParticipantReselectBlock(team, objective.targetKey, participant.playerID,
					objective.blockedParticipantIDs[participant.playerID])
			end
		else
			table.insert(retained, participant)
		end
	end
	if replacementReason == nil then
		if not objective.continuingShortHanded then return true end
		if not CanContinueLocalSiege(objective, retained, now) then
			ClearObjective(team, 'local_siege_window_lost', bot)
			return false
		end
		replacementReason = 'restore_full_group'
	end
	if now - (objective.lastAssignmentAt or objective.createdAt or now)
		< Strategy.OBJECTIVE_ASSIGNMENT_STABLE_TIME
	then
		return true
	end
	if (objective.reassignCount or 0) >= Strategy.OBJECTIVE_MAX_REASSIGNMENTS then
		ClearObjective(team, 'participant_churn', bot)
		return false
	end
	for playerID, blockedUntil in pairs(objective.blockedParticipantIDs) do
		if now < blockedUntil then excludedIDs[playerID] = blockedUntil end
	end

	local participants, requiredCount, eligibleCount = BuildParticipantSelection(
		objective.tier,
		GetUnitLocation(objective.target),
		retained,
		now,
		excludedIDs,
		objective.requiredCount
	)
	if participants == nil then
		if CanContinueLocalSiege(objective, retained, now) then
			objective.participants = retained
			objective.continuingShortHanded = true
			objective.lastAssignmentAt = now
			local hasDamageRole = false
			for _, participant in ipairs(retained) do
				if participant.role == Strategy.ROLE_BUILDING_DAMAGE then hasDamageRole = true end
			end
			if not hasDamageRole then AssignParticipantRoles(retained) end
			RebuildParticipantMap(objective)
			DebugLimited(bot, 'local_siege_continue:' .. objective.id, Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
				string.format('action=objective_local_continue id=%s count=%s required=%s removed=%s participants=%s',
					objective.id, #retained, objective.requiredCount, table.concat(removedIDs, ','), FormatParticipantIDs(objective)))
			return true
		end
		Debug(bot, string.format('action=objective_replacement_failed id=%s removed=%s eligible=%s required=%s',
			objective.id, table.concat(removedIDs, ','), eligibleCount, requiredCount))
		ClearObjective(team, 'insufficient_eligible_participants_' .. tostring(eligibleCount)
			.. '_of_' .. tostring(requiredCount), bot)
		return false
	end
	local oldIDs = {}
	for _, participant in ipairs(objective.participants or {}) do oldIDs[participant.playerID] = true end
	local addedIDs = {}
	for _, participant in ipairs(participants) do
		if oldIDs[participant.playerID] ~= true then table.insert(addedIDs, tostring(participant.playerID)) end
	end
	objective.participants = participants
	objective.continuingShortHanded = false
	-- 创建时的限额属于任务契约，换人时只补位，不能随可用人数缩成零。
	objective.requiredCount = objective.requiredCount or requiredCount
	objective.lastAssignmentAt = now
	objective.reassignCount = (objective.reassignCount or 0) + 1
	if objective.phase == Strategy.PHASE_ASSEMBLE then
		local assembleWindow = GetAssembleWindow(participants)
		objective.assembleDeadline = math.min(
			objective.absoluteDeadline or (now + Strategy.OBJECTIVE_ABSOLUTE_MAX_DURATION),
			math.max(objective.assembleDeadline or now, now + assembleWindow)
		)
		objective.overallDeadline = math.min(
			objective.absoluteDeadline or (now + Strategy.OBJECTIVE_ABSOLUTE_MAX_DURATION),
			math.max(objective.overallDeadline or now,
				objective.assembleDeadline + Strategy.OBJECTIVE_POST_ASSEMBLE_MAX_DURATION)
		)
		objective.expiresAt = math.max(objective.expiresAt or now, objective.assembleDeadline)
		objective.expireAt = objective.expiresAt
	end
	RebuildParticipantMap(objective)
	Debug(bot, string.format('action=objective_reassign id=%s reason=%s removed=%s added=%s count=%s participants=%s',
		tostring(objective.id), tostring(replacementReason), table.concat(removedIDs, ','),
		table.concat(addedIDs, ','), tostring(objective.reassignCount), FormatParticipantIDs(objective)))
	return true
end

local function ShouldLogObjectiveProgress(objective, now, reason)
	objective.progressLogAt = objective.progressLogAt or {}
	local key = reason
	local interval = nil
	if type(reason) == 'string' and string.find(reason, 'participant_approach_', 1, true) == 1 then
		key = 'participant_approach'
		interval = Strategy.OBJECTIVE_PROGRESS_LOG_INTERVAL
	elseif reason == 'ally_creep_advance' then
		interval = Strategy.OBJECTIVE_PROGRESS_LOG_INTERVAL
	elseif reason == 'building_health_drop' then
		interval = Strategy.OBJECTIVE_HEALTH_LOG_INTERVAL
	end
	if interval ~= nil
	and now - (objective.progressLogAt[key] or -9999) < interval
	then
		return false
	end
	objective.progressLogAt[key] = now
	return true
end

local function RenewObjective(objective, now, reason, bot)
	if objective == nil then return end
	objective.lastProgressAt = now
	objective.lastProgressReason = reason
	if reason == 'building_health_drop' then
		objective.overallDeadline = math.min(
			objective.absoluteDeadline or (now + Strategy.OBJECTIVE_ABSOLUTE_MAX_DURATION),
			math.max(objective.overallDeadline or now, now + Strategy.OBJECTIVE_SIEGE_PROGRESS_EXTENSION)
		)
	end
	local leaseDeadline = now + Strategy.OUTER_COMMIT_DURATION
	if objective.phase == Strategy.PHASE_ASSEMBLE then
		leaseDeadline = math.max(leaseDeadline, objective.assembleDeadline or now)
	end
	objective.expiresAt = math.min(objective.overallDeadline or now, leaseDeadline)
	objective.expireAt = objective.expiresAt
	if ShouldLogObjectiveProgress(objective, now, reason) then
		Debug(bot, string.format('action=objective_progress id=%s phase=%s reason=%s expires_in=%.1f',
			tostring(objective.id), tostring(objective.phase), tostring(reason),
			math.max(0, objective.expiresAt - now)))
	end
end

local function RefreshVisibleObjectiveHealth(objective, now, bot, visibleHealth)
	if objective == nil then return false end
	if visibleHealth == nil and CanInspectUnit(objective.target) then
		visibleHealth = Safe(nil, function() return objective.target:GetHealth() end)
	end
	visibleHealth = tonumber(visibleHealth)
	if visibleHealth == nil then return false end

	local healthDropped = objective.lastVisibleTargetHealth ~= nil
		and visibleHealth < objective.lastVisibleTargetHealth
	if healthDropped then
		objective.lastHealthDropAt = now
		objective.siegeAttackableSince = now
		RenewObjective(objective, now, 'building_health_drop', bot)
	end
	objective.lastVisibleTargetHealth = visibleHealth
	return healthDropped
end

local function TransitionPhase(objective, phase, bot, reason)
	if objective == nil or objective.phase == phase then return false end
	local previous = objective.phase
	local now = GetNow()
	objective.previousPhase = previous
	objective.phase = phase
	objective.phaseChangedAt = now
	if phase == Strategy.PHASE_ESCORT or phase == Strategy.PHASE_SIEGE then
		objective.overallDeadline = math.min(
			objective.absoluteDeadline or (now + Strategy.OBJECTIVE_ABSOLUTE_MAX_DURATION),
			math.max(objective.overallDeadline or now,
				now + Strategy.OBJECTIVE_POST_ASSEMBLE_MAX_DURATION)
		)
		objective.expiresAt = math.min(objective.overallDeadline,
			math.max(objective.expiresAt or now, now + Strategy.OUTER_COMMIT_DURATION))
		objective.expireAt = objective.expiresAt
	end
	Debug(bot, string.format('action=objective_phase id=%s from=%s to=%s reason=%s',
		tostring(objective.id), tostring(previous), tostring(phase), tostring(reason or 'state_change')))
	return true
end

function Strategy.IsEnabled()
	return Strategy.ENABLED == true
end

function Strategy.IsTeamAhead(state)
	if type(state) ~= 'table' then return false end
	local allyAverage = tonumber(state.allyAverageLevel)
	local enemyAverage = tonumber(state.enemyAverageLevel)
	if allyAverage == nil or enemyAverage == nil then return false end
	if (tonumber(state.allyAlive) or 0) < (tonumber(state.enemyAlive) or 0) then return false end
	if allyAverage - enemyAverage >= Strategy.MIN_LEVEL_LEAD then return true end
	local allyKills = math.max(0, tonumber(state.allyKills) or 0)
	local enemyKills = math.max(0, tonumber(state.enemyKills) or 0)
	local killRatio = (allyKills + 1) / (enemyKills + 1)
	return killRatio >= Strategy.MIN_KILL_RATIO
		and allyAverage + Strategy.MAX_LEVEL_DEFICIT_FOR_KILL_LEAD >= enemyAverage
end

function Strategy.GetBaseThreatSnapshot(state, bot)
	if not Strategy.IsEnabled() then return nil end
	if type(state) == 'table' and type(state.baseThreat) == 'table' then return state.baseThreat end
	if type(state) == 'table' then
		local hardEmergency = state.baseDefenseRequired == true
		local coveredPressure = state.basePressureCovered == true and not hardEmergency
		return {
			hardEmergency = hardEmergency,
			coveredPressure = coveredPressure,
			status = hardEmergency and 'hard' or (coveredPressure and 'covered' or 'none'),
			reason = 'caller_state',
			enemyCount = tonumber(state.baseEnemyCount) or 0,
			effectiveAllyCount = tonumber(state.effectiveBaseAllies) or 0,
		}
	end
	return BuildBaseThreatSnapshot(GetNow(), bot)
end

function Strategy.GetState()
	local team = Safe(nil, function() return GetTeam() end)
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	local now = GetNow()
	local allyAverageLevel, allyBotCount = nil, 0
	local enemyAverageLevel, enemyBotCount = nil, 0
	if team ~= nil then allyAverageLevel, allyBotCount = GetActualBotAverageLevel(team) end
	if enemyTeam ~= nil then enemyAverageLevel, enemyBotCount = GetActualBotAverageLevel(enemyTeam) end
	local baseThreat = BuildBaseThreatSnapshot(now, nil)
	local state = {
		time = now,
		outerTowersRemaining = CountEnemyOuterTowers(),
		allyAverageLevel = allyAverageLevel,
		enemyAverageLevel = enemyAverageLevel,
		allyBotCount = allyBotCount or 0,
		enemyBotCount = enemyBotCount or 0,
		allyAlive = Safe(0, function() return J.GetNumOfAliveHeroes(false) end) or 0,
		enemyAlive = Safe(0, function() return J.GetNumOfAliveHeroes(true) end) or 0,
		allyKills = Safe(0, function() return J.GetNumOfTeamTotalKills(false) end) or 0,
		enemyKills = Safe(0, function() return J.GetNumOfTeamTotalKills(true) end) or 0,
		baseThreat = baseThreat,
		baseStatus = baseThreat.status,
		baseDefenseRequired = baseThreat.hardEmergency == true,
		basePressureCovered = baseThreat.coveredPressure == true,
	}
	state.teamAhead = Strategy.IsTeamAhead(state)
	state.conversionOpportunity = Strategy.GetConversionOpportunity()
	state.objective = Strategy.GetPushObjective()
	state.outerCommitment = state.objective
	return state
end

function Strategy.GetPushObjective(deferVisibleHealthRefresh)
	if not Strategy.IsEnabled() then return nil end
	local team = GetTeamKey()
	if team == nil then return nil end
	local objective = objectives[team]
	if objective == nil then return nil end
	local now = GetNow()

	if objective.towerID ~= nil then objective.target = GetEnemyTower(objective.towerID) end
	objective.tower = objective.target
	if not IsObjectiveTargetValid(objective.target) then
		ClearObjective(team, 'target_destroyed', nil)
		return nil
	end
	if now >= (objective.overallDeadline or -9999) then
		ClearObjective(team, 'maximum_duration', nil)
		return nil
	end
	if objective.phase == Strategy.PHASE_ASSEMBLE
	and now >= (objective.assembleDeadline or -9999)
	then
		ClearObjective(team, 'assemble_timeout', nil)
		return nil
	end
	if deferVisibleHealthRefresh ~= true then
		-- 目标模式可能被短暂抢占；由所有高频读取者共同维护真实掉血和 5 秒攻城停滞期限。
		RefreshVisibleObjectiveHealth(objective, now, nil, nil)
		if objective.phase == Strategy.PHASE_SIEGE
		and objective.siegeAttackableSince ~= nil
		and now - objective.siegeAttackableSince >= Strategy.OBJECTIVE_SIEGE_NO_DAMAGE_TIMEOUT
		then
			ClearObjective(team, 'siege_no_health_drop', nil)
			return nil
		end
	end
	if now >= (objective.expiresAt or objective.expireAt or -9999) then
		ClearObjective(team, 'progress_lease_expired', nil)
		return nil
	end
	if not RefreshParticipants(objective, nil) then return nil end
	return objective
end

-- 第一阶段调用方继续通过旧名字读取；内部只保留一份统一目标状态。
function Strategy.GetOuterTowerCommitment()
	return Strategy.GetPushObjective()
end

function Strategy.GetLastObjectiveRelease()
	local team = GetTeamKey()
	return team ~= nil and lastObjectiveReleases[team] or nil
end

function Strategy.GetPushContinuationLane()
	if not Strategy.IsEnabled() then return nil end
	local team = GetTeamKey()
	if team == nil then return nil end
	local continuation = pushContinuations[team]
	if continuation == nil then return nil end
	if GetNow() >= (continuation.expiresAt or -9999) then
		pushContinuations[team] = nil
		return nil
	end
	return continuation.lane
end

function Strategy.NoteRoamKill(lane, missionID, bot)
	if not Strategy.IsEnabled() then return false end
	local team = GetTeamKey()
	if team == nil then return false end
	local now = GetNow()
	conversionOpportunities[team] = {
		lane = lane,
		missionID = missionID,
		createdAt = now,
		expireAt = now + Strategy.CONVERSION_OPPORTUNITY_DURATION,
	}
	Debug(bot, string.format('action=conversion_opportunity source=roam_kill mission=%s lane=%s duration=%.1f',
		tostring(missionID or 'unknown'), tostring(lane or 'auto'), Strategy.CONVERSION_OPPORTUNITY_DURATION))
	return true
end

function Strategy.GetConversionOpportunity()
	if not Strategy.IsEnabled() then return nil end
	local team = GetTeamKey()
	if team == nil then return nil end
	local opportunity = conversionOpportunities[team]
	if opportunity ~= nil and GetNow() >= (opportunity.expireAt or -9999) then
		conversionOpportunities[team] = nil
		return nil
	end
	return opportunity
end

local function HasActiveTowerAggro(towerThreat)
	if type(towerThreat) ~= 'table' then return false end
	if towerThreat.active == true then return true end
	for _, detail in pairs(towerThreat.details or {}) do
		if type(detail) == 'table'
		and (detail.locked == true or (tonumber(detail.incomingCount) or 0) > 0)
		then
			return true
		end
	end
	return false
end

function Strategy.ShouldWithdrawConversionPush(bot, towerThreat, commitment)
	if not Strategy.IsEnabled() then return false, nil end
	commitment = commitment or Strategy.GetPushObjective()
	if type(commitment) ~= 'table' or commitment.source ~= 'roam_kill' then
		return false, nil
	end
	if HasActiveTowerAggro(towerThreat) then return true, 'tower_aggro' end
	local healthFraction = GetHealthFraction(bot)
	if healthFraction == nil then return true, 'health_unknown' end
	if healthFraction <= Strategy.CONVERSION_PUSH_MIN_HEALTH then return true, 'low_health' end
	return false, nil
end

function Strategy.TryCreatePushObjective(bot, lane, state, target, tier)
	if not Strategy.IsEnabled() then return nil end
	state = state or Strategy.GetState()
	local now = tonumber(state.time) or GetNow()
	local baseThreat = Strategy.GetBaseThreatSnapshot(state, bot)
	if now < Strategy.OUTER_PUSH_START_TIME
	or (baseThreat ~= nil and baseThreat.hardEmergency == true)
	then
		return nil
	end

	local team = GetTeamKey()
	if team == nil then return nil end
	local continuationLane = Strategy.GetPushContinuationLane()
	if continuationLane ~= nil and continuationLane ~= lane then return nil end
	local opportunity = state.conversionOpportunity or Strategy.GetConversionOpportunity()
	local existing = Strategy.GetPushObjective()
	local preemptExisting = nil
	if existing ~= nil then
		local conversionMatchesLane = opportunity ~= nil
			and (opportunity.lane == nil or opportunity.lane == lane)
		if conversionMatchesLane and (tonumber(existing.tier) or 3) <= 2 then
			if existing.lane == lane then
				if existing.source ~= 'roam_kill' then
					existing.source = 'roam_kill'
					existing.missionID = opportunity.missionID
					Debug(bot, string.format('action=objective_upgrade id=%s source=roam_kill mission=%s lane=%s',
						tostring(existing.id), tostring(existing.missionID or 'unknown'), tostring(lane)))
				end
				conversionOpportunities[team] = nil
				return existing
			end
			-- 先验证新路线和参与者，成功后才抢占普通外塔任务，避免转换失败时丢失旧目标。
			preemptExisting = existing
		else
			return existing
		end
	end

	local towerID = nil
	if target == nil and LANE_OUTER_TOWERS[lane] ~= nil then
		target, tier, towerID = GetLaneOuterTower(lane)
	end
	if target == nil then return preemptExisting end
	tier = tonumber(tier) or 1
	if tier <= 2 and tonumber(state.outerTowersRemaining) == 0 then return preemptExisting end
	if towerID == nil and tier <= 2 then
		for candidateTier, candidateID in ipairs(LANE_OUTER_TOWERS[lane] or {}) do
			if GetEnemyTower(candidateID) == target then
				towerID = candidateID
				tier = candidateTier
				break
			end
		end
	end

	local source = 'normal_push'
	if opportunity ~= nil and (opportunity.lane == nil or opportunity.lane == lane) then
		source = 'roam_kill'
	elseif (tonumber(state.allyAlive) or 0) > (tonumber(state.enemyAlive) or 0) then
		source = 'alive_advantage'
	elseif state.teamAhead == true or Strategy.IsTeamAhead(state) then
		source = 'team_ahead'
	end
	if tier <= 2 and source == 'normal_push' then
		-- 均势普通外塔只走机会攻击，避免为短暂补刀式推塔反复创建共享目标。
		return preemptExisting
	end

	local targetLocation = GetUnitLocation(target)
	if targetLocation == nil then return preemptExisting end
	local targetKey = GetTargetKey(target)
	local retryBlock = GetObjectiveRetryBlock(team, targetKey, now)
	if retryBlock ~= nil then
		if retryBlock.blockedLogged ~= true then
			retryBlock.blockedLogged = true
			Debug(bot, string.format('action=objective_skip lane=%s tier=%s reason=retry_cooldown previous_reason=%s retry_in=%.1f',
				tostring(lane), tostring(tier), tostring(retryBlock.reason),
				math.max(0, (retryBlock.retryAfter or now) - now)))
		end
		return preemptExisting
	end
	local creationBlocks = GetActiveParticipantReselectBlocks(team, targetKey, now)
	local participants, requiredCount, eligibleCount = BuildParticipantSelection(
		tier, targetLocation, nil, now, creationBlocks)
	if participants == nil then
		local retryEntry = RecordObjectiveRetry(team, targetKey, 'insufficient_eligible', now)
		if retryEntry ~= nil then retryEntry.blockedLogged = true end
		Debug(bot, string.format('action=objective_skip lane=%s tier=%s reason=insufficient_eligible eligible=%s required=%s retry_in=%.1f',
			tostring(lane), tostring(tier), tostring(eligibleCount), tostring(requiredCount),
			retryEntry ~= nil and math.max(0, retryEntry.retryAfter - now) or 0))
		return preemptExisting
	end
	local highGroundContext = nil
	local highGroundReason = 'outer_tower'
	if tier >= 3 then
		local contextSeed = type(state.highGroundContext) == 'table' and state.highGroundContext or {}
		contextSeed.averageLevel = contextSeed.averageLevel or state.allyAverageLevel
		contextSeed.initialEligibleCount = eligibleCount
		highGroundContext = Strategy.GetHighGroundPermissionContext(target, contextSeed)
		local highGroundAllowed = nil
		highGroundAllowed, highGroundReason = Strategy.EvaluateHighGroundPermission(tier, highGroundContext)
		DebugLimited(bot, 'high_ground_permission_create:' .. targetKey, Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
			string.format('action=high_ground_permission stage=create target=%s allowed=%s reason=%s average=%s eligible=%s creep_distance=%s enemy_tp=%s',
				tostring(targetKey), tostring(highGroundAllowed), tostring(highGroundReason),
				highGroundContext.averageLevel ~= nil and string.format('%.2f', highGroundContext.averageLevel) or 'na',
				tostring(eligibleCount), tostring(highGroundContext.alliedCreepDistance or 'na'),
				tostring(highGroundContext.enemyTpCount or 0)))
		if not highGroundAllowed then return preemptExisting end
	end

	local assembleWindow, slowestEta = GetAssembleWindow(participants)
	local assembleDeadline = now + assembleWindow
	local absoluteDeadline = now + Strategy.OBJECTIVE_ABSOLUTE_MAX_DURATION
	if preemptExisting ~= nil then ClearObjective(team, 'roam_kill_retarget', bot) end
	objectiveSequence = objectiveSequence + 1
	local objective = {
		id = string.format('%s:%s:%s:%s:%s', tostring(team), tostring(lane), tostring(tier), targetKey,
			tostring(objectiveSequence)),
		phase = Strategy.PHASE_ASSEMBLE,
		lane = lane,
		target = target,
		tower = target,
		targetKey = targetKey,
		targetKind = (GetManagedBuildingInfo(target) or {}).kind or 'building',
		towerID = towerID,
		tier = tier,
		source = source,
		missionID = opportunity ~= nil and opportunity.missionID or nil,
		participants = participants,
		requiredCount = requiredCount,
		initialEligibleCount = eligibleCount,
		highGroundPermissionReason = highGroundReason,
		highGroundException = tier >= 3 and tonumber(highGroundContext.averageLevel) < Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND or false,
		defaultHighGroundUnlocked = tier >= 3 and tonumber(highGroundContext.averageLevel) >= Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND or false,
		baseStatusAtStart = baseThreat ~= nil and baseThreat.status or 'none',
		reassignCount = 0,
		blockedParticipantIDs = {},
		createdAt = now,
		expiresAt = assembleDeadline,
		expireAt = assembleDeadline,
		assembleEta = slowestEta,
		assembleDeadline = assembleDeadline,
		absoluteDeadline = absoluteDeadline,
		overallDeadline = math.min(absoluteDeadline,
			assembleDeadline + Strategy.OBJECTIVE_POST_ASSEMBLE_MAX_DURATION),
		lastProgressAt = now,
		lastProgressReason = 'objective_created',
		lastAssignmentAt = now,
		phaseChangedAt = now,
		releaseReason = nil,
	}
	RebuildParticipantMap(objective)
	objectives[team] = objective
	if continuationLane ~= nil then
		pushContinuations[team] = nil
		Debug(bot, string.format('action=objective_continuation_consume lane=%s target=%s',
			tostring(lane), tostring(targetKey)))
	end
	if source == 'roam_kill' then conversionOpportunities[team] = nil end
	local targetHealth, targetMaxHealth = nil, nil
	if J.Utils ~= nil and J.Utils.GetVisibleHealth ~= nil then
		targetHealth, targetMaxHealth = J.Utils.GetVisibleHealth(target)
	end
	Debug(bot, string.format('action=objective_start id=%s target=%s target_hp=%s/%s lane=%s tier=%s source=%s mission=%s required=%s eligible=%s assemble_eta=%.1f assemble_window=%.1f ally_alive=%s enemy_alive=%s ally_avg_level=%s base=%s participants=%s',
		tostring(objective.id), tostring(targetKey), tostring(targetHealth or 'na'), tostring(targetMaxHealth or 'na'),
		tostring(lane), tostring(tier), tostring(source),
		tostring(objective.missionID or 'none'), tostring(requiredCount), tostring(eligibleCount),
		slowestEta, assembleWindow, tostring(state.allyAlive or 'na'), tostring(state.enemyAlive or 'na'),
		state.allyAverageLevel ~= nil and string.format('%.2f', state.allyAverageLevel) or 'na',
		tostring(objective.baseStatusAtStart),
		FormatParticipantIDs(objective)))
	return objective
end

function Strategy.TryCreateOuterTowerCommitment(bot, lane, state, target, tier)
	return Strategy.TryCreatePushObjective(bot, lane, state, target, tier)
end

function Strategy.ReleasePushObjective(reason, bot)
	local team = GetTeamKey()
	if team == nil or objectives[team] == nil then return false end
	ClearObjective(team, reason or 'released', bot)
	return true
end

function Strategy.ReleaseOuterTowerCommitment(reason, bot)
	return Strategy.ReleasePushObjective(reason, bot)
end

function Strategy.InvalidateObjectiveForBaseDefense(bot, baseThreat)
	local hardEmergency = baseThreat == true
		or (type(baseThreat) == 'table' and baseThreat.hardEmergency == true)
	if not hardEmergency then return false end
	return Strategy.ReleasePushObjective('base_defense_pressure', bot)
end

function Strategy.IsPushObjectiveParticipant(bot, objective)
	objective = objective or Strategy.GetPushObjective()
	if not Strategy.IsPushObjectiveReservedParticipant(bot, objective) then return false end
	return GetParticipantBlockReason(bot, false) == nil
end

function Strategy.IsPushObjectiveReservedParticipant(bot, objective)
	objective = objective or Strategy.GetPushObjective()
	if bot == nil or objective == nil or objective.participantByID == nil then return false end
	-- 这里只回答租约归属，不混入暂时性的撤退/防守/不可行动状态。
	return objective.participantByID[GetPlayerID(bot)] ~= nil
end

function Strategy.GetPushObjectiveRole(bot, objective)
	objective = objective or Strategy.GetPushObjective()
	if bot == nil or objective == nil or objective.participantByID == nil then return nil end
	local participant = objective.participantByID[GetPlayerID(bot)]
	return participant ~= nil and participant.role or nil
end

function Strategy.GetPushObjectiveContext(owner)
	if not Strategy.IsEnabled() then return nil end
	return Strategy.GetPushObjective()
end

function Strategy.GetPushObjectiveDebugSnapshot(bot)
	if not Strategy.IsEnabled() then return nil end
	local team = GetTeamKey()
	local objective = team ~= nil and objectives[team] or nil
	if objective == nil then return nil end
	local participant = bot ~= nil and objective.participantByID ~= nil
		and objective.participantByID[GetPlayerID(bot)] or nil
	return {
		id = objective.id,
		phase = objective.phase,
		lane = objective.lane,
		tier = objective.tier,
		target = objective.target,
		targetKey = objective.targetKey,
		participant = participant ~= nil,
		role = participant ~= nil and participant.role or nil,
	}
end

function Strategy.GetHighGroundAssaultAuthorization(bot, objective)
	if not Strategy.IsEnabled() then return nil end
	objective = objective or Strategy.GetPushObjective(true)
	if bot == nil or objective == nil then return nil end
	if (tonumber(objective.tier) or 1) < 3 then return nil end
	-- 这里只放行已经达到默认 20 级门槛的团队；低等级临时例外不扩大塔圈作战权限。
	if objective.defaultHighGroundUnlocked ~= true then return nil end
	if objective.phase ~= Strategy.PHASE_ESCORT and objective.phase ~= Strategy.PHASE_SIEGE then return nil end
	if not Strategy.IsPushObjectiveReservedParticipant(bot, objective) then return nil end
	local targetLocation = Safe(nil, function() return objective.target:GetLocation() end)
	if targetLocation == nil then return nil end
	return {
		objectiveID = objective.id,
		lane = objective.lane,
		phase = objective.phase,
		targetKey = objective.targetKey,
		role = Strategy.GetPushObjectiveRole(bot, objective),
		targetLocation = {
			x = targetLocation.x or 0, y = targetLocation.y or 0, z = targetLocation.z or 0,
		},
		towerBypassRadius = 1800,
	}
end

function Strategy.NoteHighGroundAssaultDecision(bot, objective, decision, extra)
	if not Strategy.IsEnabled() or objective == nil then return end
	DebugLimited(bot,
		'high_ground_assault:' .. tostring(objective.id) .. ':' .. tostring(GetPlayerID(bot))
			.. ':' .. tostring(decision),
		Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
		string.format('action=high_ground_assault id=%s phase=%s role=%s decision=%s %s',
			tostring(objective.id), tostring(objective.phase),
			tostring(Strategy.GetPushObjectiveRole(bot, objective) or 'none'),
			tostring(decision), tostring(extra or '')))
end

function Strategy.GetManagedBuildingInfo(target)
	return GetManagedBuildingInfo(target)
end

function Strategy.ValidatePushObjectiveHighGround(bot, objective)
	if not Strategy.IsEnabled() then return true, 'legacy_disabled' end
	objective = objective or Strategy.GetPushObjective()
	if objective == nil or (tonumber(objective.tier) or 1) < 3 then return true, 'not_high_ground' end
	if objective.defaultHighGroundUnlocked == true then return true, 'default_level_20' end
	local context = Strategy.GetHighGroundPermissionContext(objective.target, {
		initialEligibleCount = objective.initialEligibleCount or objective.requiredCount,
	})
	local allowed, reason = Strategy.EvaluateHighGroundPermission(objective.tier, context)
	if allowed and tonumber(context.averageLevel) >= Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND then
		objective.defaultHighGroundUnlocked = true
		objective.highGroundException = false
		objective.highGroundPermissionReason = 'default_level_20'
		return true, 'default_level_20'
	end
	DebugLimited(bot, 'high_ground_permission_action:' .. tostring(objective.targetKey),
		Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
		string.format('action=high_ground_permission stage=action target=%s allowed=%s reason=%s average=%s creep_distance=%s enemy_tp=%s',
			tostring(objective.targetKey), tostring(allowed), tostring(reason),
			context.averageLevel ~= nil and string.format('%.2f', context.averageLevel) or 'na',
			tostring(context.alliedCreepDistance or 'na'), tostring(context.enemyTpCount or 0)))
	if allowed then return true, reason end
	ClearObjective(GetTeamKey(), 'high_ground_exception_lost_' .. tostring(reason), bot)
	return false, reason
end

function Strategy.CanAttackPushObjective(bot, lane, target, objective)
	if not Strategy.IsEnabled() then return true, 'legacy_disabled' end
	if target == nil then return false, 'target_missing' end
	local info = GetManagedBuildingInfo(target)
	objective = objective or Strategy.GetPushObjective()
	if objective == nil then
		if info ~= nil and info.tier <= 2 then return true, 'outer_opportunistic' end
		return false, info == nil and 'unmanaged_building' or 'missing_objective'
	end
	local highGroundAllowed, highGroundReason = Strategy.ValidatePushObjectiveHighGround(bot, objective)
	if not highGroundAllowed then return false, 'high_ground_' .. tostring(highGroundReason) end
	if objective.lane ~= lane then return false, 'lane_mismatch' end
	if objective.phase ~= Strategy.PHASE_SIEGE then return false, 'phase_' .. tostring(objective.phase) end
	if GetTargetKey(target) ~= objective.targetKey then return false, 'target_mismatch' end
	if not Strategy.IsPushObjectiveParticipant(bot, objective) then return false, 'owner_not_participant' end
	return true, 'objective_siege'
end

function Strategy.CanControlledUnitAttackBuilding(owner, target)
	if not Strategy.IsEnabled() then return true, 'legacy_disabled' end
	local objective = Strategy.GetPushObjective()
	local lane = objective ~= nil and objective.lane or nil
	local allowed, reason = Strategy.CanAttackPushObjective(owner, lane, target, objective)
	local targetKey = GetTargetKey(target)
	if allowed and reason == 'outer_opportunistic' then
		DebugLimited(owner, 'opportunistic_controlled:' .. tostring(GetPlayerID(owner)) .. ':' .. targetKey,
			Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
			string.format('action=opportunistic_building_attack unit=controlled target=%s allowed=true', targetKey))
	elseif not allowed then
		DebugLimited(owner, 'controlled_building_denied:' .. tostring(GetPlayerID(owner)) .. ':' .. targetKey .. ':' .. tostring(reason),
			Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
			string.format('action=controlled_building_denied target=%s reason=%s', targetKey, tostring(reason)))
	end
	return allowed, reason
end

function Strategy.CanControlledUnitAttackMove(owner, location)
	if not Strategy.IsEnabled() then return true, 'legacy_disabled' end
	local objective = Strategy.GetPushObjective()
	if objective ~= nil then
		local highGroundAllowed, reason = Strategy.ValidatePushObjectiveHighGround(owner, objective)
		if not highGroundAllowed then return false, 'high_ground_' .. tostring(reason) end
		if not Strategy.IsPushObjectiveParticipant(owner, objective) then return false, 'owner_not_participant' end
		-- AttackMove 无法约束自动索敌对象；共享任务始终改用普通移动或显式目标攻击。
		return false, objective.phase ~= Strategy.PHASE_SIEGE
			and 'phase_' .. tostring(objective.phase) or 'objective_requires_exact_target'
	end
	if location ~= nil and UNIT_LIST_ENEMY_BUILDINGS ~= nil then
		for _, building in pairs(Safe({}, function() return GetUnitList(UNIT_LIST_ENEMY_BUILDINGS) end) or {}) do
			local info = GetManagedBuildingInfo(building)
			if info ~= nil and info.tier >= 3
			and GetDistanceToLocation(building, location) <= 1200
			then
				return false, 'unmanaged_high_ground_nearby'
			end
		end
	end
	return true, 'outer_or_open_lane'
end

function Strategy.CanHeroUseAttackMove(bot, lane, laneBuildingTier)
	if not Strategy.IsEnabled() then return true, 'legacy_disabled' end
	local objective = Strategy.GetPushObjective()
	if objective == nil then
		return (tonumber(laneBuildingTier) or 1) <= 2,
			(tonumber(laneBuildingTier) or 1) <= 2 and 'outer_opportunistic' or 'missing_high_ground_objective'
	end
	local highGroundAllowed, reason = Strategy.ValidatePushObjectiveHighGround(bot, objective)
	if not highGroundAllowed then return false, 'high_ground_' .. tostring(reason) end
	if objective.lane ~= lane then return false, 'lane_mismatch' end
	if not Strategy.IsPushObjectiveParticipant(bot, objective) then return false, 'owner_not_participant' end
	-- 共享目标期间只允许显式攻击目标，AttackMove 一律降级为普通移动。
	return false, objective.phase ~= Strategy.PHASE_SIEGE
		and 'phase_' .. tostring(objective.phase) or 'objective_requires_exact_target'
end

function Strategy.NoteOpportunisticBuildingAttack(bot, target, unitKind)
	if not Strategy.IsEnabled() then return false end
	local info = GetManagedBuildingInfo(target)
	if info == nil or info.tier > 2 or Strategy.GetPushObjective() ~= nil then return false end
	local targetKey = GetTargetKey(target)
	DebugLimited(bot, 'opportunistic_attack:' .. tostring(unitKind or 'hero') .. ':'
		.. tostring(GetPlayerID(bot)) .. ':' .. targetKey, Strategy.OBJECTIVE_AUDIT_LOG_INTERVAL,
		string.format('action=opportunistic_building_attack unit=%s target=%s',
			tostring(unitKind or 'hero'), targetKey))
	return true
end

function Strategy.ShouldYieldPushObjective(bot, lane)
	local objective = Strategy.GetPushObjective()
	return objective ~= nil
		and objective.lane == lane
		and not Strategy.IsPushObjectiveParticipant(bot, objective)
end

function Strategy.ObservePushObjective(bot, lane, target, observation)
	-- 本次观察要先消费同帧可见 HP，再判断 5 秒无掉血，避免边界帧误释放。
	local objective = Strategy.GetPushObjective(true)
	if objective == nil or objective.lane ~= lane then return nil end
	if target ~= nil and GetTargetKey(target) ~= objective.targetKey then return objective end
	observation = observation or {}
	local team = GetTeamKey()
	local now = GetNow()
	local baseThreat = observation.baseThreat
	local hardEmergency = observation.hardEmergency == true
		or observation.baseDefenseRequired == true
		or (type(baseThreat) == 'table' and baseThreat.hardEmergency == true)
	if hardEmergency then
		ClearObjective(team, 'base_defense_pressure', bot)
		return nil
	end
	if observation.targetDestroyed == true then
		ClearObjective(team, 'target_destroyed', bot)
		return nil
	end
	local participant = objective.participantByID[GetPlayerID(bot)]
	local botDistance = tonumber(observation.botDistance)
	if participant ~= nil and botDistance ~= nil then
		if participant.bestDistance == nil then participant.bestDistance = botDistance end
		if botDistance <= Strategy.OBJECTIVE_ARRIVAL_DISTANCE and not participant.arrived then
			participant.arrived = true
			participant.lastApproachProgressAt = now
			participant.noProgressDeadline = now + Strategy.OBJECTIVE_PARTICIPANT_PROGRESS_EXTENSION
			RenewObjective(objective, now, 'participant_arrival_' .. tostring(participant.playerID), bot)
		elseif participant.bestDistance - botDistance >= Strategy.OBJECTIVE_APPROACH_PROGRESS_DISTANCE then
			participant.bestDistance = botDistance
			participant.lastApproachProgressAt = now
			participant.noProgressDeadline = now + Strategy.OBJECTIVE_PARTICIPANT_PROGRESS_EXTENSION
			RenewObjective(objective, now, 'participant_approach_' .. tostring(participant.playerID), bot)
		end
	end
	if observation.attackable == true and observation.backdoorProtected ~= true then
		objective.lastAttackableObservationAt = now
	end
	if (tonumber(observation.allyCreepDistance) or math.huge) <= 850 then
		objective.lastCreepSupportAt = now
	end
	local previousBackdoorProtected = objective.lastBackdoorProtected
	objective.lastBackdoorProtected = observation.backdoorProtected == true
	if not RefreshParticipants(objective, bot) then return nil end

	local creepDistance = tonumber(observation.allyCreepDistance)
	if creepDistance ~= nil then
		local creepAdvanced = objective.bestAllyCreepDistance ~= nil
			and objective.bestAllyCreepDistance - creepDistance >= Strategy.OBJECTIVE_CREEP_PROGRESS_DISTANCE
		if objective.bestAllyCreepDistance == nil or creepDistance < objective.bestAllyCreepDistance then
			objective.bestAllyCreepDistance = creepDistance
		end
		local creepArrived = creepDistance <= Strategy.OBJECTIVE_ESCORT_CREEP_DISTANCE
			and objective.allyCreepArrived ~= true
		if creepAdvanced or creepArrived then
			if creepArrived then objective.allyCreepArrived = true end
			RenewObjective(objective, now, creepAdvanced and 'ally_creep_advance' or 'ally_creep_arrival', bot)
			if objective.phase == Strategy.PHASE_ASSEMBLE then
				TransitionPhase(objective, Strategy.PHASE_ESCORT, bot, 'creep_wave_ready')
			end
		end
	end

	local arrivedCount = 0
	for _, assigned in ipairs(objective.participants or {}) do
		if assigned.arrived then arrivedCount = arrivedCount + 1 end
	end
	if objective.phase == Strategy.PHASE_ASSEMBLE and arrivedCount >= objective.requiredCount then
		TransitionPhase(objective, Strategy.PHASE_ESCORT, bot, 'participants_arrived')
		RenewObjective(objective, now, 'assemble_complete', bot)
	end

	local backdoorProtected = observation.backdoorProtected == true
	local attackable = observation.attackable == true and not backdoorProtected
	if previousBackdoorProtected == true and not backdoorProtected then
		RenewObjective(objective, now, 'backdoor_disabled', bot)
	end
	objective.lastBackdoorProtected = backdoorProtected
	local requiredForAttackableAssembly = math.max(2,
		(objective.requiredCount or 2) - Strategy.OBJECTIVE_ATTACKABLE_ASSEMBLY_SHORTFALL)
	if attackable
	and objective.phase == Strategy.PHASE_ASSEMBLE
	and (tonumber(objective.tier) or 1) >= 3
	and objective.defaultHighGroundUnlocked == true
	and arrivedCount >= requiredForAttackableAssembly
	then
		-- 已达默认上高等级、反偷塔关闭且只差一名集结成员时，允许本地三人组直接接管可攻击建筑。
		TransitionPhase(objective, Strategy.PHASE_ESCORT, bot, 'attackable_high_ground_local')
		RenewObjective(objective, now, 'attackable_assembly_complete', bot)
	end

	RefreshVisibleObjectiveHealth(objective, now, bot, observation.targetHealth)

	if attackable then
		if objective.phase == Strategy.PHASE_ESCORT then
			TransitionPhase(objective, Strategy.PHASE_SIEGE, bot, 'building_attackable')
			objective.siegeAttackableSince = now
			RenewObjective(objective, now, 'siege_window_open', bot)
		elseif objective.phase == Strategy.PHASE_SIEGE then
			objective.siegeAttackableSince = objective.siegeAttackableSince or now
		end
		if objective.phase == Strategy.PHASE_SIEGE
		and now - (objective.siegeAttackableSince or now) >= Strategy.OBJECTIVE_SIEGE_NO_DAMAGE_TIMEOUT
		then
			ClearObjective(team, 'siege_no_health_drop', bot)
			return nil
		end
	elseif backdoorProtected then
		objective.siegeAttackableSince = nil
	end
	return objective
end

function Strategy.NotePushObjectiveAttack(bot, lane, target)
	local objective = Strategy.GetPushObjective()
	if objective == nil or not Strategy.CanAttackPushObjective(bot, lane, target, objective) then return false end
	local now = GetNow()
	if objective.firstAttackTime == nil then
		objective.firstAttackTime = now
		Debug(bot, string.format('action=objective_first_attack id=%s lane=%s tier=%s source=%s delay=%.1f',
			tostring(objective.id), tostring(lane), tostring(objective.tier), tostring(objective.source),
			math.max(0, now - (objective.createdAt or now))))
	end
	-- 指令只记录审计信息，不刷新 expiresAt；续租只能来自 ObservePushObjective 的真实进度。
	objective.lastAttackCommandAt = now
	return true
end


function Strategy.NoteOuterTowerAttack(bot, lane, tower)
	return Strategy.NotePushObjectiveAttack(bot, lane, tower)
end

function Strategy.NoteConversionWithdrawal(bot, reason, commitment)
	commitment = commitment or Strategy.GetPushObjective()
	if type(commitment) ~= 'table' or commitment.source ~= 'roam_kill' then return false end
	local playerID = GetPlayerID(bot)
	commitment.conversionWithdrawalByPlayerID = commitment.conversionWithdrawalByPlayerID or {}
	local auditKey = tostring(playerID) .. ':' .. tostring(reason or 'safety')
	if commitment.conversionWithdrawalByPlayerID[auditKey] == true then return true end
	commitment.conversionWithdrawalByPlayerID[auditKey] = true
	Debug(bot, string.format('action=conversion_withdrawal id=%s mission=%s lane=%s reason=%s',
		tostring(commitment.id), tostring(commitment.missionID or 'unknown'),
		tostring(commitment.lane), tostring(reason or 'safety')))
	return true
end

function Strategy.ObserveOuterTowerSnapshot(bot, state)
	if not Strategy.IsEnabled() then return end
	state = state or Strategy.GetState()
	local team = GetTeamKey()
	if team == nil then return end
	towerSnapshotMilestones[team] = towerSnapshotMilestones[team] or {}
	for _, milestone in ipairs({10 * 60, 15 * 60, 20 * 60, 25 * 60, 30 * 60}) do
		if (tonumber(state.time) or 0) >= milestone and not towerSnapshotMilestones[team][milestone] then
			towerSnapshotMilestones[team][milestone] = true
			local values = {}
			for _, lane in ipairs({LANE_TOP, LANE_MID, LANE_BOT}) do
				for tier, towerID in ipairs(LANE_OUTER_TOWERS[lane] or {}) do
					local tower = GetEnemyTower(towerID)
					-- 敌方塔不可见时只记录存活状态，不触发受限 Bot API 的血量读取警告。
					local health = tower ~= nil and J.Utils.GetVisibleHealth(tower) or nil
					table.insert(values, string.format('%s_t%d=%s:%s', tostring(lane), tier,
						tower ~= nil and 'alive' or 'dead', health ~= nil and tostring(health) or 'na'))
				end
			end
			Debug(bot, string.format('action=outer_tower_snapshot milestone=%s remaining=%s ally_avg_level=%s ally_bot_count=%s towers=%s',
				tostring(milestone), tostring(state.outerTowersRemaining),
				state.allyAverageLevel ~= nil and string.format('%.2f', state.allyAverageLevel) or 'na',
				tostring(state.allyBotCount or 'na'), table.concat(values, ',')))
		end
	end
end

function Strategy.ShouldHoldHighGround(laneBuildingTier, averageLevel)
	if not Strategy.IsEnabled() or (tonumber(laneBuildingTier) or 1) < 3 then return false end
	local level = tonumber(averageLevel)
	if level == nil then
		local team = Safe(nil, function() return GetTeam() end)
		level = team ~= nil and GetActualBotAverageLevel(team) or nil
	end
	return level == nil or level < Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND
end

local function ResolveObjectiveFromState(state)
	local objective = Strategy.GetPushObjective()
	if objective ~= nil then return objective end
	objective = type(state) == 'table' and (state.objective or state.outerCommitment) or nil
	if type(objective) == 'table'
	and objective.phase ~= Strategy.PHASE_DISENGAGE
	and objective.releaseReason == nil
	then
		return objective
	end
	return nil
end

function Strategy.AdjustPushDesire(baseDesire, laneBuildingTier, state, lane, safetyCap, bot)
	CandidateDebug.Detail('pre_wasteland_desire', baseDesire)
	local adjustedDesire = baseDesire or BOT_MODE_DESIRE_NONE
	if not Strategy.IsEnabled() then
		return safetyCap ~= nil and math.min(adjustedDesire, safetyCap) or adjustedDesire
	end
	state = state or Strategy.GetState()
	local baseThreat = Strategy.GetBaseThreatSnapshot(state, bot)
	if baseThreat ~= nil and baseThreat.hardEmergency == true then CandidateDebug.Note('adjust_hard_base_emergency'); return BOT_MODE_DESIRE_NONE end
	if baseThreat ~= nil and baseThreat.coveredPressure == true then
		safetyCap = math.min(safetyCap or 1.0, 0.75)
	end
	if (tonumber(laneBuildingTier) or 1) >= 3 then
		local highGroundContext = state.highGroundContext or {
			averageLevel = state.allyAverageLevel,
			initialEligibleCount = state.initialEligibleCount or state.allyBotCount or 0,
		}
		local highGroundAllowed, permissionReason = Strategy.EvaluateHighGroundPermission(laneBuildingTier, highGroundContext)
		if not highGroundAllowed then CandidateDebug.Note('adjust_high_ground_' .. tostring(permissionReason)); return BOT_MODE_DESIRE_NONE end
	end
	local objective = ResolveObjectiveFromState(state)
	local continuationLane = Strategy.GetPushContinuationLane()
	if objective == nil and continuationLane ~= nil then
		if lane ~= nil and lane ~= continuationLane then CandidateDebug.Note('different_continuation_lane'); return BOT_MODE_DESIRE_NONE end
		adjustedDesire = math.max(adjustedDesire, Strategy.OUTER_COMMIT_DESIRE)
	end
	local opportunity = state.conversionOpportunity or Strategy.GetConversionOpportunity()
	if objective == nil
	and opportunity ~= nil
	and (opportunity.lane == nil or opportunity.lane == lane)
	and (tonumber(laneBuildingTier) or 3) <= 2
	and (tonumber(state.time) or 0) >= Strategy.OUTER_PUSH_START_TIME
	then
		-- 击杀转推先抬高安全检查后的目标路线欲望，实际目标只在 PushThink 动作层创建。
		adjustedDesire = math.max(adjustedDesire, Strategy.OUTER_COMMIT_DESIRE)
	end
	if objective ~= nil and (lane == nil or objective.lane == lane) then
		if bot ~= nil and not Strategy.IsPushObjectiveParticipant(bot, objective) then
			adjustedDesire = math.min(adjustedDesire, Strategy.NON_PARTICIPANT_PUSH_DESIRE)
		elseif (tonumber(laneBuildingTier) or 3) <= 2 then
			adjustedDesire = math.max(adjustedDesire, Strategy.OUTER_COMMIT_DESIRE)
		end
	end
	local now = tonumber(state.time) or 0
	if (tonumber(laneBuildingTier) or 3) <= 2
		and now >= Strategy.BALANCE_START_TIME
		and now < Strategy.OUTER_TOWER_DEADLINE
		and (state.teamAhead == true or Strategy.IsTeamAhead(state))
	then
		adjustedDesire = math.max(adjustedDesire, Strategy.ADVANTAGE_OUTER_PUSH_DESIRE)
	end
	if objective ~= nil and bot ~= nil and not Strategy.IsPushObjectiveParticipant(bot, objective) then
		CandidateDebug.Detail('adjustment', 'nonparticipant_cap')
		adjustedDesire = math.min(adjustedDesire, Strategy.NON_PARTICIPANT_PUSH_DESIRE)
	end
	-- Wasteland 只能抬高通过安全检查后的基础欲望，不能越过基地、人数或敌情上限。
	CandidateDebug.Detail('final_safety_cap', safetyCap)
	if safetyCap ~= nil then adjustedDesire = math.min(adjustedDesire, safetyCap) end
	return adjustedDesire
end

function Strategy.AdjustRoamProposalDesire(baseDesire, state, bot)
	if not Strategy.IsEnabled() then return baseDesire end
	state = state or Strategy.GetState()
	local objective = ResolveObjectiveFromState(state)
	if objective ~= nil then
		return bot ~= nil and not Strategy.IsPushObjectiveParticipant(bot, objective)
			and baseDesire or BOT_MODE_DESIRE_NONE
	end
	if tonumber(state.outerTowersRemaining) == 0 then return baseDesire end
	local now = tonumber(state.time) or 0
	if now >= Strategy.BALANCE_START_TIME and now < Strategy.BALANCE_END_TIME then
		return math.min(baseDesire, Strategy.BALANCED_ROAM_PROPOSAL_DESIRE)
	end
	if now >= Strategy.BALANCE_END_TIME and now < Strategy.OUTER_TOWER_DEADLINE
		and (state.teamAhead == true or Strategy.IsTeamAhead(state))
	then
		return math.min(baseDesire, Strategy.ADVANTAGE_ROAM_PROPOSAL_DESIRE)
	end
	return baseDesire
end

function Strategy.ShouldProtectOuterPushParticipant(position, activeMode, state, bot)
	if not Strategy.IsEnabled() then return false end
	state = state or Strategy.GetState()
	local objective = ResolveObjectiveFromState(state)
	if objective ~= nil then
		if bot ~= nil then return Strategy.IsPushObjectiveParticipant(bot, objective) end
		if PUSH_MODES[activeMode] ~= true then return false end
		return position == 'mid' or position == 'off_core' or position == 'safe_core'
	end
	if PUSH_MODES[activeMode] ~= true then return false end
	if position ~= 'mid' and position ~= 'off_core' and position ~= 'safe_core' then return false end
	-- 只有明确确认外塔为 0 才解除核心位的推进承诺；未知状态继续 fail-closed。
	if tonumber(state.outerTowersRemaining) == 0 then return false end
	local now = tonumber(state.time) or 0
	if now >= Strategy.BALANCE_START_TIME and now < Strategy.BALANCE_END_TIME then return true end
	return now >= Strategy.BALANCE_END_TIME and now < Strategy.OUTER_TOWER_DEADLINE
		and (state.teamAhead == true or Strategy.IsTeamAhead(state))
end

function Strategy.GetStrictTeamAverageLevel()
	local team = Safe(nil, function() return GetTeam() end)
	return team ~= nil and GetActualBotAverageLevel(team) or nil
end

function Strategy.ResetForTests()
	objectives = {}
	lastObjectiveReleases = {}
	objectiveRetryState = {}
	objectiveSequence = 0
	conversionOpportunities = {}
	towerSnapshotMilestones = {}
	lastBaseThreatSnapshots = {}
	auditLogTimes = {}
	participantReselectBlocks = {}
	pushContinuations = {}
end

return Strategy
