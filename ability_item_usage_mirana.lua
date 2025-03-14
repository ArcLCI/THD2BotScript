
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

function MyItemUsageThink()

	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;

	local item_travel_boots = IsItemAvailable( "item_travel_boots" )

	if ( item_travel_boots~=nil and item_travel_boots:IsFullyCastable() )
	then
		CastItemTravelBootsDesire = ConsiderItemTravelBoots(item_travel_boots)
		if ( CastItemTravelBootsDesire > 0 )
		then
			return;
		end
	end

end

----------------------------------------------------------------------------------------------------

cast01Desire = 0;
cast02Desire = 0;
cast03Desire = 0;
cast04Desire = 0;

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink();
	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end;

	--ability01 = npcBot:GetAbilityByName( "ability_thdots_reisenOld01" );
	ability02 = npcBot:GetAbilityByName( "ability_thdots_reisenOld02" );
	ability03 = npcBot:GetAbilityByName( "ability_thdots_reisenOld03" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_reisenOld04" );

	-- Consider using each ability
	cast02Desire = ConsiderAbilityReisen02();
	if ( cast02Desire > 0 and not npcBot:IsChanneling() )
	then
		npcBot:Action_UseAbility( ability02 );
		return;
	end

	cast03Desire, cast03Location = ConsiderAbilityReisen03();
	if ( cast03Desire > 0 and not npcBot:IsChanneling() )
	then
		npcBot:Action_UseAbilityOnLocation( ability03, cast03Location);
		return;
	end

	cast04Desire = ConsiderAbilityReisen04();

	if ( cast04Desire > 0 and not npcBot:IsChanneling() )
	then
		npcBot:Action_UseAbility( ability04 );
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastReisen03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityReisen02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;
	-- as bot has mana buff and could multi controll perfectly
	-- bot should just use this as much as possible
	return BOT_ACTION_DESIRE_HIGH;
end

function ConsiderAbilityReisen03()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0;
	end;

	local nCastRange = ability03:GetCastRange();

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastReisen03OnTarget( npcEnemy ) )
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation();
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0;
end

function ConsiderAbilityReisen04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE ); -- attack range is better, wait for api :p
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_MODERATE;
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE;

end

