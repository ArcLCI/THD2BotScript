
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire,cast02Desire,castFantasyDesire,cast04Desire = 0,0,0,0
local ability01,ability02,abilityFantasy,ability04,cast01Location,cast02Target,castFantasyLocation

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	local item_dragon_star = IsItemAvailable( "item_dragon_star" )
	local item_blue = IsItemAvailable("item_yatagarasu") or IsItemAvailable("item_yueyaomishi")

	if (item_blue~=nil and item_blue:IsFullyCastable())
	then
		local castItemBlueDesire = ConsiderItemBlue(item_blue)
		if ( castItemBlueDesire > 0 )
		then
			npcBot:Action_UseAbility(item_blue)
			return
		end
	end
	if ( item_stun~=nil and item_stun:IsFullyCastable() )
	then
		--print("stun item exist")
		local castItemStunDesire, castItemStunTarget = ConsiderItemStun(item_stun)
		if ( castItemStunDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_stun, castItemStunTarget )
			return
		end
	end
	if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
        local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 450, false, BOT_MODE_NONE )
        if (npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and #tableNearbyFriendlyHeroes > 0) or IsSeriouslyRetreating(npcBot) then
            npcBot:Action_UseAbility(item_dragon_star)
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_aya01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_aya02" )
	abilityFantasy = npcBot:GetAbilityByName( "aya_fantasy" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_aya04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityAya01()
	if ( cast01Desire > 0 ) then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityAya02()
	if ( cast02Desire > 0 ) then
		npcBot:Action_UseAbilityOnEntity( ability02 , cast02Target)
		return
	end

	castFantasyDesire, castFantasyLocation = ConsiderAbilityAyaFantasy()
	if castFantasyDesire > 0 then
		npcBot:Action_UseAbilityOnLocation( abilityFantasy, castFantasyLocation )
		return
	end


	cast04Desire = ConsiderAbilityAya04()

	if ( cast04Desire > 0 ) then
		npcBot:Action_UseAbility( ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastAya01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true, { allowMagicImmune = true })
end

function CanCastAya02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

function CanCastAya04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false, { allowMagicImmune = true })
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityAya01()

	local npcBot = GetBot()

	if not ability01:IsFullyCastable() or IsYugi04NoDisplacementActive(npcBot) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nLevel = ability01:GetLevel()
	local nCastRange = 300*nLevel + 300
	local nDamage = 50*nLevel + 30
	local nRadius = 200
	local nAheadDis = 0
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100, true, BOT_MODE_NONE )
		local locationAoE = CachedFindAoELocation(npcBot, 1, true, true, npcBot:GetLocation(), nCastRange - 200, nRadius, 0, 0)
		if npcBot:HasModifier("modifier_thdots_aya04_blink") and locationAoE.count >0 then
			nAheadDis = 300
			local vAhead = (locationAoE.targetloc - npcBot:GetLocation())/GetUnitToLocationDistance(npcBot,locationAoE.targetloc)
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc + (vAhead * nAheadDis)
		end
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if npcBot:GetTarget() == npcEnemy and CanCastAya01OnTarget(npcEnemy) then
				nAheadDis = 175
				local vAhead = (npcEnemy:GetLocation() - npcBot:GetLocation())/GetUnitToUnitDistance(npcEnemy,npcBot)
				if npcBot:HasModifier("modifier_thdots_aya04_blink") then
					nAheadDis = 350
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation() + (vAhead * nAheadDis)
				end
				if GetHP(npcEnemy) < 0.25 and math.abs(npcEnemy:GetFacing() - npcBot:GetFacing()) < 45 then
					local vEnemyFacing = Vector(math.sin(math.rad(npcEnemy:GetFacing())),math.cos(math.rad(npcEnemy:GetFacing())))
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation() + (vEnemyFacing * nAheadDis)
				end
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation() + (vAhead * nAheadDis)
			end
		end
	end

	if (IsSeriouslyRetreating(npcBot) and not npcBot:HasModifier("modifier_fountain_aura_buff")) then
		local v_home = GetAncient(npcBot:GetTeam()):GetLocation()
		local v_target = ( v_home - npcBot:GetLocation() ) / GetUnitToLocationDistance( npcBot, v_home)
		local v_final = npcBot:GetLocation() + v_target * nCastRange
		return BOT_ACTION_DESIRE_HIGH, v_final
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

function ConsiderAbilityAyaFantasy()
	local npcBot = GetBot()
	local nCastRange = 1200
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	local tableTrueHeros = {}
	if not abilityFantasy:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	for _, npcEnemy in pairs(tableNearbyEnemyHeroes) do
		if not IsPossibleIllusion(npcEnemy) then
			table.insert(tableTrueHeros, npcEnemy)
		end
	end

	if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and #tableTrueHeros > 2 then
		local vLocation = GetCenterOfUnits(tableTrueHeros)
		if GetUnitToLocationDistance(npcBot,vLocation) < 900 then
			return BOT_ACTION_DESIRE_HIGH, vLocation
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityAya04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- If we're seriously retreating, or attack
	if IsSeriouslyRetreating(npcBot) then
		return BOT_ACTION_DESIRE_MODERATE
	end

	-- If we're seriously retreating, or attack
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_VERYHIGH )
	then
		return BOT_ACTION_DESIRE_MODERATE
	end

	return BOT_ACTION_DESIRE_NONE

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityAya02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability02:GetCastRange()

	-- If we're seriously attacking
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastAya02OnTarget( npcEnemy ) then
				if ( not npcEnemy:HasModifier("modifier_thdots_aya02_buff") )
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy
				else
					local mf_index = npcEnemy:GetModifierByName("modifier_thdots_aya02_buff")
					if( npcEnemy:GetModifierRemainingDuration(mf_index) < 4.0 ) then
						return BOT_ACTION_DESIRE_MODERATE, npcEnemy
					end
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
