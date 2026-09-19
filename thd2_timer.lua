local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Scheduler = require(GetScriptDirectory()..'/thd2_scheduler')
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
        if type(key) == 'string' and key:sub(1, 13) == 'DefendDesire-' then
            CandidateDebug.CacheHit(cacheStore[key], Timer.Now() - cacheStore[key].time, 'timer:' .. key)
        end
        return cachedValue
    end

    local computedValue = computeFn()
    Timer.Set(key, computedValue)
    if type(key) == 'string' and key:sub(1, 13) == 'DefendDesire-' then CandidateDebug.SaveCache(cacheStore[key]) end
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
    if Scheduler.RELAXED_THINK_ENABLED then return 0 end
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
    -- 守塔欲望缓存与公共决策周期一致，避免玩家编号叠加出额外响应延迟。
    local effectiveInterval = Scheduler.GetDecisionInterval(interval) + Timer.GetStaggerOffset(bot, lane, staggerInterval)
    return Timer.GetOrCompute(key, effectiveInterval, computeFn)
end

function Timer.ShouldRunBotTask(bot, taskName, interval, staggerInterval)
    if bot == nil then
        return true
    end

    if interval == nil then
        interval = 1.0
    end
    interval = Scheduler.GetDecisionInterval(interval)

    local key = 'timer-task-' .. taskName .. '-' .. tostring(Timer.GetPlayerId(bot))
    local now = Timer.Now()
    local entry = cacheStore[key]
    if entry == nil then
        cacheStore[key] = {
            value = true,
            time = now + interval + Timer.GetStaggerOffset(bot, nil, staggerInterval),
        }
        return true
    end

    if now < entry.time then
        return false
    end

    entry.time = now + interval
    return true
end

function Timer.ShouldRunBotLaneTask(bot, taskName, lane, interval, staggerInterval)
    return Timer.ShouldRunBotTask(bot, taskName .. '-' .. tostring(lane), interval, staggerInterval)
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
