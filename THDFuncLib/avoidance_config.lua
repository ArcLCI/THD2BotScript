local Research = require(GetScriptDirectory()..'/THDFuncLib/avoidance_research_config')
local Diagnostics = require(GetScriptDirectory()..'/THDFuncLib/bot_diagnostics_config')
local Avoidance = {}

-- 所有原生避让能力必须逐阶段实机通过后才允许启用。
Avoidance.ENABLED = true
Avoidance.TOWER_ESCAPE_ENABLED = true
Avoidance.PROBE_MODE_LOAD = Research.PROBE_MODE_LOAD
Avoidance.PROBE_PHASE = Research.PROBE_PHASE
Avoidance.PROBE_TARGET_TEAM = Research.PROBE_TARGET_TEAM
Avoidance.USE_NATIVE_ZONES = Research.USE_NATIVE_ZONES
Avoidance.USE_NATIVE_REMOVE = Research.USE_NATIVE_REMOVE
Avoidance.USE_NATIVE_PATH = Research.USE_NATIVE_PATH
Avoidance.EXECUTE_NATIVE_PATH = Research.EXECUTE_NATIVE_PATH
Avoidance.DEBUG_LOG = Diagnostics.DEBUG_LOG
-- P8-23RF 保留22SR恢复行为；诊断与研究配置独立维护。
Avoidance.DEBUG_CANDIDATE_DESIRE = Diagnostics.DEBUG_CANDIDATE_DESIRE
Avoidance.DEBUG_DRAW = Diagnostics.DEBUG_DRAW
Avoidance.RUN_ID = Diagnostics.RUN_ID

Avoidance.TARGET_TEAM = nil
-- 双方十 Bot；原生区域与手动探针保持关闭，高地围攻许可不变。
Avoidance.RUNTIME_TEST_PLAYER_ID = nil
Avoidance.TOWER_SCAN_RANGE = 2800
Avoidance.TOWER_EXIT_BUFFER = 200
Avoidance.TOWER_EXIT_HYSTERESIS = 64
Avoidance.LUA_ROUTE_SAFETY_MARGIN = 160
Avoidance.DIRECT_EGRESS_SAFETY_MARGIN = 96
-- Lua waypoint 接管前必须在联合净空外连续稳定，避免刚跨边界就被导航或位移拉回塔圆。
Avoidance.PATH_HANDOFF_CLEARANCE_MARGIN = 160
Avoidance.PATH_HANDOFF_CLEARANCE_HOLD_TIME = 0.35
Avoidance.ROUTE_CLEAR_COMMIT_TIME = 0.45
Avoidance.ESCAPE_ANCHOR_DISTANCE = 1400
Avoidance.LUA_ZONE_TTL = 1.00
-- 只记曾可见塔的数值几何；不缓存锁定/伤害状态，不据此取得或延长租约。
Avoidance.TOWER_GEOMETRY_MEMORY_TIME = 30.00
Avoidance.GEOMETRY_SNAPSHOT_LOG_INTERVAL = 1.00
Avoidance.NATIVE_ZONE_TTL = Research.NATIVE_ZONE_TTL
Avoidance.NATIVE_ZONE_REFRESH = Research.NATIVE_ZONE_REFRESH
Avoidance.PATH_TIMEOUT = Research.PATH_TIMEOUT
Avoidance.PATH_CLEARANCE_TOLERANCE = 32
Avoidance.CLEARANCE_HOLD_TIME = 0.60
Avoidance.RECENT_TOWER_DAMAGE_TIME = 1.00
Avoidance.DIRECT_ACTION_INTERVAL = 0.18
Avoidance.NATIVE_ACTION_INTERVAL = 0.35
-- 同一位置/几何最多三次失败请求；真实位移或输入变化才重新计数。
Avoidance.PATH_FAILURE_RETRY_TIME = 0.75
Avoidance.PATH_FAILURE_MAX_ATTEMPTS = 3
Avoidance.RECOVERY_PROGRESS_DISTANCE = 96
Avoidance.RECOVERY_STALL_TIME = 1.50
Avoidance.RECOVERY_SEARCH_INTERVAL = 0.75
Avoidance.RECOVERY_MAX_SEARCHES = 3
-- 失败释放后低频探查；有可执行安全细步才重新取得租约。
Avoidance.RECOVERY_ADMISSION_INTERVAL = 3.00
Avoidance.RECOVERY_MAX_DISTANCE = 1400
Avoidance.OBJECTIVE_ESCAPE_GRACE = 2.50
Avoidance.HIGH_LEVEL_TEAMFIGHT_TOWER_PRIORITY_ENABLED = true
Avoidance.HIGH_LEVEL_TEAMFIGHT_MIN_BOT_LEVEL = 25
Avoidance.HIGH_LEVEL_TEAMFIGHT_MIN_TEAM_AVERAGE_LEVEL = 25
Avoidance.HIGH_LEVEL_TEAMFIGHT_MAX_HIGH_GROUND_TOWERS = 1
Avoidance.HIGH_LEVEL_TEAMFIGHT_POLICY_LOG_INTERVAL = 1.00
Avoidance.MODE_HANDOFF_STALE_TIME = 1.00
Avoidance.HANDOFF_FALLBACK_ENABLED = true
Avoidance.HANDOFF_FALLBACK_START_TIME = 1.00
Avoidance.HANDOFF_FALLBACK_ACTION_INTERVAL = 0.75
Avoidance.HANDOFF_FALLBACK_STEP_DISTANCE = 900
-- 预算限制释放后的续发；保留一个冻结终点，不清除其他任务的动作。
Avoidance.HANDOFF_FALLBACK_MAX_TIME = 4.00
Avoidance.HANDOFF_FALLBACK_MAX_TRAVEL = 1200
Avoidance.HANDOFF_FALLBACK_REACH_DISTANCE = 180
Avoidance.HANDOFF_FALLBACK_STALL_TIME = 1.50
Avoidance.HANDOFF_FALLBACK_PROGRESS_DISTANCE = 48
Avoidance.HANDOFF_FALLBACK_RETARGET_MIN_DISTANCE = 240
Avoidance.HANDOFF_FALLBACK_STALL_PROBE = Research.HANDOFF_FALLBACK_STALL_PROBE
Avoidance.HANDOFF_FALLBACK_STALL_PROBE_HOLD_TIME = Research.HANDOFF_FALLBACK_STALL_PROBE_HOLD_TIME
Avoidance.PROBE_MODE_LOAD_HOLD = Research.PROBE_MODE_LOAD_HOLD

function Avoidance.IsModeOverrideEnabled()
	return Avoidance.ENABLED == true
		and Avoidance.TOWER_ESCAPE_ENABLED == true
		and not Avoidance.IsAnyProbeEnabled()
end

function Avoidance.IsRuntimeTarget(bot)
	if bot == nil or type(bot.GetTeam) ~= 'function' or type(bot.GetPlayerID) ~= 'function' then
		return false
	end
	local teamOK, team = pcall(function() return bot:GetTeam() end)
	if not teamOK or (Avoidance.TARGET_TEAM ~= nil and team ~= Avoidance.TARGET_TEAM) then
		return false
	end
	if Avoidance.RUNTIME_TEST_PLAYER_ID == nil then return true end
	local playerOK, playerID = pcall(function() return bot:GetPlayerID() end)
	return playerOK and playerID == Avoidance.RUNTIME_TEST_PLAYER_ID
end

function Avoidance.IsAnyProbeEnabled()
	return Avoidance.PROBE_MODE_LOAD == true
		or (tonumber(Avoidance.PROBE_PHASE) or 0) > 0
end

return Avoidance
