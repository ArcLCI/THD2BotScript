
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

	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
					
	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
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
	
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then 
		castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_speed )
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

	ability02 = npcBot:GetAbilityByName( "ability_thdots_Jyoon_2" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_Jyoon_3" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_Jyoon_4" )

	-- Consider using each ability
	cast02Desire, cast02Location = ConsiderAbilityJyoon02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end

	cast03Desire = ConsiderAbilityJyoon03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03)
		return
	end

	cast04Desire = ConsiderAbilityJyoon04()
	
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastJyoon02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastJyoon04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------


function ConsiderAbilityJyoon02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,0
	end

	local nCastRange = 700
	local nRadius = 350 + 25 * ability02:GetLevel()
	
	
	if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK 
		or npcBot:GetActiveMode() == BOT_MODE_GANK
		or npcBot:GetActiveMode() == BOT_MODE_RETREAT )
		and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		local locationAoE = CachedFindAoELocation( npcBot, 60001, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )
		if locationAoE.count > 1 then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and CanCastJyoon02OnTarget( npcEnemy )  ) 
		then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end
				
		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) ) 
		then
			if ( CanCastJyoon02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
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
			if ( CanCastJyoon02OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	
	return BOT_ACTION_DESIRE_NONE,0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityJyoon03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local nRadius = 750

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes(nRadius, true, BOT_MODE_NONE )
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

function ConsiderAbilityJyoon04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local nCastRange = 200
	if (( npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_GANK) and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) 
	then	
		local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes( nCastRange , true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes > 1 then
			return BOT_ACTION_DESIRE_HIGH
		else
			for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
			do
				if (GetCapability(npcEnemy) > GetCapability(npcBot) or npcBot:GetHealth() < npcEnemy:GetHealth()) and not npcEnemy:IsAttackImmune() then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end 
	end
	return BOT_ACTION_DESIRE_NONE
end

