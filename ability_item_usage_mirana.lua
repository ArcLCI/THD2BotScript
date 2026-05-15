
require(GetScriptDirectory() ..  "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

----------------------------------------------------------------------------------------------------

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_king = IsItemAvailable( "item_horse_king")

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

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	--ability01 = npcBot:GetAbilityByName( "ability_thdots_reisenOld01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_reisenOld02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_reisenOld03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_reisenOld04" )

	-- Consider using each ability
	cast02Desire = ConsiderAbilityReisen02()
	if ( cast02Desire > 0 )
	then
		J.ClearActionsThrottled(npcBot, 'mirana_cast', false, 0.6)
		J.QueueUseAbilityThrottled(npcBot, 'mirana_queue_cast02', ability02, 0.6)
		return
	end

	cast03Desire, cast03Location = ConsiderAbilityReisen03()
	if ( cast03Desire > 0 )
	then
		J.ClearActionsThrottled(npcBot, 'mirana_cast_location', true, 0.6)
		J.QueueUseAbilityOnLocationThrottled(npcBot, 'mirana_queue_cast03', ability03, cast03Location, 0.6, 180)
		return
	end

	cast04Desire = ConsiderAbilityReisen04()

	if ( cast04Desire > 0 )
	then
		J.ClearActionsThrottled(npcBot, 'mirana_cast', false, 0.6)
		J.QueueUseAbilityThrottled(npcBot, 'mirana_queue_cast04', ability04, 0.6)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastReisen03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityReisen02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	-- as bot has mana buff and could multi controll perfectly
	-- bot should just use this as much as possible
	return BOT_ACTION_DESIRE_HIGH
end

function ConsiderAbilityReisen03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability03:GetCastRange()
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastReisen03OnTarget( npcEnemy ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(1)
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

function ConsiderAbilityReisen04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Fighting or Retreating with hero
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE ) -- attack range is better, wait for api :p
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

