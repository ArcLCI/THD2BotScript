local bot = GetBot()
local botName = bot:GetUnitName()
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

local IsAvoidingAbilityZone = false
local IsAvoidingAbilityProjectile = false
local IsAttackingSpecialUnit = false
local IsYugi04 = false

local specialUnits = {
	['npc_dota_phoenix_sun'] = 1,
	['npc_thdots_unit_minoriko02_box'] = 0.35,
}

local specialTarget
local yugi04Target

function GetDesire()
    IsAvoidingAbilityZone = false
	IsAvoidingAbilityProjectile = false
	IsAttackingSpecialUnit = false
    local botMode = bot:GetActiveMode()
	local nProjectiles = GetLinearProjectiles()

	if HasSpecialUnitThatNeedToAttack() and not IsSeriouslyRetreating(bot) then
		IsAttackingSpecialUnit = true
		print("bot to attack some special unit: " .. botName)
		return BOT_ACTION_DESIRE_VERYHIGH
	end

	if SpecialYugi04() and not IsSeriouslyRetreating(bot) then
		IsYugi04 = true
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end
	
    if HasModifierThatNeedToAvoidEffects() then
		IsAvoidingAbilityZone = true
		print("bot to avoid some abilities: " .. botName)
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end

	if HasProjectileThatNeedToAvoid(nProjectiles) then
		IsAvoidingAbilityProjectile = true
		print("bot to avoid some projectiles: " .. botName)
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end
end

function HasModifierThatNeedToAvoidEffects()
	local cacheKey = 'HasModifierThatNeedToAvoidEffects'..tostring(bot:GetPlayerID())
	local cache = J.Utils.GetCachedVars(cacheKey, 3)
	if cache ~= nil then return cache end

	local res = bot:HasModifier('modifier_thdots_clown04_debuff') -- 可能无视魔免的技能
	or bot:HasModifier('modifier_ability_thdots_tojiko05_debuff')
	or bot:HasModifier('modifier_ability_thdots_child02_debuff')
	J.Utils.SetCachedVars(cacheKey, res)
	return res
end

function HasProjectileThatNeedToAvoid(nProjectiles)
	for _, p in pairs(nProjectiles)
	do
		if p ~= nil and p.caster:GetTeam() ~= bot:GetTeam() and (p.ability:GetName() == "ability_thdots_ellen03"
		or p.ability:GetName() == "ability_thdots_ellen04")
        then
			if GetUnitToLocationDistance(bot, p.location) <= 2000 then
				return true
			end
		end
	end
	return false
end

function HasSpecialUnitThatNeedToAttack()
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMIES))
    do
        if IsValid(enemy)
        then
            local enemyName = enemy:GetUnitName()

            if specialUnits[enemyName]
            and enemy:GetTeam() ~= bot:GetTeam()
            and GetUnitToUnitDistance(bot, enemy) <= specialUnits[enemyName] * 1400
            and RandomInt(0, 100) <= specialUnits[enemyName] * 100
            then
				specialTarget = enemy
				return true
            end
        end
    end
	return false
end

function SpecialYugi04()
	if bot:GetUnitName() == "npc_dota_hero_centaur" then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( bot, 500, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil
			and npcEnemy:HasModifier( "modifier_thdots_yugi04_think_interval" ))
			then
				yugi04Target = npcEnemy
				return true
			end
		end
	end
	return false
end

function OnStart() end
function OnEnd() end

function Think()
    if J.CanNotUseAction(bot) then return end

	if IsAttackingSpecialUnit then
		bot:Action_AttackUnit(specialTarget, false)
	end

	if IsYugi04 then
		bot:Action_AttackUnit(yugi04Target, false)
	end

    if IsAvoidingAbilityZone then
		bot:Action_MoveToLocation(Utils.GetOffsetLocationTowardsTargetLocation(bot:GetLocation(), J.GetTeamFountain(), 600) + RandomVector(200))
		return
	end

	local nProjectiles = GetLinearProjectiles()
	if IsAvoidingAbilityProjectile and nProjectiles ~= nil then
		for _, p in pairs(nProjectiles)
		do
			if p ~= nil and (p.ability:GetName() == "ability_thdots_ellen03"
			or p.ability:GetName() == "ability_thdots_ellen04"
		)
        	then
				if GetUnitToLocationDistance(bot, p.location) <= 1400 then
					bot:Action_MoveToLocation(Utils.GetAvoidTargetLocation(bot:GetLocation(), p.location, 600) + RandomVector(200))
					return
				end
			end
		end
	end
end