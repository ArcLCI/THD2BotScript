
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire,cast02Desire,castExDesire,cast04Desire,castPoseDesire = 0,0,0,0,0
local ability01,ability02,ability04,abilityEx,abilityPose,cast04Location,castExLocation


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	local item_root = IsItemAvailable( "item_morenjingjuan" ) or IsItemAvailable( "item_tentacle" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )

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
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		local castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
	end
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then
		local castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 or cast04Desire > 0)
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_iku01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_iku02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_iku04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_ikuEx" )
	abilityPose = npcBot:GetAbilityByName( "ability_thdots_iku_pose" )

	-- Consider using each ability
	cast01Desire = ConsiderAbilityIku01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbility( ability01 )
		return
	end

	cast02Desire = ConsiderAbilityIku02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02)
		return
	end

	cast04Desire, cast04Location = ConsiderAbilityIku04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

	castExDesire, castExLocation = ConsiderAbilityIkuEx()
	if ( castExDesire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( abilityEx, castExLocation )
		return
	end

	castPoseDesire = ConsiderAbilityIkuPose()
	if ( castPoseDesire > 0 )
	then
		npcBot:Action_UseAbility( abilityPose )
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastIku01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastIku02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end

function CanCastIkuExOnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastIku04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastIkuPoseOnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityIku01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- on shit ruuuuuuuun
	if npcBot:GetActiveMode() == BOT_MODE_RETREAT then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes > 0 then
			--open
			if not ability01:GetToggleState() then
				return BOT_ACTION_DESIRE_MODERATE
			else
				return BOT_ACTION_DESIRE_NONE
			end
		else
			--close
			if ability01:GetToggleState() then
				return BOT_ACTION_DESIRE_MODERATE
			else
				return BOT_ACTION_DESIRE_NONE
			end
		end
	end

	-- mana lower than 600(no mana for 2+4) and opening, close for util
	if npcBot:GetMana() < 600 and ability04:IsFullyCastable() and ability01:GetToggleState() then
		return BOT_ACTION_DESIRE_HIGH
	end

	-- mana lower than 700, don't open this ability for util
	if npcBot:GetMana() < 700 and ability04:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end

	-- mana lower than 100 and opening, close for now
	if npcBot:GetMana() < 100 and ability01:GetToggleState() then
		return BOT_ACTION_DESIRE_HIGH
	end

	-- mana lower than 300, don't open this ability
	if npcBot:GetMana() < 200 then
		return BOT_ACTION_DESIRE_NONE
	end

	-- mana higher than 700

	--local nCastRange = npcBot:GetAttackRange()
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE )
	--local manacost = ability01:ToggleAutoCast()
	--open
	--print(ability01:GetToggleState()) true or false
	if npcBot:GetManaRegen() >= 19 and not ability01:GetToggleState() then
		return BOT_ACTION_DESIRE_HIGH
	end

	for _,npcEnemy in pairs( tableNearbyEnemyHeroes ) do
		if npcEnemy:HasModifier("modifier_ability_thdots_iku04") and not ability01:GetToggleState()then
			return BOT_ACTION_DESIRE_HIGH
		end
		if (npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetMana() >= npcBot:GetMaxMana()* 0.6 and
		not ability01:GetToggleState()) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityIku02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nCastRange = 250
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastIku02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) and
			GetUnitToLocationDistance(npcBot:GetTarget(),GetShopLocation(npcBot:GetTeam(),SHOP_HOME))<=
			GetUnitToLocationDistance(npcBot,GetShopLocation(npcBot:GetTeam(),SHOP_HOME)))
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
			if npcEnemy:HasModifier("modifier_ability_thdots_iku04") then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT ) then
		local cur_speed = npcBot:GetCurrentMovementSpeed()
		if ( cur_speed >= 420 )
		then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityIkuEx()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = abilityEx:GetCastRange()
	local nRadius = 250
	local nDamage = 100+10*npcBot:GetLevel()
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, 1.7, nDamage )
	if ( locationAoE.count >= 1 ) then
		return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	end
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_RETREAT)
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE )
		local locationAoE = CachedFindAoELocation( npcBot, 2, true, true, npcBot:GetLocation(), 800, nRadius, 1.7, 0 )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastIkuExOnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) and locationAoE.count >= 1)
			then
				return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityIku04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability04:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange-50, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastIku04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityIkuPose()

	local npcBot = GetBot()

	-- Make sure it's castable
	if (not abilityPose:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if (not npcBot:HasScepter())
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nCastRange = abilityPose:GetCastRange()
	local nRadius = 250
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if (GetModifiersTimeLeft(npcEnemy, ModifierNamesHighDebuff) >= 1.5 or
			GetModifiersTimeLeft(npcEnemy, ModifierNamesTeleporting) > 1.7)
		then
			return BOT_ACTION_DESIRE_HIGH
		end
		local locationAoE = CachedFindAoELocation( npcBot, 3, true, true, npcBot:GetLocation(), nCastRange, nRadius, 1.7, 0 )
		if ( locationAoE.count >= 3 ) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end