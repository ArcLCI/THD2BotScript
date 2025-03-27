
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------

cast01Desire = 0;
cast02Desire = 0;
cast03Desire = 0;
cast04Desire = 0;

tmp = 0;

function MyItemUsageThink()

	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;

	local item_root = IsItemAvailable( "item_tentacle" )

	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget );
			return;
		end
	end

end

----------------------------------------------------------------------------------------------------
local abilities = {}
local ConsiderAbilityPatchouli = {}
----------------------------------------------------------------------------------------------------
 --1 is no target, 2 is unit target, 3 is point target(aoe), 4 is special(extra function to consider)
local const_ability_types = {
	[1]=1, [2]=1, [3]=1, [4]=1, [5]=1,
	[11]=1, [12]=2, [13]=3, [14]=4, [15]=3,
	[22]=3, [23]=4, [24]=3, [25]=3,
	[33]=4, [34]=4, [35]=2,
	[44]=2, [45]=3,
	[55]=3,
}
--ability plans
local const_ability_groups = {
	--if not in range, prepare
	[1]={3,3,33, 99},
	--multi enemy
	[2]={2,2,22, 1,5,15, 2,4,24, 5,5,55, 3,35, 2,23, 1,12, 3,13, 4,34, 4,44, 5,45, 2,25, 4,1,14, 1,11  },
	--single enemy
	[3]={2,2,22, 1,5,15, 2,4,24, 5,5,55, 3,35, 2,23, 1,12, 3,13, 4,34, 4,44, 5,45, 2,25, 4,1,14, 1,11  },
	[4]={},
	[5]={},
	[6]={}
}
local temp_ability_queue = {}
----------------------------------------------------------------------------------------------------

local elemCounts = {0,0,0,0,0,0,0,0}

function AddElem( elemId )
	local npcBot = GetBot();
	local ability = abilities[elemId];

	if not ability:IsFullyCastable() or npcBot:IsSilenced() then
		return false
	end

	npcBot:Action_UseAbility(ability);
	for i=1,5 do
		if i==elemId then
			elemCounts[i] = elemCounts[i]+1;
		else
			elemCounts[i] = elemCounts[i]-1;
			if elemCounts[i] < 0 then
				elemCounts[i] = 0;
			end
		end
	end

	return true
end

function ConsiderElement()
	local npcBot = GetBot();
	if npcBot:GetActiveMode() == BOT_MODE_LANING then
		if (npcBot:GetHealth() * 0.85) < (npcBot:GetMaxHealth() * 1.0) then
			if elemCounts[3] < 2 then
				AddElem(3);
			end
		elseif (npcBot:GetMana() * 0.85) < (npcBot:GetMaxMana() * 1.0) then
			if elemCounts[2] < 2 then
				AddElem(2);
			end
		elseif elemCounts[1] < 2 then
			AddElem(1);
		end
	elseif (npcBot:GetHealth() * 0.85) < (npcBot:GetMaxHealth() * 1.0) then
		if elemCounts[3] < 2 then
			AddElem(3);
		end
	elseif (npcBot:GetMana() * 0.6) < (npcBot:GetMaxMana() * 1.0) then
		if elemCounts[2] < 2 then
			AddElem(2);
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

	abilities[1] = hero:FindAbilityByName("ability_thdots_patchouli_fire")
	abilities[2] = hero:FindAbilityByName("ability_thdots_patchouli_water")
	abilities[3] = hero:FindAbilityByName("ability_thdots_patchouli_wood")
	abilities[4] = hero:FindAbilityByName("ability_thdots_patchouli_metal")
	abilities[5] = hero:FindAbilityByName("ability_thdots_patchouli_earth")

	abilities[11] = hero:FindAbilityByName("ability_thdots_patchouli_fire_fire")
	abilities[12] = hero:FindAbilityByName("ability_thdots_patchouli_fire_water")
	abilities[13] = hero:FindAbilityByName("ability_thdots_patchouli_fire_wood")
	abilities[14] = hero:FindAbilityByName("ability_thdots_patchouli_fire_metal")
	abilities[15] = hero:FindAbilityByName("ability_thdots_patchouli_fire_earth")
	abilities[22] = hero:FindAbilityByName("ability_thdots_patchouli_water_water")
	abilities[23] = hero:FindAbilityByName("ability_thdots_patchouli_water_wood")
	abilities[24] = hero:FindAbilityByName("ability_thdots_patchouli_water_metal")
	abilities[25] = hero:FindAbilityByName("ability_thdots_patchouli_water_earth")
	abilities[33] = hero:FindAbilityByName("ability_thdots_patchouli_wood_wood")
	abilities[34] = hero:FindAbilityByName("ability_thdots_patchouli_wood_metal")
	abilities[35] = hero:FindAbilityByName("ability_thdots_patchouli_wood_earth")
	abilities[44] = hero:FindAbilityByName("ability_thdots_patchouli_metal_metal")
	abilities[45] = hero:FindAbilityByName("ability_thdots_patchouli_metal_earth")
	abilities[55] = hero:FindAbilityByName("ability_thdots_patchouli_earth_earth")

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityPatchouli01();
	cast02Desire, cast02Location = ConsiderAbilityPatchouli02();
	cast03Desire, cast03Target = ConsiderAbilityPatchouli03();
	cast04Desire, cast04Target = ConsiderAbilityPatchouli04();

	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target);
	end

	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location );
		return;
	end

	if ( cast03Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target);
		return;
	end

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target);
		return;
	end

end

--fire fire
function CanCastPatchouli01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--fire water
function CanCastPatchouli02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--fire wood
function CanCastPatchouli03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--fire metal
function CanCastPatchouli04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--fire earth
function CanCastPatchouli05OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--water water
function CanCastPatchouli06OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--water wood
function CanCastPatchouli07OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--water metal
function CanCastPatchouli08OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--water earth
function CanCastPatchouli09OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--wood wood
function CanCastPatchouli10OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--wood metal
function CanCastPatchouli11OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--wood earth
function CanCastPatchouli12OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--metal metal
function CanCastPatchouli13OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--metal earth
function CanCastPatchouli14OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

--earth earth
function CanCastPatchouli15OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

----------------------------------------------------------------------------------------------------

--fire creep
ConsiderAbilityPatchouli[11] = function( ability )

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil;
	end;

	local nCastRange = ability:GetCastRange();

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastPatchouli01OnTarget( npcEnemy ) )
		then
			return BOT_ACTION_DESIRE_MODERATE, npcEnemy;
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityPatchouli02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0;
	end;

	-- Get some of its values
	local nRadius = ability02:GetSpecialValueInt( "radius" );
	local nCastRange = ability02:GetCastRange();
	local nDamage = ability02:GetAbilityDamage();

	--------------------------------------
	-- Mode based usage
	--------------------------------------

	-- If we're farming and can kill 3+ creeps with LSA
	if ( npcBot:GetActiveMode() == BOT_MODE_FARM ) then
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, nDamage );

		if ( #locationAoE >= 3 ) then
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
		local locationAoE = CachedFindAoELocation( npcBot, 2, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 );

		if ( #locationAoE >= 4 )
		then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc;
		end
	end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius + 200, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastPatchouli02OnTarget( npcEnemy )  )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation();
			end

			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
			then
				if ( CanCastPatchouli02OnTarget( npcEnemy ) )
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
			if ( CanCastPatchouli02OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation();
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0;
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityPatchouli03()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil;
	end;

	-- Get some of its values
	local nCastRange = ability03:GetCastRange();

	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE );
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE );

	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastPatchouli03OnTarget( npcFriend ) and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
			return BOT_ACTION_DESIRE_HIGH, npcFriend;
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil;

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityPatchouli04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil;
	end;

	-- Get some of its values
	local nCastRange = ability04:GetCastRange();

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+100, true, BOT_MODE_NONE );
		local mxcap=0;
		local mxTarget=nil;
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastPatchouli04OnTarget( npcEnemy ) )
			then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end

	if #tableNearbyEnemyHeroes > 2 then
		return BOT_ACTION_DESIRE_MODERATE, mxTarget;
	end

	if #tableNearbyEnemyHeroes > 0 and (
			npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and(
				(npcBot:GetActiveMode() == BOT_MODE_ATTACK and #tableNearbyEnemyHeroes > 1) or
				npcBot:GetActiveMode() == BOT_MODE_RETREAT
			)
		) then
		return BOT_ACTION_DESIRE_MODERATE, mxTarget;
	end


	return BOT_ACTION_DESIRE_NONE,nil;

end

