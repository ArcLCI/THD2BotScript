
local heroName = string.gsub(GetBot():GetUnitName(),"npc_dota_hero_","")

require(GetScriptDirectory() ..  "/thd2_item_usage")
require(GetScriptDirectory() ..  "/item_purchase_" .. heroName)
local CombatPower = require(GetScriptDirectory()..'/THDFuncLib/combat_power')

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast03Desire = 0
local cast04Desire = 0
local cast05Desire = 0

local ability01,ability02,ability03,ability04,ability05,
	cast01Location,cast02Location,cast03Location,cast04Location
local cachedCast01Location,cachedCast02Location,cachedCast03Location = 0,0,0


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end


	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )

	local item_xinyan = IsItemAvailable( "item_third_eyes" )
	local item_shield = IsItemAvailable( "item_esdw" ) or IsItemAvailable( "item_trinity" )
	if ( item_xinyan~=nil and item_xinyan:IsFullyCastable() )
	then
		local castItemXinYanDesire, castItemXinYanTarget = ConsiderItemXinYan( item_xinyan )
		if ( castItemXinYanDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_xinyan, castItemXinYanTarget )
			return
		end
	end

	if ( item_shield~=nil and item_shield:IsFullyCastable() )
	then 
		local castItemShieldDesire = ConsiderItemShield(item_shield)
		if ( castItemShieldDesire > 0 )
		then
			npcBot:Action_UseAbility( item_shield )
			return
		end
	end

	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then
		local castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_tojiko01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_tojiko02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_tojiko03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_tojiko04" )
	ability05 = npcBot:GetAbilityByName( "ability_thdots_tojiko05" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityTojiko01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location)
		cachedCast01Location = cast01Location
		return
	end

	cast02Desire, cast02Location = ConsiderAbilityTojiko02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		cachedCast02Location = cast02Location
		return
	end

	cast03Desire, cast03Location = ConsiderAbilityTojiko03()
	if ( cast03Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability03, cast03Location )
		cachedCast03Location = cast03Location
		return
	end

	cast04Desire, cast04Location = ConsiderAbilityTojiko04()

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

	if npcBot:HasModifier("modifier_item_wanbaochui") then
	cast05Desire = ConsiderAbilityTojiko05()
		if ( cast05Desire > 0 )
		then
			npcBot:Action_UseAbility( ability05)
		end
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastTojiko01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

function CanCastTojiko02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, true)
end

function CanCastTojiko03OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, true)
end

function CanCastTojiko04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityTojiko01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() or ability03:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability01:GetCastRange()
	local nRadius = 150
	local nTime = 0
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	local tableAllMapEnemyHeroes = CachedGetNearbyHeroes( npcBot, 99999, true, BOT_MODE_NONE )
	local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, nTime, 0 )
	local abilityBaseDamage = ability01:GetLevel()*60

	if #tableNearbyEnemyHeroes > 1 then
		if ( locationAoE.count > 0 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	elseif #tableNearbyEnemyHeroes > 0 then
		if CanCastTojiko01OnTarget(tableNearbyEnemyHeroes[1]) then
			return BOT_ACTION_DESIRE_HIGH, tableNearbyEnemyHeroes[1]:GetLocation()
		end
	end
	if #tableAllMapEnemyHeroes > 0 and cachedCast01Location ~= 0 then
		for _, npcEnemy in pairs(tableAllMapEnemyHeroes) do
			if CanCastTojiko01OnTarget(npcEnemy) then
				local defense = CombatPower.GetDefenseSnapshot(npcEnemy)
				local rawDamage = defense ~= nil
					and math.max(0, abilityBaseDamage + 4 * defense.armor) * (1 + npcBot:GetSpellAmp())
					or nil
				local incomingDamage = rawDamage ~= nil
					and CombatPower.EstimateIncomingDamageFromSnapshot(defense, rawDamage, DAMAGE_TYPE_MAGICAL)
					or nil
				if incomingDamage ~= nil
				and defense.health < incomingDamage
				and GetUnitToLocationDistance(npcEnemy,cachedCast01Location) < nRadius
				then
					return BOT_ACTION_DESIRE_HIGH, npcBot:GetLocation()
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityTojiko02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() or ability01:IsFullyCastable() or ability03:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability02:GetCastRange()
	local nRadius = 250
	local nTime = 0.75
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	local tableAllMapEnemyHeroes = CachedGetNearbyHeroes( npcBot, 99999, true, BOT_MODE_NONE )
	local locationAoE = CachedFindAoELocation( npcBot, 2, true, true, npcBot:GetLocation(), nCastRange, nRadius, nTime, 0 )
	local abilityBaseDamage = ability02:GetLevel()*60*1.35

	if #tableNearbyEnemyHeroes > 1 then
		if ( locationAoE.count > 0 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	elseif #tableNearbyEnemyHeroes > 0 then
		if CanCastTojiko02OnTarget(tableNearbyEnemyHeroes[1]) then
			if tableNearbyEnemyHeroes[1]:GetMovementDirectionStability() >= 0.75 then
				return BOT_ACTION_DESIRE_HIGH, tableNearbyEnemyHeroes[1]:GetExtrapolatedLocation(nTime)
			else
				return BOT_ACTION_DESIRE_HIGH, tableNearbyEnemyHeroes[1]:GetLocation()
			end
		end
	end
	if #tableAllMapEnemyHeroes > 0 and cachedCast02Location ~= 0 then
		for _, npcEnemy in pairs(tableAllMapEnemyHeroes) do
			if GetUnitToLocationDistance(npcEnemy,cachedCast02Location) < nRadius-50
			and CanCastTojiko02OnTarget(npcEnemy) then
				return BOT_ACTION_DESIRE_HIGH, npcBot:GetLocation()
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityTojiko03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability03:GetCastRange()
	local nRadius = 185
	local nTime = 0
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	local tableAllMapEnemyHeroes = CachedGetNearbyHeroes( npcBot, 99999, true, BOT_MODE_NONE )
	local locationAoE = CachedFindAoELocation( npcBot, 3, true, true, npcBot:GetLocation(), nCastRange, nRadius, nTime, 0 )
	local abilityBaseDamage = 40+ability03:GetLevel()*40

	if #tableNearbyEnemyHeroes > 1 then
		if ( locationAoE.count > 0 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	elseif #tableNearbyEnemyHeroes > 0 then
		if CanCastTojiko03OnTarget(tableNearbyEnemyHeroes[1]) then
			return BOT_ACTION_DESIRE_HIGH, tableNearbyEnemyHeroes[1]:GetLocation()
		end
	end
	if #tableAllMapEnemyHeroes > 0 and cachedCast03Location ~= 0 then
		for _, npcEnemy in pairs(tableAllMapEnemyHeroes) do
			if CanCastTojiko03OnTarget(npcEnemy) then
				local defense = CombatPower.GetDefenseSnapshot(npcEnemy)
				local rawDamage = defense ~= nil
					and math.max(0, abilityBaseDamage + 4 * defense.armor) * (1 + npcBot:GetSpellAmp())
					or nil
				local incomingDamage = rawDamage ~= nil
					and CombatPower.EstimateIncomingDamageFromSnapshot(defense, rawDamage, DAMAGE_TYPE_MAGICAL)
					or nil
				if incomingDamage ~= nil
				and defense.health < incomingDamage
				and GetUnitToLocationDistance(npcEnemy,cachedCast03Location) < nRadius
				then
					return BOT_ACTION_DESIRE_HIGH, npcBot:GetLocation()
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityTojiko04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability04:GetCastRange()
	local nRadius = 350
	local nDamage = 900
	local nTime = 1.2
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1400, true, BOT_MODE_NONE )
	local tableAllMapEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	local locationAoELowHP = CachedFindAoELocation( npcBot, 4, true, true, npcBot:GetLocation(), nCastRange, nRadius, nTime, nDamage*0.7 )
	if ( locationAoELowHP.count > 1 ) then
		return BOT_ACTION_DESIRE_HIGH, locationAoELowHP.targetloc
	end
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or IsRetreating(npcBot, 'ability_thdots_tojiko04'))
	then
		local locationAoE = CachedFindAoELocation( npcBot, 5, true, true, npcBot:GetLocation(), 1000, nRadius, nTime, 0 )
		if #tableNearbyEnemyHeroes > 1 then
			for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
			do
				if ( CanCastTojiko04OnTarget( npcEnemy ) and locationAoE.count >= 2)
				then
					return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
				end
			end
		end
	end

	if #tableAllMapEnemyHeroes > 0 then
		for _, npcEnemy in pairs(tableAllMapEnemyHeroes) do
			if CanCastTojiko04OnTarget(npcEnemy) then
				local defense = CombatPower.GetDefenseSnapshot(npcEnemy)
				local incomingDamage = CombatPower.EstimateIncomingDamageFromSnapshot(
					defense,
					nDamage,
					DAMAGE_TYPE_MAGICAL
				)
				if incomingDamage ~= nil and defense.health < incomingDamage then
					if npcEnemy:GetMovementDirectionStability() >= 0.75 then
						return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(nTime)
					else
						return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
					end
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityTojiko05()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability05:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 600, true, BOT_MODE_NONE )
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 450, false, BOT_MODE_NONE )

	if #tableNearbyEnemyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.4 and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend )
				)
				) then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
