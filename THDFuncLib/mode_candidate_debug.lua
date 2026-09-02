local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Debug = {}
local currentCall = nil
local modeNames = {'laning', 'farm', 'assemble', 'push_top', 'push_mid', 'push_bot',
	'defend_top', 'defend_mid', 'defend_bot', 'roam', 'team_roam', 'rune', 'outpost', 'evasive_maneuvers'}

local function Enabled()
	return Config.DEBUG_CANDIDATE_DESIRE == true
end

local function Read(unit, method, fallback)
	local ok, value = pcall(function() return unit[method](unit) end)
	if ok and value ~= nil then return value end
	return fallback
end

local function Now()
	return type(DotaTime) == 'function' and DotaTime() or -1
end

local function Token(value)
	if value == nil then return 'na' end
	if type(value) == 'number' then return string.format('%.17g', value) end
	return tostring(value):gsub('%s+', '_')
end

local function Copy(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

local function GetState(bot)
	if bot.THD_ModeCandidateDebug == nil then
		bot.THD_ModeCandidateDebug = {entries = {}, sequence = 0, lastMode = nil}
	end
	return bot.THD_ModeCandidateDebug
end

function Debug.Note(reason)
	if currentCall ~= nil then currentCall.reason = reason end
end

function Debug.Detail(key, value)
	if currentCall ~= nil then currentCall.details[key] = value end
end

-- 子候选未接管后进入新的计算阶段，不能把辅助缓存命中误标为最终候选也被缓存。
function Debug.BeginPhase(phase)
	if currentCall == nil then return end
	currentCall.reason = nil
	currentCall.evaluation = 'computed'
	for key in pairs(currentCall.details) do currentCall.details[key] = nil end
	currentCall.details.phase = phase
end

-- 缓存原有计算理由，但不改缓存值、失效时间或计算次数。
function Debug.SaveCache(cache)
	if currentCall == nil or cache == nil then return end
	cache.candidateDebugReason = currentCall.reason
	cache.candidateDebugDetails = Copy(currentCall.details)
end

function Debug.CacheHit(cache, age, key)
	if currentCall == nil or cache == nil then return end
	currentCall.reason = cache.candidateDebugReason or 'cached_reason_unavailable'
	for name in pairs(currentCall.details) do currentCall.details[name] = nil end
	for name, value in pairs(cache.candidateDebugDetails or {}) do currentCall.details[name] = value end
	currentCall.details.cache_key = key
	currentCall.details.cache_age = age
	currentCall.evaluation = 'cached'
end

-- 只包住引擎自然调用；绝不为诊断额外求值其他模式，也不吞掉原回调的错误。
function Debug.Wrap(mode, callback)
	if type(callback) ~= 'function' then return callback end
	return function(...)
		if not Enabled() then return callback(...) end
		local bot = GetBot()
		if bot == nil then return callback(...) end
		local state = GetState(bot)
		local entry = state.entries[mode]
		if entry == nil then
			entry = {calls = 0, details = {}, working = {details = {}}}
			state.entries[mode] = entry
		end
		local previous = currentCall
		local call = entry.working
		call.reason = nil
		call.evaluation = 'computed'
		for key in pairs(call.details) do call.details[key] = nil end
		currentCall = call
		local value = callback(...)
		currentCall = previous
		entry.value = value
		entry.reason = call.reason or 'branch_not_annotated'
		entry.details, call.details = call.details, entry.details
		entry.evaluation = call.evaluation
		entry.sampleTime = Now()
		entry.calls = entry.calls + 1
		if type(value) == 'number' then
			entry.minimum = math.min(entry.minimum or value, value)
			entry.maximum = math.max(entry.maximum or value, value)
		end
		return value
	end
end

local function UnitName(unit)
	if unit == nil or Read(unit, 'IsNull', true) then return 'none' end
	return Read(unit, 'GetUnitName', 'unknown')
end

local function Flush(bot, loggerInstance)
	local state = GetState(bot)
	local now = Now()
	local mode = Read(bot, 'GetActiveMode', -1)
	local desire = Read(bot, 'GetActiveModeDesire', nil)
	local interval = type(desire) == 'number' and desire <= 0.05 and 0.5 or 5.0
	if state.lastMode == mode and now - (state.lastFlush or -90) < interval then return end
	state.lastMode = mode
	state.lastFlush = now
	state.sequence = state.sequence + 1
	local avoidance = bot.THD_AvoidanceControllerState or {}
	local location = Read(bot, 'GetLocation', {})
	local common = ' schema=1 run=' .. Token(Config.RUN_ID)
		.. ' team=' .. Token(Read(bot, 'GetTeam', -1))
		.. ' player=' .. Token(Read(bot, 'GetPlayerID', -1))
		.. ' logger_instance=' .. Token(loggerInstance) .. ' sample=' .. state.sequence
		.. ' dota_time=' .. Token(now)
		.. ' avoidance_generation=' .. Token(bot.THD_TowerEscapeGeneration or 0)
	print('[BOT][ModeArbitration]' .. common .. ' active_mode=' .. Token(mode)
		.. ' active_desire=' .. Token(desire) .. ' alive=' .. Token(Read(bot, 'IsAlive', false))
		.. ' action_type=' .. Token(Read(bot, 'GetCurrentActionType', -1))
		.. ' queued=' .. Token(Read(bot, 'NumQueuedActions', -1))
		.. ' attack_target=' .. Token(UnitName(Read(bot, 'GetAttackTarget', nil)))
		.. ' target=' .. Token(UnitName(Read(bot, 'GetTarget', nil)))
		.. ' x=' .. Token(location.x) .. ' y=' .. Token(location.y)
		.. ' casting=' .. Token(Read(bot, 'IsCastingAbility', false))
		.. ' using_ability=' .. Token(Read(bot, 'IsUsingAbility', false))
		.. ' channeling=' .. Token(Read(bot, 'IsChanneling', false))
		.. ' tower_escape_active=' .. Token(avoidance.active == true or bot.THD_TowerEscapeActive == true)
		.. ' handoff_pending=' .. Token(avoidance.handoffPending == true)
		.. ' native_candidates=unobserved')
	for _, name in ipairs(modeNames) do
		local entry = state.entries[name]
		if entry == nil or entry.sampleTime == nil then
			print('[BOT][ModeCandidate]' .. common .. ' mode=' .. name .. ' value=na reason=not_observed')
		else
			local fields = {}
			for key, value in pairs(entry.details) do fields[#fields + 1] = key .. '=' .. Token(value) end
			table.sort(fields)
			-- 各回调不保证同帧到齐；保留年龄和调用数，禁止把未调用/旧值解释为零欲望。
			print('[BOT][ModeCandidate]' .. common .. ' mode=' .. name .. ' value=' .. Token(entry.value)
				.. ' reason=' .. Token(entry.reason) .. ' evaluation=' .. Token(entry.evaluation)
				.. ' sample_age=' .. Token(now - entry.sampleTime) .. ' calls=' .. entry.calls
				.. ' min=' .. Token(entry.minimum) .. ' max=' .. Token(entry.maximum)
				.. (#fields > 0 and (' ' .. table.concat(fields, ' ')) or ''))
			entry.calls = 0
			entry.minimum = nil
			entry.maximum = nil
		end
	end
end

function Debug.Flush(bot, loggerInstance)
	if not Enabled() or bot == nil then return end
	-- 日志失败不影响原有模式与动作；仅一次报告观测故障。
	local ok, err = pcall(Flush, bot, loggerInstance)
	if not ok and not Debug.errorReported then
		Debug.errorReported = true
		print('[BOT][ModeArbitration] logger_error=' .. Token(err))
	end
end

return Debug
