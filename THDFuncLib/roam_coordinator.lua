local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Defend = require(GetScriptDirectory()..'/THDFuncLib/aba_defend')
local LaneAssignment = require(GetScriptDirectory()..'/THDFuncLib/lane_assignment')
local Config = require(GetScriptDirectory()..'/THDFuncLib/roam_config')
local Initiation = require(GetScriptDirectory()..'/THDFuncLib/roam_initiation')
local Pickoff = require(GetScriptDirectory()..'/THDFuncLib/roam_pickoff')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')

local Coordinator = {}
local states = {}
local teamStates = {}
local targetHealthHistories = {}

local LANES = {LANE_TOP, LANE_MID, LANE_BOT}
local PROPOSAL_DESIRE = BOT_MODE_DESIRE_ABSOLUTE
local APPROACH_DESIRE = math.min(BOT_MODE_DESIRE_ABSOLUTE * 0.95, BOT_MODE_DESIRE_VERYHIGH + 0.05)
local ENGAGE_DESIRE = BOT_MODE_DESIRE_ABSOLUTE * 0.95

local function Safe(defaultValue, callback)
	local ok, value, extra = pcall(callback)
	if ok then return value, extra end
	return defaultValue
end

local function IsEnabled()
	if type(Config) ~= 'table' or type(Config.IsEnabled) ~= 'function' then return false end
	return Safe(false, function() return Config.IsEnabled() end) == true
end

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function GetSharedTeamState()
	local team = Safe(-1, function() return GetTeam() end)
	if teamStates[team] == nil then
		teamStates[team] = {
			lastMissionStart = -9999,
			lastMissionID = nil,
			lastMissionLeaderID = nil,
			lastMissionTargetID = nil,
			objectiveLockUntil = -9999,
		}
	end
	return teamStates[team]
end

local function GetPlayerID(unit)
	if unit == nil then return -1 end
	return Safe(-1, function() return unit:GetPlayerID() end) or -1
end

local function GetUnitName(unit)
	if unit == nil or unit.GetUnitName == nil then return nil end
	return Safe(nil, function() return unit:GetUnitName() end)
end

local function BuildMissionID(leaderID, targetID, signalTime)
	local roundedTime = math.floor((tonumber(signalTime) or 0) + 0.5)
	return string.format('%s-%s-%d', tostring(leaderID), tostring(targetID), roundedTime)
end

local function GetMissionID(mission)
	if mission == nil then return nil end
	if mission.missionID == nil then
		mission.missionID = BuildMissionID(
			mission.leaderID,
			mission.targetPlayerID,
			mission.signalTime or mission.startTime
		)
	end
	return mission.missionID
end

local function GetState(bot)
	local playerID = GetPlayerID(bot)
	if states[playerID] == nil then
		states[playerID] = {
			pending = nil,
			mission = nil,
			lastObservedMissionStart = -9999,
			lastTeamMissionStart = -9999,
			lastTeamMissionID = nil,
			lastTeamMissionLeaderID = nil,
			lastTeamMissionTargetID = nil,
			lastTeamMissionSignalTime = -9999,
			lastAbortReason = nil,
			lastDebugStatus = nil,
			lastDebugStatusTime = -9999,
		}
	end
	return states[playerID]
end

local function ObserveTeamMission(state, missionID, missionStart, leaderID, targetID, signalTime)
	if state == nil or type(missionStart) ~= 'number' then return end
	local shared = GetSharedTeamState()
	if missionStart >= (shared.lastMissionStart or -9999) then
		shared.lastMissionStart = missionStart
		shared.lastMissionID = missionID
		shared.lastMissionLeaderID = leaderID
		shared.lastMissionTargetID = targetID
	end
	state.lastObservedMissionStart = math.max(state.lastObservedMissionStart or -9999, missionStart)
	if missionStart >= (state.lastTeamMissionStart or -9999) then
		state.lastTeamMissionStart = missionStart
		state.lastTeamMissionID = missionID
		state.lastTeamMissionLeaderID = leaderID
		state.lastTeamMissionTargetID = targetID
		state.lastTeamMissionSignalTime = signalTime or missionStart
	end
end

local function HasTeamObjectiveCommitment(bot)
	local outerCommitment = Wasteland.GetOuterTowerCommitment()
	if outerCommitment ~= nil then return true, 'outer_tower_commit' end
	local now = DotaTime()
	local shared = GetSharedTeamState()
	local doingRoshan = J.IsDoingRoshan(bot)
	local pushing = J.Utils.IsTeamPushingSecondTierOrHighGround(bot)
	if doingRoshan or pushing then
		shared.objectiveLockUntil = math.max(shared.objectiveLockUntil or -9999,
			now + Config.TEAM_OBJECTIVE_LOCK_DURATION)
		return true, doingRoshan and 'roshan' or 'pushing_t2_or_high_ground'
	end
	if now < (shared.objectiveLockUntil or -9999) then return true, 'team_objective_lock' end
	return false, nil
end

local function IsValidUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.IsAlive ~= nil and not Safe(false, function() return unit:IsAlive() end) then return false end
	return true
end

local function CanInspectUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.CanBeSeen == nil or Safe(false, function() return unit:CanBeSeen() end) ~= true then return false end
	return unit.IsAlive == nil or Safe(false, function() return unit:IsAlive() end) == true
end

local function IsRealEnemyHero(bot, target)
	if not CanInspectUnit(target) then return false end
	if target.IsHero == nil or not Safe(false, function() return target:IsHero() end) then return false end
	if GetPlayerID(target) < 0 then return false end
	if Safe(-1, function() return target:GetTeam() end) == Safe(-1, function() return bot:GetTeam() end) then return false end
	if target.IsKnownIllusion ~= nil and Safe(false, function() return target:IsKnownIllusion() end) then return false end
	if target.HasModifier ~= nil and Safe(false, function() return target:HasModifier('modifier_illusion') end) then return false end
	return true
end

local function IsTowerEngagingVisibleEnemyHero(bot, tower)
	if not CanInspectUnit(tower) or tower.GetAttackTarget == nil then return false end
	local attackTarget = Safe(nil, function() return tower:GetAttackTarget() end)
	return IsRealEnemyHero(bot, attackTarget)
end

local function GetHealthFraction(unit)
	local maxHealth = Safe(0, function() return unit:GetMaxHealth() end) or 0
	if maxHealth <= 0 then return 0 end
	return Clamp((Safe(0, function() return unit:GetHealth() end) or 0) / maxHealth, 0, 1)
end

local function GetHealthSnapshot(unit)
	if unit == nil then return nil, nil end
	local health = Safe(nil, function() return unit:GetHealth() end)
	local maxHealth = Safe(nil, function() return unit:GetMaxHealth() end)
	if type(health) ~= 'number' or type(maxHealth) ~= 'number' then return nil, nil end
	return health, maxHealth
end

local function GetManaFraction(unit)
	local maxMana = Safe(0, function() return unit:GetMaxMana() end) or 0
	if maxMana <= 0 then return 1 end
	return Clamp((Safe(0, function() return unit:GetMana() end) or 0) / maxMana, 0, 1)
end

local function GetTeamMembers()
	local result = {}
	local playerIDs = Safe(nil, function() return GetTeamPlayers(GetTeam()) end)
	local teamSize = type(playerIDs) == 'table' and #playerIDs or 0
	if teamSize <= 0 then teamSize = 5 end
	for index = 1, teamSize do
		local member = Safe(nil, function() return GetTeamMember(index) end)
		if member ~= nil then table.insert(result, member) end
	end
	return result
end

local function GetEnemyHeroes()
	local units = Safe({}, function() return GetUnitList(UNIT_LIST_ENEMY_HEROES) end) or {}
	local result = {}
	for _, unit in pairs(units) do
		if CanInspectUnit(unit) then table.insert(result, unit) end
	end
	return result
end

local function GetDistanceToLocation(unit, location)
	if unit == nil or location == nil then return math.huge end
	return Safe(math.huge, function() return GetUnitToLocationDistance(unit, location) end) or math.huge
end

local function GetDistance(first, second)
	if first == nil or second == nil then return math.huge end
	return Safe(math.huge, function() return GetUnitToUnitDistance(first, second) end) or math.huge
end

local function GetLocationDistance(first, second)
	if first == nil or second == nil then return math.huge end
	if J.GetLocationToLocationDistance ~= nil then
		local distance = Safe(nil, function() return J.GetLocationToLocationDistance(first, second) end)
		if type(distance) == 'number' then return distance end
	end
	local firstX, firstY = first.x or 0, first.y or 0
	local secondX, secondY = second.x or 0, second.y or 0
	local dx, dy = firstX - secondX, firstY - secondY
	return math.sqrt(dx * dx + dy * dy)
end

local function GetTowerID(lane, tier)
	if lane == LANE_TOP then
		if tier == 1 then return TOWER_TOP_1 elseif tier == 2 then return TOWER_TOP_2 else return TOWER_TOP_3 end
	elseif lane == LANE_MID then
		if tier == 1 then return TOWER_MID_1 elseif tier == 2 then return TOWER_MID_2 else return TOWER_MID_3 end
	elseif lane == LANE_BOT then
		if tier == 1 then return TOWER_BOT_1 elseif tier == 2 then return TOWER_BOT_2 else return TOWER_BOT_3 end
	end
	return nil
end

local function GetLaneTower(team, lane, tier)
	local towerID = GetTowerID(lane, tier)
	if towerID == nil then return nil end
	return Safe(nil, function() return GetTower(team, towerID) end)
end

local function IsBusyMode(unit)
	local mode = Safe(BOT_MODE_NONE, function() return unit:GetActiveMode() end)
	return mode == BOT_MODE_RETREAT
		or mode == BOT_MODE_ROSHAN
end

local function GetAssignedLane(unit)
	return Safe(nil, function() return unit:GetAssignedLane() end)
end

local function GetPosition(unit)
	return Safe(nil, function() return LaneAssignment.GetAssignedPosition(unit) end)
end

local function GetLevel(unit)
	return math.max(0, Safe(0, function() return unit:GetLevel() end) or 0)
end

local function IsEarlyRoamer(unit)
	return GetLevel(unit) < Config.EARLY_ROAM_LEVEL
end

local function IsMidWaveSafe(bot)
	local lane = GetAssignedLane(bot)
	if lane == nil then return false end
	if Safe(false, function() return bot:WasRecentlyDamagedByAnyHero(2.0) end) then return false end
	local nearbyEnemies = Safe({}, function() return bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) end) or {}
	if #nearbyEnemies > 0 then return false end

	local team = Safe(nil, function() return bot:GetTeam() end)
	if team == nil then return false end
	local allyTower = GetLaneTower(team, lane, 1)
	local enemyTower = GetLaneTower(GetOpposingTeam(), lane, 1)
	if not IsValidUnit(allyTower) or not CanInspectUnit(enemyTower) then return false end
	local laneFront = Safe(nil, function() return GetLaneFrontLocation(team, lane, 0) end)
	if laneFront == nil then return false end
	local allyDistance = GetDistanceToLocation(allyTower, laneFront)
	local enemyDistance = GetDistanceToLocation(enemyTower, laneFront)
	return enemyDistance + 100 < allyDistance
end

local function CountEnemiesNearLocation(location, radius)
	local count = 0
	for _, enemy in ipairs(GetEnemyHeroes()) do
		if GetDistanceToLocation(enemy, location) <= radius then count = count + 1 end
	end
	return count
end

local function IsSupportLaneSafe(bot)
	local lane = GetAssignedLane(bot)
	if lane == nil then return false end
	local laneFront = Safe(nil, function() return GetLaneFrontLocation(GetTeam(), lane, 0) end)
	if laneFront == nil then return false end

	local allies = 0
	local remainingAllies = 0
	for _, member in ipairs(GetTeamMembers()) do
		if IsValidUnit(member)
			and GetAssignedLane(member) == lane
		then
			if member ~= bot and J.Retreat.ShouldYield(member, J.Retreat.HIGH) then return false end
			if GetDistanceToLocation(member, laneFront) <= Config.LOCAL_FIGHT_RADIUS then
				allies = allies + 1
				if member ~= bot then remainingAllies = remainingAllies + 1 end
			end
		end
	end
	local enemies = CountEnemiesNearLocation(laneFront, Config.LOCAL_FIGHT_RADIUS)
	-- 五级前按 Bot 离开后的线路人数判断，避免把原本 2v2 的核心留成 1v2。
	if IsEarlyRoamer(bot) then
		if remainingAllies <= 0 then
			return false, 'early_lane_no_remaining_ally', remainingAllies, enemies
		end
		if enemies > remainingAllies then
			return false, 'early_lane_would_be_outnumbered', remainingAllies, enemies
		end
	elseif enemies > allies then
		return false, 'lane_outnumbered', remainingAllies, enemies
	end

	local tower = GetLaneTower(GetTeam(), lane, 1)
	-- Bot API 的伤害历史只支持 Bot 实体；用可见一塔当前锁定的敌方英雄作为守塔压力信号。
	if IsTowerEngagingVisibleEnemyHero(bot, tower) then
		return false, 'tower_under_pressure', remainingAllies, enemies
	end
	return true, 'eligible', remainingAllies, enemies
end

function Coordinator.IsInitiatorPosition(position)
	return type(position) == 'string' and Config.POSITION_RULES[position] ~= nil
end

local function CanInitiate(bot)
	if not IsValidUnit(bot) then return false, 'invalid_unit' end
	if bot.IsBot ~= nil and not Safe(false, function() return bot:IsBot() end) then return false, 'not_bot' end
	if IsBusyMode(bot) then
		return false, 'hard_blocked_mode_' .. tostring(Safe(BOT_MODE_NONE, function() return bot:GetActiveMode() end))
	end
	local position = GetPosition(bot)
	local rule = Config.POSITION_RULES[position]
	if rule == nil then return false, 'position_not_allowed_' .. tostring(position) end
	if GetLevel(bot) < rule.minLevel then return false, 'level_too_low' end
	if GetHealthFraction(bot) < rule.minHealth then return false, 'health_too_low' end
	if GetManaFraction(bot) < rule.minMana then return false, 'mana_too_low' end
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then return false, 'retreat' end
	local objectiveLocked, objectiveReason = HasTeamObjectiveCommitment(bot)
	if objectiveLocked then return false, objectiveReason end

	if DotaTime() < Config.LANING_PHASE_END_TIME then
		if position == 'mid' then
			if not IsMidWaveSafe(bot) then return false, 'mid_lane_not_safe' end
			return true, 'eligible'
		end
		local laneSafe, laneReason, remainingAllies, laneEnemies = IsSupportLaneSafe(bot)
		local context = {
			earlyRoam = IsEarlyRoamer(bot),
			remainingLaneAllies = remainingAllies,
			homeLaneEnemyCount = laneEnemies,
		}
		if not laneSafe then return false, laneReason or 'support_lane_not_safe', context end
		return true, 'eligible', context
	end
	return true, 'eligible'
end

function Coordinator.CanInitiate(bot)
	return CanInitiate(bot)
end

local function HasUrgentDefense(bot)
	for _, lane in ipairs(LANES) do
		local desire = Safe(BOT_MODE_DESIRE_NONE, function() return Defend.GetDefendDesire(bot, lane) end)
		if desire ~= nil and desire >= BOT_MODE_DESIRE_HIGH then return true end
	end
	return false
end

local function GetLanePosition(lane, location)
	local laneInfo, legacyDistance = Safe(nil, function() return GetAmountAlongLane(lane, location) end)
	-- Dota Bot API 返回 { amount, distance } 表；兼容旧 mock 的双返回形式并对异常值保守失败。
	if type(laneInfo) == 'table' then
		local amount = laneInfo.amount
		local distance = laneInfo.distance
		if type(amount) == 'number' and type(distance) == 'number' then return amount, distance end
		return nil, nil
	end
	if type(laneInfo) == 'number' and type(legacyDistance) == 'number' then
		return laneInfo, legacyDistance
	end
	return nil, nil
end

local function GetNearestLane(target)
	local location = Safe(nil, function() return target:GetLocation() end)
	if location == nil then return nil, math.huge end
	local bestLane = nil
	local bestDistance = math.huge
	for _, lane in ipairs(LANES) do
		local _, distance = GetLanePosition(lane, location)
		if distance ~= nil and distance < bestDistance then
			bestLane = lane
			bestDistance = distance
		end
	end
	return bestLane, bestDistance
end

local function GetHostsNearTarget(target, lane, participants)
	local hosts = {}
	local excluded = {}
	for _, participant in ipairs(participants or {}) do excluded[GetPlayerID(participant.unit)] = true end
	local laningPhase = DotaTime() < Config.LANING_PHASE_END_TIME
	for _, member in ipairs(GetTeamMembers()) do
		local memberID = GetPlayerID(member)
		if not excluded[memberID]
			and IsValidUnit(member)
			and (not laningPhase or GetAssignedLane(member) == lane)
			and GetDistance(member, target) <= Config.LOCAL_FIGHT_RADIUS
		then
			table.insert(hosts, member)
		end
	end
	return hosts
end

local function IsInEnemyTowerDanger(bot, target, lane)
	local enemyTeam = Safe(GetOpposingTeam(), function() return target:GetTeam() end)
	-- 一号塔不构成游走硬禁区；二、三塔仍阻止继续深入。
	for tier = 2, 3 do
		local tower = GetLaneTower(enemyTeam, lane, tier)
		if CanInspectUnit(tower) and GetDistance(target, tower) <= Config.TOWER_DANGER_RADIUS then return true end
	end
	return false
end

local function GetNearestVisibleEnemyTowerDistance(target, lane)
	local enemyTeam = Safe(GetOpposingTeam(), function() return target:GetTeam() end)
	local best = 3000
	-- 一号塔也不参与目标位置评分，允许人数占优时主动越塔完成击杀。
	for tier = 2, 3 do
		local tower = GetLaneTower(enemyTeam, lane, tier)
		if CanInspectUnit(tower) then best = math.min(best, GetDistance(target, tower)) end
	end
	return best
end

local function GetOwnSideDepth(bot, target, lane)
	local location = Safe(nil, function() return target:GetLocation() end)
	if location == nil then return 0 end
	local amount = GetLanePosition(lane, location)
	if type(amount) ~= 'number' then return 0 end
	amount = Clamp(amount, 0, 1)
	if Safe(TEAM_RADIANT, function() return bot:GetTeam() end) == TEAM_RADIANT then
		return 1 - amount
	end
	return amount
end

local function GetAllyOffensivePower(unit)
	local power = Safe(0, function() return unit:GetOffensivePower() end) or 0
	if power > 0 then return power end
	return math.max(1, (Safe(1, function() return unit:GetLevel() end) or 1) * 100)
end

local function GetEnemyCombatPower(unit)
	if not CanInspectUnit(unit) then return 0 end
	local attackDamage = math.max(0, Safe(0, function() return unit:GetAttackDamage() end) or 0)
	local attackPeriod = math.max(0.25, Safe(1.7, function() return unit:GetSecondsPerAttack() end) or 1.7)
	local maxHealth = math.max(0, Safe(0, function() return unit:GetMaxHealth() end) or 0)
	local level = math.max(1, Safe(1, function() return unit:GetLevel() end) or 1)
	local rawPower = attackDamage / attackPeriod + maxHealth * 0.035 + level * 5
	-- 敌方英雄不能调用仅限队友的 GetOffensivePower，使用可见的基础战斗参数估算战力。
	return math.max(0, rawPower * (0.25 + 0.75 * GetHealthFraction(unit)))
end

local function AddUniqueUnit(list, seen, unit)
	local playerID = GetPlayerID(unit)
	local key = playerID >= 0 and ('player:' .. tostring(playerID)) or tostring(unit)
	if not seen[key] then
		seen[key] = true
		table.insert(list, unit)
	end
end

local function GetPowerRatio(target, participants, includeParticipants)
	local location = Safe(nil, function() return target:GetLocation() end)
	if location == nil then return 0 end
	local allies = {}
	local seen = {}
	for _, member in ipairs(GetTeamMembers()) do
		if IsValidUnit(member) and GetDistanceToLocation(member, location) <= Config.LOCAL_FIGHT_RADIUS then
			AddUniqueUnit(allies, seen, member)
		end
	end
	if includeParticipants then
		for _, member in ipairs(participants or {}) do AddUniqueUnit(allies, seen, member) end
	end

	local allyPower = 0
	for _, ally in ipairs(allies) do allyPower = allyPower + GetAllyOffensivePower(ally) end
	local enemyPower = 0
	local enemyCount = 0
	for _, enemy in ipairs(GetEnemyHeroes()) do
		if GetDistanceToLocation(enemy, location) <= Config.LOCAL_FIGHT_RADIUS then
			enemyPower = enemyPower + GetEnemyCombatPower(enemy)
			enemyCount = enemyCount + 1
		end
	end
	if enemyPower <= 0 then return 2.0, #allies, enemyCount end
	return allyPower / enemyPower, #allies, enemyCount
end

local function IsViablePursuitAlternative(bot, target)
	if not IsRealEnemyHero(bot, target) then return false end
	if GetDistance(bot, target) > Config.LOCAL_FIGHT_RADIUS then return false end
	local lane = GetNearestLane(target)
	if lane ~= nil and IsInEnemyTowerDanger(bot, target, lane) then return false end
	return true
end

local function GetLocalPursuitBalance(bot, enemies)
	local allies = {}
	local seen = {}
	AddUniqueUnit(allies, seen, bot)
	for _, ally in ipairs(Safe({}, function()
		return bot:GetNearbyHeroes(Config.LOCAL_FIGHT_RADIUS, false, BOT_MODE_NONE)
	end) or {}) do
		if IsValidUnit(ally)
			and Safe(-1, function() return ally:GetTeam() end) == Safe(-2, function() return bot:GetTeam() end)
		then
			AddUniqueUnit(allies, seen, ally)
		end
	end

	local allyPower = 0
	for _, ally in ipairs(allies) do allyPower = allyPower + GetAllyOffensivePower(ally) end
	local enemyPower = 0
	for _, enemy in ipairs(enemies) do enemyPower = enemyPower + GetEnemyCombatPower(enemy) end
	if enemyPower <= 0 then return 2.0, #allies, #enemies end
	return allyPower / enemyPower, #allies, #enemies
end

local function GetPursuitTargetScore(bot, target, originalTarget)
	local healthScore = (1 - GetHealthFraction(target)) * 0.60
	local distanceScore = Clamp(1 - GetDistance(bot, target) / Config.LOCAL_FIGHT_RADIUS, 0, 1) * 0.40
	local commitmentBonus = target == originalTarget and 0.08 or 0
	return healthScore + distanceScore + commitmentBonus
end

local function BuildPursuitResult(action, target, reason, details)
	details = details or {}
	details.action = action
	details.target = target
	details.reason = reason
	return details
end

function Coordinator.ReassessPursuit(bot, mission)
	local originalTarget = mission ~= nil and mission.target or nil
	local fallback = BuildPursuitResult('pursue', originalTarget, 'no_reassessment')
	if mission == nil or mission.phase ~= 'engage' or not CanInspectUnit(originalTarget) then return fallback end

	local playerID = GetPlayerID(bot)
	mission.pursuitCombatTargets = mission.pursuitCombatTargets or {}
	local activeCombatTarget = mission.pursuitCombatTargets[playerID]
	if activeCombatTarget ~= nil and activeCombatTarget ~= originalTarget then
		if IsViablePursuitAlternative(bot, activeCombatTarget) then
			return BuildPursuitResult('switch', activeCombatTarget, 'switched_target_active')
		end
		mission.pursuitCombatTargets[playerID] = nil
	end

	local now = DotaTime()
	local targetLocation = Safe(nil, function() return originalTarget:GetLocation() end)
	local botLocation = Safe(nil, function() return bot:GetLocation() end)
	local targetDistance = GetDistance(bot, originalTarget)
	if targetLocation == nil or botLocation == nil or targetDistance == math.huge then return fallback end

	mission.pursuitSamples = mission.pursuitSamples or {}
	local previous = mission.pursuitSamples[playerID]
	if previous == nil then
		mission.pursuitSamples[playerID] = {
			time = now,
			distance = targetDistance,
			botLocation = botLocation,
		}
		return fallback
	end
	if now - previous.time < Config.PURSUIT_SAMPLE_INTERVAL then return fallback end

	-- 以 Bot 上一次位置为基准确认目标确实向外移动，避免把己方走位误判成敌方逃跑。
	local outwardDistance = GetLocationDistance(targetLocation, previous.botLocation) - previous.distance
	local distanceDelta = targetDistance - previous.distance
	mission.pursuitSamples[playerID] = {
		time = now,
		distance = targetDistance,
		botLocation = botLocation,
	}
	if outwardDistance < Config.PURSUIT_ESCAPE_DISTANCE
		or targetDistance < Config.PURSUIT_MIN_TARGET_DISTANCE
	then
		return fallback
	end

	local nearbyEnemies = {}
	local alternatives = {}
	for _, enemy in ipairs(Safe({}, function()
		return bot:GetNearbyHeroes(Config.LOCAL_FIGHT_RADIUS, true, BOT_MODE_NONE)
	end) or {}) do
		if IsRealEnemyHero(bot, enemy) then
			table.insert(nearbyEnemies, enemy)
			if enemy ~= originalTarget and IsViablePursuitAlternative(bot, enemy) then
				table.insert(alternatives, enemy)
			end
		end
	end
	if #alternatives == 0 then return fallback end

	local powerRatio, allyCount, enemyCount = GetLocalPursuitBalance(bot, nearbyEnemies)
	local botHealth = GetHealthFraction(bot)
	local details = {
		triggered = true,
		targetDistance = targetDistance,
		distanceDelta = distanceDelta,
		outwardDistance = outwardDistance,
		powerRatio = powerRatio,
		allyCount = allyCount,
		enemyCount = enemyCount,
		botHealth = botHealth,
	}
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
		or powerRatio < Config.PURSUIT_RETREAT_POWER_RATIO
		or botHealth < Config.PURSUIT_RETREAT_HEALTH_FRACTION
	then
		return BuildPursuitResult('retreat', nil, 'local_danger', details)
	end

	local bestTarget = nil
	local bestScore = -math.huge
	for _, candidate in ipairs(alternatives) do
		local score = GetPursuitTargetScore(bot, candidate, originalTarget)
		if score > bestScore then
			bestTarget = candidate
			bestScore = score
		end
	end
	local originalScore = GetPursuitTargetScore(bot, originalTarget, originalTarget)
	details.originalScore = originalScore
	details.alternativeScore = bestScore
	details.alternativePlayerID = GetPlayerID(bestTarget)

	if powerRatio < Config.MIN_CONTINUE_POWER_RATIO then
		return BuildPursuitResult('retreat', nil, 'local_power_disadvantage', details)
	end
	if GetHealthFraction(originalTarget) <= Config.PURSUIT_KEEP_TARGET_HEALTH_FRACTION then
		return BuildPursuitResult('pursue', originalTarget, 'original_kill_opportunity', details)
	end
	if bestTarget ~= nil
		and (targetDistance >= Config.PURSUIT_SWITCH_DISTANCE
			or bestScore >= originalScore + Config.PURSUIT_SWITCH_MARGIN)
	then
		mission.pursuitCombatTargets[playerID] = bestTarget
		return BuildPursuitResult('switch', bestTarget, 'nearby_target_better', details)
	end
	return BuildPursuitResult('pursue', originalTarget, 'original_still_feasible', details)
end

local function WasRecentlyDamagedByAlly(target)
	for _, member in ipairs(GetTeamMembers()) do
		-- 敌方实体不能作为 WasRecentlyDamagedByHero 的接收者；当前攻击目标是安全的近期交战信号。
		if IsValidUnit(member) and member.GetAttackTarget ~= nil
			and Safe(nil, function() return member:GetAttackTarget() end) == target
		then
			return true
		end
	end
	return false
end

local function GetReadyTPScroll(bot)
	local item = Safe(nil, function() return J.Utils.GetItemFromFullInventory(bot, 'item_tpscroll') end)
	if item == nil or not Safe(false, function() return J.CanCastAbility(item) end) then return nil end
	return item
end

function Coordinator.GetReadyTPScroll(bot)
	return GetReadyTPScroll(bot)
end

local function BuildTPTravelPlan(member, target, walkDistance, speed)
	if walkDistance < Config.TP_MIN_WALK_DISTANCE or GetReadyTPScroll(member) == nil then return nil end
	if Safe(false, function() return member:WasRecentlyDamagedByAnyHero(2.0) end) then return nil end
	local nearbyEnemies = Safe({}, function() return member:GetNearbyHeroes(Config.TP_SAFE_RADIUS, true, BOT_MODE_NONE) end) or {}
	if #nearbyEnemies > 0 then return nil end

	local targetLocation = Safe(nil, function() return target:GetLocation() end)
	local tpLocation = Safe(nil, function() return J.GetNearbyLocationToTp(targetLocation) end)
	if targetLocation == nil or tpLocation == nil then return nil end
	local landingDistance = GetLocationDistance(tpLocation, targetLocation)
	if landingDistance > Config.TP_MAX_LANDING_DISTANCE then return nil end

	local tpItem = GetReadyTPScroll(member)
	local channelTime = Safe(Config.TP_CHANNEL_TIME_ESTIMATE, function() return tpItem:GetChannelTime() end)
	if type(channelTime) ~= 'number' or channelTime <= 0 then channelTime = Config.TP_CHANNEL_TIME_ESTIMATE end
	local travelTime = channelTime + landingDistance / speed
	local walkTime = walkDistance / speed
	if travelTime + Config.TP_MIN_TIME_SAVING >= walkTime then return nil end
	return {
		useTP = true,
		tpLocation = tpLocation,
		targetLocation = targetLocation,
		travelTime = travelTime,
		channelTime = channelTime,
		walkDistance = walkDistance,
		landingDistance = landingDistance,
	}
end

local function GetTravelCandidate(member, target, targetLane)
	local eligible, reason, eligibilityContext = CanInitiate(member)
	if not eligible then return nil, 'ineligible_' .. tostring(reason) end
	local distance = GetDistance(member, target)
	if DotaTime() < Config.LANING_PHASE_END_TIME then
		if GetAssignedLane(member) == targetLane then return nil, 'same_lane' end
	elseif distance <= Config.LOCAL_FIGHT_RADIUS then
		-- 对线保护结束后按实际位置判断；已经在目标附近的英雄属于本地接应，不占 ROAM 名额。
		return nil, 'already_local'
	end
	local speed = math.max(1, Safe(1, function() return member:GetCurrentMovementSpeed() end) or 1)
	local tpPlan = BuildTPTravelPlan(member, target, distance, speed)
	local travelTime = tpPlan ~= nil and tpPlan.travelTime or distance / speed
	if travelTime > Config.APPROACH_TIMEOUT then return nil, 'travel_too_long' end
	local earlyRoam = IsEarlyRoamer(member)
	if earlyRoam and travelTime > Config.EARLY_ROAM_MAX_TRAVEL_TIME then
		return nil, 'early_travel_too_long'
	end
	local position = GetPosition(member)
	local rule = Config.POSITION_RULES[position]
	local candidate = {
		unit = member,
		playerID = GetPlayerID(member),
		level = GetLevel(member),
		earlyRoam = earlyRoam,
		position = position,
		travelTime = travelTime,
		effectiveTravelTime = travelTime + (rule.travelBias or 0),
		useTP = tpPlan ~= nil,
		walkDistance = distance,
		remainingLaneAllies = eligibilityContext ~= nil and eligibilityContext.remainingLaneAllies or nil,
		homeLaneEnemyCount = eligibilityContext ~= nil and eligibilityContext.homeLaneEnemyCount or nil,
	}
	if tpPlan ~= nil then
		candidate.tpLocation = tpPlan.tpLocation
		candidate.tpTargetLocation = tpPlan.targetLocation
		candidate.landingDistance = tpPlan.landingDistance
		candidate.tpChannelTime = tpPlan.channelTime
	end
	return candidate
end

function Coordinator.RefreshTPTravelPlan(bot, mission)
	if mission == nil or mission.phase ~= 'approach' or type(mission.travelPlans) ~= 'table' then
		return nil, 'invalid_mission'
	end
	local playerID = GetPlayerID(bot)
	local plan = mission.travelPlans[playerID]
	if plan == nil or plan.tpIssued == true then return nil, 'already_issued_or_missing' end
	if not CanInspectUnit(mission.target) then return nil, 'target_not_visible' end

	local distance = GetDistance(bot, mission.target)
	local speed = math.max(1, Safe(1, function() return bot:GetCurrentMovementSpeed() end) or 1)
	local refreshed = BuildTPTravelPlan(bot, mission.target, distance, speed)
	if refreshed == nil then return nil, 'route_unavailable' end
	local remainingApproach = Config.APPROACH_TIMEOUT
		- math.max(0, DotaTime() - (mission.startTime or DotaTime()))
	if refreshed.travelTime > remainingApproach then return nil, 'arrival_after_approach_timeout' end

	local movedDistance = plan.targetLocation ~= nil
		and GetLocationDistance(plan.targetLocation, refreshed.targetLocation)
		or 0
	plan.useTP = true
	plan.tpLocation = refreshed.tpLocation
	plan.targetLocation = refreshed.targetLocation
	plan.travelTime = refreshed.travelTime
	plan.walkDistance = refreshed.walkDistance
	plan.landingDistance = refreshed.landingDistance
	plan.channelTime = refreshed.channelTime
	return plan, nil, movedDistance
end

local function SortTravelCandidates(candidates)
	table.sort(candidates, function(first, second)
		if math.abs(first.effectiveTravelTime - second.effectiveTravelTime) > 0.001 then
			return first.effectiveTravelTime < second.effectiveTravelTime
		end
		return first.playerID < second.playerID
	end)
end

local function BuildParticipants(target, targetLane, fixedLeader)
	local candidates = {}
	local rejected = {}
	for _, member in ipairs(GetTeamMembers()) do
		local candidate, reason = GetTravelCandidate(member, target, targetLane)
		if candidate ~= nil then table.insert(candidates, candidate) end
		if candidate == nil then rejected[reason or 'unknown'] = (rejected[reason or 'unknown'] or 0) + 1 end
	end
	SortTravelCandidates(candidates)

	local selected = {}
	if fixedLeader ~= nil then
		local leaderID = GetPlayerID(fixedLeader)
		for _, candidate in ipairs(candidates) do
			if candidate.playerID == leaderID then
				table.insert(selected, candidate)
				break
			end
		end
		-- 信号发起者也必须持续满足资格和 12 秒接近上限，不能凭信号绕过保护条件。
		if #selected == 0 then return {}, rejected end
	end

	for _, candidate in ipairs(candidates) do
		local duplicate = false
		for _, current in ipairs(selected) do
			if current.playerID == candidate.playerID then duplicate = true break end
		end
		local selectionLimit = Config.MAX_ROAMERS
		if candidate.earlyRoam then selectionLimit = Config.EARLY_ROAM_MAX_ROAMERS end
		for _, current in ipairs(selected) do
			if current.earlyRoam then selectionLimit = Config.EARLY_ROAM_MAX_ROAMERS break end
		end
		if not duplicate and #selected < selectionLimit then table.insert(selected, candidate) end
	end
	return selected, rejected
end

function Coordinator.CalculateTargetScore(metrics)
	local healthBonusFactor = 1
	if type(metrics.expectedLocalTTK) == 'number' then
		healthBonusFactor = Clamp(
			(metrics.expectedLocalTTK - (metrics.travelTime or Config.APPROACH_TIMEOUT))
				/ Config.TARGET_TTK_BONUS_WINDOW,
			0, 1)
	end
	local healthScore = (1 - Clamp(metrics.healthFraction or 1, 0, 1)) * 0.35 * healthBonusFactor
	local powerScore = Clamp(((metrics.powerRatio or 0) - Config.MIN_START_POWER_RATIO) / 0.60, 0, 1) * 0.25
	local towerSafety = Clamp(((metrics.enemyTowerDistance or 0) - Config.TOWER_DANGER_RADIUS) / 1800, 0, 1)
	local laneDepth = Clamp(metrics.ownSideDepth or 0, 0, 1)
	local positionScore = (towerSafety + laneDepth) * 0.5 * 0.20
	local travelScore = Clamp(1 - (metrics.travelTime or Config.APPROACH_TIMEOUT) / Config.APPROACH_TIMEOUT, 0, 1) * 0.15
	local damageScore = metrics.recentlyDamaged and 0.05 or 0
	return healthScore + powerScore + positionScore + travelScore + damageScore
end

local function ObserveTargetHealthDPS(target, targetHealth)
	local targetID = GetPlayerID(target)
	if targetID < 0 or type(targetHealth) ~= 'number' then return 0 end
	local now = Safe(0, function() return DotaTime() end) or 0
	local history = targetHealthHistories[targetID]
	if history == nil then
		history = {samples = {}}
		targetHealthHistories[targetID] = history
	end
	local samples = history.samples
	local last = samples[#samples]
	if last == nil or now - last.time >= 0.20 or last.health ~= targetHealth then
		table.insert(samples, {time = now, health = targetHealth})
	end
	while #samples > 1 and now - samples[1].time > Config.TARGET_HEALTH_HISTORY_WINDOW do
		table.remove(samples, 1)
	end
	local observedDPS = 0
	for _, sample in ipairs(samples) do
		local elapsed = now - sample.time
		local healthDrop = sample.health - targetHealth
		if elapsed > 0 and healthDrop >= Config.TARGET_HEALTH_HISTORY_MIN_DROP then
			observedDPS = math.max(observedDPS, healthDrop / elapsed)
		end
	end
	return observedDPS
end

local function EstimateLocalTargetTTK(target, hosts, targetHealth, observedHealthDPS)
	local localAttackDPS = 0
	for _, host in ipairs(hosts or {}) do
		local attackTarget = host.GetAttackTarget ~= nil
			and Safe(nil, function() return host:GetAttackTarget() end)
			or nil
		if attackTarget == target then
			local damage = math.max(0, Safe(0, function() return host:GetAttackDamage() end) or 0)
			local attackPeriod = math.max(0.25, Safe(1.7, function() return host:GetSecondsPerAttack() end) or 1.7)
			localAttackDPS = localAttackDPS + damage / attackPeriod
		end
	end
	local adjustedDPS = math.max(localAttackDPS * Config.TARGET_LOCAL_DAMAGE_FACTOR,
		tonumber(observedHealthDPS) or 0)
	if adjustedDPS <= 0 then return nil, localAttackDPS, observedHealthDPS or 0 end
	return targetHealth / adjustedDPS, localAttackDPS, observedHealthDPS or 0
end

local function BuildTargetPlan(bot, target, fixedLeader)
	if not IsRealEnemyHero(bot, target) then return nil, 'invalid_enemy' end
	local targetHealth, targetMaxHealth = GetHealthSnapshot(target)
	-- 目标死亡帧可能仍短暂留在可见敌人列表中，禁止把陈旧 health=0 目标启动成任务。
	if targetHealth == nil or targetMaxHealth == nil or targetMaxHealth <= 0 or targetHealth <= 0 then
		return nil, 'target_nonpositive_health', {
			health = targetHealth or -1,
			maxHealth = targetMaxHealth or -1,
		}
	end
	local lane, laneDistance = GetNearestLane(target)
	if lane == nil or laneDistance > Config.LANE_DISTANCE then return nil, 'off_lane', laneDistance end

	local participants, participantRejects = BuildParticipants(target, lane, fixedLeader)
	if #participants == 0 then return nil, 'no_cross_lane_roamer', participantRejects end
	if IsInEnemyTowerDanger(bot, target, lane) then return nil, 'tower_danger' end
	local hosts = GetHostsNearTarget(target, lane, participants)
	if #hosts == 0 then return nil, 'no_local_host' end
	if fixedLeader ~= nil and participants[1].playerID ~= GetPlayerID(fixedLeader) then
		return nil, 'leader_not_elected'
	end
	-- 本地队友已经能在支援者抵达前完成击杀时，不再让低血量分数制造无效赶路任务。
	local observedHealthDPS = ObserveTargetHealthDPS(target, targetHealth)
	local expectedLocalTTK, localAttackDPS = EstimateLocalTargetTTK(
		target, hosts, targetHealth, observedHealthDPS)
	if expectedLocalTTK ~= nil
		and expectedLocalTTK <= participants[1].travelTime + Config.TARGET_ARRIVAL_BUFFER
	then
		return nil, 'target_likely_dead_before_arrival', {
			expectedLocalTTK = expectedLocalTTK,
			travelTime = participants[1].travelTime,
			localAttackDPS = localAttackDPS,
		}
	end
	local powerRatio, allyCount, enemyCount = GetPowerRatio(target, (function()
		local units = {}
		for _, participant in ipairs(participants) do table.insert(units, participant.unit) end
		return units
	end)(), true)
	if powerRatio < Config.MIN_START_POWER_RATIO then return nil, 'power_disadvantage' end

	local targetPlayerID = GetPlayerID(target)
	local recentlyDamaged = WasRecentlyDamagedByAlly(target)
	local healthFraction = GetHealthFraction(target)
	local score = Coordinator.CalculateTargetScore({
		healthFraction = healthFraction,
		powerRatio = powerRatio,
		enemyTowerDistance = GetNearestVisibleEnemyTowerDistance(target, lane),
		ownSideDepth = GetOwnSideDepth(bot, target, lane),
		travelTime = participants[1].travelTime,
		recentlyDamaged = recentlyDamaged,
		expectedLocalTTK = expectedLocalTTK,
	})
	local outnumberAdvantage = allyCount > enemyCount
		and powerRatio >= Config.OUTNUMBER_TARGET_MIN_POWER_RATIO
	local minimumScore = Config.MIN_TARGET_SCORE
	if outnumberAdvantage then
		minimumScore = minimumScore - Config.OUTNUMBER_TARGET_SCORE_RELIEF
	end
	if score < minimumScore then
		return nil, 'target_score_too_low', {
			score = score,
			minimumScore = minimumScore,
			powerRatio = powerRatio,
			allyCount = allyCount,
			enemyCount = enemyCount,
		}
	end
	local participantIDs = {}
	local participantLevels = {}
	local travelPlans = {}
	local earlyRoam = false
	for _, participant in ipairs(participants) do
		table.insert(participantIDs, participant.playerID)
		table.insert(participantLevels, tostring(participant.playerID) .. ':' .. tostring(participant.level))
		if participant.earlyRoam then earlyRoam = true end
		travelPlans[participant.playerID] = {
			useTP = participant.useTP == true,
			tpLocation = participant.tpLocation,
			targetLocation = participant.tpTargetLocation,
			travelTime = participant.travelTime,
			walkDistance = participant.walkDistance,
			landingDistance = participant.landingDistance,
			channelTime = participant.tpChannelTime,
		}
	end
	local initiationDescription = Initiation.DescribeMission({participantIDs = participantIDs}, GetTeamMembers())
	local hasReadyOpener = (initiationDescription.readyCount or 0) > 0
	if healthFraction >= Config.HIGH_HEALTH_TARGET_FRACTION
		and #participantIDs < Config.HIGH_HEALTH_MIN_PARTICIPANTS
		and not hasReadyOpener
	then
		return nil, 'high_health_without_setup', {
			healthFraction = healthFraction,
			participants = #participantIDs,
			readyOpeners = initiationDescription.readyCount or 0,
		}
	end
	if earlyRoam then
		local outnumberOpportunity = outnumberAdvantage
			and healthFraction <= Config.EARLY_ROAM_OUTNUMBER_TARGET_HEALTH
		local killConfirmOpportunity = healthFraction <= Config.EARLY_ROAM_KILL_CONFIRM_HEALTH
			and powerRatio >= Config.EARLY_ROAM_MIN_KILL_POWER_RATIO
		-- 五级前只离线处理短距离、明确的人数优势或低血击杀机会。
		if not outnumberOpportunity and not killConfirmOpportunity then
			return nil, 'early_opportunity_too_weak', {
				healthFraction = healthFraction,
				powerRatio = powerRatio,
				allyCount = allyCount,
				enemyCount = enemyCount,
				travelTime = participants[1].travelTime,
			}
		end
	end
	return {
		kind = 'lane_gank',
		target = target,
		targetPlayerID = targetPlayerID,
		targetLane = lane,
		leader = participants[1].unit,
		leaderID = participants[1].playerID,
		leaderLevel = participants[1].level,
		participantIDs = participantIDs,
		participantLevels = participantLevels,
		earlyRoam = earlyRoam,
		remainingLaneAllies = participants[1].remainingLaneAllies,
		homeLaneEnemyCount = participants[1].homeLaneEnemyCount,
		score = score,
		travelTime = participants[1].travelTime,
		powerRatio = powerRatio,
		healthFraction = healthFraction,
		targetHealth = targetHealth,
		targetMaxHealth = targetMaxHealth,
		targetHeroName = GetUnitName(target),
		allyCount = allyCount,
		enemyCount = enemyCount,
		outnumberAdvantage = outnumberAdvantage,
		expectedLocalTTK = expectedLocalTTK,
		localAttackDPS = localAttackDPS,
		observedHealthDPS = observedHealthDPS,
		rallyLocation = Safe(nil, function() return target:GetLocation() end),
		travelPlans = travelPlans,
		useTP = participants[1].useTP == true,
		tpLandingDistance = participants[1].landingDistance,
	}
end

function Coordinator.BuildBestProposal(bot)
	local best = nil
	local rejected = {}
	local targetCount = 0
	for _, target in ipairs(GetEnemyHeroes()) do
		targetCount = targetCount + 1
		local proposal, reason, detail = BuildTargetPlan(bot, target, nil)
		if proposal == nil then rejected[reason or 'unknown'] = (rejected[reason or 'unknown'] or 0) + 1 end
		if reason == 'no_cross_lane_roamer' and type(detail) == 'table' then
			for candidateReason, count in pairs(detail) do
				local key = 'roamer_' .. tostring(candidateReason)
				rejected[key] = (rejected[key] or 0) + count
			end
		end
		if reason == 'off_lane'
			and type(detail) == 'number'
			and detail < math.huge
			and (rejected.off_lane_nearest_distance == nil or detail < rejected.off_lane_nearest_distance)
		then
			rejected.off_lane_nearest_distance = detail
		end
		if reason == 'target_score_too_low'
			and type(detail) == 'table'
			and type(detail.score) == 'number'
			and (rejected.target_score_best == nil or detail.score > rejected.target_score_best)
		then
			rejected.target_score_best = detail.score
			rejected.target_power_best = detail.powerRatio
			 rejected.target_numbers_best = tostring(detail.allyCount) .. 'v' .. tostring(detail.enemyCount)
		end
		if reason == 'target_nonpositive_health' and type(detail) == 'table' then
			rejected.target_health_last = detail.health
			rejected.target_max_health_last = detail.maxHealth
		end
		if reason == 'target_likely_dead_before_arrival' and type(detail) == 'table' then
			rejected.target_ttk_last = detail.expectedLocalTTK
			rejected.target_travel_last = detail.travelTime
			rejected.target_local_dps_last = detail.localAttackDPS
		end
		if proposal ~= nil and (best == nil
			or proposal.score > best.score + 0.0001
			or (math.abs(proposal.score - best.score) <= 0.0001 and proposal.targetPlayerID < best.targetPlayerID))
		then
			best = proposal
		end
	end
	local pickoff, pickoffRejected = Pickoff.BuildBestProposal(bot, nil)
	for reason, count in pairs(pickoffRejected or {}) do
		rejected[reason] = (rejected[reason] or 0) + count
	end
	-- 严格多打少机会优先；纯烟雾巡逻只在没有普通线上目标时接管，避免猜测覆盖已知战机。
	if pickoff ~= nil and (pickoff.kind == 'pickoff' or best == nil) then best = pickoff end
	if targetCount == 0 then rejected.no_visible_enemy = 1 end
	return best, rejected
end

local function IsMissionSignalValid(bot, source, target, ping, now, maxAge)
	if source == nil or source == bot or ping == nil then return false end
	if source.IsBot == nil or not Safe(false, function() return source:IsBot() end) then return false end
	if Safe(BOT_MODE_NONE, function() return source:GetActiveMode() end) ~= BOT_MODE_ROAM then return false end
	if Safe(nil, function() return source:GetTarget() end) ~= target then return false end
	if not IsRealEnemyHero(bot, target) then return false end
	if ping.normal_ping ~= true or type(ping.time) ~= 'number' or ping.location == nil then return false end
	if now - ping.time < 0 or now - ping.time > (maxAge or Config.ANNOUNCEMENT_WINDOW) then return false end
	return GetDistanceToLocation(target, ping.location) <= Config.ANNOUNCEMENT_TARGET_RADIUS
end

function Coordinator.IsAnnouncementValid(bot, source, target, ping, now)
	return IsMissionSignalValid(bot, source, target, ping, now, Config.ANNOUNCEMENT_WINDOW)
end

local function IsParticipant(playerID, participantIDs)
	for _, value in ipairs(participantIDs or {}) do
		if value == playerID then return true end
	end
	return false
end

local function CopyParticipantIDs(participantIDs)
	local result = {}
	for _, playerID in ipairs(participantIDs or {}) do table.insert(result, playerID) end
	return result
end

local function FormatParticipantLevels(participantLevels)
	if type(participantLevels) ~= 'table' or #participantLevels == 0 then return 'unknown' end
	return table.concat(participantLevels, ',')
end

local function FormatParticipantSet(values)
	local result = {}
	for playerID, included in pairs(values or {}) do
		if included then table.insert(result, playerID) end
	end
	table.sort(result)
	for index, playerID in ipairs(result) do result[index] = tostring(playerID) end
	return #result > 0 and table.concat(result, ',') or 'none'
end

local function ObserveAnnouncements(bot)
	local state = GetState(bot)
	local now = DotaTime()
	local gameNow = Safe(now, function() return GameTime() end) or now
	local best = nil
	for _, source in ipairs(GetTeamMembers()) do
		if source ~= bot then
			local target = Safe(nil, function() return source:GetTarget() end)
			local ping = Safe(nil, function() return source:GetMostRecentPing() end)
			local pickoffPlan = Pickoff.BuildAnnouncement(bot, source, ping, gameNow)
			if pickoffPlan ~= nil then
				local signalAge = math.max(0, gameNow - ping.time)
				local missionStart = now - signalAge
				local missionID = BuildMissionID(GetPlayerID(source), pickoffPlan.targetPlayerID, ping.time)
				ObserveTeamMission(state, missionID, missionStart,
					GetPlayerID(source), pickoffPlan.targetPlayerID, ping.time)
				pickoffPlan.startTime = missionStart
				pickoffPlan.signalTime = ping.time
				pickoffPlan.missionID = missionID
				pickoffPlan.phase = 'assemble'
				pickoffPlan.phaseStartTime = missionStart
				if best == nil or pickoffPlan.signalTime < best.signalTime
					or (pickoffPlan.signalTime == best.signalTime and pickoffPlan.leaderID < best.leaderID)
				then
					best = pickoffPlan
				end
			end
			if Coordinator.IsAnnouncementValid(bot, source, target, ping, gameNow) then
				local signalAge = math.max(0, gameNow - ping.time)
				local missionStart = now - signalAge
				local missionID = BuildMissionID(GetPlayerID(source), GetPlayerID(target), ping.time)
				ObserveTeamMission(state, missionID, missionStart,
					GetPlayerID(source), GetPlayerID(target), ping.time)
				local plan = BuildTargetPlan(bot, target, source)
				if plan ~= nil then
					plan.startTime = missionStart
					plan.signalTime = ping.time
					plan.missionID = missionID
					plan.phase = 'approach'
					plan.lastLocation = ping.location
					if best == nil or plan.signalTime < best.signalTime
						or (plan.signalTime == best.signalTime and plan.leaderID < best.leaderID)
					then
						best = plan
					end
				end
			end
		end
	end
	return best
end

local function ObserveActiveTeamMission(bot)
	local state = GetState(bot)
	local now = DotaTime()
	local gameNow = Safe(now, function() return GameTime() end) or now
	local best = nil
	local maxAge = math.max(Config.TEAM_COOLDOWN, Config.EARLY_ROAM_TEAM_COOLDOWN)
		+ Config.ANNOUNCEMENT_WINDOW
	for _, source in ipairs(GetTeamMembers()) do
		if source ~= bot then
			local target = Safe(nil, function() return source:GetTarget() end)
			local ping = Safe(nil, function() return source:GetMostRecentPing() end)
			local oldSignal = IsMissionSignalValid(bot, source, target, ping, gameNow, maxAge)
			local pickoffSignal = Pickoff.IsSignalCandidate(bot, source, ping, gameNow, maxAge)
			if oldSignal or pickoffSignal then
				local signalAge = math.max(0, gameNow - ping.time)
				local missionStart = now - signalAge
				local leaderID = GetPlayerID(source)
				local targetID = GetPlayerID(target)
				if targetID < 0 then targetID = -1000 - leaderID end
				local missionID = BuildMissionID(leaderID, targetID, ping.time)
				ObserveTeamMission(state, missionID, missionStart, leaderID, targetID, ping.time)
				if best == nil or missionStart > best.startTime
					or (missionStart == best.startTime and leaderID < best.leaderID)
				then
					best = {
						missionID = missionID,
						startTime = missionStart,
						leaderID = leaderID,
						targetID = targetID,
					}
				end
			end
		end
	end
	return best
end

local function FormatGameTime(value)
	if type(value) ~= 'number' then return 'unknown' end
	local sign = value < 0 and '-' or ''
	local tenths = math.floor(math.abs(value) * 10 + 0.5)
	local minutes = math.floor(tenths / 600)
	local seconds = (tenths % 600) / 10
	return string.format('%s%02d:%04.1f', sign, minutes, seconds)
end

local function Debug(bot, message)
	if Config.DEBUG ~= true then return end
	local gameTime = FormatGameTime(Safe(nil, function() return DotaTime() end))
	print('[BOT][Roam] pid=' .. tostring(GetPlayerID(bot)) .. ' ' .. tostring(message)
		.. ' game_time=' .. gameTime)
end

local function FormatMetric(value, decimals)
	if type(value) ~= 'number' then return 'unknown' end
	return string.format('%.' .. tostring(decimals or 1) .. 'f', value)
end

local function EnsureMissionMetrics(mission)
	if mission.metrics ~= nil then return mission.metrics end
	local initialHealth, initialMaxHealth = GetHealthSnapshot(mission.target)
	mission.metrics = {
		initialVisibleHealth = initialHealth or mission.targetHealth,
		initialVisibleMaxHealth = initialMaxHealth or mission.targetMaxHealth,
		lastVisibleHealth = initialHealth or mission.targetHealth,
		minVisibleHealth = initialHealth or mission.targetHealth,
		cumulativeHealthDrop = 0,
		attackTargetTime = 0,
		attackTargetSeen = false,
		lastAttackTarget = false,
		lastObservationTime = nil,
		lastLoggedVisibleHealth = initialHealth or mission.targetHealth,
		lastObservationLogTime = -9999,
		firstObservedHealthDropTime = nil,
		firstAttackTargetTime = nil,
	}
	return mission.metrics
end

local function RecordMissionObservation(bot, mission, now, targetVisible)
	local metrics = EnsureMissionMetrics(mission)
	local previousSampleTime = metrics.lastObservationTime
	if type(previousSampleTime) == 'number' and metrics.lastAttackTarget == true then
		local sampleDelta = now - previousSampleTime
		if sampleDelta >= 0 and sampleDelta <= 2.0 then
			metrics.attackTargetTime = metrics.attackTargetTime + sampleDelta
		end
	end

	local attackTarget = targetVisible and Safe(nil, function() return bot:GetAttackTarget() end) or nil
	local attackingTarget = attackTarget == mission.target
	if attackingTarget then
		if not metrics.attackTargetSeen then
			metrics.attackTargetSeen = true
			metrics.firstAttackTargetTime = now
			Debug(bot, string.format('combat_first_attack_target mission=%s target=%s phase=%s',
				tostring(GetMissionID(mission)), tostring(mission.targetPlayerID), tostring(mission.phase)))
		end
	end

	if targetVisible then
		local health = GetHealthSnapshot(mission.target)
		if type(health) == 'number' then
			local previousHealth = metrics.lastVisibleHealth
			if type(previousHealth) == 'number' and health < previousHealth then
				local healthDrop = previousHealth - health
				metrics.cumulativeHealthDrop = metrics.cumulativeHealthDrop + healthDrop
				if metrics.firstObservedHealthDropTime == nil then
					metrics.firstObservedHealthDropTime = now
					Debug(bot, string.format('combat_first_observed_health_drop mission=%s target=%s phase=%s drop=%.1f attack_target=%s',
						tostring(GetMissionID(mission)), tostring(mission.targetPlayerID), tostring(mission.phase),
						healthDrop, tostring(attackingTarget)))
				end
			end
			if type(metrics.minVisibleHealth) ~= 'number' or health < metrics.minVisibleHealth then
				metrics.minVisibleHealth = health
			end
			local loggedHealth = metrics.lastLoggedVisibleHealth
			local changedEnough = type(loggedHealth) ~= 'number'
				or math.abs(health - loggedHealth) >= Config.COMBAT_HEALTH_LOG_MIN_DELTA
			if changedEnough and now - metrics.lastObservationLogTime >= Config.COMBAT_LOG_INTERVAL then
				metrics.lastLoggedVisibleHealth = health
				metrics.lastObservationLogTime = now
				Debug(bot, string.format('combat_observation mission=%s target=%s phase=%s health=%.1f min_health=%.1f cumulative_drop=%.1f attack_target=%s attack_target_time=%.1f',
					tostring(GetMissionID(mission)), tostring(mission.targetPlayerID), tostring(mission.phase),
					health, metrics.minVisibleHealth or health, metrics.cumulativeHealthDrop,
					tostring(attackingTarget), metrics.attackTargetTime))
			end
			metrics.lastVisibleHealth = health
		end
	end
	metrics.lastObservationTime = now
	metrics.lastAttackTarget = attackingTarget
end

local function FinalizeMissionMetrics(mission, now)
	local metrics = mission ~= nil and mission.metrics or nil
	if metrics == nil or metrics.lastObservationTime == nil or metrics.lastAttackTarget ~= true then return end
	local sampleDelta = now - metrics.lastObservationTime
	if sampleDelta >= 0 and sampleDelta <= 2.0 then
		metrics.attackTargetTime = metrics.attackTargetTime + sampleDelta
	end
end

local function FormatInitiationCandidates(description)
	local values = {}
	for _, candidate in ipairs(description.candidates or {}) do
		table.insert(values, string.format('%s:%s:%s:mapped=%s:ready=%s',
			tostring(candidate.playerID), tostring(candidate.heroName or 'unknown'),
			tostring(candidate.abilityName or 'nil'), tostring(candidate.mapped == true),
			tostring(candidate.ready == true)))
	end
	return #values > 0 and table.concat(values, ';') or 'none'
end

local function FormatRejectCounts(rejected)
	local keys = {}
	for reason in pairs(rejected or {}) do table.insert(keys, reason) end
	table.sort(keys)
	local values = {}
	for _, reason in ipairs(keys) do
		local value = rejected[reason]
		if reason == 'off_lane_nearest_distance' and type(value) == 'number' then
			value = string.format('%.0f', value)
		elseif reason == 'target_score_best' and type(value) == 'number' then
			value = string.format('%.3f', value)
		elseif reason == 'target_power_best' and type(value) == 'number' then
			value = string.format('%.2f', value)
		elseif (reason == 'target_ttk_last' or reason == 'target_travel_last') and type(value) == 'number' then
			value = string.format('%.1f', value)
		elseif reason == 'target_local_dps_last' and type(value) == 'number' then
			value = string.format('%.1f', value)
		end
		table.insert(values, tostring(reason) .. '=' .. tostring(value))
	end
	return #values > 0 and table.concat(values, ',') or 'none'
end

local function DebugStatus(bot, message)
	if Config.DEBUG ~= true then return end
	local state = GetState(bot)
	local now = Safe(-9999, function() return DotaTime() end) or -9999
	local repeated = state.lastDebugStatus == message
	local interval = repeated and 5.0 or 1.0
	if now - state.lastDebugStatusTime < interval then return end
	state.lastDebugStatus = message
	state.lastDebugStatusTime = now
	Debug(bot, 'idle ' .. tostring(message))
end

local function ClearTargetIfMatches(bot, mission)
	if mission == nil then return end
	if Safe(nil, function() return bot:GetTarget() end) == mission.target then
		Safe(nil, function() bot:SetTarget(nil) end)
	end
end

local function FormatAbortContext(context)
	if type(context) ~= 'table' then return '' end
	local keys = {}
	for key, value in pairs(context) do
		if value ~= nil then table.insert(keys, key) end
	end
	table.sort(keys)
	local values = {}
	for _, key in ipairs(keys) do table.insert(values, tostring(key) .. '=' .. tostring(context[key])) end
	return #values > 0 and (' ' .. table.concat(values, ' ')) or ''
end

function Coordinator.Abort(bot, reason, context)
	local state = GetState(bot)
	local mission = state.mission or state.pending
	local details = ''
	if mission ~= nil then
		local now = Safe(mission.startTime or 0, function() return DotaTime() end) or 0
		local elapsed = math.max(0, now - (mission.startTime or now))
		FinalizeMissionMetrics(mission, now)
		local metrics = mission.metrics or {}
		local engageElapsed = mission.engageStartTime ~= nil
			and math.max(0, now - mission.engageStartTime)
			or -1
		details = string.format(' mission=%s leader=%s leader_level=%s hero=%s target=%s target_hero=%s phase=%s early_roam=%s participant_levels=%s elapsed=%.1f engage_elapsed=%.1f planned=%s active=%s joined=%s dropped=%s last_visible_health=%s min_visible_health=%s cumulative_health_drop=%.1f attack_target_seen=%s attack_target_time=%.1f',
			tostring(GetMissionID(mission)), tostring(mission.leaderID),
			tostring(mission.leaderLevel or 'unknown'), tostring(GetUnitName(bot) or 'unknown'),
			tostring(mission.targetPlayerID),
			tostring(mission.targetHeroName or GetUnitName(mission.target) or 'unknown'),
			tostring(mission.phase), tostring(mission.earlyRoam == true),
			FormatParticipantLevels(mission.participantLevels), elapsed, engageElapsed,
			table.concat(mission.plannedParticipantIDs or mission.participantIDs or {}, ','),
			table.concat(mission.participantIDs or {}, ','),
			FormatParticipantSet(mission.joinedParticipantIDs),
			FormatParticipantSet(mission.droppedParticipantIDs),
			FormatMetric(metrics.lastVisibleHealth, 1), FormatMetric(metrics.minVisibleHealth, 1),
			metrics.cumulativeHealthDrop or 0, tostring(metrics.attackTargetSeen == true),
			metrics.attackTargetTime or 0)
	end
	Initiation.Clear(bot, mission)
	ClearTargetIfMatches(bot, mission)
	state.pending = nil
	state.mission = nil
	state.lastAbortReason = reason
	Debug(bot, 'release reason=' .. tostring(reason) .. details .. FormatAbortContext(context))
end

local function DropMissionParticipant(bot, mission, playerID, reason, now)
	if mission.droppedParticipantIDs[playerID] then return end
	mission.droppedParticipantIDs[playerID] = true
	local active = {}
	for _, currentID in ipairs(mission.participantIDs or {}) do
		if currentID ~= playerID then table.insert(active, currentID) end
	end
	mission.participantIDs = active
	local oldOwnerID = mission.initiationOwnerID
	if oldOwnerID == playerID then
		mission.initiationOwnerID = Initiation.SelectOwner(mission, GetTeamMembers())
	end
	Debug(bot, string.format('participant_drop mission=%s participant=%s reason=%s elapsed=%.1f active=%s opener_before=%s opener_after=%s',
		tostring(GetMissionID(mission)), tostring(playerID), tostring(reason),
		math.max(0, now - (mission.startTime or now)),
		table.concat(mission.participantIDs, ','), tostring(oldOwnerID), tostring(mission.initiationOwnerID)))
end

local function UpdateMissionRally(bot, mission, location, now)
	if location == nil then return end
	local previousLocation = mission.rallyLocation
	mission.rallyLocation = location
	mission.rallyUpdatedTime = now
	if previousLocation == nil then return end
	local movedDistance = GetLocationDistance(previousLocation, location)
	if movedDistance < Config.RALLY_UPDATE_LOG_DISTANCE
		or now - (mission.lastRallyLogTime or -9999) < Config.RALLY_UPDATE_LOG_INTERVAL
	then
		return
	end
	mission.lastRallyLogTime = now
	Debug(bot, string.format('rally_update mission=%s target=%s moved=%.0f x=%.0f y=%.0f phase=%s',
		tostring(GetMissionID(mission)), tostring(mission.targetPlayerID), movedDistance,
		location.x or 0, location.y or 0, tostring(mission.phase)))
end

local function TryAdoptVisiblePatrolTarget(bot, mission, now)
	if mission == nil or mission.kind ~= 'smoke_patrol' or mission.target ~= nil then return false end
	if mission.leader == nil or mission.leader == bot then return false end
	local target = Safe(nil, function() return mission.leader:GetTarget() end)
	if not IsRealEnemyHero(bot, target) then return false end
	local location = Safe(nil, function() return target:GetLocation() end)
	if location == nil then return false end
	local searchCenter = mission.rallyLocation or mission.lastLocation
	if searchCenter ~= nil
		and GetLocationDistance(location, searchCenter) > Config.PICKOFF_REVALIDATE_RADIUS
	then
		return false
	end
	-- 只接收本 Bot 也能看见的队长目标，避免在 Bot 之间传播隐藏单位句柄。
	mission.target = target
	mission.targetPlayerID = GetPlayerID(target)
	mission.targetHeroName = GetUnitName(target)
	mission.lastLocation = location
	mission.rallyLocation = location
	mission.lastVisibleTime = now
	return true
end

local function GetRoamTeamfightStatus(bot, mission)
	if mission == nil then return false, nil end
	local location = mission.rallyLocation or mission.lastLocation
	if location == nil and CanInspectUnit(mission.target) then
		location = Safe(nil, function() return mission.target:GetLocation() end)
	end
	local active, counts = Pickoff.GetTeamfightStatus(bot, location, Config.ROAM_TEAMFIGHT_RADIUS)
	counts = counts or {}
	return active, {
		teamfightAllies = counts.allyCount or 0,
		teamfightEnemies = counts.enemyCount or 0,
		teamfightTotal = counts.totalHeroCount or 0,
	}
end

local function NoteAttributedRoamKill(bot, mission)
	if mission == nil or mission.phase ~= 'engage' then return false end
	local metrics = mission.metrics or {}
	if metrics.attackTargetSeen ~= true then return false end
	return Wasteland.NoteRoamKill(mission.targetLane, GetMissionID(mission), bot)
end

local function IsTPReacquireProtected(bot, mission, now)
	if mission == nil or type(mission.travelPlans) ~= 'table' then return false end
	local plan = mission.travelPlans[GetPlayerID(bot)]
	if plan == nil or plan.tpIssued ~= true then return false end
	if plan.useTP == true then return true end
	return plan.tpLanded == true
		and now - (plan.tpEndedTime or now) <= Config.TP_TARGET_REACQUIRE_GRACE
end

local function GetMissionDesire(bot, state)
	local mission = state.mission
	if mission == nil then return BOT_MODE_DESIRE_NONE end
	if not IsEnabled() then Coordinator.Abort(bot, 'disabled') return BOT_MODE_DESIRE_NONE end
	local now = DotaTime()
	local missionTimeout = mission.kind == 'lane_gank' and Config.MISSION_TIMEOUT or Config.PICKOFF_TOTAL_TIMEOUT
	if now - mission.startTime >= missionTimeout then
		Coordinator.Abort(bot, 'mission_timeout')
		return BOT_MODE_DESIRE_NONE
	end
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then
		Coordinator.Abort(bot, 'retreat')
		return BOT_MODE_DESIRE_NONE
	end
	if HasUrgentDefense(bot) then
		Coordinator.Abort(bot, 'urgent_defense')
		return BOT_MODE_DESIRE_NONE
	end
	local objectiveLocked, objectiveReason = HasTeamObjectiveCommitment(bot)
	local canFinishEngagedPickoff = objectiveReason == 'outer_tower_commit'
		and mission.phase == 'engage'
	if objectiveLocked and not canFinishEngagedPickoff then
		Coordinator.Abort(bot, objectiveReason or 'team_objective')
		return BOT_MODE_DESIRE_NONE
	end
	local teamfightActive, teamfightContext = GetRoamTeamfightStatus(bot, mission)
	if teamfightActive then
		-- 局部抓单扩大为六人以上交战后释放 ROAM，让正式团战模式接管。
		Coordinator.Abort(bot, 'teamfight_escalated', teamfightContext)
		return BOT_MODE_DESIRE_NONE
	end

	if mission.leader ~= bot then
		local leaderTargetMatches = mission.target == nil
			or Safe(nil, function() return mission.leader:GetTarget() end) == mission.target
		if not IsValidUnit(mission.leader)
			or Safe(BOT_MODE_NONE, function() return mission.leader:GetActiveMode() end) ~= BOT_MODE_ROAM
			or not leaderTargetMatches
		then
			Coordinator.Abort(bot, 'leader_released')
			return BOT_MODE_DESIRE_NONE
		end
	end

	mission.plannedParticipantIDs = mission.plannedParticipantIDs or CopyParticipantIDs(mission.participantIDs)
	mission.joinedParticipantIDs = mission.joinedParticipantIDs or {}
	mission.droppedParticipantIDs = mission.droppedParticipantIDs or {}
	for _, member in ipairs(GetTeamMembers()) do
		local memberID = GetPlayerID(member)
		if member ~= bot
			and IsParticipant(memberID, mission.plannedParticipantIDs)
			and not mission.droppedParticipantIDs[memberID]
		then
			local matchingTarget = mission.target == nil
				or Safe(nil, function() return member:GetTarget() end) == mission.target
			local matchingRoam = Safe(BOT_MODE_NONE, function() return member:GetActiveMode() end) == BOT_MODE_ROAM
				and matchingTarget
			if matchingRoam and not mission.joinedParticipantIDs[memberID] then
				mission.joinedParticipantIDs[memberID] = true
				Debug(bot, string.format('participant_join mission=%s participant=%s elapsed=%.1f source=observed_roam',
					tostring(GetMissionID(mission)), tostring(memberID),
					math.max(0, now - (mission.startTime or now))))
			end
			if mission.joinedParticipantIDs[memberID] then
				if J.Retreat.ShouldYield(member, J.Retreat.HIGH) then
					DropMissionParticipant(bot, mission, memberID, 'retreat', now)
				elseif not matchingRoam then
					DropMissionParticipant(bot, mission, memberID, 'mode_or_target_changed', now)
				end
			end
		end
	end
	if now - mission.startTime >= Config.PARTICIPANT_JOIN_TIMEOUT then
		for _, participantID in ipairs(mission.plannedParticipantIDs) do
			if participantID ~= GetPlayerID(bot)
				and not mission.joinedParticipantIDs[participantID]
				and not mission.droppedParticipantIDs[participantID]
			then
				if mission.kind == nil or mission.kind == 'lane_gank' then
					DropMissionParticipant(bot, mission, participantID, 'join_timeout', now)
				else
					-- 集合/开雾任务必须等到计划成员真的进入 ROAM，不能删人后仍沿用 requiredCount。
					mission.ackWaitLoggedIDs = mission.ackWaitLoggedIDs or {}
					if not mission.ackWaitLoggedIDs[participantID] then
						mission.ackWaitLoggedIDs[participantID] = true
						Debug(bot, string.format('participant_ack_wait mission=%s participant=%s elapsed=%.1f kind=%s',
							tostring(GetMissionID(mission)), tostring(participantID),
							math.max(0, now - (mission.startTime or now)), tostring(mission.kind)))
					end
				end
			end
		end
	end

	if mission.kind ~= nil and mission.kind ~= 'lane_gank' then
		TryAdoptVisiblePatrolTarget(bot, mission, now)
		local previousPhase = mission.phase
		local desire, reason = Pickoff.UpdateMission(bot, mission)
		if reason ~= nil then
			if reason == 'target_dead' then NoteAttributedRoamKill(bot, mission) end
			Coordinator.Abort(bot, reason)
			return BOT_MODE_DESIRE_NONE
		end
		if mission.target ~= nil
			and Safe(false, function() return mission.target:CanBeSeen() end)
		then
			J.SetTargetIfChanged(bot, mission.target, 0.2)
		end
		if previousPhase ~= mission.phase then
			Debug(bot, string.format('phase=%s mission=%s kind=%s target=%s numbers=%dv%d power=%.2f kill=%.1f',
				tostring(mission.phase), tostring(GetMissionID(mission)), tostring(mission.kind),
				tostring(mission.targetPlayerID), mission.allyCount or 0, mission.enemyCount or 0,
				mission.powerRatio or -1, mission.predictedKillTime or -1))
		end
		return desire or BOT_MODE_DESIRE_NONE
	end

	-- 敌方离开视野后不再直接读取 handle:IsAlive，改用玩家级 API 避免不可见 receiver 警告。
	local targetAlive = Safe(false, function() return IsHeroAlive(mission.targetPlayerID) end)
	if not targetAlive then
		NoteAttributedRoamKill(bot, mission)
		Coordinator.Abort(bot, 'target_dead')
		return BOT_MODE_DESIRE_NONE
	end
	local targetVisible = CanInspectUnit(mission.target)
	if targetVisible then
		mission.lastVisibleTime = now
		local targetLocation = Safe(mission.lastLocation, function() return mission.target:GetLocation() end)
		mission.lastLocation = targetLocation
		-- 可见目标的位置就是当前集合点；步行和尚未发出的 TP 都消费同一份动态坐标。
		UpdateMissionRally(bot, mission, targetLocation, now)
		RecordMissionObservation(bot, mission, now, true)
	elseif not IsTPReacquireProtected(bot, mission, now)
		and now - (mission.lastVisibleTime or mission.startTime) > Config.LOST_TARGET_GRACE
	then
		Coordinator.Abort(bot, 'target_lost')
		return BOT_MODE_DESIRE_NONE
	end

	local participantUnits = {}
	for _, member in ipairs(GetTeamMembers()) do
		if IsParticipant(GetPlayerID(member), mission.participantIDs) then table.insert(participantUnits, member) end
	end
	if targetVisible and IsInEnemyTowerDanger(bot, mission.target, mission.targetLane) then
		Coordinator.Abort(bot, 'tower_danger')
		return BOT_MODE_DESIRE_NONE
	end
	if targetVisible then
		local includeParticipants = mission.phase ~= 'engage'
		if GetPowerRatio(mission.target, participantUnits, includeParticipants) < Config.MIN_CONTINUE_POWER_RATIO then
			Coordinator.Abort(bot, 'power_disadvantage')
			return BOT_MODE_DESIRE_NONE
		end
	end

	if mission.phase == 'approach' then
		local attackTarget = targetVisible and Safe(nil, function() return bot:GetAttackTarget() end) or nil
		-- 不能读取敌方目标的受伤历史，用己方 Bot 当前锁定目标表示已进入交战。
		local attacked = attackTarget == mission.target
		if targetVisible and (GetDistance(bot, mission.target) <= Config.ENGAGE_DISTANCE
			or attacked or attackTarget == mission.target)
		then
			mission.phase = 'engage'
			mission.engageStartTime = now
			local metrics = EnsureMissionMetrics(mission)
			metrics.engageStartHealth = metrics.lastVisibleHealth
			Debug(bot, string.format('phase=engage mission=%s target=%s target_hero=%s health=%s attack_target=%s',
				tostring(GetMissionID(mission)), tostring(mission.targetPlayerID),
				tostring(mission.targetHeroName or GetUnitName(mission.target) or 'unknown'),
				FormatMetric(metrics.lastVisibleHealth, 1), tostring(attacked)))
			Debug(bot, string.format('engage_start mission=%s target=%s health=%s attack_target=%s',
				tostring(GetMissionID(mission)), tostring(mission.targetPlayerID),
				FormatMetric(metrics.lastVisibleHealth, 1), tostring(attacked)))
		elseif now - mission.startTime >= Config.APPROACH_TIMEOUT then
			Coordinator.Abort(bot, 'approach_timeout')
			return BOT_MODE_DESIRE_NONE
		end
	end

	if mission.phase == 'engage' then
		if now - (mission.engageStartTime or now) >= Config.ENGAGE_TIMEOUT then
			Coordinator.Abort(bot, 'engage_timeout')
			return BOT_MODE_DESIRE_NONE
		end
		return ENGAGE_DESIRE
	end
	return APPROACH_DESIRE
end

function Coordinator.GetDesire(bot)
	local state = GetState(bot)
	if state.mission ~= nil then return GetMissionDesire(bot, state) end
	if not IsEnabled() then
		state.pending = nil
		DebugStatus(bot, 'reason=disabled_or_invalid_config')
		return BOT_MODE_DESIRE_NONE
	end

	local announcement = ObserveAnnouncements(bot)
	local urgentDefense = HasUrgentDefense(bot)
	local objectiveLocked, objectiveReason = HasTeamObjectiveCommitment(bot)
	if announcement ~= nil
		and not urgentDefense
		and not objectiveLocked
		and IsParticipant(GetPlayerID(bot), announcement.participantIDs)
	then
		local teamfightActive, teamfightContext = GetRoamTeamfightStatus(bot, announcement)
		if teamfightActive then
			state.pending = nil
			DebugStatus(bot, string.format('reason=signal_teamfight allies=%d enemies=%d total=%d',
				teamfightContext.teamfightAllies, teamfightContext.teamfightEnemies,
				teamfightContext.teamfightTotal))
			return BOT_MODE_DESIRE_NONE
		end
		state.pending = announcement
		DebugStatus(bot, 'reason=signal_accept target=' .. tostring(announcement.targetPlayerID)
			.. ' leader=' .. tostring(announcement.leaderID))
		return PROPOSAL_DESIRE
	end
	if announcement ~= nil and objectiveLocked then
		state.pending = nil
		DebugStatus(bot, 'reason=signal_objective_lock objective=' .. tostring(objectiveReason))
		return BOT_MODE_DESIRE_NONE
	end
	if not IsValidUnit(bot) or not Safe(false, function() return bot:IsAlive() end) then
		DebugStatus(bot, 'reason=invalid_or_dead')
		return BOT_MODE_DESIRE_NONE
	end
	local now = DotaTime()
	-- 每次选举前重新观察全队活跃 ROAM 信号，避免每个 Bot 只按自己的本地时间放行。
	ObserveActiveTeamMission(bot)
	local shared = GetSharedTeamState()
	local teamMissionStart = math.max(state.lastObservedMissionStart or -9999,
		state.lastTeamMissionStart or -9999, shared.lastMissionStart or -9999)
	local earlyCooldown = IsEarlyRoamer(bot)
	local cooldownDuration = earlyCooldown and Config.EARLY_ROAM_TEAM_COOLDOWN or Config.TEAM_COOLDOWN
	local cooldownRemaining = cooldownDuration - (now - teamMissionStart)
	if cooldownRemaining > 0 then
		DebugStatus(bot, string.format('reason=team_cooldown remaining=%.1f threshold=%.1f level=%d early=%s mission=%s leader=%s target=%s',
			cooldownRemaining, cooldownDuration, GetLevel(bot), tostring(earlyCooldown),
			tostring(shared.lastMissionID or state.lastTeamMissionID or 'unknown'),
			tostring(shared.lastMissionLeaderID or state.lastTeamMissionLeaderID or 'unknown'),
			tostring(shared.lastMissionTargetID or state.lastTeamMissionTargetID or 'unknown')))
		return BOT_MODE_DESIRE_NONE
	end
	local eligible, eligibilityReason, eligibilityContext = CanInitiate(bot)
	if not eligible then
		DebugStatus(bot, 'reason=' .. tostring(eligibilityReason)
			.. ' level=' .. tostring(GetLevel(bot))
			.. ' early=' .. tostring(IsEarlyRoamer(bot))
			.. ' lane_remaining=' .. tostring(eligibilityContext ~= nil and eligibilityContext.remainingLaneAllies or 'unknown')
			.. ' lane_enemies=' .. tostring(eligibilityContext ~= nil and eligibilityContext.homeLaneEnemyCount or 'unknown')
			.. ' position=' .. tostring(GetPosition(bot))
			.. ' mode=' .. tostring(Safe(BOT_MODE_NONE, function() return bot:GetActiveMode() end)))
		return BOT_MODE_DESIRE_NONE
	end
	if urgentDefense then
		DebugStatus(bot, 'reason=urgent_defense')
		return BOT_MODE_DESIRE_NONE
	end

	local proposal, rejected = Coordinator.BuildBestProposal(bot)
	if proposal == nil then
		DebugStatus(bot, 'reason=no_proposal rejects=' .. FormatRejectCounts(rejected))
		return BOT_MODE_DESIRE_NONE
	end
	if proposal.leaderID ~= GetPlayerID(bot) then
		DebugStatus(bot, 'reason=other_leader target=' .. tostring(proposal.targetPlayerID)
			.. ' leader=' .. tostring(proposal.leaderID))
		return BOT_MODE_DESIRE_NONE
	end
	local teamfightActive, teamfightContext = GetRoamTeamfightStatus(bot, proposal)
	if teamfightActive then
		state.pending = nil
		DebugStatus(bot, string.format('reason=proposal_teamfight allies=%d enemies=%d total=%d',
			teamfightContext.teamfightAllies, teamfightContext.teamfightEnemies,
			teamfightContext.teamfightTotal))
		return BOT_MODE_DESIRE_NONE
	end
	proposal.startTime = DotaTime()
	proposal.signalTime = proposal.startTime
	proposal.missionID = BuildMissionID(proposal.leaderID, proposal.targetPlayerID, proposal.signalTime)
	proposal.kind = proposal.kind or 'lane_gank'
	proposal.phase = proposal.kind == 'lane_gank' and 'approach' or 'assemble'
	proposal.phaseStartTime = proposal.startTime
	if proposal.target ~= nil then
		proposal.lastLocation = Safe(proposal.lastLocation, function() return proposal.target:GetLocation() end)
	end
	proposal.rallyLocation = proposal.rallyLocation or proposal.lastLocation
	state.pending = proposal
	DebugStatus(bot, string.format('reason=proposal mission=%s kind=%s target=%s target_hero=%s participants=%s participant_levels=%s leader_level=%s early_roam=%s lane_remaining=%s lane_enemies=%s score=%.3f travel=%.1f route=%s health=%.2f local_ttk=%s predicted_kill=%s local_dps=%.1f health_dps=%.1f power=%.2f numbers=%dv%d outnumber=%s unknown=%s smoke=%s dust=%s',
		tostring(proposal.missionID),
		tostring(proposal.kind),
		tostring(proposal.targetPlayerID),
		tostring(proposal.targetHeroName or GetUnitName(proposal.target) or 'unknown'),
		table.concat(proposal.participantIDs, ','),
		FormatParticipantLevels(proposal.participantLevels),
		tostring(proposal.leaderLevel or 'unknown'),
		tostring(proposal.earlyRoam == true),
		tostring(proposal.remainingLaneAllies or 'unknown'),
		tostring(proposal.homeLaneEnemyCount or 'unknown'),
		proposal.score or 0,
		proposal.travelTime or -1,
		tostring(proposal.route or (proposal.useTP and 'tp' or 'walk')),
		proposal.healthFraction or -1,
		FormatMetric(proposal.expectedLocalTTK, 1),
		FormatMetric(proposal.predictedKillTime, 1),
		proposal.localAttackDPS or 0,
		proposal.observedHealthDPS or 0,
		proposal.powerRatio or -1,
		proposal.allyCount or 0,
		proposal.enemyCount or 0,
		tostring(proposal.outnumberAdvantage == true),
		tostring(proposal.unknownEnemyCount or 0),
		tostring(proposal.requiresSmoke == true),
		tostring(proposal.requiresDust == true)
	))
	-- 只压低尚未接受的新提案；已发信号的参与者和活动任务继续保持原高优先级。
	return Wasteland.AdjustRoamProposalDesire(PROPOSAL_DESIRE)
end

function Coordinator.OnStart(bot)
	local state = GetState(bot)
	if not IsEnabled() or state.pending == nil then return false end
	local mission = state.pending
	local objectiveLocked, objectiveReason = HasTeamObjectiveCommitment(bot)
	if objectiveLocked then
		state.pending = nil
		state.lastAbortReason = 'start_invalid_' .. tostring(objectiveReason)
		Debug(bot, 'skip_start reason=' .. tostring(objectiveReason)
			.. ' target=' .. tostring(mission.targetPlayerID))
		return false
	end
	local playerID = GetPlayerID(bot)
	if mission.leaderID == playerID then
		-- 模式仲裁和 OnStart 之间目标可能已经死亡或局势改变；发信号前必须重新验证。
		local originalSignalTime = mission.signalTime
		local refreshed, reason = nil, nil
		if mission.kind == nil or mission.kind == 'lane_gank' then
			refreshed, reason = BuildTargetPlan(bot, mission.target, bot)
		else
			refreshed, reason = Pickoff.RefreshProposal(bot, mission, bot)
		end
		if refreshed == nil then
			state.pending = nil
			state.lastAbortReason = 'start_invalid_' .. tostring(reason)
			Debug(bot, 'skip_start reason=' .. tostring(reason)
				.. ' target=' .. tostring(mission.targetPlayerID))
			return false
		end
		refreshed.startTime = DotaTime()
		refreshed.signalTime = originalSignalTime or refreshed.startTime
		refreshed.missionID = mission.missionID
		refreshed.kind = mission.kind or refreshed.kind or 'lane_gank'
		refreshed.phase = refreshed.kind == 'lane_gank' and 'approach' or 'assemble'
		refreshed.phaseStartTime = refreshed.startTime
		if refreshed.target ~= nil then
			refreshed.lastLocation = Safe(refreshed.lastLocation, function() return refreshed.target:GetLocation() end)
		end
		refreshed.rallyLocation = refreshed.rallyLocation or refreshed.lastLocation
		mission = refreshed
	end
	local teamfightActive, teamfightContext = GetRoamTeamfightStatus(bot, mission)
	if teamfightActive then
		Coordinator.Abort(bot, 'start_invalid_teamfight', teamfightContext)
		return false
	end
	state.mission = mission
	state.pending = nil
	mission.startTime = mission.startTime or DotaTime()
	mission.signalTime = mission.signalTime or mission.startTime
	mission.missionID = mission.missionID or BuildMissionID(mission.leaderID, mission.targetPlayerID, mission.signalTime)
	mission.kind = mission.kind or 'lane_gank'
	mission.phase = mission.phase or (mission.kind == 'lane_gank' and 'approach' or 'assemble')
	mission.phaseStartTime = mission.phaseStartTime or mission.startTime
	mission.targetHeroName = mission.targetHeroName or GetUnitName(mission.target)
	mission.rallyLocation = mission.rallyLocation or mission.lastLocation
	mission.plannedParticipantIDs = mission.plannedParticipantIDs or CopyParticipantIDs(mission.participantIDs)
	mission.joinedParticipantIDs = mission.joinedParticipantIDs or {}
	mission.droppedParticipantIDs = mission.droppedParticipantIDs or {}
	local initiationDescription = Initiation.DescribeMission(mission, GetTeamMembers())
	mission.initiationOwnerID = mission.initiationOwnerID or initiationDescription.selectedID
	mission.initiationRegisteredCount = initiationDescription.registeredCount
	mission.initiationReadyCount = initiationDescription.readyCount
	mission.initiationCandidateCount = initiationDescription.candidateCount
	mission.initiationCandidates = initiationDescription.candidates
	Initiation.Begin(bot, mission)
	mission.joinedParticipantIDs[playerID] = true
	mission.lastVisibleTime = mission.target ~= nil and mission.startTime or mission.lastVisibleTime
	EnsureMissionMetrics(mission)
	ObserveTeamMission(state, mission.missionID, mission.startTime,
		mission.leaderID, mission.targetPlayerID, mission.signalTime)
	if mission.target ~= nil
		and Safe(false, function() return mission.target:CanBeSeen() end)
	then
		J.SetTargetIfChanged(bot, mission.target, 0.1)
	end
	Pickoff.NoteMissionStart(mission)
	Debug(bot, string.format('participant_join mission=%s participant=%s elapsed=%.1f source=local_start',
		tostring(mission.missionID), tostring(playerID),
		math.max(0, DotaTime() - (mission.startTime or DotaTime()))))

	if mission.leaderID == playerID then
		local location = mission.kind == 'lane_gank'
			and (mission.rallyLocation or mission.lastLocation)
			or (mission.stagingLocation or mission.rallyLocation or mission.lastLocation)
		if location ~= nil then bot:ActionImmediate_Ping(location.x, location.y, true) end
		if Config.ANNOUNCE_CHAT then
			local announcement = mission.kind == 'smoke_patrol'
				and '[Roam] 集合开雾侦察野区'
				or ('[Roam] 集火敌方玩家 ' .. tostring(mission.targetPlayerID))
			bot:ActionImmediate_Chat(announcement, false)
		end
		Debug(bot, string.format('start mission=%s kind=%s phase=%s leader=%s leader_level=%s hero=%s target=%s target_hero=%s participants=%s participant_levels=%s early_roam=%s lane_remaining=%s lane_enemies=%s score=%.3f travel=%.1f route=%s health=%.2f target_health=%s local_ttk=%s predicted_kill=%s local_dps=%.1f health_dps=%.1f power=%.2f numbers=%dv%d outnumber=%s unknown=%s smoke=%s dust=%s opener=%s opener_registered=%d opener_ready=%d opener_candidates=%d opener_detail=%s',
			tostring(mission.missionID), tostring(mission.kind), tostring(mission.phase), tostring(mission.leaderID),
			tostring(mission.leaderLevel or 'unknown'), tostring(GetUnitName(bot) or 'unknown'),
			tostring(mission.targetPlayerID),
			tostring(mission.targetHeroName or 'unknown'),
			table.concat(mission.participantIDs, ','),
			FormatParticipantLevels(mission.participantLevels),
			tostring(mission.earlyRoam == true),
			tostring(mission.remainingLaneAllies or 'unknown'),
			tostring(mission.homeLaneEnemyCount or 'unknown'),
			mission.score or 0,
			mission.travelTime or -1,
			tostring(mission.route or (mission.useTP and 'tp' or 'walk')),
			mission.healthFraction or -1,
			FormatMetric(mission.targetHealth, 1),
			FormatMetric(mission.expectedLocalTTK, 1),
			FormatMetric(mission.predictedKillTime, 1),
			mission.localAttackDPS or 0,
			mission.observedHealthDPS or 0,
			mission.powerRatio or -1,
			mission.allyCount or 0,
			mission.enemyCount or 0,
			tostring(mission.outnumberAdvantage == true),
			tostring(mission.unknownEnemyCount or 0),
			tostring(mission.requiresSmoke == true),
			tostring(mission.requiresDust == true),
			tostring(mission.initiationOwnerID),
			mission.initiationRegisteredCount or 0,
			mission.initiationReadyCount or 0,
			mission.initiationCandidateCount or 0,
			FormatInitiationCandidates(initiationDescription)
		))
		Debug(bot, string.format('initiation_map mission=%s owner=%s registered=%d ready=%d candidates=%d reason=%s',
			tostring(mission.missionID), tostring(mission.initiationOwnerID),
			mission.initiationRegisteredCount or 0, mission.initiationReadyCount or 0,
			mission.initiationCandidateCount or 0,
			mission.initiationReadyCount > 0 and 'ready' or
			(mission.initiationRegisteredCount > 0 and 'ability_unavailable' or 'no_mapped_hero')))
	end
	return true
end

function Coordinator.DebugAction(bot, message)
	Debug(bot, message)
end

function Coordinator.GetRallyLocation(mission)
	if mission == nil then return nil end
	return mission.rallyLocation or mission.lastLocation
end

function Coordinator.GetMission(bot)
	return GetState(bot).mission
end

function Coordinator.OnEnd(bot, reason)
	local state = GetState(bot)
	if state.mission == nil and state.pending == nil then return end
	Coordinator.Abort(bot, reason or 'mode_end')
end

function Coordinator.ResetForTests()
	states = {}
	teamStates = {}
	targetHealthHistories = {}
	Initiation.ResetForTests()
	Pickoff.ResetForTests()
end

return Coordinator
