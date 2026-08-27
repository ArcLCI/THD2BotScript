local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local LaneAssignment = require(GetScriptDirectory()..'/THDFuncLib/lane_assignment')
local Config = require(GetScriptDirectory()..'/THDFuncLib/roam_config')
local Consumables = require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')
local CombatPower = require(GetScriptDirectory()..'/THDFuncLib/combat_power')

local Pickoff = {}
local observations = {}
local observationUpdateTimes = {}
local visibleEnemies = {}
local visibleEnemyUpdateTimes = {}
local lastPatrolStart = {}
local cachedGates = nil
local cachedNeutralZones = nil

local POSITION_NUMBER = {
	safe_core = 1,
	mid = 2,
	off_core = 3,
	soft_support = 4,
	hard_support = 5,
}

local INVISIBILITY_HEROES = Config.INVISIBILITY_HEROES

local function HeroNeedsDust(heroName)
	local aliases = Config.INVISIBILITY_SELECTION_ALIASES or {}
	return heroName ~= nil
		and (INVISIBILITY_HEROES[heroName] == true or INVISIBILITY_HEROES[aliases[heroName]] == true)
end

local function Safe(defaultValue, callback)
	local ok, value, extra = pcall(callback)
	if ok then return value, extra end
	return defaultValue
end

local function IsFiniteNumber(value)
	return type(value) == 'number'
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function Now()
	return Safe(0, function() return DotaTime() end) or 0
end

local function GetPlayerID(unit)
	if unit == nil then return -1 end
	return Safe(-1, function() return unit:GetPlayerID() end) or -1
end

local function GetEntityIndex(unit)
	if unit == nil then return nil end
	if unit.entindex ~= nil then
		local index = Safe(nil, function() return unit:entindex() end)
		if type(index) == 'number' and index >= 0 then return index end
	end
	if unit.GetEntityIndex ~= nil then
		local index = Safe(nil, function() return unit:GetEntityIndex() end)
		if type(index) == 'number' and index >= 0 then return index end
	end
	return nil
end

local function IsSamePlayer(first, second)
	local firstID = GetPlayerID(first)
	return firstID >= 0 and firstID == GetPlayerID(second)
end

local function IsMissionTargetHandle(mission, target)
	if mission == nil or target == nil then return false end
	if mission.targetPlayerID ~= nil and mission.targetPlayerID >= 0
		and GetPlayerID(target) ~= mission.targetPlayerID
	then
		return false
	end
	if mission.targetEntityIndex ~= nil then
		local actualIndex = GetEntityIndex(target)
		if actualIndex == nil or actualIndex ~= mission.targetEntityIndex then return false end
	end
	return true
end

local function GetUnitName(unit)
	if unit == nil or unit.GetUnitName == nil then return nil end
	return Safe(nil, function() return unit:GetUnitName() end)
end

local function IsValidUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.IsAlive ~= nil and not Safe(false, function() return unit:IsAlive() end) then return false end
	return true
end

local function CanInspect(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.CanBeSeen == nil or Safe(false, function() return unit:CanBeSeen() end) ~= true then return false end
	return unit.IsAlive == nil or Safe(false, function() return unit:IsAlive() end) == true
end

local function GetLocation(unit)
	if unit == nil then return nil end
	if unit.x ~= nil and unit.y ~= nil then return unit end
	return Safe(nil, function() return unit:GetLocation() end)
end

local function LocationDistance(first, second)
	first = GetLocation(first)
	second = GetLocation(second)
	if first == nil or second == nil then return math.huge end
	if J.GetLocationToLocationDistance ~= nil then
		local value = Safe(nil, function() return J.GetLocationToLocationDistance(first, second) end)
		if type(value) == 'number' then return value end
	end
	local dx = (first.x or 0) - (second.x or 0)
	local dy = (first.y or 0) - (second.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function GetHealthFraction(unit)
	local maxHealth = Safe(0, function() return unit:GetMaxHealth() end) or 0
	if maxHealth <= 0 then return 0 end
	return math.max(0, math.min(1, (Safe(0, function() return unit:GetHealth() end) or 0) / maxHealth))
end

local function GetManaFraction(unit)
	local maxMana = Safe(0, function() return unit:GetMaxMana() end) or 0
	if maxMana <= 0 then return 1 end
	return math.max(0, math.min(1, (Safe(0, function() return unit:GetMana() end) or 0) / maxMana))
end

local function GetTeamMembers()
	local result = {}
	local playerIDs = Safe({}, function() return GetTeamPlayers(GetTeam()) end) or {}
	local count = #playerIDs > 0 and #playerIDs or 5
	for index = 1, count do
		local member = Safe(nil, function() return GetTeamMember(index) end)
		if member ~= nil then table.insert(result, member) end
	end
	return result
end

local function IsRealVisibleEnemyHero(bot, unit)
	if not CanInspect(unit) then return false end
	local unitTeam = Safe(-1, function() return unit:GetTeam() end)
	local botTeam = Safe(-2, function() return bot:GetTeam() end)
	local opposingTeam = Safe(nil, function() return GetOpposingTeam() end)
	if unitTeam == botTeam or (opposingTeam ~= nil and unitTeam ~= opposingTeam) then return false end
	if not Safe(false, function() return unit:IsHero() end) then return false end
	if GetPlayerID(unit) < 0 then return false end
	if unit.IsKnownIllusion ~= nil and Safe(false, function() return unit:IsKnownIllusion() end) then return false end
	if unit.HasModifier ~= nil
		and Safe(false, function() return unit:HasModifier('modifier_illusion') end)
	then
		return false
	end
	return true
end

function Pickoff.IsMissionTargetValid(bot, mission, target)
	return IsRealVisibleEnemyHero(bot, target) and IsMissionTargetHandle(mission, target)
end

local function AddUniqueHero(result, seenPlayerIDs, unit)
	local playerID = GetPlayerID(unit)
	if playerID < 0 or seenPlayerIDs[playerID] then return end
	seenPlayerIDs[playerID] = true
	table.insert(result, unit)
end

local function GetVisibleEnemies(bot)
	local botID = GetPlayerID(bot)
	local now = Now()
	if now - (visibleEnemyUpdateTimes[botID] or -9999) < Config.PICKOFF_OBSERVATION_INTERVAL then
		local current = {}
		local seenPlayerIDs = {}
		for _, enemy in ipairs(visibleEnemies[botID] or {}) do
			if IsRealVisibleEnemyHero(bot, enemy) then AddUniqueHero(current, seenPlayerIDs, enemy) end
		end
		visibleEnemies[botID] = current
		return current
	end
	local result = {}
	local seenPlayerIDs = {}
	for _, unit in pairs(Safe({}, function() return GetUnitList(UNIT_LIST_ENEMY_HEROES) end) or {}) do
		-- 同一玩家的分身/克隆只代表一名参团英雄；显式幻象同时走双重过滤。
		if IsRealVisibleEnemyHero(bot, unit) then AddUniqueHero(result, seenPlayerIDs, unit) end
	end
	visibleEnemies[botID] = result
	visibleEnemyUpdateTimes[botID] = now
	return result
end

function Pickoff.GetTeamfightStatus(bot, location, radius)
	radius = tonumber(radius) or Config.ROAM_TEAMFIGHT_RADIUS
	local allyCount = 0
	local enemyCount = 0
	local allyPlayerIDs = {}
	local enemyPlayerIDs = {}
	if location ~= nil then
		local seenAllies = {}
		for _, member in ipairs(GetTeamMembers()) do
			local playerID = GetPlayerID(member)
			if IsValidUnit(member) and playerID >= 0 and not seenAllies[playerID]
				and LocationDistance(member, location) <= radius
			then
				seenAllies[playerID] = true
				allyCount = allyCount + 1
				table.insert(allyPlayerIDs, playerID)
			end
		end
		-- 复用按 Bot 分桶的可见敌人缓存，不把游戏侧全图信息带入 Bot 决策。
		for _, enemy in ipairs(GetVisibleEnemies(bot)) do
			if LocationDistance(enemy, location) <= radius then
				enemyCount = enemyCount + 1
				table.insert(enemyPlayerIDs, GetPlayerID(enemy))
			end
		end
	end
	table.sort(allyPlayerIDs)
	table.sort(enemyPlayerIDs)
	local totalHeroCount = allyCount + enemyCount
	local active = Now() >= Config.ROAM_TEAMFIGHT_START_TIME
		and allyCount >= Config.ROAM_TEAMFIGHT_MIN_ALLIES
		and enemyCount >= Config.ROAM_TEAMFIGHT_MIN_ENEMIES
		and totalHeroCount >= Config.ROAM_TEAMFIGHT_MIN_TOTAL_HEROES
	return active, {
		allyCount = allyCount,
		enemyCount = enemyCount,
		totalHeroCount = totalHeroCount,
		allyPlayerIDs = allyPlayerIDs,
		enemyPlayerIDs = enemyPlayerIDs,
		radius = radius,
	}
end

local function GetObservationState(bot)
	local id = GetPlayerID(bot)
	if observations[id] == nil then observations[id] = {} end
	return observations[id]
end

local function UpdateObservations(bot)
	local state = GetObservationState(bot)
	local botID = GetPlayerID(bot)
	local now = Now()
	if now - (observationUpdateTimes[botID] or -9999) < Config.PICKOFF_OBSERVATION_INTERVAL then
		return state
	end
	observationUpdateTimes[botID] = now
	local visibleByID = {}
	for _, enemy in ipairs(GetVisibleEnemies(bot)) do
		local playerID = GetPlayerID(enemy)
		if playerID >= 0 then
			local defense = CombatPower.GetDefenseSnapshot(enemy)
			local attack = CombatPower.GetAttackSnapshot(enemy)
			visibleByID[playerID] = enemy
			state[playerID] = {
				playerID = playerID,
				heroName = GetUnitName(enemy),
				handle = enemy,
				entityIndex = GetEntityIndex(enemy),
				visible = true,
				location = GetLocation(enemy),
				seenAge = 0,
				health = defense ~= nil and defense.health or nil,
				maxHealth = defense ~= nil and defense.maxHealth or nil,
				defense = defense,
				level = Safe(nil, function() return enemy:GetLevel() end),
				attackDamage = attack ~= nil and attack.attackDamage or nil,
				attackPeriod = attack ~= nil and attack.attackPeriod or nil,
				updatedTime = Now(),
			}
		end
	end

	for _, playerID in ipairs(Safe({}, function() return GetTeamPlayers(GetOpposingTeam()) end) or {}) do
		if visibleByID[playerID] == nil then
			local info = Safe(nil, function() return GetHeroLastSeenInfo(playerID) end)
			local latest = type(info) == 'table' and info[1] or nil
			local previous = state[playerID] or {}
			local selectedHeroName = Safe(nil, function() return GetSelectedHeroName(playerID) end)
			local heroChanged = previous.heroName ~= nil and selectedHeroName ~= nil
				and previous.heroName ~= selectedHeroName
			if heroChanged then
				-- 同一玩家换英雄后，旧英雄的最后位置/血量/实体索引不能继续生成抓单任务。
				state[playerID] = {
					playerID = playerID, heroName = selectedHeroName, handle = nil,
					entityIndex = nil, visible = false, location = nil,
					seenAge = math.huge, updatedTime = Now(),
				}
			elseif type(latest) == 'table' and latest.location ~= nil and type(latest.time_since_seen) == 'number' then
				previous.playerID = playerID
				previous.heroName = previous.heroName or selectedHeroName
				previous.handle = nil
				previous.visible = false
				previous.location = latest.location
				previous.seenAge = math.max(0, latest.time_since_seen)
				previous.updatedTime = Now()
				state[playerID] = previous
			elseif previous.playerID ~= nil then
				previous.visible = false
				previous.handle = nil
				previous.seenAge = math.huge
			end
		end
	end
	return state
end

local function GetNeutralZones()
	if cachedNeutralZones ~= nil then return cachedNeutralZones end
	local zones = {}
	for index, camp in pairs(Safe({}, function() return GetNeutralSpawners() end) or {}) do
		local location = type(camp) == 'table' and (camp.location or camp.pos) or nil
		if location ~= nil then
			table.insert(zones, {
				id = tostring(index) .. ':' .. tostring(math.floor((location.x or 0) / 100))
					.. ':' .. tostring(math.floor((location.y or 0) / 100)),
				location = location,
			})
		end
	end
	cachedNeutralZones = zones
	return cachedNeutralZones
end

local function IsNearNeutralZone(location)
	for _, zone in ipairs(GetNeutralZones()) do
		if LocationDistance(location, zone.location) <= 1000 then return true, zone end
	end
	return false, nil
end

local function GetEnemyPower(observation)
	local damage = tonumber(observation.attackDamage)
	local period = tonumber(observation.attackPeriod)
	local maxHealth = tonumber(observation.maxHealth)
	local level = tonumber(observation.level)
	local health = tonumber(observation.health)
	if not IsFiniteNumber(damage) or damage < 0
		or not IsFiniteNumber(period) or period <= 0
		or not IsFiniteNumber(maxHealth) or maxHealth <= 0
		or not IsFiniteNumber(level) or level < 0
		or not IsFiniteNumber(health)
	then
		return math.huge
	end
	local healthFraction = math.max(0.1, math.min(1, health / maxHealth))
	local power = (damage / math.max(0.25, period) + maxHealth * 0.035 + math.max(1, level) * 5)
		* (0.25 + 0.75 * healthFraction)
	return IsFiniteNumber(power) and math.max(1, power) or math.huge
end

local function GetAllyPower(unit)
	return CombatPower.Estimate(unit)
end

local function IsBusy(unit)
	local mode = Safe(BOT_MODE_NONE, function() return unit:GetActiveMode() end)
	return mode == BOT_MODE_RETREAT
		or J.Retreat.ShouldYield(unit, J.Retreat.HIGH)
		or J.IsRoshanCommitmentActive(unit)
		or J.Utils.IsTeamPushingSecondTierOrHighGround(unit)
end

local function GetPosition(unit)
	return Safe(nil, function() return LaneAssignment.GetAssignedPosition(unit) end)
end

local function GetReadyTP(unit)
	local item = Safe(nil, function() return J.Utils.GetItemFromFullInventory(unit, 'item_tpscroll') end)
	if item == nil or not Safe(false, function() return J.CanCastAbility(item) end) then return nil end
	return item
end

local function BuildTPPlan(unit, targetLocation, distance, speed)
	if distance < Config.TP_MIN_WALK_DISTANCE or GetReadyTP(unit) == nil then return nil end
	if Safe(false, function() return unit:WasRecentlyDamagedByAnyHero(2.0) end) then return nil end
	if #(Safe({}, function() return unit:GetNearbyHeroes(Config.TP_SAFE_RADIUS, true, BOT_MODE_NONE) end) or {}) > 0 then return nil end
	local tpLocation = Safe(nil, function() return J.GetNearbyLocationToTp(targetLocation) end)
	if tpLocation == nil then return nil end
	local landingDistance = LocationDistance(tpLocation, targetLocation)
	if landingDistance > Config.TP_MAX_LANDING_DISTANCE then return nil end
	local item = GetReadyTP(unit)
	local channel = Safe(Config.TP_CHANNEL_TIME_ESTIMATE, function() return item:GetChannelTime() end)
	if type(channel) ~= 'number' or channel <= 0 then channel = Config.TP_CHANNEL_TIME_ESTIMATE end
	local travel = channel + landingDistance / speed
	if travel + Config.TP_MIN_TIME_SAVING >= distance / speed then return nil end
	return {
		route = 'tp', useTP = true, tpLocation = tpLocation, targetLocation = targetLocation,
		landingDistance = landingDistance, channelTime = channel, travelTime = travel,
		walkDistance = distance,
	}
end

local function DiscoverTwinGates()
	if cachedGates ~= nil then return cachedGates end
	cachedGates = {}
	for _, unit in pairs(Safe({}, function() return GetUnitList(UNIT_LIST_ALL) end) or {}) do
		if IsValidUnit(unit) and GetUnitName(unit) == 'npc_dota_unit_twin_gate' then
			table.insert(cachedGates, unit)
			if #cachedGates >= 2 then break end
		end
	end
	return cachedGates
end

local function BuildGatePlan(unit, targetLocation, distance, speed)
	if Config.ENABLE_TWIN_GATE_ROUTE ~= true then return nil end
	local gates = DiscoverTwinGates()
	if #gates < 2 or unit.GetAbilityByName == nil then return nil end
	local ability = Safe(nil, function() return unit:GetAbilityByName('twin_gate_portal_warp') end)
	if ability == nil or not Safe(false, function() return ability:IsFullyCastable() end) then return nil end
	if Safe(false, function() return unit:WasRecentlyDamagedByAnyHero(2.0) end) then return nil end
	if #(Safe({}, function() return unit:GetNearbyHeroes(Config.TWIN_GATE_SAFE_RADIUS, true, BOT_MODE_NONE) end) or {}) > 0 then return nil end
	local best = nil
	for entranceIndex = 1, 2 do
		local exitIndex = entranceIndex == 1 and 2 or 1
		local entrance, exitGate = gates[entranceIndex], gates[exitIndex]
		local entranceWalk = LocationDistance(unit, entrance)
		local exitWalk = LocationDistance(exitGate, targetLocation)
		local travel = entranceWalk / speed + Config.TWIN_GATE_CHANNEL_TIME_ESTIMATE + exitWalk / speed
		if travel + Config.TP_MIN_TIME_SAVING < distance / speed
			and (best == nil or travel < best.travelTime)
		then
			best = {
				route = 'twin_gate', useTP = false, gateEntrance = entrance, gateExit = exitGate,
				targetLocation = targetLocation, travelTime = travel, walkDistance = distance,
				landingDistance = exitWalk, channelTime = Config.TWIN_GATE_CHANNEL_TIME_ESTIMATE,
			}
		end
	end
	return best
end

local function BuildStagingLocation(location)
	local fountain = Safe(nil, function() return J.GetTeamFountain() end)
	if fountain == nil then return location end
	local dx = (fountain.x or 0) - (location.x or 0)
	local dy = (fountain.y or 0) - (location.y or 0)
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1 then return location end
	local x = (location.x or 0) + dx / length * Config.PICKOFF_STAGING_DISTANCE
	local y = (location.y or 0) + dy / length * Config.PICKOFF_STAGING_DISTANCE
	local z = location.z or 0
	-- 原生移动指令只接受 Vector；无 Vector 的 Lua 测试环境保留坐标表兼容。
	if type(Vector) == 'function' then return Vector(x, y, z) end
	return {x = x, y = y, z = z}
end

local function BuildTravelCandidate(unit, targetLocation, strategyState)
	if not IsValidUnit(unit) or IsBusy(unit) then return nil, 'busy' end
	if Safe(false, function() return unit:IsBot() end) ~= true then return nil, 'not_bot' end
	local position = GetPosition(unit)
	local number = POSITION_NUMBER[position]
	if number == nil then return nil, 'position_unknown' end
	local activeMode = Safe(BOT_MODE_NONE, function() return unit:GetActiveMode() end)
	if Wasteland.ShouldProtectOuterPushParticipant(position, activeMode, strategyState, unit) then
		return nil, 'wasteland_outer_push_commitment'
	end
	local distance = LocationDistance(unit, targetLocation)
	if position == 'safe_core' and distance > Config.PICKOFF_GROUP_RADIUS then
		-- 一号位的远程特例在整队战力与击杀时间通过后才放行。
	end
	local rule = Config.PICKOFF_POSITION_RULES[position]
	if rule == nil then return nil, 'position_not_allowed' end
	if Safe(0, function() return unit:GetLevel() end) < rule.minLevel then return nil, 'level_too_low' end
	if GetHealthFraction(unit) < rule.minHealth then return nil, 'health_too_low' end
	if GetManaFraction(unit) < rule.minMana then return nil, 'mana_too_low' end
	local speed = math.max(1, Safe(1, function() return unit:GetCurrentMovementSpeed() end) or 1)
	local plan = {route = 'walk', useTP = false, targetLocation = targetLocation,
		travelTime = distance / speed, walkDistance = distance}
	local tp = BuildTPPlan(unit, targetLocation, distance, speed)
	local gate = BuildGatePlan(unit, targetLocation, distance, speed)
	if tp ~= nil and tp.travelTime < plan.travelTime then plan = tp end
	if gate ~= nil and gate.travelTime < plan.travelTime then plan = gate end
	-- 集合点位于目标朝己方泉水方向偏移处；把参与者走到集合点的行程写进旅行计划，
	-- 供 assemble 阶段按预期到达时间提前排期，而不是用固定 8 秒一刀切。
	local stagingLocation = BuildStagingLocation(targetLocation)
	local stagingTravelTime = LocationDistance(unit, stagingLocation) / speed
	if plan.route == 'tp' and plan.tpLocation ~= nil then
		stagingTravelTime = (plan.channelTime or Config.TP_CHANNEL_TIME_ESTIMATE)
			+ LocationDistance(plan.tpLocation, stagingLocation) / speed
	elseif plan.route == 'twin_gate' and plan.gateExit ~= nil then
		stagingTravelTime = (plan.channelTime or Config.TWIN_GATE_CHANNEL_TIME_ESTIMATE)
			+ LocationDistance(plan.gateExit, stagingLocation) / speed
	end
	plan.stagingLocation = stagingLocation
	plan.stagingTravelTime = stagingTravelTime
	if plan.travelTime > Config.PICKOFF_APPROACH_TIMEOUT then return nil, 'travel_too_long' end
	return {
		unit = unit, playerID = GetPlayerID(unit), position = position, positionNumber = number,
		travelTime = plan.travelTime, effectiveTravelTime = plan.travelTime + (rule.travelBias or 0),
		plan = plan, distance = distance,
	}
end

local function SortTravel(candidates)
	table.sort(candidates, function(a, b)
		if math.abs(a.effectiveTravelTime - b.effectiveTravelTime) > 0.001 then
			return a.effectiveTravelTime < b.effectiveTravelTime
		end
		return a.playerID < b.playerID
	end)
end

local function CandidateHasItem(candidate, itemName)
	return candidate ~= nil and itemName ~= nil
		and Consumables.FindItem(candidate.unit, itemName) ~= nil
end

local function SelectParticipants(targetLocation, requiredCount, fixedLeader, requiredItems)
	local candidates, rejected = {}, {}
	local strategyState = Wasteland.IsEnabled() and Wasteland.GetState() or nil
	for _, member in ipairs(GetTeamMembers()) do
		local candidate, reason = BuildTravelCandidate(member, targetLocation, strategyState)
		if candidate ~= nil then table.insert(candidates, candidate)
		else rejected[reason or 'unknown'] = (rejected[reason or 'unknown'] or 0) + 1 end
	end
	SortTravel(candidates)
	local selected = {}
	if fixedLeader ~= nil then
		local leaderID = GetPlayerID(fixedLeader)
		for _, candidate in ipairs(candidates) do
			if candidate.playerID == leaderID and Config.POSITION_RULES[candidate.position] ~= nil then
				table.insert(selected, candidate)
				break
			end
		end
		if #selected == 0 then return {}, rejected end
	else
		-- 1/3号位可以参团但不能成为共享 ROAM 信号发起者，避免选出永远无法 OnStart 的 leader。
		for _, candidate in ipairs(candidates) do
			if Config.POSITION_RULES[candidate.position] ~= nil then
				table.insert(selected, candidate)
				break
			end
		end
		if #selected == 0 then return {}, rejected end
	end
	for _, itemName in ipairs(requiredItems or {}) do
		local alreadyCovered = false
		for _, candidate in ipairs(selected) do
			if CandidateHasItem(candidate, itemName) then alreadyCovered = true break end
		end
		if not alreadyCovered then
			local holder = nil
			for _, candidate in ipairs(candidates) do
				local duplicate = false
				for _, current in ipairs(selected) do
					if current.playerID == candidate.playerID then duplicate = true break end
				end
				if not duplicate and CandidateHasItem(candidate, itemName) then holder = candidate break end
			end
			if holder == nil or #selected >= Config.PICKOFF_MAX_PARTICIPANTS then return {}, rejected end
			table.insert(selected, holder)
		end
	end
	for _, candidate in ipairs(candidates) do
		local duplicate = false
		for _, current in ipairs(selected) do
			if current.playerID == candidate.playerID then duplicate = true break end
		end
		if not duplicate and #selected < requiredCount then table.insert(selected, candidate) end
	end
	if #selected < requiredCount then return {}, rejected end
	return selected, rejected
end

local function CountEnemyGroup(state, targetObservation)
	local group = {}
	for playerID, observation in pairs(state) do
		if playerID >= 0
			and Safe(false, function() return IsHeroAlive(playerID) end)
			and observation.location ~= nil
			and (observation.visible or observation.seenAge <= Config.PICKOFF_LAST_SEEN_MAX_AGE)
			and LocationDistance(observation.location, targetObservation.location) <= Config.PICKOFF_GROUP_RADIUS
		then
			table.insert(group, observation)
		end
	end
	table.sort(group, function(a, b) return a.playerID < b.playerID end)
	return group
end

local function CountUnknownAndCheckReinforcements(state, group, latestArrival, killTime)
	local grouped = {}
	for _, observation in ipairs(group) do grouped[observation.playerID] = true end
	local unknown = 0
	for _, playerID in ipairs(Safe({}, function() return GetTeamPlayers(GetOpposingTeam()) end) or {}) do
		if not grouped[playerID] and Safe(true, function() return IsHeroAlive(playerID) end) then
			local observation = state[playerID]
			if observation == nil or observation.location == nil
				or observation.seenAge > Config.PICKOFF_LAST_SEEN_MAX_AGE
			then
				unknown = unknown + 1
			else
				local distance = LocationDistance(observation.location, group[1].location)
				local arrival = distance / 350
				if arrival <= latestArrival + killTime + Config.PICKOFF_REINFORCEMENT_BUFFER then
					return unknown, false, playerID
				end
			end
		end
	end
	return unknown, true, nil
end

local function EstimateDamage(participants, observation, window)
	local totalDamage = 0
	for _, participant in ipairs(participants) do
		local unit = participant.unit
		-- 仅用可见基础攻击与目标护甲估算，避免原生接口解析自定义技能的空目标路径。
		local damage = CombatPower.EstimateAttackDamageFromSnapshots(
			CombatPower.GetAttackSnapshot(unit),
			observation.defense,
			window,
			0.65
		) or 0
		totalDamage = totalDamage + math.max(0, damage)
	end
	local health = math.max(1, tonumber(observation.health) or tonumber(observation.maxHealth) or 1)
	local dps = totalDamage / math.max(0.1, window)
	return totalDamage, dps > 0 and health / dps or math.huge
end

local function FindHolder(participants, itemName)
	for _, participant in ipairs(participants) do
		local item = Consumables.FindItem(participant.unit, itemName)
		if item ~= nil then return participant.playerID end
	end
	return nil
end

local function TeamHasCarriedItem(itemName)
	for _, member in ipairs(GetTeamMembers()) do
		if Consumables.FindItem(member, itemName) ~= nil then return true end
	end
	return false
end

function Pickoff.ShouldUseSmokeForVisibleTarget(distance, teamHasSmoke)
	return Config.SMOKE_ENABLED == true
		and teamHasSmoke == true
		and type(distance) == 'number'
		and distance >= Config.PICKOFF_VISIBLE_SMOKE_MIN_DISTANCE
end

function Pickoff.GetSmokeRequirement(targetVisible, distance, teamHasSmoke)
	if targetVisible ~= true then
		if Config.SMOKE_ENABLED ~= true then return nil, 'smoke_disabled' end
		return true, nil
	end
	return Pickoff.ShouldUseSmokeForVisibleTarget(distance, teamHasSmoke), nil
end

local function BuildPickoffPlan(bot, state, observation, fixedLeader)
	if observation == nil or observation.location == nil then return nil, 'invalid_observation' end
	if observation.playerID == nil
		or Safe(false, function() return IsHeroAlive(observation.playerID) end) ~= true
	then
		return nil, 'target_dead'
	end
	if not observation.visible then
		if observation.seenAge > Config.PICKOFF_LAST_SEEN_MAX_AGE then return nil, 'last_seen_stale' end
		local nearCamp = IsNearNeutralZone(observation.location)
		if not nearCamp then return nil, 'last_seen_not_jungle' end
	end
	local group = CountEnemyGroup(state, observation)
	if #group < 1 or #group > Config.PICKOFF_MAX_ENEMIES then return nil, 'enemy_group_size' end
	local requiredCount = #group + 1
	-- 接收队友公告时按被冻结的任务发起者计算距离，不能让接收者的位置反转用烟判断。
	local leaderDistance = LocationDistance(fixedLeader or bot, observation.location)
	local teamHasSmoke = Config.SMOKE_ENABLED == true
		and TeamHasCarriedItem('item_smoke_of_deceit')
	local requiresSmoke, smokeReason = Pickoff.GetSmokeRequirement(observation.visible, leaderDistance,
		teamHasSmoke)
	if requiresSmoke == nil then return nil, smokeReason end
	local requiresDust = false
	for _, enemy in ipairs(group) do
		if HeroNeedsDust(enemy.heroName) then requiresDust = true break end
	end
	local requiredItems = {}
	if requiresSmoke then table.insert(requiredItems, 'item_smoke_of_deceit') end
	if requiresDust then table.insert(requiredItems, 'item_dust') end
	local participants, rejects = SelectParticipants(observation.location, requiredCount, fixedLeader, requiredItems)
	if #participants < requiredCount then return nil, 'participants_unavailable', rejects end
	requiredCount = #participants

	local latestArrival = 0
	local latestStagingArrival = 0
	local allyPower = 0
	for _, participant in ipairs(participants) do
		latestArrival = math.max(latestArrival, participant.travelTime)
		local stagingTime = participant.plan ~= nil and tonumber(participant.plan.stagingTravelTime) or nil
		if stagingTime ~= nil then latestStagingArrival = math.max(latestStagingArrival, stagingTime) end
		allyPower = allyPower + GetAllyPower(participant.unit)
	end
	local enemyPower = 0
	for _, enemy in ipairs(group) do enemyPower = enemyPower + GetEnemyPower(enemy) end
	local ratio = enemyPower > 0 and allyPower / enemyPower or 2
	local killLimit = #group == 1 and Config.PICKOFF_SINGLE_KILL_TIME or Config.PICKOFF_PAIR_FIRST_KILL_TIME
	local unknown, reinforcementSafe, reinforcementID = CountUnknownAndCheckReinforcements(
		state, group, latestArrival, killLimit)
	if unknown > Config.PICKOFF_MAX_UNKNOWN_ENEMIES then return nil, 'too_many_unknown', unknown end
	if not reinforcementSafe then return nil, 'reinforcement_risk', reinforcementID end
	local requiredRatio = (#group == 1 and Config.PICKOFF_SINGLE_POWER_RATIO or Config.PICKOFF_PAIR_POWER_RATIO)
		+ unknown * Config.PICKOFF_UNKNOWN_POWER_BONUS
	killLimit = killLimit - unknown * Config.PICKOFF_UNKNOWN_KILL_TIME_PENALTY
	local damage, predictedKill = EstimateDamage(participants, observation, killLimit)
	if not observation.visible then
		local cachedHealth = math.max(1, tonumber(observation.health) or tonumber(observation.maxHealth) or 1)
		if damage < cachedHealth * Config.PICKOFF_CACHED_DAMAGE_MARGIN then return nil, 'cached_damage_too_low' end
	end
	if ratio < requiredRatio then return nil, 'pickoff_power_too_low', ratio end
	if predictedKill > killLimit then return nil, 'pickoff_kill_too_slow', predictedKill end

	for _, participant in ipairs(participants) do
		if participant.position == 'safe_core' and participant.distance > Config.PICKOFF_GROUP_RADIUS then
			if #group ~= 1 or predictedKill > Config.PICKOFF_SAFE_CORE_KILL_TIME
				or ratio < Config.PICKOFF_SAFE_CORE_POWER_RATIO
				or participant.travelTime > Config.PICKOFF_SAFE_CORE_MAX_TRAVEL_TIME
			then
				return nil, 'safe_core_not_exceptional'
			end
		end
	end

	local smokeOwnerID = FindHolder(participants, 'item_smoke_of_deceit')
	if requiresSmoke and smokeOwnerID == nil then return nil, 'smoke_unavailable' end
	local participantIDs, participantLevels, travelPlans = {}, {}, {}
	for _, participant in ipairs(participants) do
		table.insert(participantIDs, participant.playerID)
		table.insert(participantLevels, tostring(participant.playerID) .. ':'
			.. tostring(Safe(0, function() return participant.unit:GetLevel() end)))
		travelPlans[participant.playerID] = participant.plan
	end
	local groupIDs = {}
	for _, enemy in ipairs(group) do table.insert(groupIDs, enemy.playerID) end
	local dustOwnerID = requiresDust and FindHolder(participants, 'item_dust') or nil
	if requiresDust and dustOwnerID == nil then return nil, 'dust_unavailable' end
	return {
		kind = 'pickoff', target = observation.handle, targetPlayerID = observation.playerID,
		targetEntityIndex = observation.entityIndex,
		targetHeroName = observation.heroName, targetObservation = observation,
		targetGroupIDs = groupIDs, targetLane = nil, leader = participants[1].unit,
		leaderID = participants[1].playerID, leaderLevel = Safe(0, function() return participants[1].unit:GetLevel() end),
		participantIDs = participantIDs, participantLevels = participantLevels,
		requiredCount = requiredCount, enemyCount = #group, allyCount = #participants,
		powerRatio = ratio, requiredPowerRatio = requiredRatio, predictedKillTime = predictedKill,
		killTimeLimit = killLimit, unknownEnemyCount = unknown, score = 2 + (killLimit - predictedKill) / 10,
		travelTime = participants[1].travelTime, travelPlans = travelPlans,
		latestStagingArrival = latestStagingArrival,
		useTP = participants[1].plan.route == 'tp', route = participants[1].plan.route,
		lastLocation = observation.location, rallyLocation = observation.location,
		stagingLocation = BuildStagingLocation(observation.location),
		requiresSmoke = requiresSmoke, smokeOwnerID = smokeOwnerID,
		requiresDust = requiresDust, dustOwnerID = dustOwnerID,
		resourcePlans = {smokeOwnerID = smokeOwnerID, dustOwnerID = dustOwnerID},
	}
end

local function BuildPatrolPlan(bot, state, fixedLeader, requiredZoneID)
	if Config.SMOKE_ENABLED ~= true then return nil, 'disabled' end
	local team = Safe(GetTeam(), function() return bot:GetTeam() end)
	if Now() - (lastPatrolStart[team] or -9999) < Config.SMOKE_PATROL_COOLDOWN then
		return nil, 'patrol_cooldown'
	end
	local evidence = nil
	for _, observation in pairs(state) do
		if observation.location ~= nil
			and observation.playerID ~= nil
			and Safe(false, function() return IsHeroAlive(observation.playerID) end)
			and observation.seenAge >= Config.SMOKE_PATROL_MIN_EVIDENCE_AGE
			and observation.seenAge <= Config.SMOKE_PATROL_MAX_EVIDENCE_AGE
		then
			local nearCamp, zone = IsNearNeutralZone(observation.location)
			local zoneID = zone ~= nil and zone.id or ('last_seen:' .. tostring(observation.playerID))
			if nearCamp and (requiredZoneID == nil or zoneID == requiredZoneID)
				and (evidence == nil or observation.seenAge < evidence.observation.seenAge)
			then
				evidence = {observation = observation, zone = zone, zoneID = zoneID}
			end
		end
	end
	if evidence == nil then return nil, 'patrol_no_evidence' end
	local targetLocation = evidence.zone ~= nil and evidence.zone.location or evidence.observation.location
	local participants, rejects = SelectParticipants(targetLocation, Config.SMOKE_PATROL_PARTICIPANTS,
		fixedLeader, {'item_smoke_of_deceit'})
	if #participants < Config.SMOKE_PATROL_PARTICIPANTS then return nil, 'patrol_participants_unavailable', rejects end
	for _, participant in ipairs(participants) do
		if participant.position == 'safe_core'
			or GetHealthFraction(participant.unit) < Config.SMOKE_MIN_HEALTH
			or GetManaFraction(participant.unit) < Config.SMOKE_MIN_MANA
		then
			return nil, 'patrol_participant_not_ready'
		end
	end
	local smokeOwnerID = FindHolder(participants, 'item_smoke_of_deceit')
	if smokeOwnerID == nil then return nil, 'smoke_unavailable' end
	local participantIDs, participantLevels, travelPlans = {}, {}, {}
	for _, participant in ipairs(participants) do
		table.insert(participantIDs, participant.playerID)
		table.insert(participantLevels, tostring(participant.playerID) .. ':'
			.. tostring(Safe(0, function() return participant.unit:GetLevel() end)))
		travelPlans[participant.playerID] = participant.plan
	end
	local latestStagingArrival = 0
	for _, participant in ipairs(participants) do
		local stagingTime = participant.plan ~= nil and tonumber(participant.plan.stagingTravelTime) or nil
		if stagingTime ~= nil then latestStagingArrival = math.max(latestStagingArrival, stagingTime) end
	end
	local zoneID = evidence.zoneID
	return {
		kind = 'smoke_patrol', target = nil, targetPlayerID = -1000 - evidence.observation.playerID,
		targetHeroName = evidence.observation.heroName, patrolEvidencePlayerID = evidence.observation.playerID,
		zoneID = zoneID, leader = participants[1].unit, leaderID = participants[1].playerID,
		leaderLevel = Safe(0, function() return participants[1].unit:GetLevel() end),
		participantIDs = participantIDs, participantLevels = participantLevels,
		requiredCount = Config.SMOKE_PATROL_PARTICIPANTS, allyCount = #participants, enemyCount = 0,
		score = 1.5, travelTime = participants[1].travelTime, travelPlans = travelPlans,
		useTP = participants[1].plan.route == 'tp', route = participants[1].plan.route,
		lastLocation = targetLocation, rallyLocation = targetLocation,
		stagingLocation = BuildStagingLocation(targetLocation), requiresSmoke = true,
		latestStagingArrival = latestStagingArrival,
		smokeOwnerID = smokeOwnerID, resourcePlans = {smokeOwnerID = smokeOwnerID},
	}
end

function Pickoff.BuildBestProposal(bot, fixedLeader)
	if Now() < Config.PICKOFF_START_TIME then return nil, {pickoff_before_start = 1} end
	local state = UpdateObservations(bot)
	local best, rejected = nil, {}
	for _, observation in pairs(state) do
		if observation.visible or observation.seenAge <= Config.PICKOFF_LAST_SEEN_MAX_AGE then
			local proposal, reason = BuildPickoffPlan(bot, state, observation, fixedLeader)
			if proposal ~= nil and (best == nil or proposal.score > best.score) then best = proposal end
			if proposal == nil then rejected['pickoff_' .. tostring(reason or 'unknown')]
				= (rejected['pickoff_' .. tostring(reason or 'unknown')] or 0) + 1 end
		end
	end
	if best ~= nil then return best, rejected end
	local patrol, patrolReason = BuildPatrolPlan(bot, state, fixedLeader)
	if patrol ~= nil then return patrol, rejected end
	rejected['smoke_' .. tostring(patrolReason or 'unknown')] = 1
	return nil, rejected
end

function Pickoff.RefreshProposal(bot, mission, fixedLeader)
	if mission == nil then return nil, 'invalid_mission' end
	local proposal = nil
	local rejected = nil
	if mission.kind == 'pickoff' and mission.targetPlayerID ~= nil then
		local state = UpdateObservations(bot)
		proposal, rejected = BuildPickoffPlan(bot, state, state[mission.targetPlayerID], fixedLeader)
	elseif mission.kind == 'smoke_patrol' then
		local state = UpdateObservations(bot)
		proposal, rejected = BuildPatrolPlan(bot, state, fixedLeader, mission.zoneID)
	else
		return nil, 'invalid_mission_kind'
	end
	if proposal == nil then return nil, rejected or 'refresh_failed' end
	return proposal
end

function Pickoff.IsSignalCandidate(bot, source, ping, now, maxAge)
	if source == nil or IsSamePlayer(source, bot) or ping == nil then return false end
	if source.IsBot == nil or not Safe(false, function() return source:IsBot() end) then return false end
	if Safe(BOT_MODE_NONE, function() return source:GetActiveMode() end) ~= BOT_MODE_ROAM then return false end
	if ping.normal_ping ~= true or type(ping.time) ~= 'number' or ping.location == nil then return false end
	local age = now - ping.time
	return age >= 0 and age <= (maxAge or Config.ANNOUNCEMENT_WINDOW)
end

function Pickoff.BuildAnnouncement(bot, source, ping, now)
	if not Pickoff.IsSignalCandidate(bot, source, ping, now, Config.ANNOUNCEMENT_WINDOW) then return nil end
	local plan = Pickoff.BuildBestProposal(bot, source)
	if plan == nil then return nil end
	local sourceTarget = Safe(nil, function() return source:GetTarget() end)
	if plan.kind == 'smoke_patrol' and sourceTarget ~= nil then return nil end
	if plan.kind == 'pickoff' and plan.target ~= nil
		and not IsMissionTargetHandle(plan, sourceTarget)
	then
		return nil
	end
	-- 新任务用集结点发信号，与普通 lane_gank 在目标脚下的 ping 做空间区分。
	local location = plan.stagingLocation or plan.rallyLocation or plan.lastLocation
	if LocationDistance(location, ping.location) > Config.ANNOUNCEMENT_TARGET_RADIUS then return nil end
	return plan
end

local function GetParticipants(mission)
	local units = {}
	for _, member in ipairs(GetTeamMembers()) do
		for _, playerID in ipairs(mission.participantIDs or {}) do
			if GetPlayerID(member) == playerID and IsValidUnit(member) then table.insert(units, member) break end
		end
	end
	return units
end

local function AllAssembled(mission)
	local units = GetParticipants(mission)
	if #units < (mission.requiredCount or 2) then return false end
	local smokeOwner = nil
	if mission.requiresSmoke == true then
		for _, unit in ipairs(units) do
			if GetPlayerID(unit) == mission.smokeOwnerID then smokeOwner = unit break end
		end
		if smokeOwner == nil then return false end
	end
	for _, unit in ipairs(units) do
		local playerID = GetPlayerID(unit)
		if mission.joinedParticipantIDs == nil or mission.joinedParticipantIDs[playerID] ~= true then
			return false
		end
		if LocationDistance(unit, mission.stagingLocation) > Config.PICKOFF_ASSEMBLE_RADIUS then return false end
		if smokeOwner ~= nil
			and LocationDistance(unit, smokeOwner) > Config.SMOKE_APPLICATION_RADIUS - 50
		then
			return false
		end
	end
	return true
end

local function GetParticipantByID(mission, playerID)
	for _, unit in ipairs(GetParticipants(mission)) do
		if GetPlayerID(unit) == playerID then return unit end
	end
	return nil
end

local function HasSmoke(unit)
	return unit ~= nil and unit.HasModifier ~= nil
		and Safe(false, function() return unit:HasModifier('modifier_smoke_of_deceit') end)
end

local function AcquireTarget(bot, mission)
	local expectedEntityIndex = mission.kind == 'pickoff' and mission.targetEntityIndex or nil
	-- 先解除旧引用；重取失败时只能沿最后位置移动，绝不能把死亡实体继续交给原生动作。
	mission.target = nil
	if mission.kind == 'smoke_patrol' then mission.targetEntityIndex = nil end
	local best = nil
	for _, enemy in ipairs(GetVisibleEnemies(bot)) do
		local matchesPlayer = mission.kind == 'pickoff' and GetPlayerID(enemy) == mission.targetPlayerID
		local patrolCandidate = mission.kind == 'smoke_patrol'
			and LocationDistance(enemy, mission.rallyLocation) <= Config.PICKOFF_REVALIDATE_RADIUS
		if matchesPlayer or patrolCandidate then
			if best == nil or GetHealthFraction(enemy) < GetHealthFraction(best) then best = enemy end
		end
	end
	if best ~= nil then
		local entityIndex = GetEntityIndex(best)
		if expectedEntityIndex ~= nil and entityIndex ~= expectedEntityIndex then
			return nil, 'target_replaced'
		end
		mission.target = best
		mission.targetPlayerID = GetPlayerID(best)
		mission.targetEntityIndex = entityIndex
		mission.targetHeroName = GetUnitName(best)
		mission.lastLocation = GetLocation(best)
		mission.rallyLocation = mission.lastLocation
	end
	return best, nil
end

local function ValidateVisibleFight(bot, mission)
	if not CanInspect(mission.target) then return false, 'target_not_visible' end
	local targetLocation = GetLocation(mission.target)
	local enemyCount = 0
	local enemyPower = 0
	for _, enemy in ipairs(GetVisibleEnemies(bot)) do
		if LocationDistance(enemy, targetLocation) <= Config.PICKOFF_GROUP_RADIUS then
			local defense = CombatPower.GetDefenseSnapshot(enemy)
			local attack = CombatPower.GetAttackSnapshot(enemy)
			enemyCount = enemyCount + 1
			enemyPower = enemyPower + GetEnemyPower({
				health = defense ~= nil and defense.health or nil,
				maxHealth = defense ~= nil and defense.maxHealth or nil,
				level = Safe(nil, function() return enemy:GetLevel() end),
				attackDamage = attack ~= nil and attack.attackDamage or nil,
				attackPeriod = attack ~= nil and attack.attackPeriod or nil,
			})
		end
	end
	local participants = {}
	local allyPower = 0
	for _, unit in ipairs(GetParticipants(mission)) do
		if LocationDistance(unit, targetLocation) <= Config.PICKOFF_GROUP_RADIUS then
			table.insert(participants, {unit = unit})
			allyPower = allyPower + GetAllyPower(unit)
		end
	end
	if enemyCount < 1 or enemyCount > Config.PICKOFF_MAX_ENEMIES then return false, 'enemy_count_changed' end
	if #participants < enemyCount + 1 then return false, 'numbers_lost' end
	local ratio = enemyPower > 0 and allyPower / enemyPower or 2
	local requiredRatio = enemyCount == 1 and Config.PICKOFF_SINGLE_POWER_RATIO or Config.PICKOFF_PAIR_POWER_RATIO
	if (mission.unknownEnemyCount or 0) > 0 then requiredRatio = requiredRatio + Config.PICKOFF_UNKNOWN_POWER_BONUS end
	if ratio < requiredRatio then return false, 'power_changed' end
	local limit = enemyCount == 1 and Config.PICKOFF_SINGLE_KILL_TIME or Config.PICKOFF_PAIR_FIRST_KILL_TIME
	if (mission.unknownEnemyCount or 0) > 0 then limit = limit - Config.PICKOFF_UNKNOWN_KILL_TIME_PENALTY end
	local defense = CombatPower.GetDefenseSnapshot(mission.target)
	local observation = {
		handle = mission.target,
		health = defense ~= nil and defense.health or nil,
		maxHealth = defense ~= nil and defense.maxHealth or nil,
		defense = defense,
	}
	local _, predicted = EstimateDamage(participants, observation, limit)
	if predicted > limit then return false, 'kill_window_changed' end
	mission.enemyCount = enemyCount
	mission.allyCount = #participants
	mission.powerRatio = ratio
	mission.predictedKillTime = predicted
	return true
end

local function GetAssembleWindow(mission)
	local latestStagingArrival = 0
	if mission ~= nil then
		latestStagingArrival = tonumber(mission.latestStagingArrival) or 0
		for _, plan in pairs(mission.travelPlans or {}) do
			if type(plan) == 'table' then
				local stagingTime = tonumber(plan.stagingTravelTime)
				if stagingTime ~= nil then latestStagingArrival = math.max(latestStagingArrival, stagingTime) end
			end
		end
	end
	-- 集合窗口按参与者走到集合点的行程提前排期，并保留固定的最短窗口。
	return math.max(Config.PICKOFF_ASSEMBLE_TIMEOUT,
		latestStagingArrival + Config.PICKOFF_ASSEMBLE_TRAVEL_BUFFER), latestStagingArrival
end

function Pickoff.GetAssembleWindow(mission)
	return GetAssembleWindow(mission)
end

function Pickoff.UpdateMission(bot, mission)
	local now = Now()
	if mission.requiresSmoke == true and Config.SMOKE_ENABLED ~= true then
		return nil, 'smoke_disabled'
	end
	if mission.kind == 'smoke_patrol'
		and mission.smokeConfirmedTime ~= nil
		and mission.patrolCooldownRecorded ~= true
	then
		local team = Safe(GetTeam(), function() return mission.leader:GetTeam() end)
		lastPatrolStart[team] = mission.smokeConfirmedTime
		mission.patrolCooldownRecorded = true
	end
	if now - (mission.startTime or now) >= Config.PICKOFF_TOTAL_TIMEOUT then return nil, 'pickoff_total_timeout' end
	if mission.kind == 'pickoff' and mission.targetPlayerID ~= nil and mission.targetPlayerID >= 0 then
		local selectedHeroName = Safe(nil, function() return GetSelectedHeroName(mission.targetPlayerID) end)
		if mission.targetHeroName ~= nil and selectedHeroName ~= nil
			and selectedHeroName ~= mission.targetHeroName
		then
			mission.target = nil
			return nil, 'target_replaced'
		end
		-- 玩家级存活状态不依赖旧单位 handle；目标死亡时先释放任务，再做任何实体读取。
		if Safe(false, function() return IsHeroAlive(mission.targetPlayerID) end) ~= true then
			mission.target = nil
			return nil, 'target_dead'
		end
	end
	if mission.target ~= nil and not Pickoff.IsMissionTargetValid(bot, mission, mission.target) then
		mission.target = nil
	end
	if mission.target == nil then
		local _, acquireReason = AcquireTarget(bot, mission)
		if acquireReason ~= nil then return nil, acquireReason end
	end

	if mission.phase == 'assemble' then
		if mission.requiresSmoke == true then
			local owner = GetParticipantByID(mission, mission.smokeOwnerID)
			if owner == nil or Consumables.FindItem(owner, 'item_smoke_of_deceit') == nil then
				return nil, 'smoke_owner_lost'
			end
		end
		if AllAssembled(mission) then
			mission.phase = mission.requiresSmoke and 'conceal' or 'approach'
			mission.phaseStartTime = now
		elseif now - (mission.phaseStartTime or mission.startTime or now) >= GetAssembleWindow(mission) then
			return nil, 'assemble_timeout'
		end
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end

	if mission.phase == 'conceal' then
		if mission.smokeCastFailed == true then return nil, 'smoke_cast_unconfirmed' end
		local smokeObserved = false
		for _, unit in ipairs(GetParticipants(mission)) do
			if HasSmoke(unit) then smokeObserved = true break end
		end
		if smokeObserved or mission.smokeConfirmedTime ~= nil then
			mission.phase = 'approach'
			mission.phaseStartTime = now
		elseif now - (mission.phaseStartTime or now) >= Config.PICKOFF_CONCEAL_TIMEOUT then
			return nil, 'conceal_timeout'
		end
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end

	if mission.target ~= nil and CanInspect(mission.target) then
		mission.lastVisibleTime = now
		mission.lastLocation = GetLocation(mission.target)
		mission.rallyLocation = mission.lastLocation
	end

	if mission.phase == 'approach' then
		if mission.target ~= nil and CanInspect(mission.target)
			and LocationDistance(bot, mission.target) <= Config.ENGAGE_DISTANCE
		then
			local valid, reason = ValidateVisibleFight(bot, mission)
			if not valid then return nil, reason end
			mission.phase = 'engage'
			mission.engageStartTime = now
			mission.phaseStartTime = now
		elseif LocationDistance(bot, mission.rallyLocation) <= 600 and not CanInspect(mission.target) then
			mission.phase = 'ambush'
			mission.phaseStartTime = now
		elseif now - (mission.phaseStartTime or now) >= Config.PICKOFF_APPROACH_TIMEOUT then
			return nil, 'pickoff_approach_timeout'
		end
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end

	if mission.phase == 'ambush' then
		if mission.target ~= nil and CanInspect(mission.target) then
			local valid, reason = ValidateVisibleFight(bot, mission)
			if not valid then return nil, reason end
			mission.phase = 'engage'
			mission.engageStartTime = now
			mission.phaseStartTime = now
		elseif now - (mission.phaseStartTime or now) >= Config.PICKOFF_AMBUSH_TIMEOUT then
			return nil, 'ambush_timeout'
		end
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end

	if mission.phase == 'engage' then
		local valid, reason = ValidateVisibleFight(bot, mission)
		if not valid then return nil, reason end
		if now - (mission.engageStartTime or now) >= Config.PICKOFF_ENGAGE_TIMEOUT then
			return nil, 'pickoff_engage_timeout'
		end
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end
	return nil, 'invalid_pickoff_phase'
end

function Pickoff.NoteMissionStart(mission)
	-- 任务开始不消耗巡逻冷却；只有烟的施放被确认后才进入冷却。
	if mission ~= nil and mission.kind == 'smoke_patrol' then mission.patrolStartedTime = Now() end
end

function Pickoff.GetInvisibilityRegistry()
	return INVISIBILITY_HEROES
end

function Pickoff.ResetBotState(bot)
	local playerID = GetPlayerID(bot)
	if playerID < 0 then return end
	observations[playerID] = nil
	observationUpdateTimes[playerID] = nil
	visibleEnemies[playerID] = nil
	visibleEnemyUpdateTimes[playerID] = nil
end

function Pickoff.ResetForTests()
	observations = {}
	observationUpdateTimes = {}
	visibleEnemies = {}
	visibleEnemyUpdateTimes = {}
	lastPatrolStart = {}
	cachedGates = nil
	cachedNeutralZones = nil
end

return Pickoff
