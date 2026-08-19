local NitoriCombat = {}
local CombatPower = require(GetScriptDirectory()..'/THDFuncLib/combat_power')

local EMPOWER_TALENT = "special_bonus_unique_nitori_4"

local function SafeCall(object, methodName, fallback, ...)
	if object == nil or object[methodName] == nil then return fallback end
	local args = {...}
	local ok, value = pcall(function() return object[methodName](object, unpack(args)) end)
	if ok and value ~= nil then return value end
	return fallback
end

local function GetSpecialValue(ability, key, fallback)
	local value = SafeCall(ability, "GetSpecialValueInt", nil, key)
	if value == nil then value = SafeCall(ability, "GetSpecialValueFloat", nil, key) end
	if value == nil or value <= 0 then return fallback end
	return value
end

local function HasTalent(bot, name)
	local talent = SafeCall(bot, "GetAbilityByName", nil, name)
	return talent ~= nil and SafeCall(talent, "GetLevel", 0) > 0
end

function NitoriCombat.GetNitori03RawDamage(bot, ability)
	if ability == nil then return 0 end
	local level = math.max(SafeCall(ability, "GetLevel", 1), 1)
	local magicalBonus = GetSpecialValue(ability, "magical_bonus", ({60, 100, 140, 180})[level] or 180)
	return magicalBonus
		+ SafeCall(bot, "GetAttackDamage", 0) * 0.3
		+ SafeCall(bot, "GetIntellect", 0) * 0.6
end

function NitoriCombat.GetEmpoweredAttackRawDamage(bot, ability03)
	local outgoingBonus = GetSpecialValue(ability03, "outdamage_bonus", 20)
	if HasTalent(bot, EMPOWER_TALENT) then outgoingBonus = outgoingBonus + 20 end
	return SafeCall(bot, "GetAttackDamage", 0) * (1 + outgoingBonus / 100)
end

function NitoriCombat.GetHarvestActualDamage(bot, target, ability03)
	if bot == nil or target == nil or ability03 == nil then return 0 end
	local physicalRaw = NitoriCombat.GetEmpoweredAttackRawDamage(bot, ability03)
	local magicalRaw = NitoriCombat.GetNitori03RawDamage(bot, ability03)
	local physical = CombatPower.EstimateIncomingDamage(target, physicalRaw, DAMAGE_TYPE_PHYSICAL, 0)
	local magical = CombatPower.EstimateIncomingDamage(target, magicalRaw, DAMAGE_TYPE_MAGICAL, 0)
	return physical + magical
end

function NitoriCombat.GetEnemyHighGroundTowers(location, range)
	local result = {}
	if location == nil or GetTower == nil or GetOpposingTeam == nil then return result end
	local towerIds = {
		TOWER_TOP_3, TOWER_MID_3, TOWER_BOT_3,
		TOWER_BASE_1, TOWER_BASE_2,
	}
	for _, towerId in pairs(towerIds) do
		if towerId ~= nil then
			local tower = GetTower(GetOpposingTeam(), towerId)
			if tower ~= nil and GetUnitToLocationDistance(tower, location) < (range or 900) then
				table.insert(result, tower)
			end
		end
	end
	return result
end

function NitoriCombat.IsEnemyHighGroundTowerDanger(location, range)
	return #NitoriCombat.GetEnemyHighGroundTowers(location, range) > 0
end

return NitoriCombat
