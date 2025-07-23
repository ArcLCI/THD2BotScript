
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast03Desire = 0
local cast04Desire = 0

local ability01,ability02,ability04,cast01Target

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	local item_dragon_star = IsItemAvailable( "item_dragon_star" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or IsItemAvailable( "item_brother_sharp" )
	local item_teeth = IsItemAvailable( "item_teeth" )

	local item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end

	if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 450, false, BOT_MODE_NONE )
        if (npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and #tableNearbyFriendlyHeroes > 0) or IsSeriouslyRetreating(npcBot) then
            npcBot:Action_UseAbility(item_dragon_star)
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

	if (item_teeth~=nil and item_teeth:IsFullyCastable()) then
		if not ability01:IsFullyCastable()
		and not ability04:IsFullyCastable()
		and (npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH) then
			npcBot:Action_UseAbility( item_teeth )
			return
		end
	end

	if ( item_horse_red~=nil and item_horse_red:IsFullyCastable() )
	then
		local castItemHorseGreenDesire = ConsiderItemHorseRed(item_horse_red)
		if ( castItemHorseGreenDesire > 0 )
		then
			npcBot:Action_UseAbility(item_horse_red)
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
end

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()


	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_reisen_2_01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_reisen_2_02" )
	-- ability04 = npcBot:GetAbilityByName( "ability_thdots_reisen_2_04" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_reisen_2_ultimate" )

	-- Consider using each ability

	cast01Desire, cast01Target = ConsiderAbilityReisen_2_01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire = ConsiderAbilityReisen_2_02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02 )
		return
	end

	cast04Desire = ConsiderAbilityReisen_2_04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastReisen_2_01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable() and not IsPossibleIllusion(npcTarget)
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityReisen_2_01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability01:GetCastRange() + 50

	if ( (npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			npcBot:GetActiveMode() == BOT_MODE_RETREAT )
			and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		return BOT_ACTION_DESIRE_HIGH, npcBot
	end

	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	if #tableNearbyFriendlyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend,true)
				) then
				return BOT_ACTION_DESIRE_HIGH, npcBot
			end
		end
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and not IsPossibleIllusion( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcBot
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityReisen_2_02()

	local npcBot = GetBot()
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800 , true, BOT_MODE_NONE )
	local tableNearby600EnemyHeroes = CachedGetNearbyHeroes( npcBot, 600 , true, BOT_MODE_NONE )

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	-- 没盾
	if not npcBot:HasModifier( "modifier_ability_thdots_reisen2_02_buff_damageReduction" ) then
		-- 20%血以下
		if npcBot:GetHealth() < npcBot:GetMaxHealth()*0.2 then
			return BOT_ACTION_DESIRE_HIGH
		end
		-- 50%血以下 或 被眩晕 且周围有人
		if npcBot:GetHealth() < npcBot:GetMaxHealth()*0.5 or GetModifiersTimeLeft(npcBot, ModifierNamesStun) > 0.5 then
			if #tableNearbyEnemyHeroes > 0 then
				return BOT_ACTION_DESIRE_HIGH
			end
		end

		if #tableNearby600EnemyHeroes > 2
		and npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
			return BOT_ACTION_DESIRE_HIGH
		end
	else
	-- 有盾
		-- 50%血以下 且 被眩晕 且 周围有人
		if npcBot:GetHealth() < npcBot:GetMaxHealth()*0.5 and GetModifiersTimeLeft(npcBot, ModifierNamesStun) > 0.5 then
			if #tableNearbyEnemyHeroes > 0 then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------
function ConsiderAbilityReisen_2_04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 400 , true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes > 1 then
			return BOT_ACTION_DESIRE_HIGH
		else
			for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
			do
				if (GetCapability(npcEnemy) > GetCapability(npcBot) or npcBot:GetHealth() < npcEnemy:GetHealth()) and CanCastReisen_2_01OnTarget(npcEnemy) then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
