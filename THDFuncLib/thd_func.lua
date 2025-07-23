local J = {}

local RadiantFountain = Vector( -6619, -6336, 384 )
local DireFountain = Vector( 6928, 6372, 392 )

J.Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
J.Site = require( GetScriptDirectory()..'/THDFuncLib/aba_site')


--- Item 相关方法库 ---
function J.HasItem( bot, sItemName )
	local Slot = bot:FindItemSlot( sItemName )
	if Slot >= 0 and Slot <= 5 then	return true end
	return false
end

function J.IsHaveAegis( bot )
	return bot:FindItemSlot( "item_aegis" ) >= 0
end

function J.DoesTeamHaveAegis()
	local numPlayer = GetTeamPlayers( GetTeam() )
	for i = 1, #numPlayer
	do
		local member = GetTeamMember(i)
		if J.IsValidHero(member)
		and J.IsHaveAegis(member)
		then
			return true
		end
	end
	return false
end

function J.IsTormentor(nTarget)
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and string.find(nTarget:GetUnitName(), 'miniboss') ~= nil
end

function J.IsRoshan( nTarget )
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and string.find( nTarget:GetUnitName(), "roshan" ) ~= nil
end

function J.IsValidBuilding( nTarget )
	return J.Utils.IsValidBuilding(nTarget)
end

function J.IsValidTarget(nTarget)
	-- NOTE: return J.Utils.IsValidUnit(nTarget) -- ideally it should be IsValidUnit, but a lot of legacy usage causing some problems.
	return J.Utils.IsValidHero(nTarget)
end
----------------------------------------------------------------

function J.IsInTeamFight( bot, nRadius )
	if nRadius == nil or nRadius > 1600 then nRadius = 1600 end
	local attackModeAllyList = J.GetNearbyHeroes(bot, nRadius, false, BOT_MODE_ATTACK )
	return #attackModeAllyList >= 2
end

function J.IsDefending( bot )
	local mode = bot:GetActiveMode()
	return mode == BOT_MODE_DEFEND_TOWER_TOP
		or mode == BOT_MODE_DEFEND_TOWER_MID
		or mode == BOT_MODE_DEFEND_TOWER_BOT
end

function J.IsAttacking( bot )

	local nAnimActivity = bot:GetAnimActivity()

	if nAnimActivity ~= ACTIVITY_ATTACK
		and nAnimActivity ~= ACTIVITY_ATTACK2
	then
		return false
	end
	if bot:GetAttackPoint() > bot:GetAnimCycle() * 0.99
	then
		return true
	end

	return false
end

function J.IsRetreating( bot )

	local mode = bot:GetActiveMode()
	local modeDesire = bot:GetActiveModeDesire()
	local bDamagedByAnyHero = bot:WasRecentlyDamagedByAnyHero( 2.0 )

	return ( mode == BOT_MODE_RETREAT and modeDesire > BOT_MODE_DESIRE_MODERATE and bot:DistanceFromFountain() > 0 )
		 or ( mode == BOT_MODE_EVASIVE_MANEUVERS and bDamagedByAnyHero )
		 or ( mode == BOT_MODE_FARM and modeDesire > BOT_MODE_DESIRE_ABSOLUTE )
		
end

function J.IsGoingOnSomeone( bot )

	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_ROAM
		or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_GANK
		or mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_DEFEND_ALLY

end

----------------------------------------------------------------

--- DotaTime 相关方法库 ---
function J.IsInLaningPhase()
	return DotaTime() < 8 * 60
end

function J.CheckTimeOfDay()
    local cycle = 600
    local time = DotaTime() % cycle
    local night = 300

    if time < night then return "day", time
    else return "night", time
    end
end

function J.GetHP( unit )
	local nCurHealth = unit:GetHealth()
    local nMaxHealth = unit:GetMaxHealth()
	if nCurHealth <= 0 then return 0 end
	return nCurHealth / nMaxHealth
end

function J.GetMP( bot )
	return bot:GetMana() / bot:GetMaxMana()
end

function J.IsEarlyGame()
	if DotaTime() < 8 * 60 then
		return true
	end
	return false
end

function J.IsMidGame()
	if DotaTime() > 8 * 60 and DotaTime() < 18 * 60 then
		return true
	end
	return false
end

function J.IsLateGame()
	if DotaTime() > 18 * 60 then
		return true
	end
	return false
end
----------------------------------------------------------------

--- 距离相关方法库 ---
function J.GetDistance(s, t)
    return math.sqrt((s[1] - t[1]) * (s[1]-t[1]) + (s[2] - t[2]) * (s[2] - t[2]))
end

function J.GetRandomLocationWithinDist(sLoc, minDist, maxDist)
	local randomAngle = math.random() * 2 * math.pi
	local randomDist = math.random(minDist, maxDist)
	local newX = sLoc.x + randomDist * math.cos(randomAngle)
	local newY = sLoc.y + randomDist * math.sin(randomAngle)
	return Vector(newX, newY, sLoc.z)
end

function J.RandomForwardVector(length)
    local offset = RandomVector(length)
    if GetTeam() == TEAM_RADIANT then
        offset.x = offset.x > 0 and offset.x or -offset.x
        offset.y = offset.y > 0 and offset.y or -offset.y
    end
    if GetTeam() == TEAM_DIRE then
        offset.x = offset.x < 0 and offset.x or -offset.x
        offset.y = offset.y < 0 and offset.y or -offset.y
    end
    return offset
end

function J.GetEnemiesAroundAncient(bot, nRadius)
	return J.GetEnemiesAroundLoc(GetAncient(bot:GetTeam()):GetLocation(), nRadius)
end

function J.GetEnemiesAroundLoc(vLoc, nRadius)
	if not nRadius then nRadius = 2000 end
	local cacheKey = 'GetEnemiesAroundLoc'..tostring(nRadius) ..'-'..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	if cache ~= nil then return cache end

	local nUnitCount = 0
	local ancientLoc = GetAncient(GetBot():GetTeam()):GetLocation()

	-- Check Heroes. 
	for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local info = GetHeroLastSeenInfo(id)
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil
				and J.GetLocationToLocationDistance(vLoc, dInfo.location) <= nRadius
				and dInfo.time_since_seen < 5.0
				then
					nUnitCount = nUnitCount + GetHeroLevel(id) / 3
					if J.GetLocationToLocationDistance(ancientLoc, vLoc) < 1600 then
						nUnitCount = nUnitCount + 2 -- Increase weight for critical defense.
					end
				end
			end
		end
	end

	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES))
	do
		if J.IsValid(unit)
		and GetUnitToLocationDistance(unit, vLoc) <= nRadius
		then
			local unitName = unit:GetUnitName()
			if unit:IsCreep() then
				nUnitCount = nUnitCount + 1
				if unit:IsAncientCreep() then
					nUnitCount = nUnitCount + 1
				end
			end
			if J.GetLocationToLocationDistance(ancientLoc, vLoc) < 1600 then nUnitCount = nUnitCount + 2 end
		end
	end

	J.Utils.SetCachedVars('GetEnemiesAroundLoc'..cacheKey, nUnitCount)
	return nUnitCount
end

function J.GetAlliesNearLoc( vLoc, nRadius )
	local allies = {}
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember( i )
		if member ~= nil
			and member:IsAlive()
			and GetUnitToLocationDistance( member, vLoc ) <= nRadius
		then
			table.insert( allies, member )
		end
	end
	return allies
end

function J.GetEnemiesNearLoc(vLoc, nRadius)

	local enemies = {}
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and GetUnitToLocationDistance(enemyHero, vLoc) <= nRadius
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			table.insert(enemies, enemyHero)
		end
	end
	return enemies
end

function J.GetAverageLevel( bEnemy )
	local count = 0
	local sum = 0
	local nTeam = GetTeam()
	if bEnemy then nTeam = GetOpposingTeam() end
	for i, id in pairs( GetTeamPlayers( nTeam ) )
	do
		sum = sum + GetHeroLevel( id )
		count = count + 1
	end
	local res = sum / count
	return res
end

function J.ToNearest500(num)
    return math.floor(num / 500 + 0.5) * 500
end

--RoundToNearestThousand
function J.ToNearest1000(num)
    return math.floor(num / 1000 + 0.5) * 1000
end

function J.GetLocationToLocationDistance( fLoc, sLoc )

	local x1 = fLoc.x
	local x2 = sLoc.x
	local y1 = fLoc.y
	local y2 = sLoc.y

	return math.sqrt( ( y2-y1 )^2 + ( x2-x1 )^2 )

end

function J.GetLastSeenEnemiesNearLoc(vLoc, nRadius)
	local enemies = {}
	for i, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
	do
		if IsHeroAlive( id ) then
			local info = GetHeroLastSeenInfo( id )
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil
					and J.GetLocationToLocationDistance( vLoc, dInfo.location ) <= nRadius
					and dInfo.time_since_seen < 5.0
				then
					table.insert(enemies, id)
				end
			end
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, enemies)
	return enemies
end

function J.GetNumOfAliveHeroes( bEnemy )
	local count = 0
	local nTeam = GetTeam()
	if bEnemy then nTeam = GetOpposingTeam() end
	for i, id in pairs( GetTeamPlayers( nTeam ) )
	do
		if IsHeroAlive( id )
		then
			count = count + 1
		end
	end
	return count
end

function J.GetNumOfTeamTotalKills( bEnemy )
	local count = 0
	local nTeam = GetOpposingTeam()
	if bEnemy then nTeam = GetTeam() end
	for i, id in pairs( GetTeamPlayers( nTeam ) )
	do
		count = count + GetHeroDeaths( id )
	end
	return count
end

local hAllyTeamList = {}
local hEnemyTeamList = {}
function J.GetInventoryNetworth()
	local allyInventoryNet = 0
	local enemyInventoryNet = 0
	if math.floor(DotaTime()) % 2 == 0 then
		for i = 1, #GetTeamPlayers( GetTeam() ) do
			local ally = GetTeamMember(i)
			if ally then
				local itemsCost = 0
				for j = 0, 8 do
					local item = ally:GetItemInSlot(j)
					if item then
						itemsCost = itemsCost + GetItemCost(item:GetName())
					end
				end
				local id = ally:GetPlayerID()
				if hAllyTeamList[id] == nil then hAllyTeamList[id] = 0 end
				if hAllyTeamList[id] < itemsCost then
					hAllyTeamList[id] = itemsCost
				end
			end
		end
		for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
			if J.IsValidHero(enemy)
			and not J.IsSuspiciousIllusion(enemy)
			then
				local id = enemy:GetPlayerID()
				local itemsCost = 0
				for i = 0, 8 do
					local item = enemy:GetItemInSlot(i)
					if item then
						itemsCost = itemsCost + GetItemCost(item:GetName())
					end
				end
				if hEnemyTeamList[id] == nil then hEnemyTeamList[id] = 0 end
				if hEnemyTeamList[id] < itemsCost then
					hEnemyTeamList[id] = itemsCost
				end
			end
		end
	end
	for _, networth in pairs(hAllyTeamList) do allyInventoryNet = allyInventoryNet + networth end
	for _, networth in pairs(hEnemyTeamList) do enemyInventoryNet = enemyInventoryNet + networth end

	return allyInventoryNet, enemyInventoryNet
end

function J.GetProperTarget( bot )
	local target = nil
	if ( bot:GetTeam() == GetBot():GetTeam() )
	then
		target = bot:GetTarget()
	end
	if target == nil and bot:CanBeSeen()
	then
		target = bot:GetAttackTarget()
	end
	if target ~= nil
		and target:GetTeam() == bot:GetTeam()
		and ( target:IsHero() or target:IsBuilding() )
	then
		target = nil
	end
	return target
end

function J.WeAreStronger(bot, radius)
	if radius > 1600 then radius = 1600 end
	local cacheKey = 'WeAreStronger'..tostring(bot:GetPlayerID())..'-'..tostring(radius)
	local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	if cache ~= nil then return cache end

    local mates = J.GetNearbyHeroes(bot,radius, false, BOT_MODE_NONE);
    local enemies = J.GetNearbyHeroes(bot,radius, true, BOT_MODE_NONE);

    local ourPower = 0;
    local enemyPower = 0;
	local maxOurPower = 0;

    for _, h in pairs(mates) do
		if J.IsValid(h) and not h:IsIllusion() then
			ourPower = ourPower + h:GetOffensivePower();
			maxOurPower = math.max(maxOurPower, h:GetOffensivePower())
		end
    end

    for _, h in pairs(enemies) do
		if J.IsValid(h) and not J.IsSuspiciousIllusion(h) then
			if J.Utils.IsSpecialOffensiveHero(h:GetUnitName()) then
				enemyPower = enemyPower + h:GetRawOffensivePower();
			end
		end
    end

    local res = #mates > #enemies and ourPower > enemyPower
	J.Utils.SetCachedVars(cacheKey, res)
    return res
end

--以下可少算但不可多算
function J.GetAttackProDelayTime( bot, nCreep )
	if nCreep == nil then
		print('[ERROR] nil creep target')
		print("Stack Trace:", debug.traceback())
		return 0
	end

	local botName = bot:GetUnitName()
	local botAttackRange = bot:GetAttackRange()
	local botAttackPoint = bot:GetAttackPoint()
	local botAttackSpeed = bot:GetAttackSpeed()
	local botProSpeed = bot:GetAttackProjectileSpeed()
	local botMoveSpeed = bot:GetCurrentMovementSpeed()
	local botAttackPointTime = botAttackPoint / botAttackSpeed
	local botAttackIdleTime = bot:GetSecondsPerAttack() - botAttackPointTime
	local nLastAttackRemainIdleTime = 0

	if GameTime() - bot:GetLastAttackTime() < botAttackIdleTime
	then
		nLastAttackRemainIdleTime = botAttackIdleTime - ( GameTime() - bot:GetLastAttackTime() )
	end

	local nAttackDamageDelayTime = botAttackPointTime + nLastAttackRemainIdleTime * 0.98
	local nDist = GetUnitToUnitDistance( bot, nCreep )

	if bot:CanBeSeen()
		and bot:GetAttackTarget() == nCreep
		and bot:GetAnimActivity() == 1503
		and bot:GetAnimCycle() < botAttackPoint
	then
		nAttackDamageDelayTime = 0.9 * ( botAttackPoint - bot:GetAnimCycle() ) / botAttackSpeed
	end

	if botAttackRange > 320 then

		local ignoreDist = 39
		if bot:GetPrimaryAttribute() == ATTRIBUTE_INTELLECT then ignoreDist = 59 end

		local projectMoveDist = nDist - ignoreDist

		if projectMoveDist < 0 then projectMoveDist = 0 end

		if projectMoveDist > botAttackRange then projectMoveDist = botAttackRange - 32 end

		nAttackDamageDelayTime = nAttackDamageDelayTime + projectMoveDist / botProSpeed

		if nDist > botAttackRange + ignoreDist / 1.2 then
			nAttackDamageDelayTime = nAttackDamageDelayTime + ( nDist - botAttackRange - ignoreDist / 1.2 ) / botMoveSpeed
		end

	end

	if botAttackRange < 326 and nDist > botAttackRange + 50 then
		nAttackDamageDelayTime = nAttackDamageDelayTime + ( nDist - botAttackRange - 50 ) / botMoveSpeed
	end

	return nAttackDamageDelayTime

end

function J.GetAverageNetworth()
	local cacheKey = 'GetAverageNetworth'..tostring(GetTeam())
	local cache = J.Utils.GetCachedVars(cacheKey, 2)
	if cache ~= nil then return cache end

	local totalNetWorth = 0
	for i = 1, #GetTeamPlayers(GetTeam())
	do
		local member = GetTeamMember(i)
		if J.IsValidHero(member) then
			totalNetWorth = totalNetWorth + member:GetNetWorth()
		end
	end

	local res = totalNetWorth / #GetTeamPlayers(GetTeam())
	J.Utils.SetCachedVars(cacheKey, res)
	return res
end

--未计算技能增强
function J.WillKillTarget( npcTarget, dmg, dmgType, nDelay )

	local targetHealth = npcTarget:GetHealth() + npcTarget:GetHealthRegen() * nDelay + 0.8

	local nRealBonus = J.GetTotalAttackWillRealDamage( npcTarget, nDelay )

	local nTotalDamage = npcTarget:GetActualIncomingDamage( dmg, dmgType ) + nRealBonus

	return nTotalDamage > targetHealth and nRealBonus < targetHealth - 1

end

--当前点 * 攻击间隔 / 1.0 = 当前时
function J.GetCreepAttackActivityWillRealDamage( nUnit, nTime )

	local bot = GetBot()
	local botLV = bot:GetLevel()
	local gameTime = GameTime()
	local nDamage = 0
	local othersBeEnemy = true

	if nUnit:GetTeam() ~= bot:GetTeam() then othersBeEnemy = false end

	local nCreeps = bot:GetNearbyLaneCreeps( 1600, othersBeEnemy )
	for _, creep in pairs( nCreeps )
	do
		if creep:CanBeSeen()
			and creep:GetAttackTarget() == nUnit
			and creep:GetAnimActivity() == 1503
			and creep:GetLastAttackTime() < gameTime - 0.2
		then
			local attackPoint	= creep:GetAttackPoint()
			local animCycle	 = creep:GetAnimCycle()
			local attackPerTime = creep:GetSecondsPerAttack()

			if J.IsKeyWordUnit( 'melee', creep )
				and animCycle < attackPoint
				and ( attackPoint - animCycle ) * attackPerTime < nTime * ( 0.99 - botLV / 300 )
			then
				nDamage = nDamage + creep:GetAttackDamage() * 1
			end

			if J.IsKeyWordUnit( 'ranged', creep )
				and animCycle < attackPoint
			then
				local nDist = GetUnitToUnitDistance( creep, nUnit ) - 22
				local nProjectSpeed = creep:GetAttackProjectileSpeed()
				local nProjectTime = nDist / ( nProjectSpeed + 1 )
				if ( attackPoint - animCycle ) * attackPerTime + nProjectTime < nTime * ( 0.98 - botLV / 200 )
				then
					nDamage = nDamage + creep:GetAttackDamage() * 1
				end
			end

			if J.IsKeyWordUnit( 'siege', creep )
				and animCycle < 0.292 --0.285
			then
				local nDist = GetUnitToUnitDistance( creep, nUnit ) - 28
				local nProjectSpeed = creep:GetAttackProjectileSpeed()
				local nProjectTime = nDist / ( nProjectSpeed + 1 )
				if ( 0.292 - animCycle ) * 0.699 / 0.292 + nProjectTime < nTime * ( 0.9 - botLV / 150 )
				then
					nDamage = nDamage + creep:GetAttackDamage() * 1
				end
			end

		end
	end

	return nUnit:GetActualIncomingDamage( nDamage, DAMAGE_TYPE_PHYSICAL )

end


function J.GetCreepAttackProjectileWillRealDamage( nUnit, nTime )

	local nDamage = 0
	local incProj = nUnit:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if p.is_attack
			and p.caster ~= nil
		then
			local nProjectSpeed = p.caster:GetAttackProjectileSpeed()
			if p.caster:IsTower() then nProjectSpeed = nProjectSpeed * 0.93 end
			local nProjectDist = nProjectSpeed * nTime * 0.95
			local nDistance	 = GetUnitToLocationDistance( nUnit, p.location )
			if nProjectDist > nDistance * 1.02
			then
				nDamage = nDamage + p.caster:GetAttackDamage() * 1
			end
		end
	end

	return nUnit:GetActualIncomingDamage( nDamage, DAMAGE_TYPE_PHYSICAL )

end


function J.GetTotalAttackWillRealDamage( nUnit, nTime )

	 return J.GetCreepAttackProjectileWillRealDamage( nUnit, nTime ) + J.GetCreepAttackActivityWillRealDamage( nUnit, nTime )

end

function J.IsAnyAllyDefending(bot, lane)
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and J.IsNotSelf(bot, allyHero)
		then
			local mode = allyHero:GetActiveMode()
			if (mode == BOT_MODE_DEFEND_TOWER_TOP and lane == LANE_TOP)
			or (mode == BOT_MODE_DEFEND_TOWER_MID and lane == LANE_MID)
			or (mode == BOT_MODE_DEFEND_TOWER_BOT and lane == LANE_BOT)
			then
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------

function J.IsValid( nTarget )
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and not nTarget:IsBuilding()
end

function J.IsValidHero( nTarget )
	return J.Utils.IsValidHero(nTarget)
end

function J.CanBeAttacked( unit )
	return  unit ~= nil
			and unit:IsAlive()
			and unit:CanBeSeen()
			and not unit:IsNull()
			and not unit:IsAttackImmune()
			and not unit:IsInvulnerable()
			and not unit:HasModifier("modifier_fountain_glyph")
end

function J.IsSuspiciousIllusion( npcTarget )
	if npcTarget == nil or npcTarget:IsNull() then return false end
	if npcTarget.is_suspicious_illusion ~= nil then
		return npcTarget.is_suspicious_illusion
	end
	if not npcTarget:CanBeSeen() then
		npcTarget.is_suspicious_illusion = false
		return false
	end

	if npcTarget:CanBeSeen() and (
		not npcTarget:IsHero()
		or npcTarget:IsCastingAbility()
		or npcTarget:IsUsingAbility()
		or npcTarget:IsChanneling()
	)

	then
		npcTarget.is_suspicious_illusion = false
		return false
	end

	local bot = GetBot()

	if npcTarget:GetTeam() == bot:GetTeam()
	then
		npcTarget.is_suspicious_illusion = npcTarget:IsIllusion()
		return npcTarget.is_suspicious_illusion
	elseif npcTarget:GetTeam() == GetOpposingTeam()
	then

		if npcTarget:HasModifier( 'modifier_illusion' )
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end

		local tID = npcTarget:GetPlayerID()

		if not IsHeroAlive( tID )
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end

		if GetHeroLevel( tID ) > npcTarget:GetLevel()
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end
	end

	npcTarget.is_suspicious_illusion = false
	return false
end

function J.CanCastAbilityOnTarget( npcTarget, bIgnoreMagicImmune )

	return npcTarget:CanBeSeen()
			and ( bIgnoreMagicImmune or not npcTarget:IsMagicImmune() )
			and not npcTarget:IsInvulnerable()
			and not J.IsSuspiciousIllusion( npcTarget )
end

function J.CanCastAbility(ability)
	if ability == nil
	or ability:IsNull()
	or ability:IsPassive()
	or ability:IsHidden()
	or not ability:IsTrained()
	or not ability:IsFullyCastable()
	or not ability:IsActivated()
	then
		return false
	end
	return true
end

function J.IsNotSelf(bot, ally)
	if bot:GetUnitName() ~= ally:GetUnitName() then
		return true
	end
	return false
end

function J.GetNearbyHeroes(bot, nRadius, bEnemy, bBotMode)
	if not bBotMode then bBotMode = BOT_MODE_NONE end
	local nearby = bot:GetNearbyHeroes(nRadius, bEnemy, bBotMode)
	if not nearby then
		return nearby
	end

	local heroes = {}
	for _, hero in pairs( nearby )
	do
		if J.IsValidHero(hero) then
			table.insert(heroes, hero)
		end
	end
	return heroes
end

function J.IsInRange( bot, npcTarget, nRadius )
	if npcTarget == nil or not npcTarget:CanBeSeen() then
		return false
	end

	return GetUnitToUnitDistance( bot, npcTarget ) <= nRadius

end

function J.IsRunning( bot )
	if not bot:IsAlive() then return false end
	return bot:GetAnimActivity() == ACTIVITY_RUN
end

function J.IsChasingTarget( bot, nTarget )
	if J.IsRunning( bot )
		and J.IsRunning( nTarget )
		and bot:IsFacingLocation( nTarget:GetLocation(), 20 )
		and not nTarget:IsFacingLocation( bot:GetLocation(), 150 )
	then
		return true
	end
	return false
end

function J.CanNotUseAction( bot )
	return not bot:IsAlive()
			or J.HasQueuedAction( bot )
			or (bot:IsInvulnerable() and not bot:HasModifier('modifier_fountain_invulnerability'))
			or bot:IsCastingAbility()
			or bot:IsUsingAbility()
			or bot:IsChanneling()
			or bot:IsStunned()
			or bot:IsNightmared()
end

function J.IsSeriouslyRetreating( npcBot )
	return (npcBot:GetActiveMode() == BOT_MODE_RETREAT
	and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH
	and not npcBot:HasModifier("modifier_fountain_aura_buff"))
	or npcBot:GetHealth()/npcBot:GetMaxHealth() < 0.1
end

function J.IsDoingRoshan( bot )
	local mode = bot:GetActiveMode()
	return mode == BOT_MODE_ROSHAN
end

function J.GetCurrentRoshanLocation()
	if J.CheckTimeOfDay() == 'day'
	then
		return J.Utils.RadiantRoshanLoc
	else
		return J.Utils.DireRoshanLoc
	end
end

function J.HasQueuedAction( bot )
	if bot ~= GetBot()
	then
		return false
	end
	return bot:NumQueuedActions() > 0
end

function J.IsKeyWordUnit( keyWord, uUnit )

	if string.find( uUnit:GetUnitName(), keyWord ) ~= nil
	then
		return true
	end

	return false
end

function J.GetTeamFountain()
	local Team = GetTeam()
	if Team == TEAM_DIRE
	then
		return DireFountain
	else
		return RadiantFountain
	end
end

function J.GetEnemyFountain()
	local Team = GetTeam()

	if Team == TEAM_DIRE
	then
		return RadiantFountain
	else
		return DireFountain
	end
end

return J