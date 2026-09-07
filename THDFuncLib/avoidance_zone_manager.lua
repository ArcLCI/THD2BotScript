local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')

local Manager = {}

-- Lua 注册表是唯一事实来源；原生句柄只保存和移除，绝不从引擎回读区域。

local function Now()
	if type(DotaTime) == 'function' then
		local ok, value = pcall(DotaTime)
		if ok and type(value) == 'number' then return value end
	end
	return 0
end

local function GetPlayerID(bot)
	if bot == nil or type(bot.GetPlayerID) ~= 'function' then return -1 end
	local ok, value = pcall(function() return bot:GetPlayerID() end)
	return ok and value or -1
end

local function GetTeam(bot)
	if bot == nil or type(bot.GetTeam) ~= 'function' then return -1 end
	local ok, value = pcall(function() return bot:GetTeam() end)
	return ok and value or -1
end

local function NativeLog(bot, phase, zone, api, stage, extra)
	print(string.format(
		'[BOT][AvoidanceDev] run=%s phase=%s team=%s player=%s generation=%s zone=%s api=%s stage=%s game_time=%.3f %s',
		tostring(Config.RUN_ID or 'unset'), tostring(phase or 'runtime'), tostring(GetTeam(bot)),
		tostring(GetPlayerID(bot)), tostring(bot and bot.THD_TowerEscapeGeneration or 0),
		tostring(zone and zone.key or 'none'), tostring(api), tostring(stage), Now(), tostring(extra or '')))
end

local function DebugLog(bot, message)
	if Config.DEBUG_LOG ~= true then return end
	NativeLog(bot, 'runtime', nil, 'none', 'status', message)
end

local function GetState(bot)
	if bot.THD_AvoidanceZoneState == nil then
		bot.THD_AvoidanceZoneState = {
			zones = {},
		}
	end
	return bot.THD_AvoidanceZoneState
end

local function GeometryLifetime()
	-- 即使把额外记忆时长调低，也不能丢掉当前活动快照的几何约束。
	return math.max(tonumber(Config.LUA_ZONE_TTL) or 1,
		tonumber(Config.TOWER_GEOMETRY_MEMORY_TIME) or 30)
end

local function CopyZone(snapshot, now)
	return {
		key = snapshot.key,
		center = Geometry.MakeVector(snapshot.center.x or 0, snapshot.center.y or 0, snapshot.center.z or 0),
		radius = snapshot.radius,
		effectiveRadius = snapshot.effectiveRadius,
		createdAt = now,
		expiresAt = now + Config.LUA_ZONE_TTL,
		lastSeenAt = now,
		geometryExpiresAt = now + GeometryLifetime(),
		severity = snapshot.highGround and 'high_ground_tower' or 'tower',
		source = snapshot.source or 'visible_enemy_tower',
		sourceName = snapshot.name,
	}
end

local function ObserveGeometry(state, snapshot, now)
	local record = state.zones[snapshot.key]
	if record == nil then
		record = CopyZone(snapshot, now)
		-- 单纯见过塔不等于当前危险；活动 TTL 由下面的策略内快照单独刷新。
		record.expiresAt = -90
		state.zones[snapshot.key] = record
	end
	record.center = Geometry.MakeVector(snapshot.center.x or 0, snapshot.center.y or 0, snapshot.center.z or 0)
	record.radius = snapshot.radius
	record.effectiveRadius = snapshot.effectiveRadius
	record.severity = snapshot.highGround and 'high_ground_tower' or 'tower'
	record.source = snapshot.source or 'visible_enemy_tower'
	record.sourceName = snapshot.name
	record.lastSeenAt = now
	record.geometryExpiresAt = now + GeometryLifetime()
	return record
end

function Manager.UpsertSnapshots(bot, snapshots, now, visibleSnapshots)
	if bot == nil then return {} end
	now = now or Now()
	local state = GetState(bot)
	local active = {}
	-- 共用一份注册表，保存原始可见数值；授权过滤不会伪装成塔消失。
	for _, snapshot in ipairs(visibleSnapshots or snapshots or {}) do
		if snapshot.key ~= nil and snapshot.center ~= nil then
			ObserveGeometry(state, snapshot, now)
		end
	end
	for _, snapshot in ipairs(snapshots or {}) do
		if snapshot.key ~= nil and snapshot.center ~= nil then
			local record = state.zones[snapshot.key] or ObserveGeometry(state, snapshot, now)
			record.expiresAt = now + Config.LUA_ZONE_TTL
			table.insert(active, record)
		end
	end
	for key, record in pairs(state.zones) do
		if now >= (record.expiresAt or -90)
		and now >= (record.geometryExpiresAt or -90) then
			if Config.DEBUG_LOG == true then
				NativeLog(bot, 'runtime', record, 'none', 'geometry-memory', string.format(
					'result=expired last_seen_age=%.3f', math.max(0, now - (record.lastSeenAt or now))))
			end
			state.zones[key] = nil
		end
	end
	return active
end

local Native
local function NativeAdapter()
	if Native == nil and (Config.USE_NATIVE_ZONES or Config.USE_NATIVE_REMOVE) then
		Native = require(GetScriptDirectory()..'/THDFuncLib/avoidance_native_zones')
	end
	return Native
end

function Manager.SyncNative(bot, records, excludedKeys, phase)
	local adapter = NativeAdapter()
	if adapter == nil then return 0 end
	return adapter.SyncNative(bot, records, excludedKeys, phase)
end

function Manager.ReleaseNative(bot, phase)
	if Native ~= nil then Native.ReleaseNative(bot, phase) end
end

function Manager.Reset(bot, phase)
	if bot == nil then return end
	Manager.ReleaseNative(bot, phase)
	bot.THD_AvoidanceZoneState = nil
end

function Manager.ReleaseActive(bot, phase)
	if bot == nil or bot.THD_AvoidanceZoneState == nil then return end
	Manager.ReleaseNative(bot, phase)
	-- 正常交接只释放活动危险；短期几何记忆跨租约保留，死亡/禁用仍用 Reset 清空。
	for _, record in pairs(GetState(bot).zones) do record.expiresAt = -90 end
end

function Manager.GetRecords(bot)
	if bot == nil then return {} end
	local result = {}
	local now = Now()
	for _, record in pairs(GetState(bot).zones) do
		if now < (record.expiresAt or -90) then table.insert(result, record) end
	end
	table.sort(result, function(first, second) return tostring(first.key) < tostring(second.key) end)
	return result
end

function Manager.GetGeometryRecords(bot)
	if bot == nil then return {} end
	local result = {}
	local now = Now()
	for _, record in pairs(GetState(bot).zones) do
		if now < (record.geometryExpiresAt or -90) then table.insert(result, record) end
	end
	table.sort(result, function(first, second) return tostring(first.key) < tostring(second.key) end)
	return result
end

function Manager.GetNativeCapability(bot)
	local adapter = NativeAdapter()
	return adapter ~= nil and adapter.GetNativeCapability(bot) or {add = false, remove = false}
end

return Manager
