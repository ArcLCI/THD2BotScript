
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_stand = IsItemAvailable( "item_dummy_doll1" )

	if ( item_stand~=nil and item_stand:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemStandDesire = ConsiderItemStand( item_stand )
		if ( castItemStandDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_stand )
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
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "earthshaker_fissure" )
	ability04 = npcBot:GetAbilityByName( "zuus_thundergods_wrath" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityTenshi01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

	cast04Desire = ConsiderAbilityTenshi04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04 )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastTenshi01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastTenshi04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityTenshi01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nCastRange = ability01:GetCastRange()
	local nDamage = 30*ability01:GetLevel()+30

	if ability04:IsFullyCastable() then  -- ulti ready
		nDamage = nDamage + 100*ability04:GetLevel()+50 - 30  --( one tick hp+ < 30 )
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastTenshi01OnTarget(npcEnemy) and not IsPossibleIllusion( npcEnemy ))
		then
			if ( npcEnemy:GetHealth() < nDamage )
			then
				return BOT_ACTION_DESIRE_VERYHIGH, npcEnemy:GetLocation()
			end


		end
	end

	-- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH )
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
			then
				if ( CanCastTenshi01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
				end
			end
		end
	end

	-- If we're seriously attacking
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH )
	then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetTarget() == npcEnemy )
			then
				if ( CanCastTenshi01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
				then
					return BOT_ACTION_DESIRE_MODERATE, npcEnemy:GetLocation()
				end
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
			if ( CanCastTenshi01OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

function ConsiderAbilityTenshi04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nDamage = 100*ability04:GetLevel()+50

	for _,Enemy in pairs (GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if ( Enemy~=nil )
		then
			if ( Enemy:IsAlive() and CanCastTenshi04OnTarget(Enemy) and not IsPossibleIllusion( Enemy ))
			then
				if ( Enemy:GetHealth() < nDamage )
				then
					return BOT_ACTION_DESIRE_VERYHIGH
				end
			end

			local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( Enemy, 600, true, BOT_MODE_NONE )
			local eps_damage = nDamage
			if tableNearbyEnemyHeroes ~= nil then
				eps_damage = eps_damage + #tableNearbyEnemyHeroes * nDamage
			end
			if ( eps_damage > Enemy:GetHealth() ) then
				return BOT_ACTION_DESIRE_VERYHIGH
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

