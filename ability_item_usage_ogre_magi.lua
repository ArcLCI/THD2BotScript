
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0;
cast02Desire = 0;
cast03Desire = 0;
castExDesire = 0;
cast04Desire = 0;


function MyItemUsageThink()
	
	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;
	
	local item_pomo = IsItemAvailable( "item_pomojinlingli" )
	local item_xinyan = IsItemAvailable( "item_third_eyes" )
	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	local item_qijizhixing = IsItemAvailable( "item_qijizhixing" ) or IsItemAvailable( "item_tuzhushen" )
	if ( item_xinyan~=nil and item_xinyan:IsFullyCastable() )
	then 
		castItemXinYanDesire, castItemXinYanTarget = ConsiderItemXinYan( item_xinyan )
		if ( castItemXinYanDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_xinyan, castItemXinYanTarget );
			return;
		end
	end
	if ( item_pomo~=nil and item_pomo:IsFullyCastable() )
	then 
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_pomo )
		if ( castItemStunDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_pomo, castItemStunTarget );
			return;
		end
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
	if ( item_qijizhixing~=nil and item_qijizhixing:IsFullyCastable() )
	then 
		castItemQiJjZhiXingDesire, castItemQiJjZhiXingTarget = ConsiderItemQiJiZhiXing(item_qijizhixing)
		if ( castItemQiJjZhiXingDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_qijizhixing, castItemQiJjZhiXingTarget );
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_suwako01" );
	ability02 = npcBot:GetAbilityByName( "ability_thdots_suwako02" );
	ability03 = npcBot:GetAbilityByName( "ability_thdots_suwako03z" );
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_suwako05" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_suwako04new" );
	
	if npcBot:GetLevel() < 25 and npcBot:HasModifier("modifier_ability_thdots_suwako02_telent")
	then return end;
	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilitySuwako01();
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01);
		return;
	end

	cast02Desire = ConsiderAbilitySuwako02();
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02);
		return;
	end
	
	cast03Desire = ConsiderAbilitySuwako03();
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03);
		return;
	end
	
	castExDesire, castExLocation = ConsiderAbilitySuwakoEx();
	if ( castExDesire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( abilityEx , castExLocation);
		return;
	end

	cast04Desire = ConsiderAbilitySuwako04();
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04);
		return;
	end

end

----------------------------------------------------------------------------------------------------

function CanCastSuwako01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastSuwako02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastSuwakoExOnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end

function CanCastSuwako04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySuwako01()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE;
	end;
	
	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or 
		npcBot:GetActiveMode() == BOT_MODE_RETREAT or 
		npcBot:GetActiveMode() == BOT_MODE_GANK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 450, true, BOT_MODE_NONE );
		if ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE;
		end
	end

	return BOT_ACTION_DESIRE_NONE;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySuwako02()
	
	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE;
	end;
	
	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or 
		npcBot:GetActiveMode() == BOT_MODE_RETREAT or 
		npcBot:GetActiveMode() == BOT_MODE_GANK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE );
		if ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE;
		end
	end

	return BOT_ACTION_DESIRE_NONE;
	
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySuwako03()
	
	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE;
	end;
	--always open
	if not ability03:GetToggleState() then
		return BOT_ACTION_DESIRE_HIGH;
	end

	return BOT_ACTION_DESIRE_NONE;
	
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySuwakoEx()
	
	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0;
	end
	
	local nCastRange = 600;
	local nRadius = 200;
	local nDamage = 25;
	-- Fighting or Retreating with hero
	if not (npcBot:GetActiveMode() == BOT_MODE_RETREAT ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil ) then
				if CanCastSuwakoExOnTarget(npcEnemy) then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation();
				end
			end
		end
	end
	
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
		local locationAoE = CachedFindAoELocation( npcBot, 2, true, false, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 );

		if ( locationAoE.count >= 4 ) 
		then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc;
		end
	end
	
	return BOT_ACTION_DESIRE_NONE, 0;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySuwako04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE;
	end
	
	-- Fighting with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or 
		npcBot:GetActiveMode() == BOT_MODE_RETREAT or 
		npcBot:GetActiveMode() == BOT_MODE_GANK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE );
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH;
			end
		end
	end
	
	for _,npcFriend in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
		do
			if ( npcFriend~=nil )
			then
			if ( npcFriend:IsAlive())
			then
			if ( ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend, true)
				)
			) then
				return BOT_ACTION_DESIRE_HIGH;
			end
			end
			end
		end
	local nDamage = 50*ability04:GetLevel()+ 80
	for _,Enemy in pairs (GetUnitList(UNIT_LIST_ENEMY_HEROES)) 
	do
		if ( Enemy~=nil )
		then
			if ( Enemy:IsAlive() and CanCastSuwako04OnTarget(Enemy) )
			then
				if ( Enemy:GetHealth() < nDamage )
				then
					return BOT_ACTION_DESIRE_VERYHIGH
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE;
end

