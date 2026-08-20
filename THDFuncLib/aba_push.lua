local Push = {}
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')
local CombatPower = require(GetScriptDirectory()..'/THDFuncLib/combat_power')



local BOT_MODE_DESIRE_EXTRA_LOW = 0.02
local PUSH_SNAPSHOT_CACHE_INTERVAL = 0.75
local PUSH_LANE_STICKY_SECONDS = 3.0
local PUSH_HIGH_GROUND_TARGET_CACHE_INTERVAL = 0.75
local PUSH_ALIVE_ENEMY_ADVANTAGE_TOLERANCE = 1
local PUSH_MIN_LOCAL_ALLIES_WHEN_OUTNUMBERED = 2
local PUSH_OUTNUMBERED_MAX_DESIRE = 0.72
local PUSH_BASE_DEFENSE_MAX_DESIRE = 0.55
local PUSH_RECENT_ENEMY_MAX_DESIRE = 0.72
local PUSH_MISSING_ENEMY_MAX_DESIRE = 0.68
local PUSH_LOCAL_HERO_RESPONSE_RANGE = 1600
local PUSH_OBJECTIVE_SNAPSHOT_RANGE = 2000
local PUSH_BASE_EMERGENCY_RANGE = 1800
local PUSH_LAST_SEEN_MAX_AGE = 3.0
local PUSH_LOCAL_HERO_RETREAT_OFFSET = -1200
local PUSH_ENEMY_PRESSURE_SCORE_PER_HERO = 0.18
local PUSH_LANE_SWITCH_IMPROVEMENT_RATIO = 0.88
local LANE_MODE_DEBUG = false -- 验证期间输出三路推塔评分，确认后可关闭。


local function GetLaneName(lane)
    if lane == LANE_TOP then return 'TOP' end
    if lane == LANE_MID then return 'MID' end
    if lane == LANE_BOT then return 'BOT' end
    return tostring(lane)
end

function Push.GetStablePushLane(bot, lane)
    if bot == nil then return lane end

	local commitment = Wasteland.GetOuterTowerCommitment()
	if commitment ~= nil then
		bot.StablePushLane = commitment.lane
		bot.StablePushLaneUntil = GameTime() + PUSH_LANE_STICKY_SECONDS
		return commitment.lane
	end
	local conversion = Wasteland.GetConversionOpportunity()
	if conversion ~= nil and conversion.lane ~= nil then
		commitment = Wasteland.TryCreateOuterTowerCommitment(bot, conversion.lane, Wasteland.GetState())
		if commitment ~= nil then
			bot.StablePushLane = commitment.lane
			bot.StablePushLaneUntil = GameTime() + PUSH_LANE_STICKY_SECONDS
			return commitment.lane
		end
	end

    local now = GameTime()
    if bot.StablePushLane ~= nil
    and bot.StablePushLaneUntil ~= nil
    and now < bot.StablePushLaneUntil
    then
        return bot.StablePushLane
    end

    local selectedLane = Push.WhichLaneToPush(bot, lane)
    -- 活动模式不再无限续锁；固定窗口到期后重新比较三路，再决定是否继续原路线。
    bot.StablePushLane = selectedLane
    bot.StablePushLaneUntil = now + PUSH_LANE_STICKY_SECONDS
    return selectedLane
end

function Push.SelectLaneByScores(bot, topLaneScore, midLaneScore, botLaneScore)
    local selectedLane = LANE_MID
    local selectionReason = 'tie_mid'
    if topLaneScore < midLaneScore and topLaneScore < botLaneScore then
        selectedLane = LANE_TOP
        selectionReason = 'lowest_score'
    elseif midLaneScore < topLaneScore and midLaneScore < botLaneScore then
        selectedLane = LANE_MID
        selectionReason = 'lowest_score'
    elseif botLaneScore < topLaneScore and botLaneScore < midLaneScore then
        selectedLane = LANE_BOT
        selectionReason = 'lowest_score'
    end

    local laneScores = {
        [LANE_TOP] = topLaneScore,
        [LANE_MID] = midLaneScore,
        [LANE_BOT] = botLaneScore,
    }
    local previousLane = bot ~= nil and bot.StablePushLane or nil
    if previousLane ~= nil
    and selectedLane ~= previousLane
    and laneScores[selectedLane] > laneScores[previousLane] * PUSH_LANE_SWITCH_IMPROVEMENT_RATIO
    then
        selectedLane = previousLane
        selectionReason = 'hysteresis'
    end

    return selectedLane, selectionReason
end

function Push.GetPushDesire(bot, lane)
	-- 安全门不缓存；模式缓存窗口内发生撤退、基地告急或高地门槛变化时必须立即生效。
	if bot == nil
	or J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
	or J.CanNotUseAction(bot)
	or J.IsDoingRoshan(bot)
	then
		return BOT_MODE_DESIRE_NONE
	end

	local laneBuildingTier = Push.GetLaneBuildingTier(lane)
	local objective = Push.GetLaneBuildingTarget(lane) or GetAncient(GetOpposingTeam())
	if not Push.IsObjectiveValid(objective) then return BOT_MODE_DESIRE_NONE end
	if Wasteland.ShouldHoldHighGround(laneBuildingTier, Wasteland.GetStrictTeamAverageLevel()) then
		return BOT_MODE_DESIRE_NONE
	end

	local stablePushLane = Push.GetStablePushLane(bot, lane)
	if stablePushLane ~= lane then return BOT_MODE_DESIRE_NONE end

	local objectiveLocation = Push.GetObjectiveLocation(lane, objective)
	local snapshotKey = 'PushSnapshot-' .. Push.GetObjectiveKey(objective)
	local snapshot = Timer.GetOrCompute(
		Timer.GetBotLaneKey(snapshotKey, bot, lane),
		PUSH_SNAPSHOT_CACHE_INTERVAL,
		function()
			return Push.BuildPushSnapshot(bot, lane, objective, objectiveLocation, laneBuildingTier)
		end
	)
	local immediateSafety = Push.GetImmediateSafetyState(bot)
	return Push.ComputePushDesire(bot, lane, snapshot, immediateSafety)
end

function Push.IsObjectiveValid(objective)
	if objective == nil then return false end
	if objective.IsNull ~= nil and objective:IsNull() then return false end
	if objective.IsAlive ~= nil and not objective:IsAlive() then return false end
	return true
end

function Push.GetObjectiveKey(objective)
	if objective ~= nil and objective.entindex ~= nil then
		local index = objective:entindex()
		if index ~= nil then return tostring(index) end
	end
	return tostring(objective)
end

function Push.GetObjectiveLocation(lane, objective)
	if Push.IsObjectiveValid(objective) and objective.GetLocation ~= nil then
		return objective:GetLocation()
	end
	return GetLaneFrontLocation(GetTeam(), lane, 0)
end

local function CountVisibleCreepsNearLocation(listType, location, radius)
	if listType == nil then return 0 end
	local count = 0
	for _, creep in pairs(GetUnitList(listType)) do
		local visibleHealth = J.Utils.GetVisibleHealth(creep)
		if visibleHealth ~= nil and GetUnitToLocationDistance(creep, location) <= radius then
			count = count + 1
		end
	end
	return count
end

local function GetClosestVisibleCreepDistance(listType, location, radius)
	if listType == nil or location == nil then return nil end
	local closestDistance = nil
	for _, creep in pairs(GetUnitList(listType)) do
		local visibleHealth = J.Utils.GetVisibleHealth(creep)
		if visibleHealth ~= nil then
			local distance = GetUnitToLocationDistance(creep, location)
			if distance <= radius and (closestDistance == nil or distance < closestDistance) then
				closestDistance = distance
			end
		end
	end
	return closestDistance
end

local function SumLocalCombatPower(units)
	local total = 0
	for _, unit in pairs(units or {}) do
		total = total + CombatPower.Estimate(unit)
	end
	return total
end

function Push.GetImmediateSafetyState(bot)
	local ancient = GetAncient(GetTeam())
	if ancient == nil then return {baseEmergency = true} end
	local location = ancient:GetLocation()
	local enemyHeroPressure = J.CountLastSeenEnemiesNearLoc(location, PUSH_BASE_EMERGENCY_RANGE, PUSH_LAST_SEEN_MAX_AGE)
	local enemyTpPressure = #J.Utils.GetEnemyIdsInTpToLocation(location, PUSH_BASE_EMERGENCY_RANGE)
	local effectiveAllies = #J.GetAlliesNearLoc(location, 4500)
		+ #J.Utils.GetAllyIdsInTpToLocation(location, 4500)
	return {
		baseEmergency = enemyHeroPressure + enemyTpPressure > 0 and effectiveAllies < 1,
		baseEnemyPressure = enemyHeroPressure + enemyTpPressure,
		effectiveBaseAllies = effectiveAllies,
	}
end

function Push.BuildPushSnapshot(bot, lane, objective, objectiveLocation, laneBuildingTier)
	local allies = J.GetAlliesNearLoc(objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE)
	local enemies = J.GetEnemiesNearLoc(objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE)
	local allyPower = SumLocalCombatPower(allies)
	local enemyPower = SumLocalCombatPower(enemies)
	local teamMinLevel = math.huge
	for i = 1, #GetTeamPlayers(GetTeam()) do
		local member = GetTeamMember(i)
		if member ~= nil then teamMinLevel = math.min(teamMinLevel, member:GetLevel()) end
	end
	if teamMinLevel == math.huge then teamMinLevel = 0 end
	local wastelandState = Wasteland.IsEnabled() and Wasteland.GetState() or nil
	if wastelandState ~= nil then
		Wasteland.ObserveOuterTowerSnapshot(bot, wastelandState)
		if wastelandState.outerCommitment == nil then
			wastelandState.outerCommitment = Wasteland.TryCreatePushObjective(
				bot,
				lane,
				wastelandState,
				objective,
				laneBuildingTier
			)
			wastelandState.objective = wastelandState.outerCommitment
		end
	end
	return {
		objective = objective,
		objectiveLocation = objectiveLocation,
		laneBuildingTier = laneBuildingTier,
		allyCount = #allies,
		enemyCount = #enemies,
		allyPower = allyPower,
		enemyPower = enemyPower,
		localPowerAdvantage = #enemies == 0
			or (#allies >= #enemies and allyPower > 0 and enemyPower > 0 and allyPower >= enemyPower),
		recentEnemyCount = J.CountLastSeenEnemiesNearLoc(
			objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE, PUSH_LAST_SEEN_MAX_AGE),
		enemyTpCount = #J.Utils.GetEnemyIdsInTpToLocation(objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE),
		missingEnemyCount = J.Utils.CountMissingEnemyHeroes(),
		allyCreepCount = CountVisibleCreepsNearLocation(
			UNIT_LIST_ALLIED_CREEPS, objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE),
		enemyCreepCount = CountVisibleCreepsNearLocation(
			UNIT_LIST_ENEMY_CREEPS, objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE),
		allyAlive = J.GetNumOfAliveHeroes(false),
		enemyAlive = J.GetNumOfAliveHeroes(true),
		allyAverageLevel = J.GetAverageLevel(false),
		enemyAverageLevel = J.GetAverageLevel(true),
		allyKills = J.GetNumOfTeamTotalKills(false) + 1,
		enemyKills = J.GetNumOfTeamTotalKills(true) + 1,
		teamMinLevel = teamMinLevel,
		baseLaneDesire = GetPushLaneDesire(lane),
		doesTeamHaveAegis = J.DoesTeamHaveAegis(),
		ancientDefenseState = J.GetAncientDefenseState(4500),
		shouldWaitForImportantItems = Push.ShouldWaitForImportantItemsSpells(
			GetLaneFrontLocation(GetOpposingTeam(), lane, 0)),
		wastelandState = wastelandState,
	}
end

function Push.ComputePushDesire(bot, lane, snapshot, immediateSafety)
	if bot == nil
	or J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
	or J.CanNotUseAction(bot)
	or J.IsDoingRoshan(bot)
	then
		return BOT_MODE_DESIRE_NONE
	end
	if snapshot == nil then
		local objective = Push.GetLaneBuildingTarget(lane) or GetAncient(GetOpposingTeam())
		snapshot = Push.BuildPushSnapshot(
			bot,
			lane,
			objective,
			Push.GetObjectiveLocation(lane, objective),
			Push.GetLaneBuildingTier(lane)
		)
	end
	immediateSafety = immediateSafety or Push.GetImmediateSafetyState(bot)
	local ancientDefenseState = snapshot.ancientDefenseState or {}
	local baseDefenseRequired = (immediateSafety.baseEnemyPressure or 0) > 0
		or (ancientDefenseState.enemyPressure or 0) > 0
	Wasteland.InvalidateObjectiveForBaseDefense(bot, baseDefenseRequired)
	if Wasteland.ShouldYieldPushObjective(bot, lane) then
		return BOT_MODE_DESIRE_EXTRA_LOW
	end

	if bot:GetAssignedLane() == LANE_MID and J.IsInLaningPhase() then
		return BOT_MODE_DESIRE_EXTRA_LOW
	end
	if snapshot.teamMinLevel < 7 then return BOT_MODE_DESIRE_EXTRA_LOW end
	if snapshot.enemyTpCount > 0 then return BOT_MODE_DESIRE_EXTRA_LOW end
	-- 守军出现时只在目标点人数与本地可见属性战力均不劣时继续推进。
	if snapshot.enemyCount > 0 and not snapshot.localPowerAdvantage then
		return BOT_MODE_DESIRE_EXTRA_LOW
	end

	local nMaxDesire = 0.9
	local nSafetyMaxDesire = 1.0
	local nModeDesire = bot:GetActiveModeDesire()
	if J.IsDefending(bot) and nModeDesire >= 0.8 then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, 0.75)
	end

	local aAliveCount = snapshot.allyAlive
	local eAliveCount = snapshot.enemyAlive
	local nPushDesire = snapshot.baseLaneDesire
	local teamKillsRatio = snapshot.allyKills / snapshot.enemyKills
	local canPushWithAliveNumbers = eAliveCount == 0
		or aAliveCount >= eAliveCount
		or (aAliveCount >= PUSH_MIN_LOCAL_ALLIES_WHEN_OUTNUMBERED
			and eAliveCount - aAliveCount <= PUSH_ALIVE_ENEMY_ADVANTAGE_TOLERANCE)

	if eAliveCount > aAliveCount then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, PUSH_OUTNUMBERED_MAX_DESIRE)
	end
	if snapshot.recentEnemyCount > snapshot.enemyCount then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, PUSH_RECENT_ENEMY_MAX_DESIRE)
	end
	if snapshot.missingEnemyCount >= 3 and snapshot.allyCount < 3 then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, PUSH_MISSING_ENEMY_MAX_DESIRE)
	end
	if snapshot.enemyCreepCount > snapshot.allyCreepCount + 2 then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, PUSH_OUTNUMBERED_MAX_DESIRE)
	elseif snapshot.allyCreepCount > snapshot.enemyCreepCount then
		nPushDesire = nPushDesire + 0.04
	end

	if immediateSafety.baseEmergency
	or ((ancientDefenseState.enemyPressure or 0) > 0
		and (ancientDefenseState.effectiveAllyCount or 0) < 1)
	then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, PUSH_BASE_DEFENSE_MAX_DESIRE)
	end
	if (ancientDefenseState.effectiveAllyCount or 0) >= 1 then
		nPushDesire = nPushDesire * 0.5
	end

	if snapshot.shouldWaitForImportantItems
	and eAliveCount > aAliveCount + PUSH_ALIVE_ENEMY_ADVANTAGE_TOLERANCE
	then
		return BOT_MODE_DESIRE_VERYLOW
	end

	local botTarget = bot:GetAttackTarget()
	if J.IsValidBuilding(botTarget)
	and not string.find(botTarget:GetUnitName(), 'tower1')
	and not string.find(botTarget:GetUnitName(), 'tower2')
	and Push.HasBackdoorProtect(botTarget)
	then
		return BOT_MODE_DESIRE_EXTRA_LOW
	end

	local enemyAncient = GetAncient(GetOpposingTeam())
	if Push.IsObjectiveValid(enemyAncient)
	and GetUnitToUnitDistance(bot, enemyAncient) < PUSH_OBJECTIVE_SNAPSHOT_RANGE * 0.8
	and J.CanBeAttacked(enemyAncient)
	and not bot:WasRecentlyDamagedByAnyHero(1)
	and J.GetHP(bot) > 0.5
	and not Push.HasBackdoorProtect(enemyAncient)
	then
		return Wasteland.AdjustPushDesire(
			BOT_ACTION_DESIRE_ABSOLUTE * 0.98,
			snapshot.laneBuildingTier,
			snapshot.wastelandState,
			lane,
			nSafetyMaxDesire,
			bot
		)
	end

	if canPushWithAliveNumbers then
		if snapshot.doesTeamHaveAegis then nPushDesire = nPushDesire + 0.3 end
		local aliveLead = aAliveCount - eAliveCount
		if aliveLead > 0 then nPushDesire = nPushDesire + math.min(0.18, aliveLead * 0.12) end
		if snapshot.localPowerAdvantage and snapshot.enemyCount > 0 then
			nPushDesire = nPushDesire + 0.08
		end
		local levelLead = snapshot.allyAverageLevel - snapshot.enemyAverageLevel
		if levelLead >= 1 then nPushDesire = nPushDesire + math.min(0.12, levelLead * 0.04) end
		if teamKillsRatio >= 1.25 then nPushDesire = nPushDesire + 0.05 end
		local desire = RemapValClamped(nPushDesire, 0, 1, 0, nMaxDesire)
		return Wasteland.AdjustPushDesire(
			desire,
			snapshot.laneBuildingTier,
			snapshot.wastelandState,
			lane,
			nSafetyMaxDesire,
			bot
		)
	end

	return lane == LANE_MID and BOT_MODE_DESIRE_VERYLOW or BOT_MODE_DESIRE_EXTRA_LOW
end

function Push.WhichLaneToPush(bot, lane)
	local commitment = Wasteland.GetOuterTowerCommitment()
	if commitment ~= nil then return commitment.lane end

    local cacheKey = 'PushWhichLaneToPush-'..tostring(GetTeam())
    local cachedLane = J.Utils.GetCachedVars(cacheKey, PUSH_SNAPSHOT_CACHE_INTERVAL)
    if cachedLane ~= nil then
        return cachedLane
    end

    -- the smaller the higher desire
    local topLaneScore = 0
    local midLaneScore = 0
    local botLaneScore = 0

    local vLaneFrontLocationTop = GetLaneFrontLocation(GetTeam(), LANE_TOP, 0)
    local vLaneFrontLocationMid = GetLaneFrontLocation(GetTeam(), LANE_MID, 0)
    local vLaneFrontLocationBot = GetLaneFrontLocation(GetTeam(), LANE_BOT, 0)

    -- distance and enemy scores; should more likely to consider a lane closest to a human/core
    local members = GetTeamPlayers(GetTeam())
    for i = 1, #members do
        local member = GetTeamMember(i)
        if J.IsValidHero(member) then
            local topDist = GetUnitToLocationDistance(member, vLaneFrontLocationTop)
            local midDist = GetUnitToLocationDistance(member, vLaneFrontLocationMid)
            local botDist = GetUnitToLocationDistance(member, vLaneFrontLocationBot)

            topLaneScore = topLaneScore + topDist
            midLaneScore = midLaneScore + midDist
            botLaneScore = botLaneScore + botDist
        end
    end

    local count1 = 0
    local count2 = 0
    local count3 = 0
    for _, id in pairs( GetTeamPlayers(GetOpposingTeam())) do
        if IsHeroAlive(id) then
            local info = GetHeroLastSeenInfo(id)
            if info ~= nil then
                local dInfo = info[1]
                if dInfo ~= nil
                and type(dInfo.time_since_seen) == 'number'
                and dInfo.time_since_seen <= PUSH_LAST_SEEN_MAX_AGE
                then
                    if J.GetDistance(vLaneFrontLocationTop, dInfo.location) <= 1600 then
                        count1 = count1 + 1
                    elseif J.GetDistance(vLaneFrontLocationMid, dInfo.location) <= 1600 then
                        count2 = count2 + 1
                    elseif J.GetDistance(vLaneFrontLocationBot, dInfo.location) <= 1600 then
                        count3 = count3 + 1
                    end
                end
            end
        end
    end

    local hTeleports = GetIncomingTeleports()
    for _, tp in pairs(hTeleports) do
        if tp ~= nil and Push.IsEnemyTP(tp.playerid) then
            if     J.GetDistance(vLaneFrontLocationTop, tp.location) <= 1600 then
                count1 = count1 + 1
            elseif J.GetDistance(vLaneFrontLocationMid, tp.location) <= 1600 then
                count2 = count2 + 1
            elseif J.GetDistance(vLaneFrontLocationBot, tp.location) <= 1600 then
                count3 = count3 + 1
            end
        end
    end

    topLaneScore = topLaneScore * (PUSH_ENEMY_PRESSURE_SCORE_PER_HERO * count1 + 1)
    midLaneScore = midLaneScore * (PUSH_ENEMY_PRESSURE_SCORE_PER_HERO * count2 + 1)
    botLaneScore = botLaneScore * (PUSH_ENEMY_PRESSURE_SCORE_PER_HERO * count3 + 1)

    -- tower scores; should more likely consider taking out outer tower first, ^ unless overwhelmingly closer (case above)
    local topLaneTier = Push.GetLaneBuildingTier(LANE_TOP)
    local midLaneTier = Push.GetLaneBuildingTier(LANE_MID)
    local botLaneTier = Push.GetLaneBuildingTier(LANE_BOT)

    -- slight, not too strong; start mid first
    if midLaneTier < topLaneTier and midLaneTier < botLaneTier then
        midLaneScore = midLaneScore * 0.5
        if not J.Utils.IsAnyBarracksOnLaneAlive(false, LANE_MID) then midLaneScore = midLaneScore * 0.5 end
    elseif topLaneTier < midLaneTier and topLaneTier < botLaneTier then
        topLaneScore = topLaneScore * 0.5
        if not J.Utils.IsAnyBarracksOnLaneAlive(false, LANE_TOP) then topLaneScore = topLaneScore * 0.5 end
    elseif botLaneTier < topLaneTier and botLaneTier < midLaneTier then
        botLaneScore = botLaneScore * 0.5
        if not J.Utils.IsAnyBarracksOnLaneAlive(false, LANE_BOT) then botLaneScore = botLaneScore * 0.5 end
    end

    local selectedLane, selectionReason = Push.SelectLaneByScores(bot, topLaneScore, midLaneScore, botLaneScore)
    J.Utils.SetCachedVars(cacheKey, selectedLane)
    if LANE_MODE_DEBUG or J.Utils.DebugMode then
        print(string.format(
            '[BOT][LaneMode][Push] time=%.1f team=%s pid=%s previous=%s selected=%s reason=%s score=%.0f/%.0f/%.0f pressure=%d/%d/%d tier=%d/%d/%d',
            GameTime(),
            tostring(GetTeam()),
            tostring(bot:GetPlayerID()),
            bot.StablePushLane ~= nil and GetLaneName(bot.StablePushLane) or 'NONE',
            GetLaneName(selectedLane),
            selectionReason,
            topLaneScore,
            midLaneScore,
            botLaneScore,
            count1,
            count2,
            count3,
            topLaneTier,
            midLaneTier,
            botLaneTier
        ))
    end
    return selectedLane
end

local function GetLaneBuildingIDs(lane)
    if lane == LANE_TOP then
        return TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3, BARRACKS_TOP_MELEE, BARRACKS_TOP_RANGED
    elseif lane == LANE_MID then
        return TOWER_MID_1, TOWER_MID_2, TOWER_MID_3, BARRACKS_MID_MELEE, BARRACKS_MID_RANGED
    elseif lane == LANE_BOT then
        return TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3, BARRACKS_BOT_MELEE, BARRACKS_BOT_RANGED
    end
end

function Push.GetLaneBuildingTarget(lane)
    local tower1ID, tower2ID, tower3ID, meleeBarracksID, rangedBarracksID = GetLaneBuildingIDs(lane)
    if tower1ID == nil then return nil end

    local enemyTeam = GetOpposingTeam()
    return GetTower(enemyTeam, tower1ID)
        or GetTower(enemyTeam, tower2ID)
        or GetTower(enemyTeam, tower3ID)
        or GetBarracks(enemyTeam, meleeBarracksID)
        or GetBarracks(enemyTeam, rangedBarracksID)
end

function Push.GetLaneBarracks(lane)
    local _, _, _, meleeBarracksID, rangedBarracksID = GetLaneBuildingIDs(lane)
    if meleeBarracksID == nil then return nil, nil end

    local enemyTeam = GetOpposingTeam()
    return GetBarracks(enemyTeam, meleeBarracksID), GetBarracks(enemyTeam, rangedBarracksID)
end

function Push.TryAttackLaneBarracks(bot, lane)
    local _, _, tower3ID = GetLaneBuildingIDs(lane)
    if tower3ID == nil or GetTower(GetOpposingTeam(), tower3ID) ~= nil then return false end

    local meleeBarracks, rangedBarracks = Push.GetLaneBarracks(lane)
    local candidates = {
        { unit = meleeBarracks, sticky = 'push_melee_barrack_'..tostring(lane), action = 'push_attack_melee_barrack' },
        { unit = rangedBarracks, sticky = 'push_range_barrack_'..tostring(lane), action = 'push_attack_range_barrack' },
    }

    -- T3 拆除后锁定当前路兵营，避免全局防偷塔状态把 Bot 长期留在高地边界。
    for _, candidate in ipairs(candidates) do
        local barracks = candidate.unit
        if J.IsValidBuilding(barracks)
        and J.CanBeAttacked(barracks)
        and not Push.HasBackdoorProtect(barracks)
        then
            barracks = J.GetStickyTarget(bot, candidate.sticky, barracks, 1.8, 2200)
            if barracks ~= nil
            and J.ActionAttackUnit(bot, candidate.action, barracks, true, 0.45)
            then
                return true
            end
        end
    end

    return false
end

function Push.GetVisibleNearbyEnemyHeroes(bot, candidates, radius)
	local enemies = {}
	radius = radius or PUSH_LOCAL_HERO_RESPONSE_RANGE
	for _, enemy in pairs(candidates or {}) do
		if J.IsValidHero(enemy)
		and J.CanBeAttacked(enemy)
		and enemy:GetTeam() ~= bot:GetTeam()
		and not J.IsSuspiciousIllusion(enemy)
		and GetUnitToUnitDistance(bot, enemy) <= radius
		then
			table.insert(enemies, enemy)
		end
	end
	return enemies
end

function Push.SelectNearbyEnemyHero(bot, enemies)
	local currentTarget = J.GetProperTarget(bot)
	local closestTarget = nil
	local closestDistance = math.huge
	for _, enemy in pairs(enemies or {}) do
		if enemy == currentTarget then return enemy end
		local distance = GetUnitToUnitDistance(bot, enemy)
		if distance < closestDistance then
			closestTarget = enemy
			closestDistance = distance
		end
	end
	return closestTarget
end

function Push.HandleNearbyEnemyHeroes(bot, lane, nearbyAllies, nearbyEnemies)
	if #nearbyEnemies == 0 then return false end

	if #nearbyAllies < #nearbyEnemies then
		-- 模式切换存在缓存窗口；人数劣势时当前帧先后撤，禁止继续攻击兵线或建筑。
		local retreatLocation = GetLaneFrontLocation(GetTeam(), lane, PUSH_LOCAL_HERO_RETREAT_OFFSET)
		J.ActionMoveToLocation(bot, 'push_yield_outnumbered_enemy_heroes', retreatLocation, 0.25, 220)
		return true
	end

	local target = Push.SelectNearbyEnemyHero(bot, nearbyEnemies)
	if target ~= nil then
		-- 人数不劣时先响应可见英雄；下一轮模式仲裁会让 ATTACK 接管技能与追击。
		J.SetTargetIfChanged(bot, target, 0.2)
		J.ActionAttackUnit(bot, 'push_answer_enemy_hero', target, true, 0.25)
		return true
	end

	return false
end

local fNextMovementTime = 0
function Push.PushThink(bot, lane)
    if not Timer.ShouldRunBotTask(bot, 'push_think_'..tostring(lane), 0.25, 0.03) then return end
	if J.CanNotUseAction(bot) then return end
	local hEnemyAncient = GetAncient(GetOpposingTeam())
	local immediateSafety = Push.GetImmediateSafetyState(bot)
	if Wasteland.InvalidateObjectiveForBaseDefense(
		bot,
		(immediateSafety.baseEnemyPressure or 0) > 0
	) then
		-- 基地出现防守压力时先释放统一目标；本帧不再沿用缓存中的推进模式下单。
		return
	end
	local pushObjective = Wasteland.GetPushObjective()
	if pushObjective ~= nil
	and pushObjective.lane == lane
	and not Wasteland.IsPushObjectiveParticipant(bot, pushObjective)
	then
		return
	end

	local retreatState = J.Retreat.GetState(bot)
	local conversionUnsafe, conversionReason = Wasteland.ShouldWithdrawConversionPush(
		bot, retreatState.towerThreat)
	if conversionUnsafe then
		-- gank 击杀转推塔时，不默认当前 Bot 继续吃塔伤；低血量或已被塔锁定都先退出。
		local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
		J.ActionMoveToLocation(bot, 'push_flee_conversion_' .. tostring(conversionReason or 'safety'), vLocation, 0.25, 260)
		return
	end
	if retreatState.severity >= J.Retreat.HIGH then
		-- 模式切换可能仍受缓存影响；塔风险期间先退出高地，禁止继续叠加伤害和攻速。
		if retreatState.towerThreat ~= nil and retreatState.towerThreat.active then
			local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
			J.ActionMoveToLocation(bot, 'push_flee_tower_threat', vLocation, 0.35, 260)
		end
		return
	end

	local nearbyAllies = J.GetAlliesNearLoc(bot:GetLocation(), PUSH_LOCAL_HERO_RESPONSE_RANGE)
	local nearbyEnemies = Push.GetVisibleNearbyEnemyHeroes(
		bot,
		J.GetNearbyHeroes(bot, PUSH_LOCAL_HERO_RESPONSE_RANGE, true, BOT_MODE_NONE),
		PUSH_LOCAL_HERO_RESPONSE_RANGE
	)
	if Push.HandleNearbyEnemyHeroes(bot, lane, nearbyAllies, nearbyEnemies) then return end

	local laneBuildingTier = Push.GetLaneBuildingTier(lane)
	if Wasteland.ShouldHoldHighGround(laneBuildingTier) then
		-- 欲望缓存或旧模式仍存活时也不允许继续攻击高地；已接近则退回兵线安全侧。
		if J.Utils.IsNearEnemyHighGroundTower(bot, 4200) then
			local waitLocation = GetLaneFrontLocation(GetTeam(), lane, -1800)
			J.ActionMoveToLocation(bot, 'wasteland_wait_high_ground_level', waitLocation, 0.35, 260)
		end
		return
	end

    local botAttackRange = bot:GetAttackRange()
    local fDeltaFromFront = (Min(J.GetHP(bot), 0.7) * 1000 - 700) + RemapValClamped(botAttackRange, 300, 700, 0, -600)
    local nEnemyTowers = bot:GetNearbyTowers(1600, true)
    local nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)

    local hLaneBuildingTarget = Push.GetLaneBuildingTarget(lane)
    local bLaneBuildingProtected = J.IsValidBuilding(hLaneBuildingTarget)
        and Push.HasBackdoorProtect(hLaneBuildingTarget)
	local observedTarget = pushObjective ~= nil and pushObjective.target or (hLaneBuildingTarget or hEnemyAncient)
	if pushObjective ~= nil and pushObjective.lane == lane and Push.IsObjectiveValid(observedTarget) then
		local objectiveLocation = Push.GetObjectiveLocation(lane, observedTarget)
		local targetHealth, targetMaxHealth = J.Utils.GetVisibleHealth(observedTarget)
		local botDistance = GetUnitToUnitDistance(bot, observedTarget)
		local attackableDistance = math.min(1600, botAttackRange + 400)
		pushObjective = Wasteland.ObservePushObjective(bot, lane, observedTarget, {
			botDistance = botDistance,
			allyCreepDistance = GetClosestVisibleCreepDistance(
				UNIT_LIST_ALLIED_CREEPS, objectiveLocation, 5000),
			targetHealth = targetHealth,
			targetMaxHealth = targetMaxHealth,
			backdoorProtected = J.IsValidBuilding(observedTarget)
				and Push.HasBackdoorProtect(observedTarget),
			attackable = J.IsValidBuilding(observedTarget)
				and J.CanBeAttacked(observedTarget)
				and botDistance <= attackableDistance,
		})
		if pushObjective == nil then return end
	end
	local objectiveRole = Wasteland.GetPushObjectiveRole(bot, pushObjective)
    if #nearbyAllies < #nearbyEnemies or bLaneBuildingProtected then
        local nEnemyHeroLongestAttackRange = 0
        for _, enemyHero in pairs(nearbyEnemies) do
            if J.IsValidHero(enemyHero)
            and not J.IsSuspiciousIllusion(enemyHero)
            then
                local enemyHeroAttackRange = enemyHero:GetAttackRange()
                if enemyHeroAttackRange > nEnemyHeroLongestAttackRange then
                    nEnemyHeroLongestAttackRange = enemyHeroAttackRange
                end
            end
        end

        fDeltaFromFront = -1000 - nEnemyHeroLongestAttackRange
    end

    local targetLoc = GetLaneFrontLocation(GetTeam(), lane, fDeltaFromFront)

    if J.IsValidBuilding(hLaneBuildingTarget)
    and Push.HasDefenseGlyphBuff(hLaneBuildingTarget)
    and #J.GetEnemiesNearLoc(hLaneBuildingTarget:GetLocation(), 1600) == 0
    then
        local vRetreatLocation = GetLaneFrontLocation(GetTeam(), lane, -1800)
        J.ActionMoveToLocation(bot, 'push_retreat_glyphed_tower', vRetreatLocation, 0.45, 260)
        return
    end

	local towerThreat = J.Retreat.GetTowerThreat(bot, 3.0)
	if towerThreat.active
	and not towerThreat.coveredHighGroundLock
	and (towerThreat.highGroundLock
		or towerThreat.unavoidableDamage >= bot:GetHealth()
		or towerThreat.predictedDamage / math.max(1, bot:GetHealth()) >= 0.25)
	then
		local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
		J.ActionMoveToLocation(bot, 'push_flee_tower', vLocation, 0.35, 260)
		return
	end

	-- 分工只改变动作优先级：建筑输出位进入 SIEGE 后先打统一目标，其他角色保留兵线/掩护顺序。
	if pushObjective ~= nil
	and pushObjective.phase == Wasteland.PHASE_SIEGE
	and objectiveRole == Wasteland.ROLE_BUILDING_DAMAGE
	and Push.IsObjectiveValid(observedTarget)
	and J.IsValidBuilding(observedTarget)
	and J.CanBeAttacked(observedTarget)
	and not Push.HasBackdoorProtect(observedTarget)
	and GetUnitToUnitDistance(bot, observedTarget) <= math.min(1600, botAttackRange + 400)
	then
		local buildingTarget = J.GetStickyTarget(
			bot, 'push_objective_building_damage', observedTarget, 1.8, botAttackRange + 500)
		if buildingTarget ~= nil then
			Wasteland.NoteOuterTowerAttack(bot, lane, buildingTarget)
			J.SetTargetIfChanged(bot, buildingTarget, 0.6)
			J.ActionAttackUnit(bot, 'push_objective_building_damage', buildingTarget, true, 0.45)
			return
		end
	end

	-- 欲望函数只决定优先级；远古目标与所有攻击指令统一在动作阶段下达。
	if Push.IsObjectiveValid(hEnemyAncient)
	and GetUnitToUnitDistance(bot, hEnemyAncient) < PUSH_OBJECTIVE_SNAPSHOT_RANGE * 0.8
	and J.CanBeAttacked(hEnemyAncient)
	and not bot:WasRecentlyDamagedByAnyHero(1)
	and J.GetHP(bot) > 0.5
	and not Push.HasBackdoorProtect(hEnemyAncient)
	then
		J.SetTargetIfChanged(bot, hEnemyAncient, 0.6)
		J.ActionAttackUnit(bot, 'push_attack_enemy_ancient', hEnemyAncient, true, 0.45)
		return
	end

    if Push.TryAttackLaneBarracks(bot, lane) then return end

    if J.IsValidBuilding(hLaneBuildingTarget)
    and Push.HasBackdoorProtect(hLaneBuildingTarget)
    then
        local vWaitLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
        J.ActionMoveToLocation(bot, 'push_wait_for_creeps', vWaitLocation, 0.45, 220)
        return
    end

    if Push.IsObjectiveValid(hEnemyAncient)
    and GetUnitToUnitDistance(bot, hEnemyAncient) <= 3200
    and (   GetTower(GetOpposingTeam(), TOWER_TOP_2) == nil
        and GetTower(GetOpposingTeam(), TOWER_MID_2) == nil
        and GetTower(GetOpposingTeam(), TOWER_BOT_2) == nil)
    then
        local hBuildingTarget = TryClearingOtherLaneHighGround(bot, targetLoc)
        if hBuildingTarget then
            hBuildingTarget = J.GetStickyTarget(bot, 'push_clear_other_high_ground', hBuildingTarget, 1.5, 2200)
            J.ActionAttackUnit(bot, 'push_clear_other_high_ground', hBuildingTarget, true, 0.45)
            return
        end

    end

    local ancientAllies = Push.IsObjectiveValid(hEnemyAncient)
        and J.GetAlliesNearLoc(hEnemyAncient:GetLocation(), 1600)
        or {}
    if Push.IsObjectiveValid(hEnemyAncient)
    and GetUnitToUnitDistance(bot, hEnemyAncient) < 1600
    and J.CanBeAttacked(hEnemyAncient)
    and not Push.HasBackdoorProtect(hEnemyAncient)
    and (#Push.GetAllyHeroesAttackingUnit(hEnemyAncient) >= 3
        or #Push.GetAllyCreepsAttackingUnit(hEnemyAncient) >= 4
        or hEnemyAncient:GetHealthRegen() < 20
        or #ancientAllies >= 4)
    then
        J.ActionAttackUnit(bot, 'push_attack_enemy_ancient', hEnemyAncient, true, 0.45)
        return
    end


    local nRange = math.min(700 + botAttackRange, 1600)

    -- 原逻辑在 bot 12 级后会从 GetNearbyLaneCreeps 扩大到 GetNearbyCreeps，
    -- 目的是推进时顺手清理召唤物、支配怪、陈怪等非兵线单位。
    -- 但 THI/当前 Dota 环境里存在隐藏中立、特殊 creep、缓存池中立等大量非兵线单位，
    -- 这个 all-creeps 扫描会把它们纳入 push 目标评估，放大原生 bot/NextBotCombat 开销。
    -- 因此这里强制只扫描兵线小兵，避免后期/满级 bot 推进时扫描中立或特殊单位。
    local nCreeps = bot:GetNearbyLaneCreeps(nRange, true)

    local vTeamFountain = J.GetTeamFountain()
    local bTowerNearby = false
    if J.IsValidBuilding(nEnemyTowers[1]) then
        bTowerNearby = true
    end

    for _, creep in pairs(nCreeps) do
        if J.IsValid(creep)
        and J.CanBeAttacked(creep)
        and (not bTowerNearby
            or (bTowerNearby and GetUnitToLocationDistance(creep, vTeamFountain) < GetUnitToLocationDistance(nEnemyTowers[1], vTeamFountain)))
        and not J.IsRoshan(creep)
        then
            local targetCreep = J.GetStickyTarget(bot, 'push_creep', creep, 1.0, nRange + 300)
            J.ActionAttackUnit(bot, 'push_attack_creep', targetCreep, true, 0.35)
            return

        end
    end

    if J.IsValidBuilding(nEnemyTowers[1]) and J.CanBeAttacked(nEnemyTowers[1]) and not Push.HasBackdoorProtect(nEnemyTowers[1]) then
        local hTowerTarget = nil
        local hTowerTargetDistance = math.huge
        for _, tower in pairs(nEnemyTowers) do
            if J.IsValidBuilding(tower) and J.CanBeAttacked(tower) and not Push.HasBackdoorProtect(tower) then
                local towerDistance = GetUnitToLocationDistance(tower, targetLoc)
                if towerDistance < hTowerTargetDistance then
                    hTowerTarget = tower
                    hTowerTargetDistance = towerDistance
                end
            end
        end

        if hTowerTarget then
            hTowerTarget = J.GetStickyTarget(bot, 'push_tower', hTowerTarget, 1.8, nRange + 300)
			Wasteland.NoteOuterTowerAttack(bot, lane, hTowerTarget)
            J.ActionAttackUnit(bot, 'push_attack_tower', hTowerTarget, true, 0.45)
            return

        end
    end

    local nEnemyFillers = bot:GetNearbyFillers(nRange, true)
    if J.IsValidBuilding(nEnemyFillers[1]) and J.CanBeAttacked(nEnemyFillers[1]) and not Push.HasBackdoorProtect(nEnemyFillers[1]) then
        local hTowerFillerTarget = nil
        local hTowerFillerTargetDistance = math.huge
        for _, filler in pairs(nEnemyFillers) do
            if J.CanBeAttacked(filler) and not Push.HasBackdoorProtect(filler) then
                local fillerTowerDistance = GetUnitToLocationDistance(filler, targetLoc)
                if fillerTowerDistance < hTowerFillerTargetDistance then
                    hTowerFillerTarget = filler
                    hTowerFillerTargetDistance = fillerTowerDistance
                end
            end
        end

        if hTowerFillerTarget then
            hTowerFillerTarget = J.GetStickyTarget(bot, 'push_filler', hTowerFillerTarget, 1.8, nRange + 300)
            J.ActionAttackUnit(bot, 'push_attack_filler', hTowerFillerTarget, true, 0.45)
            return

        end
    end

    if GetUnitToLocationDistance(bot, targetLoc) > 500 then
        J.ActionMoveToLocation(bot, 'push_move_lane_front', targetLoc, 0.5, 220)
        return

    else
        if DotaTime() >= fNextMovementTime then
            local attackMoveLoc = J.GetStableFormationLocation(bot, 'push_attack_move_lane_front', targetLoc, 320, 30.0)
            J.ActionAttackMove(bot, 'push_attack_move_lane_front', attackMoveLoc, 0.5, 260)
            fNextMovementTime = DotaTime() + 0.8
            return

        end
    end
end

function TryClearingOtherLaneHighGround(bot, vLocation)
    if vLocation == nil then return nil end

    local cacheKey = 'PushClearOtherHighGround-'..tostring(GetTeam())..'-'..Timer.RoundLocationKey(vLocation, 800)
    local cachedTarget = J.Utils.GetCachedOrCompute(cacheKey, PUSH_HIGH_GROUND_TARGET_CACHE_INTERVAL, function()
        local unitList = GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)
        local function IsValid(building)
            return J.IsValidBuilding(building)
                and J.CanBeAttacked(building)
                and not (Push.HasBackdoorProtect(building))
        end

        local hBarrackTarget = nil
        local hBarrackTargetDistance = math.huge
        for _, barrack in pairs(unitList) do
            if IsValid(barrack)
            and (  barrack == GetBarracks(GetOpposingTeam(), BARRACKS_TOP_MELEE)
                or barrack == GetBarracks(GetOpposingTeam(), BARRACKS_TOP_RANGED)
                or barrack == GetBarracks(GetOpposingTeam(), BARRACKS_MID_MELEE)
                or barrack == GetBarracks(GetOpposingTeam(), BARRACKS_MID_RANGED)
                or barrack == GetBarracks(GetOpposingTeam(), BARRACKS_BOT_MELEE)
                or barrack == GetBarracks(GetOpposingTeam(), BARRACKS_BOT_RANGED))
            then
                local barrackDistance = GetUnitToLocationDistance(barrack, vLocation)
                if barrackDistance < hBarrackTargetDistance then
                    hBarrackTarget = barrack
                    hBarrackTargetDistance = barrackDistance
                end
            end
        end
        if hBarrackTarget then
            return hBarrackTarget
        end

        local hTowerTarget = nil
        local hTowerTargetDistance = math.huge
        for _, tower in pairs(unitList) do
            if IsValid(tower) and (tower == GetTower(GetOpposingTeam(), TOWER_TOP_3) or tower == GetTower(GetOpposingTeam(), TOWER_MID_3) or tower == GetTower(GetOpposingTeam(), TOWER_BOT_3)) then
                local towerDistance = GetUnitToLocationDistance(tower, vLocation)
                if towerDistance < hTowerTargetDistance then
                    hTowerTarget = tower
                    hTowerTargetDistance = towerDistance
                end
            end
        end
        if hTowerTarget then
            return hTowerTarget
        end

        return false
    end)

    if cachedTarget == false then return nil end
    return cachedTarget
end

function Push.CanBeAttacked(building)
    if  building ~= nil
    and building:CanBeSeen()
    and not building:IsInvulnerable()
    then
        return true
    end
end

function Push.IsEnemyTP(nID)
    for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
        if id == nID then
            return true
        end
    end

    return false
end

function Push.IsInDangerWithinTower(hUnit, fThreshold, fDuration)
    local cacheKey = 'PushIsInDangerWithinTower-'..tostring(hUnit:GetUnitName())..'-'..tostring(J.ToNearest500(hUnit:GetLocation().x))..'-'..tostring(J.ToNearest500(hUnit:GetLocation().y))
    return J.Utils.GetCachedOrCompute(cacheKey, 0.3, function()
        local totalDamage = 0
        for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
            if J.IsValid(enemy)
            and J.IsInRange(hUnit, enemy, 1600)
            and (enemy:GetAttackTarget() == hUnit or J.IsChasingTarget(enemy, hUnit)) then
                local enemyDamage = CombatPower.EstimateAttackDamage(
                    enemy,
                    hUnit,
                    fDuration,
                    1,
                    math.huge
                )
                totalDamage = totalDamage + enemyDamage
            end
        end

        local hUnitHealth = hUnit:GetHealth()
        return (totalDamage / hUnitHealth * 1.2) > fThreshold
    end)
end

function Push.GetSpecialUnitsNearby(bot, hUnitList, nRadius)
    local cacheKey = 'PushGetSpecialUnitsNearby-'..tostring(bot:GetPlayerID())..'-'..tostring(nRadius)
    return J.Utils.GetCachedOrCompute(cacheKey, 0.5, function()
        local hCreepList = hUnitList
        for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
            if unit ~= nil and unit:CanBeSeen() and J.IsInRange(bot, unit, nRadius) then
                local sUnitName = unit:GetUnitName()
                if string.find(sUnitName, 'invoker_forge_spirit')
                or string.find(sUnitName, 'lycan_wolf')
                or string.find(sUnitName, 'eidolon')
                or string.find(sUnitName, 'beastmaster_boar')
                or string.find(sUnitName, 'beastmaster_greater_boar')
                or string.find(sUnitName, 'furion_treant')
                or string.find(sUnitName, 'broodmother_spiderling')
                or string.find(sUnitName, 'skeleton_warrior')
                or string.find(sUnitName, 'warlock_golem')
                or unit:HasModifier('modifier_dominated')
                or unit:HasModifier('modifier_chen_holy_persuasion')
                then
                    table.insert(hCreepList, unit)
                end
            end
        end

        return hCreepList
    end)
end

function Push.IsHealthyInsideFountain(hUnit)
    return hUnit:HasModifier('modifier_fountain_aura_buff')
        and J.GetHP(hUnit) > 0.90
        and J.GetMP(hUnit) > 0.85
end

function Push.GetAllyHeroesAttackingUnit(hUnit)
    local hUnitList = {}
    for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
        if J.IsValidHero(allyHero)
        and not J.IsSuspiciousIllusion(allyHero)
        and (allyHero:GetAttackTarget() == hUnit)
        then
            table.insert(hUnitList, allyHero)
        end
    end

    return hUnitList
end

function Push.GetAllyCreepsAttackingUnit(hUnit)
    local hUnitList = {}
    for _, creep in pairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS)) do
        if J.IsValid(creep)
        and (creep:GetAttackTarget() == hUnit)
        then
            table.insert(hUnitList, creep)
        end
    end

    return hUnitList
end

function Push.GetLaneBuildingTier(nLane)
    if nLane == LANE_TOP then
        if GetTower(GetOpposingTeam(), TOWER_TOP_1) ~= nil then
            return 1
        elseif GetTower(GetOpposingTeam(), TOWER_TOP_2) ~= nil then
            return 2
        elseif GetTower(GetOpposingTeam(), TOWER_TOP_3) ~= nil
            or GetBarracks(GetOpposingTeam(), BARRACKS_TOP_MELEE) ~= nil
            or GetBarracks(GetOpposingTeam(), BARRACKS_TOP_RANGED) ~= nil
        then
            return 3
        else
            return 4
        end
    elseif nLane == LANE_MID then
        if GetTower(GetOpposingTeam(), TOWER_MID_1) ~= nil then
            return 1
        elseif GetTower(GetOpposingTeam(), TOWER_MID_2) ~= nil then
            return 2
        elseif GetTower(GetOpposingTeam(), TOWER_MID_3) ~= nil
            or GetBarracks(GetOpposingTeam(), BARRACKS_MID_MELEE) ~= nil
            or GetBarracks(GetOpposingTeam(), BARRACKS_MID_RANGED) ~= nil
        then
            return 3
        else
            return 4
        end
    elseif nLane == LANE_BOT then
        if GetTower(GetOpposingTeam(), TOWER_BOT_1) ~= nil then
            return 1
        elseif GetTower(GetOpposingTeam(), TOWER_BOT_2) ~= nil then
            return 2
        elseif GetTower(GetOpposingTeam(), TOWER_BOT_3) ~= nil
            or GetBarracks(GetOpposingTeam(), BARRACKS_BOT_MELEE) ~= nil
            or GetBarracks(GetOpposingTeam(), BARRACKS_BOT_RANGED) ~= nil
        then
            return 3
        else
            return 4
        end
    end
    return 1
end

function Push.ShouldWaitForImportantItemsSpells(vLocation)
    if J.IsMidGame() or J.IsLateGame() then
        if J.Utils.HasTeamMemberWithCriticalItemInCooldown(vLocation) then return true end
        if J.Utils.HasTeamMemberWithCriticalSpellInCooldown(vLocation) then return true end
    end
    return false
end

function Push.IsAntiBackdoorStopBuilding(target)
    local enemyTeam = GetOpposingTeam()
    return target == GetTower(enemyTeam, TOWER_TOP_2)
        or target == GetTower(enemyTeam, TOWER_MID_2)
        or target == GetTower(enemyTeam, TOWER_BOT_2)
        or target == GetTower(enemyTeam, TOWER_TOP_3)
        or target == GetTower(enemyTeam, TOWER_MID_3)
        or target == GetTower(enemyTeam, TOWER_BOT_3)
        or (TOWER_BASE_1 ~= nil and target == GetTower(enemyTeam, TOWER_BASE_1))
        or (TOWER_BASE_2 ~= nil and target == GetTower(enemyTeam, TOWER_BASE_2))
        or target == GetAncient(enemyTeam)
        or target == GetBarracks(enemyTeam, BARRACKS_TOP_MELEE)
        or target == GetBarracks(enemyTeam, BARRACKS_TOP_RANGED)
        or target == GetBarracks(enemyTeam, BARRACKS_MID_MELEE)
        or target == GetBarracks(enemyTeam, BARRACKS_MID_RANGED)
        or target == GetBarracks(enemyTeam, BARRACKS_BOT_MELEE)
        or target == GetBarracks(enemyTeam, BARRACKS_BOT_RANGED)
end

function Push.HasDefenseGlyphBuff(target)
    if target == nil then return false end
    return target:HasModifier('modifier_fountain_glyph')
end

function Push.HasBackdoorProtect(target)
    if target == nil then return false end
    if Push.HasDefenseGlyphBuff(target)
        or target:HasModifier('modifier_backdoor_protection')
        or target:HasModifier('modifier_backdoor_protection_in_base')
        or target:HasModifier('modifier_backdoor_protection_active')
    then
        return true
    end

    if Push.IsAntiBackdoorStopBuilding(target) then
        return not target:HasModifier('modifier_thdots_anti_bd_stop')
    end

    return false
end

return Push
