local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Config = require(GetScriptDirectory()..'/THDFuncLib/roam_config')
local Coordinator = require(GetScriptDirectory()..'/THDFuncLib/roam_coordinator')
local Initiation = require(GetScriptDirectory()..'/THDFuncLib/roam_initiation')

local Gank = {}
local TryUseTP = nil
local HasIssuedTP = nil

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function IsEnabled()
	if type(Config) ~= 'table' or type(Config.IsEnabled) ~= 'function' then return false end
	local ok, enabled = pcall(Config.IsEnabled)
	return ok and enabled == true
end

function Gank.GetDesire(bot)
	if not IsEnabled() then return BOT_MODE_DESIRE_NONE end
	local mission = Coordinator.GetMission(bot)
	-- GetDesire 先于 Think 执行；在这里仅观察已发出的 TP，避免目标死亡先清空任务而丢失终态。
	if HasIssuedTP(bot, mission) and TryUseTP(bot, mission) then
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end
	return Coordinator.GetDesire(bot)
end

function Gank.OnStart(bot)
	return Coordinator.OnStart(bot)
end

function Gank.Abort(bot, reason, context)
	Coordinator.Abort(bot, reason, context)
end

function Gank.OnEnd(bot, reason)
	Coordinator.OnEnd(bot, reason)
end

local function IsActionBlocked(bot)
	return J.CanNotUseAction(bot)
		or (bot.IsCastingAbility ~= nil and bot:IsCastingAbility())
		or (bot.IsUsingAbility ~= nil and bot:IsUsingAbility())
		or (bot.IsChanneling ~= nil and bot:IsChanneling())
end

local function GetLandingDistance(bot, location)
	if location == nil then return math.huge end
	return Safe(math.huge, function() return GetUnitToLocationDistance(bot, location) end)
end

local function LogTPFallback(bot, mission, plan, reason)
	plan.useTP = false
	Coordinator.DebugAction(bot, string.format('tp_fallback mission=%s reason=%s target=%s channel_observed=%s',
		tostring(mission.missionID or 'unknown'), tostring(reason), tostring(mission.targetPlayerID),
		tostring(plan.tpChannelObserved == true)))
end

TryUseTP = function(bot, mission)
	if type(mission.travelPlans) ~= 'table' then return false end
	local playerID = Safe(-1, function() return bot:GetPlayerID() end)
	local plan = mission.travelPlans[playerID]
	if plan == nil or plan.useTP ~= true or plan.tpLocation == nil then return false end
	local teleporting = Safe(false, function() return bot:HasModifier('modifier_teleporting') end)

	if plan.tpIssued then
		local landingDistance = GetLandingDistance(bot, plan.tpLocation)
		if landingDistance <= Config.TP_LANDING_OBSERVED_RADIUS then
			local endState = plan.tpChannelObserved == true and 'landed_observed' or 'landed_unobserved'
			plan.useTP = false
			plan.tpEndedLogged = true
			Coordinator.DebugAction(bot, string.format('tp_end mission=%s target=%s state=%s landing_distance=%.0f channel_time=%.1f',
				tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID), endState,
				landingDistance, DotaTime() - (plan.tpChannelStartTime or plan.tpIssuedTime or DotaTime())))
			return false
		end
		if teleporting then
			if plan.tpChannelObserved ~= true then
				plan.tpChannelObserved = true
				plan.tpChannelStartTime = DotaTime()
				Coordinator.DebugAction(bot, string.format('tp_channel_start mission=%s target=%s elapsed=%.1f',
					tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID),
					DotaTime() - (plan.tpIssuedTime or DotaTime())))
			end
			return true
		end
		if plan.tpChannelObserved == true and plan.tpEndedLogged ~= true then
			plan.tpEndedLogged = true
			plan.useTP = false
			Coordinator.DebugAction(bot, string.format('tp_end mission=%s target=%s state=interrupted landing_distance=%.0f channel_time=%.1f',
				tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID),
				landingDistance, DotaTime() - (plan.tpChannelStartTime or plan.tpIssuedTime or DotaTime())))
			return false
		end
		local elapsed = DotaTime() - (plan.tpIssuedTime or DotaTime())
		if elapsed < Config.TP_CAST_START_GRACE then return true end
		local itemStillReady = plan.tpItem ~= nil
			and Safe(false, function() return J.CanCastAbility(plan.tpItem) end)
		if itemStillReady then
			LogTPFallback(bot, mission, plan, 'cast_not_started')
			return false
		end
		local expectedChannelTime = plan.channelTime or Config.TP_CHANNEL_TIME_ESTIMATE
		if elapsed < expectedChannelTime + Config.TP_CAST_START_GRACE then return true end
		LogTPFallback(bot, mission, plan, 'channel_not_observed')
		return false
	end
	if mission.phase ~= 'approach' then return false end
	if teleporting then return true end
	if IsActionBlocked(bot) then return false end
	local refreshedPlan, refreshReason, targetMoved = Coordinator.RefreshTPTravelPlan(bot, mission)
	if refreshedPlan == nil then
		LogTPFallback(bot, mission, plan, 'replan_' .. tostring(refreshReason))
		return false
	end
	plan = refreshedPlan
	if targetMoved ~= nil and targetMoved >= Config.TP_REPLAN_LOG_DISTANCE then
		Coordinator.DebugAction(bot, string.format('tp_replan mission=%s target=%s moved=%.0f landing=%.0f',
			tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID),
			targetMoved, plan.landingDistance or -1))
	end

	local targetLocation = Coordinator.GetRallyLocation(mission)
		or Safe(nil, function() return mission.target:GetLocation() end)
	local currentDistance = Safe(math.huge, function() return GetUnitToLocationDistance(bot, targetLocation) end)
	local landingDistance = J.GetLocationToLocationDistance ~= nil
		and Safe(math.huge, function() return J.GetLocationToLocationDistance(plan.tpLocation, targetLocation) end)
		or (plan.landingDistance or math.huge)
	if targetLocation == nil
		or currentDistance < Config.TP_MIN_WALK_DISTANCE
		or landingDistance > Config.TP_MAX_LANDING_DISTANCE
		or landingDistance + 500 >= currentDistance
	then
		LogTPFallback(bot, mission, plan, 'route_changed')
		return false
	end

	if Safe(false, function() return bot:WasRecentlyDamagedByAnyHero(2.0) end)
		or #(Safe({}, function() return bot:GetNearbyHeroes(Config.TP_SAFE_RADIUS, true, BOT_MODE_NONE) end) or {}) > 0
	then
		LogTPFallback(bot, mission, plan, 'unsafe_channel')
		return false
	end

	local tpScroll = Coordinator.GetReadyTPScroll(bot)
	if tpScroll == nil then
		LogTPFallback(bot, mission, plan, 'tp_unavailable')
		return false
	end

	bot:Action_UseAbilityOnLocation(tpScroll, plan.tpLocation)
	plan.tpIssued = true
	plan.tpIssuedTime = DotaTime()
	plan.tpChannelObserved = false
	plan.tpEndedLogged = false
	plan.tpItem = tpScroll
	plan.channelTime = plan.channelTime or Safe(Config.TP_CHANNEL_TIME_ESTIMATE, function() return tpScroll:GetChannelTime() end)
	Coordinator.DebugAction(bot, string.format('tp_start mission=%s target=%s from_distance=%.0f landing=%.0f',
		tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID), currentDistance, landingDistance))
	return true
end

HasIssuedTP = function(bot, mission)
	if mission == nil or type(mission.travelPlans) ~= 'table' then return false end
	local playerID = Safe(-1, function() return bot:GetPlayerID() end)
	local plan = mission.travelPlans[playerID]
	return plan ~= nil and plan.useTP == true and plan.tpIssued == true
end

function Gank.Think(bot)
	if not IsEnabled() then
		Coordinator.Abort(bot, 'disabled')
		return
	end
	-- 已发出的 TP 必须先收集终态；否则目标同帧死亡会让 coordinator 先释放并丢失落点结果。
	local activeMission = Coordinator.GetMission(bot)
	if HasIssuedTP(bot, activeMission) and TryUseTP(bot, activeMission) then return end
	if Coordinator.GetDesire(bot) <= BOT_MODE_DESIRE_NONE then return end
	local mission = Coordinator.GetMission(bot)
	if mission == nil then return end

	-- 先让 TP 生命周期观察到引导开始和结束，再保护普通技能前摇/引导动作。
	if TryUseTP(bot, mission) then return end
	-- ROAM 只负责移动和普攻；前摇、引导和持续施法期间绝不覆盖技能动作。
	if IsActionBlocked(bot) then return end

	if mission.target ~= nil and mission.target.CanBeSeen ~= nil and mission.target:CanBeSeen() then
		J.SetTargetIfChanged(bot, mission.target, 0.5)
		local rallyLocation = Coordinator.GetRallyLocation(mission)
			or Safe(nil, function() return mission.target:GetLocation() end)
		if mission.phase == 'engage' then
			local initiation = Initiation.GetStatus(bot, mission)
			if initiation ~= nil then
				local statusKey = tostring(initiation.status) .. ':' .. tostring(initiation.reason)
				if mission.lastLoggedInitiationStatus ~= statusKey then
					mission.lastLoggedInitiationStatus = statusKey
					Coordinator.DebugAction(bot, string.format('initiation_status mission=%s target=%s hero=%s owner=%s status=%s reason=%s hold=%s need_move=%s',
						tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID),
						tostring(bot.GetUnitName ~= nil and Safe('unknown', function() return bot:GetUnitName() end) or 'unknown'),
						tostring(mission.initiationOwnerID or 'none'), tostring(initiation.status),
						tostring(initiation.reason or 'none'), tostring(initiation.hold == true), tostring(initiation.needMove == true)))
				end
				if initiation.event ~= nil then
					Coordinator.DebugAction(bot, string.format('initiation_%s mission=%s target=%s reason=%s',
						tostring(initiation.event), tostring(mission.missionID or 'unknown'),
						tostring(mission.targetPlayerID), tostring(initiation.reason)))
				end
				if initiation.hold then
					if initiation.needMove and rallyLocation ~= nil then
						J.ActionMoveToLocation(bot, 'roam_gank_initiation_approach', rallyLocation, 0.25, 180)
					end
					return
				end
			end
			local pursuit = Coordinator.ReassessPursuit(bot, mission)
			if pursuit ~= nil and pursuit.triggered then
				Coordinator.DebugAction(bot, string.format('pursuit_reassess mission=%s original=%s action=%s reason=%s alternative=%s distance=%.0f distance_delta=%.0f outward=%.0f power=%.2f numbers=%dv%d bot_health=%.2f original_score=%s alternative_score=%s',
					tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID),
					tostring(pursuit.action), tostring(pursuit.reason),
					tostring(pursuit.alternativePlayerID or 'none'), pursuit.targetDistance or -1,
					pursuit.distanceDelta or 0, pursuit.outwardDistance or 0, pursuit.powerRatio or -1,
					pursuit.allyCount or 0, pursuit.enemyCount or 0, pursuit.botHealth or -1,
					pursuit.originalScore ~= nil and string.format('%.3f', pursuit.originalScore) or 'none',
					pursuit.alternativeScore ~= nil and string.format('%.3f', pursuit.alternativeScore) or 'none'))
			end
			if pursuit ~= nil and pursuit.action == 'retreat' then
				Coordinator.Abort(bot, 'pursuit_disengage', {
					reason = pursuit.reason,
					power = pursuit.powerRatio ~= nil and string.format('%.2f', pursuit.powerRatio) or 'unknown',
					numbers = tostring(pursuit.allyCount or 0) .. 'v' .. tostring(pursuit.enemyCount or 0),
				})
				local fountain = J.GetTeamFountain ~= nil and Safe(nil, function() return J.GetTeamFountain() end) or nil
				if fountain ~= nil then
					J.ActionMoveToLocation(bot, 'roam_gank_pursuit_disengage', fountain, 0.25, 180)
				end
				return
			end
			local combatTarget = pursuit ~= nil and pursuit.target or mission.target
			J.ActionAttackUnit(bot, 'roam_gank_attack', combatTarget, false, 0.35)
			return
		end
		if rallyLocation ~= nil then
			J.ActionMoveToLocation(bot, 'roam_gank_approach', rallyLocation, 0.35, 180)
		end
		return
	end

	local rallyLocation = Coordinator.GetRallyLocation(mission)
	if rallyLocation ~= nil then
		J.ActionMoveToLocation(bot, 'roam_gank_last_seen', rallyLocation, 0.35, 180)
	end
end

return Gank
