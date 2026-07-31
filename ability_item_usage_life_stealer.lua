
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire,cast04Desire = 0,0
local ability01,ability04,cast04Target


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	local item_kafziel = IsItemAvailable( "item_kafziel" )
	local item_shield = IsItemAvailable( "item_esdw" ) or IsItemAvailable( "item_trinity" )

	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then
		--print("stun item exist")
		local castItemGhostDesire, castItemGhostTarget = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_ghost, castItemGhostTarget )
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

	if ( item_weijin~=nil and item_weijin:IsFullyCastable() )
	then
		--print("stun item exist")
		local castItemWeijinDesire = ConsiderItemWeiJin(item_weijin)
		if ( castItemWeijinDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_weijin )
			return
		end
	end
	if ( item_kafziel~=nil and item_kafziel:IsFullyCastable() )
	then
		local castItemKafzielDesire, castItemKafzielTarget = ConsiderItemKafziel( item_kafziel )
		if ( castItemKafzielDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_kafziel, castItemKafzielTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_rumia01" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_rumia04" )

	-- Consider using each ability
	cast01Desire = ConsiderAbilityRumia01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbility( ability01 )
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityRumia04()

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastRumia04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityRumia01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Fighting or Retreating 
	if ( IsRetreating(npcBot, 'ability_thdots_rumia01') or npcBot:GetActiveMode() == BOT_MODE_ATTACK )
	then
		-- Use ability before being catched ( Near By has enemy heros )
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1500, true, BOT_MODE_NONE )
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

----------------------------------------------------------------------------------------------------

function ConsiderAbilityRumia04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local item_ganggenier = IsItemAvailable( "item_ganggenier" )
	-- Get some of its values
	local nCastRange = ability04:GetCastRange()
	local nDamage = ability04:GetAbilityDamage()
	local nKafzielDamage = 270

	if item_ganggenier ~= nil then
		nDamage = nDamage*1.1
	end

	-- Can eat enemy hero
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 100 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastRumia04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
		then
			if (npcEnemy:HasModifier("modifier_item_kafziel_debuff") and nDamage + nKafzielDamage > npcEnemy:GetHealth())
			or nDamage > npcEnemy:GetHealth() then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
			end
		end
	end

	if npcBot:GetActiveMode() == BOT_MODE_LANING
	or npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP
	or npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID
	or npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT
	or npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP
	or npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID
	or npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT then
        local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(nCastRange + 450,true)
        if #tableNearbylanecreeps > 0 then
            local highestHP = 0
            local highestHPTarget
            for _,enemyCreep in pairs(tableNearbylanecreeps)
            do
                -- 先打旗手和炮车
                if IsKeyWordUnit("flagbearer",enemyCreep) or IsKeyWordUnit("siege",enemyCreep) then
                    highestHPTarget = enemyCreep
                    break
                -- 然后打远程兵
                elseif IsKeyWordUnit("ranged",enemyCreep) then
                    highestHPTarget = enemyCreep
                    break
                end
                -- 最后打血多的
                if enemyCreep:GetHealth() < highestHP and highestHPTarget:GetHealth()/highestHPTarget:GetMaxHealth() > 0.7 then
                    highestHP = enemyCreep:GetHealth()
                    highestHPTarget = enemyCreep
                end
            end
            if highestHPTarget ~= nil and CanCastRumia04OnTarget(highestHPTarget) then
                return BOT_ACTION_DESIRE_HIGH, highestHPTarget
            end
        end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

