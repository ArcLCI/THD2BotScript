local bot = GetBot()
local botName = bot:GetUnitName();
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

local IsAvoidingAbilityZone = false
local IsAvoidingAbilityProjectile = false

function GetDesire()
    IsAvoidingAbilityZone = false
	IsAvoidingAbilityProjectile = false
    local botMode = bot:GetActiveMode()
	local nProjectiles = GetLinearProjectiles()

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
	or ( -- 不无视魔免的技能
		(bot:HasModifier('modifier_sandking_sand_storm_slow')
		or bot:HasModifier('modifier_sand_king_epicenter_slow'))
		and not bot:HasModifier("modifier_magic_immune")
	)
	J.Utils.SetCachedVars(cacheKey, res)
	return res
end

function HasProjectileThatNeedToAvoid(nProjectiles)
	for _, p in pairs(nProjectiles)
	do
		if p ~= nil and (p.ability:GetName() == "ability_thdots_ellen03"
		or p.ability:GetName() == "ability_thdots_ellen04"
	)
        then
			if GetUnitToLocationDistance(bot, p.location) <= 600 then
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