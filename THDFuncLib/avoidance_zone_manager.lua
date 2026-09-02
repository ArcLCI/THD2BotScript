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
			nativeAddDisabled = false,
			nativeRemoveDisabled = false,
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
		nativeHandle = nil,
		nativeExpiresAt = -90,
		lastNativeAt = -90,
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
		if now >= (record.expiresAt or -90) and now >= (record.nativeExpiresAt or -90)
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

local function RemoveNativeRecord(bot, state, record, phase)
	if record == nil or type(record.nativeHandle) ~= 'number' then return true end
	if Now() >= (record.nativeExpiresAt or -90) then
		-- TTL 已自然结束的句柄不再交给 Remove，避免操作已失效的原生对象。
		record.nativeHandle = nil
		record.nativeExpiresAt = -90
		return true
	end
	if Config.USE_NATIVE_REMOVE ~= true or state.nativeRemoveDisabled then return false end
	if type(RemoveAvoidanceZone) ~= 'function' then
		state.nativeRemoveDisabled = true
		return false
	end
	NativeLog(bot, phase, record, 'RemoveAvoidanceZone', 'before-call',
		'handle=' .. tostring(record.nativeHandle))
	local ok, err = pcall(function() return RemoveAvoidanceZone(record.nativeHandle) end)
	if not ok then
		state.nativeRemoveDisabled = true
		NativeLog(bot, phase, record, 'RemoveAvoidanceZone', 'after-call',
			'result=lua-error error=' .. tostring(err))
		return false
	end
	NativeLog(bot, phase, record, 'RemoveAvoidanceZone', 'after-call', 'result=returned')
	record.nativeHandle = nil
	record.nativeExpiresAt = -90
	return true
end

local function AddNativeRecord(bot, state, record, now, phase)
	if Config.USE_NATIVE_ZONES ~= true or state.nativeAddDisabled then return nil end
	if type(AddAvoidanceZone) ~= 'function' then
		state.nativeAddDisabled = true
		return nil
	end
	if now - (record.lastNativeAt or -90) < Config.NATIVE_ZONE_REFRESH then
		-- Remove 后短时间重新进入目标集合也要遵守每塔刷新间隔，避免句柄抖动。
		if now < (record.nativeExpiresAt or -90) then return record.nativeHandle end
		return nil
	end
	if type(record.nativeHandle) == 'number' and now < (record.nativeExpiresAt or -90) then
		if not RemoveNativeRecord(bot, state, record, phase) then
			-- Remove 不可用时让当前短 TTL 自然过期，不能叠加另一个原生句柄。
			return record.nativeHandle
		end
	end
	local nativeVector = Geometry.MakeVector(record.center.x or 0, record.center.y or 0,
		record.effectiveRadius or record.radius or 0)
	local botLocation = nil
	if type(bot.GetLocation) == 'function' then
		local locationOK, location = pcall(function() return bot:GetLocation() end)
		if locationOK then botLocation = location end
	end
	local extra = string.format(
		'center_x=%.1f center_y=%.1f radius=%.1f duration=%.2f',
		record.center.x or 0, record.center.y or 0,
		record.effectiveRadius or record.radius or 0, Config.NATIVE_ZONE_TTL)
	if botLocation ~= nil then
		extra = extra .. string.format(' bot_x=%.1f bot_y=%.1f center_distance=%.1f',
			botLocation.x or 0, botLocation.y or 0, Geometry.Distance(botLocation, record.center))
	end
	NativeLog(bot, phase, record, 'AddAvoidanceZone', 'before-call', extra)
	local ok, handle = pcall(function()
		return AddAvoidanceZone(nativeVector, Config.NATIVE_ZONE_TTL)
	end)
	if not ok then
		state.nativeAddDisabled = true
		NativeLog(bot, phase, record, 'AddAvoidanceZone', 'after-call',
			'result=lua-error error=' .. tostring(handle))
		return nil
	end
	NativeLog(bot, phase, record, 'AddAvoidanceZone', 'after-call',
		'result=returned handle_type=' .. type(handle) .. ' handle=' .. tostring(handle))
	if type(handle) ~= 'number' then
		state.nativeAddDisabled = true
		return nil
	end
	record.nativeHandle = handle
	record.nativeExpiresAt = now + Config.NATIVE_ZONE_TTL
	record.lastNativeAt = now
	return handle
end

function Manager.SyncNative(bot, records, excludedKeys, phase)
	local registeredCount = 0
	if bot == nil then return registeredCount end
	local state = GetState(bot)
	local now = Now()
	local desiredKeys = {}
	for _, record in ipairs(records or {}) do
		if excludedKeys == nil or excludedKeys[record.key] ~= true then
			desiredKeys[record.key] = true
		end
	end
	-- 原生区域只镜像当前撤退路线；离开路线或进入该圆时立即移除，起点圆不交给原生层。
	for key, record in pairs(state.zones) do
		if type(record.nativeHandle) == 'number' and desiredKeys[key] ~= true then
			RemoveNativeRecord(bot, state, record, phase or 'runtime')
		end
	end
	for _, record in ipairs(records or {}) do
		if desiredKeys[record.key] == true then
			local handle = AddNativeRecord(bot, state, record, now, phase or 'runtime')
			-- 原生句柄封装在 record 内，只用于刷新和 Remove，不传给 GeneratePath。
			if type(handle) == 'number' then registeredCount = registeredCount + 1 end
		end
	end
	return registeredCount
end

function Manager.ReleaseNative(bot, phase)
	if bot == nil or bot.THD_AvoidanceZoneState == nil then return end
	local state = GetState(bot)
	for _, record in pairs(state.zones) do
		RemoveNativeRecord(bot, state, record, phase or 'runtime')
	end
	DebugLog(bot, 'result=native_release_complete')
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
	if bot == nil then return {add = false, remove = false} end
	local state = GetState(bot)
	return {
		add = Config.USE_NATIVE_ZONES == true and not state.nativeAddDisabled,
		remove = Config.USE_NATIVE_REMOVE == true and not state.nativeRemoveDisabled,
	}
end

return Manager
