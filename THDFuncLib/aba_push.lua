local Push = {}
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local pingTimeDelta = 5
local StartToPushTime = 9 * 60 -- after x mins, start considering to push.
local weAreStronger = false
local nEffctiveEnemyHeroesNearPushLoc = 0
local teamAveLvl = 0
local enemyTeamAveLvl = 0
local nInRangeAlly
local nInRangeEnemy
local hEnemyAncient
local BOT_MODE_DESIRE_EXTRA_LOW = 0.02
local PUSH_DESIRE_CACHE_INTERVAL = 0.75
local PUSH_DESIRE_STAGGER_INTERVAL = 0.08

function Push.GetPushDesire(bot, lane)
    return Timer.GetOrComputeBotLane('PushDesire', bot, lane, PUSH_DESIRE_CACHE_INTERVAL, function()
        return Push.ComputePushDesire(bot, lane)
    end, PUSH_DESIRE_STAGGER_INTERVAL)
end

function Push.ComputePushDesire(bot, lane)
    if bot.laneToPush == nil then bot.laneToPush = lane end

    local nMaxDesire = 0.9
    local nSearchRange = 2000
    local botActiveMode = bot:GetActiveMode()
    local nModeDesire = bot:GetActiveModeDesire()
    local bMyLane = bot:GetAssignedLane() == lane
    local isMidOrEarlyGame = J.IsEarlyGame() or J.IsMidGame()
    hEnemyAncient = GetAncient(GetOpposingTeam())
    nInRangeAlly = J.GetAlliesNearLoc(bot:GetLocation(), 1600)
    nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1600)

    if botActiveMode == BOT_MODE_PUSH_TOWER_TOP then
		bot.laneToPush = LANE_TOP
	elseif botActiveMode == BOT_MODE_PUSH_TOWER_MID then
		bot.laneToPush = LANE_MID
	elseif botActiveMode == BOT_MODE_PUSH_TOWER_BOT then
		bot.laneToPush = LANE_BOT
	end

    -- do not push too early.
    local currentTime = DotaTime()

	if (bot:GetAssignedLane() == LANE_MID and J.IsInLaningPhase())
    or (J.IsDoingRoshan(bot) and J.GetRoshanTeamState(2800).isDoingRoshanWithTeam)
	then
		return BOT_MODE_DESIRE_EXTRA_LOW
	end

	for i = 1, #GetTeamPlayers( GetTeam() )
    do
		local member = GetTeamMember(i)
        if member ~= nil and member:GetLevel() < 7 then return BOT_MODE_DESIRE_EXTRA_LOW end
    end

    weAreStronger = J.WeAreStronger(bot, nSearchRange)
    local laneFront = GetLaneFrontLocation(GetTeam(), lane, 0)
    local distanceToLaneFront = GetUnitToLocationDistance(bot, laneFront)
    local lEnemyHeroesAroundLoc = J.GetLastSeenEnemiesNearLoc(laneFront, nSearchRange)
    nEffctiveEnemyHeroesNearPushLoc = #lEnemyHeroesAroundLoc + #J.Utils.GetAllyIdsInTpToLocation(laneFront, nSearchRange)
    local nMissingEnemyHeroes = J.Utils.CountMissingEnemyHeroes()
    teamAveLvl = J.GetAverageLevel( false )
    enemyTeamAveLvl = J.GetAverageLevel( true )

    if #nInRangeAlly < #nInRangeEnemy
    or #nInRangeAlly <= 1 and #nInRangeEnemy > 0
    then
        return BOT_MODE_DESIRE_EXTRA_LOW
    end

	if J.IsDefending(bot) and nModeDesire >= 0.8
    then
        nMaxDesire = 0.75
    end

    local aAliveCount = J.GetNumOfAliveHeroes(false)
    local eAliveCount = J.GetNumOfAliveHeroes(true)
    local hAncient = GetAncient(GetTeam())
    local nPushDesire = GetPushLaneDesire(lane)
    local allyKills = J.GetNumOfTeamTotalKills(false) + 1
    local enemyKills = J.GetNumOfTeamTotalKills(true) + 1
    local teamKillsRatio = allyKills / enemyKills

    local distanceToEnemyAncient = GetUnitToUnitDistance(bot, hEnemyAncient)
    local ancientDefenseState = J.GetAncientDefenseState(4500)
    local nEffctiveAllyHeroesNearAncient = ancientDefenseState.effectiveAllyCount
	local nEnemyUnitsAroundAncient = ancientDefenseState.enemyPressure
    if nEnemyUnitsAroundAncient > 0 and nEffctiveAllyHeroesNearAncient < 1
    then
        nMaxDesire = 0.55
    end
    if nEffctiveAllyHeroesNearAncient >= 1 then
        nPushDesire = nPushDesire * 0.5
    end

    -- 如果有重要物品或技能在cd，且敌人英雄数量大于我方英雄数量，则不上高
    local vEnemyLaneFrontLocation = GetLaneFrontLocation(GetOpposingTeam(), lane, 0)
    if Push.ShouldWaitForImportantItemsSpells(vEnemyLaneFrontLocation)
    and eAliveCount >= aAliveCount then
        return BOT_MODE_DESIRE_VERYLOW
    end

    local botTarget = bot:GetAttackTarget()
    if J.IsValidBuilding(botTarget)
    and not string.find(botTarget:GetUnitName(), 'tower1')
    and not string.find(botTarget:GetUnitName(), 'tower2')
    then
        if Push.HasBackdoorProtect(botTarget)
        then
            return BOT_MODE_DESIRE_EXTRA_LOW
        end
    end
    
    if distanceToEnemyAncient < nSearchRange * 0.8
    and J.CanBeAttacked(hEnemyAncient)
    and not bot:WasRecentlyDamagedByAnyHero(1)
    and J.GetHP(bot) > 0.5
    and not Push.HasBackdoorProtect(hEnemyAncient)
    then
        bot:SetTarget(hEnemyAncient)
        bot:Action_AttackUnit(hEnemyAncient, true)
        return BOT_ACTION_DESIRE_ABSOLUTE * 0.98
    end

    local pushLane = Push.WhichLaneToPush(bot, lane)
    local isCurrentLanePushLane = pushLane == lane

    -- General Push
    if isCurrentLanePushLane
    or ((J.IsLateGame() and isCurrentLanePushLane) or isMidOrEarlyGame)
    then
        if eAliveCount == 0
        or aAliveCount >= eAliveCount
        then
            if J.DoesTeamHaveAegis() then
                nPushDesire = nPushDesire + 0.3
            end
            return RemapValClamped(nPushDesire, 0, 1, 0, nMaxDesire)
        end
    end

    return lane == LANE_MID and BOT_MODE_DESIRE_VERYLOW or BOT_MODE_DESIRE_EXTRA_LOW
end

function Push.WhichLaneToPush(bot, lane)
    local cacheKey = 'PushWhichLaneToPush-'..tostring(GetTeam())
    local cachedLane = J.Utils.GetCachedVars(cacheKey, 1.0)
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
                if dInfo ~= nil then
                    if     J.GetDistance(vLaneFrontLocationTop, dInfo.location) <= 1600 then
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

    topLaneScore = topLaneScore * (0.05 * count1 + 1)
    midLaneScore = midLaneScore * (0.05 * count2 + 1)
    botLaneScore = botLaneScore * (0.05 * count3 + 1)

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

    if  topLaneScore < midLaneScore
    and topLaneScore < botLaneScore
    then
        J.Utils.SetCachedVars(cacheKey, LANE_TOP)
        return LANE_TOP
    end

    if  midLaneScore < topLaneScore
    and midLaneScore < botLaneScore
    then
        J.Utils.SetCachedVars(cacheKey, LANE_MID)
        return LANE_MID
    end

    if  botLaneScore < topLaneScore
    and botLaneScore < midLaneScore
    then
        J.Utils.SetCachedVars(cacheKey, LANE_BOT)
        return LANE_BOT
    end

    J.Utils.SetCachedVars(cacheKey, LANE_MID)
    return LANE_MID
end

local fNextMovementTime = 0
function Push.PushThink(bot, lane)
    if J.CanNotUseAction(bot) then return end

    local botAttackRange = bot:GetAttackRange()
    local fDeltaFromFront = (Min(J.GetHP(bot), 0.7) * 1000 - 700) + RemapValClamped(botAttackRange, 300, 700, 0, -600)
    local nEnemyTowers = bot:GetNearbyTowers(1600, true)
    local nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)

    if #nInRangeAlly < #nInRangeEnemy or Push.IsBuildingGlyphedBackdoor() then
        local nEnemyHeroLongestAttackRange = 0
        for _, enemyHero in pairs(nInRangeEnemy) do
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

    if J.IsValidBuilding(nEnemyTowers[1]) and (nEnemyTowers[1]:GetAttackTarget() == bot or (nEnemyTowers[1]:GetAttackTarget() ~= bot and bot:WasRecentlyDamagedByTower(#nAllyCreeps <= 2 and 4.0 or 2.0))) then
        local nDamage = nEnemyTowers[1]:GetAttackDamage() * nEnemyTowers[1]:GetAttackSpeed() * 5.0 - bot:GetHealthRegen() * 5.0
        if (bot:GetActualIncomingDamage(nDamage, DAMAGE_TYPE_PHYSICAL) / bot:GetHealth() > 0.15)
        or #nAllyCreeps > 2
        then
            local vLocation = GetLaneFrontLocation(GetTeam(), lane, -1200)
            bot:Action_MoveToLocation(vLocation)
            return
        end
    end

    if GetUnitToUnitDistance(bot, hEnemyAncient) <= 3200
    and (   GetTower(GetOpposingTeam(), TOWER_TOP_2) == nil
        and GetTower(GetOpposingTeam(), TOWER_MID_2) == nil
        and GetTower(GetOpposingTeam(), TOWER_BOT_2) == nil)
    then
        local hBuildingTarget = TryClearingOtherLaneHighGround(bot, targetLoc)
        if hBuildingTarget then
            bot:Action_AttackUnit(hBuildingTarget, true)
            return
        end
    end

    nInRangeAlly = J.GetAlliesNearLoc(hEnemyAncient:GetLocation(), 1600)
    if GetUnitToUnitDistance(bot, hEnemyAncient) < 1600
    and J.CanBeAttacked(hEnemyAncient)
    and not Push.HasBackdoorProtect(hEnemyAncient)
    and (#Push.GetAllyHeroesAttackingUnit(hEnemyAncient) >= 3
        or #Push.GetAllyCreepsAttackingUnit(hEnemyAncient) >= 4
        or hEnemyAncient:GetHealthRegen() < 20
        or #nInRangeAlly >= 4)
    then
        bot:Action_AttackUnit(hEnemyAncient, true)
        return
    end

    local nRange = math.min(700 + botAttackRange, 1600)

    local nCreeps = bot:GetNearbyLaneCreeps(nRange, true)
    if bot:GetLevel() >= 12 then
        nCreeps = bot:GetNearbyCreeps(nRange, true)
    end
    nCreeps = Push.GetSpecialUnitsNearby(bot, nCreeps, nRange)

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
            bot:Action_AttackUnit(creep, true)
            return
        end
    end

    local nBarracks = bot:GetNearbyBarracks(nRange, true)
    if J.IsValidBuilding(nBarracks[1]) and J.CanBeAttacked(nBarracks[1]) then
        for _, barrack in pairs(nBarracks) do
            if J.IsValid(barrack) and string.find(barrack:GetUnitName(), 'melee') then
                bot:Action_AttackUnit(barrack, true)
                return
            end
        end
        for _, barrack in pairs(nBarracks) do
            if J.IsValid(barrack) and string.find(barrack:GetUnitName(), 'range') then
                bot:Action_AttackUnit(barrack, true)
                return
            end
        end
    end

    if J.IsValidBuilding(nEnemyTowers[1]) and J.CanBeAttacked(nEnemyTowers[1]) then
        local hTowerTarget = nil
        local hTowerTargetDistance = math.huge
        for _, tower in pairs(nEnemyTowers) do
            if J.IsValidBuilding(tower) and J.CanBeAttacked(tower) then
                local towerDistance = GetUnitToLocationDistance(tower, targetLoc)
                if towerDistance < hTowerTargetDistance then
                    hTowerTarget = tower
                    hTowerTargetDistance = towerDistance
                end
            end
        end

        if hTowerTarget then
            bot:Action_AttackUnit(hTowerTarget, true)
            return
        end
    end

    local nEnemyFillers = bot:GetNearbyFillers(nRange, true)
    if J.IsValidBuilding(nEnemyFillers[1]) and J.CanBeAttacked(nEnemyFillers[1]) then
        local hTowerFillerTarget = nil
        local hTowerFillerTargetDistance = math.huge
        for _, filler in pairs(nEnemyFillers) do
            if J.CanBeAttacked(filler) then
                local fillerTowerDistance = GetUnitToLocationDistance(filler, targetLoc)
                if fillerTowerDistance < hTowerFillerTargetDistance then
                    hTowerFillerTarget = filler
                    hTowerFillerTargetDistance = fillerTowerDistance
                end
            end
        end

        if hTowerFillerTarget then
            bot:Action_AttackUnit(hTowerFillerTarget, true)
            return
        end
    end

    if GetUnitToLocationDistance(bot, targetLoc) > 500 then
        bot:Action_MoveToLocation(targetLoc)
        return
    else
        if DotaTime() >= fNextMovementTime then
            bot:Action_AttackMove(J.GetRandomLocationWithinDist(targetLoc, 0, 400))
            fNextMovementTime = DotaTime() + (RandomInt(5, 30)/100)
            return
        end
    end
end

function TryClearingOtherLaneHighGround(bot, vLocation)
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
                totalDamage = totalDamage + hUnit:GetActualIncomingDamage(enemy:GetAttackDamage() * enemy:GetAttackSpeed() * fDuration, DAMAGE_TYPE_PHYSICAL)
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

function Push.IsBuildingGlyphedBackdoor()
    local unitList = GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)
    for _, building in pairs(unitList) do
        if J.IsValidBuilding(building)
        and Push.HasBackdoorProtect(building)
        then
            return true
        end
    end

    return false
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

function Push.HasBackdoorProtect(target)
    return target:HasModifier('modifier_fountain_glyph')
        or target:HasModifier('modifier_backdoor_protection')
        or target:HasModifier('modifier_backdoor_protection_in_base')
        or target:HasModifier('modifier_backdoor_protection_active')
        or not target:HasModifier('modifier_thdots_anti_bd_stop')
end

return Push