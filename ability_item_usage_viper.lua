
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0

tmp = 0

function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_root = IsItemAvailable( "item_tentacle" )
	
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then 
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_medicine01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_medicine02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_medicine03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_medicine04" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityMedicine01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire, cast02Location = ConsiderAbilityMedicine02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end

	cast03Desire, cast03Target = ConsiderAbilityMedicine03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityMedicine04()
	
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastMedicine01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastMedicine02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastMedicine03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and ( GetBot():HasScepter() or not npcTarget:IsMagicImmune() ) and not npcTarget:IsInvulnerable()
end

function CanCastMedicine04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMedicine01()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = ability01:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMedicine01OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMedicine02()

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

function ConsiderAbilityMedicine03()

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
	local nModifier = npcBot:GetModifierByName("modifier_ability_thdots_ellen04_debuff")
	
	if HasSpecificEnemyHero("npc_dota_hero_arc_warden") then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if (npcFriend:GetModifierStackCount(nModifier) >= 5 and npcFriend:GetModifierRemainingDuration(nModifier) <= 0.6) or
			(npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.28 and IsUnderAttack(npcFriend))
			then
				return BOT_ACTION_DESIRE_HIGH, npcFriend
			end
		end
	else
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( CanCastMedicine03OnTarget( npcFriend ) and 
					((npcFriend:GetModifierStackCount(nModifier) >= 5 and npcFriend:GetModifierRemainingDuration(nModifier) <= 1.2) or
					GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
					npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
					IsUnderAttack(npcFriend)
					)
				) then
				return BOT_ACTION_DESIRE_HIGH, npcFriend
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMedicine04()

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
			if ( CanCastMedicine04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
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

