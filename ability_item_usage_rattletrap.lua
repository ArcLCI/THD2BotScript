
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
cast05Desire = 0

function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	
	local item_xinyan = IsItemAvailable( "item_third_eyes" )
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
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_sunny01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_sunny02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_sunny03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_sunny04" )
	
	-- Consider using each ability
	cast01Desire = ConsiderAbilitySunny01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01 )
		return
	end

	cast02Desire = ConsiderAbilitySunny02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02 )
		return
	end

	cast03Desire, cast03Target = ConsiderAbilitySunny03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03, cast03Target )
		return
	end

	cast04Desire = ConsiderAbilitySunny04()
	
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end
	
	if npcBot:HasScepter()
	then
		ability05 = npcBot:GetAbilityByName( "ability_thdots_sunny05" )
		cast05Desire, cast05Target = ConsiderAbilitySunny05()
		if ( cast05Desire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( ability05, cast05Target )
		end
		return
	end


end

----------------------------------------------------------------------------------------------------

function CanCastSunny01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSunny02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSunny03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSunny04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSunny05OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySunny01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	local target = npcBot:GetTarget()
	if target ~= nil then
		if ( not target:IsHero() ) then
		return BOT_ACTION_DESIRE_NONE
		end
	end
	return BOT_ACTION_DESIRE_HIGH
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySunny02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local nCastRange = ability02:GetCastRange()

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastSunny02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end

	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilitySunny03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local tableNearbyTowers = npcBot:GetNearbyTowers(800,true)
	if (npcBot:HasModifier("modifier_invisible")) then
		if ((ability02:IsFullyCastable() or ability02:GetCooldownTimeRemaining()<=3) and 
		#tableNearbyTowers == 0) then		
		return BOT_ACTION_DESIRE_NONE, nil
	end
	end
	local nCastRange = ability03:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastSunny03OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySunny04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	

	local nCastRange = ability04:GetCastRange()

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastSunny04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) and 
			npcBot:GetActiveMode() == BOT_MODE_ATTACK and
			npcBot:GetTarget() == npcEnemy) 
			then
				return BOT_ACTION_DESIRE_HIGH
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
			if ( CanCastSunny04OnTarget( npcTarget ) and GetUnitToUnitDistance(npcBot, npcTarget) < 500)
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySunny05()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability05:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	--[[
	else
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
		local mxhealth = npcBot:GetHealth()
		local mxTarget = npcBot
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastSunny05OnTarget( npcEnemy ) ) 
			then
				local curhealth = npcEnemy:GetHealth()
				if curhealth > mxhealth then
					mxhealth = curhealth
					mxTarget = npcEnemy
				end
			end
		end
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( CanCastSunny05OnTarget( npcFriend ) ) 
			then
				local curhealth = npcFriend:GetHealth()
				if curhealth > mxhealth then
					mxhealth = curhealth
					mxTarget = npcFriend
				end
			end
		end
		return BOT_ACTION_DESIRE_HIGH,mxTarget
		
	--]]
	end
	--return BOT_ACTION_DESIRE_NONE,nil
	return BOT_ACTION_DESIRE_HIGH,npcBot
end