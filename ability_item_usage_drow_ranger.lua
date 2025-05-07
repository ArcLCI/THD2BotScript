
require(GetScriptDirectory() ..  "/thd2_item_usage")

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

Cast01Desire = 0
Cast02Desire = 0
Cast03Desire = 0
Cast04Desire = 0

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	Ability01 = npcBot:GetAbilityByName( "ability_thdots_koishi01" )
	Ability04 = npcBot:GetAbilityByName( "ability_thdots_koishi04" )
	AbilityEx = npcBot:GetAbilityByName( "phantom_assassin_blur" )


	-- Consider using each ability
	Cast01Desire = ConsiderAbilityKoishi01()
	if ( Cast01Desire > 0 )
	then
		npcBot:Action_UseAbility( Ability01 )
		return
	end

	CastExDesire = ConsiderAbilityKoishiEx()
	if ( CastExDesire > 0 )
	then
		npcBot:Action_UseAbility( AbilityEx )
		return
	end

	Cast04Desire = ConsiderAbilityKoishi04()
	if ( Cast04Desire > 0 )
	then
		if ( AbilityEx ~= nil and AbilityEx:IsFullyCastable() )
		then
			npcBot:Action_UseAbility( AbilityEx )
		end

		npcBot:Action_UseAbility( Ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityKoishi01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( Ability01 == nil or not Ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE )
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
		if (#tableNearbyHeroes < 5 and #tableNearbyHeroes >= 2) then
			return BOT_ACTION_DESIRE_MODERATE
		elseif #tableNearbyHeroes < 3 then
			return BOT_ACTION_DESIRE_HIGH
		else
			return BOT_ACTION_DESIRE_NONE
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

function ConsiderAbilityKoishiEx()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( AbilityEx == nil or not AbilityEx:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT )
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

function ConsiderAbilityKoishi04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not Ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	TableNearbyEnemyHeroes1300 = CachedGetNearbyHeroes( npcBot, 1300, true, BOT_MODE_NONE )
	TableNearbyEnemyHeroes800 = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE )

	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT  )
	then
		local tableNearbyEnemyBarracks = npcBot:GetNearbyBarracks( 800, true )
		if #tableNearbyEnemyBarracks > 0 then
			if #TableNearbyEnemyHeroes1300 > 1 then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT )
	then
		if npcBot:GetHealth() > npcBot:GetMaxHealth() * 0.3 then
			if #TableNearbyEnemyHeroes800 >= 3 then
				return BOT_ACTION_DESIRE_MODERATE
			end
			for _,npcEnemy in pairs( TableNearbyEnemyHeroes800 )
			do
				if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
				then
					return BOT_ACTION_DESIRE_MODERATE
				end
			end
		end
	end

	if #TableNearbyEnemyHeroes1300 > 4 then
		return BOT_ACTION_DESIRE_MODERATE
	end
	if #TableNearbyEnemyHeroes800 > 3 then
		return BOT_ACTION_DESIRE_MODERATE
	end
	return BOT_ACTION_DESIRE_NONE

end

