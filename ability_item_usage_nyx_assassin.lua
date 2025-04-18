
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

	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_king = IsItemAvailable( "item_horse_king")

	if ( item_horse_red~=nil and item_horse_red:IsFullyCastable() )
	then
		local castItemHorseRedDesire = ConsiderItemHorseRed(item_horse_red)
		if ( castItemHorseRedDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_red )
			return
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then
		local castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_king )
			return
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_daiyousei01" );
	ability02 = npcBot:GetAbilityInSlot(1);
	-- ability02 = npcBot:GetAbilityByName( "ability_thdots_daiyousei02" );
	ability03 = npcBot:GetAbilityByName( "ability_thdots_daiyousei03" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_daiyousei04" );

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityDaiyousei01();
	if ( cast01Desire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbilityOnEntity( ability01 , cast01Target)
		npcBot:ActionQueue_AttackUnit(cast01Target, true)
		return;
	end

	cast02Desire = ConsiderAbilityDaiyousei02();
	if ( cast02Desire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbility( ability02 );
		return;
	end

	cast03Desire, cast03Target = ConsiderAbilityDaiyousei03();
	if ( cast03Desire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbilityOnEntity( ability03, cast03Target);
		return;
	end

	cast04Desire = ConsiderAbilityDaiyousei04();

	if ( cast04Desire > 0 )
	then
		npcBot:Action_ClearActions(false)
		npcBot:ActionQueue_UseAbility( ability04);
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastDaiyousei01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastDaiyousei02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastDaiyousei03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastDaiyousei04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityDaiyousei01()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil;
	end;

	local nCastRange = ability01:GetCastRange();
	local tableNearbyTrees = npcBot:GetNearbyTrees ( nCastRange )
	local dis = 0
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK ) then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget()==npcEnemy and CanCastDaiyousei01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy;
			end
		end
		if npcBot:GetTarget() ~= nil then
			local dismin = GetUnitToUnitDistance( npcBot, npcBot:GetTarget())
			local treeid = 0
			for _,tree in pairs( tableNearbyTrees )
			do
				dis = GetUnitToLocationDistance( npcBot:GetTarget(),GetTreeLocation( tree ))
				if dis < dismin then
					dismin = dis
					treeid = tree
				end
			end
			if treeid ~= 0 then
				npcBot:Action_ClearActions(false)
				npcBot:ActionQueue_UseAbilityOnTree( ability01, treeid )
				return BOT_ACTION_DESIRE_NONE, nil
			end
		end
	end
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT) then
		local dismin = npcBot:DistanceFromFountain()
		local opfriendhero = 0
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE );
		--排除只有自己的情况 否则就会仰望星空
		if #tableNearbyFriendlyHeroes > 1 then
			for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
			do
				if npcFriend:DistanceFromFountain() < dismin then
					opfriendhero = npcFriend
				end
			end
			if opfriendhero ~= 0 then
				return BOT_ACTION_DESIRE_HIGH,opfriendhero;
			end
		end
		dismin = npcBot:DistanceFromFountain()
		local treeid = 0
		for _,tree in pairs( tableNearbyTrees )
		do
			local v = GetTreeLocation( tree ) - GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
			dis = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
			if dis < dismin then
				dismax = dis
				treeid = tree
			end
		end
		if treeid ~= 0 then
			npcBot:Action_ClearActions(false)
			npcBot:ActionQueue_UseAbilityOnTree( ability01, treeid )
			return BOT_ACTION_DESIRE_NONE, nil
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityDaiyousei02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;


	local nCastRange = ability02:GetCastRange();

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange - 50, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastDaiyousei02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH;
			end
		end

	return BOT_ACTION_DESIRE_NONE;
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityDaiyousei03()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil;
	end;

	if (npcBot:GetLevel() >= 20) then
		for _,npcFriend in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
		do
			if ( npcFriend~=nil )
			then
			if ( npcFriend:IsAlive())
			then
			if ( CanCastDaiyousei03OnTarget( npcFriend ) and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
				return BOT_ACTION_DESIRE_HIGH, npcFriend;
			end
			end
			end
		end
	else
		-- Get some of its values
		local nCastRange = ability03:GetCastRange();
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE );
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( CanCastDaiyousei03OnTarget( npcFriend ) and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
				return BOT_ACTION_DESIRE_HIGH, npcFriend;
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityDaiyousei04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end;


	local nCastRange = ability04:GetCastRange();

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastDaiyousei04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH;
			end
		end

	return BOT_ACTION_DESIRE_NONE;
end

