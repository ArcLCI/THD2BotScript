
ModifierNamesTeleporting = {
	"modifier_teleporting",
	"modifier_teleporting_root_logic",

}

ModifierNamesMagicBlock = {
	"modifier_item_sphere_target",
}


ModifierNamesHexed = {
	"modifier_item_yukkuri_stick_debuff",

}

ModifierNamesStun = {
	"modifier_item_pocket_watch_pause",
	"modifier_item_yuetufensuijvren_pause",
	"modifier_stunsystem_pause",

}

ModifierNamesHighDebuff = {
	"modifier_item_yukkuri_stick_debuff",
	"modifier_item_pocket_watch_pause",
	"modifier_item_yuetufensuijvren_pause",
	"modifier_stunsystem_pause",
}

----------------------------------------------------------------------------------------------------

local RandomTimes = 10

local function RandomChoose( tTargets, vBaseLocation, nMaxDistanceFromBase, nRadius, nMaxHealth )

	local RadiusSqr = nRadius * nRadius
	rd_best_result = {}

	rd_best_result.count = 0
	rd_best_result.targetloc = vBaseLocation

	local tTagers_InRange1 = {} --in nMaxDistanceFromBase - nRadius
	local tTagers_InRange2 = {} --in nMaxDistanceFromBase
	local tTagers_InRange3 = {} --in nMaxDistanceFromBase + nRadius

	local dis_sqr_1 = (nMaxDistanceFromBase - nRadius) * (nMaxDistanceFromBase - nRadius)
	if nMaxDistanceFromBase < nRadius then dis_sqr_1 = 0 end
	local dis_sqr_2 = nMaxDistanceFromBase * nMaxDistanceFromBase
	local dis_sqr_3 = (nMaxDistanceFromBase + nRadius) * (nMaxDistanceFromBase + nRadius)

	local vReservePoints = {}

	for _,unit in pairs( tTargets )
	do
		if unit:CanBeSeen() and (nMaxHealth < 1 or unit:GetHealth() < nMaxHealth) then
			if GetUnitToLocationDistanceSqr( unit, vBaseLocation ) < dis_sqr_1 then
				table.insert(tTagers_InRange1, unit)
				table.insert(tTagers_InRange2, unit)
				table.insert(tTagers_InRange3, unit)
				rd_best_result.count = 1
				rd_best_result.targetloc = unit:GetLocation()
			elseif GetUnitToLocationDistanceSqr( unit, vBaseLocation ) < dis_sqr_2 then
				table.insert(tTagers_InRange2, unit)
				table.insert(tTagers_InRange3, unit)
				rd_best_result.count = 1
				rd_best_result.targetloc = unit:GetLocation()
				--special
				if #vReservePoints < 20 then
					table.insert(vReservePoints, unit:GetLocation())
				end
			elseif GetUnitToLocationDistanceSqr( unit, vBaseLocation ) < dis_sqr_3 then
				table.insert(tTagers_InRange3, unit)
			end
		end
	end

	if rd_best_result.count == 0 then
		if #tTagers_InRange3 > 0 then
			local unit = tTagers_InRange3[1]
			rd_best_result.count = 1
			rd_best_result.targetloc = vBaseLocation + (unit:GetLocation() - vBaseLocation) * (nMaxDistanceFromBase / GetUnitToLocationDistance( unit, vBaseLocation ))
		else
			return rd_best_result
		end
	end

	--limited random
	if #tTagers_InRange1 > 0 then

		for i=1,RandomTimes do
			local vPoint = tTagers_InRange1[RandomInt( 1, #tTagers_InRange1 )]:GetLocation()
			vPoint = vPoint + RandomVector( nRadius ) * math.random(0, 1)

			table.insert(vReservePoints, vPoint)


		end
	end

	-- completely random
	for i=1,RandomTimes do

		local vPoint = RandomVector( nMaxDistanceFromBase ) * math.random(0, 1)
		vPoint = vBaseLocation + vPoint

		table.insert(vReservePoints, vPoint)

	end

	-- (20+10*2) * N times
	for _,vPoint in pairs( vReservePoints ) do

		local count=0

		for _,unit in pairs( tTagers_InRange3 )
		do
			if GetUnitToLocationDistanceSqr( unit, vPoint ) < RadiusSqr then
				count = count + 1
			end
		end

		if count > rd_best_result.count then
			rd_best_result.count = count
			rd_best_result.targetloc = vPoint
		end

	end

	return rd_best_result

end

local LastFindAoEDotaTime = {}
local LastFindAoEResult = {}

--max for 200ms
local CacheAliveLimitNormal = 0.1
local CacheAliveLimitLooser = 0.2
--1000ms for full screen ability
local CacheAliveLimitWild = 1.0

local time_sum=0
local last_print_time=-6000

function CachedFindAoELocation( bot, nTag, bEnemies, bHeroes, vBaseLocation, nMaxDistanceFromBase, nRadius, fTimeInFuture, nMaxHealth)
    --[[
	local st=RealTime()
	if st - last_print_time >= 5.0 then
		print("-----CachedFindAoELocation-----")
		print(time_sum)
		print(st - last_print_time)
		print("-----CachedFindAoELocation-----")
		last_print_time = st
		time_sum = 0
	end
	]]--
	local CacheAliveLimit = CacheAliveLimitNormal
	if #GetTeamPlayers(TEAM_RADIANT) + #GetTeamPlayers(TEAM_DIRE) >=20 then
		CacheAliveLimit = CacheAliveLimitLooser
	end

	if not bHeroes then CacheAliveLimit = CacheAliveLimitWild end
	if nMaxDistanceFromBase >= 3000 then CacheAliveLimit = CacheAliveLimitWild end
	--if nMaxDistanceFromBase > 1500 and nMaxDistanceFromBase < 3000 then nMaxDistanceFromBase = 1500 end
	--if nRadius > 500 then nRadius = 500 end

	local tag = bot:GetPlayerID()*65536 + nTag

	if LastFindAoEDotaTime[tag] == nil then
		LastFindAoEDotaTime[tag] = -6000
		LastFindAoEResult[tag] = {}
	end

	-- Update 
	if DotaTime()-LastFindAoEDotaTime[tag] > CacheAliveLimit then
		LastFindAoEDotaTime[tag] = DotaTime()
		local tmp = {}
		if fTimeInFuture > 0 or not bHeroes or RandomInt( 1, 100 ) < 7 then
			tmp = bot:FindAoELocation(bEnemies, bHeroes, vBaseLocation, nMaxDistanceFromBase, nRadius, fTimeInFuture, nMaxHealth)
		elseif bEnemies then
			tmp = RandomChoose( GetUnitList(UNIT_LIST_ENEMY_HEROES), vBaseLocation, nMaxDistanceFromBase, nRadius, nMaxHealth)
		else
			tmp = RandomChoose( GetUnitList(UNIT_LIST_ALLIED_HEROES), vBaseLocation, nMaxDistanceFromBase, nRadius, nMaxHealth)
		end

		if tmp == nil then tmp = {} end
		LastFindAoEResult[tag] = {}
		for _,v in pairs( tmp )
		do
			LastFindAoEResult[tag][_] = v
		end
	end

	--time_sum = time_sum + RealTime() - st

	return LastFindAoEResult[tag]

end

local LastGetNearbyHeroesDotaTime = {}
local LastGetNearbyHeroesResult = {}

local time_sum2=0
local last_print_time2=-6000

function CachedGetNearbyHeroes( bot, nRadius, bEnemies, nMode )

	--[[
	local st=RealTime()
	if st - last_print_time2 >= 5.0 then
		print("----CachedGetNearbyHeroes----")
		print(time_sum2)
		print(st - last_print_time2)
		print("----CachedGetNearbyHeroes----")
		last_print_time2 = st
		time_sum2 = 0
	end
	]]--
	--special: reduce to avoid error
	--local CacheAliveLimit = 0.05
	local CacheAliveLimit = 0.00

	--if nRadius > 1500 then CacheAliveLimit = CacheAliveLimitWild end
	--if nRadius > 1500 and nRadius < 3000 then nRadius = 1500 end
	--nRadius = nRadius - (nRadius%200)

	local RadiusSqr = nRadius*nRadius

	local tag = bot:GetPlayerID()*2048 + nRadius
	tag = tag*2
	if bEnemies then tag = tag + 1 end
	tag = tag*64+nMode

	if LastGetNearbyHeroesDotaTime[tag] == nil then
		LastGetNearbyHeroesDotaTime[tag] = -6000
		LastGetNearbyHeroesResult[tag] = {}
	end

	-- Update 
	if DotaTime()-LastGetNearbyHeroesDotaTime[tag] > CacheAliveLimit then
		LastGetNearbyHeroesDotaTime[tag] = DotaTime()
		local tmp = {}
		LastGetNearbyHeroesResult[tag] = {}
		if nRadius > 1500 then
			if bEnemies then
				tmp = GetUnitList(UNIT_LIST_ENEMY_HEROES)
			else
				tmp = GetUnitList(UNIT_LIST_ALLIED_HEROES)
			end
			for _,unit in pairs( tmp )
			do
				if GetUnitToUnitDistanceSqr( bot, unit ) < RadiusSqr then
					table.insert(LastGetNearbyHeroesResult[tag], unit)
				end
			end
		else
			tmp = bot:GetNearbyHeroes(nRadius, bEnemies, nMode)
			if tmp == nil then tmp = {} end
			for _,v in pairs( tmp )
			do
				LastGetNearbyHeroesResult[tag][_] = v
			end
		end
	end

	--time_sum2 = time_sum2 + RealTime() - st

	return LastGetNearbyHeroesResult[tag]

end

-- Can this bot do anything now?
function IsBotAwake( bot )

	if bot == nil then bot = GetBot() end
	return not ( bot:IsIllusion() or bot:IsHexed() or bot:IsStunned() )

end

function IsValid( nTarget )
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and not nTarget:IsBuilding()
end

function GetCenterOfUnits( nUnits )

	if #nUnits == 0
	then
		return Vector( 0.0, 0.0 )
	end

	local sum = Vector( 0.0, 0.0 )
	local num = 0

	for _, unit in pairs( nUnits )
	do
		if IsValid(unit)
		then
			sum = sum + unit:GetLocation()
			num = num + 1
		end
	end

	if num == 0 then return Vector( 0.0, 0.0 ) end

	return sum / num

end

function GetHP( unit )
	local nCurHealth = unit:GetHealth()
    local nMaxHealth = unit:GetMaxHealth()
	if nCurHealth <= 0 then return 0 end
	return nCurHealth / nMaxHealth
end

function GetEnemyPlayersID() return GetTeamPlayers(GetOpposingTeam()) end

function HasSpecificEnemyHero( nHeroName )
	local tEnemyPlayers = GetEnemyPlayersID()
	for _, i in pairs(tEnemyPlayers) do
		if GetSelectedHeroName(i) == nHeroName then
			return true
		end
	end
	return false
end

function IsKeyWordUnit( keyWord, uUnit )

	if string.find( uUnit:GetUnitName(), keyWord ) ~= nil
	then
		return true
	end

	return false
end
----------------------------------------------------------------------------------------------------

local function IsRocket(item_name)
	return item_name == "item_rocket" or
			item_name == "item_rocket_2" or
			item_name == "item_rocket_3" or
			item_name == "item_rocket_4" or
			item_name == "item_rocket_5"

end

function IsItemAvailable(item_name)
    local npcBot = GetBot()
    for i = 0, 5 do
        local item = npcBot:GetItemInSlot(i)
        if (item ~= nil) then
            if (item:GetName() == item_name) then
				return item
            end
        end
    end
    return nil
end

function SwapItemInBackpack(item_name)
	local npcBot = GetBot()
    for i = 6, 8 do
        local item = npcBot:GetItemInSlot(i)
        if (item ~= nil) then
            if (item:GetName() == item_name) then
				npcBot:ActionImmediate_SwapItems(i,5)
				return
            end
        end
    end
end

--战斗力估算(不包含主动技能)
function GetCapability( npcHero )

	local AttackDamage = npcHero:GetAttackDamage()
	local AttackRange = npcHero:GetAttackRange()
	local AttackSpeed = npcHero:GetSecondsPerAttack()

	if npcHero:HasModifier( "passive_youmu02_attack" ) then
		AttackDamage = AttackDamage*(4.0 * 1.0 / AttackSpeed)
	else
		AttackDamage = AttackDamage*0.5
	end

	return AttackDamage * (AttackRange/200 + 1) * (1.0 / AttackSpeed)

end

function GetPhysicalDamageRemain( fArmor )
	return 1.0 - ( 0.052*fArmor ) / ( 0.9 + 0.048*math.abs(fArmor) )
end

function GetModifierTimeLeft( Target, ModifierName )
	if ( not Target:HasModifier( ModifierName ) )
	then
		return 0.0
	else
		local mf_index = Target:GetModifierByName( ModifierName )
		return Target:GetModifierRemainingDuration( mf_index )
	end
end

function GetModifiersTimeLeft( Target, ModifierNames )
	for _,ModifierName in pairs( ModifierNames )
	do
		if ( Target:HasModifier( ModifierName ) )
		then
			local mf_index = Target:GetModifierByName( ModifierName )
			return Target:GetModifierRemainingDuration( mf_index )
		end
	end
	return 0.0
end

function IsTeleporting( Target )

	if ( Target:HasModifier( ModifierNamesTeleporting[1] ) or
			Target:HasModifier( ModifierNamesTeleporting[2] )
		)
	then
		return true
	end

	return false

end

function IsMagicBlocking( Target )

	if ( Target:HasModifier( ModifierNamesMagicBlock[1] ) )
	then
		return true
	end

	return false

end

function IsUnderAttack( Target , HeroOnly )
	--添加参数默认值以兼容旧代码
	if nil == HeroOnly then
		HeroOnly = false
	end
	local tableIncomingProjectiles = Target:GetIncomingTrackingProjectiles()
	for _,p in pairs( tableIncomingProjectiles )
	do
		if ( p.is_attack
			and GetUnitToLocationDistanceSqr(Target,p.location) < 200.0*200.0
			and (
					HeroOnly == nil
					or HeroOnly == false
					or ( p.caster ~=nil and p.caster:IsHero() )
				)
			)
		then
			return true
		end

	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( Target, 300 , true, BOT_MODE_NONE )
	if( tableNearbyEnemyHeroes == nil) then tableNearbyEnemyHeroes = { } end
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy:GetAttackTarget() == Target )
		then
			return true
		end

	end

	return false

end

function IsSeriouslyRetreating( npcBot )
	return (npcBot:GetActiveMode() == BOT_MODE_RETREAT
	and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH
	and not npcBot:HasModifier("modifier_fountain_aura_buff"))
	or npcBot:GetHealth()/npcBot:GetMaxHealth() < 0.1
end

----------------------------------------------------------------------------------------------------

function CanCastStunOnTarget( npcTarget )
	return npcTarget:CanBeSeen()
	and not npcTarget:IsMagicImmune()
	and not npcTarget:IsInvulnerable()
	and not IsPossibleIllusion( npcTarget )
end

function IsPossibleIllusion( npcTarget )
	return npcTarget:HasModifier("modifier_flandre01_illusion_model")
	or npcTarget:HasModifier("modifier_illusion")
end

function IsSpellVulnerable( npcTarget )
	return npcTarget:HasModifier("modifier_item_three_dimension_debuff")
	or npcTarget:HasModifier("modifier_item_ghost_spoon")
end

----------------------------------------------------------------------------------------------------

function ConsiderItemStun( item_stun )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_stun:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_stun:GetCastRange()
	--print(nCastRange)

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		local j_time=0.2
		if IsRocket( item_stun:GetName() ) then j_time = 0.7 end
		if GetModifiersTimeLeft( npcEnemy, ModifierNamesStun ) < j_time then
			if ( npcBot:GetTarget() == npcEnemy
			and CanCastStunOnTarget( npcEnemy )
			and not IsPossibleIllusion( npcEnemy )
			and not (npcEnemy:IsStunned() or npcEnemy:IsRooted()))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end

			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ))
			then
				if ( CanCastStunOnTarget( npcEnemy ) )
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderItemRoot( item_root )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_root:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_root:GetCastRange()
	--print(nCastRange)

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy
		and CanCastStunOnTarget( npcEnemy )
		and not (npcEnemy:IsStunned() or npcEnemy:IsRooted()))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ))
		then
			if ( CanCastStunOnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end

	end

	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderItemSlow( item_slow )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_slow:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,0
	end

	-- Get some of its values
	local nCastRange = 1000
	local nRadius = 600
	if item_slow:GetName() == "item_jiao_shou" then
		nCastRange = 600
		nRadius = 300
	end
	--print(nCastRange)
	-- 125 250

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	local locationAoE = CachedFindAoELocation( npcBot, 60001, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )
	if ( (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
			and locationAoE.count > 2 ) then
		return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	end

	if ( (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH
			and locationAoE.count > 0 ) then
		return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	end

	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if npcEnemy:HasModifier("modifier_item_jiao_shou_play_debuff") or npcEnemy:HasModifier("modifier_item_zaiezhizhurenxing_play_debuff") then
			return BOT_ACTION_DESIRE_NONE,0
		end
		if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and
				npcBot:GetTarget() == npcEnemy and
				CanCastStunOnTarget( npcEnemy )
			)
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			if ( CanCastStunOnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end

	end

	return BOT_ACTION_DESIRE_NONE,0

end

----------------------------------------------------------------------------------------------------

function ConsiderItemSpeed( item_speed )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_speed:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if ( (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		return BOT_ACTION_DESIRE_HIGH
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1500 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy )
		then
			return BOT_ACTION_DESIRE_HIGH
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			return BOT_ACTION_DESIRE_MODERATE
		end

	end

	return BOT_ACTION_DESIRE_NONE

end

function ConsiderItemSpeedMulti( item_speed )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_speed:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if ( (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		return BOT_ACTION_DESIRE_HIGH
	end

	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 650, false, BOT_MODE_NONE )
	if #tableNearbyFriendlyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend )
				) then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1500 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy )
		then
			return BOT_ACTION_DESIRE_HIGH
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			return BOT_ACTION_DESIRE_MODERATE
		end

	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemStand( item_stand )

	local npcBot = GetBot()
	local nRange = math.max(npcBot:GetAttackRange(),650)

	-- Make sure it's castable
	if ( not item_stand:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes1200 = CachedGetNearbyHeroes( npcBot, 1200 , true, BOT_MODE_NONE )

	if IsSeriouslyRetreating(npcBot) and #tableNearbyEnemyHeroes1200 > 0 then
		return BOT_ACTION_DESIRE_HIGH
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nRange , true, BOT_MODE_NONE )

	if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
		if #tableNearbyEnemyHeroes > 2 then
			return BOT_ACTION_DESIRE_HIGH
		end

		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if npcBot:GetTarget() == npcEnemy then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemTeeth( item_teeth )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_teeth:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, npcBot:GetAttackRange()+200, true, BOT_MODE_NONE )
		if ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemGhost( item_ghost )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_ghost:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if ( IsUnderAttack(npcBot) )
	then
		return BOT_ACTION_DESIRE_MODERATE
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemWeiJin( item_weijin )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_weijin:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_RETREAT )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 900-200, true, BOT_MODE_NONE )
		if ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemDouPeng( item_doupeng )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_doupeng:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	local tableNearbyEnemyHeroes1000 = CachedGetNearbyHeroes( npcBot, 1000 , true, BOT_MODE_NONE )

	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
			and #tableNearbyEnemyHeroes1000 > 0
			) then
		return BOT_ACTION_DESIRE_HIGH
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 550 , true, BOT_MODE_NONE )

	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy )
		then
			return BOT_ACTION_DESIRE_MODERATE
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			return BOT_ACTION_DESIRE_HIGH
		end

	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderItemFeiXiangJian( item_feixiangjian )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_feixiangjian:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_feixiangjian:GetCastRange()
	--print(nCastRange)

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if npcEnemy:HasModifier("modifier_thdots_shikieiki04_debuff") or npcEnemy:IsMuted()
		then
			return BOT_ACTION_DESIRE_NONE, nil
		end

		if ( npcBot:GetTarget() == npcEnemy and CanCastStunOnTarget( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			if ( CanCastStunOnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end

	end
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderItemXinYan( item_xinyan )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_xinyan:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_xinyan:GetCastRange()
	--print(nCastRange)

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and CanCastStunOnTarget( npcEnemy )  )
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			if ( CanCastStunOnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderItemFan( item_fan )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_fan:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nCastRange = item_fan:GetCastRange() - 100
	local nRadius = 100
	local nDamage = (200 + math.floor(GameTime()/60) * 4) * (1 + npcBot:GetSpellAmp())
	-- print("fan_damage")
	-- print(nDamage)

	if ( npcBot:GetActiveMode() == BOT_MODE_FARM ) then
		local locationAoE = CachedFindAoELocation( npcBot, 60002, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, nDamage )

		if ( locationAoE.count >= 1 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end

	-- If we're pushing or defending a lane and can hit 2+ creeps, go for it
	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local locationAoE = CachedFindAoELocation( npcBot, 60003, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )

		if ( locationAoE.count >= 2 )
		then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end
	if ( (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) then

		local locationAoE = CachedFindAoELocation( npcBot, 60004, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )

		if ( locationAoE.count >= 1 )
		then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderItemQiJiZhiXing( item_qijizhixing )

	local npcBot = GetBot()
	local nModifier = npcBot:GetModifierByName("modifier_ability_thdots_ellen04_debuff")

	-- Make sure it's castable
	if ( not item_qijizhixing:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_qijizhixing:GetCastRange()

	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, false, BOT_MODE_NONE )

	if HasSpecificEnemyHero("npc_dota_hero_arc_warden") then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
		if ( npcBot:GetModifierStackCount(nModifier) >= 4 or
			npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.28)
		then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end
	else
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 2.5 ) or
				npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.5)
			then
				return BOT_ACTION_DESIRE_HIGH, npcFriend
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
----------------------------------------------------------------------------------------------------

function ConsiderItemJump( item_jump, delta_min, delta_max)

	delta_min = delta_min or 100
	delta_max = delta_min or 600

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_jump:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nCastRange = 500
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + delta_max, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			local target1 = npcBot:GetTarget()
			if ( target1 == npcEnemy and
			GetUnitToUnitDistance(npcBot,npcEnemy) >= nCastRange - delta_min and
			GetUnitToUnitDistance(npcBot,npcEnemy) <= nCastRange - delta_min + delta_max and
			(target1:GetHealth() < target1:GetMaxHealth()*0.3 or target1:GetHealth() < npcBot:GetAttackDamage() * 3)
			)
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
	end
	if IsSeriouslyRetreating(npcBot) then
		local v_shop = GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
		local v_target = - npcBot:GetLocation() + v_shop
		local dis = GetUnitToLocationDistance( npcBot,v_shop)
		local v_final = v_target/dis * nCastRange + npcBot:GetLocation()
		return BOT_ACTION_DESIRE_HIGH, v_final
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderItemDuQun( item_duqun )

	local npcBot = GetBot()
	local nModifier = npcBot:GetModifierByName("modifier_ability_thdots_ellen04_debuff")

	-- Make sure it's castable
	if ( not item_duqun:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1600 , true, BOT_MODE_NONE )
	if HasSpecificEnemyHero("npc_dota_hero_arc_warden") then
		if npcBot:GetModifierStackCount(nModifier) >= 5 and npcBot:GetModifierRemainingDuration(nModifier) <= 1.3 then
			return BOT_ACTION_DESIRE_VERYHIGH
		end
	else
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
				then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderItemMoonBow( item_moon_bow )
	--月弓 待优化
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_moon_bow:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Get some of its values
	local nCastRange = item_moon_bow:GetCastRange()
	local nRadius = 150
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange - 500, true, BOT_MODE_NONE )
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK or  npcBot:GetActiveMode() == BOT_MODE_RETREAT then
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderItemKafziel( item_kafziel )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_kafziel:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_kafziel:GetCastRange()
	--print(nCastRange)
	local max_hr = 0
	local target_cache = nil
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if npcEnemy:HasModifier("modifier_thdots_komachi_04_debuff")
		then
			return BOT_ACTION_DESIRE_NONE, nil
		end
		if ( CanCastStunOnTarget( npcEnemy ) )
		then
			if (npcEnemy:GetHealthRegen() >= max_hr) then target_cache = npcEnemy end
			if (npcEnemy:GetUnitName() == "npc_dota_hero_drow_ranger" or
				npcEnemy:GetUnitName() == "npc_dota_hero_warlock" or
				npcEnemy:GetUnitName() == "npc_dota_hero_dark_seer" or
				npcEnemy:GetUnitName() == "npc_dota_hero_naga_siren" )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
	end
	if (target_cache ~= nil)
	then
		return BOT_ACTION_DESIRE_HIGH, target_cache
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
----------------------------------------------------------------------------------------------------

function ConsiderItemBlue( item_blue )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_blue:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	if (npcBot:GetMana() < npcBot:GetMaxMana()* 0.3) then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderItemHorseRed( item_horse_red )

	local npcBot = GetBot()

	-- Make sure it's castable
	if (not item_horse_red:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 600, true, BOT_MODE_NONE )
		if not ( #tableNearbyEnemyHeroes >= 1 ) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	if ( npcBot:GetHealth()/npcBot:GetMaxHealth() <= 0.8 and (npcBot:TimeSinceDamagedByAnyHero() >= 2.5 )) then
		return BOT_ACTION_DESIRE_MODERATE
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemHorseGreen( item_horse_green )

	local npcBot = GetBot()

	-- Make sure it's castable
	if (not item_horse_green:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, npcBot:GetAttackRange(), true, BOT_MODE_NONE )
		if ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemHorseKing( item_horse_king )

	local npcBot = GetBot()
	local nRange = math.max(npcBot:GetAttackRange(),650)
	local manaPercent = npcBot:GetMana()/npcBot:GetMaxMana()

	-- Make sure it's castable
	if (not item_horse_king:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and manaPercent > 0.2 then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nRange, true, BOT_MODE_NONE )
		if ( #tableNearbyEnemyHeroes > 0 ) then
			if npcBot:HasModifier("modifier_item_horse_king_open") then
				return BOT_ACTION_DESIRE_NONE
			end
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	if IsSeriouslyRetreating(npcBot) then
		if npcBot:HasModifier("modifier_item_horse_king_open") then
			return BOT_ACTION_DESIRE_NONE
		end
		return BOT_ACTION_DESIRE_MODERATE
	end

	-- 想办法主动关掉
	if npcBot:HasModifier("modifier_item_horse_king_open") then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nRange, true, BOT_MODE_NONE )
		if not ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderItemYukkuriStick( item_yukkuri_stick )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_yukkuri_stick:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Get some of its values
	local nCastRange = item_yukkuri_stick:GetCastRange()
	--print(nCastRange)\

	local j_time=0.2
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if npcEnemy:HasModifier("modifier_thdots_shikieiki04_debuff") or npcEnemy:IsHexed()
		then
			return BOT_ACTION_DESIRE_NONE, nil
		end
		if GetModifiersTimeLeft( npcEnemy, ModifierNamesStun ) < j_time then
			if ( npcBot:GetTarget() == npcEnemy and CanCastStunOnTarget( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end

			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ))
			then
				if ( CanCastStunOnTarget( npcEnemy ) )
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderItemTiDeng( item_tideng )
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_tideng:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if (npcBot:GetHealth() < npcBot:GetMaxHealth()* 0.35) then
		return BOT_ACTION_DESIRE_HIGH
	end

	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderItemBook( item_three_dimension )

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not item_three_dimension:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = item_three_dimension:GetCastRange()
	--print(nCastRange)

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+200 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and CanCastStunOnTarget( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ))
		then
			if ( CanCastStunOnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------


function ConsiderItemDoctorDoll(item_doctor_doll)
	local npcBot = GetBot()

	if ( not item_doctor_doll:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if IsSeriouslyRetreating(npcBot) or npcBot:GetHealth() < npcBot:GetMaxHealth()*0.25 then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------


function ConsiderNeutralItems(tBlacklist)

	local npcBot = GetBot()
	local DOTA_ITEM_NEUTRAL_SLOT = 16
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 650 , true, BOT_MODE_NONE )

	local item = npcBot:GetItemInSlot(DOTA_ITEM_NEUTRAL_SLOT)
	if item == nil or not item:IsFullyCastable() then
		return
	end

	local itemName = item:GetName()
	local nCastRange = item:GetCastRange()

	if tBlacklist ~= nil and #tBlacklist > 0 then
		for _, blacklistedItem in pairs(tBlacklist) do
			if itemName == blacklistedItem then
				return
			end
		end
	end

	if itemName == "item_unstable_wand" then
		if IsSeriouslyRetreating(npcBot) then
			npcBot:Action_UseAbility(item)
			return
		end
		return
	elseif itemName == "item_polliwog_charm" then
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, false, BOT_MODE_NONE )
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.8 then
				npcBot:Action_UseAbilityOnEntity(item,npcFriend)
				return
			end
		end
		return
	elseif itemName == "item_kobold_cup" then
		if ConsiderItemSpeedMulti(item) > 0 then
			npcBot:Action_UseAbility(item)
			return
		end
	elseif itemName == "item_essence_ring" then
		if IsSeriouslyRetreating(npcBot) or npcBot:GetHealth() < npcBot:GetMaxHealth()*0.25 then
			npcBot:Action_UseAbility(item)
			return
		end
	elseif itemName == "item_rippers_lash" then
		local nRadius = 200
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes > 0 then
			for _, npcEnemy in pairs(tableNearbyEnemyHeroes) do
				if CanCastNeutralItemOnTarget(npcEnemy) then
					local locationAoE = CachedFindAoELocation( npcBot, 60005, true, true, npcEnemy:GetLocation(), nCastRange, nRadius, 0, 0 )
					if locationAoE.count > 1 then
						npcBot:Action_UseAbilityOnLocation(item,locationAoE.targetloc)
						return
					end
				end
			end
			npcBot:Action_UseAbilityOnLocation(item,tableNearbyEnemyHeroes[1]:GetLocation())
			return
		end
		return
	elseif itemName == "item_pogo_stick" then
		if IsSeriouslyRetreating(npcBot) then
			npcBot:Action_UseAbility(item)
			return
		end
		return
	elseif itemName == "item_mana_draught" then
		npcBot:Action_UseAbility(item)
		return
	elseif itemName == "item_gale_guard" then
		if ConsiderItemDouPeng(item) > 0 then
			npcBot:Action_UseAbility(item)
			return
		end
		return
	elseif itemName == "item_jidi_pollen_bag" then
		if ConsiderItemWeiJin(item) > 0 then
			npcBot:Action_UseAbility(item)
			return
		end
		return
	elseif itemName == "item_psychic_headband" then
		if IsSeriouslyRetreating(npcBot) then
			tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
			if #tableNearbyEnemyHeroes > 0 then
				if CanCastNeutralItemOnTarget(tableNearbyEnemyHeroes[1]) then
					npcBot:Action_UseAbilityOnEntity(item,tableNearbyEnemyHeroes[1])
				end
			return
			end
		end
		return
	elseif itemName == "item_crippling_crossbow" then
		if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
			tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
			if #tableNearbyEnemyHeroes > 0 then
				for _, npcEnemy in pairs(tableNearbyEnemyHeroes) do
					if npcBot:GetTarget() == npcEnemy and CanCastNeutralItemOnTarget(npcEnemy) then
						npcBot:Action_UseAbilityOnEntity(item,npcEnemy)
						return
					end
				end
			end
		end
		return
	elseif itemName == "item_outworld_staff" then
		local tableIncomingProjectiles = npcBot:GetIncomingTrackingProjectiles()
		for _,p in pairs( tableIncomingProjectiles )
		do
			if p.ability ~= nil and p.caster ~=nil and p.caster:IsHero() then
				local stunTime = p.ability:GetSpecialValueFloat("stun_duration") or p.ability:GetSpecialValueFloat("rocket_stun_duration") or 0
				if stunTime > 0 then
					npcBot:Action_UseAbility(item)
				end
			end
		end
		return
	elseif itemName == "item_pyrrhic_cloak" then
		tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+50, true, BOT_MODE_NONE )
		local mxcap=0
		local mxTarget=nil
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastNeutralItemOnTarget(npcEnemy) then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end
		if #tableNearbyEnemyHeroes > 2 then
			if mxTarget ~= nil then
				npcBot:Action_UseAbilityOnEntity(item,mxTarget)
				return
			end
		end

		if #tableNearbyEnemyHeroes > 0 and (npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
		and((npcBot:GetActiveMode() == BOT_MODE_ATTACK and #tableNearbyEnemyHeroes > 1)
		or npcBot:GetActiveMode() == BOT_MODE_RETREAT)) then
			if mxTarget ~= nil then
				npcBot:Action_UseAbilityOnEntity(item,mxTarget)
				return
			end
		end
		return
	elseif itemName == "item_fallen_sky" then
		local nRadius = 315
		tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes > 0 then
			for _, npcEnemy in pairs(tableNearbyEnemyHeroes) do
				if CanCastNeutralItemOnTarget(npcEnemy) then
					local locationAoE = CachedFindAoELocation( npcBot, 60006, true, true, npcEnemy:GetLocation(), nCastRange, nRadius, 0, 0 )
					if locationAoE.count > 2 then
						npcBot:Action_UseAbilityOnLocation(item,locationAoE.targetloc)
						return
					end
				end
			end
			npcBot:Action_UseAbilityOnLocation(item,tableNearbyEnemyHeroes[1]:GetLocation())
			return
		end
		return
	elseif itemName == "item_minotaur_horn" then
		if IsSeriouslyRetreating(npcBot)
		or (npcBot:GetActiveMode() == BOT_MODE_ATTACK
		and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
		and #tableNearbyEnemyHeroes > 2) then
			npcBot:Action_UseAbility(item)
			return
		end
		return
	elseif itemName == "item_spider_legs" then
		if ConsiderItemSpeed(item) > 0 then
			npcBot:Action_UseAbility(item)
			return
		end
		return
	elseif itemName == "item_demonicon" then
		if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
			npcBot:Action_UseAbility(item)
		end
	end
end

function CanCastNeutralItemOnTarget(npcTarget)
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable() and not IsPossibleIllusion( npcTarget )
end