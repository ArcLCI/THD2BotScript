local Scheduler = {}

local DEFAULT_PHASE_INTERVAL = 0.12
local BASE_ENEMY_SCAN_RANGE = 1800
local OBJECTIVE_THINK_INTERVAL = 0.25
Scheduler.DEBUG_OBJECTIVE_INTERVAL = false
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

function Scheduler.GetLowPowerThinkInterval(bot, normalInterval, lowPowerInterval)
    if Scheduler.IsInCombat(bot) then
        return normalInterval
    end

    -- 六个实际推塔/守塔模式采用固定目标周期，避免误落入 1.25 秒以上的低功耗分支。
    if bot ~= nil and Scheduler.IsObjectiveMode(bot:GetActiveMode()) then
		if Scheduler.DEBUG_OBJECTIVE_INTERVAL == true then
			local now = Scheduler.Now()
			if now - (bot.SchedulerObjectiveIntervalLogAt or -9999) >= OBJECTIVE_DEBUG_LOG_INTERVAL then
				bot.SchedulerObjectiveIntervalLogAt = now
				print(string.format('[BOT][Scheduler] pid=%s action=objective_interval mode=%s interval=%.2f game_time=%.1f',
					tostring(Scheduler.GetPlayerId(bot)), tostring(bot:GetActiveMode()),
					OBJECTIVE_THINK_INTERVAL, now))
			end
		end
        return OBJECTIVE_THINK_INTERVAL
    end
    if Scheduler.IsHighPriorityState(bot) then return normalInterval end

    local gameTime = DotaTime()
    if gameTime > 40 * 60 then
        return math.max(lowPowerInterval or 1.2, 1.8)
    end
    if gameTime > 30 * 60 then
        return math.max(lowPowerInterval or 1.0, 1.25)
    end

    return lowPowerInterval
end

return Scheduler
