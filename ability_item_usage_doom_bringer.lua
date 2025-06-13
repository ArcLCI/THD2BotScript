
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0


function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	

	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )
	
	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemGhostDesire = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_ghost )
			return
		end
	end

	if ( item_weijin~=nil and item_weijin:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemWeijinDesire = ConsiderItemWeiJin(item_weijin)
		if ( castItemWeijinDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_weijin )
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
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_clown01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_clown02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_clown03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_clown04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityClown01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityClown02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02, cast02Target )
		return
	end

	cast03Desire = ConsiderAbilityClown03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03)
		return
	end
	
	cast04Desire, cast04Location = ConsiderAbilityClown04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastClown01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastClown02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastClown03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastClown04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityClown01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = ability01:GetCastRange()
	local nRadius = ability01:GetSpecialValueInt( "radius" )
	local nSpeed = ability01:GetSpecialValueInt( "speed" )
	local nTime = nCastRange/nSpeed * 0.75
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, nTime, 0 )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastClown01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityClown02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	--------------------------------------
	-- Mode based usage
	--------------------------------------
	local nCastRange = ability02:GetCastRange()
	local tableNearbyLanecreeps = npcBot:GetNearbyLaneCreeps(nCastRange, true)

	if ( #tableNearbyLanecreeps >= 2 ) then
		return BOT_ACTION_DESIRE_HIGH, npcBot
	end
	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastClown02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end
	-- If we're going after someone
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
	then
		local npcTarget = npcBot:GetTarget()

		if ( npcTarget ~= nil ) 
		then
			if ( CanCastClown02OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityClown03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting or Retreating with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 300, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end
	
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityClown04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = ability04:GetCastRange()
	local nRadius = 500
	local locationAoE = CachedFindAoELocation( npcBot, 2, true, true, npcBot:GetLocation(), nCastRange, nRadius-100, 0, 0 )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
		--[[
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastClown04OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
		--]]
	return BOT_ACTION_DESIRE_NONE, 0
end

