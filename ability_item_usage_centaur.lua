
require(GetScriptDirectory() ..  "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0

function MyItemUsageThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	local item_yuemianjidongzhuangzhi = IsItemAvailable( "item_yuemianjidongzhuangzhi" )
	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	local item_root = IsItemAvailable( "item_morenjingjuan" )
	if item_root == nil then
		item_root = IsItemAvailable( "item_tentacle" )
	end
	local item_stand = IsItemAvailable( "item_dummy_doll1" )

	if ( item_stand~=nil and item_stand:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemStandDesire = ConsiderItemStand( item_stand )
		if ( castItemStandDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_stand )
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
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
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

--大推逻辑
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil
		and item_yuemianjidongzhuangzhi~=nil
		and item_yuemianjidongzhuangzhi:IsFullyCastable()
		and npcEnemy:HasModifier( "modifier_thdots_yugi04_think_interval" ))
		then
			npcBot:Action_UseAbilityOnEntity( item_yuemianjidongzhuangzhi, npcEnemy )
			return
		end
	end

end

function AbilityUsageThink()

	if not IsBotAwake() then return end
	
	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()
	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability02 = npcBot:GetAbilityByName( "centaur_hoof_stomp" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_yugi04" )

	-- Consider using each ability
	cast02Desire = ConsiderAbilityYugi02()
	if ( cast02Desire > 0 )
	then
		J.ClearActionsThrottled(npcBot, 'yugi_cast02', false, 0.6)
		J.QueueUseAbilityThrottled(npcBot, 'yugi_queue_cast02', ability02, 0.6)
		return
	end

	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then
		cast02JumpDesire, cast02JumpLoc = ConsiderAbilityYugi02WithJump(item_jump)
		if ( cast02JumpDesire > 0 )
		then
			if not J.ClearActionsThrottled(npcBot, 'yugi_jump_cast02', false, 0.8) then return end
			J.QueueUseAbilityOnLocationThrottled(npcBot, 'yugi_queue_jump_item02', item_jump, cast02JumpLoc, 0.8, 180)
			J.QueueUseAbilityThrottled(npcBot, 'yugi_queue_jump_cast02', ability02, 0.6)
			return
		end
	end

	cast04Desire, cast04Target = ConsiderAbilityYugi04()

	if ( cast04Desire > 0 )
	then
		J.ClearActionsThrottled(npcBot, 'yugi_cast04', false, 0.6)
		J.QueueUseAbilityOnEntityThrottled(npcBot, 'yugi_queue_cast04', ability04, cast04Target, 0.6)
		return
	end

	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then
		cast04JumpDesire, cast04JumpTarget, cast04JumpLoc = ConsiderAbilityYugi04WithJump(item_jump)
		if ( cast04JumpDesire > 0 )
		then
			if not J.ClearActionsThrottled(npcBot, 'yugi_jump_cast04', false, 0.8) then return end
			J.QueueUseAbilityOnLocationThrottled(npcBot, 'yugi_queue_jump_item04', item_jump, cast04JumpLoc, 0.8, 180)
			J.QueueUseAbilityOnEntityThrottled(npcBot, 'yugi_queue_jump_cast04', ability04, cast04JumpTarget, 0.6)
			return
		end
	end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil
		and npcEnemy:HasModifier( "modifier_thdots_yugi04_think_interval" ))
		then
			J.SetTargetIfChanged(npcBot, npcEnemy, 0.8)
			return
		end
	end
end

----------------------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------------------

function ConsiderAbilityYugi02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 300, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

function ConsiderAbilityYugi02WithJump(item_jump)

	local npcBot = GetBot()

	if (not ability02:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and CanCastStunOnTarget( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

function ConsiderAbilityYugi04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 285, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and CanCastStunOnTarget( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

function ConsiderAbilityYugi04WithJump(item_jump)

	local npcBot = GetBot()

	-- Make sure it's castable
	if (ability02:IsFullyCastable() or not ability04:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil and CanCastStunOnTarget( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy,  npcEnemy:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil

end

