
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire,cast02Desire,cast04Desire = 0,0,0
local ability01,ability02,ability04,cast01Target,cast02Location,cast04Location


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end


	local item_feixiangjian = IsItemAvailable( "item_feixiangjian" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
	IsItemAvailable( "item_brother_sharp" )

	if ( item_feixiangjian~=nil and item_feixiangjian:IsFullyCastable() )
	then
		local castItemFeiXiangJianDesire, castItemFeiXiangJianTarget = ConsiderItemFeiXiangJian( item_feixiangjian )
		if ( castItemFeiXiangJianDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_feixiangjian, castItemFeiXiangJianTarget )
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
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then
		local castItemSpeedDesire = ConsiderItemSpeed( item_speed )
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
	ConsiderNeutralItems()


	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_child01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_child02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_child04" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityLuna01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire, cast02Location = ConsiderAbilityLuna02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end

	cast04Desire, cast04Location = ConsiderAbilityLuna04()

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastLuna01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false) and npcTarget:IsHero()
end

function CanCastLuna02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastLuna04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLuna01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	--local nCastRange = ability01:GetCastRange()
	local nCastRange = npcBot:GetAttackRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy and CanCastLuna01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLuna02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability02:GetCastRange()
	local nRadius = ability02:GetSpecialValueInt( "radius" )
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )
		if ( locationAoE.count >= 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastLuna04OnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end

	return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityLuna04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRangeNear =  npcBot:GetAttackRange()
	--local nCastRange = 1500 + 300 * ability04:GetLevel()
	local nCastRange = 1799
	local nRadius = 200
	local nDamage = 100 + 100 * ability04:GetLevel()
	local locationAoE = CachedFindAoELocation( npcBot, 2, true, true, npcBot:GetLocation(), nCastRangeNear, nRadius, 0, 0 )
		if ( locationAoE.count >= 3 ) then
			return BOT_ACTION_DESIRE_MODERATE, locationAoE.targetloc
		end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastLuna04OnTarget( npcEnemy ) and nDamage > npcEnemy:GetHealth() and not IsPossibleIllusion( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

