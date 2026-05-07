
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast03endDesire = 0
cast04Desire = 0
cast05Desire = 0


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_doupeng = IsItemAvailable( "item_zun_glasses" )
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
						IsItemAvailable( "item_jiao_shou" )
	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_pomo = IsItemAvailable( "item_pomojinlingli" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_king = IsItemAvailable( "item_horse_king")

	if ( item_doupeng~=nil and item_doupeng:IsFullyCastable() )
	then
		castItemDouPengDesire = ConsiderItemDouPeng( item_doupeng )
		if ( castItemDouPengDesire > 0 )
		then
			npcBot:Action_UseAbility( item_doupeng )
			return
		end
	end
	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end

	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemGhostDesire, castItemGhostTarget = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_ghost, castItemGhostTarget )
			return
		end
	end

	if ( item_pomo~=nil and item_pomo:IsFullyCastable() )
	then
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_pomo )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_pomo, castItemStunTarget )
			return
		end
	end

	if ( item_horse_red~=nil and item_horse_red:IsFullyCastable() )
	then
		local castItemHorseRedDesire = ConsiderItemHorseRed(item_horse_red)
		if ( castItemHorseRedDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_red )
			return
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then
		local castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_king )
			return
		end
	end


end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()


	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_ellen01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_ellen02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_ellen03" )
	ability03end = npcBot:GetAbilityByName( "ability_thdots_ellen03_end" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_ellen04" )
	ability05 = npcBot:GetAbilityInSlot(3)


	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityEllen01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast02Desire = ConsiderAbilityEllen02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02 )
		return
	end

	cast03Desire, cast03Location = ConsiderAbilityEllen03()
	if ( cast03Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability03, cast03Location )
		return
	end

	cast03endDesire = ConsiderAbilityEllen03end()
	if ( cast03endDesire > 0 )
	then
		npcBot:Action_UseAbility( ability03end )
		return
	end

	cast04Desire, cast04Location = ConsiderAbilityEllen04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

	cast05Desire, cast05Location = ConsiderAbilityEllen05()
	if ( cast05Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability05, cast05Location )
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastEllen01OnTarget( npcTarget )
	return npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable() and not IsPossibleIllusion(npcTarget)
end


function CanCastEllen02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastEllen03OnTarget( npcTarget )
	return not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastEllen04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable() and not IsPossibleIllusion(npcTarget)
end

function CanCastEllen05OnTarget( npcTarget )
	return npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityEllen01()

	local npcBot = GetBot()
	local nCastPoint = ability01:GetCastPoint()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability01:GetCastRange()

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1600, true, BOT_MODE_NONE )
	--[[
		if #tableNearbyEnemyHeroes == 0
		then
			return BOT_ACTION_DESIRE_MODERATE, npcBot:GetLocation()
		end
	--]]
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastEllen01OnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetExtrapolatedLocation(nCastPoint)
			end
		end

	return BOT_ACTION_DESIRE_NONE, 0

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityEllen02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Fighting or Retreating with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_RETREAT)
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 450, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityEllen03()

	local npcBot = GetBot()
	local nMP = npcBot:GetMana()/npcBot:GetMaxMana()
	local nCastPoint = 0.2
    local nSpeed = 650

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Get some of its values
	local nCastRange = ability03:GetCastRange()
	local nRadius = 275
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1600, true, BOT_MODE_NONE )
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_RETREAT then
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy ) then
				if npcEnemy:GetMovementDirectionStability() >= 0.75 then
					local eta = (GetUnitToUnitDistance(npcBot, npcEnemy) / nSpeed) + nCastPoint
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
				else
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
				end
			end
		end
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(750,true)
		if tableNearbylanecreeps ~= nil and #tableNearbylanecreeps >= 3
        then
            return BOT_ACTION_DESIRE_HIGH, GetCenterOfUnits(tableNearbylanecreeps)
        end
	end

	if nMP > 0.58 and #tableNearbyEnemyHeroes > 0 then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy ) then
				if npcEnemy:GetMovementDirectionStability() >= 0.75 then
					local eta = (GetUnitToUnitDistance(npcBot, npcEnemy) / nSpeed) + nCastPoint
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
				else
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityEllen04()

	local npcBot = GetBot()
	local nMP = npcBot:GetMana()/npcBot:GetMaxMana()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Get some of its values
	local nCastRange = ability04:GetCastRange()
	local nRadius = 225
	local nCastPoint = 0.3
    local nSpeed = 1200
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange*1.1, true, BOT_MODE_NONE )
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK or  npcBot:GetActiveMode() == BOT_MODE_RETREAT then
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastEllen04OnTarget(npcEnemy)) then
				if npcEnemy:GetMovementDirectionStability() >= 0.75 then
					local eta = (GetUnitToUnitDistance(npcBot, npcEnemy) / nSpeed) + nCastPoint
					return BOT_ACTION_DESIRE_VERYHIGH, npcEnemy:GetExtrapolatedLocation(eta)
				else
					return BOT_ACTION_DESIRE_VERYHIGH, npcEnemy:GetLocation()
				end
			end
		end
	end

	if nMP > 0.32 and #tableNearbyEnemyHeroes > 0 then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastEllen04OnTarget(npcEnemy) then
				if npcEnemy:GetMovementDirectionStability() >= 0.75 then
					local eta = (GetUnitToUnitDistance(npcBot, npcEnemy) / nSpeed) + nCastPoint
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
				else
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityEllen03end()

	local npcBot = GetBot()

	if ability03end ~= npcBot:GetAbilityInSlot(2)
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Make sure it's castable
	if ( not ability03end:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	-- as bot has mana buff and could multi controll perfectly
	-- bot should just use this as much as possible
	return BOT_ACTION_DESIRE_VERYHIGH

end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityEllen05()

	local npcBot = GetBot()
	local nActivationDelay = ability05:GetSpecialValueFloat('activation_delay')

	-- Make sure it's castable
	if ( not ability05:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability05:GetCastRange()

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange-50, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastEllen05OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				if npcEnemy:IsChanneling()
				then
					return BOT_ACTION_DESIRE_HIGH, ConsiderPointVectorAbilityLocation(npcEnemy:GetLocation())
				end
				return BOT_ACTION_DESIRE_HIGH, ConsiderPointVectorAbilityLocation(npcEnemy:GetExtrapolatedLocation(nActivationDelay))
			end
		end
	return BOT_ACTION_DESIRE_NONE, 0
end

function ConsiderPointVectorAbilityLocation(nLocation)
	local centerPoint = Vector(0,0)
	local nLength = 275

	local dist = math.sqrt(nLocation.x * nLocation.x + nLocation.y * nLocation.y + nLocation.z * nLocation.z)
	local unitVector = nLocation/dist

	return nLocation + (unitVector*nLength)
end