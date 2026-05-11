
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

	item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )
	item_ghost = IsItemAvailable( "item_ghost_balloon" )
	item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	item_shield = IsItemAvailable( "item_esdw" ) or IsItemAvailable( "item_trinity" )
	
	if ( item_morenjingjuan~=nil and item_morenjingjuan:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemMoRenDesire, castItemMoRenTarget = ConsiderItemRoot( item_morenjingjuan )
		if ( castItemMoRenDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_morenjingjuan, castItemMoRenTarget )
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

	if ( item_shield~=nil and item_shield:IsFullyCastable() )
	then 
		castItemShieldDesire = ConsiderItemShield(item_shield)
		if ( castItemShieldDesire > 0 )
		then
			npcBot:Action_UseAbility( item_shield )
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

end

function AbilityUsageThink()

	if not IsBotAwake() then return end
	
	MyItemUsageThink()
	ConsiderNeutralItems()

	

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end
	
	ability01 = npcBot:GetAbilityByName( "ability_thdots_byakuren01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_byakuren02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_byakuren03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_byakuren05" )

	cast03Desire, cast03Target = ConsiderAbilityByakuren03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target )
		return
	end

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	cast04Desire, cast04Target = ConsiderAbilityByakuren04()

	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target )
		return
	end

	cast01Desire, cast01Target = ConsiderAbilityByakuren01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target )
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityByakuren02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastAbilityOnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityByakuren01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = ability01:GetCastRange()

	-- Fighting or Retreating 
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		-- Use ability before being catched ( Near By has enemy heros )
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and not IsPossibleIllusion(npcEnemy) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityByakuren02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( npcBot:GetMana() < npcBot:GetMaxMana()*0.5 or not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = ability02:GetCastRange()

	-- Fighting or Retreating 
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		-- Use ability before being catched ( Near By has enemy heros )
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and not IsPossibleIllusion(npcEnemy) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityByakuren03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = ability03:GetCastRange()
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
	if #tableNearbyEnemyHeroes > 0 then return BOT_ACTION_DESIRE_NONE, nil end
		
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, false, BOT_MODE_NONE )
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( npcFriend ~= nil and 
			npcFriend:GetActiveMode() == BOT_MODE_RETREAT and
			GetUnitToUnitDistanceSqr(npcBot, npcFriend) > 400*400 and
			not npcFriend:WasRecentlyDamagedByAnyHero( 5.0 ) ) 
		then
			return BOT_ACTION_DESIRE_MODERATE, npcFriend
		end
	end
	
	local tableNearbyEnemyHeroes2 = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( IsTeleporting(npcEnemy) or IsMagicBlocking(npcEnemy) ) 
		then
			return BOT_ACTION_DESIRE_MODERATE, npcEnemy
		end
	end
	
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityByakuren04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nCastRange = ability04:GetCastRange()

	-- Fighting or Retreating 
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		-- Use ability before being catched ( Near By has enemy heros )
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and not IsPossibleIllusion(npcEnemy) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end
