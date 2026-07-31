
require(GetScriptDirectory() ..  "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

----------------------------------------------------------------------------------------------------

local cast01Desire, cast02Desire, cast02BackDesire, cast03Desire, cast04Desire = 0, 0, 0, 0, 0
local ability01, ability02, ability03, ability04, cast01Target, cast02Location, cast04Target
local ability02LocationCache = 0
local cast03ToggleState


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	local item_root = IsItemAvailable( "item_tentacle" )
	local item_rocket = IsItemAvailable( "item_rocket" )
	or IsItemAvailable( "item_rocket_2" )
	or IsItemAvailable( "item_rocket_3" )
	or IsItemAvailable( "item_rocket_4" )
	or IsItemAvailable( "item_rocket_5" )

	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		local castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
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

	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then
		local castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget )
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
	ConsiderNeutralItems()


	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_sagume_1" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_sagume_2" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_sagume_3" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_sagume_4" )
	cast03ToggleState = ability03:GetAutoCastState()

	-- Consider using each ability

	cast01Desire, cast01Target = ConsiderAbilitySagume01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end

	cast02Desire, cast02Location, cast02BackDesire = ConsiderAbilitySagume02()
	if cast02Desire > 0 and cast02BackDesire > 0 then
		if not J.ClearActionsThrottled(npcBot, 'sagume_cast02_back', false, 0.8) then return end
		J.QueueUseAbilityOnLocationThrottled(npcBot, 'sagume_queue_cast02_back_loc', ability02, cast02Location, 0.8, 160)
		npcBot:ActionQueue_Delay(0.4)
		J.QueueUseAbilityThrottled(npcBot, 'sagume_queue_cast02_back', ability02, 0.8)
		return
	elseif cast02Desire > 0 then
		npcBot:Action_UseAbilityOnLocation(ability02, cast02Location)
	end

	cast03Desire = ConsiderAbilitySagume03()
	if cast03Desire >= BOT_ACTION_DESIRE_HIGH and not cast03ToggleState then
		ability03:ToggleAutoCast()
		return
	elseif cast03Desire == 0 and cast03ToggleState then
		ability03:ToggleAutoCast()
		return
	end

	cast04Desire, cast04Target = ConsiderAbilitySagume04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastSagume01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, true)
end

function CanCastSagume03OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

function CanCastSagume04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, true)
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySagume01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability01:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastSagume01OnTarget(npcEnemy) then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySagume02()

	local npcBot = GetBot()

	if not ability02:IsFullyCastable() or IsYugi04NoDisplacementActive(npcBot) then
		return BOT_ACTION_DESIRE_NONE, 0, BOT_ACTION_DESIRE_NONE
	end

	-- Get some of its values
	local nCastRange = ability02:GetCastRange()
	local nRadius = 600
	if npcBot:GetLevel() >= 20 then
		ability02LocationCache = npcBot:GetLocation()
		local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0)
		if ( locationAoE.count > 2 ) then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc, BOT_ACTION_DESIRE_HIGH
		end
	end

	if not npcBot:HasModifier("modifier_ability_sagume_telent7_check") then
		if npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
			local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
			for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
			do
				if (npcBot:GetTarget() == npcEnemy and CanCastSagume01OnTarget(npcEnemy)
            	and (npcEnemy:GetHealth() < 320 or GetHP(npcEnemy) < 0.15 )) then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation(), BOT_ACTION_DESIRE_NONE
				elseif npcBot:GetTarget() == npcEnemy and CanCastSagume01OnTarget(npcEnemy)
				and GetUnitToUnitDistance(npcBot,npcEnemy) < 600 then
					local midPoint = (npcBot:GetLocation() - npcEnemy:GetLocation())/2
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation() + midPoint, BOT_ACTION_DESIRE_NONE
				end
			end
		end

		if IsSeriouslyRetreating(npcBot, 'ability_thdots_sagume_2') then
			return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME), BOT_ACTION_DESIRE_NONE
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0, BOT_ACTION_DESIRE_NONE
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySagume03()

	local npcBot = GetBot()
	local toggleState = ability03:GetAutoCastState()

	-- Make sure it's castable
	if not ability03:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end

	if not toggleState and npcBot:GetMana()/npcBot:GetMaxMana() > 0.25 then
		return BOT_ACTION_DESIRE_HIGH
	elseif toggleState and npcBot:GetMana()/npcBot:GetMaxMana() < 0.25 then
		return BOT_ACTION_DESIRE_NONE
	end

	return BOT_ACTION_DESIRE_MODERATE
end
----------------------------------------------------------------------------------------------------
function ConsiderAbilitySagume04()

	local npcBot = GetBot()
	local item_rocket = IsItemAvailable( "item_rocket" )
	or IsItemAvailable( "item_rocket_2" )
	or IsItemAvailable( "item_rocket_3" )
	or IsItemAvailable( "item_rocket_4" )
	or IsItemAvailable( "item_rocket_5" )

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	--简易版
	if (not ability01:IsFullyCastable()) and item_rocket ~= nil and (not item_rocket:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_HIGH, npcBot
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
