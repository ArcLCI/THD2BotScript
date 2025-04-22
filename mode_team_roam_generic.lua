local bot = GetBot()
local botName = bot:GetUnitName();
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

local IsAvoidingAbilityZone = false

function GetDesire()
    IsAvoidingAbilityZone = false
    local botMode = bot:GetActiveMode()

    if HasModifierThatNeedToAvoidEffects() then
		IsAvoidingAbilityZone = true
		print("bot to avoid some abilities: " .. botName)
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end
end

function HasModifierThatNeedToAvoidEffects()
	local cacheKey = 'HasModifierThatNeedToAvoidEffects'..tostring(bot:GetPlayerID())
	local cache = J.Utils.GetCachedVars(cacheKey, 3)
	if cache ~= nil then return cache end

	local res = bot:HasModifier('modifier_jakiro_macropyre_burn') -- 可能无视魔免的技能
	or bot:HasModifier('modifier_dark_seer_wall_slow')
	or ( -- 不无视魔免的技能
		(bot:HasModifier('modifier_sandking_sand_storm_slow')
		or bot:HasModifier('modifier_sand_king_epicenter_slow'))
		and (not bot:HasModifier("modifier_black_king_bar_immune") or not bot:HasModifier("modifier_magic_immune") or not bot:HasModifier("modifier_omniknight_repel"))
	)
	J.Utils.SetCachedVars(cacheKey, res)
	return res
end

function OnStart() end
function OnEnd() end

function Think()
    if J.CanNotUseAction(bot) then return end

    if IsAvoidingAbilityZone then
		bot:Action_MoveToLocation(Utils.GetOffsetLocationTowardsTargetLocation(bot:GetLocation(), J.GetTeamFountain(), 600) + RandomVector(200))
		return
	end
end