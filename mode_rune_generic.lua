local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Tasks = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_task')
local ExecutionConfig=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local MapResources=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/map_resources')
local LocalRoutes=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/local_route_candidates')
local SkillMovement = require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/skill_avoidance')
local TowerSafety = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/tower_safety')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_candidate_debug')
local bot = GetBot()
local botName = bot:GetUnitName();
if bot == nil or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
local X = {}
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local Timer = require(GetScriptDirectory()..'/thd2_timer')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')

local RUNE_DESIRE_EARLY_INTERVAL = 0.35
local RUNE_DESIRE_MID_INTERVAL = 0.9
local RUNE_DESIRE_LATE_INTERVAL = 1.5
local RUNE_DESIRE_STAGGER = 0.11
local RUNE_LATE_GAME_TIME = 20 * 60
local RUNE_LATE_NEAR_DISTANCE = 2200
local RUNE_VERY_LATE_NEAR_DISTANCE = 1400
local RUNE_BOUNTY_MAX_DIST = 4200
local RUNE_POWER_MAX_DIST_MULTIPLIER = 3.0
local RUNE_BOUNTY_NON_LANING_SCALE = 0.55
local RUNE_POWER_NON_LANING_SCALE = 0.75
local RUNE_ACTIVE_STICKY_SECONDS = 6.0
local RUNE_ACTIVE_STICKY_DESIRE = 0.72
local RUNE_ACTIVE_STICKY_NEAR_DESIRE = 0.82
local RUNE_PICKUP_DISTANCE = 150
local RUNE_CHAIN_PICKUP_DISTANCE = 900
local RUNE_RECENT_PICKUP_IGNORE_SECONDS = 1.5
local RUNE_SAFE_ABORT_RADIUS = 900
local RUNE_DANGER_ABORT_RADIUS = 1700
local RUNE_POWER_ABORT_RADIUS = 700
local RUNE_POWER_ENEMY_NEAR_RUNE_RADIUS = 450
local RUNE_SAFE_ABANDON_SECONDS = 12
local RUNE_DANGER_ABANDON_SECONDS = 35
local WISDOM_RUNE_CLEAR_RADIUS = 650
local WISDOM_RUNE_PICKUP_RADIUS = 300 -- 缺少观察时仅用于安全距离；领取使用桥接的实际radius。
local WISDOM_RUNE_BACKUP_DISTANCE = 5200
local WISDOM_RUNE_ENEMY_ABORT_RADIUS = 1400
local MAX_DIST = 1600
local minute = 0
local second = 0
local ClosestRune = -1
local ClosestDistance = -1
local nRuneStatus = -1

local botActiveMode = -1

local nRuneList = {
	RUNE_BOUNTY_1,
	RUNE_BOUNTY_2,
	RUNE_POWERUP_1,
	RUNE_POWERUP_2,
}

local radiantWRLocation = Vector(-7956, 395, 256)
local direWRLocation = Vector(8197, -979, 256)
local wisdomRuneSpots = {
	[1] = radiantWRLocation,
	[2] = direWRLocation,
}
local function WisdomObservation(spot)
	local observation=MapResources.Get(bot,'wisdom',spot)
	if observation then
		wisdomRuneSpots[spot]=observation.location
		if spot==1 then radiantWRLocation=observation.location else direWRLocation=observation.location end
	end
	return observation
end
local wisdomRuneInfo = {0, 0, false} -- 开始时间、符点槽位、任务启用；不代表已取得经验。
local timeInMin = 0
local Bottle = nil
local lastMin = 0
local runeModeStartTime = -9999
local wisdomRuneEnterTime = -9999
local lastRunePickupTime = -9999
local lastRunePickupLocation = nil
local idleRuneTask = nil
local runeExecutionOutcome=nil
local function SetRuneOutcome(status,reason)
	runeExecutionOutcome={status=status,reason=reason}
end

local function RuneMove(unit, actionName, location, interval, distance)
	return J.ActionMoveToLocation(unit, actionName, location, interval, distance, function(point)
		local observation=TowerSafety.Observe(unit, 'rune')
		if observation.available~=true or not Geometry.ValidateMovementSegment(unit:GetLocation(), point, observation.towers, 96) then return false end
		if actionName=='idle_available_rune' and #J.GetLastSeenEnemiesNearLoc(unit:GetLocation(), Geometry.Distance(unit:GetLocation(),point)+1200)>0 then return false end
		return Geometry.ValidateLocalTerrainSegment(unit:GetLocation(), point, true)
	end)
end

local function IdleRuneSafe(rune)
	if J.CanNotUseAction(bot) or J.GetHP(bot) < 0.55
	or bot:WasRecentlyDamagedByAnyHero(2.0) or bot:WasRecentlyDamagedByTower(2.0)
	or J.IsRoshanCommitmentActive(bot) then return false, 'protected_or_danger' end
	local ability = bot:GetCurrentActiveAbility()
	if ability ~= nil then
		local ok, protected = pcall(function() return ability:IsInAbilityPhase() or ability:IsChanneling() end)
		if not ok or protected then return false, 'protected_phase' end
	end
	local location = GetRuneSpawnLocation(rune)
	if location == nil or GetRuneStatus(rune) ~= RUNE_STATUS_AVAILABLE then return false, 'not_available' end
	local current = bot:GetLocation()
	local distance = Geometry.Distance(current, location)
	if distance > 900 then return false, 'outside_local_range' end
	local observation = TowerSafety.Observe(bot, 'rune')
	if observation.available ~= true then return false, 'tower_snapshot_stale' end
	if not Geometry.ValidateMovementSegment(current, location, observation.towers, 96) then
		return false, 'tower_segment'
	end
	if #J.GetLastSeenEnemiesNearLoc(current, distance + 1200) > 0 then return false, 'recent_enemy' end
	return Geometry.ValidateLocalTerrainSegment(current, location, true)
end

local function ValidateIdleRuneTask()
	if idleRuneTask == nil then return false end
	local now = DotaTime()
	local distance = GetUnitToLocationDistance(bot, GetRuneSpawnLocation(idleRuneTask.rune))
	if idleRuneTask.bestDistance - distance >= 48 then
		idleRuneTask.bestDistance, idleRuneTask.progressAt = distance, now
	end
	local reason = now >= idleRuneTask.expiresAt and 'expired'
		or (now - idleRuneTask.progressAt >= 3.0 and 'no_progress' or nil)
	if reason == nil and now >= idleRuneTask.nextSafetyAt then
		idleRuneTask.nextSafetyAt = now + 0.5
		local safe, safetyReason = IdleRuneSafe(idleRuneTask.rune)
		if not safe then reason = safetyReason end
	end
	if reason == nil then return true end
	CandidateDebug.Note('idle_rune_' .. reason)
	X.MarkRuneAbandoned(idleRuneTask.rune)
	idleRuneTask = nil
	return false
end

local function ClearWisdomRuneMode()
	wisdomRuneInfo[1] = 0
	wisdomRuneInfo[2] = nil
	wisdomRuneInfo[3] = false
	wisdomRuneEnterTime = -9999
end

local function MarkWisdomRuneConsumed()
	if bot.wisdom ~= nil
	and bot.wisdom[timeInMin] ~= nil
	and wisdomRuneInfo[2] ~= nil
	then
		bot.wisdom[timeInMin][wisdomRuneInfo[2]] = true
	end

	ClearWisdomRuneMode()
end

local function MarkWisdomRuneAbandoned()
	if timeInMin > 0 and wisdomRuneInfo[2] ~= nil then
		-- 智慧符被敌人拦截时不等同于确认已拾取，只让当前 bot 放弃本轮尝试。
		bot.wisdomAbandoned = bot.wisdomAbandoned or {}
		bot.wisdomAbandoned[timeInMin] = bot.wisdomAbandoned[timeInMin] or {}
		bot.wisdomAbandoned[timeInMin][wisdomRuneInfo[2]] = true
	end

	ClearWisdomRuneMode()
end

local function IsRecentlyPickedRuneLocation(vLoc)
	return lastRunePickupLocation ~= nil
		and DotaTime() - lastRunePickupTime <= RUNE_RECENT_PICKUP_IGNORE_SECONDS
		and J.GetDistance(vLoc, lastRunePickupLocation) <= RUNE_PICKUP_DISTANCE
end

local function ClearActiveRuneTarget()
	idleRuneTask = nil
	ClosestRune = -1
	ClosestDistance = -1
	nRuneStatus = -1
end

local activeRuneReason='none'
local function GetActiveRuneDesire()
	activeRuneReason='active'
	if idleRuneTask ~= nil then
		if ValidateIdleRuneTask() then return 0.28 end
		ClearActiveRuneTarget()
		activeRuneReason='idle_rune_invalid'
		return BOT_MODE_DESIRE_NONE
	end
	if wisdomRuneInfo[3] then
		local observation=wisdomRuneInfo[2] and WisdomObservation(wisdomRuneInfo[2])
		if not observation then activeRuneReason='wisdom_observation_unavailable';return 0 end
		if observation.state=='empty' then activeRuneReason='wisdom_observed_empty';return 0 end
		local wisdomLoc = observation.location
		if wisdomLoc ~= nil and X.ShouldAbortWisdomRune(wisdomLoc) then
			MarkWisdomRuneAbandoned()
			activeRuneReason='wisdom_unsafe'
			return BOT_MODE_DESIRE_NONE
		end

		if wisdomLoc ~= nil
		and observation.state=='ready' and GetUnitToLocationDistance(bot, wisdomLoc) <= observation.radius-32
		then
			return BOT_MODE_DESIRE_ABSOLUTE
		end

		return observation.state=='ready' and RUNE_ACTIVE_STICKY_NEAR_DESIRE or math.min(0.35,X.GetWisdomDesire(wisdomLoc))
	end

	if bot:GetActiveMode() ~= BOT_MODE_RUNE then activeRuneReason='not_active_mode';return BOT_MODE_DESIRE_NONE end

	if ClosestRune == nil or ClosestRune == -1 then
		activeRuneReason='missing_rune_target'
		return BOT_MODE_DESIRE_NONE
	end

	if not X.IsSuitableToPickRune() then
		activeRuneReason='unsuitable_to_pick'
		return BOT_MODE_DESIRE_NONE
	end

	local runeLoc = GetRuneSpawnLocation(ClosestRune)
	if runeLoc == nil then
		activeRuneReason='missing_rune_location'
		return BOT_MODE_DESIRE_NONE
	end

	ClosestDistance = GetUnitToLocationDistance(bot, runeLoc)
	if ClosestDistance > 6000 then
		activeRuneReason='rune_too_far'
		return BOT_MODE_DESIRE_NONE
	end

	if X.ShouldAbortRune(ClosestRune, runeLoc, ClosestDistance) then
		activeRuneReason='rune_unsafe'
		X.MarkRuneAbandoned(ClosestRune)
		ClearActiveRuneTarget()
		return BOT_MODE_DESIRE_NONE
	end

	nRuneStatus = GetRuneStatus(ClosestRune)
	activeRuneReason=nRuneStatus==RUNE_STATUS_AVAILABLE and 'rune_available'
		or (nRuneStatus==RUNE_STATUS_MISSING and 'rune_missing' or 'rune_unknown')
	if nRuneStatus == RUNE_STATUS_AVAILABLE then
		if ClosestDistance < 700 then
			return RUNE_ACTIVE_STICKY_NEAR_DESIRE
		end
		return RUNE_ACTIVE_STICKY_DESIRE
	end

	if nRuneStatus == RUNE_STATUS_UNKNOWN
	and DotaTime() - runeModeStartTime < RUNE_ACTIVE_STICKY_SECONDS then
		return RUNE_ACTIVE_STICKY_DESIRE
	end

	if nRuneStatus == RUNE_STATUS_MISSING
	and ClosestDistance < 350
	and DotaTime() - runeModeStartTime < 1.5 then
		return BOT_MODE_DESIRE_MODERATE
	end

	return BOT_MODE_DESIRE_NONE
end

local function ComputeDesire()
	if not Utils.AllowModeDesire(bot, 'rune') then CandidateDebug.Note('mode_switch_lock'); return BOT_MODE_DESIRE_NONE end
	if not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() or bot.isBear then CandidateDebug.Note('invalid_bot'); return BOT_MODE_DESIRE_NONE end
    if DotaTime() > 2 * 60 and DotaTime() < 6 * 60 and GetUnitToLocationDistance(bot, GetRuneSpawnLocation(RUNE_POWERUP_2)) < 150
	then
        CandidateDebug.Note('early_power_rune_wait')
        return 0
    end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		CandidateDebug.Note('team_push_proximity')
		return BOT_MODE_DESIRE_NONE
	end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		CandidateDebug.Note('ancient_pressure')
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() - J.Utils.GameStates.recentDefendTime < 2 then
		CandidateDebug.Note('recent_defense')
		return BOT_MODE_DESIRE_NONE
	end

    botActiveMode = bot:GetActiveMode()

	if bot:IsInvulnerable() and J.GetHP(bot) > 0.95 and bot:DistanceFromFountain() < 100 then
        CandidateDebug.Note('fountain_exit')
        return BOT_MODE_DESIRE_ABSOLUTE
    end

	local activeRuneDesire = GetActiveRuneDesire()
	if activeRuneDesire > BOT_MODE_DESIRE_NONE then
		CandidateDebug.Note('active_rune_task')
		return activeRuneDesire
	end

	local wrDesire = ConsiderWisdomRune()
	if wrDesire > 0.1 then
		CandidateDebug.Note('wisdom_candidate')
		return wrDesire
	end

	if DotaTime() > RUNE_LATE_GAME_TIME and not X.IsNearRune(bot, RUNE_LATE_NEAR_DISTANCE) then
		CandidateDebug.Note('late_rune_too_far')
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() > 30 * 60 and not X.IsNearRune(bot, RUNE_VERY_LATE_NEAR_DISTANCE) then
		CandidateDebug.Note('very_late_rune_too_far')
		return BOT_MODE_DESIRE_NONE
	end

	local idleCandidate = DotaTime() > -10 and bot:GetCurrentActionType() == BOT_ACTION_TYPE_IDLE
	if idleCandidate and (DotaTime() < 0 or bot:GetLevel() <= 15 or bot:GetActiveModeDesire() > 0) then
		CandidateDebug.Note('idle_has_owner_or_laning')
		return BOT_MODE_DESIRE_NONE
	end

    minute = math.floor(DotaTime() / 60)
    second = DotaTime() % 60

    if not X.IsSuitableToPickRune() then
        CandidateDebug.Note('unsuitable_rune_mode')
        return BOT_MODE_DESIRE_NONE
    end

    if DotaTime() < 0 and not bot:WasRecentlyDamagedByAnyHero(5.0)
    then
        local nEnemyHeroes = J.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 2000)
        if #nEnemyHeroes <= 1 then
            CandidateDebug.Note('pregame_rune')
            return RemapValClamped(J.GetHP(bot), 0.2, 0.8, BOT_MODE_DESIRE_NONE, BOT_MODE_DESIRE_MODERATE)
        end
    end

    if J.IsLateGame() and X.IsUnitAroundLocation(GetAncient(GetTeam()):GetLocation(), 2800) then
        MAX_DIST = 900
    else
        MAX_DIST = 1600
    end

    ClosestRune, ClosestDistance = X.GetBotClosestRune()

	if ClosestRune ~= -1 and ClosestDistance < 6000 then
		local nRuneType = GetRuneType(ClosestRune)
        nRuneStatus = GetRuneStatus(ClosestRune)

		if X.ShouldAbortRune(ClosestRune, GetRuneSpawnLocation(ClosestRune), ClosestDistance) then
			X.MarkRuneAbandoned(ClosestRune)
			CandidateDebug.Note('rune_danger_abort')
			return 0
		end

		if X.IsEnemyPickRune(ClosestRune) then
			X.MarkRuneAbandoned(ClosestRune)
			CandidateDebug.Note('enemy_picked_rune')
			return 0
		end

		if idleCandidate then
			local safe, reason = IdleRuneSafe(ClosestRune)
			if not safe then CandidateDebug.Note('idle_rune_' .. tostring(reason)); return 0 end
			-- IDLE 只接已出现、可达的近处符文；冻结目标，不升级为普通符文的高粘性欲望。
			idleRuneTask = {rune = ClosestRune, expiresAt = DotaTime() + 6.0,
				progressAt = DotaTime(), bestDistance = ClosestDistance, nextSafetyAt = DotaTime() + 0.5}
			CandidateDebug.Note('idle_available_rune')
			CandidateDebug.Detail('idle_rune_target', ClosestRune)
			return 0.28
		end

        if ClosestRune == RUNE_BOUNTY_1 or ClosestRune == RUNE_BOUNTY_2 then
            if nRuneStatus == RUNE_STATUS_AVAILABLE then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					if J.IsInLaningPhase() then
						CandidateDebug.Note('rune_branch_p816_L284')
						return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.82)
					end

					CandidateDebug.Note('rune_branch_p816_L287')
					return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.78, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
				end

                CandidateDebug.Note('rune_branch_p816_L290')
                return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.82, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
            elseif nRuneStatus == RUNE_STATUS_UNKNOWN
                and DotaTime() > 2 * 60 + 50
                and ((minute % 3 == 0) or (minute % 3 == 2 and second > 45))
            then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					if J.IsInLaningPhase() then
						CandidateDebug.Note('rune_branch_p816_L297')
						return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.78)
					end

					CandidateDebug.Note('rune_branch_p816_L300')
					return X.GetScaledDesire(BOT_MODE_DESIRE_LOW, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.72, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
				end

                CandidateDebug.Note('rune_branch_p816_L303')
                return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.82, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
            elseif nRuneStatus == RUNE_STATUS_MISSING
                and DotaTime() > 2 * 60
                and (minute % 3 == 2 and second > 52)
            then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					CandidateDebug.Note('rune_branch_p816_L309')
					return X.GetScaledDesire(BOT_MODE_DESIRE_LOW, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.70, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
				end

                CandidateDebug.Note('rune_branch_p816_L312')
                return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.76, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
            end
        else
            if nRuneStatus == RUNE_STATUS_AVAILABLE then
				if nRuneType == RUNE_WATER and (J.GetHP(bot) < 0.6 or J.GetMP(bot) < 0.5) then
					CandidateDebug.Note('rune_branch_p816_L317')
					return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, 3200)
				else
					if nRuneType == RUNE_WATER then
						CandidateDebug.Note('rune_branch_p816_L320')
						return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST)
					else
						if X.IsPowerRune(ClosestRune) then
							CandidateDebug.Note('rune_branch_p816_L323')
							return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, MAX_DIST * RUNE_POWER_MAX_DIST_MULTIPLIER, 0.85, RUNE_POWER_NON_LANING_SCALE, 0.55)
						else
							CandidateDebug.Note('rune_branch_p816_L325')
							return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * 2.5)
						end
					end
				end
            elseif nRuneStatus == RUNE_STATUS_UNKNOWN
                and DotaTime() > 113
            then
				if DotaTime() > 5 * 60 then
					if X.IsPowerRune(ClosestRune) then
						CandidateDebug.Note('rune_branch_p816_L334')
						return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * RUNE_POWER_MAX_DIST_MULTIPLIER, 0.78, RUNE_POWER_NON_LANING_SCALE, 0.55)
					end

					CandidateDebug.Note('rune_branch_p816_L337')
					return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * 2.5)
				else
					CandidateDebug.Note('rune_branch_p816_L339')
					return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST)
				end
            elseif nRuneStatus == RUNE_STATUS_MISSING
                and DotaTime() > 60
                and (minute % 2 == 1 and second > 53)
            then
                CandidateDebug.Note('rune_branch_p816_L345')
                return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST)
            end
        end
    end

    CandidateDebug.Note('no_rune_candidate')
    return 0
end

function ConsiderWisdomRune()
	if not ExecutionConfig.MAP_RESOURCES_ENABLED or bot:GetLevel()>=30 or DotaTime()<7*60 then return 0 end
	timeInMin=X.GetMulTime();X.UpdateWisdom()
	WisdomObservation(1);WisdomObservation(2)
	local towers=bot:GetNearbyTowers(700,true)
	if (#towers>0 and bot:WasRecentlyDamagedByTower(1) and J.GetHP(bot)<0.3)
	or #J.GetEnemiesNearLoc(bot:GetLocation(),1200)>0 then return 0 end
	local spot=X.GetWisdomRuneSpot()
	local observation=spot and WisdomObservation(spot)
	if not observation then MapResources.Log(bot,nil,'unknown','wisdom_bridge_unavailable');return 0 end
	if observation.state=='empty' or X.IsWisdomRuneAbandoned(spot) or not MapResources.CanTry(bot,'wisdom',spot) then return 0 end
	if not X.ShouldTryWisdomRune(observation.location) then return 0 end
	local score=X.GetWisdomDesire(observation.location)
	-- 未见到实际就绪时只允许低优先级侦察，不把刷新日历当作符仍存在的证据。
	if observation.state=='unknown' then score=math.min(score,0.35) end
	if score<=0 then return 0 end
	wisdomRuneInfo={DotaTime(),spot,true};wisdomRuneEnterTime=-9999
	MapResources.Log(bot,observation,observation.state=='ready' and 'ready' or 'unknown','wisdom_candidate')
	return score
end

local function CaptureRuneState()
	local idle=nil
	if idleRuneTask~=nil then idle={};for k,v in pairs(idleRuneTask) do idle[k]=v end end
	return {rune=ClosestRune,distance=ClosestDistance,status=nRuneStatus,
		wisdom={wisdomRuneInfo[1],wisdomRuneInfo[2],wisdomRuneInfo[3]},idle=idle,
		wisdomEnter=wisdomRuneEnterTime,minute=timeInMin}
end
local function RestoreRuneState(state)
	if state==nil then return end
	ClosestRune,ClosestDistance,nRuneStatus=state.rune,state.distance,state.status
	wisdomRuneInfo={state.wisdom[1],state.wisdom[2],state.wisdom[3]}
	idleRuneTask=state.idle
	wisdomRuneEnterTime,timeInMin=state.wisdomEnter,state.minute
end
local function RuneTask(snapshot)
	local kind,location,key='rune',nil,snapshot.rune
	if snapshot.wisdom[3] then
		kind,key='wisdom',snapshot.wisdom[2];location=wisdomRuneSpots[key]
	elseif DotaTime()<0 then kind,key='pregame','pregame'
	elseif bot:IsInvulnerable() and J.GetHP(bot)>0.95 and bot:DistanceFromFountain()<100 then
		local lane=bot:GetAssignedLane()
		if lane~=LANE_TOP and lane~=LANE_MID and lane~=LANE_BOT then lane=LANE_MID end
		kind,key='fountain','fountain';location=GetLaneFrontLocation(GetTeam(),lane,0)
	elseif snapshot.rune~=nil and snapshot.rune~=-1 then location=GetRuneSpawnLocation(snapshot.rune) end
	local observation=kind=='wisdom' and WisdomObservation(key)
	if observation then location=observation.location end
	return {kind=kind,key=key,location=location,snapshot=snapshot,reason=kind,
		resourceIdentity=observation and observation.identity,deadline=kind=='wisdom' and snapshot.wisdom[1]+30 or (kind=='fountain' and DotaTime()+6 or nil),
		arrivalRadius=kind=='wisdom' and WISDOM_RUNE_PICKUP_RADIUS or RUNE_PICKUP_DISTANCE,stallSeconds=6}
end
local function ValidateRuneCandidate(task,fresh)
	if not task then return false,'missing_candidate' end
	if task.kind=='rune' then
		local known=false;for _,rune in ipairs(nRuneList) do if rune==task.key then known=true;break end end
		if not known or not task.location or task.snapshot.rune~=task.key then return false,'invalid_rune_target' end
		if fresh and task.snapshot.status==RUNE_STATUS_AVAILABLE and GetRuneStatus(task.key)~=RUNE_STATUS_AVAILABLE then
			return false,'rune_changed_before_commit'
		end
		if fresh and task.snapshot.status==RUNE_STATUS_UNKNOWN and GetRuneStatus(task.key)==RUNE_STATUS_MISSING then
			return false,'rune_missing_before_commit'
		end
	elseif task.kind=='wisdom' then
		if not task.location or not task.snapshot.wisdom[3] or task.snapshot.wisdom[2]~=task.key then return false,'invalid_wisdom_target' end
		if DotaTime()>=(task.deadline or -90) then return false,'wisdom_task_deadline' end
		local observation=WisdomObservation(task.key)
		if not observation or observation.identity~=task.resourceIdentity then return false,'wisdom_observation_unavailable' end
		if fresh and observation.state=='empty' then return false,'wisdom_empty_before_commit' end
	elseif task.kind=='fountain' then
		if not task.location then return false,'fountain_exit_location_missing' end
		if DotaTime()>=(task.deadline or -90) then return false,'fountain_exit_deadline' end
	elseif task.kind=='pregame' and DotaTime()>=0 then return false,'pregame_ended' end
	return true
end
local function RuneMissionSafe()
	if J.Retreat.ShouldYield(bot,J.Retreat.HIGH) then return false,'high_retreat' end
	if J.GetEnemiesAroundAncient(bot,3200)>0 then return false,'base_emergency' end
	local strategicChange=J.Utils.IsTeamPushingSecondTierOrHighGround(bot)
		or DotaTime()-J.Utils.GameStates.recentDefendTime<2
	if not strategicChange then return true end
	-- 普通战略变化计入机会成本，但已接近的可用符可有界收尾；未知/消失符不保留。
	local task=Tasks.Active(bot,'rune')
	if task and task.kind=='wisdom' then
		local observation=WisdomObservation(task.key)
		return observation and observation.state=='ready' and task.resourceClaimAt
			and GetUnitToLocationDistance(bot,observation.location)<=observation.radius
			and DotaTime()<(task.resourceClaimUntil or -90),'strategic_commitment'
	end
	if not task or task.kind~='rune' or bot:GetActiveMode()~=BOT_MODE_RUNE
		or GetRuneStatus(task.key)~=RUNE_STATUS_AVAILABLE or not task.location then return false,'strategic_commitment' end
	local distance=GetUnitToLocationDistance(bot,task.location)
	return distance<=RUNE_PICKUP_DISTANCE or (distance<=700 and Tasks.ProgressScore(bot,'rune',0.5,true)>0.5),'strategic_commitment'
end
local pendingRuneSnapshot=nil
local runeContinuation=nil
local runeSession=0
local runeRejected={}
local runeLogAt=-90
local function RuneIdentity(task)
	return tostring(task.kind)..':'..tostring(task.key)..(task.kind=='wisdom' and ':'..tostring(task.snapshot.minute) or '')
end
local function ObservedRuneStatus(task)
	return task and task.kind=='rune' and task.key and task.key~=-1 and GetRuneStatus(task.key) or -1
end
local function LogRune(event,task,reason,score)
	if not ExecutionConfig.DEBUG or not task then return end
	local now=DotaTime()
	if (event=='active' or event=='admission_rejected') and now-runeLogAt<2 then return end
	runeLogAt=now
	print(string.format('[BOT][RuneTask] run=%s time=%.3f pid=%s event=%s session=%s target=%s rune_status=%s distance=%.1f score=%s reason=%s progress_at=%s started_at=%s retry_at=%s',
		ExecutionConfig.RUN_ID,now,bot:GetPlayerID(),event,tostring(task.runeSession),RuneIdentity(task),ObservedRuneStatus(task),
		task.location and GetUnitToLocationDistance(bot,task.location) or -1,tostring(score),tostring(reason),tostring(task.progressAt),tostring(task.startedAt),tostring(task.retryAt)))
end
local function RejectRune(task,reason)
	if not task then return end
	bot.THD_RunePickup=nil
	local previous=runeRejected[RuneIdentity(task)]
	local failed=string.find(reason or '','^pickup_')~=nil
	local failures=failed and math.min(4,(previous and previous.failures or 0)+1) or 0
	local delay=failed and math.min(12,failures*3) or ExecutionConfig.RUNE_RESUME_SECONDS
	runeRejected[RuneIdentity(task)]={untilAt=DotaTime()+delay,status=ObservedRuneStatus(task),reason=reason,failures=failures}
	runeContinuation=nil
	LogRune('released',task,reason,0)
end
local function PickupOutcome(task)
	if not task or not task.pickupIssuedAt then return nil end
	local receipt=MapResources.RuneReceipt(bot)
	if receipt and receipt.sequence~=(task.pickupReceiptSequence or 0)
		and receipt.time>=task.pickupIssuedAt-0.11 and receipt.time<=(task.pickupReceiptUntil or task.pickupDeadline)
		and (task.pickupRuneType==nil or task.pickupRuneType<0 or receipt.runeType==task.pickupRuneType)
		and task.location and J.GetDistance(receipt.location,task.location)<=350 then
		return {status='COMPLETE',reason='rune_self_activation_confirmed'}
	end
	-- 指令不等于拾取成功：只确认命令之后符已消失，不把消失归因为本Bot取得。
	if ObservedRuneStatus(task)==RUNE_STATUS_MISSING then return {status='COMPLETE',reason='rune_absent_after_pickup'} end
	if DotaTime()>=(task.pickupReceiptUntil or task.pickupDeadline or task.pickupIssuedAt+1.5) then return {status='INVALID',reason='pickup_unconfirmed'} end
	if not bot:IsAlive() or bot:GetHealth()<(task.pickupHealth or 0)-1 then return {status='INVALID',reason='pickup_danger'} end
	if Actions.Protected(bot,nil,true) or bot:GetCurrentActionType()==BOT_ACTION_TYPE_USE_ABILITY
		or J.HasQueuedAction(bot) then return {status='INVALID',reason='pickup_interrupted_by_action'} end
	if task.location then
		local distance=GetUnitToLocationDistance(bot,task.location)
		task.pickupMaxDistance=math.max(task.pickupMaxDistance or 0,distance)
		-- 原生拾取仍在执行时容纳局部绕行；不增加总期限，也不追随无限远的目标。
		local nativePickup=bot:GetCurrentActionType()==BOT_ACTION_TYPE_PICK_UP_RUNE
		if distance>(nativePickup and 650 or RUNE_PICKUP_DISTANCE*2) then
			return {status='INVALID',reason=nativePickup and 'pickup_native_path_out_of_bounds' or 'pickup_displaced'}
		end
	end
	return {status='WAITING',reason=DotaTime()>=(task.pickupDeadline or math.huge) and 'pickup_receipt_grace' or 'pickup_confirmation'}
end
local function FinishRune(task,outcome)
	bot.THD_RunePickup=nil
	if outcome.status=='COMPLETE' then
		if task then runeRejected[RuneIdentity(task)]=nil end
		LogRune('completed',task,outcome.reason,0);runeContinuation=nil
		if task and task.kind=='wisdom' and outcome.reason=='wisdom_observed_empty' then
			RestoreRuneState(task.snapshot);MarkWisdomRuneConsumed()
		end
	else RejectRune(task,outcome.reason) end
	if task and task.kind=='wisdom' then MapResources.Defer(bot,'wisdom',task.key,outcome.reason,8) end
	Tasks.Release(bot,'rune',outcome.reason)
	ClearActiveRuneTarget();ClearWisdomRuneMode()
end
local function NotePickup(task,event)
	if not ExecutionConfig.DEBUG then return end
	local issued=bot.THD_LastIssuedAction
	local position,spawn=bot:GetLocation(),GetRuneSpawnLocation(task.key)
	local action=bot:GetCurrentActionType()
	local receipt=MapResources.RuneReceipt(bot)
	print(string.format('[BOT][RunePickup] run=%s time=%.3f pid=%s session=%s event=%s rune=%s distance=%.1f action=%s queued=%d issued_kind=%s issued_at=%s deadline=%.3f',
		ExecutionConfig.RUN_ID,DotaTime(),bot:GetPlayerID(),tostring(task.runeSession),event,tostring(task.key),GetUnitToLocationDistance(bot,task.location),
		tostring(action),bot:NumQueuedActions(),tostring(issued and issued.kind),tostring(issued and issued.at),task.pickupDeadline or -1)
		..string.format(' rune_status=%s rune_type=%s seen_age=%s action_is_pickup=%s action_is_idle=%s x=%.1f y=%.1f spawn_x=%s spawn_y=%s visible=%s hp=%s rooted=%s stunned=%s invulnerable=%s using_ability=%s',
			tostring(GetRuneStatus(task.key)),tostring(GetRuneType(task.key)),tostring(GetRuneTimeSinceSeen(task.key)),
			tostring(action==BOT_ACTION_TYPE_PICK_UP_RUNE),tostring(action==BOT_ACTION_TYPE_IDLE),position.x,position.y,
			tostring(spawn and spawn.x),tostring(spawn and spawn.y),tostring(spawn and IsLocationVisible(spawn)),
			tostring(bot:GetHealth()),tostring(bot:IsRooted()),tostring(bot:IsStunned()),tostring(bot:IsInvulnerable()),tostring(bot:IsUsingAbility()))
		..string.format(' receipt_sequence=%s receipt_time=%s receipt_type=%s receipt_baseline=%s receipt_until=%s max_distance=%s',
			tostring(receipt and receipt.sequence),tostring(receipt and receipt.time),tostring(receipt and receipt.runeType),tostring(task.pickupReceiptSequence),tostring(task.pickupReceiptUntil),tostring(task.pickupMaxDistance)))
end
local function IssuePickup(task,retry)
	-- 独立的短拾取保护，不覆盖技能/物品保护；补发最多一次，绝不刷新确认期限。
	-- 前后各取一次引擎状态；API返回与记录意图都不等于引擎已经开始拾取。
	NotePickup(task,retry and 'retry_requested' or 'requested')
	if not retry then
		local receipt=MapResources.RuneReceipt(bot)
		task.pickupReceiptSequence=receipt and receipt.sequence or 0
		task.pickupRuneType=GetRuneType(task.key)
	end
	Actions.Forget(bot)
	bot:Action_PickUpRune(task.key)
	-- 命令返回后才建立确认状态，避免下单失败却进入虚假的等待窗口。
	if not retry then
		task.pickupIssuedAt=DotaTime();task.pickupDeadline=DotaTime()+1.5;task.pickupHealth=bot:GetHealth()
		-- 原发单窗口之后只等自身激活回执，不再补发，也不因符仍存在判失败。
		task.pickupReceiptUntil=task.pickupDeadline+0.75
	else task.pickupRetried=true end
	bot.THD_RunePickup={rune=task.key,deadline=task.pickupReceiptUntil or task.pickupDeadline,health=task.pickupHealth}
	Actions.NoteIssued(bot,'rune_pickup',nil,task.location)
	lastRunePickupTime,lastRunePickupLocation=DotaTime(),task.location
	NotePickup(task,retry and 'reissued' or 'issued')
	SetRuneOutcome('WAITING','pickup_confirmation')
end
function GetDesire()
	local active=Tasks.Active(bot,'rune')
	local confirmed=active and PickupOutcome(active)
	if confirmed and confirmed.status=='COMPLETE' then NotePickup(active,confirmed.reason);FinishRune(active,confirmed);return 0 end
	local safe,safetyReason=RuneMissionSafe()
	if not safe then
		RejectRune(active,safetyReason)
		Tasks.Release(bot,'rune',safetyReason);ClearActiveRuneTarget();ClearWisdomRuneMode();return 0
	end
	if active~=nil then
		local valid,reason=ValidateRuneCandidate(active)
		if not valid then FinishRune(active,{status='INVALID',reason=reason});return 0 end
		if active.kind=='fountain' then
			if bot:DistanceFromFountain()>=100 or not bot:IsInvulnerable() then FinishRune(active,{status='COMPLETE',reason='fountain_exit_complete'});return 0 end
			if J.GetHP(bot)<=0.95 then FinishRune(active,{status='INVALID',reason='fountain_recovery_required'});return 0 end
			return Tasks.Offer(bot,'rune',active.score,active)
		end
		local pickup=PickupOutcome(active)
		if pickup then
			if pickup.status~='WAITING' then NotePickup(active,pickup.reason);FinishRune(active,pickup);return 0 end
			LogRune('active',active,pickup.reason,active.score)
			return Tasks.Offer(bot,'rune',math.max(active.score or 0,0.96),active)
		end
		RestoreRuneState(active.snapshot)
		if not Tasks.Check(bot,'rune',true) then
			RejectRune(active,'task_invalid_or_no_progress')
			if active.kind=='rune' then X.MarkRuneAbandoned(active.key) end
			ClearActiveRuneTarget();ClearWisdomRuneMode();return 0
		end
		if active.kind=='rune' or active.kind=='wisdom' then
			-- 存活任务只复核当前符点、危险与进度，不在Think里重新寻找另一个符。
			local score=GetActiveRuneDesire()
			if score<=0 then
				FinishRune(active,{status=activeRuneReason=='wisdom_observed_empty' and 'COMPLETE' or 'INVALID',reason=activeRuneReason});return 0
			end
			Tasks.ObserveValue(bot,'rune',active)
			score=Tasks.ProgressScore(bot,'rune',score)
			LogRune('active',active,activeRuneReason,score)
			return Tasks.Offer(bot,'rune',score,RuneTask(CaptureRuneState()))
		end
	end
	local saved=active and CaptureRuneState() or nil
	local interval=DotaTime()<0 and RUNE_DESIRE_EARLY_INTERVAL
		or DotaTime()>RUNE_LATE_GAME_TIME and RUNE_DESIRE_LATE_INTERVAL or RUNE_DESIRE_MID_INTERVAL
	local score=Utils.GetCachedModeDesire(bot,'rune',function()
		local value=ComputeDesire()
		pendingRuneSnapshot=CaptureRuneState()
		return value
	end,interval)
	if saved then RestoreRuneState(saved) end
	if score<=0 or pendingRuneSnapshot==nil then Tasks.Release(bot,'rune','no_candidate');return 0 end
	local candidate=RuneTask(pendingRuneSnapshot)
	if candidate.kind=='wisdom' then
		local observation=WisdomObservation(candidate.key)
		if observation and observation.state=='unknown' then score=math.min(score,0.35) end
	end
	local valid,reason=ValidateRuneCandidate(candidate,true)
	if not valid then
		LogRune('admission_rejected',candidate,reason,0)
		Tasks.Release(bot,'rune',reason);pendingRuneSnapshot=nil;return 0
	end
	local rejected=runeRejected[RuneIdentity(candidate)]
	if rejected and DotaTime()<rejected.untilAt and ObservedRuneStatus(candidate)==rejected.status then
		candidate.retryAt=rejected.untilAt;LogRune('admission_rejected',candidate,rejected.reason,0)
		Tasks.Offer(bot,'rune',0,nil);return 0
	end
	if runeContinuation and DotaTime()<runeContinuation.expiresAt and RuneIdentity(candidate)==RuneIdentity(runeContinuation.task)
	and ObservedRuneStatus(candidate)==RUNE_STATUS_AVAILABLE then candidate.resume=runeContinuation end
	return Tasks.Offer(bot,'rune',Tasks.OpportunityScore(bot,score),candidate)
end

function OnStart()
	Utils.NoteModeStart(bot,'rune')
	local task=Tasks.Start(bot,'rune')
	if task then
		local valid,reason=ValidateRuneCandidate(task,true)
		if not valid then FinishRune(task,{status='INVALID',reason=reason});return end
	end
	if task then RestoreRuneState(task.snapshot) end
	local resume=task and task.resume
	if resume and DotaTime()<resume.expiresAt and ObservedRuneStatus(task)==RUNE_STATUS_AVAILABLE then
		-- 短暂让出模式后延续同一符点的进度与起始时间，不重置未知等待/停滞预算。
		for _,field in ipairs({'startedAt','progressAt','bestDistance','health','runeSession','pickupIssuedAt','pickupDeadline',
			'pickupReceiptUntil','pickupReceiptSequence','pickupRuneType','pickupRetried','pickupHealth'}) do task[field]=resume.task[field] end
		runeModeStartTime=resume.modeStart
		LogRune('resumed',task,'same_available_rune',task.score)
	else
		runeModeStartTime=DotaTime();runeSession=runeSession+1
		if task then task.runeSession=runeSession;LogRune('acquired',task,'new_candidate',task.score) end
	end
	runeContinuation=nil
end

function OnEnd()
	bot.THD_RunePickup=nil
	local task=Tasks.Active(bot,'rune')
	local pickup=PickupOutcome(task)
	if pickup and pickup.status~='WAITING' then FinishRune(task,pickup);task=nil end
	if task and not task.pickupIssuedAt and task.kind=='rune' and bot:IsAlive() and ObservedRuneStatus(task)==RUNE_STATUS_AVAILABLE
	and not J.Retreat.ShouldYield(bot,J.Retreat.HIGH) then
		runeContinuation={task=task,modeStart=runeModeStartTime,expiresAt=DotaTime()+ExecutionConfig.RUNE_RESUME_SECONDS}
		LogRune('suspended',task,'mode_end',task.score)
	elseif task then RejectRune(task,'mode_end_unavailable') end
	Tasks.Release(bot,'rune','mode_end')
	runeModeStartTime=-9999
	pendingRuneSnapshot=nil
	ClearActiveRuneTarget();ClearWisdomRuneMode()
end

local function ExecuteRuneTask(task)
	if J.CanNotUseAction(bot) then return end
    if not Timer.ShouldRunBotTask(bot, 'rune_think', 0.25, 0.04) then return end
	if task.kind=='fountain' then
		-- 出泉任务不落入普通符分支；固定目的地和6秒期限，只重选安全局部路点。
		if bot:DistanceFromFountain()>=100 or not bot:IsInvulnerable() then SetRuneOutcome('COMPLETE','fountain_exit_complete');return end
		local function MoveExit(point)
			local towers=TowerSafety.Observe(bot,'rune_fountain_leave')
			if not towers.available or not Geometry.ValidateMovementSegment(bot:GetLocation(),point,towers.towers,96)
				or not Geometry.ValidateLocalTerrainSegment(bot:GetLocation(),point,true) then return false end
			return RuneMove(bot,'rune_fountain_leave',point,0.4,48)
		end
		local point=task.exitStep
		if point and GetUnitToLocationDistance(bot,point)>48 and MoveExit(point) then return end
		for index,entry in ipairs(LocalRoutes.Journey(bot:GetLocation(),task.location,true)) do
			if index>18 then break end
			if MoveExit(entry.location) then task.exitStep=entry.location;return end
		end
		SetRuneOutcome('INVALID','fountain_exit_no_safe_step');return
	end

    if J.CanNotUseAction(bot)
	or bot:GetCurrentActionType() == BOT_ACTION_TYPE_PICK_UP_RUNE
	or (GetGameState() ~= GAME_STATE_PRE_GAME and GetGameState() ~= GAME_STATE_GAME_IN_PROGRESS)
	then
        return
    end

	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then
		SetRuneOutcome('INVALID','high_retreat')
		ClearActiveRuneTarget()
		ClearWisdomRuneMode()
		return
	end

	if wisdomRuneInfo[3] then
		return PickWisdomRune(task)
	end

    if DotaTime() < 0 then
        if DotaTime() < -25 then
            local vGoOutLocation = X.GetGoOutLocation()

            if GetUnitToLocationDistance(bot, vGoOutLocation) > 500 then
                RuneMove(bot, "rune_pre_go_out", vGoOutLocation, 0.5)
                return
            end

            J.ClearActionsThrottled(bot, 'rune_pre_go_out_clear', false, 1.0)
            return
        end

        if GetTeam() == TEAM_RADIANT
		then
			if bot:GetAssignedLane() == LANE_BOT
			then
				RuneMove(bot, "rune_pre_bounty_2", J.GetStableRandomLocation(bot, 'rune_pre_bounty_2', GetRuneSpawnLocation(RUNE_BOUNTY_2), 30, 60, 1.0), 0.5)
				return
            else
                RuneMove(bot, "rune_pre_power_1", J.GetStableRandomLocation(bot, 'rune_pre_power_1', GetRuneSpawnLocation(RUNE_POWERUP_1), 30, 60, 1.0), 0.5)
				return
			end
		else
			if bot:GetAssignedLane() == LANE_TOP
			then
				RuneMove(bot, "rune_pre_bounty_1", J.GetStableRandomLocation(bot, 'rune_pre_bounty_1', GetRuneSpawnLocation(RUNE_BOUNTY_1), 30, 60, 1.0), 0.5)
				return
            else
                RuneMove(bot, "rune_pre_power_2", J.GetStableRandomLocation(bot, 'rune_pre_power_2', GetRuneSpawnLocation(RUNE_POWERUP_2), 30, 60, 1.0), 0.5)
				return
			end
		end
    end

    local botAttackRange = bot:GetAttackRange() + 550
    if botAttackRange > 1400 then botAttackRange = 1400 end
    local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), botAttackRange)

	if idleRuneTask ~= nil then
		if bot:GetActiveModeDesire() <= 0 then SetRuneOutcome('INVALID','idle_rune_zero_desire');ClearActiveRuneTarget(); return end
		if not ValidateIdleRuneTask() then SetRuneOutcome('INVALID','idle_rune_invalid');ClearActiveRuneTarget(); return end
		ClosestRune = idleRuneTask.rune
	else
		-- 沿用OnStart/同模式交接的符点，执行时只刷新距离。
		if ClosestRune~=nil and ClosestRune~=-1 then ClosestDistance=GetUnitToLocationDistance(bot,GetRuneSpawnLocation(ClosestRune)) end
	end

	if ClosestRune == nil or ClosestRune == -1 then
		SetRuneOutcome('INVALID','missing_execution_target')
		return
	end

	local closestRuneLoc = GetRuneSpawnLocation(ClosestRune)
	if closestRuneLoc == nil then
		SetRuneOutcome('INVALID','missing_execution_location')
		return
	end

	ClosestDistance = GetUnitToLocationDistance(bot, closestRuneLoc)
	nRuneStatus = GetRuneStatus(ClosestRune)

	if idleRuneTask ~= nil then
		-- 低欲望接管只执行已验证的精确符点，不沿用普通分支的随机偏移或攻击转移。
		if not IdleRuneSafe(ClosestRune) then SetRuneOutcome('INVALID','idle_rune_unsafe');ClearActiveRuneTarget(); return end
		if ClosestDistance <= RUNE_PICKUP_DISTANCE then
			IssuePickup(task,false)
		else
			if not RuneMove(bot, 'idle_available_rune', closestRuneLoc, 0.35, 120) then SetRuneOutcome('INVALID','idle_rune_path_rejected') end
		end
		return
	end

	if nRuneStatus == RUNE_STATUS_AVAILABLE then
		if ClosestDistance <= RUNE_PICKUP_DISTANCE then
			IssuePickup(task,false)
			return
		end

		if ClosestDistance > RUNE_PICKUP_DISTANCE then
			if X.ShouldAbortRune(ClosestRune, closestRuneLoc, ClosestDistance) then
				SetRuneOutcome('INVALID','rune_enemy_intercept')
				X.MarkRuneAbandoned(ClosestRune)
				ClearActiveRuneTarget()
				J.ClearActionsThrottled(bot, 'rune_abort_enemy', false, 0.2)
				return
			end

			if J.IsValidHero(nEnemyHeroes[1])
            and J.GetHP(bot) > 0.65
            and J.GetHP(nEnemyHeroes[1]) < 0.45
            and bot:GetHealth() > 500
			then
				J.ActionAttackUnit(bot, "rune_attack_enemy", nEnemyHeroes[1], true, 0.35)
				return
			end

			if not RuneMove(bot, "rune_move_closest", J.GetStableRandomLocation(bot, 'rune_move_closest_'..tostring(ClosestRune), GetRuneSpawnLocation(ClosestRune), 15, 30, 0.8), 0.4) then SetRuneOutcome('INVALID','rune_path_rejected') end
			return
		end
	else
		if X.ShouldAbortRune(ClosestRune, closestRuneLoc, ClosestDistance) then
			SetRuneOutcome('INVALID','rune_missing_enemy_intercept')
			X.MarkRuneAbandoned(ClosestRune)
			ClearActiveRuneTarget()
			J.ClearActionsThrottled(bot, 'rune_abort_enemy_missing', false, 0.2)
			return
		end

        if J.IsValidHero(nEnemyHeroes[1])
        and J.GetHP(bot) > 0.65
        and J.GetHP(nEnemyHeroes[1]) < 0.45
        and bot:GetHealth() > 500
        then
            J.ActionAttackUnit(bot, "rune_attack_enemy_missing", nEnemyHeroes[1], true, 0.35)
            return
        end

		if not RuneMove(bot, "rune_move_spawn", GetRuneSpawnLocation(ClosestRune), 0.4) then SetRuneOutcome('INVALID','rune_spawn_path_rejected') end
		return
	end
 end

function PickWisdomRune(task)
	local observation=task and WisdomObservation(task.key)
	if not observation then SetRuneOutcome('INVALID','wisdom_observation_unavailable');return 0 end
	if observation.state=='empty' then
		MapResources.Log(bot,observation,'consumed','site_observed_empty')
		SetRuneOutcome('COMPLETE','wisdom_observed_empty');return 0
	end
	local wisdomLoc=observation.location
	if X.ShouldAbortWisdomRune(wisdomLoc) then
		SetRuneOutcome('INVALID','wisdom_enemy_intercept');MarkWisdomRuneAbandoned()
		J.ClearActionsThrottled(bot,'rune_wisdom_abort_enemy',false,0.2);return 0
	end
	local distance=GetUnitToLocationDistance(bot,wisdomLoc)
	if task.resourceClaimAt and distance>observation.radius then SetRuneOutcome('INVALID','wisdom_claim_area_left');return 0 end
	if observation.state=='ready' and distance<=1000 then
		local blocker=X.GetWisdomRuneBlocker(wisdomLoc)
		if blocker then
			J.ActionAttackUnit(bot,'rune_clear_wisdom_creep',blocker,true,0.35);return 1
		end
	end
	if distance<=math.max(64,observation.radius-32) then
		if observation.state=='unknown' then
			task.resourceUnknownUntil=task.resourceUnknownUntil or DotaTime()+2.5
			if DotaTime()>=task.resourceUnknownUntil then SetRuneOutcome('INVALID','wisdom_observation_timeout');return 0 end
			MapResources.Log(bot,observation,'unknown','await_visible_observation');return 1
		end
		if not task.resourceClaimAt then
			task.resourceClaimAt=DotaTime();task.resourceClaimUntil=math.min(task.deadline,DotaTime()+observation.countdown+2)
		end
		if DotaTime()>=task.resourceClaimUntil then SetRuneOutcome('INVALID','wisdom_claim_timeout');return 0 end
		-- 原生区域机制负责倒计时；不清动作队列，不再以本地等待时间宣称成功。
		MapResources.Log(bot,observation,'claiming','await_native_state_change');return 1
	end
	MapResources.Log(bot,observation,'approach',observation.state=='ready' and 'native_ready' or 'scout_unknown')
	local point,kind=SkillMovement.ResolveMove(bot,'rune_wisdom_move',wisdomLoc)
	if point==nil then SetRuneOutcome('INVALID','wisdom_no_safe_path');return 0 end
	if kind=='detour' then
		Actions.Move(bot,point,24);SkillMovement.NoteTaskMove(bot,'rune_wisdom_move',point,kind)
	else
		Actions.Move(bot,point,24,'direct');SkillMovement.NoteTaskMove(bot,'rune_wisdom_move',point,kind,BOT_ACTION_TYPE_MOVE_TO_DIRECTLY)
	end
	return 1
end

function X.IsSuitableToPickRune()
	if X.IsNearRune(bot) then return true end

	local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)

	if (bot:GetActiveMode() == BOT_MODE_RETREAT and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_HIGH)
	or (#nEnemyHeroes >= 1 and X.IsIBecameTheTarget(nEnemyHeroes))
	or (bot:WasRecentlyDamagedByAnyHero(4.0) and bot:GetActiveMode() == BOT_MODE_RETREAT)
	or (GetUnitToUnitDistance(bot, GetAncient(GetTeam())) < 2500 and DotaTime() > 0)
	or GetUnitToUnitDistance(bot, GetAncient(GetOpposingTeam())) < 4000
	then
		return false
	end

	return true
end

function X.IsNearRune(hUnit, nDistance)
	if nDistance == nil then nDistance = 600 end
	for _, rune in pairs(nRuneList) do
		local rLoc = GetRuneSpawnLocation(rune)
		if GetUnitToLocationDistance(hUnit, rLoc) <= nDistance then
			return true
		end
	end

	return false
end

function X.IsBountyRune(nRune)
	return nRune == RUNE_BOUNTY_1 or nRune == RUNE_BOUNTY_2
end

function X.IsOwnBountyRune(nRune)
	if not X.IsBountyRune(nRune) then return false end

	local runeLoc = GetRuneSpawnLocation(nRune)
	if runeLoc == nil then return false end

	return GetUnitToLocationDistance(GetAncient(GetTeam()), runeLoc)
		<= GetUnitToLocationDistance(GetAncient(GetOpposingTeam()), runeLoc)
end

function X.GetRuneAbortRadius(nRune)
	if X.IsBountyRune(nRune) and not X.IsOwnBountyRune(nRune) then
		return RUNE_DANGER_ABORT_RADIUS
	end

	if not X.IsBountyRune(nRune) then
		return RUNE_POWER_ABORT_RADIUS
	end

	return RUNE_SAFE_ABORT_RADIUS
end

function X.GetRuneAbandonSeconds(nRune)
	if X.IsBountyRune(nRune) and not X.IsOwnBountyRune(nRune) then
		return RUNE_DANGER_ABANDON_SECONDS
	end

	return RUNE_SAFE_ABANDON_SECONDS
end

function X.MarkRuneAbandoned(nRune)
	if nRune == nil or nRune == -1 then return end

	-- 普通符文遭遇拦截时只短期放弃，避免把未知符点误判为永久已拾取。
	bot.runeAbandonedUntil = bot.runeAbandonedUntil or {}
	bot.runeAbandonedUntil[nRune] = DotaTime() + X.GetRuneAbandonSeconds(nRune)
end

function X.IsRuneAbandoned(nRune)
	return bot.runeAbandonedUntil ~= nil
		and bot.runeAbandonedUntil[nRune] ~= nil
		and bot.runeAbandonedUntil[nRune] > DotaTime()
end

function X.ShouldAbortRune(nRune, runeLoc, runeDistance)
	if nRune == nil or nRune == -1 or runeLoc == nil then return true end
	if runeDistance == nil then runeDistance = GetUnitToLocationDistance(bot, runeLoc) end
	if runeDistance <= RUNE_PICKUP_DISTANCE then return false end

	local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), X.GetRuneAbortRadius(nRune))
	if #nEnemyHeroes >= 2 then
		return true
	end

	if not X.IsBountyRune(nRune) then
		-- 河道符靠近中路线，单个可见线上敌人不应直接阻止 bot 拿符。
		local nEnemyHeroesNearRune = J.GetEnemiesNearLoc(runeLoc, RUNE_POWER_ENEMY_NEAR_RUNE_RADIUS)
		if J.IsValidHero(nEnemyHeroesNearRune[1])
		and GetUnitToLocationDistance(nEnemyHeroesNearRune[1], runeLoc) + 150 < runeDistance
		then
			return true
		end

		if X.IsIBecameTheTarget(nEnemyHeroes) then
			return true
		end
	elseif J.IsValidHero(nEnemyHeroes[1]) then
		return true
	end

	if bot:WasRecentlyDamagedByAnyHero(4.0)
	and runeDistance > RUNE_PICKUP_DISTANCE * 2
	then
		return true
	end

	if X.IsSuitableToPickRune() == false then
		return true
	end

	return false
end

function X.IsIBecameTheTarget(hUnitList)
	for _, unit in pairs(hUnitList) do
        if J.IsValid(unit)
		and ((unit:GetAttackTarget() == bot and J.IsInRange(bot, unit, 700))
			or (J.IsInRange(bot, unit, unit:GetAttackRange() + 300) and J.IsChasingTarget(unit, bot)))
		then
			return true
		end
	end

	return false
end

function X.GetWisdomRuneBlocker(vWisdomLoc)
	local blocker = nil
	local blockerDistance = math.huge
	local unitLists = {
		bot:GetNearbyLaneCreeps(WISDOM_RUNE_CLEAR_RADIUS,true),
		bot:GetNearbyNeutralCreeps(WISDOM_RUNE_CLEAR_RADIUS),
	}

	for _, unitList in pairs(unitLists) do
		for _, unit in pairs(unitList or {}) do
			if J.IsValid(unit)
			and unit:IsCreep()
			and GetUnitToLocationDistance(unit, vWisdomLoc) <= WISDOM_RUNE_CLEAR_RADIUS
			then
				local distance = GetUnitToUnitDistance(bot, unit)
				if distance < blockerDistance then
					blocker = unit
					blockerDistance = distance
				end
			end
		end
	end

	return blocker
end

function X.IsWisdomRuneAbandoned(runeSpot)
	return bot.wisdomAbandoned ~= nil
		and bot.wisdomAbandoned[timeInMin] ~= nil
		and bot.wisdomAbandoned[timeInMin][runeSpot] == true
end

function X.ShouldAbortWisdomRune(vWisdomLoc)
	if vWisdomLoc == nil then return true end

	local distance = GetUnitToLocationDistance(bot, vWisdomLoc)
	local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), WISDOM_RUNE_ENEMY_ABORT_RADIUS)

	if #nEnemyHeroes >= 2 then
		return true
	end

	if J.IsValidHero(nEnemyHeroes[1]) then
		return true
	end

	local observation=wisdomRuneInfo[2] and WisdomObservation(wisdomRuneInfo[2])
	if distance > (observation and observation.radius or WISDOM_RUNE_PICKUP_RADIUS)
	and bot:WasRecentlyDamagedByAnyHero(4.0)
	then
		return true
	end

	if X.IsSuitableToPickRune() == false then
		return true
	end

	return false
end

function X.IsUnitAroundLocation(vLoc, nRadius)
    for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local info = GetHeroLastSeenInfo(id)
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil and J.GetDistance(vLoc, dInfo.location) <= nRadius and dInfo.time_since_seen < 1.0 then
					return true
				end
			end
		end
	end
	return false
end

function X.GetBotClosestRune()
    local cDist = 100000
	local cRune = -1

	for _, rune in pairs(nRuneList) do
		local rLoc = GetRuneSpawnLocation(rune)

        if X.IsTheClosestOne(rLoc, rune)
		and not X.IsMissing(rune)
		and not X.IsRuneAbandoned(rune)
        then
            local dist = GetUnitToLocationDistance(bot, rLoc)
            if dist < cDist then
                cDist = dist
                cRune = rune
            end
        end
	end

	return cRune, cDist
end

function X.GetBestRuneForThink()
	local availableRune = -1
	local availableDistance = math.huge
	local fallbackRune = -1
	local fallbackDistance = math.huge

	for _, rune in pairs(nRuneList) do
		local rLoc = GetRuneSpawnLocation(rune)
		if rLoc ~= nil
		and X.IsTheClosestOne(rLoc, rune)
		and not X.IsRuneAbandoned(rune)
		then
			local dist = GetUnitToLocationDistance(bot, rLoc)
			local status = GetRuneStatus(rune)
			if status == RUNE_STATUS_AVAILABLE
			and dist < availableDistance
			then
				availableRune = rune
				availableDistance = dist
			elseif status ~= RUNE_STATUS_MISSING
			and not IsRecentlyPickedRuneLocation(rLoc)
			and dist < fallbackDistance
			then
				fallbackRune = rune
				fallbackDistance = dist
			end
		end
	end

	if availableRune ~= -1
	and (availableDistance <= RUNE_CHAIN_PICKUP_DISTANCE or fallbackRune == -1)
	then
		return availableRune, availableDistance
	end

	if fallbackRune ~= -1 then
		return fallbackRune, fallbackDistance
	end

	return availableRune, availableDistance
end

function X.IsTheClosestOne(vLocation, nRuneLoc)
    local minDist = GetUnitToLocationDistance(bot, vLocation)
	local closest = bot
	local nRuneType = GetRuneType(nRuneLoc)

	if (J.IsMidGame() or J.IsLateGame()) and nRuneType == RUNE_DOUBLEDAMAGE
	and GetUnitToLocationDistance(bot, vLocation) <= 3500
	then
		return true
	end

	if nRuneType == RUNE_ARCANE
	and GetUnitToLocationDistance(bot, vLocation) <= 3500
	then
		return true
	end

    for i = 1, #GetTeamPlayers( GetTeam() ) do
        local member = GetTeamMember(i)
        if member ~= nil and member:IsAlive() then
			local dist = GetUnitToLocationDistance(member, vLocation)
			if dist < minDist then
				minDist = dist
				closest = member
			end
        end
    end

	return closest == bot
end

function X.IsPowerRune(nRuneLoc)
    local nRuneType = GetRuneType(nRuneLoc)

    if nRuneType == RUNE_DOUBLEDAMAGE
    or nRuneType == RUNE_HASTE
    or nRuneType == RUNE_ILLUSION
    or nRuneType == RUNE_INVISIBILITY
    or nRuneType == RUNE_REGENERATION
    or nRuneType == RUNE_ARCANE
	or nRuneType == RUNE_SHIELD
    then
        return true
    end

	return false
end

function X.IsMissing(nRune)
    nRuneStatus = GetRuneStatus(nRune)
	if second < 52 and nRuneStatus == RUNE_STATUS_MISSING then
		return true
	end

    return false
end

function X.IsEnemyPickRune(nRune)
	local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), 1600)
	local vRuneLocation = GetRuneSpawnLocation(nRune)

	if GetUnitToLocationDistance(bot, vRuneLocation) < 600 then return false end

	for _, enemy in pairs(nEnemyHeroes) do
        if J.IsValidHero(enemy)
        and (enemy:IsFacingLocation(vRuneLocation, 30) or GetUnitToLocationDistance(enemy, vRuneLocation) < 600)
        and (GetUnitToLocationDistance(enemy, vRuneLocation) < GetUnitToLocationDistance(bot, vRuneLocation) + 300)
		and (bot:WasRecentlyDamagedByAnyHero(6) and GetUnitToUnitDistance(bot, enemy) < enemy:GetAttackRange() + 300) -- 别被无脑a
        then
            return true
        end
	end

	if #nEnemyHeroes >= 2 then
		return true
	end

	return false
end

function X.GetScaledDesire(nBase, nCurrDist, nMaxDist, nCap, nNonLaningScale, nFarScale)
	if nCap == nil then nCap = 0.65 end
	if nNonLaningScale == nil then nNonLaningScale = 0.3 end
	if nFarScale == nil then nFarScale = 0.2 end
    local desire = Clamp(nBase + RemapValClamped(nCurrDist, 600, nMaxDist, 1 - nBase, 0), 0, nCap)
	if not J.IsInLaningPhase() then
		desire = desire * nNonLaningScale
	elseif bot:GetNetWorth() > 15000 then
		desire = desire * 0.6
	elseif GetUnitToLocationDistance(bot, J.GetEnemyFountain()) < 4300 then
		desire = desire * 0.2
	end

	if nCurrDist > 3300 and not J.IsInLaningPhase() then
		desire = desire * nFarScale
	end
	if DotaTime() > 1800 and nCurrDist > 3000 and J.Utils.CountMissingEnemyHeroes() >= 3 then
		desire = desire * 0.2
	end

	return RemapValClamped(J.GetHP(bot), 0.3, 0.8, desire * 0.3, desire)
end

function X.GetGoOutLocation()
	local nLane = bot:GetAssignedLane()
	local vLocation = J.Site.GetXUnitsTowardsLocation(GetTower(GetTeam(),TOWER_MID_2),GetTower(GetTeam(),TOWER_MID_1):GetLocation(),300)

	if nLane == LANE_BOT then
		vLocation = J.Site.GetXUnitsTowardsLocation(GetTower(GetTeam(),TOWER_BOT_2),GetTower(GetTeam(),TOWER_BOT_1):GetLocation(),300)
	elseif nLane == LANE_TOP then
		vLocation = J.Site.GetXUnitsTowardsLocation(GetTower(GetTeam(),TOWER_TOP_2),GetTower(GetTeam(),TOWER_TOP_1):GetLocation(),300)
	end

	return vLocation
end

function X.UpdateWisdom()
	if timeInMin >= 7 and timeInMin % 7 == 0 then
		for i = 1, #GetTeamPlayers( GetTeam() ) do
			local member = GetTeamMember(i)
			-- init
			if member ~= nil and member == bot then
				if bot.wisdom == nil then bot.wisdom = {} end
				if bot.wisdom[timeInMin] == nil then
					bot.wisdom[timeInMin] = { [1] = false, [2] = false } -- radi, dire
				end

				member.wisdom = bot.wisdom
			end

			-- update
			if member ~= nil
			and bot.wisdom ~= nil and bot.wisdom[timeInMin] ~= nil
			and member.wisdom ~= nil and member.wisdom[timeInMin] ~= nil
			then
				if member.wisdom[timeInMin][1] == true and bot.wisdom[timeInMin][1] == false then
					bot.wisdom[timeInMin][1] = true
				end

				if member.wisdom[timeInMin][2] == true and bot.wisdom[timeInMin][2] == false then
					bot.wisdom[timeInMin][2] = true
				end
			end
		end
	end
end

function X.GetMulTime()
	local currTime = math.floor(DotaTime() / 60)
	local currWisdomTime = math.floor(currTime / 7) * 7
	if currWisdomTime >= 7 and currWisdomTime > lastMin then
		lastMin = currWisdomTime
	end
	return lastMin
end

function X.GetWisdomAlly(vLoc)
	local target = nil
	local score = math.huge
	for i = 1, #GetTeamPlayers( GetTeam() ) do
		local member = GetTeamMember(i)
		if member ~= nil and member:IsAlive() then
			local dist = GetUnitToLocationDistance(member, vLoc)
			if dist < score then
				target = member
				score = dist
			end
		end
	end

	return target
end

function X.ShouldTryWisdomRune(vLoc)
	if bot == X.GetWisdomAlly(vLoc) then
		return true
	end

	return GetUnitToLocationDistance(bot, vLoc) <= WISDOM_RUNE_BACKUP_DISTANCE
		and X.IsSuitableToPickRune()
end

function X.GetWisdomDesire(vWisdomLoc)
	if (J.IsDefending(bot) and bot:GetActiveModeDesire() > 0.7)
	or J.IsInTeamFight(bot, 1600) then
		return 0
	end

	local nDesire = 0
	local botLevel = bot:GetLevel()
	local distFromLoc = GetUnitToLocationDistance(bot, vWisdomLoc)
	if J.Utils.CountMissingEnemyHeroes() >= 3 then
		distFromLoc = distFromLoc * 2
	end
	if botLevel < 12 then
		nDesire = RemapValClamped(distFromLoc, 5200, 300, BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_VERYHIGH )
	elseif botLevel < 18 then
		nDesire = RemapValClamped(distFromLoc, 5200, 300, BOT_ACTION_DESIRE_MODERATE , BOT_ACTION_DESIRE_HIGH )
	elseif botLevel < 25 then
		nDesire = RemapValClamped(distFromLoc, 5200, 300, BOT_ACTION_DESIRE_LOW, BOT_ACTION_DESIRE_HIGH )
	elseif botLevel < 30 then
		nDesire = RemapValClamped(distFromLoc, 5200, 300, BOT_ACTION_DESIRE_NONE , BOT_ACTION_DESIRE_HIGH )
	end

	return nDesire
end

function X.GetWisdomRuneSpot()
	if GetTeam() == TEAM_RADIANT then
		local dist1 = GetUnitToLocationDistance(bot, radiantWRLocation)
		local dist2 = GetUnitToLocationDistance(bot, direWRLocation)
		if dist1 < dist2 then
			return 1
		else
			local tier_1_tower = GetTower(GetOpposingTeam(), TOWER_BOT_1)
			if tier_1_tower == nil then
				return 2
			end
		end

		return 1
	elseif GetTeam() == TEAM_DIRE then
		local dist1 = GetUnitToLocationDistance(bot, radiantWRLocation)
		local dist2 = GetUnitToLocationDistance(bot, direWRLocation)
		if dist1 > dist2 then
			return 2
		else
			local tier_1_tower = GetTower(GetOpposingTeam(), TOWER_TOP_1)
			if tier_1_tower == nil then
				return 1
			end
		end

		return 2
	end

	return nil
end

function Think()
	local task=Tasks.Commit(bot,'rune')
	if not task then return end
	local valid,reason=ValidateRuneCandidate(task)
	if not valid then FinishRune(task,{status='INVALID',reason=reason});return end
	local safe,safetyReason=RuneMissionSafe()
	if not safe then FinishRune(task,{status='INVALID',reason=safetyReason});return end
	local pickup=PickupOutcome(task)
	if pickup then
		if pickup.status~='WAITING' then NotePickup(task,pickup.reason);FinishRune(task,pickup)
		else
			if not task.pickupRetried and DotaTime()>=task.pickupIssuedAt+0.35 and DotaTime()<task.pickupDeadline
				and bot:GetCurrentActionType()~=BOT_ACTION_TYPE_PICK_UP_RUNE
				and GetUnitToLocationDistance(bot,task.location)<=RUNE_PICKUP_DISTANCE then IssuePickup(task,true) end
			if not task.pickupActionLogAt or DotaTime()-task.pickupActionLogAt>=0.35 then
				task.pickupActionLogAt=DotaTime();NotePickup(task,'waiting')
			end
			LogRune('active',task,pickup.reason,task.score)
		end
		return
	end
	if not Tasks.Check(bot,'rune',true) then RejectRune(task,'task_invalid_or_no_progress');ClearActiveRuneTarget();ClearWisdomRuneMode();return end
	RestoreRuneState(task.snapshot)
	runeExecutionOutcome=nil
	ExecuteRuneTask(task)
	if runeExecutionOutcome then
		if runeExecutionOutcome.status~='WAITING' then FinishRune(task,runeExecutionOutcome);return end
		LogRune('active',task,runeExecutionOutcome.reason,task.score)
	end
	task.snapshot=CaptureRuneState()
end

GetDesire = Actions.GuardDesire(bot,BOT_MODE_RUNE,GetDesire)

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('rune', GetDesire)
