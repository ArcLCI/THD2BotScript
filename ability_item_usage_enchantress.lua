
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
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_youmu2_01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_youmu2_02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_youmu2_03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_youmu2_04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityYoumu201()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location)
		return
	end

	cast02Desire = ConsiderAbilityYoumu202()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02)
		return
	end

	cast03Desire = ConsiderAbilityYoumu203()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03 )
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityYoumu204()
	
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastYoumu201OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastYoumu202OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastYoumu203OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastYoumu204OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumu201()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Get some of its values
	local nRadius = 300
	local nCastRange = 900
	local nDamage = 100 + ability01:GetLevel() * 50
	--attack mode
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastYoumu201OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end
	end
	-- Can kill enemy hero
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( nDamage > npcEnemy:GetHealth() ) 
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
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
			if (CanCastYoumu201OnTarget(npcTarget) and GetUnitToUnitDistance(npcBot,npcTarget)>800)
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and 
	npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
		return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumu202()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	if npcBot:GetLevel() < 6
	then
		return BOT_ACTION_DESIRE_NONE
	end
	
	if IsUnderAttack(npcBot,true) then
		return BOT_ACTION_DESIRE_HIGH
	end
	
	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumu203()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end

	-- Get some of its values
	local nCastRange = 300

	local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes(nCastRange, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil ) 
		then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumu204()


	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 300
	if npcBot:GetLevel() >= 30
	then
		nCastRange = 1300
	end
	
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) 
	then	
		local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes(nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (CanCastYoumu204OnTarget( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end


