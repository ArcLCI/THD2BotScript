local Avoidance = {}

-- 所有原生避让能力必须逐阶段实机通过后才允许启用。
Avoidance.ENABLED = true
Avoidance.TOWER_ESCAPE_ENABLED = true
Avoidance.PROBE_MODE_LOAD = false
Avoidance.PROBE_PHASE = 0
Avoidance.PROBE_TARGET_TEAM = TEAM_RADIANT
Avoidance.USE_NATIVE_ZONES = false
Avoidance.USE_NATIVE_REMOVE = false
Avoidance.USE_NATIVE_PATH = false
Avoidance.EXECUTE_NATIVE_PATH = false
Avoidance.DEBUG_LOG = true
-- P8-20TG 区分短期塔几何记忆与危险租约，记录完整路径集合。
Avoidance.DEBUG_CANDIDATE_DESIRE = true
Avoidance.DEBUG_DRAW = false
Avoidance.RUN_ID = '20260902-P8-01R-20TG-10B'

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
Avoidance.NATIVE_ZONE_TTL = 0.75
Avoidance.NATIVE_ZONE_REFRESH = 0.50
Avoidance.PATH_TIMEOUT = 0.25
Avoidance.PATH_CLEARANCE_TOLERANCE = 32
Avoidance.CLEARANCE_HOLD_TIME = 0.60
Avoidance.RECENT_TOWER_DAMAGE_TIME = 1.00
Avoidance.DIRECT_ACTION_INTERVAL = 0.18
Avoidance.NATIVE_ACTION_INTERVAL = 0.35
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
Avoidance.HANDOFF_FALLBACK_STALL_PROBE = false
Avoidance.HANDOFF_FALLBACK_STALL_PROBE_HOLD_TIME = 1.60
Avoidance.PROBE_MODE_LOAD_HOLD = 1.00

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
