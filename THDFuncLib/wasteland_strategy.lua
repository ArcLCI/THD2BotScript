local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local laneAssignmentOK, LaneAssignment = pcall(
	require,
	GetScriptDirectory()..'/THDFuncLib/lane_assignment'
)

local Strategy = {}

-- Wasteland 部署保持开启；Nostalgia 部署必须把本开关设为 false，关闭后完全沿用旧逻辑。
Strategy.ENABLED = true
Strategy.BALANCE_START_TIME = 15 * 60
Strategy.BALANCE_END_TIME = 20 * 60
Strategy.OUTER_TOWER_DEADLINE = 30 * 60
Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND = 25
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
Strategy.OBJECTIVE_SIEGE_NO_DAMAGE_TIMEOUT = 5.0
Strategy.OBJECTIVE_ASSIGNMENT_STABLE_TIME = 3.0
Strategy.OBJECTIVE_PARTICIPANT_NO_PROGRESS_TIME = 5.0
Strategy.OBJECTIVE_MIN_HEALTH = 0.60
Strategy.OBJECTIVE_APPROACH_PROGRESS_DISTANCE = 300
Strategy.OBJECTIVE_CREEP_PROGRESS_DISTANCE = 250
Strategy.OBJECTIVE_ARRIVAL_DISTANCE = 1600
Strategy.OBJECTIVE_ESCORT_CREEP_DISTANCE = 2000
Strategy.NON_PARTICIPANT_PUSH_DESIRE = 0.02
Strategy.CONVERSION_OPPORTUNITY_DURATION = 12.0
-- 击杀转推外塔时，低于此血量的 Bot 不再继续站在塔前承伤。
Strategy.CONVERSION_PUSH_MIN_HEALTH = 0.45
Strategy.DEBUG = true

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
local conversionOpportunities = {}
local towerSnapshotMilestones = {}

local OUTER_TOWERS = {}
for _, towerID in ipairs({TOWER_TOP_1, TOWER_TOP_2, TOWER_MID_1, TOWER_MID_2, TOWER_BOT_1, TOWER_BOT_2}) do
	if towerID ~= nil then table.insert(OUTER_TOWERS, towerID) end
end

local LANE_OUTER_TOWERS = {}
if LANE_TOP ~= nil then LANE_OUTER_TOWERS[LANE_TOP] = {TOWER_TOP_1, TOWER_TOP_2} end
if LANE_MID ~= nil then LANE_OUTER_TOWERS[LANE_MID] = {TOWER_MID_1, TOWER_MID_2} end
if LANE_BOT ~= nil then LANE_OUTER_TOWERS[LANE_BOT] = {TOWER_BOT_1, TOWER_BOT_2} end

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

local function Debug(bot, message)
	if Strategy.DEBUG ~= true then return end
	print(string.format('[BOT][Objective] pid=%s %s game_time=%.1f',
		tostring(GetPlayerID(bot)), tostring(message), GetNow()))
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

local function GetTargetKey(target)
	if target == nil then return 'nil' end
	local entityIndex = Safe(nil, function() return target:entindex() end)
	if entityIndex ~= nil then return tostring(entityIndex) end
	return tostring(target)
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
		table.insert(values, tostring(participant.playerID) .. ':' .. tostring(participant.role))
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
	lastObjectiveReleases[team] = objective
	Debug(bot, string.format('action=objective_release id=%s lane=%s tier=%s source=%s reason=%s elapsed=%.1f phase=%s participants=%s',
		tostring(objective.id), tostring(objective.lane), tostring(objective.tier),
		tostring(objective.source), tostring(objective.releaseReason),
		math.max(0, now - (objective.createdAt or now)), tostring(objective.previousPhase),
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

local function GetParticipantBlockReason(unit, initialSelection)
	if not IsAlive(unit) then return 'dead' end
	local mode = Safe(BOT_MODE_NONE, function() return unit:GetActiveMode() end)
	if BOT_MODE_ROSHAN ~= nil and mode == BOT_MODE_ROSHAN then return 'roshan' end
	if DEFEND_MODES[mode] == true
	and Safe(0, function() return unit:GetActiveModeDesire() end) >= 0.8
	then
		return 'base_defense'
	end
	if J.Retreat ~= nil and J.Retreat.ShouldYield ~= nil
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
	if tier == 3 then return 4 end
	return eligibleCount
end

local function BuildCandidate(member, playerID, targetLocation)
	local distance = GetDistanceToLocation(member, targetLocation)
	local speed = math.max(1, Safe(1, function() return member:GetCurrentMovementSpeed() end) or 1)
	return {
		unit = member,
		playerID = playerID,
		position = GetAssignedPosition(member),
		distance = distance,
		eta = distance / speed,
	}
end

local function GetEligibleCandidates(targetLocation)
	local team = GetTeamKey()
	if team == nil then return {} end
	local playerIDs = Safe({}, function() return GetTeamPlayers(team) end) or {}
	local candidates = {}
	for index, playerID in ipairs(playerIDs) do
		if Safe(false, function() return IsPlayerBot(playerID) end) == true then
			local member = Safe(nil, function() return GetTeamMember(index) end)
			if member ~= nil and GetParticipantBlockReason(member, true) == nil then
				table.insert(candidates, BuildCandidate(member, playerID, targetLocation))
			end
		end
	end
	table.sort(candidates, function(first, second)
		if math.abs(first.eta - second.eta) > 0.001 then return first.eta < second.eta end
		return first.playerID < second.playerID
	end)
	return candidates
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

local function BuildParticipantSelection(tier, targetLocation, retained, now, excludedIDs)
	local allCandidates = GetEligibleCandidates(targetLocation)
	local candidates = {}
	for _, candidate in ipairs(allCandidates) do
		if excludedIDs == nil or excludedIDs[candidate.playerID] ~= true then
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
	local requiredCount = GetRequiredParticipantCount(tier, eligibleCount)
	if requiredCount <= 0 or #candidates < requiredCount then
		if #candidates + retainedOutsideCandidates < requiredCount then
			return nil, requiredCount, eligibleCount
		end
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
	end
	AssignParticipantRoles(selected)
	return selected, requiredCount, eligibleCount
end

local function RebuildParticipantMap(objective)
	objective.participantByID = {}
	for _, participant in ipairs(objective.participants or {}) do
		objective.participantByID[participant.playerID] = participant
	end
end

local function ParticipantNeedsReplacement(participant, now)
	local reason = GetParticipantBlockReason(participant.unit, false)
	if reason ~= nil then return true, reason end
	if participant.stalledSince ~= nil
	then
		return true, 'no_progress'
	end
	return false, nil
end

local function RefreshParticipants(objective, bot)
	if objective == nil then return false end
	local now = GetNow()
	local retained = {}
	local replacementReason = nil
	local excludedIDs = {}
	for _, participant in ipairs(objective.participants or {}) do
		local replace, reason = ParticipantNeedsReplacement(participant, now)
		if replace then
			replacementReason = replacementReason or reason
			excludedIDs[participant.playerID] = true
		else
			table.insert(retained, participant)
		end
	end
	if replacementReason == nil then return true end
	if now - (objective.lastAssignmentAt or objective.createdAt or now)
		< Strategy.OBJECTIVE_ASSIGNMENT_STABLE_TIME
	then
		return true
	end

	local participants, requiredCount, eligibleCount = BuildParticipantSelection(
		objective.tier,
		GetUnitLocation(objective.target),
		retained,
		now,
		excludedIDs
	)
	if participants == nil then
		ClearObjective(GetTeamKey(), 'insufficient_eligible_participants_' .. tostring(eligibleCount)
			.. '_of_' .. tostring(requiredCount), bot)
		return false
	end
	objective.participants = participants
	objective.requiredCount = requiredCount
	objective.lastAssignmentAt = now
	RebuildParticipantMap(objective)
	Debug(bot, string.format('action=objective_reassign id=%s reason=%s participants=%s',
		tostring(objective.id), tostring(replacementReason), FormatParticipantIDs(objective)))
	return true
end

local function RenewObjective(objective, now, reason, bot)
	if objective == nil then return end
	objective.lastProgressAt = now
	objective.lastProgressReason = reason
	objective.expiresAt = math.min(objective.overallDeadline or now, now + Strategy.OUTER_COMMIT_DURATION)
	objective.expireAt = objective.expiresAt
	Debug(bot, string.format('action=objective_progress id=%s phase=%s reason=%s expires_in=%.1f',
		tostring(objective.id), tostring(objective.phase), tostring(reason),
		math.max(0, objective.expiresAt - now)))
end

local function TransitionPhase(objective, phase, bot, reason)
	if objective == nil or objective.phase == phase then return false end
	local previous = objective.phase
	objective.previousPhase = previous
	objective.phase = phase
	objective.phaseChangedAt = GetNow()
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

function Strategy.GetState()
	local team = Safe(nil, function() return GetTeam() end)
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	local allyAverageLevel, allyBotCount = nil, 0
	local enemyAverageLevel, enemyBotCount = nil, 0
	if team ~= nil then allyAverageLevel, allyBotCount = GetActualBotAverageLevel(team) end
	if enemyTeam ~= nil then enemyAverageLevel, enemyBotCount = GetActualBotAverageLevel(enemyTeam) end
	local ancientDefenseState = Safe({}, function() return J.GetAncientDefenseState(4500) end) or {}
	local state = {
		time = GetNow(),
		outerTowersRemaining = CountEnemyOuterTowers(),
		allyAverageLevel = allyAverageLevel,
		enemyAverageLevel = enemyAverageLevel,
		allyBotCount = allyBotCount or 0,
		enemyBotCount = enemyBotCount or 0,
		allyAlive = Safe(0, function() return J.GetNumOfAliveHeroes(false) end) or 0,
		enemyAlive = Safe(0, function() return J.GetNumOfAliveHeroes(true) end) or 0,
		allyKills = Safe(0, function() return J.GetNumOfTeamTotalKills(false) end) or 0,
		enemyKills = Safe(0, function() return J.GetNumOfTeamTotalKills(true) end) or 0,
		baseDefenseRequired = (tonumber(ancientDefenseState.enemyPressure) or 0) > 0,
	}
	state.teamAhead = Strategy.IsTeamAhead(state)
	state.conversionOpportunity = Strategy.GetConversionOpportunity()
	state.objective = Strategy.GetPushObjective()
	state.outerCommitment = state.objective
	return state
end

function Strategy.GetPushObjective()
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
	if now < Strategy.OUTER_PUSH_START_TIME or state.baseDefenseRequired == true then return nil end

	local existing = Strategy.GetPushObjective()
	if existing ~= nil then return existing end

	local towerID = nil
	if target == nil and LANE_OUTER_TOWERS[lane] ~= nil then
		target, tier, towerID = GetLaneOuterTower(lane)
	end
	if target == nil then return nil end
	tier = tonumber(tier) or 1
	if tier <= 2 and tonumber(state.outerTowersRemaining) == 0 then return nil end
	if towerID == nil and tier <= 2 then
		for candidateTier, candidateID in ipairs(LANE_OUTER_TOWERS[lane] or {}) do
			if GetEnemyTower(candidateID) == target then
				towerID = candidateID
				tier = candidateTier
				break
			end
		end
	end

	local opportunity = state.conversionOpportunity or Strategy.GetConversionOpportunity()
	local source = 'normal_push'
	if opportunity ~= nil and (opportunity.lane == nil or opportunity.lane == lane) then
		source = 'roam_kill'
	elseif (tonumber(state.allyAlive) or 0) > (tonumber(state.enemyAlive) or 0) then
		source = 'alive_advantage'
	elseif state.teamAhead == true or Strategy.IsTeamAhead(state) then
		source = 'team_ahead'
	end

	local team = GetTeamKey()
	local targetLocation = GetUnitLocation(target)
	if team == nil or targetLocation == nil then return nil end
	local participants, requiredCount, eligibleCount = BuildParticipantSelection(tier, targetLocation, nil, now)
	if participants == nil then
		Debug(bot, string.format('action=objective_skip lane=%s tier=%s reason=insufficient_eligible eligible=%s required=%s',
			tostring(lane), tostring(tier), tostring(eligibleCount), tostring(requiredCount)))
		return nil
	end

	local objective = {
		id = string.format('%s:%s:%s:%s:%.1f', tostring(team), tostring(lane), tostring(tier), GetTargetKey(target), now),
		phase = Strategy.PHASE_ASSEMBLE,
		lane = lane,
		target = target,
		tower = target,
		targetKey = GetTargetKey(target),
		towerID = towerID,
		tier = tier,
		source = source,
		missionID = opportunity ~= nil and opportunity.missionID or nil,
		participants = participants,
		requiredCount = requiredCount,
		createdAt = now,
		expiresAt = now + Strategy.OUTER_COMMIT_DURATION,
		expireAt = now + Strategy.OUTER_COMMIT_DURATION,
		overallDeadline = now + Strategy.OUTER_COMMIT_MAX_DURATION,
		assembleDeadline = now + Strategy.OBJECTIVE_ASSEMBLE_TIMEOUT,
		lastProgressAt = now,
		lastProgressReason = 'objective_created',
		lastAssignmentAt = now,
		phaseChangedAt = now,
		releaseReason = nil,
	}
	RebuildParticipantMap(objective)
	objectives[team] = objective
	Debug(bot, string.format('action=objective_start id=%s lane=%s tier=%s source=%s mission=%s required=%s eligible=%s participants=%s',
		tostring(objective.id), tostring(lane), tostring(tier), tostring(source),
		tostring(objective.missionID or 'none'), tostring(requiredCount), tostring(eligibleCount),
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

function Strategy.InvalidateObjectiveForBaseDefense(bot, baseDefenseRequired)
	if baseDefenseRequired ~= true then return false end
	return Strategy.ReleasePushObjective('base_defense_pressure', bot)
end

function Strategy.IsPushObjectiveParticipant(bot, objective)
	objective = objective or Strategy.GetPushObjective()
	if bot == nil or objective == nil then return false end
	local participant = objective.participantByID ~= nil and objective.participantByID[GetPlayerID(bot)] or nil
	if participant == nil then return false end
	return GetParticipantBlockReason(bot, false) == nil
end

function Strategy.GetPushObjectiveRole(bot, objective)
	objective = objective or Strategy.GetPushObjective()
	if bot == nil or objective == nil or objective.participantByID == nil then return nil end
	local participant = objective.participantByID[GetPlayerID(bot)]
	return participant ~= nil and participant.role or nil
end

function Strategy.ShouldYieldPushObjective(bot, lane)
	local objective = Strategy.GetPushObjective()
	return objective ~= nil
		and objective.lane == lane
		and not Strategy.IsPushObjectiveParticipant(bot, objective)
end

function Strategy.ObservePushObjective(bot, lane, target, observation)
	local objective = Strategy.GetPushObjective()
	if objective == nil or objective.lane ~= lane then return nil end
	if target ~= nil and GetTargetKey(target) ~= objective.targetKey then return objective end
	observation = observation or {}
	local team = GetTeamKey()
	local now = GetNow()
	if observation.baseDefenseRequired == true then
		ClearObjective(team, 'base_defense_pressure', bot)
		return nil
	end
	if observation.targetDestroyed == true then
		ClearObjective(team, 'target_destroyed', bot)
		return nil
	end
	if not RefreshParticipants(objective, bot) then return nil end

	local participant = objective.participantByID[GetPlayerID(bot)]
	local botDistance = tonumber(observation.botDistance)
	if participant ~= nil and botDistance ~= nil then
		if participant.bestDistance == nil then participant.bestDistance = botDistance end
		if botDistance <= Strategy.OBJECTIVE_ARRIVAL_DISTANCE and not participant.arrived then
			participant.arrived = true
			participant.lastApproachProgressAt = now
			participant.stalledSince = nil
			RenewObjective(objective, now, 'participant_arrival_' .. tostring(participant.playerID), bot)
		elseif participant.bestDistance - botDistance >= Strategy.OBJECTIVE_APPROACH_PROGRESS_DISTANCE then
			participant.bestDistance = botDistance
			participant.lastApproachProgressAt = now
			participant.stalledSince = nil
			RenewObjective(objective, now, 'participant_approach_' .. tostring(participant.playerID), bot)
		elseif not participant.arrived
		and now - (participant.lastApproachProgressAt or participant.assignedAt or now)
			>= Strategy.OBJECTIVE_PARTICIPANT_NO_PROGRESS_TIME
		then
			participant.stalledSince = participant.stalledSince
				or (participant.lastApproachProgressAt or participant.assignedAt or now)
		end
	end

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
	if objective.lastBackdoorProtected == true and not backdoorProtected then
		RenewObjective(objective, now, 'backdoor_disabled', bot)
	end
	objective.lastBackdoorProtected = backdoorProtected

	local visibleHealth = tonumber(observation.targetHealth)
	local healthDropped = visibleHealth ~= nil
		and objective.lastVisibleTargetHealth ~= nil
		and visibleHealth < objective.lastVisibleTargetHealth
	if healthDropped then
		objective.lastHealthDropAt = now
		objective.siegeAttackableSince = now
		RenewObjective(objective, now, 'building_health_drop', bot)
	end
	if visibleHealth ~= nil then objective.lastVisibleTargetHealth = visibleHealth end

	if attackable then
		if objective.phase ~= Strategy.PHASE_SIEGE then
			TransitionPhase(objective, Strategy.PHASE_SIEGE, bot, 'building_attackable')
			objective.siegeAttackableSince = now
			RenewObjective(objective, now, 'siege_window_open', bot)
		else
			objective.siegeAttackableSince = objective.siegeAttackableSince or now
		end
		if now - objective.siegeAttackableSince >= Strategy.OBJECTIVE_SIEGE_NO_DAMAGE_TIMEOUT then
			ClearObjective(team, 'siege_no_health_drop', bot)
			return nil
		end
	elseif backdoorProtected then
		objective.siegeAttackableSince = nil
	end
	return objective
end

function Strategy.NoteOuterTowerAttack(bot, lane, tower)
	local objective = Strategy.GetPushObjective()
	if objective == nil or objective.lane ~= lane or tower == nil then return false end
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
					local health = tower ~= nil and Safe(nil, function() return tower:GetHealth() end) or nil
					table.insert(values, string.format('%s_t%d=%s:%s', tostring(lane), tier,
						tower ~= nil and 'alive' or 'dead', health ~= nil and tostring(health) or 'na'))
				end
			end
			Debug(bot, string.format('action=outer_tower_snapshot milestone=%s remaining=%s towers=%s',
				tostring(milestone), tostring(state.outerTowersRemaining), table.concat(values, ',')))
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
	local adjustedDesire = baseDesire or BOT_MODE_DESIRE_NONE
	if not Strategy.IsEnabled() then
		return safetyCap ~= nil and math.min(adjustedDesire, safetyCap) or adjustedDesire
	end
	if Strategy.ShouldHoldHighGround(laneBuildingTier, state ~= nil and state.allyAverageLevel or nil) then
		return BOT_MODE_DESIRE_NONE
	end
	state = state or Strategy.GetState()
	local objective = ResolveObjectiveFromState(state)
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
		adjustedDesire = math.min(adjustedDesire, Strategy.NON_PARTICIPANT_PUSH_DESIRE)
	end
	-- Wasteland 只能抬高通过安全检查后的基础欲望，不能越过基地、人数或敌情上限。
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
	conversionOpportunities = {}
	towerSnapshotMilestones = {}
end

return Strategy
