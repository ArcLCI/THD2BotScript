local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Defend = require(GetScriptDirectory()..'/THDFuncLib/aba_defend')
local LaneAssignment = require(GetScriptDirectory()..'/THDFuncLib/lane_assignment')
local Config = require(GetScriptDirectory()..'/THDFuncLib/roam_config')

local Coordinator = {}
local states = {}

local LANES = {LANE_TOP, LANE_MID, LANE_BOT}

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

local function GetPlayerID(unit)
	if unit == nil then return -1 end
	return Safe(-1, function() return unit:GetPlayerID() end) or -1
end

local function GetState(bot)
	local playerID = GetPlayerID(bot)
	if states[playerID] == nil then
		states[playerID] = {
			pending = nil,
			mission = nil,
			lastObservedMissionStart = -9999,
			lastAbortReason = nil,
		}
	end
	return states[playerID]
end

local function IsValidUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.IsAlive ~= nil and not Safe(false, function() return unit:IsAlive() end) then return false end
	return true
end

local function CanInspectUnit(unit)
	return IsValidUnit(unit)
		and unit.CanBeSeen ~= nil
		and Safe(false, function() return unit:CanBeSeen() end) == true
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

local function GetManaFraction(unit)
	local maxMana = Safe(0, function() return unit:GetMaxMana() end) or 0
	if maxMana <= 0 then return 1 end
	return Clamp((Safe(0, function() return unit:GetMana() end) or 0) / maxMana, 0, 1)
end

local function GetTeamMembers()
	local result = {}
	for index = 1, 5 do
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
		or mode == BOT_MODE_DEFEND_TOWER_TOP
		or mode == BOT_MODE_DEFEND_TOWER_MID
		or mode == BOT_MODE_DEFEND_TOWER_BOT
		or mode == BOT_MODE_PUSH_TOWER_TOP
		or mode == BOT_MODE_PUSH_TOWER_MID
		or mode == BOT_MODE_PUSH_TOWER_BOT
		or mode == BOT_MODE_ROSHAN
end

local function GetAssignedLane(unit)
	return Safe(nil, function() return unit:GetAssignedLane() end)
end

local function GetPosition(unit)
	return Safe(nil, function() return LaneAssignment.GetAssignedPosition(unit) end)
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
	for _, member in ipairs(GetTeamMembers()) do
		if IsValidUnit(member)
			and GetAssignedLane(member) == lane
		then
			if member ~= bot and J.Retreat.ShouldYield(member, J.Retreat.HIGH) then return false end
			if GetDistanceToLocation(member, laneFront) <= Config.LOCAL_FIGHT_RADIUS then
				allies = allies + 1
			end
		end
	end
	if CountEnemiesNearLocation(laneFront, Config.LOCAL_FIGHT_RADIUS) > allies then return false end

	local tower = GetLaneTower(GetTeam(), lane, 1)
	-- Bot API 的伤害历史只支持 Bot 实体；用可见一塔当前锁定的敌方英雄作为守塔压力信号。
	if IsTowerEngagingVisibleEnemyHero(bot, tower) then
		return false
	end
	return true
end

function Coordinator.IsInitiatorPosition(position)
	return type(position) == 'string' and Config.POSITION_RULES[position] ~= nil
end

local function CanInitiate(bot)
	if not IsValidUnit(bot) then return false end
	if bot.IsBot ~= nil and not Safe(false, function() return bot:IsBot() end) then return false end
	if IsBusyMode(bot) then return false end
	local position = GetPosition(bot)
	local rule = Config.POSITION_RULES[position]
	if rule == nil then return false end
	if (Safe(0, function() return bot:GetLevel() end) or 0) < rule.minLevel then return false end
	if GetHealthFraction(bot) < rule.minHealth or GetManaFraction(bot) < rule.minMana then return false end
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then return false end
	if J.IsDoingRoshan(bot) or J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then return false end

	if DotaTime() < Config.LANING_PHASE_END_TIME then
		if position == 'mid' then return IsMidWaveSafe(bot) end
		return IsSupportLaneSafe(bot)
	end
	return true
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

local function GetNearestLane(target)
	local location = Safe(nil, function() return target:GetLocation() end)
	if location == nil then return nil, math.huge end
	local bestLane = nil
	local bestDistance = math.huge
	for _, lane in ipairs(LANES) do
		local _, distance = Safe(nil, function() return GetAmountAlongLane(lane, location) end)
		if distance ~= nil and distance < bestDistance then
			bestLane = lane
			bestDistance = distance
		end
	end
	return bestLane, bestDistance
end

local function GetHostsNearTarget(target, lane)
	local hosts = {}
	for _, member in ipairs(GetTeamMembers()) do
		if IsValidUnit(member)
			and GetAssignedLane(member) == lane
			and GetDistance(member, target) <= Config.LOCAL_FIGHT_RADIUS
		then
			table.insert(hosts, member)
		end
	end
	return hosts
end

local function IsInEnemyTowerDanger(bot, target, lane)
	local enemyTeam = Safe(GetOpposingTeam(), function() return target:GetTeam() end)
	for tier = 1, 3 do
		local tower = GetLaneTower(enemyTeam, lane, tier)
		if CanInspectUnit(tower) and GetDistance(target, tower) <= Config.TOWER_DANGER_RADIUS then return true end
	end
	return false
end

local function GetNearestVisibleEnemyTowerDistance(target, lane)
	local enemyTeam = Safe(GetOpposingTeam(), function() return target:GetTeam() end)
	local best = 3000
	for tier = 1, 3 do
		local tower = GetLaneTower(enemyTeam, lane, tier)
		if CanInspectUnit(tower) then best = math.min(best, GetDistance(target, tower)) end
	end
	return best
end

local function GetOwnSideDepth(bot, target, lane)
	local location = Safe(nil, function() return target:GetLocation() end)
	if location == nil then return 0 end
	local amount = Safe(nil, function() return GetAmountAlongLane(lane, location) end)
	if type(amount) ~= 'number' then return 0 end
	amount = Clamp(amount, 0, 1)
	if Safe(TEAM_RADIANT, function() return bot:GetTeam() end) == TEAM_RADIANT then
		return 1 - amount
	end
	return amount
end

local function GetOffensivePower(unit)
	local power = Safe(0, function() return unit:GetOffensivePower() end) or 0
	if power > 0 then return power end
	return math.max(1, (Safe(1, function() return unit:GetLevel() end) or 1) * 100)
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
	for _, ally in ipairs(allies) do allyPower = allyPower + GetOffensivePower(ally) end
	local enemyPower = 0
	for _, enemy in ipairs(GetEnemyHeroes()) do
		if GetDistanceToLocation(enemy, location) <= Config.LOCAL_FIGHT_RADIUS then
			enemyPower = enemyPower + GetOffensivePower(enemy)
		end
	end
	if enemyPower <= 0 then return 2.0 end
	return allyPower / enemyPower
end

local function WasRecentlyDamagedByAlly(target)
	for _, member in ipairs(GetTeamMembers()) do
		if IsValidUnit(member)
			and Safe(false, function() return target:WasRecentlyDamagedByHero(member, 2.0) end)
		then
			return true
		end
	end
	return false
end

local function GetTravelCandidate(member, target, targetLane)
	if not CanInitiate(member) or GetAssignedLane(member) == targetLane then return nil end
	local speed = math.max(1, Safe(1, function() return member:GetCurrentMovementSpeed() end) or 1)
	local travelTime = GetDistance(member, target) / speed
	if travelTime > Config.APPROACH_TIMEOUT then return nil end
	local position = GetPosition(member)
	local rule = Config.POSITION_RULES[position]
	return {
		unit = member,
		playerID = GetPlayerID(member),
		position = position,
		travelTime = travelTime,
		effectiveTravelTime = travelTime + (rule.travelBias or 0),
	}
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
	for _, member in ipairs(GetTeamMembers()) do
		local candidate = GetTravelCandidate(member, target, targetLane)
		if candidate ~= nil then table.insert(candidates, candidate) end
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
		if #selected == 0 then return {} end
	end

	for _, candidate in ipairs(candidates) do
		local duplicate = false
		for _, current in ipairs(selected) do
			if current.playerID == candidate.playerID then duplicate = true break end
		end
		if not duplicate and #selected < Config.MAX_ROAMERS then table.insert(selected, candidate) end
	end
	return selected
end

function Coordinator.CalculateTargetScore(metrics)
	local healthScore = (1 - Clamp(metrics.healthFraction or 1, 0, 1)) * 0.35
	local powerScore = Clamp(((metrics.powerRatio or 0) - Config.MIN_START_POWER_RATIO) / 0.60, 0, 1) * 0.25
	local towerSafety = Clamp(((metrics.enemyTowerDistance or 0) - Config.TOWER_DANGER_RADIUS) / 1800, 0, 1)
	local laneDepth = Clamp(metrics.ownSideDepth or 0, 0, 1)
	local positionScore = (towerSafety + laneDepth) * 0.5 * 0.20
	local travelScore = Clamp(1 - (metrics.travelTime or Config.APPROACH_TIMEOUT) / Config.APPROACH_TIMEOUT, 0, 1) * 0.15
	local damageScore = metrics.recentlyDamaged and 0.05 or 0
	return healthScore + powerScore + positionScore + travelScore + damageScore
end

local function BuildTargetPlan(bot, target, fixedLeader)
	if not IsRealEnemyHero(bot, target) then return nil end
	local lane, laneDistance = GetNearestLane(target)
	if lane == nil or laneDistance > Config.LANE_DISTANCE then return nil end
	if #GetHostsNearTarget(target, lane) == 0 then return nil end
	if IsInEnemyTowerDanger(bot, target, lane) then return nil end

	local participants = BuildParticipants(target, lane, fixedLeader)
	if #participants == 0 then return nil end
	if fixedLeader ~= nil and participants[1].playerID ~= GetPlayerID(fixedLeader) then return nil end
	local powerRatio = GetPowerRatio(target, (function()
		local units = {}
		for _, participant in ipairs(participants) do table.insert(units, participant.unit) end
		return units
	end)(), true)
	if powerRatio < Config.MIN_START_POWER_RATIO then return nil end

	local targetPlayerID = GetPlayerID(target)
	local recentlyDamaged = WasRecentlyDamagedByAlly(target)
	local score = Coordinator.CalculateTargetScore({
		healthFraction = GetHealthFraction(target),
		powerRatio = powerRatio,
		enemyTowerDistance = GetNearestVisibleEnemyTowerDistance(target, lane),
		ownSideDepth = GetOwnSideDepth(bot, target, lane),
		travelTime = participants[1].travelTime,
		recentlyDamaged = recentlyDamaged,
	})
	local participantIDs = {}
	for _, participant in ipairs(participants) do table.insert(participantIDs, participant.playerID) end
	return {
		target = target,
		targetPlayerID = targetPlayerID,
		targetLane = lane,
		leader = participants[1].unit,
		leaderID = participants[1].playerID,
		participantIDs = participantIDs,
		score = score,
		travelTime = participants[1].travelTime,
		powerRatio = powerRatio,
	}
end

function Coordinator.BuildBestProposal(bot)
	local best = nil
	for _, target in ipairs(GetEnemyHeroes()) do
		local proposal = BuildTargetPlan(bot, target, nil)
		if proposal ~= nil and (best == nil
			or proposal.score > best.score + 0.0001
			or (math.abs(proposal.score - best.score) <= 0.0001 and proposal.targetPlayerID < best.targetPlayerID))
		then
			best = proposal
		end
	end
	return best
end

function Coordinator.IsAnnouncementValid(bot, source, target, ping, now)
	if source == nil or source == bot or ping == nil then return false end
	if source.IsBot == nil or not Safe(false, function() return source:IsBot() end) then return false end
	if Safe(BOT_MODE_NONE, function() return source:GetActiveMode() end) ~= BOT_MODE_ROAM then return false end
	if Safe(nil, function() return source:GetTarget() end) ~= target then return false end
	if not IsRealEnemyHero(bot, target) then return false end
	if ping.normal_ping ~= true or type(ping.time) ~= 'number' or ping.location == nil then return false end
	if now - ping.time < 0 or now - ping.time > Config.ANNOUNCEMENT_WINDOW then return false end
	return GetDistanceToLocation(target, ping.location) <= Config.ANNOUNCEMENT_TARGET_RADIUS
end

local function IsParticipant(playerID, participantIDs)
	for _, value in ipairs(participantIDs or {}) do
		if value == playerID then return true end
	end
	return false
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
			if Coordinator.IsAnnouncementValid(bot, source, target, ping, gameNow) then
				local signalAge = math.max(0, gameNow - ping.time)
				local missionStart = now - signalAge
				state.lastObservedMissionStart = math.max(state.lastObservedMissionStart, missionStart)
				local plan = BuildTargetPlan(bot, target, source)
				if plan ~= nil then
					plan.startTime = missionStart
					plan.signalTime = ping.time
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

local function Debug(bot, message)
	if Config.DEBUG ~= true then return end
	print('[BOT][Roam] pid=' .. tostring(GetPlayerID(bot)) .. ' ' .. tostring(message))
end

local function ClearTargetIfMatches(bot, mission)
	if mission == nil then return end
	if Safe(nil, function() return bot:GetTarget() end) == mission.target then
		Safe(nil, function() bot:SetTarget(nil) end)
	end
end

function Coordinator.Abort(bot, reason)
	local state = GetState(bot)
	local mission = state.mission or state.pending
	ClearTargetIfMatches(bot, mission)
	state.pending = nil
	state.mission = nil
	state.lastAbortReason = reason
	Debug(bot, 'release reason=' .. tostring(reason))
end

local function GetMissionDesire(bot, state)
	local mission = state.mission
	if mission == nil then return BOT_MODE_DESIRE_NONE end
	if not IsEnabled() then Coordinator.Abort(bot, 'disabled') return BOT_MODE_DESIRE_NONE end
	local now = DotaTime()
	if now - mission.startTime >= Config.MISSION_TIMEOUT then
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
	if J.IsDoingRoshan(bot) or J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		Coordinator.Abort(bot, 'team_objective')
		return BOT_MODE_DESIRE_NONE
	end

	if mission.leader ~= bot then
		if not IsValidUnit(mission.leader)
			or Safe(BOT_MODE_NONE, function() return mission.leader:GetActiveMode() end) ~= BOT_MODE_ROAM
			or Safe(nil, function() return mission.leader:GetTarget() end) ~= mission.target
		then
			Coordinator.Abort(bot, 'leader_released')
			return BOT_MODE_DESIRE_NONE
		end
	end

	mission.joinedParticipantIDs = mission.joinedParticipantIDs or {}
	for _, member in ipairs(GetTeamMembers()) do
		local memberID = GetPlayerID(member)
		if member ~= bot and IsParticipant(memberID, mission.participantIDs) then
			local matchingRoam = Safe(BOT_MODE_NONE, function() return member:GetActiveMode() end) == BOT_MODE_ROAM
				and Safe(nil, function() return member:GetTarget() end) == mission.target
			if matchingRoam then mission.joinedParticipantIDs[memberID] = true end
			if mission.joinedParticipantIDs[memberID]
				and (J.Retreat.ShouldYield(member, J.Retreat.HIGH) or not matchingRoam)
			then
				Coordinator.Abort(bot, 'participant_released')
				return BOT_MODE_DESIRE_NONE
			end
		end
	end

	local targetAlive = Safe(false, function() return mission.target:IsAlive() end)
	if not targetAlive then
		Coordinator.Abort(bot, 'target_dead')
		return BOT_MODE_DESIRE_NONE
	end
	local targetVisible = CanInspectUnit(mission.target)
	if targetVisible then
		mission.lastVisibleTime = now
		mission.lastLocation = Safe(mission.lastLocation, function() return mission.target:GetLocation() end)
	elseif now - (mission.lastVisibleTime or mission.startTime) > Config.LOST_TARGET_GRACE then
		Coordinator.Abort(bot, 'target_lost')
		return BOT_MODE_DESIRE_NONE
	end

	if targetVisible and IsInEnemyTowerDanger(bot, mission.target, mission.targetLane) then
		Coordinator.Abort(bot, 'tower_danger')
		return BOT_MODE_DESIRE_NONE
	end
	if targetVisible then
		local includeParticipants = mission.phase ~= 'engage'
		local participantUnits = {}
		for _, member in ipairs(GetTeamMembers()) do
			if IsParticipant(GetPlayerID(member), mission.participantIDs) then table.insert(participantUnits, member) end
		end
		if GetPowerRatio(mission.target, participantUnits, includeParticipants) < Config.MIN_CONTINUE_POWER_RATIO then
			Coordinator.Abort(bot, 'power_disadvantage')
			return BOT_MODE_DESIRE_NONE
		end
	end

	if mission.phase == 'approach' then
		local attacked = targetVisible and Safe(false, function() return mission.target:WasRecentlyDamagedByHero(bot, 1.0) end)
		local attackTarget = Safe(nil, function() return bot:GetAttackTarget() end)
		if targetVisible and (GetDistance(bot, mission.target) <= Config.ENGAGE_DISTANCE
			or attacked or attackTarget == mission.target)
		then
			mission.phase = 'engage'
			mission.engageStartTime = now
			Debug(bot, 'phase=engage target=' .. tostring(mission.targetPlayerID))
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
		return BOT_MODE_DESIRE_VERYHIGH
	end
	return BOT_MODE_DESIRE_HIGH
end

function Coordinator.GetDesire(bot)
	local state = GetState(bot)
	if state.mission ~= nil then return GetMissionDesire(bot, state) end
	if not IsEnabled() then
		state.pending = nil
		return BOT_MODE_DESIRE_NONE
	end

	local announcement = ObserveAnnouncements(bot)
	local urgentDefense = HasUrgentDefense(bot)
	if announcement ~= nil
		and not urgentDefense
		and IsParticipant(GetPlayerID(bot), announcement.participantIDs)
	then
		state.pending = announcement
		return BOT_MODE_DESIRE_HIGH
	end
	if not IsValidUnit(bot) or not Safe(false, function() return bot:IsAlive() end) then return BOT_MODE_DESIRE_NONE end
	if DotaTime() - state.lastObservedMissionStart < Config.TEAM_COOLDOWN then return BOT_MODE_DESIRE_NONE end
	if not CanInitiate(bot) then return BOT_MODE_DESIRE_NONE end
	if urgentDefense then return BOT_MODE_DESIRE_NONE end

	local proposal = Coordinator.BuildBestProposal(bot)
	if proposal == nil or proposal.leaderID ~= GetPlayerID(bot) then return BOT_MODE_DESIRE_NONE end
	proposal.startTime = DotaTime()
	proposal.phase = 'approach'
	proposal.lastLocation = Safe(nil, function() return proposal.target:GetLocation() end)
	state.pending = proposal
	return BOT_MODE_DESIRE_HIGH
end

function Coordinator.OnStart(bot)
	local state = GetState(bot)
	if not IsEnabled() or state.pending == nil then return false end
	state.mission = state.pending
	state.pending = nil
	local mission = state.mission
	if mission.leaderID == GetPlayerID(bot) then mission.startTime = DotaTime() end
	mission.joinedParticipantIDs = mission.joinedParticipantIDs or {}
	mission.joinedParticipantIDs[GetPlayerID(bot)] = true
	mission.lastVisibleTime = mission.startTime
	state.lastObservedMissionStart = math.max(state.lastObservedMissionStart, mission.startTime)
	J.SetTargetIfChanged(bot, mission.target, 0.1)

	if mission.leaderID == GetPlayerID(bot) then
		local location = mission.lastLocation
		if location ~= nil then bot:ActionImmediate_Ping(location.x, location.y, true) end
		if Config.ANNOUNCE_CHAT then
			bot:ActionImmediate_Chat('[Roam] 集火敌方玩家 ' .. tostring(mission.targetPlayerID), false)
		end
		Debug(bot, 'start target=' .. tostring(mission.targetPlayerID)
			.. ' participants=' .. table.concat(mission.participantIDs, ','))
	end
	return true
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
end

return Coordinator
