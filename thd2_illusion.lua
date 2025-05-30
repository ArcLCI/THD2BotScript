local X = {}
local ownerBot
local nNextMoveTime = 0

local nEnemyAncient = GetAncient(GetOpposingTeam())
local RadiantFountain = Vector( -6619, -6336, 384 )
local DireFountain = Vector( 6928, 6372, 392 )

local SpecialUnits = {
	['npc_dota_phoenix_sun'] = 1,
	['npc_thdots_unit_minoriko02_box'] = 0.95,
	['npc_dota_rattletrap_cog'] = 0.9,
}

function X.IllusionThink(owner, hMinionUnit)

	ownerBot = owner
	if not hMinionUnit:IsIllusion() then return end

	if hMinionUnit:IsIllusion() then
        if ConfuseEnemyWithIllusions(owner, hMinionUnit) > 0 then
			print("Confusing Enemy...")
            return
        end
    end

	hMinionUnit.attack_desire, hMinionUnit.attack_target = ConsiderAttack(hMinionUnit)
    if ConsiderRetreat(hMinionUnit, hMinionUnit.attack_target) then return end

    if hMinionUnit.attack_desire > 0 then
        if IsValidUnit(hMinionUnit.attack_target) then
            hMinionUnit:Action_AttackUnit(hMinionUnit.attack_target, false)
            return
        end
    end

    if DotaTime() >= nNextMoveTime then
        hMinionUnit.move_desire, hMinionUnit.move_location = ConsiderMove(hMinionUnit)
        if hMinionUnit.move_desire > 0 then
            if GetUnitToLocationDistance(hMinionUnit, hMinionUnit.move_location) > 400 then
                hMinionUnit:Action_MoveToLocation(hMinionUnit.move_location)
            else
                hMinionUnit:Action_AttackMove(GetRandomLocationWithinDist(hMinionUnit.move_location, 0, 300))
            end
            nNextMoveTime = DotaTime() + 0.2
            return
        end

        -- Default
        if ownerBot:IsAlive()
        then
            hMinionUnit:Action_MoveToLocation(GetRandomLocationWithinDist(ownerBot:GetLocation(), 400, 800))
        else
            hMinionUnit:Action_MoveToLocation(GetClosestTeamLane(hMinionUnit))
        end
        nNextMoveTime = DotaTime() + 0.2
    end
end
----------------------------------------------------------------------------------------------------
-- 幻象基础方法

function IsValidUnit(unit)
    return unit ~= nil
        and not unit:IsNull()
        and unit:IsAlive()
        and unit:CanBeSeen()
end

function IsValidTarget(unit)
	return IsValidUnit(unit)
	   and not unit:IsInvulnerable()
	   and not unit:IsAttackImmune()
end

function IsBusy(unit)
	return IsValidUnit(unit)
        and (unit:IsUsingAbility()
            or unit:IsCastingAbility()
            or unit:IsChanneling())
end

function CantMove(unit)
	return IsValidUnit(unit)
        and (unit:IsStunned()
            or unit:IsRooted()
            or unit:IsNightmared()
            or unit:IsInvulnerable() and not unit:HasModifier('modifier_fountain_invulnerability')
			or not unit:GetCurrentMovementSpeed() or unit:GetCurrentMovementSpeed() < 100
            )
end

function HasQueuedAction( unit )
	if unit ~= GetBot()
	then
		return false
	end
	return unit:NumQueuedActions() > 0
end

function CanNotUseAction( unit )
	return not unit:IsAlive()
			or HasQueuedAction( unit )
			or unit:IsInvulnerable()
			or unit:IsCastingAbility()
			or unit:IsUsingAbility()
			or unit:IsChanneling()
			or unit:IsStunned()
			or unit:IsNightmared()

end

function CanNotUseAbility( unit )
	return not IsValidUnit(unit)
			or unit:IsInvulnerable()
			or unit:IsCastingAbility()
			or unit:IsUsingAbility()
			or unit:IsChanneling()
			or unit:IsSilenced()
			or unit:IsStunned()
			or unit:IsHexed()
			or unit:IsNightmared()
end

function CantAttack(unit)
	return IsValidUnit(unit)
        and (unit:IsStunned()
            or unit:IsRooted()
            or unit:IsNightmared()
            or unit:IsDisarmed()
            or unit:IsInvulnerable()
            or unit:GetAttackDamage() <= 0
            )
end

function IsInRange( bot, npcTarget, nRadius )
	if npcTarget == nil or not npcTarget:CanBeSeen() then
		return false
	end
	return GetUnitToUnitDistance( bot, npcTarget ) <= nRadius
end

function IsValidBuilding(target)
    return target ~= nil and not target:IsNull() and target:CanBeSeen() and target:IsAlive() and not target:IsInvulnerable() and target:IsBuilding()
end

function GetWeakestHero(nRadius, thisUnit)
    if IsValidUnit(thisUnit)
    then
        local nEnemyHeroes = thisUnit:GetNearbyHeroes(nRadius * 0.5, true, BOT_MODE_NONE)
        if #nEnemyHeroes == 0
        then
            nEnemyHeroes = thisUnit:GetNearbyHeroes(nRadius, true, BOT_MODE_NONE)
        end

        return GetWeakest(nEnemyHeroes)
    end

    return nil
end

function GetWeakestCreep(nRadius, hMinionUnit)
    if IsValidUnit(hMinionUnit)
    then
        local nCreeps = hMinionUnit:GetNearbyCreeps(nRadius * 0.5, true)

        if #nCreeps == 0
        then
            nCreeps = hMinionUnit:GetNearbyCreeps(nRadius, true)
        end

        return GetWeakest(nCreeps)
    end

    return nil
end

function GetWeakestTower(nRadius, hMinionUnit)
    if IsValidUnit(hMinionUnit)
    then
        if IsValidTarget(nEnemyAncient)
        and GetUnitToUnitDistance(hMinionUnit, nEnemyAncient) <= nRadius
        then
            return nEnemyAncient
        end

		local nTowers = hMinionUnit:GetNearbyTowers(nRadius, true)
        if nTowers == nil or #nTowers == 0
        then
			nTowers = hMinionUnit:GetNearbyBarracks(nRadius, true)
            if nTowers == nil or #nTowers == 0
            then
                nTowers = hMinionUnit:GetNearbyFillers(nRadius, true)
            end
        end

        return GetWeakest(nTowers)
    end

	return nil
end

function GetWeakest(unitList)
	local target = nil
	local minKillTime = 10000

	if #unitList > 0
	then
		for i = 1, #unitList
		do
			local unit = unitList[i]
			if IsValidTarget(unit)
			and not IsNotAllowedToAttack(unit)
			then
				local killUnitTime = unit:GetHealth() / unit:GetActualIncomingDamage( 3000, DAMAGE_TYPE_PHYSICAL )
				if killUnitTime < minKillTime
				then
					target = unit
					minKillTime = killUnitTime
				end
			end
		end
	end

	return target
end

function IsNotAllowedToAttack(unit)
	local unit_name = unit:GetUnitName()
	return unit_name == '#DOTA_OutpostName_North'
		or unit_name == '#DOTA_OutpostName_South'
		or unit_name == 'npc_dota_unit_twin_gate'
end

function IsTargetedByHero(unit)
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if IsValidUnit(enemy)
		and enemy:IsHero()
		and GetUnitToUnitDistance( unit, enemy ) <= enemy:GetAttackRange() + 300
		and enemy:GetAttackTarget() == unit
		then
			return true
		end
	end

	return false
end

function IsTargetedByTower(unit)
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS))
	do
		if IsValidUnit(enemy)
		and enemy:IsTower()
		and GetUnitToUnitDistance( unit, enemy ) <= enemy:GetAttackRange() + 300
		and enemy:GetAttackTarget() == unit
		then
			return true
		end
	end

	return false
end

function IsTargetedByCreep(unit)
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS))
	do
		if IsValidUnit(enemy)
		and enemy:IsCreep()
		and GetUnitToUnitDistance( unit, enemy ) <= enemy:GetAttackRange() + 300
		and enemy:GetAttackTarget() == unit
		then
			return true
		end
	end

    for _, enemy in pairs(GetUnitList(UNIT_LIST_NEUTRAL_CREEPS))
	do
		if IsValidUnit(enemy)
		and enemy:IsCreep()
		and GetUnitToUnitDistance( unit, enemy ) <= enemy:GetAttackRange() + 300
		and enemy:GetAttackTarget() == unit
		then
			return true
		end
	end

	return false
end

function GetHP( unit )
	local nCurHealth = unit:GetHealth()
    local nMaxHealth = unit:GetMaxHealth()
	if nCurHealth <= 0 then return 0 end
	return nCurHealth / nMaxHealth
end

function GetTeamFountain()

	local Team = GetTeam()
	if Team == TEAM_DIRE
	then
		return DireFountain
	else
		return RadiantFountain
	end
end

function IsValid( nTarget )
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and not nTarget:IsBuilding()
end

function IsRunning( bot )
	if not bot:IsAlive() then return false end

	return bot:GetAnimActivity() == ACTIVITY_RUN
end

function IsChasingTarget( bot, nTarget )
	if IsRunning( bot )
		and IsRunning( nTarget )
		and bot:IsFacingLocation( nTarget:GetLocation(), 20 )
		and not nTarget:IsFacingLocation( bot:GetLocation(), 150 )
	then
		return true
	end
	return false
end

function GetClosestTeamLane(unit)
	local v_top_lane = GetLaneFrontLocation(GetTeam(), LANE_TOP, 0)
	local v_mid_lane = GetLaneFrontLocation(GetTeam(), LANE_MID, 0)
	local v_bot_lane = GetLaneFrontLocation(GetTeam(), LANE_BOT, 0)

	local dist_from_top = GetUnitToLocationDistance(unit, v_top_lane)
	local dist_from_mid = GetUnitToLocationDistance(unit, v_mid_lane)
	local dist_from_bot = GetUnitToLocationDistance(unit, v_bot_lane)

	if dist_from_top < dist_from_mid and dist_from_top < dist_from_bot
	then
		return v_top_lane
	elseif dist_from_mid < dist_from_top and dist_from_mid < dist_from_bot
	then
		return v_mid_lane
	elseif dist_from_bot < dist_from_top and dist_from_bot < dist_from_mid
	then
		return v_bot_lane
	end

	return v_mid_lane
end

function GetRandomLocationWithinDist(sLoc, minDist, maxDist)
	local randomAngle = math.random() * 2 * math.pi
	local randomDist = math.random(minDist, maxDist)
	local newX = sLoc.x + randomDist * math.cos(randomAngle)
	local newY = sLoc.y + randomDist * math.sin(randomAngle)
	return Vector(newX, newY, sLoc.z)
end

function GetSpecialUnits()
	return SpecialUnits
end
----------------------------------------------------------------------------------------------------
-- 幻象逻辑用方法

-- 幻象迷惑对手
function ConfuseEnemyWithIllusions(bot, hMinionUnit)
    if IsValidUnit(bot) and GetHP(bot) < 0.4 and bot:GetActiveMode() == BOT_MODE_RETREAT then
        local retreatDirection = bot:GetFacing()
        local oppositeDirection = (retreatDirection + 180) % 360
        local confuseDistance = 800 -- distance illusions will move
        local confuseLocation = hMinionUnit:GetLocation() +
            Vector(confuseDistance * math.cos(math.rad(oppositeDirection)), confuseDistance * math.sin(math.rad(oppositeDirection))) + RandomVector(50)
        hMinionUnit:Action_MoveToLocation(confuseLocation)
        return 1
    end
    return 0
end

function ConsiderRetreat(hMinionUnit, hTarget)
    if hMinionUnit:IsIllusion() then return nil end
    if ((IsValidUnit(hTarget) and GetHP(hTarget) > 0.5 and hTarget:IsFacingLocation( hMinionUnit:GetLocation(), 20 ))
        or GetHP(hMinionUnit) < 0.25)
    and GetHP(hMinionUnit) < 0.3
    and hMinionUnit:GetHealth() < 300
     then
        hMinionUnit:Action_MoveToLocation(GetTeamFountain())
        return 1
    end
    return nil
end

function IsTargetInShouldAimToAttackRange(hMinionUnit, target, nMaxRange)
    if not IsValidUnit(target) then return false end
    return GetUnitToUnitDistance(hMinionUnit, target) <= hMinionUnit:GetAttackRange()
        or (not CantMove(hMinionUnit) and GetUnitToUnitDistance(hMinionUnit, target) < math.min(hMinionUnit:GetAttackRange() * 3, nMaxRange))
end

function ConsiderAttack(hMinionUnit)
	if CantAttack(hMinionUnit)
    then
        return BOT_ACTION_DESIRE_NONE, nil
    end

	local hTarget = GetAttackTarget(hMinionUnit)

	if hTarget ~= nil and not IsNotAllowedToAttack(hTarget)
	then
		return BOT_ACTION_DESIRE_HIGH, hTarget
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

function GetAttackTarget(hMinionUnit)
	local target = nil
	local bot = GetBot()

    for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMIES))
    do
        if IsValid(enemy)
        then
            local enemyName = enemy:GetUnitName()
            local specialUnits = GetSpecialUnits()

            if specialUnits[enemyName]
            and enemy:GetTeam() ~= hMinionUnit:GetTeam()
            and GetUnitToUnitDistance(hMinionUnit, enemy) <= specialUnits[enemyName] * 1600
            and RandomInt(0, 100) <= specialUnits[enemyName] * 100
            then
                return enemy
            end
        end
    end

    if GetUnitToUnitDistance(bot, hMinionUnit) < 1600
    then
        local nInRangeEnemy = CachedGetNearbyHeroes( bot, 1200, true, BOT_MODE_NONE )
        if #nInRangeEnemy > 0 then target = bot:GetAttackTarget() end
    end

	if target == nil
    or bot:GetActiveMode() == BOT_MODE_RETREAT
    or (IsTargetedByHero(bot) and bot:GetAttackTarget() == nil)
	then
		target = GetWeakestHero(1600, hMinionUnit)
		if target == nil then target = GetWeakestCreep(1600, hMinionUnit) end
		if target == nil then target = GetWeakestTower(1600, hMinionUnit) end
	end

    if target ~= nil
    then
        if not target:IsBuilding()
        and not target:IsTower()
        and target ~= GetAncient(GetOpposingTeam())
        and IsTargetUnderEnemyTower(hMinionUnit, target)
        then
            if GetHP(target) > 0.25
            and bot:IsAlive()
            and not IsChasingTarget(bot, target)
            then
                return bot:GetAttackTarget()
            end
        end
    end

	return target
end

function ConsiderMove(hMinionUnit)
	if CanNotUseAction(hMinionUnit) or CantMove(hMinionUnit) then return BOT_MODE_DESIRE_NONE, nil end

	local bot = GetBot()

    if GetUnitToUnitDistance(bot, hMinionUnit) > 1600
    or not bot:IsAlive()
    or bot:HasModifier('modifier_teleporting')
    then
        return BOT_ACTION_DESIRE_HIGH, GetClosestTeamLane(hMinionUnit)
    else
        return BOT_ACTION_DESIRE_HIGH, GetRandomLocationWithinDist(bot:GetLocation(), 400, 800)
    end
end

function IsTargetUnderEnemyTower(hMinionUnit, unit)
    local nEnemyTowers = hMinionUnit:GetNearbyTowers(1600, true)
    if nEnemyTowers then
        if IsValidBuilding(nEnemyTowers[1])
        and IsValidUnit(unit)
        and IsInRange(unit, nEnemyTowers[1], 880)
        then
            return true
        end
    end

    return false
end

function IsMinionInLane(hMinionUnit, lane)
	local bot = GetBot()
    for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
        if IsValid(ally)
        and hMinionUnit ~= ally
        and ally:IsIllusion()
        and string.find(bot:GetUnitName(), ally:GetUnitName())
        then
            if ally.to_farm_lane == lane
            or GetUnitToLocationDistance(ally, GetLaneFrontLocation(GetTeam(), lane, 0)) < 1600
            then
                return true
            end
        end
    end

    return false
end

return X