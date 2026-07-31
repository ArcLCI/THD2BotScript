
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast03Desire = 0
local cast04Desire = 0

local ability01,ability02,ability03,ability04,
	cast01Location,cast03Target,cast03TargetLocation

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )

	local item_root = IsItemAvailable( "item_tentacle" ) or IsItemAvailable( "item_morenjingjuan" )
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
						IsItemAvailable( "item_jiao_shou" )

	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then
		local castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget )
			return
		end
	end


	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		local castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
	end

	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then
		local castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_dota2x_reimu01" )
	ability02 = npcBot:GetAbilityByName( "ability_dota2x_reimu02" )
	ability03 = npcBot:GetAbilityByName( "ability_dota2x_reimu03" )
	ability04 = npcBot:GetAbilityByName( "ability_dota2x_reimu04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityReimu01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast02Desire = ConsiderAbilityReimu02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02 )
		return
	end

	if not npcBot:HasModifier("modifier_item_wanbaochui") then
		cast03Desire, cast03Target = ConsiderAbilityReimu03()
		if ( cast03Desire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target)
			return
		end
	else
		cast03Desire, cast03TargetLocation = ConsiderAbilityReimu03()
		if ( cast03Desire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( ability03 , cast03TargetLocation)
			return
		end
	end


	cast04Desire = ConsiderAbilityReimu04()

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastReimu01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end


function CanCastReimu02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end


function CanCastReimu03OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false, { allowMagicImmune = GetBot():HasScepter() })
end

function CanCastReimu04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityReimu01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nRadius = 200
	local nCastRange = ability01:GetCastRange()
	local eta = 0.66

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange +100 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and CanCastReimu01OnTarget( npcEnemy ))
		then
			local locationAoE = CachedFindAoELocation( npcBot, 1, true, false, npcEnemy:GetLocation(), 2*nRadius, nRadius, eta, 0 )

			if ( locationAoE.count >= 2 ) then
				return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
			end
			if npcEnemy:GetMovementDirectionStability() >= 0.75 then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
			end
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end
	end

	if IsSeriouslyRetreating(npcBot, 'ability_dota2x_reimu01') then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (CanCastReimu01OnTarget(npcEnemy)) then
				if npcEnemy:GetMovementDirectionStability() >= 0.75 then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
				end
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
	end
	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(750,true)
		if tableNearbylanecreeps ~= nil and #tableNearbylanecreeps >= 3
        then
            return BOT_ACTION_DESIRE_HIGH, GetCenterOfUnits(tableNearbylanecreeps)
        end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityReimu02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Get some of its values
	local nRadius = 650

	local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes(nRadius, true, BOT_MODE_NONE)
	local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(nRadius,true)
	local t300 = CachedGetNearbyHeroes( npcBot, 300 , true, BOT_MODE_NONE )

	if tableNearbyEnemyHeroes~=nil and #tableNearbyEnemyHeroes > 0 and npcBot:GetActiveMode() == BOT_MODE_ATTACK then
		for _,npcEnemy in pairs(tableNearbyEnemyHeroes)
        do
			if (tableNearbylanecreeps == nil
			or GetUnitToUnitDistance(npcBot,tableNearbylanecreeps[1]) > GetUnitToUnitDistance(npcBot,npcEnemy))
			and npcBot:GetTarget() == npcEnemy
			and CanCastReimu02OnTarget(npcEnemy) then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	if #t300 > 0 then
		return BOT_ACTION_DESIRE_HIGH
	end
	if (tableNearbyEnemyHeroes~=nil and #tableNearbyEnemyHeroes > 0
	and IsRetreating(npcBot, 'ability_dota2x_reimu02', { legacyModeDesire = BOT_MODE_DESIRE_VERYHIGH }) ) then
		return BOT_ACTION_DESIRE_HIGH
	end

	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityReimu03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability03:GetCastRange()

	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )

	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastReimu03OnTarget( npcFriend ) and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
				if npcBot:HasModifier("modifier_item_wanbaochui") then
					return BOT_ACTION_DESIRE_HIGH, npcFriend:GetLocation()
				end
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH )
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy )
			then
				if ( CanCastReimu03OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
				then
					if npcBot:HasModifier("modifier_item_wanbaochui") then
						return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
					end
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy
				end
			end
		end
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if IsRetreating(npcBot, 'ability_dota2x_reimu03', { legacyModeDesire = BOT_MODE_DESIRE_VERYHIGH })
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
			then
				if npcBot:HasModifier("modifier_item_wanbaochui") then
					return BOT_ACTION_DESIRE_HIGH, npcBot:GetLocation()
				end
				return BOT_ACTION_DESIRE_MODERATE, npcBot
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityReimu04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )

	if #tableNearbyEnemyHeroes > 2 then
		return BOT_ACTION_DESIRE_MODERATE
	end

	if #tableNearbyEnemyHeroes > 0 and
		tableNearbyEnemyHeroes[1]:GetHealth() < 150.0 + 100 * ability04:GetLevel() then
		return BOT_ACTION_DESIRE_MODERATE
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and
		npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH and
		#tableNearbyEnemyHeroes > 0) then
		return BOT_ACTION_DESIRE_MODERATE
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if IsRetreating(npcBot, 'ability_dota2x_reimu04', { legacyModeDesire = BOT_MODE_DESIRE_VERYHIGH })
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) and not IsPossibleIllusion( npcEnemy ))
			then
				if ( CanCastReimu04OnTarget( npcBot ) )
				then
					return BOT_ACTION_DESIRE_MODERATE
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

