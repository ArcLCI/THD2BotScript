
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
castExDesire = 0

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_hatate01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_hatate02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_hatate03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_hatate04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_hatateEx" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityHatate01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast02Desire, cast02Location = ConsiderAbilityHatate02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end

	cast03Desire = ConsiderAbilityHatate03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03 )
		return
	end

	cast04Desire = ConsiderAbilityHatate04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end
	
	castExDesire = ConsiderAbilityHatateEx()
	if ( castExDesire > 0 ) 
	then
		npcBot:Action_UseAbility( abilityEx )
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastHatate02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityHatate01()


	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nRadius = ability01:GetSpecialValueInt( "radius" )
	local nCastRange = ability01:GetLevel()*100 + 300

	--------------------------------------
	-- Mode based usage
	--------------------------------------

	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK or
		 npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
	then
		local npcTarget = npcBot:GetTarget()
		
		if npcBot:GetTarget() ~= nil then
			local disT = GetUnitToUnitDistance( npcBot, npcBot:GetTarget())
			local dimin = 500
			local dimax = 500 + nCastRange
			if disT > dimin and disT < dimax then
				print('hatate 1 2')
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and 
	npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
	print('hatate 1 3')
		return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityHatate02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = ability02:GetCastRange()
	local nRadius = 300
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange + 50, nRadius, 1, 0 )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 50, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastHatate02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityHatate03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- local attackT = npcBot:GetAttackTarget()
	
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

function ConsiderAbilityHatate04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_GANK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1600, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil ) 
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end
	
	for _,npcFriend in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
		do
			if ( npcFriend~=nil )
			then
			if ( npcFriend:IsAlive())
			then
			if ( ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
				return BOT_ACTION_DESIRE_HIGH
			end
			end
			end
		end
	
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityHatateEx()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting or Retreating with hero
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetHealth() < npcBot:GetMaxHealth()*0.2 ) 
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	
	return BOT_ACTION_DESIRE_NONE
end
