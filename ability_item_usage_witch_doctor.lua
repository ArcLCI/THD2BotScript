
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
	
	local item_doupeng = IsItemAvailable( "item_zun_glasses" )
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
						IsItemAvailable( "item_jiao_shou" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	if ( item_doupeng~=nil and item_doupeng:IsFullyCastable() )
	then 
		castItemDouPengDesire = ConsiderItemDouPeng( item_doupeng )
		if ( castItemDouPengDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_doupeng )
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
	
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then 
		castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 or cast04Desire > 0) 
		then
			npcBot:Action_UseAbility( item_speed )
			return
		end
	end
	
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
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_hina01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_hina02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_hina03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_hina04" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityHina01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityHina02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02, cast02Target )
		return
	end

	cast03Desire, cast03Target = ConsiderAbilityHina03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target)
		return
	end

	cast04Desire = ConsiderAbilityHina04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastHina01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastHina02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end


function CanCastHina03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastHina04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityHina01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability01:GetCastRange()
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastHina01OnTarget( npcFriend ) and 
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

function ConsiderAbilityHina02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = ability02:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastHina02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, nil
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityHina03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = ability03:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastHina03OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityHina04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end

	-- Get some of its values
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 600, true, BOT_MODE_NONE )
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 900, false, BOT_MODE_NONE )

	if #tableNearbyEnemyHeroes > 1 and #tableNearbyEnemyHeroes < 3 and #tableNearbyFriendlyHeroes > 1 then
		return BOT_ACTION_DESIRE_MODERATE
	elseif #tableNearbyEnemyHeroes > 2 and #tableNearbyEnemyHeroes < 5 then
		return BOT_ACTION_DESIRE_HIGH
	elseif #tableNearbyEnemyHeroes > 4 then
		return BOT_ACTION_DESIRE_VERYHIGH
	end
	
	return BOT_ACTION_DESIRE_NONE
end

