local bot = GetBot()
local botName = bot:GetUnitName()
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local IsAvoidingAbilityZone = false
local IsAvoidingAbilityProjectile = false
local IsAttackingSpecialUnit = false
local IsYugi04 = false

local nNextActionTime= 0

local specialUnits = {
	['npc_dota_phoenix_sun'] = 1,
	['npc_thdots_unit_minoriko02_box'] = 0.35,
}

local specialTarget
local yugi04Target

local TEAM_ROAM_DESIRE_INTERVAL = 0.45
local TEAM_ROAM_DESIRE_STAGGER = 0.07

function GetDesire()
	if not Timer.ShouldRunBotTask(bot, 'team_roam_desire', TEAM_ROAM_DESIRE_INTERVAL, TEAM_ROAM_DESIRE_STAGGER) then
		return BOT_MODE_DESIRE_NONE
	end

    IsAvoidingAbilityZone = false
	IsAvoidingAbilityProjectile = false
	IsAttackingSpecialUnit = false
	IsYugi04 = false

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

	--[[if HasProjectileThatNeedToAvoid(nProjectiles) then
		IsAvoidingAbilityProjectile = true
		print("bot to avoid some projectiles: " .. botName)
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end]]

	return BOT_MODE_DESIRE_NONE
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
		if p ~= nil
		and p.caster ~= nil
		and p.ability ~= nil
		and p.caster:GetTeam() ~= bot:GetTeam()
		and (p.ability:GetName() == "ability_thdots_ellen03"
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
	return Timer.GetOrCompute('TeamRoamSpecialUnit-'..tostring(bot:GetPlayerID()), 0.4, function()
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
	end)
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

	if IsAttackingSpecialUnit and DotaTime() > nNextActionTime then
		J.ActionAttackUnit(bot, 'team_roam_special_attack', specialTarget, false, 0.7)
		nNextActionTime = DotaTime() + 0.7
	end

	if IsYugi04 and DotaTime() > nNextActionTime then
		J.ActionAttackUnit(bot, 'team_roam_yugi_attack', yugi04Target, false, 0.7)
		nNextActionTime = DotaTime() + 0.7
	end

    if IsAvoidingAbilityZone then
		local avoidLoc = J.GetStableRandomLocation(bot, 'team_roam_avoid_zone', Utils.GetOffsetLocationTowardsTargetLocation(bot:GetLocation(), J.GetTeamFountain(), 600), 160, 240, 0.8)
		J.ActionMoveToLocation(bot, 'team_roam_avoid_zone', avoidLoc, 0.4, 220)
		return
	end

	local nProjectiles = GetLinearProjectiles()
	if IsAvoidingAbilityProjectile and nProjectiles ~= nil then
		for _, p in pairs(nProjectiles)
		do
			if p ~= nil
			and p.ability ~= nil
			and (p.ability:GetName() == "ability_thdots_ellen03"
			or p.ability:GetName() == "ability_thdots_ellen04"
		)
        	then
				if GetUnitToLocationDistance(bot, p.location) <= 1400 then
					local avoidLoc = J.GetStableRandomLocation(bot, 'team_roam_avoid_projectile', Utils.GetAvoidTargetLocation(bot:GetLocation(), p.location, 600), 160, 240, 0.7)
					J.ActionMoveToLocation(bot, 'team_roam_avoid_projectile', avoidLoc, 0.35, 220)
					return
				end
			end
		end
	end
end