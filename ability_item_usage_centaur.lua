
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

	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	local item_yuemianjidongzhuangzhi = IsItemAvailable( "item_yuemianjidongzhuangzhi" );

	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then
		castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget);
			return;
		end
	end
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
			npcBot:Action_UseAbilityOnEntity( item_stun, castItemStunTarget );
			return;
		end
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE );
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil
		and item_yuemianjidongzhuangzhi~=nil
		and item_yuemianjidongzhuangzhi:IsFullyCastable()
		and npcEnemy:HasModifier( "modifier_thdots_yugi04_think_interval" ))
		then
			npcBot:Action_UseAbilityOnEntity( item_yuemianjidongzhuangzhi, npcEnemy );
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

	ability02 = npcBot:GetAbilityByName( "centaur_hoof_stomp" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_yugi04" );

	-- Consider using each ability
	cast04Desire, cast04Target = ConsiderAbilityYugi04();

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target );
		return;
	end

	cast02Desire = ConsiderAbilityYugi02();
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02 );
		return;
	end

end

----------------------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------------------

function ConsiderAbilityYugi02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;
	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 300, true, BOT_MODE_NONE );
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

function ConsiderAbilityYugi04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil;
	end;

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 280, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy;
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil;

end

