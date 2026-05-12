local Timer = {}

local cacheStore = {}

local DEFAULT_STAGGER_INTERVAL = 0.08
local LANE_STAGGER_INTERVAL = 0.02

function Timer.Now()
    return GameTime()
end

function Timer.Set(key, value)
    cacheStore[key] = {
        value = value,
        time = Timer.Now(),
    }
end

function Timer.Get(key, interval)
    local entry = cacheStore[key]
    if entry == nil then
        return nil
    end

    if Timer.Now() - entry.time <= interval then
        return entry.value
    end

    return nil
end

function Timer.GetOrCompute(key, interval, computeFn)
    local cachedValue = Timer.Get(key, interval)
    if cachedValue ~= nil then
        return cachedValue
    end

    local computedValue = computeFn()
    Timer.Set(key, computedValue)
    return computedValue
end

function Timer.GetPlayerId(bot)
    if bot == nil then
        return 0
    end

    local playerId = bot:GetPlayerID()
    if playerId == nil or playerId < 0 then
        return 0
    end

    return playerId
end

function Timer.GetStaggerOffset(bot, lane, staggerInterval)
    if staggerInterval == nil then
        staggerInterval = DEFAULT_STAGGER_INTERVAL
    end

    local laneOffset = 0
    if lane ~= nil then
        laneOffset = lane * LANE_STAGGER_INTERVAL
    end

    return Timer.GetPlayerId(bot) * staggerInterval + laneOffset
end

function Timer.GetBotLaneKey(prefix, bot, lane)
    return prefix .. '-' .. tostring(Timer.GetPlayerId(bot)) .. '-' .. tostring(lane)
end

function Timer.GetOrComputeBotLane(prefix, bot, lane, interval, computeFn, staggerInterval)
    local key = Timer.GetBotLaneKey(prefix, bot, lane)
    local effectiveInterval = interval + Timer.GetStaggerOffset(bot, lane, staggerInterval)
    return Timer.GetOrCompute(key, effectiveInterval, computeFn)
end

function Timer.RoundLocationKey(vLoc, bucketSize)
    if bucketSize == nil then
        bucketSize = 500
    end

    local roundedX = math.floor(vLoc.x / bucketSize + 0.5) * bucketSize
    local roundedY = math.floor(vLoc.y / bucketSize + 0.5) * bucketSize
    return tostring(roundedX) .. '-' .. tostring(roundedY)
end

return Timer
