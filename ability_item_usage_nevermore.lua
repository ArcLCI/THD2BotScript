
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast04Desire = 0
castExDesire = 0

tmp = 0

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_root = IsItemAvailable( "item_tentacle" )

	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
	end

end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_shizuha01" )
	ability04 = npcBot:GetAbilityByName( "tinker_march_of_the_machines_lua" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_shizuhaEXNew" )

	-- Consider using each ability

	cast01Desire, cast01Location = ConsiderAbilityShizuha01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast04Desire, cast04Location = ConsiderAbilityShizuha04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability04, cast04Location )
		return
	end

	castExDesire = ConsiderAbilityShizuhaEx()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( abilityEx )
		return
	end
end

----------------------------------------------------------------------------------------------------
function CanCastShizuha01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastShizuha04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityShizuha01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,0
	end

	local nCastRange = 550
	local nRadius = 150 + 25 * ability01:GetLevel()

	if npcBot:GetLevel() >= 15 then
		nRadius = 150 + 25 * ability01:GetLevel() + 150
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + nRadius - 50, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcBot:GetTarget() == npcEnemy and CanCastShizuha01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end

		if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
		then
			if ( CanCastShizuha01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
			end
		end
	end

	-- If we're going after someone
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY )
	then
		local npcTarget = npcBot:GetTarget()

		if ( npcTarget ~= nil )
		then
			if ( CanCastShizuha01OnTarget( npcTarget ) and not IsPossibleIllusion( npcTarget ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end

	if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK
		or npcBot:GetActiveMode() == BOT_MODE_GANK
		or npcBot:GetActiveMode() == BOT_MODE_RETREAT )
		and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		local locationAoE = CachedFindAoELocation( npcBot, 60001, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )
		if locationAoE.count > 1 then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end
	return BOT_ACTION_DESIRE_NONE,0

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityShizuha04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE,0
	end

	local nCastRange = 400
	local nRadius = 400

	if npcBot:HasModifier("modifier_item_wanbaochui") then
		nRadius = 800
	end

	if ((npcBot:GetActiveMode() == BOT_MODE_ATTACK
		or npcBot:GetActiveMode() == BOT_MODE_GANK
		or npcBot:GetActiveMode() == BOT_MODE_RETREAT )
		and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH ) then
		local locationAoE = CachedFindAoELocation( npcBot, 60001, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0 )
		if locationAoE.count > 1 then
			return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
		end
	end
	return BOT_ACTION_DESIRE_NONE,0

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityShizuhaEx()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if not npcBot:HasModifier("modifier_item_wanbaochui")
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nDamage = 75 + 9 * ability01:GetLevel()

	for _,Enemy in pairs (GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if ( Enemy~=nil )
		then
			if ( Enemy:IsAlive() and CanCastShizuha04OnTarget(Enemy) )
			then
				if ( Enemy:GetHealth() < nDamage )
				then
					return BOT_ACTION_DESIRE_VERYHIGH
				end
			end

		end
	end
	return BOT_ACTION_DESIRE_NONE
end