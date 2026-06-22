
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0

function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	
	local item_feixiangjian = IsItemAvailable( "item_feixiangjian" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	
	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	
	if ( item_feixiangjian~=nil and item_feixiangjian:IsFullyCastable() )
	then 
		castItemFeiXiangJianDesire, castItemFeiXiangJianTarget = ConsiderItemFeiXiangJian( item_feixiangjian )
		if ( castItemFeiXiangJianDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_feixiangjian, castItemFeiXiangJianTarget )
			return
		end
	end
	
	if ( item_horse_green~=nil and item_horse_green:IsFullyCastable() )
	then 
		castItemHorseGreenDesire = ConsiderItemHorseGreen(item_horse_green)
		if ( castItemHorseGreenDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_green )
			return
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then 
		castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_king )
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
end

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()
	
	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdotsr_Nazrin01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdotsr_Nazrin02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdotsr_Nazrin04" )

	-- Consider using each ability

	cast01Desire = ConsiderAbilityNazrin01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01 )
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityNazrin02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityNazrin04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastNazrin02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end

function CanCastNazrin04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityNazrin01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() or SafeHasModifier(npcBot, "modifier_thdots_yugi04_think_interval" )) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local nCastRange = 800
	
	if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK or 
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		return BOT_ACTION_DESIRE_HIGH
	end
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	if #tableNearbyFriendlyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend,true )
				) then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and not IsPossibleIllusion( npcEnemy )) 
		then
			return BOT_ACTION_DESIRE_HIGH
		end
		
		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) and not IsPossibleIllusion( npcEnemy )) 
		then
			return BOT_ACTION_DESIRE_MODERATE
		end
		
	end
	
	return BOT_ACTION_DESIRE_NONE
	
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityNazrin02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local nRadius = 300
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nRadius , true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes > 0 then
			return BOT_ACTION_DESIRE_HIGH, npcBot
		end
	end
	
	local nCastRange = 500
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastNazrin02OnTarget( npcFriend ) and 
			( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
			npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
			IsUnderAttack( npcFriend,true )))
		then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------
function ConsiderAbilityNazrin04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 750
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) 
	then	
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (CanCastNazrin04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
