
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
	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	local item_root = IsItemAvailable( "item_morenjingjuan" )
	if item_root == nil then
		item_root = IsItemAvailable( "item_tentacle" )
	end

	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then
		castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget);
			return;
		end
	end
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget );
			return;
		end
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

--大推逻辑
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
	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end;

	ability02 = npcBot:GetAbilityByName( "centaur_hoof_stomp" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_yugi04" );

	-- Consider using each ability
	cast02Desire = ConsiderAbilityYugi02();
	if ( cast02Desire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbility( ability02 );
		return;
	end

	cast02JumpDesire, cast02JumpLoc = ConsiderAbilityYugi02WithJump(item_jump);
	if ( cast02JumpDesire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbilityOnLocation(item_jump,cast02JumpLoc)
		npcBot:ActionQueue_UseAbility( ability02 );
		return;
	end

	cast04Desire, cast04Target = ConsiderAbilityYugi04();

	if ( cast04Desire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbilityOnEntity( ability04 , cast04Target );
		return;
	end

	cast04JumpDesire, cast04JumpTarget, cast04JumpLoc = ConsiderAbilityYugi04WithJump(item_jump);
	if ( cast04JumpDesire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbilityOnLocation(item_jump,cast04JumpLoc)
		npcBot:ActionQueue_UseAbilityOnEntity(ability04, cast04JumpTarget)
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
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 290, true, BOT_MODE_NONE );
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

function ConsiderAbilityYugi02WithJump(item_jump)

	local npcBot = GetBot();

	if (not ability02:IsFullyCastable() and not item_jump:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, nil;
	end
	
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
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
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 270, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil)
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy;
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil;

end

function ConsiderAbilityYugi04WithJump(item_jump)

	local npcBot = GetBot();

	-- Make sure it's castable
	if (ability02:IsFullyCastable() or (not ability04:IsFullyCastable() and not item_jump:IsFullyCastable()))
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil;
	end;

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil)
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy,  npcEnemy:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil;

end

