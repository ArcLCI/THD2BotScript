
require(GetScriptDirectory() ..  "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast04Desire = 0

local ability01, ability02, ability04, cast01Location, cast02Target, cast04Target

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_horse_red = IsItemAvailable("item_horse_red")
	local item_horse_king = IsItemAvailable("item_horse_king")
	local item_doctor_doll = IsItemAvailable("item_doctor_doll")
	local item_stand = IsItemAvailable("item_dummy_doll1")
	local item_root = IsItemAvailable("item_tentacle")
	local item_morenjingjuan = IsItemAvailable("item_morenjingjuan")
	local item_feixiangjian = IsItemAvailable("item_feixiangjian")

	if ( item_stand~=nil and item_stand:IsFullyCastable() )
	then
		local castItemStandDesire = ConsiderItemStand( item_stand )
		if ( castItemStandDesire > 0 )
		then
			npcBot:Action_UseAbility( item_stand )
			return
		end
	end

	if ( item_morenjingjuan~=nil and item_morenjingjuan:IsFullyCastable() )
	then
		local castItemMoRenDesire, castItemMoRenTarget = ConsiderItemRoot( item_morenjingjuan )
		if ( castItemMoRenDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_morenjingjuan, castItemMoRenTarget )
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
	if ( item_horse_red~=nil and item_horse_red:IsFullyCastable() )
	then
		local castItemHorseRedDesire = ConsiderItemHorseRed(item_horse_red)
		if ( castItemHorseRedDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_red )
			return
		end
	end

	if ( item_doctor_doll~=nil and item_doctor_doll:IsFullyCastable() )
	then
		local castItemDoctorDollDesire = ConsiderItemDoctorDoll(item_doctor_doll)
		if ( castItemDoctorDollDesire > 0 )
		then
			npcBot:Action_UseAbility(item_doctor_doll)
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
	if ( item_feixiangjian~=nil and item_feixiangjian:IsFullyCastable() )
	then
		local castItemFeiXiangJianDesire, castItemFeiXiangJianTarget = ConsiderItemFeiXiangJian( item_feixiangjian )
		if ( castItemFeiXiangJianDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_feixiangjian, castItemFeiXiangJianTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_shikieiki01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_shikieiki02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_shikieiki04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityShikieiki01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityShikieiki02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityShikieiki04()
	if ( cast04Desire > 0 and cast04Target ~= nil )
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastShikieiki01OnTarget( npcTarget )
	return J.IsValidBotTarget(npcTarget)
end


function CanCastShikieiki02OnTarget( npcTarget )
	return J.IsValidBotTarget(npcTarget)
end


function CanCastShikieiki04OnTarget( npcTarget )
	return J.IsValidBotTarget(npcTarget)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityShikieiki01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability01:GetCastRange()
	local nRadius = ability01:GetSpecialValueInt( "AOE" )
	local nTime = 0
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange + 100, nRadius, nTime, 0 )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if CanCastShikieiki01OnTarget(npcEnemy) and locationAoE.count >= 1 then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityShikieiki02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability02:GetCastRange()
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastShikieiki02OnTarget(npcEnemy) then
				local nModifier = npcEnemy:GetModifierByName("modifier_thdots_shikieiki1_accusation")
				local accCount = npcEnemy:GetModifierStackCount(nModifier)
				local stunTime = 1 + (0.05 + 0.05*ability02:GetLevel())*accCount
				local abilityDmg = npcEnemy:GetActualIncomingDamage((50 * ability02:GetLevel() + accCount * (50 + 10 * ability02:GetLevel()))*(1+npcBot:GetSpellAmp()),DAMAGE_TYPE_MAGICAL)

				if accCount >= 8 then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy
				end

				if (npcEnemy:GetHealth() >= 400 and abilityDmg > npcEnemy:GetHealth() * 0.85)
				or npcEnemy:GetHealth() < 400 and abilityDmg > npcEnemy:GetHealth() then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy
				end

				if stunTime >= 2 and npcBot:GetTarget() == npcEnemy and GetUnitToUnitDistance(npcBot,npcEnemy) > 500 then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy
				end
			end
		end
	end

	if IsSeriouslyRetreating(npcBot) then
		for _,npcEnemy in pairs(tableNearbyEnemyHeroes)
		do
			if CanCastShikieiki02OnTarget(npcEnemy) then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityShikieiki04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability04:GetCastRange()

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+100, true, BOT_MODE_NONE )
		local mxcap=0
		local mxTarget=nil
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastShikieiki04OnTarget( npcEnemy ) then
				local capability = GetCapability(npcEnemy)
				if capability > mxcap then
					mxcap=capability
					mxTarget=npcEnemy
				end
			end
		end

	if npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and (npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_RETREAT)
	then
		return BOT_ACTION_DESIRE_HIGH, mxTarget
	end
	return BOT_ACTION_DESIRE_NONE,nil
end

