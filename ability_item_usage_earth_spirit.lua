
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
	

	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )
	
	local item_frock = IsItemAvailable( "item_frock" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	
	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemGhostDesire = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_ghost )
			return
		end
	end

	if ( item_weijin~=nil and item_weijin:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemWeijinDesire = ConsiderItemWeiJin(item_weijin)
		if ( castItemWeijinDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_weijin )
			return
		end
	end
	
	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then 
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end
	if ( item_frock~=nil and item_frock:IsFullyCastable() )
	then 
		castItemDuQunDesire = ConsiderItemDuQun(item_frock)
		if ( castItemDuQunDesire > 0 ) 
		then
			npcBot:Action_UseAbility(item_frock)
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
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_merlin01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_merlin02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_merlin03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_merlin04" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityMerlin01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityMerlin02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02, cast02Target )
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityMerlin04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastMerlin01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastMerlin02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastMerlin04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMerlin01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability01:GetCastRange()
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK or 
	npcBot:GetActiveMode() == BOT_MODE_RETREAT
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+100, true, BOT_MODE_NONE )
		local mxcap=0
		local mxTarget=nil
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMerlin01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end
		return BOT_ACTION_DESIRE_MODERATE, mxTarget
	end
	return BOT_ACTION_DESIRE_NONE,nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMerlin02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability02:GetCastRange()
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastMerlin02OnTarget( npcFriend ) and 
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMerlin04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability04:GetCastRange()
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+50, true, BOT_MODE_NONE )
		local mxcap=0
		local mxTarget=nil
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMerlin04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end
		
	if #tableNearbyEnemyHeroes > 2 then
		return BOT_ACTION_DESIRE_MODERATE, mxTarget
	end
	
	if #tableNearbyEnemyHeroes > 0 and (
			npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and(
				(npcBot:GetActiveMode() == BOT_MODE_ATTACK and #tableNearbyEnemyHeroes > 1) or
				npcBot:GetActiveMode() == BOT_MODE_RETREAT
			) 
		) then
		return BOT_ACTION_DESIRE_MODERATE, mxTarget
	end
	

	return BOT_ACTION_DESIRE_NONE,nil
end

