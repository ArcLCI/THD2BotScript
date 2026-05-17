
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast04Desire = 0
cast05Desire = 0

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	local item_kafziel = IsItemAvailable( "item_kafziel" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_king = IsItemAvailable( "item_horse_king")

	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemGhostDesire, castItemGhostTarget = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_ghost, castItemGhostTarget )
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
	if ( item_kafziel~=nil and item_kafziel:IsFullyCastable() )
	then
		local castItemKafzielDesire, castItemKafzielTarget = ConsiderItemKafziel( item_kafziel )
		if ( castItemKafzielDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_kafziel, castItemKafzielTarget )
			return
		end
	end
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
	if ( item_horse_red~=nil and item_horse_red:IsFullyCastable() )
	then
		castItemHorseRedDesire = ConsiderItemHorseRed(item_horse_red)
		if ( castItemHorseRedDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_red )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_miyako01" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_miyako04" )
	ability05 = npcBot:GetAbilityByName( "ability_thdots_miyako05" )

	-- Consider using each ability

	cast01Desire = ConsiderAbilityMiyako01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbility( ability01)
		return
	end

	cast04Desire = ConsiderAbilityMiyako04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04)
		return
	end
	if npcBot:HasModifier("modifier_item_wanbaochui") then
	cast05Desire = ConsiderAbilityMiyako05()
		if ( cast05Desire > 0 )
		then
			npcBot:Action_UseAbility( ability05)
		end
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastMiyako01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end


function CanCastMiyako04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMiyako01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 600, true, BOT_MODE_NONE )
	--[[
	--open
	if #tableNearbyEnemyHeroes >= 1 and not ability01:GetToggleState()
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	--close
	if not #tableNearbyEnemyHeroes > 0 and ability01:GetToggleState()
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	--]]
	--[[
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if #tableNearbyEnemyHeroes > 0
			then --周围有人
				--open
				if not ability01:GetToggleState() then
					return BOT_ACTION_DESIRE_HIGH
				end
			else --周围没人
				--close
				if ability01:GetToggleState() then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	--]]
	--GetToggleState是什么几把，我直接用HasModifier
	if #tableNearbyEnemyHeroes > 0 then --周围有人
		--open
		if not npcBot:HasModifier("modifier_ability_thdots_miyako01_caster") then
			return BOT_ACTION_DESIRE_HIGH
		end
	else
		--close
		if npcBot:HasModifier("modifier_ability_thdots_miyako01_caster") then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------------------

function ConsiderAbilityMiyako04()


	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end


--[[
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
	
	if ( npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3 and
		( GetModifiersTimeLeft(npcBot, ModifierNamesHighDebuff) > 0.5 
		or npcBot:WasRecentlyDamagedByAnyHero( 1.0 )
		or IsUnderAttack( npcBot )))
	then
		return BOT_ACTION_DESIRE_HIGH
	end
--]]

	if ( npcBot:GetHealth() < npcBot:GetMaxHealth()*0.5 )
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE

end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityMiyako05()


	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability05:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end


	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1500, true, BOT_MODE_NONE )
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