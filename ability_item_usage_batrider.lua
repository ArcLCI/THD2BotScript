
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

	local item_doupeng = IsItemAvailable( "item_zun_glasses" )
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
						IsItemAvailable( "item_jiao_shou" )
	local item_xinyan = IsItemAvailable( "item_third_eyes" )
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
		castItemSlowDesire = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, npcBot:GetLocation() )
			return
		end
	end
	
	if ( item_xinyan~=nil and item_xinyan:IsFullyCastable() )
	then 
		castItemXinYanDesire, castItemXinYanTarget = ConsiderItemXinYan( item_xinyan )
		if ( castItemXinYanDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_xinyan, castItemXinYanTarget )
			return
		end
	end
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_seija01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_seija02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_seija03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_seija04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_seijaEx" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilitySeija01()
	cast02Desire, cast02Location = ConsiderAbilitySeija02()
	cast03Desire, cast03Target = ConsiderAbilitySeija03()
	cast04Desire, cast04Location = ConsiderAbilitySeija04()
	castExDesire, castExTarget = ConsiderAbilitySeijaEx()
	
	mode04 = 0
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location)
	end

	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end

	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target)
		return
	end

	if ( cast04Desire > 0 ) 
	then
		if mode04 == 0
		then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		else
		npcBot:Action_UseAbilityOnLocation( ability04 , cast04Location)
		end
		return
	end
	
	if ( castExDesire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( abilityEx , castExTarget)
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastSeija01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastSeija02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastSeija03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and ( GetBot():HasScepter() or not npcTarget:IsMagicImmune() ) and not npcTarget:IsInvulnerable()
end

function CanCastSeija04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSeijaExOnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and ( GetBot():HasScepter() or not npcTarget:IsMagicImmune() ) and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeija01()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = ability01:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMedicine01OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeija02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nRadius = ability02:GetSpecialValueInt( "radius" )
	local nCastRange = ability02:GetCastRange()
	local nDamage = ability02:GetAbilityDamage()

	--------------------------------------
	-- Mode based usage
	--------------------------------------

	-- If we're farming and can kill 3+ creeps with LSA
	if ( npcBot:GetActiveMode() == BOT_MODE_FARM ) then
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, nDamage )

		if ( locationAoE.count >= 3 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end

	-- If we're pushing or defending a lane and can hit 4+ creeps, go for it
	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT ) 
	then
		local locationAoE = CachedFindAoELocation( npcBot, 2, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )

		if ( locationAoE.count >= 4 ) 
		then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastMedicine02OnTarget( npcEnemy )  ) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
				
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) ) 
			then
				if ( CanCastMedicine02OnTarget( npcEnemy ) ) 
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
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
			if ( CanCastMedicine02OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeija03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability03:GetCastRange()
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastMedicine03OnTarget( npcFriend ) and 
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeija04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability04:GetCastRange()
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+100, true, BOT_MODE_NONE )
		local mxcap=0
		local mxTarget=nil
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMedicine04OnTarget( npcEnemy ) ) 
			then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end
		
	if #tableNearbyEnemyHeroes > 2 then
		return BOT_ACTION_DESIRE_MODERATE, mxTarget
	end
	
	if #tableNearbyEnemyHeroes > 0 and (
			npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and(
				(npcBot:GetActiveMode() == BOT_MODE_ATTACK and #tableNearbyEnemyHeroes > 1) or
				npcBot:GetActiveMode() == BOT_MODE_RETREAT
			) 
		) then
		return BOT_ACTION_DESIRE_MODERATE, mxTarget
	end
	

	return BOT_ACTION_DESIRE_NONE,nil

end

