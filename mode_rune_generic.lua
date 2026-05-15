local bot = GetBot()
local botName = bot:GetUnitName();
if bot == nil or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
local X = {}
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local RUNE_DESIRE_EARLY_INTERVAL = 0.35
local RUNE_DESIRE_MID_INTERVAL = 0.9
local RUNE_DESIRE_LATE_INTERVAL = 3.0
local RUNE_DESIRE_STAGGER = 0.11
local RUNE_LATE_GAME_TIME = 20 * 60
local RUNE_LATE_NEAR_DISTANCE = 900
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

function GetDesire()
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

	if DotaTime() > 30 * 60 and not X.IsNearRune(bot, 450) then
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

		if X.IsEnemyPickRune(ClosestRune) then return 0 end

        if ClosestRune == RUNE_BOUNTY_1 or ClosestRune == RUNE_BOUNTY_2 then
            if nRuneStatus == RUNE_STATUS_AVAILABLE then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					return X.GetScaledDesire(BOT_MODE_DESIRE_VERYLOW, ClosestDistance, 3500)
				end

                return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, 3500)
            elseif nRuneStatus == RUNE_STATUS_UNKNOWN
                and DotaTime() > 2 * 60 + 50
                and ((minute % 3 == 0) or (minute % 3 == 2 and second > 45))
            then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					return X.GetScaledDesire(BOT_MODE_DESIRE_VERYLOW, ClosestDistance, MAX_DIST)
				end

                return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, MAX_DIST)
            elseif nRuneStatus == RUNE_STATUS_MISSING
                and DotaTime() > 2 * 60
                and (minute % 3 == 2 and second > 52)
            then
				if DotaTime() > 2 * 60 and DotaTime() < 20 * 60 then
					return X.GetScaledDesire(BOT_MODE_DESIRE_VERYLOW, ClosestDistance, MAX_DIST)
				end

                return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * 2)
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
							return X.GetScaledDesire(BOT_MODE_DESIRE_HIGH, ClosestDistance, MAX_DIST * 2.5)
						else
							return X.GetScaledDesire(BOT_MODE_DESIRE_MODERATE, ClosestDistance, MAX_DIST * 2.5)
						end
					end
				end
            elseif nRuneStatus == RUNE_STATUS_UNKNOWN
                and DotaTime() > 113
            then
				if DotaTime() > 5 * 60 then
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
					wisdomRuneInfo[1] = 0
					wisdomRuneInfo[2] = nil
					wisdomRuneInfo[3] = false
					return 0
				end
				if GetUnitToLocationDistance(bot, activeWisdomLoc) < 50 then
					return 0
				end
				if not bot:WasRecentlyDamagedByAnyHero(3.0) then
					return BOT_MODE_DESIRE_HIGH
				end
			else
				wisdomRuneInfo[1] = 0
				wisdomRuneInfo[3] = false
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
			and bot == X.GetWisdomAlly(wisdomRuneSpots[runeSpot]) then
				wisdomRuneInfo[2] = runeSpot
				wisdomRuneInfo[3] = true
				return X.GetWisdomDesire(wisdomRuneSpots[runeSpot])
			end
		end
	else
		wisdomRuneInfo[3] = false
	end
	return 0
end

function OnStart()

end

function OnEnd()

end

function Think()
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
	nRuneStatus = GetRuneStatus(ClosestRune)

	if nRuneStatus == RUNE_STATUS_AVAILABLE then
		if ClosestDistance > 50 then
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
		else
			bot:Action_PickUpRune(ClosestRune)
			return
		end
	else
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
	local distance = GetUnitToLocationDistance(bot, wisdomRuneSpots[wisdomRuneInfo[2]])
	if distance < 75
	or (distance < 1800 and bot:WasRecentlyDamagedByAnyHero(2) and (wisdomRuneInfo[2] + 1) ~= GetTeam()) -- if encountered an enemy on the way, assume enemy had noticed and would go pick it.
	then
		if bot.wisdom[timeInMin][wisdomRuneInfo[2]] == false then
			wisdomRuneInfo[1] = DotaTime()
		end
		bot.wisdom[timeInMin][wisdomRuneInfo[2]] = true
	end

	bot:Action_MoveDirectly(wisdomRuneSpots[wisdomRuneInfo[2]] + RandomVector(15))
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

function X.GetScaledDesire(nBase, nCurrDist, nMaxDist)
    local desire = Clamp(nBase + RemapValClamped(nCurrDist, 600, nMaxDist, 1 - nBase, 0), 0, 0.65)
	if not J.IsInLaningPhase() then
		desire = desire * 0.3
	elseif bot:GetNetWorth() > 15000 then
		desire = desire * 0.6
	elseif GetUnitToLocationDistance(bot, J.GetEnemyFountain()) < 4300 then
		desire = desire * 0.2
	end

	if nCurrDist > 3300 and not J.IsInLaningPhase() then
		desire = desire * 0.2
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
	if currTime > lastMin and currTime % 7 == 0 then
		lastMin = currTime
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
		nDesire = RemapValClamped(distFromLoc, 4000, 300, BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_VERYHIGH )
	elseif botLevel < 18 then
		nDesire = RemapValClamped(distFromLoc, 4000, 300, BOT_ACTION_DESIRE_LOW , BOT_ACTION_DESIRE_HIGH )
	elseif botLevel < 25 then
		nDesire = RemapValClamped(distFromLoc, 4000, 300, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH )
	elseif botLevel < 30 then
		nDesire = RemapValClamped(distFromLoc, 4000, 300, BOT_ACTION_DESIRE_NONE , BOT_ACTION_DESIRE_MODERATE )
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