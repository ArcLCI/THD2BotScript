local Scheduler = {}

local DEFAULT_PHASE_INTERVAL = 0.12

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

function Scheduler.IsHighPriorityState(bot)
    if Scheduler.IsInCombat(bot) then return true end
    if bot == nil or not bot:IsAlive() then return false end

    local mode = bot:GetActiveMode()
    if mode == BOT_MODE_DEFEND_TOWER
        or mode == BOT_MODE_PUSH_TOWER
        or mode == BOT_MODE_ATTACK
        or mode == BOT_MODE_RETREAT
        or mode == BOT_MODE_ROSHAN
    then
        return true
    end

    local ancient = GetAncient(GetTeam())
    if ancient ~= nil and GetUnitToUnitDistance(bot, ancient) < 3600 then
        local enemies = bot:GetNearbyHeroes(1800, true, BOT_MODE_NONE)
        if #enemies > 0 then return true end
    end

    return false
end

function Scheduler.GetLowPowerThinkInterval(bot, normalInterval, lowPowerInterval)
    if Scheduler.IsHighPriorityState(bot) then
        return normalInterval
    end

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
