
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0;
cast01StopDesire = 0;
cast02Desire = 0;
cast03Desire = 0;
cast04Desire = 0;


local larva01_time = -1;
local larva01_stop_time = 2;

function MyItemUsageThink()

	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;

	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )
	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )

	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then
		castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget);
			return;
		end
	end
	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget );
			return;
		end
	end

	if ( item_morenjingjuan~=nil and item_morenjingjuan:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemMoRenDesire, castItemMoRenTarget = ConsiderItemRoot( item_morenjingjuan )
		if ( castItemMoRenDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_morenjingjuan, castItemMoRenTarget );
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

	local isfly = npcBot:HasModifier("modifier_ability_larva01_dash")

	ability01 = npcBot:GetAbilityByName("ability_thdots_larva01_1")
	ability01stop = npcBot:GetAbilityByName("ability_thdots_larva01_2")
	ability02 = npcBot:GetAbilityByName( "ability_thdots_larva02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_larva03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_larva04" )

	-- Consider using each ability


	cast01Desire, cast01Location = ConsiderAbilityLarva01();
	if ( cast01Desire > 0 )
	then
		if not isfly then
			print("is casting fly")
			npcBot:Action_UseAbilityOnLocation( ability01, cast01Location );
			larva01_time = DotaTime();
			return
		else
			return
		end
	end

	cast01StopDesire = ConsiderAbilityLarva01Stop();
	if ( cast01StopDesire > 0 and isfly ) then
		print("is stopping")
		npcBot:Action_UseAbility( ability01stop);
		return
	end

	cast02Desire = ConsiderAbilityLarva02();
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02);
		return;
	end

	cast03Desire, cast03Target = ConsiderAbilityLarva03();
	if ( cast03Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target);
		return;
	end

	cast04Desire, cast04Location = ConsiderAbilityLarva04();
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location );
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastLarva01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end


function CanCastLarva02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end


function CanCastLarva03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastLarva04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLarva01()

	local npcBot = GetBot()
	local isfly = npcBot:HasModifier("modifier_ability_larva01_dash")

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable()) or isfly
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = 1200;
	if npcBot:GetLevel() >= 15 then
		nCastRange = 2000
	end

	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetHealth() < npcBot:GetMaxHealth()*0.4) then
		if not isfly then
			print("calculating destination...")
			local v_shop = GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
			local v_target = - npcBot:GetLocation() + v_shop
			local dis = GetUnitToLocationDistance( npcBot,v_shop)
			local v_final = v_target/dis * nCastRange + npcBot:GetLocation()
			return BOT_ACTION_DESIRE_HIGH, v_final
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

function ConsiderAbilityLarva01Stop()

	local npcBot = GetBot()
	local isfly = npcBot:HasModifier("modifier_ability_larva01_dash")

	-- Make sure it's castable
	if not isfly then return BOT_ACTION_DESIRE_NONE end

	if npcBot:GetHealth() < npcBot:GetMaxHealth()*0.45 and isfly then
		if DotaTime() > (larva01_time + (larva01_stop_time / 2) + 0.2)
        then
			print("consider to stop...")
            return BOT_ACTION_DESIRE_HIGH
        end
	end
	return BOT_ACTION_DESIRE_NONE

end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLarva02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;

	-- Get some of its values
	local nRadius = 400;

	if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK
		or npcBot:GetActiveMode() == BOT_MODE_GANK
		or npcBot:GetActiveMode() == BOT_MODE_RETREAT )
		and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nRadius , true, BOT_MODE_NONE );
		if #tableNearbyEnemyHeroes > 0 then
			return BOT_ACTION_DESIRE_HIGH;
		end
	end
	return BOT_ACTION_DESIRE_NONE;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLarva03()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil;
	end;

	local nCastRange = ability03:GetLevel()*50 + 450;
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	local nModifier = npcBot:GetModifierByName("modifier_ability_thdots_ellen04_debuff")
	
	if HasSpecificEnemyHero("npc_dota_hero_arc_warden") then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( CanCastLarva03OnTarget( npcFriend ) and
				( npcFriend:GetModifierStackCount(nModifier) >= 5 and npcFriend:GetModifierRemainingDuration(nModifier) <= 0.6))
			then
				return BOT_ACTION_DESIRE_HIGH, npcFriend;
			end
		end
	else
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( CanCastLarva03OnTarget( npcFriend ) and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend,true )))
			then
				return BOT_ACTION_DESIRE_HIGH, npcFriend;
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil;

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLarva04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,0;
	end;

	local nCastRange = 400;
	local nRadius = 525;

	if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK
		or npcBot:GetActiveMode() == BOT_MODE_GANK
		or npcBot:GetActiveMode() == BOT_MODE_RETREAT )
		and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		local locationAoE = CachedFindAoELocation( npcBot, 60001, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 );
		if locationAoE.count > 1 then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc;
		end
	end
	return BOT_ACTION_DESIRE_NONE,0;

end

