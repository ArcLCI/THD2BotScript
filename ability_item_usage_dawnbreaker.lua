
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0;
cast02Desire = 0;
cast03Desire = 0;
cast04Desire = 0;

last_time = 0;
function MyItemUsageThink()
	
	local npcBot = GetBot();

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end;

	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	
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
	
	if ( item_horse_green~=nil and item_horse_green:IsFullyCastable() )
	then 
		castItemHorseGreenDesire = ConsiderItemHorseGreen(item_horse_green)
		if ( castItemHorseGreenDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_green );
			return;
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then 
		castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_king );
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_miko01" );
	ability02 = npcBot:GetAbilityByName( "ability_thdots_miko02" );
	ability03 = npcBot:GetAbilityByName( "ability_thdots_miko03" );
	ability04 = npcBot:GetAbilityByName( "ability_thdots_miko04" );

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityMiko01();
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location );
		return;
	end

	cast02Desire = ConsiderAbilityMiko02();
	if ( cast02Desire > 0 ) 
	then
		last_time = GameTime();
		npcBot:Action_UseAbility( ability02 );
		return;
	end
	--[[
	cast04Desire, cast04Target = ConsiderAbilityMiko04();

	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target);
		return;
	end
	--]]
end

----------------------------------------------------------------------------------------------------

function CanCastMiko01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end


function CanCastMiko02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end


function CanCastMiko04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable();
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMiko01()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0;
	end;
	
	local nCastRange = 600;
	local nRadius = 300
	
	if npcBot:GetLevel() >= 25 then
		nRadius = 600;
	end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 50, true, BOT_MODE_NONE );
	
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_GANK then
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, 1, 0 );
		if ( #locationAoE >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc;
		end

		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMiko01OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation();
			end
		end
	end
	if npcBot:GetActiveMode() == BOT_MODE_RETREAT then
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 50, false, BOT_MODE_NONE )
		if not (#tableNearbyFriendlyHeroes > 0) and npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3 then
			local v_shop = GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
			local v_target = - npcBot:GetLocation() + v_shop
			local dis = GetUnitToLocationDistance( npcBot,v_shop)
			local v_final = v_target/dis * nCastRange + npcBot:GetLocation()
			return BOT_ACTION_DESIRE_HIGH, v_final;
		else
			for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
			do
				if ( CanCastMiko01OnTarget( npcEnemy ) ) 
				then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation();
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0;
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMiko02()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE;
	end;
	
	if GameTime() - last_time < 1.5 then
		return BOT_ACTION_DESIRE_NONE
	end
	
	local IsToggleOn = npcBot:HasModifier("modifier_ability_miko02_aura")
	--on 回蓝很高或仙人模式时，无条件开启,且不执行之后的判断(else里的return)
	if npcBot:GetLevel() >= 20 or npcBot:GetManaRegen() >= 32 then
		if not IsToggleOn then --没开就开
			return BOT_ACTION_DESIRE_HIGH;
		else --开了就不管了
			return BOT_ACTION_DESIRE_NONE;
		end
	end
	
	if npcBot:GetMana() < 150 then
		if IsToggleOn then --off 没蓝了
			return BOT_ACTION_DESIRE_HIGH;
		end
	end
	
	--根据实际情况判断是否要开启
	--大逻辑内的小循环还是不要写else，不然两个return之后的代码就失效了
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_GANK then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE );
		if #tableNearbyEnemyHeroes > 0 and npcBot:GetMana() >= npcBot:GetMaxMana()* 0.6 then
			if not IsToggleOn then --on 周围有人且蓝还够
				return BOT_ACTION_DESIRE_HIGH;
			end
		end
		if not (#tableNearbyEnemyHeroes > 0) and npcBot:GetMana() <= npcBot:GetMaxMana()* 0.4 then
			if IsToggleOn then --off 周围没人且快没蓝了
				return BOT_ACTION_DESIRE_HIGH;
			end
		end
	end
	
	if npcBot:GetActiveMode() == BOT_MODE_RETREAT then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE );
		if #tableNearbyEnemyHeroes > 0 then --周围有人追杀
			if not IsToggleOn then --on 没开就开
				return BOT_ACTION_DESIRE_HIGH;
			end
		else --周围没人追杀
			if IsToggleOn then --off 别跑了，没人追
				return BOT_ACTION_DESIRE_HIGH;
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE;
end


----------------------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------------------

function ConsiderAbilityMiko04()

	local npcBot = GetBot();

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil;
	end;
	
	for _,npcFriend in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if ( npcFriend~=nil )
		then
			if ( npcFriend:IsAlive())
			then
				if ( CanCastMiko04OnTarget( npcFriend ) and npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.3 and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend )))
				then
					return BOT_ACTION_DESIRE_HIGH, npcFriend;
				end
			end
		end
	end
	
	return BOT_ACTION_DESIRE_NONE, nil;
	
end


