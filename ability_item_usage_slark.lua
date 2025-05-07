
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

	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	
	if ( item_stun~=nil and item_stun:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemStunDesire, castItemStunTarget = ConsiderItemStun(item_stun)
		if ( castItemStunDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_stun, castItemStunTarget )
			return
		end
	end

end

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_aya01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_aya02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_aya04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityAya01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityAya02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target)
		return
	end

	cast04Desire = ConsiderAbilityAya04()

	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastAya01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsInvulnerable()
end

function CanCastAya02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastAya04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsInvulnerable()
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityAya01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Get some of its values
	local nLevel = ability01:GetLevel()
	local nRadius = ability01:GetSpecialValueInt( "radius" )
	local nCastRange = ( nLevel + 1 )*300 
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

	-- If we're seriously attacking
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH ) 
	then
	
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastAya01OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityAya04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, or attack
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) 
	then
		return BOT_ACTION_DESIRE_MODERATE
	end

	-- If we're seriously retreating, or attack
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH ) 
	then
		return BOT_ACTION_DESIRE_MODERATE
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
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityAya02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability02:GetCastRange()

	-- If we're seriously attacking
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastAya02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) then
				if ( not npcEnemy:HasModifier("modifier_thdots_aya02_buff") ) 
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy
				else 
					local mf_index = npcEnemy:GetModifierByName("modifier_thdots_aya02_buff")
					if( npcEnemy:GetModifierRemainingDuration(mf_index) < 4.0 ) then
						return BOT_ACTION_DESIRE_MODERATE, npcEnemy
					end
				end
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
			if ( CanCastAya02OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH,npcTarget
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

