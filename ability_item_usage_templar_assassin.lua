
require(GetScriptDirectory() ..  "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

----------------------------------------------------------------------------------------------------

local cast01Desire = 0
local cast02Desire = 0
local cast03Desire = 0
local cast04Desire = 0
local castExDesire = 0

local ability01,ability02,ability03,ability04,abilityEx,
    cast01Location,cast02Location,cast03Location

local DQERDesire,QERDesire,ERDesire,theWorldtarget
local theWorldWDesire,theWorldWTargetloc,theWorldQDesire,theWorldQTargetloc

local theWorldRadius
local theWorldStatus = false
local theWorldLocation
local theWorldTime = 0

local nNextActionTime= 0

function MyItemUsageThink()
    local npcBot = GetBot()

    if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

    local item_yukkuri_stick = IsItemAvailable("item_yukkuri_stick")
    local item_dragon_star = IsItemAvailable( "item_dragon_star" )
    local item_blue = IsItemAvailable("item_yatagarasu") or IsItemAvailable("item_yueyaomishi")
    local item_horse_red = IsItemAvailable("item_horse_red")
	local item_horse_king = IsItemAvailable("item_horse_king")

	if (item_blue~=nil and item_blue:IsFullyCastable())
	then
		local castItemBlueDesire = ConsiderItemBlue(item_blue)
		if ( castItemBlueDesire > 0 )
		then
			npcBot:Action_UseAbility(item_blue)
			return
		end
	end

    if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
        if IsSeriouslyRetreating(npcBot) then
            npcBot:Action_UseAbility(item_dragon_star)
            return
        end
	end

    if ( item_yukkuri_stick~=nil and item_yukkuri_stick:IsFullyCastable() )
	then
		local castItemYukkuriStickDesire, castItemYukkuriStickTarget = ConsiderItemYukkuriStick(item_yukkuri_stick)
		if ( castItemYukkuriStickDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity(item_yukkuri_stick, castItemYukkuriStickTarget)
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
    local npcBot = GetBot()
    -- 咲夜大招期间需要按0.2秒技能前摇连续利用冷却重置，不能受IsBotAwake的0.25秒全局门控限制。
    if npcBot == nil
    or not npcBot:IsAlive()
    or npcBot:IsIllusion()
    or npcBot:IsHexed()
    or npcBot:IsStunned()
    then
        return
    end

    local item_dragon_star = IsItemAvailable( "item_dragon_star" )

	ability01 = npcBot:GetAbilityByName( "ability_thdots_sakuya01" )
    ability02 = npcBot:GetAbilityByName( "ability_thdots_sakuya02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_sakuya03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_sakuya04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_sakuyaEx" )

    theWorldRadius = 250 + (150 * ability04:GetLevel())
    local theWorldBuffTime = 3 + ability04:GetLevel()

    if ability04:GetLevel() > 0 and npcBot:HasModifier("modifier_item_wanbaochui") then
        theWorldRadius = 99999
    end

    if theWorldTime > 0 and theWorldTime >= DotaTime() - theWorldBuffTime and
    not ability04:IsCooldownReady() and
    GetUnitToLocationDistance(npcBot,theWorldLocation) < theWorldRadius then
        theWorldStatus = true
    else
        theWorldStatus = false
    end

    if npcBot:IsSilenced() or npcBot:IsCastingAbility() or npcBot:IsChanneling() then return end
    -- 大招区域内的技能均无视后摇；前摇结束后允许继续决策，由0.2秒连发时钟防止指令互相覆盖。
    if npcBot:IsUsingAbility() and not theWorldStatus then return end
    if not theWorldStatus then
        MyItemUsageThink()
        ConsiderNeutralItems()
    end

    DQERDesire,QERDesire,ERDesire,theWorldtarget = ConsiderTHEWORLD()
    if DQERDesire > 0 and theWorldtarget ~= nil then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_combo_dqer', false, 1.0) then return end
        npcBot:ActionQueue_UseAbility(abilityEx)
        npcBot:ActionQueue_Delay(0.1)
        npcBot:ActionQueue_UseAbilityOnLocation(ability01,theWorldtarget:GetLocation())
        npcBot:ActionQueue_Delay(0.1)
        if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
            npcBot:ActionQueue_UseAbility(item_dragon_star)
            npcBot:ActionQueue_Delay(0.1)
        end
        npcBot:ActionQueue_UseAbilityOnLocation(ability03,theWorldtarget:GetLocation())
        if ability02:IsFullyCastable() then
            npcBot:ActionQueue_Delay(0.1)
            npcBot:ActionQueue_UseAbilityOnLocation(ability02, theWorldtarget:GetLocation())
        end
        npcBot:ActionQueue_Delay(0.1)
        npcBot:ActionQueue_UseAbility(ability04)
        theWorldTime = DotaTime()
        theWorldLocation = npcBot:GetLocation()
        return
    end
    if QERDesire > 0 and theWorldtarget ~= nil then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_combo_qer', false, 0.2) then return end
        npcBot:ActionQueue_UseAbilityOnLocation(ability01,theWorldtarget:GetLocation())
        npcBot:ActionQueue_Delay(0.1)
        if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
            npcBot:ActionQueue_UseAbility(item_dragon_star)
            npcBot:ActionQueue_Delay(0.1)
        end
        npcBot:ActionQueue_UseAbilityOnLocation(ability03,theWorldtarget:GetLocation())
        if ability02:IsFullyCastable() then
            npcBot:ActionQueue_Delay(0.1)
            npcBot:ActionQueue_UseAbilityOnLocation(ability02, theWorldtarget:GetLocation())
        end
        npcBot:ActionQueue_Delay(0.1)
        npcBot:ActionQueue_UseAbility(ability04)
        theWorldTime = DotaTime()
        theWorldLocation = npcBot:GetLocation()
        return
    end
    if ERDesire > 0 and theWorldtarget ~= nil then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_combo_er', false, 0.2) then return end
        if (item_dragon_star~=nil and item_dragon_star:IsFullyCastable()) then
            npcBot:ActionQueue_UseAbility(item_dragon_star)
            npcBot:ActionQueue_Delay(0.1)
        end
        npcBot:ActionQueue_UseAbilityOnLocation(ability03,theWorldtarget:GetLocation())
        if ability02:IsFullyCastable() then
            npcBot:ActionQueue_Delay(0.1)
            npcBot:ActionQueue_UseAbilityOnLocation(ability02, theWorldtarget:GetLocation())
        end
        npcBot:ActionQueue_Delay(0.1)
        npcBot:ActionQueue_UseAbility(ability04)
        theWorldTime = DotaTime()
        theWorldLocation = npcBot:GetLocation()
        return
    end

    theWorldWDesire, theWorldWTargetloc  = ConsidertheWorldW()
    if theWorldWDesire > 0 and theWorldWTargetloc ~= nil and DotaTime() >= nNextActionTime then
        npcBot:Action_UseAbilityOnLocation(ability02, theWorldWTargetloc)
        nNextActionTime = DotaTime() + 0.2
		return
    end

    theWorldQDesire, theWorldQTargetloc = ConsidertheWorldQ()
    if theWorldQDesire > 0 and theWorldQTargetloc ~= nil and DotaTime() >= nNextActionTime then
        if abilityEx:IsFullyCastable() and not npcBot:HasModifier("modifier_thdots_sakuyaEx_flag") then
            npcBot:ActionQueue_UseAbility(abilityEx)
            npcBot:ActionQueue_UseAbilityOnLocation(ability01, theWorldQTargetloc)
            nNextActionTime = DotaTime() + 0.2
            return
        end
        npcBot:Action_UseAbilityOnLocation(ability01, theWorldQTargetloc)
        nNextActionTime = DotaTime() + 0.2
		return
    end

    cast04Desire = ConsiderAbilitySakuya04()
	if ( cast04Desire > 0 )
	then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_cast04', false, 0.2) then return end
		npcBot:Action_UseAbility( ability04 )
        theWorldTime = DotaTime()
        theWorldLocation = npcBot:GetLocation()
		return
	end

    castExDesire = ConsiderAbilitySakuyaEx()
	if ( castExDesire > 0 and not theWorldStatus)
	then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_cast_ex', false, 0.2) then return end
		npcBot:Action_UseAbility( abilityEx )
		return
	end

    cast01Desire, cast01Location = ConsiderAbilitySakuya01()
	if ( cast01Desire > 0 and cast01Location ~= nil and not theWorldStatus)
	then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_cast01', false, 0.2) then return end
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location )
		return
	end

    cast03Desire, cast03Location = ConsiderAbilitySakuya03()
	if ( cast03Desire > 0 and cast03Location ~= nil)
	then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_cast03', false, 0.2) then return end
		npcBot:Action_UseAbilityOnLocation( ability03, cast03Location )
		return
	end

    cast02Desire, cast02Location = ConsiderAbilitySakuya02()
	if ( cast02Desire > 0 and cast02Location ~= nil and not theWorldStatus)
	then
        if not J.ClearActionsThrottled(npcBot, 'sakuya_cast02', false, 0.2) then return end
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastSakuya01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

function CanCastSakuya02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

function CanCastSakuya03OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, true)
end

----------------------------------------------------------------------------------------------------
function ConsiderTHEWORLD()
    local npcBot = GetBot()

    if ability03:IsFullyCastable() and ability04:IsFullyCastable() and npcBot:GetActiveMode() == BOT_MODE_ATTACK then
        local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500 + (100 *ability03:GetLevel()), true, BOT_MODE_NONE )
        local tempTarget
        for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (npcBot:GetTarget() == npcEnemy and CanCastSakuya01OnTarget(npcEnemy)) then
                tempTarget = npcEnemy
            end
        end
        if ability01:IsFullyCastable() then
            if abilityEx:IsFullyCastable() then
                return BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE, tempTarget
            elseif npcBot:HasModifier("modifier_thdots_sakuyaEx_flag") then
                return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_NONE, tempTarget
            end
        end
        return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH, tempTarget
    end
    return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE, 0
end

function ConsidertheWorldW()
    local npcBot = GetBot()
    local nCastRange = 600

    if not theWorldStatus or not ability02:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange, true, BOT_MODE_NONE)
    if #tableNearbyEnemyHeroes > 1 then
        local lowestHP = 99999
        local lowestHPTarget
        for _,npcEnemy in pairs(tableNearbyEnemyHeroes)
        do
            if CanCastSakuya02OnTarget(npcEnemy) then
                if npcEnemy:GetHealth() <= lowestHP then
                    lowestHP = npcEnemy:GetHealth()
                    lowestHPTarget = npcEnemy:GetLocation()
                end
            end
        end
        return BOT_ACTION_DESIRE_HIGH, lowestHPTarget
    else
    	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastSakuya02OnTarget(npcEnemy) then
	    		return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
	    	end
    	end
    end

	return BOT_ACTION_DESIRE_NONE, 0
end

function ConsidertheWorldQ()
    local npcBot = GetBot()
    local nCastRange = 1000 + (150 * ability01:GetLevel())
    local nProjectileSpeed = 2000

    if not theWorldStatus or not ability01:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange, true, BOT_MODE_NONE)
    if #tableNearbyEnemyHeroes > 1 then
        local lowestHP = 99999
        local lowestHPTarget
        for _,npcEnemy in pairs(tableNearbyEnemyHeroes)
        do
            if CanCastSakuya01OnTarget(npcEnemy) then
                if npcEnemy:GetHealth() <= lowestHP then
                    lowestHP = npcEnemy:GetHealth()
                    lowestHPTarget = npcEnemy
                end
            end
        end
        if lowestHPTarget:GetMovementDirectionStability() >= 0.75 then
            local eta = 0.2 + (GetUnitToUnitDistance(npcBot,lowestHPTarget)/nProjectileSpeed)
            return BOT_ACTION_DESIRE_HIGH, lowestHPTarget:GetExtrapolatedLocation(eta)
        end
        return BOT_ACTION_DESIRE_HIGH, lowestHPTarget:GetLocation()
    else
    	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastSakuya01OnTarget(npcEnemy) then
                if npcEnemy:GetMovementDirectionStability() >= 0.75 then
                local eta = 0.2 + (GetUnitToUnitDistance(npcBot,npcEnemy)/nProjectileSpeed)
                    return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
                end
	    		return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
	    	end
    	end
    end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySakuyaEx()
    local npcBot = GetBot()

    if (not abilityEx:IsFullyCastable())
	then
		return BOT_ACTION_DESIRE_NONE
	end

    if not npcBot:HasModifier("modifier_thdots_sakuyaEx_flag") then
        return BOT_ACTION_DESIRE_HIGH
    end

    return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySakuya01()
    local npcBot = GetBot()

    local nCastRange = 1000 + (150 * ability01:GetLevel())
    local nProjectileSpeed = 2000

    if (not ability01:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

    if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(900,true)
		if tableNearbylanecreeps ~= nil and #tableNearbylanecreeps >= 2
        then
            return BOT_ACTION_DESIRE_HIGH, GetCenterOfUnits(tableNearbylanecreeps)
        end
	end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange, true, BOT_MODE_NONE)
    if #tableNearbyEnemyHeroes > 1 then
        local lowestHP = 99999
        local lowestHPTarget
        for _,npcEnemy in pairs(tableNearbyEnemyHeroes)
        do
            if CanCastSakuya01OnTarget(npcEnemy) then
                if npcEnemy:GetHealth() <= lowestHP then
                    lowestHP = npcEnemy:GetHealth()
                    lowestHPTarget = npcEnemy
                end
            end
        end
        if lowestHPTarget:GetMovementDirectionStability() >= 0.75 then
            local eta = 0.2 + (GetUnitToUnitDistance(npcBot,lowestHPTarget)/nProjectileSpeed)
            return BOT_ACTION_DESIRE_HIGH, lowestHPTarget:GetExtrapolatedLocation(eta)
        end
        return BOT_ACTION_DESIRE_HIGH, lowestHPTarget:GetLocation()
    else
    	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastSakuya01OnTarget(npcEnemy) then
                if npcEnemy:GetMovementDirectionStability() >= 0.75 then
                local eta = 0.2 + (GetUnitToUnitDistance(npcBot,npcEnemy)/nProjectileSpeed)
                    return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetExtrapolatedLocation(eta)
                end
	    		return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
	    	end
    	end
    end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySakuya02()
    local npcBot = GetBot()

    local nCastRange = 600

    if (not ability02:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

    if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(600,true)
		if tableNearbylanecreeps ~= nil and #tableNearbylanecreeps >= 3
        then
            return BOT_ACTION_DESIRE_HIGH, GetCenterOfUnits(tableNearbylanecreeps)
        end
	end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, nCastRange-50, true, BOT_MODE_NONE)
    if #tableNearbyEnemyHeroes > 1 then
        local lowestHP = 99999
        local lowestHPTarget
        for _,npcEnemy in pairs(tableNearbyEnemyHeroes)
        do
            if CanCastSakuya02OnTarget(npcEnemy) then
                if npcEnemy:GetHealth() <= lowestHP then
                    lowestHP = npcEnemy:GetHealth()
                    lowestHPTarget = npcEnemy:GetLocation()
                end
            end
        end
        return BOT_ACTION_DESIRE_HIGH, lowestHPTarget
    else
    	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastSakuya02OnTarget(npcEnemy) then
	    		return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
	    	end
    	end
    end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySakuya03()
    local npcBot = GetBot()

    local nCastRange = 500 + (100 *ability03:GetLevel())

    if (not ability03:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

    -- 追人
    if (npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH and not theWorldStatus)
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (npcBot:GetTarget() == npcEnemy and CanCastSakuya03OnTarget(npcEnemy)
            and (npcEnemy:GetHealth() < 320 or GetHP(npcEnemy) < 0.15 ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end

		end
	end
    -- 撤退
    if IsSeriouslyRetreating(npcBot) then
		local v_home = GetAncient(npcBot:GetTeam()):GetLocation()
		local v_target = ( v_home - npcBot:GetLocation() ) / GetUnitToLocationDistance( npcBot, v_home)
		local v_final = npcBot:GetLocation() + v_target * nCastRange
		return BOT_ACTION_DESIRE_HIGH, v_final
	end

    return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySakuya04()
    local npcBot = GetBot()

    if (not ability04:IsFullyCastable()) then
		return BOT_ACTION_DESIRE_NONE
	end

    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes(npcBot, 400, true, BOT_MODE_NONE)
    
    if #tableNearbyEnemyHeroes > 0 and npcBot:GetActiveMode() == BOT_MODE_ATTACK then
        for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
	    	if CanCastSakuya02OnTarget(npcEnemy) then
	    		return BOT_ACTION_DESIRE_HIGH
	    	end
    	end
    end

    return BOT_ACTION_DESIRE_NONE
end
