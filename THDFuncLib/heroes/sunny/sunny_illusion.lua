local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local X = {}

local SUNNY05_MODIFIER = "modifier_ability_thdots_sunny05"
local SCOUT_AHEAD_DISTANCE = 900
local SCOUT_ORDER_INTERVAL = 0.75

local function GetPushLane(bot)
	local mode = bot:GetActiveMode()
	if mode == BOT_MODE_PUSH_TOWER_TOP then return LANE_TOP end
	if mode == BOT_MODE_PUSH_TOWER_MID then return LANE_MID end
	if mode == BOT_MODE_PUSH_TOWER_BOT then return LANE_BOT end
	return nil
end

local function IsSunnySelfIllusion(bot, unit)
	return bot ~= nil
		and unit ~= nil
		and not unit:IsNull()
		and unit:IsAlive()
		and unit:IsIllusion()
		and unit:HasModifier(SUNNY05_MODIFIER)
		and unit:GetUnitName() == bot:GetUnitName()
end

function X.Think(bot, unit)
	if not IsSunnySelfIllusion(bot, unit) then return false end
	local lane = GetPushLane(bot)
	if lane == nil then return false end

	local now = DotaTime()
	if now < (unit.sunnyScoutNextOrderTime or -90) then
		-- 已进入桑尼侦察逻辑时保持动作所有权，避免通用幻象逻辑覆盖前探命令。
		return true
	end
	local scoutLocation = GetLaneFrontLocation(bot:GetTeam(), lane, SCOUT_AHEAD_DISTANCE)
	if scoutLocation == nil then return false end
	Actions.Move(unit, scoutLocation)
	unit.sunnyScoutNextOrderTime = now + SCOUT_ORDER_INTERVAL
	return true
end

return X
