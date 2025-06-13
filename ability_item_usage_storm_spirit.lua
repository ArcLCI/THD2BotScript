
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

	local item_stand = IsItemAvailable( "item_dummy_doll1" )
	local item_root = IsItemAvailable( "item_tentacle" )
	local item_doupeng = IsItemAvailable( "item_zun_glasses" )
	local item_feixiangjian = IsItemAvailable( "item_feixiangjian" )
	
	if ( item_stand~=nil and item_stand:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemStandDesire = ConsiderItemStand( item_stand )
		if ( castItemStandDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_stand )
			return
		end
	end
		
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then 
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
	end
	
	if ( item_doupeng~=nil and item_doupeng:IsFullyCastable() )
	then 
		castItemDouPengDesire = ConsiderItemDouPeng( item_doupeng )
		if ( castItemDouPengDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_doupeng )
			return
		end
	end
	
	if ( item_feixiangjian~=nil and item_feixiangjian:IsFullyCastable() )
	then 
		castItemFeiXiangJianDesire, castItemFeiXiangJianTarget = ConsiderItemFeiXiangJian( item_feixiangjian )
		if ( castItemFeiXiangJianDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_feixiangjian, castItemFeiXiangJianTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_shikieiki01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_shikieiki02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_shikieiki04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityShikieiki01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityShikieiki02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target)
		return
	end
	
	cast04Desire, cast04Target = ConsiderAbilityShikieiki04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastShikieiki01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastShikieiki02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastShikieiki04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityShikieiki01()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = ability01:GetCastRange()
	local nRadius = ability01:GetSpecialValueInt( "AOE" )
	local nTime = 0
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, nTime, 0 )
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastShikieiki01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) and locationAoE.count >= 1 ) 
			then
				return BOT_ACTION_DESIRE_VERYHIGH, locationAoE.targetloc
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityShikieiki02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability02:GetCastRange()
	
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
	
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and not IsPossibleIllusion( npcEnemy ) and CanCastShikieiki02OnTarget( npcEnemy ) or 
			( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) ) 
			) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityShikieiki04()

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
			if ( CanCastShikieiki04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end
	
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY or
		 (npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and 
		 (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
		 npcBot:GetActiveMode() == BOT_MODE_RETREAT)
		 )
		)
	then
		return BOT_ACTION_DESIRE_HIGH, mxTarget
	end
	

	return BOT_ACTION_DESIRE_NONE,nil

end

