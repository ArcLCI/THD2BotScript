local Scheduler = {}

local DEFAULT_PHASE_INTERVAL = 0.12
local BASE_ENEMY_SCAN_RANGE = 1800
local OBJECTIVE_THINK_INTERVAL = 0.25
-- 阶段 A 针对性复测期间临时开启；完成最终运行验收后恢复为 false。
Scheduler.DEBUG_OBJECTIVE_INTERVAL = true
local OBJECTIVE_DEBUG_LOG_INTERVAL = 5.0

local OBJECTIVE_MODES = {}
local function RegisterObjectiveMode(mode)
    if mode ~= nil then OBJECTIVE_MODES[mode] = true end
end
RegisterObjectiveMode(BOT_MODE_PUSH_TOWER_TOP)
RegisterObjectiveMode(BOT_MODE_PUSH_TOWER_MID)
RegisterObjectiveMode(BOT_MODE_PUSH_TOWER_BOT)
RegisterObjectiveMode(BOT_MODE_DEFEND_TOWER_TOP)
RegisterObjectiveMode(BOT_MODE_DEFEND_TOWER_MID)
RegisterObjectiveMode(BOT_MODE_DEFEND_TOWER_BOT)

local function HasVisibleEnemyHeroWithinRange(bot, range)
    for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
        if enemy ~= nil
            and (enemy.IsNull == nil or not enemy:IsNull())
            and enemy:IsAlive()
            and enemy:CanBeSeen()
            and GetUnitToUnitDistance(bot, enemy) <= range
        then
            return true
        end
    end
    return false
end

function Scheduler.Now()
    return GameTime()
end

function Scheduler.GetPlayerId(bot)
    if bot == nil then return 0 end
    if bot.GetPlayerID ~= nil then
        local ok, playerId = pcall(function() return bot:GetPlayerID() end)
        if ok and playerId ~= nil and playerId >= 0 then return playerId end
    end
    if bot.entindex ~= nil then
        local ok, result = pcall(function() return bot:entindex() end)
        if ok and result ~= nil then return result end
    end
    return 0
end

function Scheduler.GetPhaseOffset(bot, phaseInterval)
    if phaseInterval == nil then phaseInterval = DEFAULT_PHASE_INTERVAL end
    return (Scheduler.GetPlayerId(bot) % 10) * phaseInterval
end

function Scheduler.ShouldRunBotTask(bot, taskName, interval, phaseInterval)
    if bot == nil then return true end
    if interval == nil then interval = 1.0 end

    local fieldName = 'SchedulerNext_' .. taskName
    local now = Scheduler.Now()
    if bot[fieldName] == nil then
        bot[fieldName] = now + Scheduler.GetPhaseOffset(bot, phaseInterval)
    end

    if now < bot[fieldName] then
        return false
    end

    bot[fieldName] = now + interval
    return true
end

function Scheduler.IsInCombat(bot)
    if bot == nil then return false end
    if not bot:IsAlive() then return false end

    if bot:WasRecentlyDamagedByAnyHero(3.0) then return true end
    if bot:GetActiveMode() == BOT_MODE_ATTACK or bot:GetActiveMode() == BOT_MODE_RETREAT then return true end
    if #bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE) > 0 then return true end

    return false
end

function Scheduler.IsObjectiveMode(mode)
    return OBJECTIVE_MODES[mode] == true
end

function Scheduler.IsHighPriorityState(bot)
    if Scheduler.IsInCombat(bot) then return true end
    if bot == nil or not bot:IsAlive() then return false end

    local mode = bot:GetActiveMode()
    if Scheduler.IsObjectiveMode(mode)
        or mode == BOT_MODE_ATTACK
        or mode == BOT_MODE_RETREAT
        or mode == BOT_MODE_ROSHAN
    then
        return true
    end

    local ancient = GetAncient(GetTeam())
    if ancient ~= nil and GetUnitToUnitDistance(bot, ancient) < 3600 then
        -- 原生 GetNearbyHeroes 最大只支持 1600；全局列表过滤可保留原有 1800 判断。
        if HasVisibleEnemyHeroWithinRange(bot, BASE_ENEMY_SCAN_RANGE) then return true end
    end

    return false
end

local function GetTaskDebugState(bot, taskName)
	if bot.THDSchedulerTaskDebugState == nil then bot.THDSchedulerTaskDebugState = {} end
	local state = bot.THDSchedulerTaskDebugState[taskName]
	if state == nil then
		state = {
			inObjective = false,
			mode = nil,
			lastRun = nil,
			lastLog = -9999,
			intervalMin = nil,
			intervalMax = nil,
			intervalSum = 0,
			intervalSamples = 0,
		}
		bot.THDSchedulerTaskDebugState[taskName] = state
	end
	return state
end

local function ResetTaskIntervalWindow(state)
	state.intervalMin = nil
	state.intervalMax = nil
	state.intervalSum = 0
	state.intervalSamples = 0
end

-- 只在任务真正通过自身门控后调用；把“选中了 0.25”与“实际按 0.25 执行”拆成两类证据。
function Scheduler.ObserveTaskRun(bot, taskName, configuredInterval)
	if Scheduler.DEBUG_OBJECTIVE_INTERVAL ~= true or bot == nil then return false end
	taskName = taskName or 'unspecified'
	local mode = bot:GetActiveMode()
	local state = GetTaskDebugState(bot, taskName)
	local now = Scheduler.Now()

	if not Scheduler.IsObjectiveMode(mode) then
		state.inObjective = false
		state.mode = nil
		state.lastRun = nil
		ResetTaskIntervalWindow(state)
		return false
	end

	if not state.inObjective or state.mode ~= mode then
		state.inObjective = true
		state.mode = mode
		state.lastRun = now
		state.lastLog = now
		ResetTaskIntervalWindow(state)
		print(string.format('[BOT][Scheduler] schema=3 pid=%s action=task_enter task=%s mode=%s configured_interval=%.3f dota_time=%.2f game_time=%.2f',
			tostring(Scheduler.GetPlayerId(bot)), tostring(taskName), tostring(mode),
			configuredInterval or -1, DotaTime(), now))
		return true
	end

	if state.lastRun ~= nil then
		local interval = math.max(0, now - state.lastRun)
		state.intervalMin = state.intervalMin == nil and interval or math.min(state.intervalMin, interval)
		state.intervalMax = state.intervalMax == nil and interval or math.max(state.intervalMax, interval)
		state.intervalSum = state.intervalSum + interval
		state.intervalSamples = state.intervalSamples + 1
	end
	state.lastRun = now

	if state.intervalSamples > 0 and now - state.lastLog >= OBJECTIVE_DEBUG_LOG_INTERVAL then
		print(string.format('[BOT][Scheduler] schema=3 pid=%s action=task_cadence task=%s mode=%s configured_interval=%.3f observed_min=%.3f observed_avg=%.3f observed_max=%.3f samples=%d dota_time=%.2f game_time=%.2f',
			tostring(Scheduler.GetPlayerId(bot)), tostring(taskName), tostring(mode),
			configuredInterval or -1, state.intervalMin,
			state.intervalSum / state.intervalSamples, state.intervalMax,
			state.intervalSamples, DotaTime(), now))
		state.lastLog = now
		ResetTaskIntervalWindow(state)
	end
	return true
end

function Scheduler.GetLowPowerThinkInterval(bot, normalInterval, lowPowerInterval, taskName)
	-- 六个实际推塔/守塔模式采用固定目标周期，避免误落入 1.25 秒以上的低功耗分支。
	if bot ~= nil and Scheduler.IsObjectiveMode(bot:GetActiveMode()) then
		if Scheduler.DEBUG_OBJECTIVE_INTERVAL == true then
			local now = Scheduler.Now()
			taskName = taskName or 'unspecified'
			if bot.THDSchedulerIntervalLogAt == nil then bot.THDSchedulerIntervalLogAt = {} end
			local lastLog = bot.THDSchedulerIntervalLogAt[taskName] or -9999
			if now - lastLog >= OBJECTIVE_DEBUG_LOG_INTERVAL then
				bot.THDSchedulerIntervalLogAt[taskName] = now
				print(string.format('[BOT][Scheduler] schema=3 pid=%s action=interval_selected task=%s mode=%s selected_interval=%.3f dota_time=%.2f game_time=%.2f',
					tostring(Scheduler.GetPlayerId(bot)), tostring(taskName), tostring(bot:GetActiveMode()),
					OBJECTIVE_THINK_INTERVAL, DotaTime(), now))
			end
		end
		return OBJECTIVE_THINK_INTERVAL
	end
	if Scheduler.IsInCombat(bot) then
		return normalInterval
	end
	if Scheduler.IsHighPriorityState(bot) then return normalInterval end

    local dotaTime = DotaTime()
    if dotaTime > 40 * 60 then
        return math.max(lowPowerInterval or 1.2, 1.8)
    end
    if dotaTime > 30 * 60 then
        return math.max(lowPowerInterval or 1.0, 1.25)
    end

    return lowPowerInterval
end

return Scheduler
