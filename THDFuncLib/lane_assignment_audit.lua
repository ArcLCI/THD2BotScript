local Config = require(GetScriptDirectory() .. "/THDFuncLib/lane_assignment_audit_config")

local Audit = {}

Audit.DIMENSIONS = {
	"gold_scaling",
	"level_scaling",
	"lane_independence",
	"last_hit",
	"trading",
	"wave_control",
	"initiation",
	"follow_up",
	"protection",
	"roaming",
	"low_economy",
	"late_carry",
}

-- 权重取自人工审核表的岗位重点，最后统一换算到 0-30 分。
Audit.POSITION_WEIGHTS = {
	safe_core = {
		gold_scaling = 3, level_scaling = 1, lane_independence = 1, last_hit = 3,
		trading = 1, wave_control = 1, follow_up = 1, late_carry = 3,
	},
	mid = {
		gold_scaling = 1, level_scaling = 3, lane_independence = 3, last_hit = 2,
		trading = 2, wave_control = 3, initiation = 1, follow_up = 1,
		roaming = 3, late_carry = 1,
	},
	off_core = {
		gold_scaling = 1, level_scaling = 2, lane_independence = 3, last_hit = 1,
		trading = 3, wave_control = 2, initiation = 3, follow_up = 1,
		roaming = 1, low_economy = 1,
	},
	soft_support = {
		level_scaling = 2, lane_independence = 1, trading = 2, wave_control = 1,
		initiation = 3, follow_up = 3, protection = 1, roaming = 3,
		low_economy = 3,
	},
	hard_support = {
		level_scaling = 1, lane_independence = 1, trading = 3, wave_control = 2,
		initiation = 1, follow_up = 2, protection = 3, roaming = 1,
		low_economy = 3,
	},
}

local DIMENSION_SET = {}
for _, dimension in ipairs(Audit.DIMENSIONS) do DIMENSION_SET[dimension] = true end

local POSITIONING_SET = {
	base = true,
	damage = true,
	damage_spell = true,
	frontline = true,
	support = true,
}

local function IsInteger(value)
	return type(value) == "number" and value % 1 == 0
end

function Audit.ValidateTraits(traits)
	if type(traits) ~= "table" then return false, "traits_not_table" end
	for _, dimension in ipairs(Audit.DIMENSIONS) do
		local value = traits[dimension]
		if not IsInteger(value) then return false, "invalid_" .. dimension end
		if value < 0 or value > 3 then return false, "out_of_range_" .. dimension end
	end
	for dimension, _ in pairs(traits) do
		if not DIMENSION_SET[dimension] then return false, "unknown_" .. tostring(dimension) end
	end
	return true
end

function Audit.CalculateScores(traits)
	local valid, reason = Audit.ValidateTraits(traits)
	if not valid then return nil, reason end
	local scores = {}
	for position, weights in pairs(Audit.POSITION_WEIGHTS) do
		local weightedValue = 0
		local totalWeight = 0
		for dimension, weight in pairs(weights) do
			weightedValue = weightedValue + traits[dimension] * weight
			totalWeight = totalWeight + weight
		end
		scores[position] = math.floor(weightedValue * 10 / totalWeight + 0.5)
	end
	return scores
end

function Audit.GetScores(heroName, profile)
	local heroes = type(Config.heroes) == "table" and Config.heroes or nil
	local heroConfig = heroes ~= nil and heroes[heroName] or nil
	if type(heroConfig) ~= "table" then return nil end
	local positioning = profile or "base"
	local record = heroConfig[positioning]
	if type(record) ~= "table" then return nil end
	local scores, reason = Audit.CalculateScores(record.traits)
	return scores, {
		positioning = positioning,
		label = record.label,
		error = reason,
	}
end

function Audit.ValidateConfig()
	local errors = {}
	if Config.schemaVersion ~= 1 then table.insert(errors, "unsupported_schema") end
	if type(Config.heroes) ~= "table" then
		table.insert(errors, "heroes_not_table")
		return false, errors
	end
	for heroName, heroConfig in pairs(Config.heroes) do
		if type(heroName) ~= "string" or type(heroConfig) ~= "table" then
			table.insert(errors, "invalid_hero_entry:" .. tostring(heroName))
		else
			for positioning, record in pairs(heroConfig) do
				if POSITIONING_SET[positioning] ~= true then
					table.insert(errors, heroName .. ":unknown_positioning:" .. tostring(positioning))
				elseif type(record) ~= "table" then
					table.insert(errors, heroName .. ":" .. positioning .. ":record_not_table")
				else
					local valid, reason = Audit.ValidateTraits(record.traits)
					if not valid then table.insert(errors, heroName .. ":" .. positioning .. ":" .. reason) end
				end
			end
		end
	end
	return #errors == 0, errors
end

Audit.Config = Config

return Audit
