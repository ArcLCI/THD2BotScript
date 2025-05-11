
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


	local item_teeth = IsItemAvailable( "item_teeth" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
	IsItemAvailable( "item_brother_sharp" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_king = IsItemAvailable( "item_horse_king")

	local ability03 = npcBot:GetAbilityByName( "ability_thdots_youmu03" )

	if ( item_teeth~=nil and item_teeth:IsFullyCastable() and
			( npcBot:IsSilenced()
				or not ability03:IsFullyCastable()
				or not ability03:IsOwnersManaEnough()
				--must use ability3 before teeth(except can't)
			)
		)
	then
		local castItemTeethDesire = ConsiderItemTeeth( item_teeth )
		if ( castItemTeethDesire > 0 )
		then
			npcBot:Action_UseAbility( item_teeth )
			return
		end
	end

	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then
		local castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 )
		then
			npcBot:Action_UseAbility( item_speed )
			return
		end
	end

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

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_youmu01" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_youmu03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_youmu04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_youmuEx" )
	item_tideng = IsItemAvailable( "item_tsundere" )

	-- Consider using each ability
	castexDesire = ConsiderAbilityYoumuEx()
	if ( castexDesire > 0 )
	then
		npcBot:Action_UseAbility( abilityEx )
		return
	end

	cast01Desire, cast01Location = ConsiderAbilityYoumu01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast03Desire = ConsiderAbilityYoumu03()
	if ( cast03Desire > 0 )
	then
		npcBot:Action_UseAbility( ability03 )
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityYoumu04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastYoumu01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsInvulnerable()
end

function CanCastYoumu03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsInvulnerable()
end

function CanCastYoumu04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and
	not npcTarget:IsMagicImmune() and
	not npcTarget:IsInvulnerable() and
	npcTarget:GetArmor() < 200.0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumuEx()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- consider attack range
	local nCastRange = 220

	--------------------------------------
	-- Mode based usage
	--------------------------------------

	if IsUnderAttack(npcBot,true) then
		return BOT_ACTION_DESIRE_HIGH
	end

	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumu01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nRadius = ability01:GetSpecialValueInt( "radius" )
	local nDamage = ability01:GetAbilityDamage()
	local nLevel = ability01:GetLevel()
	local nCastRange = (nLevel-1)*100 + 699

	-- consider attack range

	--------------------------------------
	-- Mode based usage
	--------------------------------------

	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastYoumu01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end

		end
	end

	-- 冲刺！冲刺！冲！冲！
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY )
	then
		local npcTarget = npcBot:GetTarget()

		if ( npcTarget ~= nil )
		then
			if ( CanCastYoumu01OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	-- 我军败了！快撤！
	if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and not npcBot:HasModifier("modifier_fountain_aura_buff")) then
		local v_home = GetAncient(npcBot:GetTeam()):GetLocation()
		local v_target = ( v_home - npcBot:GetLocation() ) / GetUnitToLocationDistance( npcBot, v_home)
		local v_final = npcBot:GetLocation() + v_target * nCastRange
		return BOT_ACTION_DESIRE_HIGH, v_final
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYoumu03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end


	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 400, true, BOT_MODE_NONE )
		if ( #tableNearbyEnemyHeroes > 0 ) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

local a1={90,180,270}
local a2={3.0,4.2,5.4}

function ConsiderAbilityYoumu04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil
	end

	local nLevel = ability04:GetLevel()
	local nCastRange = ability04:GetCastRange()
	local nDamage = a1[nLevel] + npcBot:GetAttributeValue( ATTRIBUTE_AGILITY )*a2[nLevel]
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 700, false, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes500 = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	local exDamage = (#tableNearbyFriendlyHeroes - 1) * 100

	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetHealth() < npcBot:GetMaxHealth() * 0.3 )
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes500 )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastYoumu04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
--				print('youmu_debug_01')
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end

			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) and not IsPossibleIllusion( npcEnemy ))
			then
				if ( CanCastYoumu04OnTarget( npcEnemy ) )
				then
--					print('youmu_debug_02')
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy
				end
			end
		end
	end

		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastYoumu04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) and
					( nDamage * GetPhysicalDamageRemain( npcEnemy:GetArmor() )
						+ exDamage > npcEnemy:GetHealth()
					)
				)
			then
--				print( nDamage * GetPhysicalDamageRemain( npcEnemy:GetArmor() ) )
--				print( GetPhysicalDamageRemain( npcEnemy:GetArmor()  ) )
--				print( exDamage )
--				print( npcEnemy:GetHealth() )
--				print('youmu_debug_03')
				return BOT_ACTION_DESIRE_MODERATE,npcEnemy
			end
		end

	-- extremely want attack -> direct util
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and
		npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH
		)
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			local is_tp=GetModifierTimeLeft( npcEnemy, "modifier_teleporting" )
			if ( npcBot:GetTarget() == npcEnemy and not IsPossibleIllusion( npcEnemy ) and
			CanCastYoumu04OnTarget( npcEnemy ) and
			is_tp < 1.0 and is_tp > 0.2 )
			then
--				print('youmu_debug_04')
				return BOT_ACTION_DESIRE_MODERATE,npcEnemy
			end
		end
	end
--[[
	-- If we're going after someone
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
	then
		local npcTarget = npcBot:GetTarget()

		if ( npcTarget ~= nil ) 
		then
			if ( CanCastYoumu04OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH,npcTarget
			end
		end
	end
]]--
	return BOT_ACTION_DESIRE_NONE, nil

end

