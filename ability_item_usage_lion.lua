
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

function MyItemUsageThink()

	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;

	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )

	local item_yukkuri_stick = IsItemAvailable( "item_yukkuri_stick" )

	--红魔火箭判定
	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget );
			return;
		end
	end

	--油库里杖判定
	if ( item_yukkuri_stick~=nil and item_yukkuri_stick:IsFullyCastable() )
	then
		castItemYukkuriStickDesire, castItemYukkuriStickTarget = ConsiderItemYukkuriStick( item_yukkuri_stick )
		if ( castItemYukkuriStickDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_yukkuri_stick, castItemYukkuriStickTarget );
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_sanae01" );
	ability02 = npcBot:GetAbilityByName( "ability_thdots_sanae02" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_sanae04" );

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilitySanae( ability01 );
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location );
		return;
	end

	cast02Desire, cast02Location = ConsiderAbilitySanae( ability02 );
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location );
		return;
	end

	cast04Desire = ConsiderAbilitySanae04();

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04 );
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastSanae01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastSanae04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySanae( abilityX )

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not abilityX:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0;
	end;

	-- Get some of its values
	local nRadius = abilityX:GetSpecialValueInt( "radius" );
	local nCastRange = abilityX:GetCastRange();
	local nDamage = abilityX:GetAbilityDamage();

	--------------------------------------
	-- Mode based usage
	--------------------------------------

	-- If we're farming and can kill 3+ creeps with LSA
	if ( npcBot:GetActiveMode() == BOT_MODE_FARM ) then
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, nDamage );

		if ( locationAoE.count >= 3 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc;
		end
	end

	-- If we're pushing or defending a lane and can hit 4+ creeps, go for it
	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOTTOM or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOTTOM )
	then
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 );

		if ( locationAoE.count >= 4 )
		then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc;
		end
	end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius + 200, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastSanae01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation();
			end

			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ))
			then
				if ( CanCastSanae01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation();
				end
			end
		end

	-- If we're going after someone
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY )
	then
		local npcTarget = npcBot:GetTarget();

		if ( npcTarget ~= nil )
		then
			if ( CanCastSanae01OnTarget( npcTarget ) and not IsPossibleIllusion( npcTarget ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation();
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySanae04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 900, true, BOT_MODE_NONE );
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 550, false, BOT_MODE_NONE );

	if #tableNearbyEnemyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.3 and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend )
				)
				) then
				return BOT_ACTION_DESIRE_HIGH;
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE;

end

