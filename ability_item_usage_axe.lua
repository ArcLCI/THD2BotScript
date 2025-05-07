
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
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_cirno01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_cirno02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_cirno03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_cirno04" )

	-- Consider using each ability
	cast02Desire = ConsiderAbilityCirno02()
	
	cast01Desire = ConsiderAbilityCirno01()
	if ( cast01Desire > 0 ) 
	then
		if ( cast02Desire > 0 ) 
		then
			npcBot:ActionPush_UseAbility( ability02)
			npcBot:ActionPush_Delay(0.1)
			npcBot:ActionPush_UseAbility( ability01)
		else
			npcBot:Action_UseAbility( ability01)
		end
		return
	end

	
	cast03Desire, cast03Location = ConsiderAbilityCirno03()
	if ( cast03Desire > 0 ) 
	then
		if ( cast02Desire > 0 ) 
		then
			npcBot:ActionPush_UseAbility( ability02)
			npcBot:ActionPush_Delay(0.2)
			npcBot:ActionPush_UseAbilityOnLocation( ability03, cast03Location )
		else
			npcBot:Action_UseAbilityOnLocation( ability03, cast03Location )
		end
		return
	end

	
	cast04Desire = ConsiderAbilityCirno04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:ActionQueue_UseAbility( ability04)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastCirno01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastCirno02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastCirno03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastCirno04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityCirno01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 400, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil ) 
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end
	
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityCirno02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end

	return BOT_ACTION_DESIRE_HIGH
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityCirno03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = 800
	local nRadius = 100
	local nDamage = ability03:GetAbilityDamage()
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange-50, nRadius, 0, 0 )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_MODERATE, locationAoE.targetloc
		end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange-50 , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastCirno03OnTarget( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityCirno04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
	-- Get some of its values
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 800, false, BOT_MODE_NONE )

		if #tableNearbyEnemyHeroes > 0 and 
		(#tableNearbyEnemyHeroes <= #tableNearbyFriendlyHeroes + 1 or
		#tableNearbyFriendlyHeroes >2) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

