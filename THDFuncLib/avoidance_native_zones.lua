local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Adapter = {}
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
	if bot.THD_AvoidanceNativeZoneState == nil then
		bot.THD_AvoidanceNativeZoneState = {
			zones = {},
			nativeAddDisabled = false,
			nativeRemoveDisabled = false,
		}
	end
	return bot.THD_AvoidanceNativeZoneState
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

function Adapter.SyncNative(bot, records, excludedKeys, phase)
	local registeredCount = 0
	if bot == nil then return registeredCount end
	local state = GetState(bot)
	local now = Now()
	local desiredKeys = {}
	local nativeRecords = {}
	for _, snapshot in ipairs(records or {}) do
		local record = state.zones[snapshot.key] or {key = snapshot.key}
		record.center, record.radius = snapshot.center, snapshot.radius
		record.effectiveRadius = snapshot.effectiveRadius
		state.zones[snapshot.key] = record
		table.insert(nativeRecords, record)
	end
	records = nativeRecords
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

function Adapter.ReleaseNative(bot, phase)
	if bot == nil or bot.THD_AvoidanceNativeZoneState == nil then return end
	local state = GetState(bot)
	for _, record in pairs(state.zones) do
		RemoveNativeRecord(bot, state, record, phase or 'runtime')
	end
	DebugLog(bot, 'result=native_release_complete')
	-- 保留未过期且无法移除的句柄，避免下一轮重复叠加。
end

function Adapter.GetNativeCapability(bot)
	if bot == nil then return {add = false, remove = false} end
	local state = GetState(bot)
	return {
		add = Config.USE_NATIVE_ZONES == true and not state.nativeAddDisabled,
		remove = Config.USE_NATIVE_REMOVE == true and not state.nativeRemoveDisabled,
	}
end


return Adapter
