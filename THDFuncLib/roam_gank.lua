local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Config = require(GetScriptDirectory()..'/THDFuncLib/roam_config')
local Coordinator = require(GetScriptDirectory()..'/THDFuncLib/roam_coordinator')
local Initiation = require(GetScriptDirectory()..'/THDFuncLib/roam_initiation')
local Consumables = require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')

local Gank = {}
local TryUseTP = nil
local HasIssuedTP = nil
local TryUseTwinGate = nil
local HasIssuedTwinGate = nil
local SMOKE_REQUESTER = 'roam_pickoff_smoke'
local DUST_REQUESTER = 'roam_pickoff_dust'

Consumables.SetBackpackBridgeEnabled(Config.BACKPACK_CAST_BRIDGE_ENABLED == true)

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function ReleaseConsumable(bot, mission, requester, reason)
	local state = Consumables.GetState(bot)
	local itemName = state ~= nil and state.requester == requester and state.itemName or nil
	local released, releaseReason = Consumables.Release(bot, requester, reason)
	if itemName ~= nil and mission ~= nil then
		Coordinator.DebugAction(bot, string.format('consumable_release mission=%s item=%s owner=%s phase=%s request_reason=%s released=%s reason=%s',
			tostring(mission.missionID or 'unknown'), tostring(itemName),
			tostring(Safe(-1, function() return bot:GetPlayerID() end)), tostring(mission.phase),
			tostring(reason), tostring(released), tostring(releaseReason)))
	end
	return released, releaseReason
end

local function IsEnabled()
	if type(Config) ~= 'table' or type(Config.IsEnabled) ~= 'function' then return false end
	local ok, enabled = pcall(Config.IsEnabled)
	return ok and enabled == true
end

function Gank.GetDesire(bot)
	if not IsEnabled() then return BOT_MODE_DESIRE_NONE end
	local mission = Coordinator.GetMission(bot)
	-- GetDesire 先于 Think 执行；这里只观察已发出的长引导，避免任务先释放而丢失终态。
	if HasIssuedTP(bot, mission) and TryUseTP(bot, mission) then
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end
	if HasIssuedTwinGate(bot, mission) and TryUseTwinGate(bot, mission) then
		return BOT_MODE_DESIRE_ABSOLUTE * 0.95
	end
	return Coordinator.GetDesire(bot)
end

function Gank.OnStart(bot)
	return Coordinator.OnStart(bot)
end

function Gank.Abort(bot, reason, context)
	local mission = Coordinator.GetMission(bot)
	ReleaseConsumable(bot, mission, SMOKE_REQUESTER, reason or 'mission_abort')
	ReleaseConsumable(bot, mission, DUST_REQUESTER, reason or 'mission_abort')
	Coordinator.Abort(bot, reason, context)
end

function Gank.OnEnd(bot, reason)
	local mission = Coordinator.GetMission(bot)
	ReleaseConsumable(bot, mission, SMOKE_REQUESTER, reason or 'mode_end')
	ReleaseConsumable(bot, mission, DUST_REQUESTER, reason or 'mode_end')
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
	if plan.tpIssued == true then
		plan.tpEndedTime = DotaTime()
		plan.tpLanded = false
	end
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
			plan.tpEndedTime = DotaTime()
			plan.tpLanded = true
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
			plan.tpEndedTime = DotaTime()
			plan.tpLanded = false
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
	if mission.kind == nil or mission.kind == 'lane_gank' then
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
	plan.tpEndedTime = nil
	plan.tpLanded = nil
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

local function LogGateFallback(bot, mission, plan, reason)
	plan.route = 'walk'
	plan.gateFailed = true
	Coordinator.DebugAction(bot, string.format('gate_fallback mission=%s reason=%s target=%s channel_observed=%s',
		tostring(mission.missionID or 'unknown'), tostring(reason), tostring(mission.targetPlayerID),
		tostring(plan.gateChannelObserved == true)))
end

-- 双生门 API 在参考 Bot 中也默认关闭；这里只保留有界实验路径，由配置显式启用。
TryUseTwinGate = function(bot, mission)
	if Config.ENABLE_TWIN_GATE_ROUTE ~= true or mission == nil or type(mission.travelPlans) ~= 'table' then return false end
	local playerID = Safe(-1, function() return bot:GetPlayerID() end)
	local plan = mission.travelPlans[playerID]
	if plan == nil or plan.route ~= 'twin_gate' or plan.gateFailed == true
		or plan.gateEntrance == nil or plan.gateExit == nil
	then
		return false
	end

	local warp = Safe(nil, function() return bot:GetAbilityByName('twin_gate_portal_warp') end)
	if warp == nil then
		LogGateFallback(bot, mission, plan, 'ability_unavailable')
		return false
	end
	if plan.gateIssued then
		local exitDistance = GetLandingDistance(bot, Safe(nil, function() return plan.gateExit:GetLocation() end))
		if exitDistance <= Config.TP_LANDING_OBSERVED_RADIUS then
			plan.route = 'walk'
			Coordinator.DebugAction(bot, string.format('gate_end mission=%s target=%s state=landed landing_distance=%.0f',
				tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID), exitDistance))
			return false
		end
		local channeling = Safe(false, function() return warp:IsInAbilityPhase() end)
			or Safe(false, function() return warp:IsChanneling() end)
			or Safe(false, function() return bot:IsChanneling() end)
		if channeling then
			plan.gateChannelObserved = true
			return true
		end
		local elapsed = DotaTime() - (plan.gateIssuedTime or DotaTime())
		if elapsed < Config.TWIN_GATE_CAST_START_GRACE then return true end
		if plan.gateChannelObserved ~= true and Safe(false, function() return warp:IsFullyCastable() end) then
			LogGateFallback(bot, mission, plan, 'cast_not_started')
			return false
		end
		if elapsed < (plan.channelTime or Config.TWIN_GATE_CHANNEL_TIME_ESTIMATE)
			+ Config.TWIN_GATE_CAST_START_GRACE
		then
			return true
		end
		LogGateFallback(bot, mission, plan, 'channel_not_completed')
		return false
	end

	if mission.phase ~= 'approach' or IsActionBlocked(bot) then return false end
	local entranceLocation = Safe(nil, function() return plan.gateEntrance:GetLocation() end)
	if entranceLocation == nil then
		LogGateFallback(bot, mission, plan, 'entrance_invalid')
		return false
	end
	local entranceDistance = GetLandingDistance(bot, entranceLocation)
	if entranceDistance > Config.TWIN_GATE_CAST_RANGE then
		J.ActionMoveToLocation(bot, 'roam_gank_gate_approach', entranceLocation, 0.25, 180)
		return true
	end
	if Safe(false, function() return bot:WasRecentlyDamagedByAnyHero(2.0) end)
		or #(Safe({}, function() return bot:GetNearbyHeroes(Config.TWIN_GATE_SAFE_RADIUS, true, BOT_MODE_NONE) end) or {}) > 0
	then
		LogGateFallback(bot, mission, plan, 'unsafe_channel')
		return false
	end
	if not Safe(false, function() return warp:IsFullyCastable() end) then
		LogGateFallback(bot, mission, plan, 'ability_not_ready')
		return false
	end

	bot:Action_UseAbilityOnEntity(warp, plan.gateEntrance)
	plan.gateIssued = true
	plan.gateIssuedTime = DotaTime()
	plan.gateChannelObserved = false
	plan.channelTime = Safe(Config.TWIN_GATE_CHANNEL_TIME_ESTIMATE, function() return warp:GetChannelTime() end)
	Coordinator.DebugAction(bot, string.format('gate_start mission=%s target=%s entrance_distance=%.0f',
		tostring(mission.missionID or 'unknown'), tostring(mission.targetPlayerID), entranceDistance))
	return true
end

HasIssuedTwinGate = function(bot, mission)
	if mission == nil or type(mission.travelPlans) ~= 'table' then return false end
	local playerID = Safe(-1, function() return bot:GetPlayerID() end)
	local plan = mission.travelPlans[playerID]
	return plan ~= nil and plan.route == 'twin_gate' and plan.gateIssued == true
end

local function GetPlayerID(bot)
	return Safe(-1, function() return bot:GetPlayerID() end)
end

local function IsMissionParticipant(mission, playerID)
	for _, expectedID in ipairs(mission.participantIDs or {}) do
		if expectedID == playerID then return true end
	end
	return false
end

local function GetMissionParticipants(mission)
	local participants = {}
	for index = 1, #(Safe({}, function() return GetTeamPlayers(GetTeam()) end) or {}) do
		local member = Safe(nil, function() return GetTeamMember(index) end)
		local memberID = member ~= nil and GetPlayerID(member) or -1
		if member ~= nil and IsMissionParticipant(mission, memberID) then
			table.insert(participants, member)
		end
	end
	return participants
end

local function CanSafelyCastSmoke(bot, mission)
	if Config.SMOKE_ENABLED ~= true then return false, 'smoke_disabled' end
	if mission == nil or mission.requiresSmoke ~= true then return false, 'not_required' end
	local participants = GetMissionParticipants(mission)
	if #participants < (mission.requiredCount or 2) then return false, 'participants_missing' end
	if mission.stagingLocation ~= nil
		and GetLandingDistance(bot, mission.stagingLocation) > Config.SMOKE_PRECAST_STAGING_DISTANCE
	then
		return false, 'staging_too_far'
	end
	for _, member in ipairs(participants) do
		local memberID = GetPlayerID(member)
		if mission.joinedParticipantIDs == nil or mission.joinedParticipantIDs[memberID] ~= true then
			return false, 'participant_not_acknowledged'
		end
		if GetLandingDistance(member, Safe(nil, function() return bot:GetLocation() end))
			> Config.SMOKE_APPLICATION_RADIUS - 50
		then
			return false, 'outside_application_radius'
		end
		local enemies = Safe({}, function()
			return member:GetNearbyHeroes(Config.SMOKE_SAFE_ENEMY_RADIUS, true, BOT_MODE_NONE)
		end) or {}
		if #enemies > 0 then return false, 'visible_enemy_near_group' end
		local towers = Safe({}, function() return member:GetNearbyTowers(Config.SMOKE_SAFE_TOWER_RADIUS, true) end) or {}
		if #towers > 0 then return false, 'enemy_tower_near_group' end
	end
	return true, 'group_safe'
end

local function UseReadyConsumable(bot, mission, itemName, requester, castPhase)
	if itemName == 'item_smoke_of_deceit' and Config.SMOKE_ENABLED ~= true then return false end
	local item = Consumables.GetReadyItem(bot, itemName, requester)
	if item == nil then return false end
	bot:Action_UseAbility(item)
	local marked, reason = Consumables.MarkCastIssued(bot, requester)
	local attemptsField = itemName == 'item_smoke_of_deceit' and 'smokeCastAttempts' or 'dustCastAttempts'
	mission[attemptsField] = (mission[attemptsField] or 0) + 1
	if not marked then
		if itemName == 'item_smoke_of_deceit' then mission.smokeCastFailed = true
		else mission.dustCastFailed = true end
	end
	Coordinator.DebugAction(bot, string.format('consumable_cast_issued mission=%s item=%s phase=%s owner=%s attempt=%s tracked=%s reason=%s',
		tostring(mission.missionID or 'unknown'), tostring(itemName), tostring(castPhase), tostring(GetPlayerID(bot)),
		tostring(mission[attemptsField]), tostring(marked), tostring(reason)))
	return true
end

local function GetConsumableSlot(bot, itemName)
	local item, slot = Consumables.FindItem(bot, itemName)
	return item ~= nil and slot or -1
end

local function LogConsumableRequest(bot, mission, itemName, requester, accepted, reason, deadline)
	mission.consumableRequestLogs = mission.consumableRequestLogs or {}
	local key = tostring(accepted) .. ':' .. tostring(reason) .. ':' .. tostring(mission.phase)
	if mission.consumableRequestLogs[requester] == key then return end
	mission.consumableRequestLogs[requester] = key
	Coordinator.DebugAction(bot, string.format('consumable_request mission=%s item=%s owner=%s phase=%s accepted=%s reason=%s slot=%s deadline_remaining=%.1f',
		tostring(mission.missionID or 'unknown'), tostring(itemName), tostring(GetPlayerID(bot)),
		tostring(mission.phase), tostring(accepted), tostring(reason),
		tostring(GetConsumableSlot(bot, itemName)), math.max(0, deadline - DotaTime())))
end

local function RequestMissionConsumable(bot, mission, itemName, requester, priority, deadline)
	local accepted, reason = Consumables.Request(bot, itemName, requester, priority, deadline, {kind = 'none'})
	LogConsumableRequest(bot, mission, itemName, requester, accepted, reason, deadline)
	return accepted, reason
end

local function LogConsumableStatus(bot, mission, state, status)
	if state == nil or (state.requester ~= SMOKE_REQUESTER and state.requester ~= DUST_REQUESTER) then return end
	mission.consumableStatusLogs = mission.consumableStatusLogs or {}
	local key = tostring(status) .. ':' .. tostring(mission.phase)
	if mission.consumableStatusLogs[state.requester] == key then return end
	mission.consumableStatusLogs[state.requester] = key
	Coordinator.DebugAction(bot, string.format('consumable_status mission=%s item=%s owner=%s phase=%s status=%s slot=%s ready=%s restore=%s deadline_remaining=%.1f',
		tostring(mission.missionID or 'unknown'), tostring(state.itemName), tostring(GetPlayerID(bot)),
		tostring(mission.phase), tostring(status), tostring(GetConsumableSlot(bot, state.itemName)),
		tostring(state.ready == true), tostring(state.restorePending == true),
		math.max(0, (state.deadline or DotaTime()) - DotaTime())))
end

local function LogSmokeWait(bot, mission, playerID, reason)
	if mission.lastSmokeSafetyReason == reason then return end
	mission.lastSmokeSafetyReason = reason
	Coordinator.DebugAction(bot, string.format('smoke_wait mission=%s owner=%s phase=%s reason=%s',
		tostring(mission.missionID or 'unknown'), tostring(playerID),
		tostring(mission.phase), tostring(reason)))
end

local function HandleCastStatus(bot, mission, status)
	local state = Consumables.GetState(bot)
	if state == nil then return false end
	local isSmoke = state.itemName == 'item_smoke_of_deceit' and state.requester == SMOKE_REQUESTER
	local isDust = state.itemName == 'item_dust' and state.requester == DUST_REQUESTER
	if not isSmoke and not isDust then return false end
	if isSmoke and Config.SMOKE_ENABLED ~= true then
		ReleaseConsumable(bot, mission, state.requester, 'smoke_disabled')
		return true
	end
	if status == 'cast_confirmed' then
		if isSmoke then mission.smokeConfirmedTime = DotaTime()
		else mission.dustConfirmedTime = DotaTime() end
		ReleaseConsumable(bot, mission, state.requester, 'cast_confirmed')
		Coordinator.DebugAction(bot, string.format('consumable_cast_confirmed mission=%s item=%s owner=%s',
			tostring(mission.missionID or 'unknown'), tostring(state.itemName), tostring(GetPlayerID(bot))))
		return true
	end
	if status == 'cast_unconfirmed' then
		local attempts = isSmoke and (mission.smokeCastAttempts or 0) or (mission.dustCastAttempts or 0)
		Coordinator.DebugAction(bot, string.format('consumable_cast_unconfirmed mission=%s item=%s owner=%s attempt=%s',
			tostring(mission.missionID or 'unknown'), tostring(state.itemName), tostring(GetPlayerID(bot)), tostring(attempts)))
		if attempts >= 2 then
			if isSmoke then mission.smokeCastFailed = true else mission.dustCastFailed = true end
			ReleaseConsumable(bot, mission, state.requester, 'cast_unconfirmed')
			return true
		end
	end
	return false
end

local function HandleMissionConsumables(bot, mission)
	local playerID = GetPlayerID(bot)
	local deadline = (mission.startTime or DotaTime()) + Config.PICKOFF_TOTAL_TIMEOUT
	local ownsSmoke = mission.requiresSmoke == true
		and mission.smokeConfirmedTime == nil
		and mission.smokeOwnerID == playerID
	if Config.SMOKE_ENABLED ~= true then
		-- 配置关闭后只收尾旧租约，绝不重新申请或尝试施放已有烟雾。
		ReleaseConsumable(bot, mission, SMOKE_REQUESTER, 'smoke_disabled')
	elseif ownsSmoke
		and (mission.phase == 'assemble' or mission.phase == 'conceal')
	then
		RequestMissionConsumable(bot, mission, 'item_smoke_of_deceit', SMOKE_REQUESTER, 100, deadline)
	elseif mission.smokeOwnerID == playerID then
		ReleaseConsumable(bot, mission, SMOKE_REQUESTER, 'smoke_phase_ended')
	end

	local canPrestageDust = mission.phase == 'assemble' and mission.dustOwnerID ~= mission.smokeOwnerID
	if mission.requiresDust == true and mission.dustOwnerID == playerID
		and (canPrestageDust or mission.phase == 'approach' or mission.phase == 'ambush' or mission.phase == 'engage')
	then
		RequestMissionConsumable(bot, mission, 'item_dust', DUST_REQUESTER, 90, deadline)
	elseif mission.dustOwnerID == playerID then
		ReleaseConsumable(bot, mission, DUST_REQUESTER, 'dust_phase_ended')
	end

	local stateBeforeThink = Consumables.GetState(bot)
	local ownsLifecycle, status = Consumables.Think(bot)
	LogConsumableStatus(bot, mission, stateBeforeThink or Consumables.GetState(bot), status)
	if HandleCastStatus(bot, mission, status) then return true end
	local state = Consumables.GetState(bot)
	if status == 'ready' and state ~= nil then
		-- 已在释放技能或持续施法时不发烟/粉订单；等待原动作结束后再使用。
		if IsActionBlocked(bot) then
			if state.itemName == 'item_smoke_of_deceit' then
				LogSmokeWait(bot, mission, playerID, 'action_blocked')
			end
			return true
		end
		if Config.SMOKE_ENABLED == true
			and state.itemName == 'item_smoke_of_deceit'
			and (mission.phase == 'assemble' or mission.phase == 'conceal')
		then
			local safeToSmoke, safetyReason = CanSafelyCastSmoke(bot, mission)
			if safeToSmoke then
				return UseReadyConsumable(bot, mission, state.itemName, SMOKE_REQUESTER, mission.phase)
			end
			LogSmokeWait(bot, mission, playerID, safetyReason)
		end
		if state.itemName == 'item_dust' then
			local targetLocation = Coordinator.GetRallyLocation(mission)
			local closeEnough = targetLocation ~= nil and GetLandingDistance(bot, targetLocation) <= 850
			if closeEnough and (mission.phase == 'ambush' or mission.phase == 'engage') then
				return UseReadyConsumable(bot, mission, state.itemName, DUST_REQUESTER, mission.phase)
			end
		end
		return false
	end
	-- 换位/确认动作独占；激活冷却与安全等待期间仍可继续向集结点移动。
	local blocking = status == 'swap_issued' or status == 'restore_swap'
		or status == 'bridge_attempt' or status == 'cast_confirm_wait'
		or status == 'cast_confirmed'
	return ownsLifecycle == true and blocking
end

function Gank.Think(bot)
	if not IsEnabled() then
		Coordinator.Abort(bot, 'disabled')
		return
	end
	-- 已发出的 TP 必须先收集终态；否则目标同帧死亡会让 coordinator 先释放并丢失落点结果。
	local activeMission = Coordinator.GetMission(bot)
	if HasIssuedTP(bot, activeMission) and TryUseTP(bot, activeMission) then return end
	if HasIssuedTwinGate(bot, activeMission) and TryUseTwinGate(bot, activeMission) then return end
	if Coordinator.GetDesire(bot) <= BOT_MODE_DESIRE_NONE then
		ReleaseConsumable(bot, activeMission, SMOKE_REQUESTER, 'mission_released')
		ReleaseConsumable(bot, activeMission, DUST_REQUESTER, 'mission_released')
		return
	end
	local mission = Coordinator.GetMission(bot)
	if mission == nil then return end

	-- 先让长距离路线观察到引导开始和结束，再保护普通技能前摇/引导动作。
	if TryUseTP(bot, mission) then return end
	if TryUseTwinGate(bot, mission) then return end

	-- 先预热副包烟，再继续向集结点移动；这样最后到达的 owner 不会把激活等待全部压进 conceal。
	if HandleMissionConsumables(bot, mission) then return end
	if mission.phase == 'assemble' and mission.stagingLocation ~= nil
		and GetLandingDistance(bot, mission.stagingLocation) > Config.PICKOFF_ASSEMBLE_RADIUS - 50
	then
		J.ActionMoveToLocation(bot, 'roam_gank_assemble', mission.stagingLocation, 0.25, 180)
		return
	end
	-- ROAM 只负责移动和普攻；前摇、引导和持续施法期间绝不覆盖技能动作。
	if IsActionBlocked(bot) then return end
	if mission.phase == 'assemble' or mission.phase == 'conceal' then
		local stagingLocation = mission.stagingLocation or Coordinator.GetRallyLocation(mission)
		if stagingLocation ~= nil then
			J.ActionMoveToLocation(bot, 'roam_gank_' .. tostring(mission.phase), stagingLocation, 0.25, 180)
		end
		return
	end

	if mission.target ~= nil and mission.target.CanBeSeen ~= nil
		and Safe(false, function() return mission.target:CanBeSeen() end)
	then
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
