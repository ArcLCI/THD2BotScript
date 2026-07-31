
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
castExDesire = 0
cast04Desire = 0


function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" )
	local item_stun = IsItemAvailable( "item_yuetufensuijvren" )
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
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_meirin01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_meirin02" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_meirinex" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_meirin04_fix" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityMeirin01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location)
		return
	end

	cast02Desire = ConsiderAbilityMeirin02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02)
		return
	end

	castExDesire = ConsiderAbilityMeirinEx()
	if ( castExDesire > 0 ) 
	then
		npcBot:Action_UseAbility( abilityEx)
		return
	end

	cast04Desire, cast04Location = ConsiderAbilityMeirin04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastMeirin01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastMeirin02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end

function CanCastMeirinExOnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastMeirin04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMeirin01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() or IsYugi04NoDisplacementActive(npcBot) )
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Get some of its values
	local nRadius = 125
	local nCastRange = 800
	local nDamage = ability01:GetLevel() * 70
	--attack mode
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastMeirin01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end
	end
	-- Can kill enemy hero
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastMeirin01OnTarget( npcEnemy ) and nDamage > npcEnemy:GetHealth() and not IsPossibleIllusion( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end
		if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK and 
		GetUnitToLocationDistance(npcBot:GetTarget(),GetShopLocation(npcBot:GetTeam(),SHOP_HOME))<
		GetUnitToLocationDistance(npcBot,GetShopLocation(npcBot:GetTeam(),SHOP_HOME))) or
			SafeHasModifier(npcEnemy, "modifier_imba_puck_dream_coil"))
		then 
			local v = npcBot:GetLocation() + 10*(npcEnemy:GetLocation()-npcBot:GetLocation())
			return BOT_ACTION_DESIRE_HIGH, v
		end
	end
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
	then
		local npcTarget = npcBot:GetTarget()
		if ( npcTarget ~= nil ) 
		then
			if (CanCastMeirin01OnTarget(npcTarget) and GetUnitToUnitDistance(npcBot,npcTarget)>800)
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	if (IsSeriouslyRetreating(npcBot, 'ability_thdots_meirin01') and
	npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
		return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMeirin02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting or Retreating with hero
	if ( IsRetreating(npcBot, 'ability_thdots_meirin02') or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1500, true, BOT_MODE_NONE )
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

function ConsiderAbilityMeirinEx()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting or Retreating with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 180, true, BOT_MODE_NONE )
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

function ConsiderAbilityMeirin04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = ability04:GetCastRange()
	local nRadius = 500
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius-100, 0, 0 )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
		--[[
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMeirin04OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
		--]]
	return BOT_ACTION_DESIRE_NONE, 0
end

