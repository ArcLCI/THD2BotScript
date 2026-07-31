local bot = GetBot()
local botName = bot:GetUnitName();
if bot == nil or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
local X = {}
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

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
local WISDOM_RUNE_PICKUP_RADIUS = 360
local WISDOM_RUNE_CONFIRM_SECONDS = 2.6
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
local wisdomRuneInfo = {0, 0, false} -- time, loc spot index, did pick
local timeInMin = 0
local Bottle = nil
local lastMin = 0
local runeModeStartTime = -9999
local wisdomRuneEnterTime = -9999
local lastRunePickupTime = -9999
local lastRunePickupLocation = nil

local function ClearWisdomRuneMode()
	wisdomRuneInfo[1] = 0
	wisdomRuneInfo[2] = nil
	wisdomRuneInfo[3] = false
	wisdomRuneEnterTime = -9999
end

local function MarkWisdomRunePicked()
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
	ClosestRune = -1
	ClosestDistance = -1
	nRuneStatus = -1
end

local function GetActiveRuneDesire()
	if wisdomRuneInfo[3] then
		if wisdomRuneInfo[2] == nil
		or bot.wisdom == nil
		or bot.wisdom[timeInMin] == nil
		or bot.wisdom[timeInMin][wisdomRuneInfo[2]] == true
		then
			ClearWisdomRuneMode()
			return BOT_MODE_DESIRE_NONE
		end

		local wisdomLoc = wisdomRuneSpots[wisdomRuneInfo[2]]
		if wisdomLoc ~= nil and X.ShouldAbortWisdomRune(wisdomLoc) then
			MarkWisdomRuneAbandoned()
			return BOT_MODE_DESIRE_NONE
		end

		if wisdomLoc ~= nil
		and GetUnitToLocationDistance(bot, wisdomLoc) <= WISDOM_RUNE_PICKUP_RADIUS
		then
			return BOT_MODE_DESIRE_ABSOLUTE
		end

		return RUNE_ACTIVE_STICKY_NEAR_DESIRE
	end

	if bot:GetActiveMode() ~= BOT_MODE_RUNE then return BOT_MODE_DESIRE_NONE end

	if ClosestRune == nil or ClosestRune == -1 then
		return BOT_MODE_DESIRE_NONE
	end

	if not X.IsSuitableToPickRune() then
		return BOT_MODE_DESIRE_NONE
	end

	local runeLoc = GetRuneSpawnLocation(ClosestRune)
	if runeLoc == nil then
		return BOT_MODE_DESIRE_NONE
	end

	ClosestDistance = GetUnitToLocationDistance(bot, runeLoc)
	if ClosestDistance > 6000 then
		return BOT_MODE_DESIRE_NONE
	end

	if X.ShouldAbortRune(ClosestRune, runeLoc, ClosestDistance) then
		X.MarkRuneAbandoned(ClosestRune)
		ClearActiveRuneTarget()
		return BOT_MODE_DESIRE_NONE
	end

	nRuneStatus = GetRuneStatus(ClosestRune)
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
	if not Utils.AllowModeDesire(bot, 'rune') then return BOT_MODE_DESIRE_NONE end
	if not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() or bot.isBear then return BOT_MODE_DESIRE_NONE end
    if DotaTime() > 2 * 60 and DotaTime() < 6 * 60 and GetUnitToLocationDistance(bot, GetRuneSpawnLocation(RUNE_POWERUP_2)) < 150
	then
        return 0
    end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE
	end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() - J.Utils.GameStates.recentDefendTime < 2 then
		return BOT_MODE_DESIRE_NONE
	end

    botActiveMode = bot:GetActiveMode()

	if bot:IsInvulnerable() and J.GetHP(bot) > 0.95 and bot:DistanceFromFountain() < 100 then
        return BOT_MODE_DESIRE_ABSOLUTE
    end

	local activeRuneDesire = GetActiveRuneDesire()
	if activeRuneDesire > BOT_MODE_DESIRE_NONE then
		return activeRuneDesire
	end

	local runeDesireInterval = RUNE_DESIRE_MID_INTERVAL
	if DotaTime() < 0 then
		runeDesireInterval = RUNE_DESIRE_EARLY_INTERVAL
	elseif DotaTime() > 20 * 60 then
		runeDesireInterval = RUNE_DESIRE_LATE_INTERVAL
	end

	if not Timer.ShouldRunBotTask(bot, 'rune_desire', runeDesireInterval, RUNE_DESIRE_STAGGER) then
		return BOT_MODE_DESIRE_NONE
	end

	local wrDesire = ConsiderWisdomRune()
	if wrDesire > 0.1 then
		return wrDesire
	end

	if DotaTime() > RUNE_LATE_GAME_TIME and not X.IsNearRune(bot, RUNE_LATE_NEAR_DISTANCE) then
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() > 30 * 60 and not X.IsNearRune(bot, RUNE_VERY_LATE_NEAR_DISTANCE) then
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() > -10 and bot:GetCurrentActionType() == BOT_ACTION_TYPE_IDLE then
		return BOT_MODE_DESIRE_NONE
	end

    minute = math.floor(DotaTime() / 60)
    second = DotaTime() % 60

    if not X.IsSuitableToPickRune() then
        return BOT_MODE_DESIRE_NONE
    end

    if DotaTime() < 0 and not bot:WasRecentlyDamagedByAnyHero(5.0)
    then
        local nEnemyHeroes = J.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 2000)
        if #nEnemyHeroes <= 1 then
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
			return 0
		end

		if X.IsEnemyPickRune(ClosestRune) then
			X.MarkRuneAbandoned(ClosestRune)
			return 0
		end

        if ClosestRune == RUNE_BOUNTY_1 or ClosestRune == RUNE_BOUNTY_2 then
            if nRuneStatus == RUNE_STATUS_AVAILABLE then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					if J.IsInLaningPhase() then
						return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.82)
					end

					return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.78, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
				end

                return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.82, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
            elseif nRuneStatus == RUNE_STATUS_UNKNOWN
                and DotaTime() > 2 * 60 + 50
                and ((minute % 3 == 0) or (minute % 3 == 2 and second > 45))
            then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					if J.IsInLaningPhase() then
						return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.78)
					end

					return X.GetScaledDesire(BOT_MODE_DESIRE_LOW, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.72, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
				end

                return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.82, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
            elseif nRuneStatus == RUNE_STATUS_MISSING
                and DotaTime() > 2 * 60
                and (minute % 3 == 2 and second > 52)
            then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					return X.GetScaledDesire(BOT_MODE_DESIRE_LOW, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.70, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
				end

                return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, RUNE_BOUNTY_MAX_DIST, 0.76, RUNE_BOUNTY_NON_LANING_SCALE, 0.45)
            end
        else
            if nRuneStatus == RUNE_STATUS_AVAILABLE then
				if nRuneType == RUNE_WATER and (J.GetHP(bot) < 0.6 or J.GetMP(bot) < 0.5) then
					return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, 3200)
				else
					if nRuneType == RUNE_WATER then
						return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST)
					else
						if X.IsPowerRune(ClosestRune) then
							return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, MAX_DIST * RUNE_POWER_MAX_DIST_MULTIPLIER, 0.85, RUNE_POWER_NON_LANING_SCALE, 0.55)
						else
							return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * 2.5)
						end
					end
				end
            elseif nRuneStatus == RUNE_STATUS_UNKNOWN
                and DotaTime() > 113
            then
				if DotaTime() > 5 * 60 then
					if X.IsPowerRune(ClosestRune) then
						return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * RUNE_POWER_MAX_DIST_MULTIPLIER, 0.78, RUNE_POWER_NON_LANING_SCALE, 0.55)
					end

					return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * 2.5)
				else
					return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST)
				end
            elseif nRuneStatus == RUNE_STATUS_MISSING
                and DotaTime() > 60
                and (minute % 2 == 1 and second > 53)
            then
                return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST)
            end
        end
    end

    return 0
end

function ConsiderWisdomRune()
	if bot:GetLevel() < 30 then
		timeInMin = X.GetMulTime()
		X.UpdateWisdom()
		if DotaTime() >= 7 * 60 then
			if DotaTime() < wisdomRuneInfo[1] + 3.5 then
				local activeWisdomSpot = wisdomRuneInfo[2]
				local activeWisdomLoc = activeWisdomSpot ~= nil and wisdomRuneSpots[activeWisdomSpot] or nil
				if activeWisdomLoc == nil then
					ClearWisdomRuneMode()
					return 0
				end
				if GetUnitToLocationDistance(bot, activeWisdomLoc) < 50 then
					return 0
				end
				if not bot:WasRecentlyDamagedByAnyHero(3.0) then
					return BOT_MODE_DESIRE_HIGH
				end
			else
				ClearWisdomRuneMode()
			end

			local tEnemyTowers = bot:GetNearbyTowers(700, true)
			local tEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)
			if (#tEnemyTowers > 0 and bot:WasRecentlyDamagedByTower(1.0) and J.GetHP(bot) < 0.3)
			or #tEnemyHeroes > 0 then
				return 0
			end

			local runeSpot = X.GetWisdomRuneSpot()
			if runeSpot ~= nil
			and bot.wisdom ~= nil
			and bot.wisdom[timeInMin] ~= nil
			and wisdomRuneSpots[runeSpot] ~= nil
			and bot.wisdom[timeInMin][runeSpot] == false
			and not X.IsWisdomRuneAbandoned(runeSpot)
			and X.ShouldTryWisdomRune(wisdomRuneSpots[runeSpot]) then
				wisdomRuneInfo[1] = DotaTime()
				wisdomRuneInfo[2] = runeSpot
				wisdomRuneInfo[3] = true
				wisdomRuneEnterTime = -9999
				return X.GetWisdomDesire(wisdomRuneSpots[runeSpot])
			end
		end
	else
		ClearWisdomRuneMode()
	end
	return 0
end

function GetDesire()
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then
		ClearActiveRuneTarget()
		ClearWisdomRuneMode()
		return BOT_MODE_DESIRE_NONE
	end
	return Utils.GetCachedModeDesire(bot, 'rune', ComputeDesire)
end

function OnStart()
	Utils.NoteModeStart(bot, 'rune')
	runeModeStartTime = DotaTime()
end

function OnEnd()
	runeModeStartTime = -9999
end

function Think()
    if not Timer.ShouldRunBotTask(bot, 'rune_think', 0.25, 0.04) then return end
    if bot:IsInvulnerable()
    and J.GetHP(bot) > 0.95
    and bot:DistanceFromFountain() < 100 then
        J.ActionMoveToLocation(bot, "rune_fountain_leave", J.GetStableRandomLocation(bot, 'rune_fountain_leave', bot:GetLocation(), 450, 550, 1.5), 0.5)
        return
    end

    if J.CanNotUseAction(bot)
	or bot:GetCurrentActionType() == BOT_ACTION_TYPE_PICK_UP_RUNE
	or (GetGameState() ~= GAME_STATE_PRE_GAME and GetGameState() ~= GAME_STATE_GAME_IN_PROGRESS)
	then
        return
    end

	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then
		ClearActiveRuneTarget()
		ClearWisdomRuneMode()
		return
	end

	if wisdomRuneInfo[3] then
		return PickWisdomRune()
	end

    if DotaTime() < 0 then
        if DotaTime() < -25 then
            local vGoOutLocation = X.GetGoOutLocation()

            if GetUnitToLocationDistance(bot, vGoOutLocation) > 500 then
                J.ActionMoveToLocation(bot, "rune_pre_go_out", vGoOutLocation, 0.5)
                return
            end

            J.ClearActionsThrottled(bot, 'rune_pre_go_out_clear', false, 1.0)
            return
        end

        if GetTeam() == TEAM_RADIANT
		then
			if bot:GetAssignedLane() == LANE_BOT
			then
				J.ActionMoveToLocation(bot, "rune_pre_bounty_2", J.GetStableRandomLocation(bot, 'rune_pre_bounty_2', GetRuneSpawnLocation(RUNE_BOUNTY_2), 30, 60, 1.0), 0.5)
				return
            else
                J.ActionMoveToLocation(bot, "rune_pre_power_1", J.GetStableRandomLocation(bot, 'rune_pre_power_1', GetRuneSpawnLocation(RUNE_POWERUP_1), 30, 60, 1.0), 0.5)
				return
			end
		else
			if bot:GetAssignedLane() == LANE_TOP
			then
				J.ActionMoveToLocation(bot, "rune_pre_bounty_1", J.GetStableRandomLocation(bot, 'rune_pre_bounty_1', GetRuneSpawnLocation(RUNE_BOUNTY_1), 30, 60, 1.0), 0.5)
				return
            else
                J.ActionMoveToLocation(bot, "rune_pre_power_2", J.GetStableRandomLocation(bot, 'rune_pre_power_2', GetRuneSpawnLocation(RUNE_POWERUP_2), 30, 60, 1.0), 0.5)
				return
			end
		end
    end

    local botAttackRange = bot:GetAttackRange() + 550
    if botAttackRange > 1400 then botAttackRange = 1400 end
    local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), botAttackRange)

	ClosestRune, ClosestDistance = X.GetBestRuneForThink()

	if ClosestRune == nil or ClosestRune == -1 then
		return
	end

	local closestRuneLoc = GetRuneSpawnLocation(ClosestRune)
	if closestRuneLoc == nil then
		return
	end

	ClosestDistance = GetUnitToLocationDistance(bot, closestRuneLoc)
	nRuneStatus = GetRuneStatus(ClosestRune)

	if nRuneStatus == RUNE_STATUS_AVAILABLE then
		if ClosestDistance <= RUNE_PICKUP_DISTANCE then
			bot:Action_PickUpRune(ClosestRune)
			lastRunePickupTime = DotaTime()
			lastRunePickupLocation = closestRuneLoc
			ClosestRune = -1
			ClosestDistance = -1
			return
		end

		if ClosestDistance > RUNE_PICKUP_DISTANCE then
			if X.ShouldAbortRune(ClosestRune, closestRuneLoc, ClosestDistance) then
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

			J.ActionMoveToLocation(bot, "rune_move_closest", J.GetStableRandomLocation(bot, 'rune_move_closest_'..tostring(ClosestRune), GetRuneSpawnLocation(ClosestRune), 15, 30, 0.8), 0.4)
			return
		end
	else
		if X.ShouldAbortRune(ClosestRune, closestRuneLoc, ClosestDistance) then
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

		J.ActionMoveToLocation(bot, "rune_move_spawn", GetRuneSpawnLocation(ClosestRune), 0.4)
		return
	end
 end

function PickWisdomRune()
	local wisdomLoc = wisdomRuneSpots[wisdomRuneInfo[2]]
	if wisdomLoc == nil then
		ClearWisdomRuneMode()
		return 0
	end

	local blocker = X.GetWisdomRuneBlocker(wisdomLoc)
	if blocker ~= nil then
		wisdomRuneEnterTime = -9999
		J.ActionAttackUnit(bot, 'rune_clear_wisdom_creep', blocker, true, 0.35)
		return 1
	end

	local distance = GetUnitToLocationDistance(bot, wisdomLoc)
	if bot.wisdom ~= nil
	and bot.wisdom[timeInMin] ~= nil
	and wisdomRuneInfo[2] ~= nil
	and bot.wisdom[timeInMin][wisdomRuneInfo[2]] == true
	then
		ClearWisdomRuneMode()
		return 0
	end

	if X.ShouldAbortWisdomRune(wisdomLoc) then
		MarkWisdomRuneAbandoned()
		J.ClearActionsThrottled(bot, 'rune_wisdom_abort_enemy', false, 0.2)
		return 0
	end

	if distance <= WISDOM_RUNE_PICKUP_RADIUS then
		if wisdomRuneEnterTime < 0 then
			wisdomRuneEnterTime = DotaTime()
		end

		if DotaTime() - wisdomRuneEnterTime >= WISDOM_RUNE_CONFIRM_SECONDS then
			MarkWisdomRunePicked()
			return 0
		end

		J.ClearActionsThrottled(bot, 'rune_wisdom_wait_pickup', false, 0.5)
		return 1
	else
		wisdomRuneEnterTime = -9999
	end

	bot:Action_MoveDirectly(wisdomLoc + RandomVector(15))
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
		UNIT_LIST_ENEMY_CREEPS,
		UNIT_LIST_NEUTRAL_CREEPS,
	}

	for _, unitList in pairs(unitLists) do
		for _, unit in pairs(GetUnitList(unitList)) do
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

	if distance > WISDOM_RUNE_PICKUP_RADIUS
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
