
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
	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	local item_frock = IsItemAvailable( "item_frock" )
	local item_rocket = IsItemAvailable( "item_rocket" ) or
				IsItemAvailable( "item_rocket_2" ) or
				IsItemAvailable( "item_rocket_3" ) or
				IsItemAvailable( "item_rocket_4" ) or
				IsItemAvailable( "item_rocket_5" )
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
	
	if ( item_frock~=nil and item_frock:IsFullyCastable() )
	then 
		castItemDuQunDesire = ConsiderItemDuQun(item_frock)
		if ( castItemDuQunDesire > 0 ) 
		then
			npcBot:Action_UseAbility(item_frock)
			return
		end
	end
	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then 
		castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget)
			return
		end
	end
	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then 
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_kisume01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_kisume02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_kisume03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_kisume04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityKisume01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end
	
	cast04Desire = ConsiderAbilityKisume04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end
	
	cast02Desire, cast02Location = ConsiderAbilityKisume02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end

	cast03Desire = ConsiderAbilityKisume03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03 )
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastKisume01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastKisume02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastKisume04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityKisume01()


	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nRadius = 120
	local nCastRange = 900
	local nDamage = ability01:GetAbilityDamage()

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

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and CanCastKisume01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end
			
		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) ) 
		then
			if ( CanCastKisume01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
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
			if ( CanCastKisume01OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityKisume02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nCastRange = ability02:GetLevel()*100 + 300
	local nRadius = 500
	if npcBot:GetLevel() >= 20 then
		nCastRange = ability02:GetLevel()*100 + 800
	end
	local abilitycount = npcBot:GetModifierByName("modifier_ability_thdots_kisumeEx_telent_1")
	local num = npcBot:GetModifierStackCount(abilitycount)
	local maxnum = 4
	if npcBot:GetLevel() >= 25 then
		maxnum = 2
	end

	--------------------------------------
	-- Mode based usage
	--------------------------------------
	if num >= maxnum then
		if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			 npcBot:GetActiveMode() == BOT_MODE_ROAM or
			 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
			 npcBot:GetActiveMode() == BOT_MODE_GANK or
			 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
		then
			local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, 1, 0 )
			if ( locationAoE.count >= 2 ) then
				return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
			end
			local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius - 100, true, BOT_MODE_NONE )
			for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
			do
				if ( CanCastKisume02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
				then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
				end
			end
		end
	end
	
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
		local v_shop = GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
		local v_target = - npcBot:GetLocation() + v_shop
		local dis = GetUnitToLocationDistance( npcBot,v_shop)
		local v_final = v_target/dis * nCastRange + npcBot:GetLocation()
		return BOT_ACTION_DESIRE_HIGH, v_final
	end
	return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityKisume03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1200 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) ) 
			then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityKisume04()

	local npcBot = GetBot()
	
	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local nRadius = 450
	local nDamage = ability04:GetLevel()*250 + 250
	
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK or
		 npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
	then
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), 0, nRadius, 0.1, nDamage )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetHealth() < npcBot:GetMaxHealth()*0.15) then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE

end

