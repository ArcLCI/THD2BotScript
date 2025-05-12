
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
castExDesire = 0


function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	
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
	
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )
	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then 
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end
	
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then 
		castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_speed )
			return
		end
	end	
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_seiga01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_seiga02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_seiga03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_seiga04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_seigaEx" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilitySeiga01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilitySeiga02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target )
		return
	end

	cast03Desire, cast03Target = ConsiderAbilitySeiga03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03, cast03Target)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilitySeiga04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

	castExDesire, castExLocation = ConsiderAbilitySeigaEx()
	if ( castExDesire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( abilityEx , castExLocation)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastSeiga01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSeiga02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSeiga03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSeiga04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSeigaExOnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeiga01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 800
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastSeiga01OnTarget( npcFriend ) and 
			( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
			npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
			IsUnderAttack( npcFriend )))
		then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeiga02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 800
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastSeiga02OnTarget( npcFriend ) and 
			( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
			npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
			IsUnderAttack( npcFriend )))
		then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeiga03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 800

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastSeiga03OnTarget( npcEnemy ) ) 
			then
				return BOT_ACTION_DESIRE_VERYHIGH, npcEnemy
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeiga04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	

	for _,npcFriend in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if ( npcFriend~=nil )
		then
			if ( npcFriend:IsAlive())
			then
				if ( CanCastSeiga04OnTarget( npcFriend ) and npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.3 and 
					( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
					npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
					IsUnderAttack( npcFriend ))) 
				then
					return BOT_ACTION_DESIRE_HIGH, npcFriend
				end
			end
		end
	end
	
	return BOT_ACTION_DESIRE_NONE, nil
	
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySeigaEx()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nCastRange = 1000
	
	--[[
	--------------------------------------
	-- Mode based usage
	--------------------------------------

	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK or
		 npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
	then
		local npcTarget = npcBot:GetTarget()
		
		if npcBot:GetTarget() ~= nil then
			local disT = GetUnitToUnitDistance( npcBot, npcBot:GetTarget())
			local dimin = 500
			local dimax = 500 + nCastRange
			if disT > dimin and disT < dimax then
				print('seiga 5 2')
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	--]]
	
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
		local v_shop = GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
		local v_target = - npcBot:GetLocation() + v_shop
		local dis = GetUnitToLocationDistance( npcBot,v_shop)
		local v_final = v_target/dis * nCastRange + npcBot:GetLocation()
		return BOT_ACTION_DESIRE_HIGH, v_final
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

