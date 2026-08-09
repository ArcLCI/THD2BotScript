local heroName = string.gsub(GetBot():GetUnitName(),"npc_dota_hero_","")

require(GetScriptDirectory() ..  "/thd2_item_usage")
require(GetScriptDirectory() ..  "/item_purchase_" .. heroName)

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast03Desire = 0
local cast04Desire = 0
local castExDesire = 0

local ability01,ability02,ability03,ability04,abilityEx,
    cast01Target,cast02Target,cast03Location,cast04Location

local lilyInitRoll = false
local lilyInitRollResult = RandomInt(1,3)
local lilyModeEnum = {WHITE = 1, GREY1 = 2, GREY2 = 3}
local lilyMode = 0
local lilyStatus = false

local function GetVisibleHealth(unit)
    if not SafeCanBeSeen(unit) then return nil, nil end
    local health = unit:GetHealth()
    local maxHealth = unit:GetMaxHealth()
    if maxHealth == nil or maxHealth <= 0 then return nil, nil end
    return health, maxHealth
end

function MyItemUsageThink()
    local npcBot = GetBot()

    if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_fan = IsItemAvailable("item_fan")
    local item_horse_red = IsItemAvailable("item_horse_red")
	local item_horse_king = IsItemAvailable("item_horse_king")
    local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
						IsItemAvailable( "item_jiao_shou" )
    local item_qijizhixing = IsItemAvailable( "item_qijizhixing" ) or IsItemAvailable( "item_tuzhushen" )

    if ( item_fan~=nil and item_fan:IsFullyCastable() )
	then
		local castItemFanDesire, castItemFanTarget = ConsiderItemFan(item_fan)
		if ( castItemFanDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_fan, castItemFanTarget)
			return
		end
	end

    if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then
		local castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow(item_slow)
		if ( castItemSlowDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end


    if ( item_qijizhixing~=nil and item_qijizhixing:IsFullyCastable() )
	then
		local castItemQiJjZhiXingDesire, castItemQiJjZhiXingTarget = ConsiderItemQiJiZhiXing(item_qijizhixing)
		if ( castItemQiJjZhiXingDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_qijizhixing, castItemQiJjZhiXingTarget )
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
    -- 莉莉白随机模式
    if not lilyInitRoll then
        lilyInitRoll = true
        lilyMode = lilyInitRollResult
        print("lilyInitRollResult")
        print(lilyInitRollResult)
    end

    if not IsBotAwake() then return end
    local npcBot = GetBot()

    lilyStatus = npcBot:HasModifier("modifier_lily_black")

	MyItemUsageThink()
	ConsiderNeutralItems()


    if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

    ability01 = npcBot:GetAbilityByName( "ability_thdots_lily01" )
    ability02 = npcBot:GetAbilityByName( "ability_thdots_lily02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_lily03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_lily04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_lily05" )

    cast01Desire, cast01Target = ConsiderAbilityLily01()
	if cast01Desire > 0 then
		npcBot:Action_UseAbilityOnEntity(ability01, cast01Target)
		return
	end

    cast02Desire, cast02Target = ConsiderAbilityLily02()
	if cast02Desire > 0 then
		npcBot:Action_UseAbilityOnEntity(ability02, cast02Target)
		return
	end

    cast03Desire, cast03Location = ConsiderAbilityLily03()
	if cast03Desire > 0 then
		npcBot:Action_UseAbilityOnLocation(ability03, cast03Location)
		return
	end

    cast04Desire, cast04Location = ConsiderAbilityLily04()
	if cast04Desire > 0 then
		npcBot:Action_UseAbilityOnLocation(ability04, cast04Location)
		return
	end

    castExDesire = ConsiderAbilityLilyEx()
	if castExDesire > 0 then
		npcBot:Action_UseAbility(abilityEx)
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastLily01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

function CanCastLily02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLilyEx()
    if (not abilityEx:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE
	end

    if lilyMode == lilyModeEnum.WHITE and lilyStatus then
        return BOT_ACTION_DESIRE_HIGH
    elseif lilyMode == lilyModeEnum.BLACK and not lilyStatus then
        return BOT_ACTION_DESIRE_HIGH
    elseif lilyMode == lilyModeEnum.GREY1 or lilyMode == lilyModeEnum.GREY2 then
        return BOT_ACTION_DESIRE_HIGH
    end
    return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLily01()
    local npcBot = GetBot()
    local nCastRange = ability01:GetCastRange()

    if (not ability01:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

    if lilyStatus and GetHP(npcBot) > 0.35 then
        local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, true, BOT_MODE_NONE )
        if #tableNearbyEnemyHeroes > 0 then
            local lowestHP = 99999
            local lowestHPTarget
            for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		    do
                if CanCastLily01OnTarget(npcEnemy) and npcEnemy:GetHealth() <= lowestHP then
                    lowestHP = npcEnemy:GetHealth()
                    lowestHPTarget = npcEnemy
			    end
            end
            return BOT_ACTION_DESIRE_HIGH, lowestHPTarget
        end
    elseif not lilyStatus then
        local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange + 200, false, BOT_MODE_NONE )
	    if #tableNearbyFriendlyHeroes > 0 then
            local lowestHP = 99999
            local lowestHPTarget
		    for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		    do
                if CanCastLily02OnTarget(npcFriend) and not IsPossibleIllusion(npcFriend) and npcFriend:GetHealth() <= lowestHP then
                    lowestHP = npcFriend:GetHealth()
                    lowestHPTarget = npcFriend
                end
		    end
            if GetHP(lowestHPTarget) < 0.8 then
                return BOT_ACTION_DESIRE_HIGH, lowestHPTarget
            end
	    end
    end

    return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLily02()
    local npcBot = GetBot()
    local nCastRange = ability02:GetCastRange()

    if (not ability02:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

    if lilyStatus and GetHP(npcBot) > 0.2 then
        local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(nCastRange + 200,true)
        if #tableNearbylanecreeps > 0 then
            local highestHP = 0
            local highestHPTarget
            for _,enemyCreep in pairs(tableNearbylanecreeps)
            do
                local enemyHealth = GetVisibleHealth(enemyCreep)
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
                if enemyHealth ~= nil and highestHPTarget ~= nil then
                    local targetHealth, targetMaxHealth = GetVisibleHealth(highestHPTarget)
                    if targetHealth ~= nil and enemyHealth < highestHP
                        and targetHealth / targetMaxHealth > 0.7 then
                        highestHP = enemyHealth
                        highestHPTarget = enemyCreep
                    end
                end
            end
            if highestHPTarget ~= nil and CanCastLily02OnTarget(highestHPTarget) then
                return BOT_ACTION_DESIRE_HIGH, highestHPTarget
            end
        end
    elseif not lilyStatus then
        local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(nCastRange + 200,false)
        if #tableNearbylanecreeps > 0 then
            local lowestHP = 99999
            local lowestHPTarget
            for _,friendlyCreep in pairs(tableNearbylanecreeps)
            do
                local friendlyHealth, friendlyMaxHealth = GetVisibleHealth(friendlyCreep)
                -- 先奶旗手或者炮车
                if (IsKeyWordUnit("flagbearer",friendlyCreep) or IsKeyWordUnit("siege",friendlyCreep))
                and friendlyHealth ~= nil and friendlyHealth / friendlyMaxHealth < 0.4 then
                    lowestHPTarget = friendlyCreep
                    break
                end
                -- 然后奶血少的
                if friendlyHealth ~= nil and friendlyHealth < lowestHP then
                    lowestHP = friendlyHealth
                    lowestHPTarget = friendlyCreep
                end
            end
            local lowestHealth, lowestMaxHealth = GetVisibleHealth(lowestHPTarget)
            if lowestHealth ~= nil and lowestHealth / lowestMaxHealth < 0.3 then
                return BOT_ACTION_DESIRE_HIGH, lowestHPTarget
            end
        end
    end

    return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLily03()
    local npcBot = GetBot()
    local nCastRange = ability03:GetCastRange()
    local nRadius = 375
    local nFriendlyHeroesAttackingCount = 0
    local nFriendlyHeroesRetreatingCount = 0

    if (not ability03:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

    if lilyStatus and GetHP(npcBot) > 0.3 then
        local locationAoE = CachedFindAoELocation( npcBot, 1, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0)
        if ( locationAoE ~= nil and locationAoE.count > 0 ) then
		    return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	    end
    elseif not lilyStatus then
        local locationAoE = CachedFindAoELocation( npcBot, 2, false, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0)
        local tableNearbyFriendlyHeroesAttacking = CachedGetNearbyHeroes(npcBot, nCastRange, false, BOT_MODE_ATTACK)
        for _,npcFriend in pairs(tableNearbyFriendlyHeroesAttacking)
		do
            if not IsPossibleIllusion(npcFriend) then
                nFriendlyHeroesAttackingCount = nFriendlyHeroesAttackingCount + 1
            end
        end
        local tableNearbyFriendlyHeroesRetreating = CachedGetNearbyHeroes(npcBot, nCastRange, false, BOT_MODE_ATTACK)
        for _,npcFriend in pairs(tableNearbyFriendlyHeroesRetreating)
		do
            if not IsPossibleIllusion(npcFriend) then
                nFriendlyHeroesRetreatingCount = nFriendlyHeroesRetreatingCount + 1
            end
        end
        if nFriendlyHeroesAttackingCount > 1 or nFriendlyHeroesRetreatingCount > 1 then
            if ( locationAoE ~= nil and locationAoE.count > 1 ) then
		        return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	        end
        end
    end

    return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLily04()
    local npcBot = GetBot()
    local nCastRange = 99999
    local nRadius = 600
    local nFriendlyHeroesAttackingCount = 0
    local nFriendlyHeroesRetreatingCount = 0

    if (not ability04:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

    if lilyStatus and GetHP(npcBot) > 0.4 then
        local locationAoE = CachedFindAoELocation( npcBot, 3, true, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0)
        if ( locationAoE ~= nil and locationAoE.count > 2 ) then
		    return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	    end
    elseif not lilyStatus then
        local locationAoE = CachedFindAoELocation( npcBot, 4, false, true, npcBot:GetLocation(), nCastRange, nRadius, 0, 0)
        local tableNearbyFriendlyHeroesAttacking = CachedGetNearbyHeroes(npcBot, nCastRange, false, BOT_MODE_ATTACK)
        for _,npcFriend in pairs(tableNearbyFriendlyHeroesAttacking)
		do
            if not IsPossibleIllusion(npcFriend) then
                nFriendlyHeroesAttackingCount = nFriendlyHeroesAttackingCount + 1
            end
        end
        local tableNearbyFriendlyHeroesRetreating = CachedGetNearbyHeroes(npcBot, nCastRange, false, BOT_MODE_ATTACK)
        for _,npcFriend in pairs(tableNearbyFriendlyHeroesRetreating)
		do
            if not IsPossibleIllusion(npcFriend) then
                nFriendlyHeroesRetreatingCount = nFriendlyHeroesRetreatingCount + 1
            end
        end
        if nFriendlyHeroesAttackingCount > 2 then
            if ( locationAoE ~= nil and locationAoE.count > 3 ) then
		        return BOT_ACTION_DESIRE_HIGH, locationAoE.targetloc
	        end
        end
    end

    return BOT_ACTION_DESIRE_NONE, 0
end
