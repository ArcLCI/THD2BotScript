local Tasks = require(GetScriptDirectory()..'/THDFuncLib/mode_task')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Push = {}
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')
local CombatPower = require(GetScriptDirectory()..'/THDFuncLib/combat_power')
local LaneWork = require(GetScriptDirectory()..'/THDFuncLib/push_lane_work')
local Escort = require(GetScriptDirectory()..'/THDFuncLib/push_escort')
local PushMovement = require(GetScriptDirectory()..'/THDFuncLib/push_movement')
local EscortConfig = require(GetScriptDirectory()..'/THDFuncLib/push_escort_config')
local TowerSafety = require(GetScriptDirectory()..'/THDFuncLib/tower_safety')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')

local function NoteDesire(bot, reason)
	bot.THD_PushDesireReason = reason
	CandidateDebug.Note(reason)
end

local function LogPushDecision(bot,lane,score,reason,detail)
	if not EscortConfig.DEBUG or not EscortConfig.PUSH_ESCORT_ENABLED then return end
	if reason == 'different_stable_lane' then return end
	bot.THD_PushDecisionLogs = bot.THD_PushDecisionLogs or {}
	local old = bot.THD_PushDecisionLogs[lane]
	local key = tostring(reason)..':'..tostring(bot:GetActiveMode())
	if old and DotaTime()-old.at < 0.5 then return end
	if old and old.key == key and DotaTime()-old.at < 2 then return end
	bot.THD_PushDecisionLogs[lane] = {key = key, at = DotaTime()}
	print(string.format('[BOT][PushDecision] run=%s time=%.3f pid=%s lane=%s score=%.3f reason=%s active_mode=%s active_desire=%.3f %s',
		EscortConfig.RUN_ID,DotaTime(),bot:GetPlayerID(),lane,score,tostring(reason),bot:GetActiveMode(),bot:GetActiveModeDesire(),detail or ''))
end



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
local PUSH_HIGH_GROUND_ASSAULT_AUTH_TTL = 0.80
local PUSH_HIGH_GROUND_FORCE_BUILDING_HP = 0.45 -- 弱化高地塔的收尾窗口适度提前
local PUSH_HIGH_GROUND_FORCE_MIN_ATTACKERS = 2
local PUSH_HIGH_GROUND_COMMIT_MIN_HP = Wasteland.HIGH_GROUND_COMMIT_MIN_HP
local PUSH_HIGH_GROUND_MAX_TOWER_DAMAGE_RATIO = Wasteland.HIGH_GROUND_MAX_TOWER_DAMAGE_RATIO
local LANE_MODE_DEBUG = false -- 验证期间输出三路推塔评分，确认后可关闭。


local function GetLaneName(lane)
    if lane == LANE_TOP then return 'TOP' end
    if lane == LANE_MID then return 'MID' end
    if lane == LANE_BOT then return 'BOT' end
    return tostring(lane)
end

function Push.GetStablePushLane(bot, lane)
    if bot == nil then return lane end

	local continuationLane = Wasteland.GetPushContinuationLane ~= nil
		and Wasteland.GetPushContinuationLane() or nil
	if continuationLane ~= nil then
		bot.StablePushLane = continuationLane
		bot.StablePushLaneUntil = GameTime() + PUSH_LANE_STICKY_SECONDS
		return continuationLane
	end
	local conversion = Wasteland.GetConversionOpportunity()
	local commitment = Wasteland.GetOuterTowerCommitment()
	if conversion ~= nil and conversion.lane ~= nil
	and (commitment == nil or (tonumber(commitment.tier) or 3) <= 2)
	then
		-- 欲望阶段只选择击杀转推路线，目标生命周期统一在 PushThink 的安全门后创建。
		bot.StablePushLane = conversion.lane
		bot.StablePushLaneUntil = GameTime() + PUSH_LANE_STICKY_SECONDS
		return conversion.lane
	end
	if commitment ~= nil then
		bot.StablePushLane = commitment.lane
		bot.StablePushLaneUntil = GameTime() + PUSH_LANE_STICKY_SECONDS
		return commitment.lane
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

function Push.CanMaintainHighGroundAssault(bot, objective, retreatState)
	local authorization = Wasteland.GetHighGroundAssaultAuthorization ~= nil
		and Wasteland.GetHighGroundAssaultAuthorization(bot, objective) or nil
	if authorization == nil or bot == nil then return false, nil, 'authorization_missing' end
	retreatState = retreatState or J.Retreat.GetState(bot)
	if (retreatState.enemyCount or 0) > (retreatState.allyCount or 0) then
		return false, nil, 'outnumbered'
	end
	if retreatState.severity >= J.Retreat.CRITICAL then return false, nil, 'critical_retreat' end
	if (retreatState.contextRawSeverity or J.Retreat.NONE) >= J.Retreat.HIGH then
		return false, nil, 'context_retreat_high'
	end
	if J.GetHP(bot) <= PUSH_HIGH_GROUND_COMMIT_MIN_HP then return false, nil, 'low_hp' end

	local towerThreat = retreatState.towerThreat or {}
	if retreatState.severity >= J.Retreat.HIGH and towerThreat.highGroundLock ~= true then
		return false, nil, 'non_tower_high_danger'
	end
	local health = math.max(1, bot:GetHealth())
	if towerThreat.unseenIncoming == true then return false, nil, 'unseen_incoming' end
	if (towerThreat.unavoidableDamage or 0) >= health then return false, nil, 'lethal_tower_damage' end
	if (towerThreat.predictedDamage or 0) / health >= PUSH_HIGH_GROUND_MAX_TOWER_DAMAGE_RATIO then
		return false, nil, 'tower_damage_ratio'
	end
	return true, authorization, 'allowed'
end

function Push.BuildHighGroundAssaultSafetyState(bot, retreatState)
	retreatState = retreatState or J.Retreat.GetState(bot)
	local towerThreat = retreatState.towerThreat or {}
	if retreatState.frameworkEnabled == false and J.Retreat.GetTowerThreat ~= nil then
		towerThreat = J.Retreat.GetTowerThreat(bot, 3.0, nil, true)
	end
	local nearbyAllies = J.GetAlliesNearLoc(bot:GetLocation(), PUSH_LOCAL_HERO_RESPONSE_RANGE)
	local nearbyEnemies = Push.GetVisibleNearbyEnemyHeroes(
		bot,
		J.GetNearbyHeroes(bot, PUSH_LOCAL_HERO_RESPONSE_RANGE, true, BOT_MODE_NONE),
		PUSH_LOCAL_HERO_RESPONSE_RANGE)
	local severity = retreatState.severity or J.Retreat.NONE
	local contextRawSeverity = retreatState.contextRawSeverity or J.Retreat.NONE
	if bot:GetActiveMode() == BOT_MODE_RETREAT
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH
	then
		severity = math.max(severity, J.Retreat.HIGH)
		contextRawSeverity = math.max(contextRawSeverity, J.Retreat.HIGH)
	end
	return {
		severity = severity,
		contextRawSeverity = contextRawSeverity,
		allyCount = #nearbyAllies,
		enemyCount = #nearbyEnemies,
		towerThreat = towerThreat,
	}
end

function Push.RefreshHighGroundAssaultAuthorization(bot, lane)
	if bot == nil then return nil end
	local objective = Wasteland.GetPushObjective ~= nil and Wasteland.GetPushObjective(true) or nil
	if objective == nil then
		bot.THD_HighGroundAssaultAuthorization = nil
		return nil
	end
	-- 三个 Push mode 会逐帧查询欲望；非目标 lane 不抢先清除匹配 mode 刚刷新的短租约。
	if objective.lane ~= lane then return bot.THD_HighGroundAssaultAuthorization end
	if Wasteland.GetHighGroundAssaultAuthorization == nil
	or Wasteland.GetHighGroundAssaultAuthorization(bot, objective) == nil
	then
		bot.THD_HighGroundAssaultAuthorization = nil
		return nil
	end
	local safetyState = Push.BuildHighGroundAssaultSafetyState(bot, J.Retreat.GetState(bot))
	local allowed, authorization, denialReason = Push.CanMaintainHighGroundAssault(
		bot, objective, safetyState)
	if not allowed then
		bot.THD_HighGroundAssaultAuthorization = nil
		if denialReason ~= 'authorization_missing'
		and Wasteland.NoteHighGroundAssaultDecision ~= nil
		then
			Wasteland.NoteHighGroundAssaultDecision(bot, objective, 'safety_cancel',
				string.format('reason=%s hp=%.3f allies=%s enemies=%s severity=%s raw_severity=%s',
					tostring(denialReason), J.GetHP(bot), tostring(safetyState.allyCount or 0),
					tostring(safetyState.enemyCount or 0), tostring(safetyState.severity or 0),
					tostring(safetyState.contextRawSeverity or 0)))
			if denialReason == 'outnumbered' then
				Wasteland.NoteHighGroundAssaultDecision(bot, objective, 'yield_outnumbered',
					'allies=' .. tostring(safetyState.allyCount or 0)
						.. ' enemies=' .. tostring(safetyState.enemyCount or 0))
			end
		end
		return nil
	end
	authorization.expiresAt = DotaTime() + PUSH_HIGH_GROUND_ASSAULT_AUTH_TTL
	bot.THD_HighGroundAssaultAuthorization = authorization
	if Wasteland.NoteHighGroundAssaultDecision ~= nil then
		Wasteland.NoteHighGroundAssaultDecision(bot, objective, 'authorized',
			'ttl=' .. tostring(PUSH_HIGH_GROUND_ASSAULT_AUTH_TTL))
	end
	return authorization
end

local function ComputeModeDesire(bot, lane)
	local highGroundAuthorization = Push.RefreshHighGroundAssaultAuthorization(bot, lane)
	-- 安全门不缓存；模式缓存窗口内发生撤退、基地告急或高地门槛变化时必须立即生效。
	if bot == nil
	or (highGroundAuthorization == nil and J.Retreat.ShouldYield(bot, J.Retreat.HIGH))
	or J.CanNotUseAction(bot)
	or J.IsRoshanCommitmentActive(bot)
	then
		NoteDesire(bot, 'action_unavailable_or_retreat_or_roshan')
		LaneWork.Release(bot, 'push_unavailable')
		return BOT_MODE_DESIRE_NONE
	end

	local laneBuildingTier = Push.GetLaneBuildingTier(lane)
	CandidateDebug.Detail('target_tier', laneBuildingTier)
	local objective = Push.GetLaneBuildingTarget(lane) or GetAncient(GetOpposingTeam())
	if not Push.IsObjectiveValid(objective) then
		LaneWork.Release(bot, 'invalid_objective', lane)
		NoteDesire(bot, 'invalid_objective')
		return BOT_MODE_DESIRE_NONE
	end
	local currentWastelandState = Wasteland.IsEnabled() and Wasteland.GetState() or nil

	local stablePushLane = Push.GetStablePushLane(bot, lane)
	CandidateDebug.Detail('lane', lane)
	CandidateDebug.Detail('stable_lane', stablePushLane)
	if stablePushLane ~= lane then
		LaneWork.Leave(bot, 'different_stable_lane', lane)
		NoteDesire(bot, 'different_stable_lane')
		return BOT_MODE_DESIRE_NONE
	end

	local objectiveLocation = Push.GetObjectiveLocation(lane, objective)
	local snapshotKey = 'PushSnapshot-' .. Push.GetObjectiveKey(objective)
	CandidateDebug.Detail('objective_key', snapshotKey)
	local snapshot = Timer.GetOrCompute(
		Timer.GetBotLaneKey(snapshotKey, bot, lane),
		PUSH_SNAPSHOT_CACHE_INTERVAL,
		function()
			return Push.BuildPushSnapshot(
				bot, lane, objective, objectiveLocation, laneBuildingTier, currentWastelandState)
		end
	)
	if currentWastelandState ~= nil then
		snapshot.wastelandState = currentWastelandState
		snapshot.baseThreat = currentWastelandState.baseThreat
		if snapshot.highGroundContext ~= nil then
			snapshot.highGroundContext.averageLevel = currentWastelandState.allyAverageLevel
			currentWastelandState.highGroundContext = snapshot.highGroundContext
		end
	end
	if laneBuildingTier >= 3 then
		local allowed, permissionReason = Wasteland.EvaluateHighGroundPermission(
			laneBuildingTier, snapshot.highGroundContext or {})
		if not allowed then CandidateDebug.BeginPhase('ordinary_lane_work') end
		CandidateDebug.Detail('lane', lane)
		CandidateDebug.Detail('tier', laneBuildingTier)
		CandidateDebug.Detail('eligible', snapshot.highGroundContext and snapshot.highGroundContext.initialEligibleCount)
		CandidateDebug.Detail('average_level', snapshot.highGroundContext and snapshot.highGroundContext.averageLevel)
		if not allowed then
			-- 拒绝围攻不等于禁止所有普通兵线工作；独立任务不能取得建筑攻击授权。
			NoteDesire(bot,'lane_work_'..tostring(permissionReason))
			return LaneWork.GetDesire(bot, lane, permissionReason)
		end
	end
	LaneWork.Leave(bot, 'siege_permission_restored', lane)
	local immediateSafety = Push.GetImmediateSafetyState(bot)
	return Push.ComputePushDesire(bot, lane, snapshot, immediateSafety)
end

local function LiveEnemy(bot,target)
	local ok, valid = pcall(function()
		return target ~= nil and not target:IsNull() and target:CanBeSeen() and target:IsAlive()
			and target:IsHero() and target:GetTeam() ~= bot:GetTeam() and not J.IsSuspiciousIllusion(target)
	end)
	return ok and valid == true
end

local function CombatHandoff(bot,lane)
	if not EscortConfig.PUSH_ESCORT_ENABLED then return false end
	local goal = Wasteland.GetPushObjective()
	if goal == nil or goal.lane ~= lane or not Wasteland.IsPushObjectiveParticipant(bot,goal) then
		if bot.THD_PushFightIntent and bot.THD_PushFightIntent.lane == lane then bot.THD_PushFightIntent = nil end
		return false
	end
	local ok,target = pcall(function() return bot:GetAttackTarget() end)
	if not ok or not LiveEnemy(bot,target) then ok,target = pcall(function() return J.GetProperTarget(bot) end) end
	if bot:GetActiveMode() == BOT_MODE_ATTACK and ok and LiveEnemy(bot,target)
	and GetUnitToUnitDistance(target,goal.target) <= EscortConfig.LOCAL_RANGE then return true,'attack_active' end
	local intent = bot.THD_PushFightIntent
	if intent == nil or intent.lane ~= lane or intent.objectiveID ~= goal.id then return false end
	if not LiveEnemy(bot,intent.target) or GetUnitToUnitDistance(intent.target,goal.target) > EscortConfig.LOCAL_RANGE then
		bot.THD_PushFightIntent = nil
		return false
	end
	if DotaTime() < intent.untilAt then return true,'handoff_pending' end
	bot.THD_PushFightIntent = nil
	bot.THD_PushFightRetryAt = DotaTime()+EscortConfig.RETRY_DELAY
	LogPushDecision(bot,lane,0,'handoff_not_observed')
	return false
end

local function TaskName(lane) return 'push_'..tostring(lane) end
function Push.GetPushDesire(bot,lane)
	PushMovement.Observe(bot)
	if PushMovement.Yielding(bot) then
		Tasks.Release(bot,TaskName(lane),'physical_stall')
		LogPushDecision(bot,lane,0,'physical_stall_yield')
		return 0
	end
	if EscortConfig.PUSH_ESCORT_ENABLED and EscortConfig.DEBUG and not bot.THD_PushEscortReady then
		bot.THD_PushEscortReady = true
		print('[BOT][PushEscort] run='..EscortConfig.RUN_ID..' event=ready pid='..tostring(bot:GetPlayerID()))
	end
	if EscortConfig.PUSH_ESCORT_ENABLED and DotaTime() < (bot.THD_PushEscortRetryAt or -90)
	and bot.THD_PushEscortRetryLane == lane then LogPushDecision(bot,lane,0,'escort_retry'); return 0 end
	local name=TaskName(lane)
	local active=Tasks.Active(bot,name)
	if active~=nil and not Tasks.Check(bot,name,Push.IsObjectiveValid(active.objective)) then LogPushDecision(bot,lane,0,'task_invalid'); return 0 end
	bot.THD_PushDesireReason,bot.THD_PushScoreSnapshot = 'evaluating',nil
	local score=ComputeModeDesire(bot,lane)
	local yieldCombat,combatReason = CombatHandoff(bot,lane)
	if yieldCombat then score=math.min(score,EscortConfig.HANDOFF_PUSH_CAP) end
	local info = bot.THD_PushScoreSnapshot or {}
	local pressure = bot.THD_PushPressure
	if pressure ~= nil and pressure.lane == lane and score <= BOT_MODE_DESIRE_EXTRA_LOW*1.1 then
		pressure.ready,pressure.reason = false,'push_gate_'..tostring(bot.THD_PushDesireReason)
	end
	LogPushDecision(bot,lane,score,combatReason or bot.THD_PushDesireReason,
		string.format('min_level=%s allies=%s enemies=%s enemy_tp=%s base=%s pressure=%s pressure_reason=%s base_reason=%s min_level_pid=%s ready_members=%s level_scope=%s excluded=%s',
			tostring(info.minLevel),tostring(info.allies),tostring(info.enemies),tostring(info.tp),tostring(info.base),
			tostring(pressure and pressure.ready),tostring(pressure and pressure.reason),tostring(bot.THD_PushDesireReason),
			tostring(info.minPlayerID),tostring(info.readyMembers),tostring(info.levelScope),tostring(info.excluded)))
	local objective=Push.GetLaneBuildingTarget(lane) or GetAncient(GetOpposingTeam())
	if score<=0 or not Push.IsObjectiveValid(objective) then Tasks.Release(bot,name,'score_or_safety');return 0 end
	local location=objective:CanBeSeen() and objective:GetLocation() or GetLaneFrontLocation(bot:GetTeam(),lane,0)
	return Tasks.Offer(bot,name,score,{objective=objective,location=location,lane=lane,
		reason='push_objective',arrivalRadius=1600,stallSeconds=8})
end
function Push.OnStart(bot,lane) Tasks.Start(bot,TaskName(lane)) end

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

function Push.BuildPushSnapshot(bot, lane, objective, objectiveLocation, laneBuildingTier, wastelandState)
	local allies = J.GetAlliesNearLoc(objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE)
	local enemies = J.GetEnemiesNearLoc(objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE)
	local allyPower = SumLocalCombatPower(allies)
	local enemyPower = SumLocalCombatPower(enemies)
	local readiness = nil
	local teamMinLevel = math.huge
	if EscortConfig.PUSH_ESCORT_ENABLED then
		readiness = Wasteland.GetPushLevelReadiness(objectiveLocation,lane)
		teamMinLevel = readiness.minLevel
	else
		for i = 1, #GetTeamPlayers(GetTeam()) do
			local member = GetTeamMember(i)
			if member ~= nil then teamMinLevel = math.min(teamMinLevel,member:GetLevel()) end
		end
		if teamMinLevel == math.huge then teamMinLevel = 0 end
	end
	wastelandState = wastelandState or (Wasteland.IsEnabled() and Wasteland.GetState() or nil)
	local localPowerAdvantage = #enemies == 0
		or (#allies >= #enemies and allyPower >= enemyPower)
	local highGroundContext = {
		averageLevel = wastelandState ~= nil and wastelandState.allyAverageLevel or nil,
		initialEligibleCount = Wasteland.IsEnabled()
			and Wasteland.GetEligibleParticipantCount(objectiveLocation) or 0,
		alliedCreepDistance = GetClosestVisibleCreepDistance(
			UNIT_LIST_ALLIED_CREEPS, objectiveLocation, 2000),
		backdoorProtected = Push.HasBackdoorProtect(objective),
		allyCount = #allies,
		enemyCount = #enemies,
		allyPower = allyPower,
		enemyPower = enemyPower,
		localPowerAdvantage = localPowerAdvantage,
		enemyTpCount = #J.Utils.GetEnemyIdsInTpToLocation(objectiveLocation, PUSH_OBJECTIVE_SNAPSHOT_RANGE),
		doesTeamHaveAegis = J.DoesTeamHaveAegis(),
		enemyAlive = J.GetNumOfAliveHeroes(true),
	}
	if wastelandState ~= nil then wastelandState.highGroundContext = highGroundContext end
	return {
		objective = objective,
		objectiveLocation = objectiveLocation,
		laneBuildingTier = laneBuildingTier,
		allyCount = #allies,
		enemyCount = #enemies,
		allyPower = allyPower,
		enemyPower = enemyPower,
		localPowerAdvantage = localPowerAdvantage,
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
		levelReadiness = readiness,
		baseLaneDesire = GetPushLaneDesire(lane),
		doesTeamHaveAegis = J.DoesTeamHaveAegis(),
		ancientDefenseState = J.GetAncientDefenseState(4500),
		baseThreat = wastelandState ~= nil and wastelandState.baseThreat or nil,
		highGroundContext = highGroundContext,
		shouldWaitForImportantItems = Push.ShouldWaitForImportantItemsSpells(
			GetLaneFrontLocation(GetOpposingTeam(), lane, 0)),
		wastelandState = wastelandState,
	}
end

local function ComputePressure(snapshot)
	if not EscortConfig.PUSH_ESCORT_ENABLED then return false,'disabled' end
	if snapshot.wastelandState == nil or not Wasteland.IsTeamAhead(snapshot.wastelandState) then return false,'no_strategic_advantage' end
	if snapshot.allyCount < EscortConfig.PRESSURE_MIN_ALLIES or not snapshot.localPowerAdvantage then return false,'insufficient_local_force' end
	if snapshot.enemyCount > 0 and snapshot.allyPower < snapshot.enemyPower*EscortConfig.PRESSURE_POWER_RATIO then return false,'small_power_margin' end
	if snapshot.enemyTpCount > 0 or snapshot.recentEnemyCount > snapshot.enemyCount or snapshot.missingEnemyCount > 2 then return false,'enemy_information_risk' end
	if snapshot.baseThreat and (snapshot.baseThreat.hardEmergency or snapshot.baseThreat.coveredPressure) then return false,'base_pressure' end
	if not J.IsValidBuilding(snapshot.objective) or Push.HasBackdoorProtect(snapshot.objective) then return false,'no_building_window' end
	local readyCount,ultimates,readyUltimates,items,readyItems = 0,0,0,0,0
	for _, member in ipairs(J.GetAlliesNearLoc(snapshot.objectiveLocation,1600)) do
		local mana = member:GetMaxMana() > 0 and member:GetMana()/member:GetMaxMana() or 1
		if J.GetHP(member) >= EscortConfig.PRESSURE_MIN_HP and mana >= EscortConfig.PRESSURE_MIN_MANA
		and not J.IsRoshanCommitmentActive(member) then
			readyCount = readyCount + 1
			-- 只使用技能本身声明的类型/冷却，不按原版英雄槽位推断大招。
			for slot=0,5 do
				local ability = member:GetAbilityInSlot(slot)
				if ability ~= nil and ability:IsTrained() and ability:IsUltimate() and not ability:IsPassive() then
					ultimates = ultimates + 1
					if ability:IsFullyCastable() then readyUltimates = readyUltimates + 1 end
				end
				local item = member:GetItemInSlot(slot)
				if item ~= nil and not item:IsPassive() then
					items = items + 1
					if item:IsFullyCastable() then readyItems = readyItems + 1 end
				end
			end
		end
	end
	if readyCount < EscortConfig.PRESSURE_MIN_ALLIES then return false,'health_or_mana_not_ready' end
	if readyUltimates < math.ceil(ultimates/2) or readyItems < math.ceil(items/2) then return false,'cooldowns_not_ready' end
	return true,'advantage_pressure'
end

function Push.AssessPressure(snapshot)
	if DotaTime() < (snapshot.pressureRefreshAt or -90) then return snapshot.pressureReady,snapshot.pressureReason end
	snapshot.pressureReady,snapshot.pressureReason = ComputePressure(snapshot)
	snapshot.pressureRefreshAt = DotaTime()+EscortConfig.SAMPLE_INTERVAL
	return snapshot.pressureReady,snapshot.pressureReason
end

function Push.ComputePushDesire(bot, lane, snapshot, immediateSafety)
	-- 与入口共用本帧安全审查，避免已授权的纯塔风险被第二道旧门槛否决。
	local authorized = bot ~= nil and Wasteland.HasLiveHighGroundAssaultAuthorization(bot)
		and bot.THD_HighGroundAssaultAuthorization.lane == lane
	if bot == nil
	or (not authorized and J.Retreat.ShouldYield(bot, J.Retreat.HIGH))
	or J.CanNotUseAction(bot)
	or J.IsRoshanCommitmentActive(bot)
	then
		NoteDesire(bot, 'action_unavailable_or_retreat_or_roshan')
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
	local wastelandState = snapshot.wastelandState
	local baseThreat = snapshot.baseThreat
		or (wastelandState ~= nil and Wasteland.GetBaseThreatSnapshot(wastelandState, bot) or nil)
	bot.THD_PushScoreSnapshot = {lane=lane,minLevel=snapshot.teamMinLevel,enemies=snapshot.enemyCount,
		allies=snapshot.allyCount,tp=snapshot.enemyTpCount,base=snapshot.baseLaneDesire}
	if snapshot.levelReadiness then
		local info = bot.THD_PushScoreSnapshot
		info.minPlayerID,info.readyMembers = snapshot.levelReadiness.minPlayerID,snapshot.levelReadiness.count
		info.levelScope,info.excluded = snapshot.levelReadiness.scope,snapshot.levelReadiness.excluded
	end
	if Wasteland.IsEnabled() and baseThreat ~= nil and baseThreat.hardEmergency == true then
		Wasteland.InvalidateObjectiveForBaseDefense(bot, baseThreat)
		NoteDesire(bot, 'hard_base_emergency')
		return BOT_MODE_DESIRE_NONE
	end
	if Wasteland.ShouldYieldPushObjective(bot, lane) then
		NoteDesire(bot, 'objective_nonparticipant')
		return BOT_MODE_DESIRE_EXTRA_LOW
	end

	if bot:GetAssignedLane() == LANE_MID and J.IsInLaningPhase() then
		NoteDesire(bot, 'mid_laning')
		return BOT_MODE_DESIRE_EXTRA_LOW
	end
	if snapshot.teamMinLevel < 7 then NoteDesire(bot, 'team_min_level_below_7'); return BOT_MODE_DESIRE_EXTRA_LOW end
	if snapshot.enemyTpCount > 0 then NoteDesire(bot, 'enemy_tp'); return BOT_MODE_DESIRE_EXTRA_LOW end
	-- 守军出现时只在目标点人数与本地可见属性战力均不劣时继续推进。
	if snapshot.enemyCount > 0 and not snapshot.localPowerAdvantage then
		NoteDesire(bot, 'local_power_disadvantage')
		return BOT_MODE_DESIRE_EXTRA_LOW
	end

	local nMaxDesire = 0.9
	local nSafetyMaxDesire = 1.0
	if Wasteland.IsEnabled() and baseThreat ~= nil and baseThreat.coveredPressure == true then
		nSafetyMaxDesire = math.min(nSafetyMaxDesire, 0.75)
	end
	CandidateDebug.Detail('base_lane_desire', snapshot.baseLaneDesire)
	CandidateDebug.Detail('ally_alive', snapshot.allyAlive)
	CandidateDebug.Detail('enemy_alive', snapshot.enemyAlive)
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

	if not Wasteland.IsEnabled() then
		if immediateSafety.baseEmergency
		or ((ancientDefenseState.enemyPressure or 0) > 0
			and (ancientDefenseState.effectiveAllyCount or 0) < 1)
		then
			nSafetyMaxDesire = math.min(nSafetyMaxDesire, PUSH_BASE_DEFENSE_MAX_DESIRE)
		end
		if (ancientDefenseState.effectiveAllyCount or 0) >= 1 then
			nPushDesire = nPushDesire * 0.5
		end
	end

	if snapshot.shouldWaitForImportantItems
	and eAliveCount > aAliveCount + PUSH_ALIVE_ENEMY_ADVANTAGE_TOLERANCE
	then
		NoteDesire(bot, 'wait_important_items')
		return BOT_MODE_DESIRE_VERYLOW
	end

	local botTarget = bot:GetAttackTarget()
	if J.IsValidBuilding(botTarget)
	and not string.find(botTarget:GetUnitName(), 'tower1')
	and not string.find(botTarget:GetUnitName(), 'tower2')
	and Push.HasBackdoorProtect(botTarget)
	then
		NoteDesire(bot, 'attack_target_backdoor')
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
		NoteDesire(bot, 'ancient_opportunity')
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
		CandidateDebug.Detail('safety_cap', nSafetyMaxDesire)
		CandidateDebug.Detail('scored_lane_desire', nPushDesire)
		local desire = RemapValClamped(nPushDesire, 0, 1, 0, nMaxDesire)
		local pressureReady,pressureReason = Push.AssessPressure(snapshot)
		bot.THD_PushPressure = {lane=lane,at=DotaTime(),ready=pressureReady,reason=pressureReason}
		if pressureReady then desire = math.max(desire,EscortConfig.PRESSURE_DESIRE) end
		NoteDesire(bot, 'push_score')
		return Wasteland.AdjustPushDesire(
			desire,
			snapshot.laneBuildingTier,
			snapshot.wastelandState,
			lane,
			nSafetyMaxDesire,
			bot
		)
	end

	NoteDesire(bot, 'alive_disadvantage')
	return lane == LANE_MID and BOT_MODE_DESIRE_VERYLOW or BOT_MODE_DESIRE_EXTRA_LOW
end

function Push.WhichLaneToPush(bot, lane)
	local continuationLane = Wasteland.GetPushContinuationLane ~= nil
		and Wasteland.GetPushContinuationLane() or nil
	if continuationLane ~= nil then return continuationLane end
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

local function GetLiveTower(team, towerID)
	if towerID == nil then return nil end
	local tower = GetTower(team, towerID)
	if not Wasteland.IsEnabled() then return tower end
	return Push.IsObjectiveValid(tower) and tower or nil
end

local function GetLiveBarracks(team, barracksID)
	if barracksID == nil then return nil end
	local building = GetBarracks(team, barracksID)
	if not Wasteland.IsEnabled() then return building end
	return Push.IsObjectiveValid(building) and building or nil
end

function Push.GetLaneBuildingTarget(lane)
    local tower1ID, tower2ID, tower3ID, meleeBarracksID, rangedBarracksID = GetLaneBuildingIDs(lane)
    if tower1ID == nil then return nil end

    local enemyTeam = GetOpposingTeam()
    return GetLiveTower(enemyTeam, tower1ID)
        or GetLiveTower(enemyTeam, tower2ID)
        or GetLiveTower(enemyTeam, tower3ID)
        or GetLiveBarracks(enemyTeam, meleeBarracksID)
        or GetLiveBarracks(enemyTeam, rangedBarracksID)
		or (Wasteland.IsEnabled() and GetLiveTower(enemyTeam, TOWER_BASE_1) or nil)
		or (Wasteland.IsEnabled() and GetLiveTower(enemyTeam, TOWER_BASE_2) or nil)
end

function Push.GetLaneBarracks(lane)
    local _, _, _, meleeBarracksID, rangedBarracksID = GetLaneBuildingIDs(lane)
    if meleeBarracksID == nil then return nil, nil end

    local enemyTeam = GetOpposingTeam()
    return GetLiveBarracks(enemyTeam, meleeBarracksID), GetLiveBarracks(enemyTeam, rangedBarracksID)
end

function Push.CanAttackManagedBuilding(bot, lane, target, objective)
	if Wasteland.CanAttackPushObjective == nil then return not Wasteland.IsEnabled() end
	return Wasteland.CanAttackPushObjective(bot, lane, target, objective)
end

function Push.NoteManagedBuildingAttack(bot, lane, target, objective)
	if objective ~= nil then return Wasteland.NotePushObjectiveAttack(bot, lane, target) end
	return Wasteland.NoteOpportunisticBuildingAttack(bot, target, 'hero')
end

function Push.TryAttackLaneBarracks(bot, lane, objective)
    local _, _, tower3ID = GetLaneBuildingIDs(lane)
    if tower3ID == nil or GetLiveTower(GetOpposingTeam(), tower3ID) ~= nil then return false end

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
		and Push.CanAttackManagedBuilding(bot, lane, barracks, objective)
        then
            barracks = J.GetStickyTarget(bot, candidate.sticky, barracks, 1.8, 2200)
            if barracks ~= nil
			and Push.CanAttackManagedBuilding(bot, lane, barracks, objective)
            and J.ActionAttackUnit(bot, candidate.action, barracks, true, 0.45)
            then
				Push.NoteManagedBuildingAttack(bot, lane, barracks, objective)
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
		bot.THD_HighGroundAssaultAuthorization = nil
		return true, 'yield_outnumbered'
	end

	local target = Push.SelectNearbyEnemyHero(bot, nearbyEnemies)
	if target ~= nil then
		-- 人数不劣时先响应可见英雄；下一轮模式仲裁会让 ATTACK 接管技能与追击。
		J.SetTargetIfChanged(bot, target, 0.2)
		J.ActionAttackUnit(bot, 'push_answer_enemy_hero', target, true, 0.25)
		return true, 'fight_hero'
	end

	return false, nil
end

function Push.ShouldForceHighGroundObjective(context)
	context = context or {}
	if context.authorized ~= true
	or context.phase ~= Wasteland.PHASE_SIEGE
	or context.role ~= Wasteland.ROLE_BUILDING_DAMAGE
	or context.attackable ~= true
	or context.backdoorProtected == true
	or (tonumber(context.botHP) or 0) <= PUSH_HIGH_GROUND_COMMIT_MIN_HP
	or (tonumber(context.allyCount) or 0) < (tonumber(context.enemyCount) or 0)
	then
		return false
	end
	local health, maxHealth = tonumber(context.targetHealth), tonumber(context.targetMaxHealth)
	local healthRatio = health ~= nil and maxHealth ~= nil and maxHealth > 0
		and health / maxHealth or 1
	-- 安全且有兵线的人数优势窗口允许输出位启动拆塔，不要求先有两人攻击。
	return (context.creepSupport == true and (tonumber(context.allyCount) or 0) >= 3
		and (tonumber(context.allyCount) or 0) > (tonumber(context.enemyCount) or 0))
		or healthRatio <= PUSH_HIGH_GROUND_FORCE_BUILDING_HP
		or (tonumber(context.allyBuildingAttackers) or 0) >= PUSH_HIGH_GROUND_FORCE_MIN_ATTACKERS
end

function Push.TryAttackObjectiveBuilding(bot, lane, pushObjective, observedTarget, botAttackRange, actionName)
	if pushObjective == nil
	or pushObjective.phase ~= Wasteland.PHASE_SIEGE
	or Push.IsObjectiveValid(observedTarget) ~= true
	or J.IsValidBuilding(observedTarget) ~= true
	or J.CanBeAttacked(observedTarget) ~= true
	or Push.HasBackdoorProtect(observedTarget)
	or Push.CanAttackManagedBuilding(bot, lane, observedTarget, pushObjective) ~= true
	or GetUnitToUnitDistance(bot, observedTarget) > math.min(1600, botAttackRange + 400)
	then
		return false
	end
	actionName = actionName or 'push_objective_building_damage'
	local buildingTarget = J.GetStickyTarget(
		bot, actionName, observedTarget, 1.8, botAttackRange + 500)
	if buildingTarget ~= nil
	and Push.CanAttackManagedBuilding(bot, lane, buildingTarget, pushObjective)
	then
		J.SetTargetIfChanged(bot, buildingTarget, 0.6)
		if J.ActionAttackUnit(bot, actionName, buildingTarget, true, 0.45) then
			Push.NoteManagedBuildingAttack(bot, lane, buildingTarget, pushObjective)
			return true
		end
	end
	return false
end

-- 围绕共享建筑接近；普通兵线前沿不再承担高地目标的最后一段移动。
function Push.TryApproachObjective(bot, lane, objective, target, attackRange, authorized)
	if not authorized or objective == nil or objective.lane ~= lane
	or (objective.phase ~= Wasteland.PHASE_ESCORT and objective.phase ~= Wasteland.PHASE_SIEGE)
	or not Wasteland.IsPushObjectiveParticipant(bot, objective)
	or not J.IsValidBuilding(target) or not J.CanBeAttacked(target)
	or Push.HasBackdoorProtect(target) then return false end
	local distance = GetUnitToUnitDistance(bot, target)
	if distance <= math.max(100, attackRange - 50) then return false end
	local center, current = target:GetLocation(), bot:GetLocation()
	local offset = math.max(100, attackRange - 75)
	local goal = center + (current - center):Normalized() * offset
	if not IsLocationPassable(goal) then
		Wasteland.NoteHighGroundAssaultDecision(bot, objective, 'approach_blocked', 'reason=terrain')
		return false
	end
	Wasteland.NoteHighGroundAssaultDecision(bot, objective, 'approach_objective',
		string.format('distance=%.1f attack_range=%.1f goal_x=%.1f goal_y=%.1f',
			distance, attackRange, goal.x, goal.y))
	return J.ActionMoveToLocation(bot, 'push_approach_objective', goal, 0.35, 100)
end

local fNextMovementTime = 0
function Push.OnEnd(bot, lane)
	Tasks.Release(bot,TaskName(lane),'mode_end')
	LaneWork.Leave(bot, 'mode_ended', lane)
	-- 普通攻击短暂接管时保留波次与不可重置的期限；公开上下文一秒后自然失效。
	if not EscortConfig.PUSH_ESCORT_ENABLED then Escort.Release(bot, 'disabled') end
end

local function EscortVisible(unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
end

local function EscortLaneCreep(unit)
	if not EscortVisible(unit) then return false end
	local name = unit:GetUnitName()
	-- 只接受游戏中的兵线/攻城兵名称，排除全局 creep 列表中的野怪和召唤物。
	return string.match(name, '^npc_dota_creep_goodguys_') ~= nil
		or string.match(name, '^npc_dota_creep_badguys_') ~= nil
		or string.match(name, '^npc_dota_goodguys_siege') ~= nil
		or string.match(name, '^npc_dota_badguys_siege') ~= nil
		or string.match(name, '^npc_thd_goodguys_.*siege') ~= nil
		or string.match(name, '^npc_thd_badguys_.*siege') ~= nil
end

local function EscortRecord(unit)
	return {unit = unit, key = tostring(unit), location = unit:GetLocation(),
		health = unit:GetHealth(), siege = string.find(unit:GetUnitName(), 'siege', 1, true) ~= nil,
		attackTarget = unit:GetAttackTarget()}
end

function Push.SampleEscort(bot, lane, objective)
	local cached = bot.THD_PushEscortSample
	local now = DotaTime()
	if cached ~= nil and cached.objective == objective and cached.lane == lane
	and now - cached.at < EscortConfig.SAMPLE_INTERVAL then return cached end
	local location = objective:GetLocation()
	local botLocation = bot:GetLocation()
	local botAmount = GetAmountAlongLane(lane, botLocation).amount
	local goalAmount = GetAmountAlongLane(lane, location).amount
	local direction = bot:GetTeam() == TEAM_RADIANT and 1 or -1
	cached = {at = now, objective = objective, lane = lane, allied = {}, enemy = {}, creepDistance = math.huge}
	local function InLane(unit, allied)
		if not EscortLaneCreep(unit) then return false end
		local point = unit:GetLocation()
		if Geometry.Distance(point, location) > EscortConfig.LOCAL_RANGE
		and Geometry.Distance(point, botLocation) > EscortConfig.LOCAL_RANGE then return false end
		local along = GetAmountAlongLane(lane, point)
		if along.distance > EscortConfig.LANE_WIDTH then return false end
		for _, otherLane in ipairs({LANE_TOP, LANE_MID, LANE_BOT}) do
			if otherLane ~= lane and GetAmountAlongLane(otherLane, point).distance + 50 < along.distance then return false end
		end
		if allied then
			local old = bot.THD_PushEscort
			local retained = old and old.wave and old.wave.members[unit] ~= nil
			-- 已追踪的同一波可以继续保留；新波仅取本方向、未越过目标的单位。
			if not retained and ((along.amount-botAmount)*direction < -0.08
			or (goalAmount-along.amount)*direction < -0.02) then return false end
		end
		return true
	end
	-- 替代原 Think 中无节流的最近小兵全表扫描，快照只保留局部单位。
	for _, creep in pairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS)) do
		if InLane(creep, true) then
			table.insert(cached.allied, EscortRecord(creep))
			cached.creepDistance = math.min(cached.creepDistance, GetUnitToUnitDistance(creep, objective))
		end
	end
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(1600, true)) do
		if InLane(creep, false) and J.CanBeAttacked(creep) then table.insert(cached.enemy, EscortRecord(creep)) end
	end
	bot.THD_PushEscortSample = cached
	return cached
end

local function EscortProtectionReason(target)
	if not EscortVisible(target) then return 'unseen_building' end
	if Push.HasDefenseGlyphBuff(target) then return 'glyph' end
	if target:HasModifier('modifier_backdoor_protection') or target:HasModifier('modifier_backdoor_protection_in_base')
	or target:HasModifier('modifier_backdoor_protection_active') then return 'native_backdoor' end
	if Push.IsAntiBackdoorStopBuilding(target) and not target:HasModifier('modifier_thdots_anti_bd_stop') then return 'custom_backdoor' end
	return 'open'
end

local function EscortMovementSafety(bot, objective, wave, authorized, protection)
	local observation = TowerSafety.Observe(bot, 'push_escort')
	local result = {available = observation.available, zones = {}}
	local keys = {tostring(objective.id),tostring(protection),tostring(authorized == true)}
	if not observation.available then result.key = table.concat(keys,'|'); return result end
	local towers = {}
	for _, tower in ipairs(observation.towers) do
		local isTarget = Geometry.Distance(tower.center, objective.target:GetLocation()) < 64
		local covered = false
		if isTarget and EscortVisible(objective.target) and not tower.locked and wave ~= nil then
			covered = wave.members[objective.target:GetAttackTarget()] ~= nil
		end
		-- 仅已有授权或实际兵线承伤的目标塔可例外；其他塔仍检查完整路径。
		local exempt = isTarget and protection == 'open' and (authorized or covered)
		table.insert(towers,tostring(tower.key)..':'..tostring(tower.radius)..':'..tostring(tower.locked)..':'..tostring(exempt == true))
		if not exempt then
			table.insert(result.zones, tower)
		end
	end
	-- 只记录改变安全判定的离散状态，不因时间戳/兵量小幅变化刷新失败缓存。
	table.sort(towers)
	result.key = table.concat(keys,'|')..'|'..table.concat(towers,'|')
	return result
end

local function EscortSafeLocation(bot, location, movementSafety, navigation, recoveryStep)
	if location == nil then return false, 'missing_location' end
	if Geometry.Distance(bot:GetLocation(), location) > 1400 then return false, 'beyond_local_range' end
	if not movementSafety.available then return false, 'tower_snapshot_unavailable' end
	local zones = movementSafety.zones
	local origin = bot:GetLocation()
	local valid, reason, zone
	if recoveryStep then
		-- 短恢复步可单调离开已有危险区，但不能穿入其他塔区。
		valid,reason,zone = Geometry.ValidateRecoverySegment(origin,location,zones,96)
	else valid,reason,zone = Geometry.ValidateMovementSegment(origin,location,zones,96) end
	if not valid then return false, 'tower_'..tostring(reason), zone and zone.key end
	if not IsLocationPassable(location) then return false,'impassable_goal' end
	if not IsLocationVisible(location) then return false,'unseen_goal' end
	local steps = math.max(1, math.ceil(Geometry.Distance(origin, location)/180))
	for i = 1, steps do
		local point = origin + (location-origin)*(i/steps)
		-- 普通MoveTo由引擎绕过地形；短恢复步/战斗接近仍要求直线可行。
		if not navigation and not IsLocationPassable(point) then return false, 'impassable_segment', tostring(i)..'/'..tostring(steps) end
		if not IsLocationVisible(point) then return false, 'unseen_segment', tostring(i)..'/'..tostring(steps) end
	end
	return true
end

local function EscortApproachLocations(bot, lane, destination)
	local origin = bot:GetLocation()
	local along = GetAmountAlongLane(lane,origin)
	local target = GetAmountAlongLane(lane,destination)
	local direction = target.amount >= along.amount and 1 or -1
	local function LanePoint(amount) return GetLocationAlongLane(lane,math.max(0,math.min(1,amount))) end
	local amount = along.amount
	if along.distance <= 300 then amount = amount + direction*math.min(0.015,math.abs(target.amount-amount)) end
	local anchor = LanePoint(amount)
	local candidates = {anchor, LanePoint(amount+direction*0.008), LanePoint(amount-direction*0.008)}
	-- 先接入所在分路，再沿路前进；局部障碍只尝试有界扇形步，不切跨地图直线。
	local delta = anchor-origin
	local length = Geometry.Distance(origin,anchor)
	if length > 180 then
		for _, step in ipairs({EscortConfig.APPROACH_STEP, EscortConfig.APPROACH_STEP/2}) do
			for _, degrees in ipairs({0,35,-35,70,-70}) do
				local angle = math.rad(degrees)
				local x,y = delta.x/length,delta.y/length
				local point = Vector(origin.x+(x*math.cos(angle)-y*math.sin(angle))*math.min(step,length),
					origin.y+(x*math.sin(angle)+y*math.cos(angle))*math.min(step,length),origin.z)
				if Geometry.Distance(point,anchor) <= length-24 then table.insert(candidates,point) end
			end
		end
	end
	return candidates
end

local function EscortFormationLocations(state, lane, objective)
	local candidates = {state.guardLocation}
	for _, point in ipairs(state.fallbacks or {}) do table.insert(candidates,point) end
	local center = state.guardLocation
	if center == nil then return candidates end
	local amount = GetAmountAlongLane(lane,center).amount
	for _, offset in ipairs({0,0.008,-0.008}) do
		table.insert(candidates,GetLocationAlongLane(lane,math.max(0,math.min(1,amount+offset))))
	end
	local delta = objective.target:GetLocation()-center
	local length = math.max(1,Geometry.Distance(center,objective.target:GetLocation()))
	for _, scale in ipairs({1,-1,2,-2}) do
		table.insert(candidates,Vector(center.x-delta.y/length*EscortConfig.FORMATION_SIDE_STEP*scale,
			center.y+delta.x/length*EscortConfig.FORMATION_SIDE_STEP*scale,center.z))
	end
	return candidates
end

local function SelectDefenderContact(bot,lane,objective,alliedRecords,enemies)
	if J.GetHP(bot) < EscortConfig.MIN_PRESSURE_HP or DotaTime() < (bot.THD_PushFightRetryAt or -90) then return nil end
	if GetUnitToUnitDistance(bot,objective.target) > EscortConfig.LOCAL_RANGE then return nil end
	local pressure = bot.THD_PushPressure
	local forceFight = pressure ~= nil and pressure.lane == lane and pressure.ready
		and DotaTime()-pressure.at <= EscortConfig.CONTEXT_TTL
	local members = {}
	for _, creep in ipairs(alliedRecords) do members[creep.unit] = true end
	local best, bestRank, bestDistance = nil,math.huge,math.huge
	for _, enemy in ipairs(enemies) do
		if LiveEnemy(bot,enemy) and GetUnitToUnitDistance(enemy,objective.target) <= EscortConfig.LOCAL_RANGE then
			local victim = enemy:GetAttackTarget()
			local attacksAlly = EscortVisible(victim) and victim:IsHero() and victim:GetTeam() == bot:GetTeam()
			local distance = GetUnitToUnitDistance(bot,enemy)
			local rank = attacksAlly and 0 or (members[victim] and 1
				or (forceFight and GetUnitToUnitDistance(enemy,objective.target) <= EscortConfig.CONTACT_RADIUS and 2 or nil))
			if rank ~= nil and distance <= EscortConfig.CONTACT_RADIUS
			and (rank < bestRank or (rank == bestRank and distance < bestDistance)) then
				best,bestRank,bestDistance = enemy,rank,distance
			end
		end
	end
	return best, bestRank == 0 and 'ally_under_attack' or (bestRank == 1 and 'wave_under_attack' or 'advantage_defender')
end

local function LogEscort(bot, state, reason)
	if not EscortConfig.DEBUG then return end
	local now = DotaTime()
	local signature = tostring(state.objectiveID)..':'..tostring(state.phase)..':'..tostring(state.threat)..':'..tostring(reason)
		..':'..tostring(state.result)..':'..tostring(state.operation)
	local log = bot.THD_PushEscortLog or {}
	if signature == log.signature and now-(log.at or -90) < EscortConfig.LOG_INTERVAL then return end
	bot.THD_PushEscortLog = {signature = signature, at = now}
	print(string.format('[BOT][PushEscort] run=%s pid=%s time=%.2f objective=%s lane=%s role=%s phase=%s reason=%s wave=%s count=%s hp=%s loss=%s threat=%s protection=%s mode=%s desire=%.3f deadline=%s tower_damage=%s intent=%s front_x=%s front_y=%s under_pressure=%s',
		EscortConfig.RUN_ID, bot:GetPlayerID(), now, tostring(state.objectiveID), tostring(state.lane), tostring(state.role),
		tostring(state.phase), tostring(reason), tostring(state.wave and state.wave.id), tostring(state.wave and state.wave.count),
		tostring(state.wave and state.wave.health), tostring(state.waveLoss), tostring(state.threat), tostring(state.protectionReason),
		tostring(bot:GetActiveMode()), bot:GetActiveModeDesire(), tostring(state.untilAt), tostring(state.towerDamage),
		tostring(state.intent), tostring(state.wave and state.wave.front.x), tostring(state.wave and state.wave.front.y),
		tostring(state.wave and state.wave.underPressure))
		..string.format(' result=%s operation=%s action_target=%s bot_x=%.1f bot_y=%.1f goal_x=%s goal_y=%s rejects=%s continuation_reason=%s maintainer=%s continuation_until=%s continuation_safe_until=%s move_issued=%s route=%s strategic_count=%s local_count=%s threat_reason=%s pressure_reason=%s visible_enemies=%s near_enemies=%s wave_attackers=%s',
			tostring(state.result),tostring(state.operation),tostring(state.actionTarget):gsub('%s','_'),
			bot:GetLocation().x,bot:GetLocation().y,tostring(state.actionLocation and state.actionLocation.x),
			tostring(state.actionLocation and state.actionLocation.y),table.concat(state.rejects or {},'|'),
			tostring(state.continuationReason),tostring(state.maintainerID),tostring(state.continuationUntil),tostring(state.continuationSafeUntil),
			tostring(state.moveIssued),tostring(state.moveRoute),tostring(state.strategicCount),tostring(state.localCount),
			tostring(state.threatObservation and state.threatObservation.reason),tostring(state.pressureReason),
			tostring(state.threatObservation and state.threatObservation.visible),tostring(state.threatObservation and state.threatObservation.near),
			tostring(state.threatObservation and state.threatObservation.attackingWave))
		..' path_policy='..tostring(state.pathPolicy))
end

function Push.TryEscort(bot, lane, objective, sample, allies, enemies, safety, authorized)
	if not EscortConfig.PUSH_ESCORT_ENABLED or objective == nil
	or not Wasteland.IsPushObjectiveParticipant(bot, objective) then return false end
	-- 即使自定义撤退框架关闭，护线也必须使用真实的只读三秒塔伤预测。
	local tower = J.Retreat.GetTowerThreat(bot, 3.0, nil, true)
	local safe = #allies >= #enemies and (#enemies == 0 or SumLocalCombatPower(allies) >= SumLocalCombatPower(enemies))
		and not tower.unseenIncoming and (tower.unavoidableDamage or 0) < bot:GetHealth()
		and (tower.predictedDamage or 0)/math.max(1,bot:GetHealth()) < EscortConfig.MAX_TOWER_DAMAGE_RATIO
		and (safety.severity < J.Retreat.HIGH or authorized)
	if not safe then
		if bot.THD_PushEscort ~= nil then
			bot.THD_PushEscort.result,bot.THD_PushEscort.operation = 'released','none'
			bot.THD_PushEscort.actionTarget,bot.THD_PushEscort.actionLocation = nil,nil
			bot.THD_PushEscort.moveIssued,bot.THD_PushEscort.moveRoute = nil,nil
			LogEscort(bot,bot.THD_PushEscort,'unsafe')
		end
		Escort.Release(bot, 'unsafe')
		Wasteland.NoteEscortTactic(bot, objective, nil)
		Tasks.Release(bot,TaskName(lane),'escort_unsafe',0.75)
		return true
	end
	local now, old = DotaTime(), bot.THD_PushEscort
	local records, alliedRecords, enemyRecords = {}, {}, {}
	for _, enemy in ipairs(enemies) do if EscortVisible(enemy) then table.insert(records, EscortRecord(enemy)) end end
	for _, creep in ipairs(sample.allied) do
		if EscortVisible(creep.unit) then
			local retained = old ~= nil and old.wave ~= nil and old.wave.members[creep.unit] ~= nil
			local range = retained and EscortConfig.LOCAL_RETAIN_RANGE or EscortConfig.LOCAL_JOIN_RANGE
			if GetUnitToUnitDistance(bot,creep.unit) <= range then table.insert(alliedRecords, EscortRecord(creep.unit)) end
		end
	end
	for _, creep in ipairs(sample.enemy) do
		if EscortVisible(creep.unit) and J.CanBeAttacked(creep.unit) then table.insert(enemyRecords, EscortRecord(creep.unit)) end
	end
	local loss = 'unobserved'
	if old ~= nil and old.wave ~= nil then
		loss = 'confirmed_dead'
		for unit in pairs(old.wave.members) do
			if unit ~= nil and not unit:IsNull() and (not unit:CanBeSeen() or unit:IsAlive()) then loss = 'out_of_view_or_area' end
		end
	end
	local protection = EscortProtectionReason(objective.target)
	local sharedContinuation, mustRegroup, continuationReason = Wasteland.GetEscortContinuation(objective)
	local currentCreepSupport = false
	for _, creep in ipairs(sample.allied) do
		if EscortVisible(creep.unit) and GetUnitToUnitDistance(creep.unit,objective.target) <= 850
		and not creep.unit:HasModifier('modifier_thdots_unit_anti_bd') then currentCreepSupport = true; break end
	end
	local localObjective = GetUnitToUnitDistance(bot,objective.target) <= EscortConfig.LOCAL_JOIN_RANGE
	local continuation = sharedContinuation and localObjective
	local movementAuthorization = authorized or continuation
	local approachLocation = GetLaneFrontLocation(GetTeam(),lane,-600)
	local approach = #alliedRecords == 0 and not continuation
		and GetUnitToUnitDistance(bot,objective.target) > EscortConfig.LOCAL_JOIN_RANGE
		and Geometry.Distance(bot:GetLocation(),approachLocation) > 180
	local state, decision = Escort.Evaluate({now = now, sampledAt = sample.at, objectiveID = objective.id, lane = lane,
		approach = approach, approachLocation = approachLocation,
		role = Wasteland.GetPushObjectiveRole(bot, objective), playerID = bot:GetPlayerID(), botLocation = bot:GetLocation(),
		objectiveLocation = objective.target:GetLocation(), attackRange = bot:GetAttackRange(),
		alliedCreeps = alliedRecords, enemyCreeps = enemyRecords, enemies = records, waveLoss = loss,
		blockerDead = old ~= nil and old.blocker ~= nil and not old.blocker:IsNull() and old.blocker:CanBeSeen() and not old.blocker:IsAlive(),
		pressureSafe = J.GetHP(bot) >= EscortConfig.MIN_PRESSURE_HP,
		supplementSafe = #enemies == 0,
		canSiege = localObjective and protection == 'open' and J.CanBeAttacked(objective.target)
			and Wasteland.CanAttackPushObjective(bot,lane,objective.target,objective)
			and (currentCreepSupport or continuation),
		creepSupport = currentCreepSupport,
		continuation = continuation, mustRegroup = mustRegroup,
		continuationUntil = objective.escortBreakAt and objective.escortBreakAt + EscortConfig.CONTINUATION_DURATION,
		regroupLocation = GetLaneFrontLocation(GetTeam(), lane, -600)}, old)
	state.protectionReason = protection
	state.strategicCount,state.localCount = #sample.allied,#alliedRecords
	state.towerDamage, state.intent = tower.predictedDamage, decision.kind
	local recovery = PushMovement.NeedsRecovery(bot)
	local contact,contactReason = SelectDefenderContact(bot,lane,objective,alliedRecords,enemies)
	if contact ~= nil and state.role == 'building_damage' and decision.kind == 'building'
	and contactReason ~= 'ally_under_attack' then
		-- 有可执行的前排/掩护响应者时，主要输出位继续制造建筑压力，避免全队追一个守军。
		for _, assigned in ipairs(objective.participants or {}) do
			local member = assigned.unit
			if member ~= bot and (assigned.role == 'frontline' or assigned.role == 'cover')
			and EscortVisible(member) and J.GetHP(member) >= EscortConfig.MIN_PRESSURE_HP
			and not J.Retreat.ShouldYield(member,J.Retreat.HIGH)
			and GetUnitToUnitDistance(member,contact) <= EscortConfig.CONTACT_RADIUS then contact = nil; break end
		end
	end
	if contact ~= nil then
		local previous = bot.THD_PushFightIntent
		local deadline = previous and previous.objectiveID == objective.id and previous.untilAt or now+EscortConfig.HANDOFF_DURATION
		state.phase,state.reason,state.untilAt = 'CONTACT','defender_contact',deadline
		state.threat,state.pressureReason = contact,contactReason
		decision = {kind='attack',target=contact,location=contact:GetLocation(),reason='defender_contact',untilAt=deadline}
		state.intent = 'attack'
	end
	state.result,state.operation,state.actionTarget,state.actionLocation,state.rejects = 'pending','none',nil,nil,{}
	state.pathPolicy = 'none'
	state.moveIssued,state.moveRoute = nil,nil
	state.continuationReason = continuationReason
	state.maintainerID = objective.escortLastMaintainerID
	state.continuationUntil = objective.escortBreakAt and objective.escortBreakAt + EscortConfig.CONTINUATION_DURATION
	state.continuationSafeUntil = objective.escortContinuationSafeUntil
	local participant = objective.participantByID[bot:GetPlayerID()]
	if state.role == 'frontline' and not participant.frontlineProfile then
		-- 位置分工不等于坦克能力：没有明确前排 profile 时必须有真实兵线承伤。
		movementAuthorization = continuation
	end
	local movementSafety = EscortMovementSafety(bot,objective,state.wave,movementAuthorization,protection)
	bot.THD_PushEscort = state
	Wasteland.NoteEscortTactic(bot, objective, state)
	local function Release(reason)
		state.result,state.operation = 'released','none'
		LogEscort(bot, state, reason)
		if reason == 'no_safe_action' then
			PushMovement.NoPath(bot)
			-- 路径暂不可用只释放动作任务，保留波次和已消费的压制期限，避免重试重置。
			state.expiresAt = now
		else Escort.Release(bot, reason) end
		Wasteland.NoteEscortTactic(bot, objective, nil)
		Tasks.Release(bot,TaskName(lane),reason,EscortConfig.RETRY_DELAY)
		bot.THD_PushEscortRetryAt, bot.THD_PushEscortRetryLane = now+EscortConfig.RETRY_DELAY, lane
		if reason == 'regroup_timeout' or reason == 'continuation_closed' then Wasteland.ReleasePushObjective(reason, bot) end
		return true
	end
	local function Reject(stage,reason,point,detail)
		if #state.rejects >= 8 then return end
		local where = point and string.format('%.0f,%.0f',point.x,point.y) or 'nil'
		local rejection = (stage..':'..tostring(reason)..':'..tostring(detail or '-')..'@'..where):gsub('%s','_')
		table.insert(state.rejects,rejection)
	end
	local function Check(point,stage)
		local navigation = not recovery and not string.find(stage,'detour',1,true)
			and (string.find(stage,'^approach_') or string.find(stage,'^formation_'))
			and point ~= nil and Geometry.Distance(bot:GetLocation(),point) > EscortConfig.NAVIGATION_MIN_DISTANCE
		state.pathPolicy = navigation and 'native_navigation' or 'direct_segment'
		local blocked,failedReason = false,nil
		if point ~= nil then blocked,failedReason = PushMovement.Blocked(bot,point,navigation,movementSafety.key) end
		if blocked then Reject(stage,'recent_failed_goal',point,failedReason); return false end
		local recoveryStep = string.find(stage,'^recovery_') ~= nil
		local allowed,reason,detail = EscortSafeLocation(bot,point,movementSafety,navigation,recoveryStep)
		if not allowed then
			Reject(stage,reason,point,detail)
			-- 超出局部范围不是坏路点，不把战略目标永久当作地形障碍。
			if reason ~= 'beyond_local_range' and reason ~= 'tower_snapshot_unavailable' then PushMovement.Reject(bot,point,reason,movementSafety.key) end
		end
		return allowed
	end
	local function Accepted(operation,target,point,purpose)
		-- accepted可包含复用现有动作，不表示本帧新发单、命中或造成伤害。
		if decision.reason == 'defender_contact' and (operation == 'attack_unit' or (operation == 'move' and purpose == 'attack')) then
			local previous = bot.THD_PushFightIntent
			if previous == nil or previous.objectiveID ~= objective.id then
				bot.THD_PushFightIntent = {objectiveID=objective.id,lane=lane,target=decision.target,untilAt=state.untilAt}
			else previous.target = decision.target end
			J.SetTargetIfChanged(bot,decision.target,0.2)
		end
		state.result,state.operation,state.actionTarget,state.actionLocation = 'accepted',operation,target,point
		LogEscort(bot,state,decision.reason)
		return true
	end
	local function Move(point,tolerance,stage)
		if PushMovement.Hold(bot,point,tolerance,objective.id) then
			state.moveIssued,state.moveRoute = false,'already_in_position'
			return Accepted('hold',nil,point,stage)
		end
		local feedback = {}
		local accepted = J.ActionMoveToLocation(bot,'lane_work_push_escort',point,0.25,tolerance,
			function(goal) return Check(goal,stage..'_detour') end,feedback)
		state.moveIssued,state.moveRoute = feedback.issued,feedback.route
		if accepted then
			PushMovement.Accept(bot,feedback.location or point,feedback.route == 'detour' and 24 or tolerance,objective.id)
			return Accepted('move',nil,feedback.location or point,stage)
		end
		Reject(stage,J.CanNotUseAction(bot) and 'action_protected' or feedback.reason or 'move_submit_rejected',feedback.location or point,feedback.route)
		return false
	end
	if decision.kind == 'release' then return Release(decision.reason) end
	local immediateAttack = decision.kind == 'building' and GetUnitToUnitDistance(bot,objective.target) <= bot:GetAttackRange()+25
		or decision.kind == 'attack' and EscortVisible(decision.target) and GetUnitToUnitDistance(bot,decision.target) <= bot:GetAttackRange()+25
	if recovery and not immediateAttack then
		-- 实际无位移时先尝试短恢复步；不让同一建筑的编队点覆盖恢复预算。
		for index,point in ipairs(PushMovement.Candidates(bot)) do
			if Check(point,'recovery_'..index) and Move(point,48,'recovery_'..index) then return true end
		end
		return Release('no_safe_action')
	end
	if decision.kind == 'building' then
		local center, current = objective.target:GetLocation(), bot:GetLocation()
		local goal = center + (current-center):Normalized()*math.max(100,bot:GetAttackRange()-75)
		local inRange = GetUnitToUnitDistance(bot,objective.target) <= bot:GetAttackRange()+25
		-- 已有合法输出不需要重新进入塔圈；本帧即时塔伤/权限门仍然必须成立。
		local holding = inRange and bot:GetCurrentActionType() == BOT_ACTION_TYPE_ATTACK
			and bot:GetAttackTarget() == objective.target and not Push.HasBackdoorProtect(objective.target)
			and Push.CanAttackManagedBuilding(bot,lane,objective.target,objective)
		if holding or Check(inRange and current or goal,'building') then
			if inRange then
				if Push.TryAttackObjectiveBuilding(bot,lane,objective,objective.target,bot:GetAttackRange(),'push_escort_building') then return Accepted('attack_building',objective.target,current) end
				Reject('building',J.CanNotUseAction(bot) and 'action_protected' or 'building_permission_or_submit_rejected',current)
			elseif Move(goal,80,'building') then return true end
		end
	end
	if decision.kind == 'attack' and EscortVisible(decision.target) and J.CanBeAttacked(decision.target) then
		local targetLocation = decision.target:GetLocation()
		local distance = Geometry.Distance(bot:GetLocation(), targetLocation)
		local goal = targetLocation + (bot:GetLocation()-targetLocation):Normalized()*math.max(100,bot:GetAttackRange()-50)
		local inRange = distance <= bot:GetAttackRange()+25
		-- 已在射程内不检查虚构的更远站位；距离外只能通过已验证的移动接近。
		if Check(inRange and bot:GetLocation() or goal,'attack') then
			if inRange then
				J.SetTargetIfChanged(bot, decision.target, 0.2)
				if J.ActionAttackUnit(bot,'push_escort_'..decision.reason,decision.target,true,0.25) then return Accepted('attack_unit',decision.target,bot:GetLocation()) end
				Reject('attack',J.CanNotUseAction(bot) and 'action_protected' or 'attack_submit_rejected',bot:GetLocation())
			elseif Move(goal,80,'attack') then return true end
		end
	end
	if decision.kind == 'attack' and not EscortVisible(decision.target) then Reject('attack','target_lost',nil) end
	local locations = state.phase == 'APPROACH' and EscortApproachLocations(bot,lane,approachLocation)
		or EscortFormationLocations(state,lane,objective)
	local tried = {}
	for index, point in ipairs(locations) do
		local stage = (state.phase == 'APPROACH' and 'approach_' or 'formation_')..index
		-- 远处编队点先化为局部接近步，每步仍检查视野、地形和所有未豁免塔区。
		local origin = bot:GetLocation()
		local distance = Geometry.Distance(origin,point)
		if distance > 1400 then
			point = origin+(point-origin):Normalized()*EscortConfig.APPROACH_STEP
			stage = stage..'_local_step'
		end
		local key = string.format('%.0f:%.0f',point.x/32,point.y/32)
		if not tried[key] and (state.phase ~= 'APPROACH' or Geometry.Distance(bot:GetLocation(),point) > 120) then
			tried[key] = true
			if Check(point,stage) then
				if Move(point,120,stage) then return true end
			end
		end
	end
	return Release('no_safe_action')
end

function Push.PushThink(bot, lane)
	PushMovement.Observe(bot)
	if PushMovement.Yielding(bot) then Tasks.Release(bot,TaskName(lane),'physical_stall'); return end
	local task=Tasks.Commit(bot,TaskName(lane))
	if not Tasks.Check(bot,TaskName(lane),task~=nil and Push.IsObjectiveValid(task.objective)) then return end
    if not Timer.ShouldRunBotTask(bot, 'push_think_'..tostring(lane), 0.25, 0.03) then return end
	if J.CanNotUseAction(bot) then return end
	if LaneWork.TryThink(bot, lane) then return end
	local hEnemyAncient = GetAncient(GetOpposingTeam())
	local wastelandState = Wasteland.IsEnabled() and Wasteland.GetState() or nil
	local baseThreat = wastelandState ~= nil and Wasteland.GetBaseThreatSnapshot(wastelandState, bot) or nil
	if Wasteland.IsEnabled()
	and baseThreat ~= nil
	and baseThreat.hardEmergency == true
	and Wasteland.InvalidateObjectiveForBaseDefense(bot, baseThreat)
	then
		-- 基地出现防守压力时先释放统一目标；本帧不再沿用缓存中的推进模式下单。
		return
	end
	if Wasteland.IsEnabled() and baseThreat ~= nil and baseThreat.hardEmergency == true then return end
	if not Wasteland.IsEnabled() then
		local immediateSafety = Push.GetImmediateSafetyState(bot)
		if Wasteland.InvalidateObjectiveForBaseDefense(
			bot, (immediateSafety.baseEnemyPressure or 0) > 0)
		then
			return
		end
	end
	local pushObjective = Wasteland.GetPushObjective()
	if pushObjective ~= nil and (tonumber(pushObjective.tier) or 1) >= 3 then
		local allowed, reason = Wasteland.ValidatePushObjectiveHighGround(bot, pushObjective)
		if not allowed then
			local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
			J.ActionMoveToLocation(bot, 'push_high_ground_exception_lost_' .. tostring(reason), vLocation, 0.25, 260)
			return
		end
	end
	local retreatState = J.Retreat.GetState(bot)
	local highGroundAuthorizationCandidate = Wasteland.GetHighGroundAssaultAuthorization ~= nil
		and Wasteland.GetHighGroundAssaultAuthorization(bot, pushObjective) or nil
	local highGroundSafetyState = highGroundAuthorizationCandidate ~= nil
		and Push.BuildHighGroundAssaultSafetyState(bot, retreatState) or {
			severity = retreatState.severity or J.Retreat.NONE,
			contextRawSeverity = retreatState.contextRawSeverity or J.Retreat.NONE,
			allyCount = retreatState.allyCount or 0,
			enemyCount = retreatState.enemyCount or 0,
			towerThreat = retreatState.towerThreat or {},
		}
	local highGroundAssaultAllowed, highGroundAuthorization, highGroundDenialReason = Push.CanMaintainHighGroundAssault(
		bot, pushObjective, highGroundSafetyState)
	if highGroundAssaultAllowed and highGroundAuthorization ~= nil then
		highGroundAuthorization.expiresAt = DotaTime() + PUSH_HIGH_GROUND_ASSAULT_AUTH_TTL
		bot.THD_HighGroundAssaultAuthorization = highGroundAuthorization
	else
		bot.THD_HighGroundAssaultAuthorization = nil
	end
	if highGroundAuthorizationCandidate ~= nil and not highGroundAssaultAllowed then
		-- 已解锁高地的短租约一旦触发安全门，本帧立即退出，不能等模式缓存自然切走。
		if Wasteland.NoteHighGroundAssaultDecision ~= nil then
			Wasteland.NoteHighGroundAssaultDecision(bot, pushObjective, 'safety_cancel',
				string.format('reason=%s hp=%.3f allies=%s enemies=%s severity=%s raw_severity=%s',
					tostring(highGroundDenialReason), J.GetHP(bot),
					tostring(highGroundSafetyState.allyCount or 0),
					tostring(highGroundSafetyState.enemyCount or 0),
					tostring(highGroundSafetyState.severity or 0),
					tostring(highGroundSafetyState.contextRawSeverity or 0)))
			if highGroundDenialReason == 'outnumbered' then
				Wasteland.NoteHighGroundAssaultDecision(bot, pushObjective, 'yield_outnumbered',
					'allies=' .. tostring(highGroundSafetyState.allyCount or 0)
						.. ' enemies=' .. tostring(highGroundSafetyState.enemyCount or 0))
			end
		end
		local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
		J.ActionMoveToLocation(bot,
			'push_high_ground_safety_cancel_' .. tostring(highGroundDenialReason or 'unknown'),
			vLocation, 0.35, 260)
		return
	end
	local conversionUnsafe, conversionReason = Wasteland.ShouldWithdrawConversionPush(
		bot, highGroundSafetyState.towerThreat, pushObjective)
	if conversionUnsafe then
		bot.THD_HighGroundAssaultAuthorization = nil
		if Wasteland.NoteConversionWithdrawal ~= nil then
			Wasteland.NoteConversionWithdrawal(bot, conversionReason, pushObjective)
		end
		local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
		J.ActionMoveToLocation(bot, 'push_flee_conversion_' .. tostring(conversionReason or 'safety'), vLocation, 0.25, 260)
		return
	end
	if highGroundSafetyState.severity >= J.Retreat.HIGH and not highGroundAssaultAllowed then
		bot.THD_HighGroundAssaultAuthorization = nil
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
	local laneBuildingTier = Push.GetLaneBuildingTier(lane)

    local botAttackRange = bot:GetAttackRange()
    local fDeltaFromFront = (Min(J.GetHP(bot), 0.7) * 1000 - 700) + RemapValClamped(botAttackRange, 300, 700, 0, -600)
    local nEnemyTowers = bot:GetNearbyTowers(1600, true)
    local nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)

	local hLaneBuildingTarget = task.objective
	local candidateTarget = hLaneBuildingTarget or hEnemyAncient
	if wastelandState ~= nil and laneBuildingTier >= 3 and Push.IsObjectiveValid(candidateTarget) then
		wastelandState.highGroundContext = Wasteland.GetHighGroundPermissionContext(candidateTarget, {
			averageLevel = wastelandState.allyAverageLevel,
		})
	end
	if wastelandState ~= nil and Wasteland.ObserveOuterTowerSnapshot ~= nil then
		Wasteland.ObserveOuterTowerSnapshot(bot, wastelandState)
	end
	if Wasteland.TryCreatePushObjective ~= nil and Push.IsObjectiveValid(candidateTarget) then
		-- 只有真正进入 PushThink 且通过即时安全门后，才创建或升级共享目标。
		pushObjective = Wasteland.TryCreatePushObjective(
			bot, lane, wastelandState, candidateTarget, laneBuildingTier)
	end
	if pushObjective ~= nil
	and (pushObjective.lane ~= lane or not Wasteland.IsPushObjectiveParticipant(bot, pushObjective))
	then
		if Push.HandleNearbyEnemyHeroes(bot, lane, nearbyAllies, nearbyEnemies) then return end
		return
	end
	conversionUnsafe, conversionReason = Wasteland.ShouldWithdrawConversionPush(
		bot, highGroundSafetyState.towerThreat, pushObjective)
	if conversionUnsafe then
		-- gank 击杀转推塔时，不默认当前 Bot 继续吃塔伤；低血量或已被塔锁定都先退出。
		bot.THD_HighGroundAssaultAuthorization = nil
		if Wasteland.NoteConversionWithdrawal ~= nil then
			Wasteland.NoteConversionWithdrawal(bot, conversionReason, pushObjective)
		end
		local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
		J.ActionMoveToLocation(bot, 'push_flee_conversion_' .. tostring(conversionReason or 'safety'), vLocation, 0.25, 260)
		return
	end
    local bLaneBuildingProtected = J.IsValidBuilding(hLaneBuildingTarget)
        and Push.HasBackdoorProtect(hLaneBuildingTarget)
	local observedTarget = pushObjective ~= nil and pushObjective.target or (hLaneBuildingTarget or hEnemyAncient)
	local observedTargetHealth, observedTargetMaxHealth = nil, nil
	local objectiveCreepDistance = math.huge
	local escortSample = nil
	if pushObjective ~= nil and pushObjective.lane == lane and Push.IsObjectiveValid(observedTarget) then
		local objectiveLocation = Push.GetObjectiveLocation(lane, observedTarget)
		observedTargetHealth, observedTargetMaxHealth = J.Utils.GetVisibleHealth(observedTarget)
		local botDistance = GetUnitToUnitDistance(bot, observedTarget)
		local attackableDistance = math.min(1600, botAttackRange + 400)
		if EscortConfig.PUSH_ESCORT_ENABLED then
			escortSample = Push.SampleEscort(bot,lane,observedTarget)
			objectiveCreepDistance = escortSample.creepDistance
			Wasteland.ObserveEscortSupport(bot,pushObjective,escortSample)
		else
			objectiveCreepDistance = GetClosestVisibleCreepDistance(
				UNIT_LIST_ALLIED_CREEPS, objectiveLocation, 5000) or math.huge
		end
		pushObjective = Wasteland.ObservePushObjective(bot, lane, observedTarget, {
			baseThreat = baseThreat,
			hardEmergency = baseThreat ~= nil and baseThreat.hardEmergency == true,
			botDistance = botDistance,
			allyCreepDistance = objectiveCreepDistance,
			targetHealth = observedTargetHealth,
			targetMaxHealth = observedTargetMaxHealth,
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
    and escortSample == nil
    then
		bot.THD_HighGroundAssaultAuthorization = nil
        local vRetreatLocation = GetLaneFrontLocation(GetTeam(), lane, -1800)
        J.ActionMoveToLocation(bot, 'push_retreat_glyphed_tower', vRetreatLocation, 0.45, 260)
        return
    end

	local towerThreat = highGroundSafetyState.towerThreat
	if towerThreat.active
	and not towerThreat.coveredHighGroundLock
	and ((towerThreat.highGroundLock and not highGroundAssaultAllowed)
		or towerThreat.unavoidableDamage >= bot:GetHealth()
		or towerThreat.predictedDamage / math.max(1, bot:GetHealth()) >= PUSH_HIGH_GROUND_MAX_TOWER_DAMAGE_RATIO)
	then
		bot.THD_HighGroundAssaultAuthorization = nil
		local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
		J.ActionMoveToLocation(bot, 'push_flee_tower', vLocation, 0.35, 260)
		return
	end

	-- 安全门之后、旧英雄追击/保护等待之前执行分工，防止输出位随全队追人。
	if escortSample ~= nil and Push.TryEscort(bot,lane,pushObjective,escortSample,
		nearbyAllies,nearbyEnemies,highGroundSafetyState,highGroundAssaultAllowed) then return end

	local forceHighGroundObjective = Push.ShouldForceHighGroundObjective({
		authorized = highGroundAssaultAllowed,
		phase = pushObjective ~= nil and pushObjective.phase or nil,
		role = objectiveRole,
		attackable = Push.IsObjectiveValid(observedTarget)
			and J.IsValidBuilding(observedTarget)
			and J.CanBeAttacked(observedTarget)
			and Push.CanAttackManagedBuilding(bot, lane, observedTarget, pushObjective),
		backdoorProtected = Push.IsObjectiveValid(observedTarget)
			and J.IsValidBuilding(observedTarget) and Push.HasBackdoorProtect(observedTarget),
		botHP = J.GetHP(bot),
		allyCount = #nearbyAllies,
		enemyCount = #nearbyEnemies,
		creepSupport = objectiveCreepDistance <= 850,
		targetHealth = observedTargetHealth,
		targetMaxHealth = observedTargetMaxHealth,
		allyBuildingAttackers = Push.IsObjectiveValid(observedTarget)
			and #Push.GetAllyHeroesAttackingUnit(observedTarget) or 0,
	})
	if forceHighGroundObjective then
		if Push.TryAttackObjectiveBuilding(
			bot, lane, pushObjective, observedTarget, botAttackRange, 'push_force_high_ground_objective') then
			-- 只有实际攻击指令才记 force_building；接近动作使用独立日志。
			Wasteland.NoteHighGroundAssaultDecision(bot, pushObjective, 'force_building',
				string.format('target_hp=%s/%s enemies=%s',
					tostring(observedTargetHealth or 'na'), tostring(observedTargetMaxHealth or 'na'), #nearbyEnemies))
			return
		end
		if Push.TryApproachObjective(bot, lane, pushObjective, observedTarget, botAttackRange, highGroundAssaultAllowed) then return end
	end
	local handledEnemyHeroes, heroResponse = Push.HandleNearbyEnemyHeroes(
		bot, lane, nearbyAllies, nearbyEnemies)
	if handledEnemyHeroes then
		if highGroundAssaultAllowed and Wasteland.NoteHighGroundAssaultDecision ~= nil then
			Wasteland.NoteHighGroundAssaultDecision(bot, pushObjective, heroResponse or 'fight_hero',
				'allies=' .. tostring(#nearbyAllies) .. ' enemies=' .. tostring(#nearbyEnemies))
		end
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
	and Push.CanAttackManagedBuilding(bot, lane, observedTarget, pushObjective)
	and GetUnitToUnitDistance(bot, observedTarget) <= math.min(1600, botAttackRange + 400)
	and Push.TryAttackObjectiveBuilding(
		bot, lane, pushObjective, observedTarget, botAttackRange, 'push_objective_building_damage')
	then
		return
	end

	if objectiveRole == Wasteland.ROLE_BUILDING_DAMAGE
	and Push.TryApproachObjective(bot, lane, pushObjective, observedTarget, botAttackRange, highGroundAssaultAllowed) then return end

	-- 欲望函数只决定优先级；远古目标与所有攻击指令统一在动作阶段下达。
	if Push.IsObjectiveValid(hEnemyAncient)
	and GetUnitToUnitDistance(bot, hEnemyAncient) < PUSH_OBJECTIVE_SNAPSHOT_RANGE * 0.8
	and J.CanBeAttacked(hEnemyAncient)
	and not bot:WasRecentlyDamagedByAnyHero(1)
	and J.GetHP(bot) > 0.5
	and not Push.HasBackdoorProtect(hEnemyAncient)
	and Push.CanAttackManagedBuilding(bot, lane, hEnemyAncient, pushObjective)
	then
		J.SetTargetIfChanged(bot, hEnemyAncient, 0.6)
		if J.ActionAttackUnit(bot, 'push_attack_enemy_ancient', hEnemyAncient, true, 0.45) then
			Push.NoteManagedBuildingAttack(bot, lane, hEnemyAncient, pushObjective)
			return
		end
	end

	if Push.TryAttackLaneBarracks(bot, lane, pushObjective) then return end

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
        if hBuildingTarget and Push.CanAttackManagedBuilding(bot, lane, hBuildingTarget, pushObjective) then
            hBuildingTarget = J.GetStickyTarget(bot, 'push_clear_other_high_ground', hBuildingTarget, 1.5, 2200)
			if Push.CanAttackManagedBuilding(bot, lane, hBuildingTarget, pushObjective)
			and J.ActionAttackUnit(bot, 'push_clear_other_high_ground', hBuildingTarget, true, 0.45)
			then
				Push.NoteManagedBuildingAttack(bot, lane, hBuildingTarget, pushObjective)
				return
			end
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
	and Push.CanAttackManagedBuilding(bot, lane, hEnemyAncient, pushObjective)
	then
		if J.ActionAttackUnit(bot, 'push_attack_enemy_ancient', hEnemyAncient, true, 0.45) then
			Push.NoteManagedBuildingAttack(bot, lane, hEnemyAncient, pushObjective)
			return
		end
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

	-- 先使用共享目标，避免普通选塔挑中另一座 T4 后被 exact-target 许可拒绝。
	if highGroundAssaultAllowed and pushObjective ~= nil then
		if Push.TryAttackObjectiveBuilding(bot, lane, pushObjective, observedTarget, botAttackRange) then return end
		if Push.TryApproachObjective(bot, lane, pushObjective, observedTarget, botAttackRange, true) then return end
		Wasteland.NoteHighGroundAssaultDecision(bot, pushObjective, 'objective_action_blocked',
			string.format('visible=%s backdoor=%s distance=%.1f phase=%s',
				tostring(J.IsValidBuilding(observedTarget)), tostring(Push.HasBackdoorProtect(observedTarget)),
				GetUnitToUnitDistance(bot, observedTarget), tostring(pushObjective.phase)))
	end

    if J.IsValidBuilding(nEnemyTowers[1]) and J.CanBeAttacked(nEnemyTowers[1]) and not Push.HasBackdoorProtect(nEnemyTowers[1]) then
        local hTowerTarget = nil
        local hTowerTargetDistance = math.huge
        for _, tower in pairs(nEnemyTowers) do
            if J.IsValidBuilding(tower) and J.CanBeAttacked(tower) and not Push.HasBackdoorProtect(tower)
			and Push.CanAttackManagedBuilding(bot, lane, tower, pushObjective) then
                local towerDistance = GetUnitToLocationDistance(tower, targetLoc)
                if towerDistance < hTowerTargetDistance then
                    hTowerTarget = tower
                    hTowerTargetDistance = towerDistance
                end
            end
        end

		if hTowerTarget and Push.CanAttackManagedBuilding(bot, lane, hTowerTarget, pushObjective) then
			hTowerTarget = J.GetStickyTarget(bot, 'push_tower', hTowerTarget, 1.8, nRange + 300)
			if Push.CanAttackManagedBuilding(bot, lane, hTowerTarget, pushObjective)
			and J.ActionAttackUnit(bot, 'push_attack_tower', hTowerTarget, true, 0.45)
			then
				Push.NoteManagedBuildingAttack(bot, lane, hTowerTarget, pushObjective)
				return
			end

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

        if hTowerFillerTarget
		and Push.CanAttackManagedBuilding(bot, lane, hTowerFillerTarget, pushObjective)
		then
            hTowerFillerTarget = J.GetStickyTarget(bot, 'push_filler', hTowerFillerTarget, 1.8, nRange + 300)
			if Push.CanAttackManagedBuilding(bot, lane, hTowerFillerTarget, pushObjective)
			and J.ActionAttackUnit(bot, 'push_attack_filler', hTowerFillerTarget, true, 0.45)
			then
				Push.NoteManagedBuildingAttack(bot, lane, hTowerFillerTarget, pushObjective)
				return
			end

        end
    end

    if GetUnitToLocationDistance(bot, targetLoc) > 500 then
        J.ActionMoveToLocation(bot, 'push_move_lane_front', targetLoc, 0.5, 220)
        return

    else
        if DotaTime() >= fNextMovementTime then
			local canAttackMove = Wasteland.CanHeroUseAttackMove(bot, lane, laneBuildingTier)
			if not canAttackMove then
				-- 无有效共享窗口时只移动，避免 AttackMove 自动索敌绕过建筑许可。
				J.ActionMoveToLocation(bot, 'push_stage_lane_front', targetLoc, 0.5, 260)
				fNextMovementTime = DotaTime() + 0.8
				return
			end
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
        if GetLiveTower(GetOpposingTeam(), TOWER_TOP_1) ~= nil then
            return 1
        elseif GetLiveTower(GetOpposingTeam(), TOWER_TOP_2) ~= nil then
            return 2
        elseif GetLiveTower(GetOpposingTeam(), TOWER_TOP_3) ~= nil
            or GetLiveBarracks(GetOpposingTeam(), BARRACKS_TOP_MELEE) ~= nil
            or GetLiveBarracks(GetOpposingTeam(), BARRACKS_TOP_RANGED) ~= nil
        then
            return 3
        else
            return 4
        end
    elseif nLane == LANE_MID then
        if GetLiveTower(GetOpposingTeam(), TOWER_MID_1) ~= nil then
            return 1
        elseif GetLiveTower(GetOpposingTeam(), TOWER_MID_2) ~= nil then
            return 2
        elseif GetLiveTower(GetOpposingTeam(), TOWER_MID_3) ~= nil
            or GetLiveBarracks(GetOpposingTeam(), BARRACKS_MID_MELEE) ~= nil
            or GetLiveBarracks(GetOpposingTeam(), BARRACKS_MID_RANGED) ~= nil
        then
            return 3
        else
            return 4
        end
    elseif nLane == LANE_BOT then
        if GetLiveTower(GetOpposingTeam(), TOWER_BOT_1) ~= nil then
            return 1
        elseif GetLiveTower(GetOpposingTeam(), TOWER_BOT_2) ~= nil then
            return 2
        elseif GetLiveTower(GetOpposingTeam(), TOWER_BOT_3) ~= nil
            or GetLiveBarracks(GetOpposingTeam(), BARRACKS_BOT_MELEE) ~= nil
            or GetLiveBarracks(GetOpposingTeam(), BARRACKS_BOT_RANGED) ~= nil
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

local function CanInspectBuilding(target)
    if target == nil then return false end
    local ok, visible = pcall(function()
        if target.IsNull ~= nil and target:IsNull() then return false end
        if target.CanBeSeen == nil or not target:CanBeSeen() then return false end
        return target.IsAlive == nil or target:IsAlive()
    end)
    return ok and visible == true
end

function Push.HasDefenseGlyphBuff(target)
    if not CanInspectBuilding(target) then return false end
    return target:HasModifier('modifier_fountain_glyph')
end

function Push.HasBackdoorProtect(target)
    if target == nil then return false end
    -- 不可见建筑的保护状态不可读，动作层必须失败关闭。
    if not CanInspectBuilding(target) then return true end
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
