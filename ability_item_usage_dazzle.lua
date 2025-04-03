
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0;
cast02Desire = 0;
cast03Desire = 0;
cast04Desire = 0;


function MyItemUsageThink()
	
	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;
	
	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )					
	local item_moon_bow  = IsItemAvailable( "item_moon_bow" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	
	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then 
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget );
			return;
		end
	end
	
	if ( item_moon_bow~=nil and item_moon_bow:IsFullyCastable() )
	then 
		castItemMoonBowDesire, castItemMoonBowTarget = ConsiderItemMoonBow( item_moon_bow  )
		if ( castItemMoonBowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_moon_bow , castItemMoonBowTarget);
			return;
		end
	end
	if ( item_horse_green~=nil and item_horse_green:IsFullyCastable() )
	then 
		castItemHorseGreenDesire = ConsiderItemHorseGreen(item_horse_green)
		if ( castItemHorseGreenDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_green );
			return;
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then 
		castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_king );
			return;
		end
	end
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink();
	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end;

	ability01 = npcBot:GetAbilityByName( "ability_thdots_lunasa01" );
	ability02 = npcBot:GetAbilityByName( "ability_thdots_lunasa02" );
	ability03 = npcBot:GetAbilityByName( "ability_thdots_lunasa03" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_lunasa04" );

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityLunasa01();
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location);
		return;
	end

	cast04Desire, cast04Target = ConsiderAbilityLunasa04();
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target );
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastLunasa01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastLunasa04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLunasa01()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0;
	end;
	
	local nCastRange = ability01:GetCastRange();

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastLunasa01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation();
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, 0;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLunasa04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil;
	end;
	
	local nCastRange = ability04:GetCastRange();

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastLunasa04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy;
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, nil;
end

