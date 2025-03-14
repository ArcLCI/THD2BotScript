
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

	item_ghost = IsItemAvailable( "item_ghost_balloon" )
	item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	
	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemGhostDesire = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_ghost );
			return;
		end
	end

	if ( item_weijin~=nil and item_weijin:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemWeijinDesire = ConsiderItemWeiJin(item_weijin)
		if ( castItemWeijinDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_weijin );
			return;
		end
	end

end

function AbilityUsageThink()

	if not IsBotAwake() then return end
	
	MyItemUsageThink();
	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end;

	ability01 = npcBot:GetAbilityByName( "ability_thdots_rumia01" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_rumia04" );

	-- Consider using each ability
	cast01Desire = ConsiderAbilityRumia01();
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01 );
		return;
	end

	cast04Desire, cast04Target = ConsiderAbilityRumia04();

	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target );
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastRumia04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityRumia01()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE;
	end;

	-- Fighting or Retreating 
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		-- Use ability before being catched ( Near By has enemy heros )
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1500, true, BOT_MODE_NONE );
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

----------------------------------------------------------------------------------------------------

function ConsiderAbilityRumia04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil;
	end;

	-- Get some of its values
	local nCastRange = ability04:GetCastRange();
	local nDamage = ability04:GetAbilityDamage();

	-- Can eat enemy hero
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100 , true, BOT_MODE_NONE );
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastRumia04OnTarget( npcEnemy ) and nDamage > npcEnemy:GetHealth() ) 
		then
			return BOT_ACTION_DESIRE_MODERATE, npcEnemy;
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil;

end

