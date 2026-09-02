local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local ModeDesireDebug = {}
local wastelandOK, Wasteland = pcall(
	require,
	GetScriptDirectory()..'/THDFuncLib/wasteland_strategy'
)
local thdFuncOK, J = pcall(
	require,
	GetScriptDirectory()..'/THDFuncLib/thd_func'
)

-- 即使 Bot API 不暴露 entity index，也能按 PID + logger_instance 区分脚本重载代际。
local instanceSequence = (rawget(_G, 'THDModeDesireDebugInstanceSequence') or 0) + 1
rawset(_G, 'THDModeDesireDebugInstanceSequence', instanceSequence)
local instanceClock = type(GameTime) == 'function' and GameTime()
	or (type(DotaTime) == 'function' and DotaTime()) or 0
local loggerInstance = string.format('%d-%d', math.floor(instanceClock * 1000 + 0.5), instanceSequence)

-- 当前模式倾向复测期间开启；完成日志采集后可改为 false。
ModeDesireDebug.ENABLED = true
ModeDesireDebug.SAMPLE_INTERVAL = 0.5

local MODE_NAMES = {}

local function RegisterMode(mode, name)
	if type(mode) == 'number' then
		MODE_NAMES[mode] = name
	end
end

RegisterMode(BOT_MODE_NONE, 'none')
RegisterMode(BOT_MODE_LANING, 'laning')
RegisterMode(BOT_MODE_ATTACK, 'attack')
RegisterMode(BOT_MODE_ROAM, 'roam')
RegisterMode(BOT_MODE_RETREAT, 'retreat')
RegisterMode(BOT_MODE_SECRET_SHOP, 'secret_shop')
RegisterMode(BOT_MODE_SIDE_SHOP, 'side_shop')
RegisterMode(BOT_MODE_RUNE, 'rune')
RegisterMode(BOT_MODE_PUSH_TOWER_TOP, 'push_top')
RegisterMode(BOT_MODE_PUSH_TOWER_MID, 'push_mid')
RegisterMode(BOT_MODE_PUSH_TOWER_BOT, 'push_bot')
RegisterMode(BOT_MODE_DEFEND_TOWER_TOP, 'defend_top')
RegisterMode(BOT_MODE_DEFEND_TOWER_MID, 'defend_mid')
RegisterMode(BOT_MODE_DEFEND_TOWER_BOT, 'defend_bot')
RegisterMode(BOT_MODE_ASSEMBLE, 'assemble')
RegisterMode(BOT_MODE_TEAM_ROAM, 'team_roam')
RegisterMode(BOT_MODE_FARM, 'farm')
RegisterMode(BOT_MODE_DEFEND_ALLY, 'defend_ally')
RegisterMode(BOT_MODE_EVASIVE_MANEUVERS, 'evasive_maneuvers')
RegisterMode(BOT_MODE_ROSHAN, 'roshan')
RegisterMode(BOT_MODE_ITEM, 'item')
RegisterMode(BOT_MODE_WARD, 'ward')
RegisterMode(BOT_MODE_TWIN_GATE, 'twin_gate')
RegisterMode(BOT_MODE_OUTPOST, 'outpost')
RegisterMode(BOT_MODE_CHALLENGE_ENDGAME, 'challenge_endgame')
RegisterMode(BOT_MODE_WATCHER, 'watcher')
RegisterMode(BOT_MODE_WISDOM_RUNE, 'wisdom_shrine')
RegisterMode(BOT_MODE_WISDOM_SHRINE, 'wisdom_shrine')
RegisterMode(BOT_MODE_LOTUS_POOL, 'lotus_pool')
RegisterMode(BOT_MODE_DEWARD, 'deward')

-- Dota 2 7.38 的新增模式常量并非所有 Bot Lua 环境都会导出，保留数值回退避免再次出现 unknown_26。
local function RegisterModeFallback(mode, name)
	if MODE_NAMES[mode] == nil then MODE_NAMES[mode] = name end
end
RegisterModeFallback(26, 'outpost')
RegisterModeFallback(27, 'challenge_endgame')
RegisterModeFallback(28, 'watcher')
RegisterModeFallback(29, 'wisdom_shrine')
RegisterModeFallback(30, 'lotus_pool')
RegisterModeFallback(31, 'deward')

local function GetPlayerId(bot)
	if bot == nil then return -1 end
	if type(bot.GetPlayerID) ~= 'function' then return -1 end
	local playerId = bot:GetPlayerID()
	if type(playerId) ~= 'number' then return -1 end
	return playerId
end

local function GetUnitId(bot)
	if bot == nil then return -1 end
	if type(bot.entindex) == 'function' then
		local ok, unitId = pcall(function() return bot:entindex() end)
		if ok and type(unitId) == 'number' then return unitId end
	end
	if type(bot.GetEntityIndex) == 'function' then
		local ok, unitId = pcall(function() return bot:GetEntityIndex() end)
		if ok and type(unitId) == 'number' then return unitId end
	end
	return -1
end

local function GetUnitName(unit)
	if unit == nil or type(unit.GetUnitName) ~= 'function' then return 'none' end
	local ok, name = pcall(function() return unit:GetUnitName() end)
	return ok and name ~= nil and tostring(name) or 'unknown'
end

local function GetAttackTarget(bot)
	if type(bot.GetAttackTarget) ~= 'function' then return nil end
	local ok, target = pcall(function() return bot:GetAttackTarget() end)
	if not ok or target == nil then return nil end
	if type(target.IsNull) == 'function' then
		local nullOK, isNull = pcall(function() return target:IsNull() end)
		if nullOK and isNull then return nil end
	end
	return target
end

local function GetUnitKind(unit)
	if unit == nil then return 'none' end
	for methodName, kind in pairs({
		IsHero = 'hero',
		IsBuilding = 'building',
		IsCreep = 'creep',
	}) do
		if type(unit[methodName]) == 'function' then
			local ok, matched = pcall(function() return unit[methodName](unit) end)
			if ok and matched then return kind end
		end
	end
	return 'unit'
end

local function GetObjectiveSnapshot(bot)
	if not wastelandOK or type(Wasteland) ~= 'table'
		or type(Wasteland.GetPushObjectiveDebugSnapshot) ~= 'function'
	then
		return nil
	end
	local ok, snapshot = pcall(function()
		return Wasteland.GetPushObjectiveDebugSnapshot(bot)
	end)
	return ok and type(snapshot) == 'table' and snapshot or nil
end

local function GetRoshanSnapshot(bot)
	if not thdFuncOK or type(J) ~= 'table'
		or type(J.GetRoshanCommitmentDebugSnapshot) ~= 'function'
	then
		return nil
	end
	local ok, snapshot = pcall(function()
		return J.GetRoshanCommitmentDebugSnapshot(bot)
	end)
	return ok and type(snapshot) == 'table' and snapshot or nil
end

local function IsCurrentTeamMember(bot)
	if type(GetTeamPlayers) ~= 'function' or type(GetTeamMember) ~= 'function' then return true end
	local playerId = GetPlayerId(bot)
	if playerId < 0 or type(bot.GetTeam) ~= 'function' then return true end

	local teamOk, team = pcall(function() return bot:GetTeam() end)
	if not teamOk then return true end
	local playersOk, players = pcall(function() return GetTeamPlayers(team) end)
	if not playersOk or type(players) ~= 'table' then return true end

	for index, listedPlayerId in ipairs(players) do
		if listedPlayerId == playerId then
			local memberOk, member = pcall(function() return GetTeamMember(index) end)
			-- 只有明确取得当前队员句柄后才淘汰旧实例，查询失败时不制造整队日志盲区。
			if not memberOk or member == nil or member == bot then return true end
			local memberUnitId = GetUnitId(member)
			local botUnitId = GetUnitId(bot)
			return memberUnitId >= 0 and botUnitId >= 0 and memberUnitId == botUnitId
		end
	end
	return false
end

local function GetState(bot)
	if bot.THDModeDesireDebugState == nil then
		bot.THDModeDesireDebugState = {
			nextSampleTime = -9999,
			lastSampleTime = nil,
			lastMode = nil,
			modeStats = {},
		}
	end
	return bot.THDModeDesireDebugState
end

function ModeDesireDebug.GetModeName(mode)
	return MODE_NAMES[mode] or ('unknown_' .. tostring(mode))
end

function ModeDesireDebug.Think(bot)
	if ModeDesireDebug.ENABLED ~= true or bot == nil then return false end
	if not IsCurrentTeamMember(bot) then return false end
	if type(bot.GetActiveMode) ~= 'function'
		or type(bot.GetActiveModeDesire) ~= 'function'
	then
		return false
	end

	local dotaTime = DotaTime()
	if type(dotaTime) ~= 'number' then return false end
	local mode = bot:GetActiveMode()
	if dotaTime < 0 then
		local evasiveMode = rawget(_G, 'BOT_MODE_EVASIVE_MANEUVERS')
		if bot.THD_AvoidanceModeLoadProbeActive ~= true
		or evasiveMode == nil or mode ~= evasiveMode
		then
			return false
		end
	end

	local state = GetState(bot)
	local modeChanged = state.lastMode ~= mode
	if not modeChanged and dotaTime < state.nextSampleTime then return false end

	local desire = bot:GetActiveModeDesire()
	if type(desire) ~= 'number' then return false end

	local stats = state.modeStats[mode]
	if stats == nil then
		stats = { min = desire, max = desire, samples = 0 }
		state.modeStats[mode] = stats
	end
	stats.min = math.min(stats.min, desire)
	stats.max = math.max(stats.max, desire)
	stats.samples = stats.samples + 1

	state.lastMode = mode
	local sampleDelta = state.lastSampleTime == nil and -1 or math.max(0, dotaTime - state.lastSampleTime)
	state.lastSampleTime = dotaTime
	state.nextSampleTime = dotaTime + ModeDesireDebug.SAMPLE_INTERVAL

	local gameTime = type(GameTime) == 'function' and GameTime() or dotaTime
	local team = type(bot.GetTeam) == 'function' and bot:GetTeam() or -1
	local hero = type(bot.GetUnitName) == 'function' and bot:GetUnitName() or 'unknown'
	local alive = type(bot.IsAlive) ~= 'function' or bot:IsAlive()
	local attackTarget = GetAttackTarget(bot)
	local objective = GetObjectiveSnapshot(bot)
	local roshan = GetRoshanSnapshot(bot)
	local objectiveTarget = objective ~= nil and objective.target or nil
	local attackTargetId = GetUnitId(attackTarget)
	local objectiveTargetId = GetUnitId(objectiveTarget)
	local attackTargetIsObjective = attackTarget ~= nil and objectiveTarget ~= nil
		and ((attackTargetId >= 0 and objectiveTargetId >= 0 and attackTargetId == objectiveTargetId)
			or attackTarget == objectiveTarget)
	print(string.format(
		'[BOT][ModeDesire] schema=5 dota_time=%.2f game_time=%.2f team=%s pid=%s unit_id=%s logger_instance=%s hero=%s alive=%d mode_id=%s mode=%s desire=%.3f observed_min=%.3f observed_max=%.3f mode_samples=%d changed=%d sample_dt=%.3f attack_target_id=%s attack_target_pid=%s attack_target_name=%s attack_target_kind=%s objective_id=%s objective_phase=%s objective_lane=%s objective_tier=%s objective_participant=%d objective_role=%s objective_target_id=%s objective_target_key=%s attack_target_is_objective=%d roshan_raw_mode=%d roshan_commitment_active=%d roshan_commitment_reason=%s roshan_target_name=%s roshan_kill_game_time=%.2f roshan_kill_age=%.2f roshan_last_evidence_age=%.2f roshan_grace_remaining=%.2f roshan_pit_distance=%.1f roshan_allies_near_pit=%s',
		dotaTime,
		gameTime,
		tostring(team),
		tostring(GetPlayerId(bot)),
		tostring(GetUnitId(bot)),
		loggerInstance,
		tostring(hero),
		alive and 1 or 0,
		tostring(mode),
		ModeDesireDebug.GetModeName(mode),
		desire,
		stats.min,
		stats.max,
		stats.samples,
		modeChanged and 1 or 0,
		sampleDelta,
		tostring(attackTargetId),
		tostring(GetPlayerId(attackTarget)),
		GetUnitName(attackTarget),
		GetUnitKind(attackTarget),
		tostring(objective ~= nil and objective.id or 'none'),
		tostring(objective ~= nil and objective.phase or 'none'),
		tostring(objective ~= nil and objective.lane or -1),
		tostring(objective ~= nil and objective.tier or -1),
		objective ~= nil and objective.participant == true and 1 or 0,
		tostring(objective ~= nil and objective.role or 'none'),
		tostring(objectiveTargetId),
		tostring(objective ~= nil and objective.targetKey or 'none'),
		attackTargetIsObjective and 1 or 0,
		roshan ~= nil and roshan.rawMode == true and 1 or 0,
		roshan ~= nil and roshan.active == true and 1 or 0,
		tostring(roshan ~= nil and roshan.reason or 'unavailable'),
		GetUnitName(roshan ~= nil and roshan.target or nil),
		roshan ~= nil and tonumber(roshan.killGameTime) or -1,
		roshan ~= nil and tonumber(roshan.killAge) or -1,
		roshan ~= nil and tonumber(roshan.lastEvidenceAge) or -1,
		roshan ~= nil and tonumber(roshan.graceRemaining) or 0,
		roshan ~= nil and tonumber(roshan.pitDistance) or -1,
		tostring(roshan ~= nil and roshan.alliesNearPit or -1)
	))
	CandidateDebug.Flush(bot, loggerInstance)
	return true
end

return ModeDesireDebug
