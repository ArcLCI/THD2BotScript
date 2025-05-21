
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast03Desire = 0
local cast04Desire = 0
local castExDesire = 0
local castEx2Desire = 0

local nNextPlantingTime = 0

local ability01,ability02,ability03,ability04,abilityEx,abilityEx2,
    cast02Target,cast03Location,cast04Target,castEx2Target

function MyItemUsageThink()
    local npcBot = GetBot()

    if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

    local item_dragon_star = IsItemAvailable( "item_dragon_star" )
    local item_root = IsItemAvailable( "item_morenjingjuan" )
	if item_root == nil then
		item_root = IsItemAvailable( "item_tentacle" )
	end
    local item_rand_jump = IsItemAvailable( "item_9ball" )
    local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )

    if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then
		local castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget)
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
    if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
        if IsSeriouslyRetreating(npcBot) then
            npcBot:Action_UseAbility(item_dragon_star)
            return
        end
	end
end

function AbilityUsageThink()
    if not IsBotAwake() then return end

	MyItemUsageThink()

    local npcBot = GetBot()

    if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

    local item_dragon_star = IsItemAvailable( "item_dragon_star" )

    ability01 = npcBot:GetAbilityByName( "ability_thdots_yuuka01" )
    ability02 = npcBot:GetAbilityByName( "ability_thdots_yuuka02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_yuuka03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_yuuka04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_YuukaEx" )
    abilityEx2 = npcBot:GetAbilityInSlot(4)

    cast01Desire = ConsiderAbilityYuuka01()
	if cast01Desire > 0 then
		npcBot:Action_UseAbility(ability01)
		return
	end

    cast02Desire, cast02Target = ConsiderAbilityYuuka02()
	if cast02Desire > 0 then
		npcBot:Action_UseAbilityOnEntity(ability02, cast02Target)
		return
	end

    cast03Desire, cast03Location = ConsiderAbilityYuuka03()
	if cast03Desire > 0 then
		npcBot:Action_UseAbilityOnLocation(ability03, cast03Location)
		return
	end

    cast04Desire, cast04Target = ConsiderAbilityYuuka04()
	if cast04Desire > 0 then
		npcBot:Action_UseAbilityOnEntity(ability04, cast04Target)
		return
	end

    castExDesire = ConsiderAbilityYuukaEx()
	if castExDesire > 0 then
		npcBot:Action_UseAbility(abilityEx)
        nNextPlantingTime = DotaTime() + 5
		return
	end

    castEx2Desire, castEx2Target = ConsiderAbilityYuukaEx2()
	if castEx2Desire > 0 and castEx2Target ~= nil then
        print(castEx2Target)
        print(castEx2Target:GetUnitName())
        if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
            npcBot:Action_UseAbility(item_dragon_star)
        end
		npcBot:Action_UseAbilityOnEntity(abilityEx2, castEx2Target)
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastYuuka01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsInvulnerable() and not IsPossibleIllusion(npcTarget)
end

function CanCastYuuka02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable() and not IsPossibleIllusion(npcTarget)
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYuuka01()
    local npcBot = GetBot()
    local nRadius = 150 + (25 * ability01:GetLevel())

    if (not ability01:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE
	end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nRadius, true, BOT_MODE_NONE)

    if #tableNearbyEnemyHeroes > 0 and npcBot:GetActiveMode() == BOT_MODE_ATTACK then
        for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastYuuka01OnTarget(npcEnemy) then
	    		return BOT_ACTION_DESIRE_HIGH
	    	end
    	end
    end

    return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYuuka02()
    local npcBot = GetBot()
    local nCastRange = ability02:GetCastRange()

    if (not ability02:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange + 200, true, BOT_MODE_NONE)

    if #tableNearbyEnemyHeroes > 0 then
        for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastYuuka02OnTarget(npcEnemy) then
	    		return BOT_ACTION_DESIRE_HIGH, npcEnemy
	    	end
    	end
    end

    return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYuuka03()
    local npcBot = GetBot()
    local nRadius = 800
    local nCastRange = ability03:GetCastRange()
    local flowers = {}

    if (not ability03:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

    for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
        if ally:GetUnitName() == "ability_yuuka_flower" and GetUnitToUnitDistance(npcBot,ally) <= (nRadius / 2) + nCastRange then
            table.insert(flowers,ally)
        end
    end

    if npcBot:GetActiveMode() == BOT_MODE_ATTACK and #flowers >= 5 then
        return BOT_ACTION_DESIRE_HIGH, GetCenterOfUnits(flowers)
    end

    return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYuuka04()
    local npcBot = GetBot()
    local nCastRange = ability04:GetCastRange()

    if (not ability04:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

    if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
        local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange, true, BOT_MODE_NONE)
        for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastYuuka02OnTarget(npcEnemy) and npcBot:GetTarget() == npcEnemy then
                local targetFlower, range = GetNearestFlower(npcEnemy)
                if range < 200 then
	    		    return BOT_ACTION_DESIRE_HIGH, targetFlower
                end
	    	end
    	end
    end

    return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYuukaEx()
    local npcBot = GetBot()
    local flowerCount = npcBot:GetModifierStackCount(npcBot:GetModifierByName("modifier_thdots_yuukaex_flower_buff"))
    local maxFlowerCount = 5
    local flowersIn2400Range = {}
    local flowersIn4800Range = {}

    if (not abilityEx:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE
	end

    if npcBot:GetActiveMode() == BOT_MODE_ATTACK or
        npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT then
        if flowerCount < maxFlowerCount then
            for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
            do
                if ally:GetUnitName() == "ability_yuuka_flower" and GetUnitToUnitDistance(npcBot,ally) <= 2400 then
                    table.insert(flowersIn2400Range,ally)
                end
            end
            if #flowersIn2400Range < maxFlowerCount then
                return BOT_ACTION_DESIRE_HIGH
            end
        end
    else
        if flowerCount < maxFlowerCount then
            for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
            do
                if ally:GetUnitName() == "ability_yuuka_flower" and GetUnitToUnitDistance(npcBot,ally) <= 4800 then
                    table.insert(flowersIn4800Range,ally)
                end
            end
            if #flowersIn4800Range < maxFlowerCount and nNextPlantingTime <= DotaTime() then
                return BOT_ACTION_DESIRE_HIGH
            end
        end
    end
    return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYuukaEx2()
    local npcBot = GetBot()
    local nCastRange = abilityEx2:GetCastRange()
    local vFountain = GetShopLocation(npcBot:GetTeam(),SHOP_HOME)

    if (not abilityEx2:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

    if IsSeriouslyRetreating(npcBot) then
        local nFarthestFlower, nMaxRange = GetFarthestFlowerWithinRange(npcBot, nCastRange + 300)
        local nClosestFlower, nFountainMinRange, nFlowerRange = GetClosestFlowerToFountain(npcBot, nCastRange + 300)
        if nClosestFlower ~= nil then
            if nFlowerRange > 500 or (nFarthestFlower ~= nil and nFountainMinRange + 300 < GetUnitToLocationDistance(nFarthestFlower,vFountain)) then
                print("choose to fountain")
                print(nClosestFlower)
                return BOT_ACTION_DESIRE_HIGH, nClosestFlower
            elseif nFarthestFlower ~= nil and nMaxRange > 600 then
                print("choose farthest")
                print(nFarthestFlower)
                return BOT_ACTION_DESIRE_HIGH, nFarthestFlower
            end
        end
        return BOT_ACTION_DESIRE_NONE, nil
    end

    if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
        local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange, true, BOT_MODE_NONE)

        if #tableNearbyEnemyHeroes > 0 then
            for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	        do
	    	    if CanCastYuuka02OnTarget(npcEnemy) and npcBot:GetTarget() == npcEnemy and (npcEnemy:IsStunned() or npcEnemy:GetHealth() < 320 or GetHP(npcEnemy) < 0.15 ) then
                    if npcBot:HasModifier("modifier_item_wanbaochui") then
                        return BOT_ACTION_DESIRE_HIGH, npcEnemy
                    end
                    local nNearestFlower, nMinRange = GetNearestFlower(npcEnemy)
                    if nNearestFlower ~= nil and GetUnitToUnitDistance(npcBot,npcEnemy) > nMinRange then
                        print("choose target")
                        print(nNearestFlower)
                        return BOT_ACTION_DESIRE_HIGH, nNearestFlower
                    end
	    	    end
    	    end
        end
        return BOT_ACTION_DESIRE_NONE, nil
    end
    return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function GetNearestFlower(nTarget)
    local nMinRange = 99999
    local nNearestFlower = nil

    for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
        if ally:GetUnitName() == "ability_yuuka_flower" and GetUnitToUnitDistance(nTarget,ally) <= nMinRange then
            nMinRange = GetUnitToUnitDistance(nTarget,ally)
            nNearestFlower = ally
        end
    end
    return nNearestFlower, nMinRange
end

function GetFarthestFlowerWithinRange(nTarget, nRange)
    local nMaxRange = 0
    local nFarthestFlower = nil

    for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
        if ally:GetUnitName() == "ability_yuuka_flower" and GetUnitToUnitDistance(nTarget,ally) <= nRange and GetUnitToUnitDistance(nTarget,ally) >= nMaxRange then
            nMaxRange = GetUnitToUnitDistance(nTarget,ally)
            nFarthestFlower = ally
        end
    end
    return nFarthestFlower, nMaxRange
end

function GetClosestFlowerToFountain(nTarget, nRange)
    local nFountainMinRange = 99999
    local nFlowerRange = 0
    local nClosestFlower = nil
    local vFountain = GetShopLocation(nTarget:GetTeam(),SHOP_HOME)

    for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
        if ally:GetUnitName() == "ability_yuuka_flower" and GetUnitToUnitDistance(nTarget,ally) <= nRange and GetUnitToLocationDistance(ally,vFountain) <= nFountainMinRange then
            nFountainMinRange = GetUnitToLocationDistance(ally,vFountain)
            nClosestFlower = ally
            nFlowerRange = GetUnitToUnitDistance(nTarget,ally)
        end
    end
    return nClosestFlower, nFountainMinRange, nFlowerRange
end