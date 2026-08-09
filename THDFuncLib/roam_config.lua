local RoamConfig = {}

-- 新 gank 框架默认关闭；现有持续施法、连招和拾取逻辑不受此开关影响。
RoamConfig.ENABLED = true
RoamConfig.DEBUG = false
RoamConfig.ANNOUNCE_CHAT = true

RoamConfig.LANING_PHASE_END_TIME = 8 * 60
RoamConfig.APPROACH_TIMEOUT = 12.0
RoamConfig.ENGAGE_TIMEOUT = 8.0
RoamConfig.MISSION_TIMEOUT = 22.0
RoamConfig.ANNOUNCEMENT_WINDOW = 4.0
RoamConfig.ANNOUNCEMENT_TARGET_RADIUS = 900
RoamConfig.LOST_TARGET_GRACE = 2.5
RoamConfig.TEAM_COOLDOWN = 60.0
RoamConfig.MAX_ROAMERS = 2

RoamConfig.LANE_DISTANCE = 900
RoamConfig.LOCAL_FIGHT_RADIUS = 1600
RoamConfig.TOWER_DANGER_RADIUS = 1200
RoamConfig.ENGAGE_DISTANCE = 900
RoamConfig.MIN_START_POWER_RATIO = 0.90
RoamConfig.MIN_CONTINUE_POWER_RATIO = 0.80

RoamConfig.POSITION_RULES = {
	mid = {
		minLevel = 6,
		minHealth = 0.70,
		minMana = 0.50,
		travelBias = 2.0,
	},
	soft_support = {
		minLevel = 3,
		minHealth = 0.60,
		minMana = 0.40,
		travelBias = 0.0,
	},
	hard_support = {
		minLevel = 3,
		minHealth = 0.60,
		minMana = 0.40,
		travelBias = 1.0,
	},
}

local REQUIRED_POSITIVE_NUMBERS = {
	"LANING_PHASE_END_TIME",
	"APPROACH_TIMEOUT",
	"ENGAGE_TIMEOUT",
	"MISSION_TIMEOUT",
	"ANNOUNCEMENT_WINDOW",
	"ANNOUNCEMENT_TARGET_RADIUS",
	"LOST_TARGET_GRACE",
	"TEAM_COOLDOWN",
	"MAX_ROAMERS",
	"LANE_DISTANCE",
	"LOCAL_FIGHT_RADIUS",
	"TOWER_DANGER_RADIUS",
	"ENGAGE_DISTANCE",
	"MIN_START_POWER_RATIO",
	"MIN_CONTINUE_POWER_RATIO",
}

local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > 0
end

local function IsValidPositionRule(rule)
	return type(rule) == "table"
		and IsFiniteNumber(rule.minLevel)
		and IsFiniteNumber(rule.minHealth) and rule.minHealth <= 1
		and IsFiniteNumber(rule.minMana) and rule.minMana <= 1
		and type(rule.travelBias) == "number" and rule.travelBias == rule.travelBias
		and rule.travelBias >= 0
end

function RoamConfig.IsEnabled()
	if RoamConfig.ENABLED ~= true
		or type(RoamConfig.DEBUG) ~= "boolean"
		or type(RoamConfig.ANNOUNCE_CHAT) ~= "boolean"
		or type(RoamConfig.POSITION_RULES) ~= "table"
	then
		return false
	end
	for _, field in ipairs(REQUIRED_POSITIVE_NUMBERS) do
		if not IsFiniteNumber(RoamConfig[field]) then return false end
	end
	return IsValidPositionRule(RoamConfig.POSITION_RULES.mid)
		and IsValidPositionRule(RoamConfig.POSITION_RULES.soft_support)
		and IsValidPositionRule(RoamConfig.POSITION_RULES.hard_support)
end

return RoamConfig
