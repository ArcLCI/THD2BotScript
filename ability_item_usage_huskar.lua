
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
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then 
		castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget);
			return;
		end
	end
	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then 
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget);
			return;
		end
	end
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then 
		castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 or cast04Desire > 0) 
		then
			npcBot:Action_UseAbility( item_speed );
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_minoriko01" );
	ability02 = npcBot:GetAbilityByName( "ability_thdots_minoriko02" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_minoriko04" );

	-- Consider using each ability

	cast01Desire, cast01Target = ConsiderAbilityMinoriko01();
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target);
		return;
	end

	cast02Desire, cast02Location = ConsiderAbilityMinoriko02();
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location );
		return;
	end
	
	cast04Desire, cast04Target = ConsiderAbilityMinoriko04();
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target);
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastMinoriko01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastMinoriko04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMinoriko01()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil;
	end;
	
	local nCastRange = 650
	if npcBot:GetLevel() >= 25 then
		nCastRange = 950
	end
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE );
	if #tableNearbyFriendlyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.5 
				and ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend ,true)
				) then
				return BOT_ACTION_DESIRE_HIGH, npcFriend;
			end
			if npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.3 then
				return BOT_ACTION_DESIRE_HIGH, npcFriend;
			end
		end
	end
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE );
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and not IsPossibleIllusion( npcEnemy )) 
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy;
		end
		
		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) and not IsPossibleIllusion( npcEnemy )) 
		then
			return BOT_ACTION_DESIRE_MODERATE, npcEnemy;
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil;
	
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMinoriko02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0;
	end;
	local nCastRange = 500
	if npcBot:GetLevel() >= 25 then
		nCastRange = 800
	end
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE );
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if (npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.5 or npcFriend:GetMana() < npcFriend:GetMaxMana()*0.5) 
		and not npcFriend:HasModifier("modifier_fountain_aura_buff") then
			return BOT_ACTION_DESIRE_HIGH, npcFriend:GetLocation();
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0;
end

----------------------------------------------------------------------------------------------------
function ConsiderAbilityMinoriko04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil;
	end;
	
	local nCastRange = 600
	if npcBot:GetLevel() >= 25 then
		nCastRange = 900
	end
	local nRadius = 600
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE );
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcFriend, nRadius-100 , true, BOT_MODE_NONE );
		if #tableNearbyEnemyHeroes > 2 and CanCastMinoriko04OnTarget(npcFriend) then
			return BOT_ACTION_DESIRE_HIGH, npcFriend;
		end
	end
	
	local tableNearbyEnemyHeroes2 = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE );
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes2 )
	do
		local tableNearbyFriendlyHeroes2 = CachedGetNearbyHeroes( npcEnemy, nRadius-100, false, BOT_MODE_NONE );
		if #tableNearbyFriendlyHeroes2 > 2 and CanCastMinoriko04OnTarget(npcEnemy) then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy;
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil;
end
