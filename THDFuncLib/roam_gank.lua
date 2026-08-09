local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Config = require(GetScriptDirectory()..'/THDFuncLib/roam_config')
local Coordinator = require(GetScriptDirectory()..'/THDFuncLib/roam_coordinator')

local Gank = {}

local function IsEnabled()
	if type(Config) ~= 'table' or type(Config.IsEnabled) ~= 'function' then return false end
	local ok, enabled = pcall(Config.IsEnabled)
	return ok and enabled == true
end

function Gank.GetDesire(bot)
	if not IsEnabled() then return BOT_MODE_DESIRE_NONE end
	return Coordinator.GetDesire(bot)
end

function Gank.OnStart(bot)
	return Coordinator.OnStart(bot)
end

function Gank.Abort(bot, reason)
	Coordinator.Abort(bot, reason)
end

function Gank.OnEnd(bot, reason)
	Coordinator.OnEnd(bot, reason)
end

function Gank.Think(bot)
	if not IsEnabled() then
		Coordinator.Abort(bot, 'disabled')
		return
	end
	if Coordinator.GetDesire(bot) <= BOT_MODE_DESIRE_NONE then return end
	local mission = Coordinator.GetMission(bot)
	if mission == nil then return end

	-- ROAM 只负责移动和普攻；前摇、引导和持续施法期间绝不覆盖技能动作。
	if J.CanNotUseAction(bot)
		or (bot.IsCastingAbility ~= nil and bot:IsCastingAbility())
		or (bot.IsUsingAbility ~= nil and bot:IsUsingAbility())
		or (bot.IsChanneling ~= nil and bot:IsChanneling())
	then
		return
	end

	if mission.target ~= nil and mission.target.CanBeSeen ~= nil and mission.target:CanBeSeen() then
		J.SetTargetIfChanged(bot, mission.target, 0.5)
		if mission.phase == 'engage' then
			J.ActionAttackUnit(bot, 'roam_gank_attack', mission.target, false, 0.35)
			return
		end
		local location = mission.target:GetLocation()
		J.ActionMoveToLocation(bot, 'roam_gank_approach', location, 0.35, 180)
		return
	end

	if mission.lastLocation ~= nil then
		J.ActionMoveToLocation(bot, 'roam_gank_last_seen', mission.lastLocation, 0.35, 180)
	end
end

return Gank
