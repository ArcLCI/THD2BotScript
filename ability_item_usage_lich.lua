
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast04Desire = 0


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_travel_boots = IsItemAvailable( "item_travel_boots" )
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or IsItemAvailable( "item_jiao_shou" )
	local item_book = IsItemAvailable( "item_three_dimension" )

	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end

	if ( item_book~=nil and item_book:IsFullyCastable() ) then
		castBookDesire, castBookTarget = ConsiderItemBook( item_book )
		if ( castBookDesire > 0 ) then
			npcBot:Action_UseAbilityOnEntity( item_book, castBookTarget)
		end
	end
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_koakuma01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_koakuma02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_koakuma04" )

	item_book = IsItemAvailable( "item_three_dimension" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityKoakuma01()
	if ( cast01Desire > 0 )
	then
		if ( item_book~=nil and item_book:IsFullyCastable() )then
			npcBot:Action_UseAbilityOnEntity( item_book, cast01Target)
			return
		end
		npcBot:Action_UseAbilityOnEntity( ability01, cast01Target)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityKoakuma02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability02, cast02Target)
		return
	end

	cast04Desire = ConsiderAbilityKoakuma04()

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastKoakuma01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastKoakuma02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityKoakuma01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() or ability04:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability01:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastKoakuma01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(nCastRange,true)
		for _,npccreeps in pairs( tableNearbylanecreeps )
		do
			return BOT_ACTION_DESIRE_HIGH, npccreeps
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityKoakuma02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() or ability04:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability02:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastKoakuma02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityKoakuma04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	local nCastRange = ability01:GetCastRange()
	-- Fighting or Retreating with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

