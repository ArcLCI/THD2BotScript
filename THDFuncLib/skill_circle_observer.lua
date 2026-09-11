-- 只读感知门禁：不注册危险区、不发动作，也不接收Game侧诊断数据。
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Observer = {}
local MODIFIER = 'modifier_thd_sanae01_observation'
local function Safe(default, callback)
	local ok, value = pcall(callback)
	if not ok or value == nil then return default end
	return value
end
local function Now() return Safe(0, DotaTime) end
local function Log(bot, event, extra)
	print(string.format('[BOT][SkillCircleProbe] run=%s team=%s player=%s dota_time=%.3f event=%s %s',
		tostring(Config.RUN_ID), tostring(bot:GetTeam()), tostring(bot:GetPlayerID()), Now(), event, extra or ''))
end
local function Selected(bot)
	local cached = bot.THD_SkillCircleObserverSelection
	if cached ~= nil and Now() < cached.expiresAt then return cached.selected end
	local selected = nil
	for _, pid in ipairs(Safe({}, function() return GetTeamPlayers(bot:GetTeam()) end)) do
		if Safe(false, function() return IsPlayerBot(pid) end) and (selected == nil or pid < selected) then selected = pid end
	end
	local result = selected == bot:GetPlayerID()
	bot.THD_SkillCircleObserverSelection = {selected = result, expiresAt = Now() + 5}
	return result
end
function Observer.OnLoaded(bot)
	if bot == nil then return end
	Log(bot, 'loaded', string.format('observe_only=1 selected=%d avoidance_enabled=%d native_path=%d',
		Selected(bot) and 1 or 0, Config.ENABLED and 1 or 0, Config.USE_NATIVE_PATH and 1 or 0))
end
local function Read(callback)
	local ok, value = pcall(callback)
	if not ok then return nil, 'error' end
	if value == nil then return nil, 'nil' end
	return value, 'ok'
end
local function Flag(value, status)
	if status ~= 'ok' then return status end
	if value == true then return 'true' end
	if value == false then return 'false' end
	return 'unexpected'
end
local function Candidate(name)
	return string.find(name, 'thinker', 1, true) ~= nil or string.find(name, 'dummy', 1, true) ~= nil
end
local function ReadSource(bot, unit, location, name, state, now, touched)
	local has, hasStatus = Read(function() return unit:HasModifier(MODIFIER) end)
	local rawIndex, indexStatus = Read(function() return unit:GetModifierByName(MODIFIER) end)
	local index = tonumber(rawIndex) or -1
	local indexedName = index >= 0 and Safe('', function() return unit:GetModifierName(index) end) or ''
	local query = string.format('has_modifier=%d has_status=%s modifier_index=%s index_status=%s indexed_name=%s',
		has == true and 1 or 0, hasStatus, tostring(index), indexStatus, indexedName ~= '' and tostring(indexedName) or 'none')
	if has ~= true and indexedName ~= MODIFIER then return false, hasStatus ~= 'ok' or indexStatus ~= 'ok', query end
	local remaining, remainingStatus, radius, radiusStatus = nil, 'not_read', nil, 'not_read'
	if index >= 0 then
		remaining, remainingStatus = Read(function() return unit:GetModifierRemainingDuration(index) end)
		radius, radiusStatus = Read(function() return unit:GetModifierStackCount(index) end)
	end
	local token = string.gsub(tostring(unit), '%s+', '')
	touched[token] = true
	state.seen[token] = {last = now}
	local carrier = name == 'npc_no_vision_dummy_unit' and 'additive' or (name == 'npc_dota_thinker' and 'thinker' or 'other')
	Log(bot, 'visible_source', string.format(
		'token=%s unit=%s carrier=%s source_team=%s has_modifier=%d has_status=%s modifier_index=%s index_status=%s x=%.1f y=%.1f remaining=%.3f remaining_status=%s marker_radius=%.1f radius_status=%s position_readable=1 visibility_passed=1',
		token, name, carrier, tostring(Safe(-1, function() return unit:GetTeam() end)), has and 1 or 0, hasStatus,
		tostring(index), indexStatus, location.x, location.y, tonumber(remaining) or -1, remainingStatus, tonumber(radius) or -1, radiusStatus))
	return true, hasStatus ~= 'ok' or indexStatus ~= 'ok' or remainingStatus ~= 'ok' or radiusStatus ~= 'ok', query
end
function Observer.Observe(bot)
	if Config.SOURCE_OBSERVATION_ENABLED ~= true or bot == nil or not Selected(bot)
	or not Safe(false, function() return bot:IsAlive() end) then return end
	local state = bot.THD_SkillCircleProbe
	if state == nil then
		state = {nextAt = -90, nextPulse = -90, cursor = 1, seen = {}, enumLog = {}}
		bot.THD_SkillCircleProbe = state
	end
	local now = Now()
	if now < state.nextAt then return end
	state.nextAt = now + 0.5
	local units, listStatus = Read(function() return GetUnitList(UNIT_LIST_ALL) end)
	if type(units) ~= 'table' then units = {}; listStatus = 'invalid_list' end
	local count, checked, valid, unitVisible, locationVisible = #units, 0, 0, 0, 0
	local candidates, candidateVisible, candidateLocation, matched, errors = 0, 0, 0, 0, 0
	local touched, sampleCount = {}, 0
	if state.cursor > count then state.cursor = 1 end
	local first = state.cursor
	for i = first, math.min(count, first + 255) do
		checked = checked + 1
		local unit = units[i]
		local isNull, nullStatus = Read(function() return unit:IsNull() end)
		if nullStatus == 'ok' and isNull == false then
			valid = valid + 1
			-- 枚举阶段仅记录Bot列表已提供的名称，不读取隐藏坐标、modifier或半径。
			local name, nameStatus = Read(function() return unit:GetUnitName() end)
			if type(name) ~= 'string' then name = ''; errors = errors + 1 end
			local candidate = Candidate(name)
			if candidate then candidates = candidates + 1 end
			local seen, seenStatus = Read(function() return unit:CanBeSeen() end)
			local location, positionStatus, locationSeen, locationStatus = nil, 'not_read', nil, 'not_read'
			if seen == true and seenStatus == 'ok' then
				unitVisible = unitVisible + 1
				if candidate then candidateVisible = candidateVisible + 1 end
				location, positionStatus = Read(function() return unit:GetLocation() end)
				if location ~= nil and positionStatus == 'ok' then
					locationSeen, locationStatus = Read(function() return IsLocationVisible(location) end)
				end
			end
			if seenStatus ~= 'ok' or positionStatus == 'error' or locationStatus == 'error' then errors = errors + 1 end
			local readDetails = 'modifier_status=not_read'
			local visible = seen == true and locationSeen == true and positionStatus == 'ok'
			if visible then
				locationVisible = locationVisible + 1
				if candidate then
					candidateLocation = candidateLocation + 1
					local found, readError, query = ReadSource(bot, unit, location, name, state, now, touched)
					readDetails = query
					if found then matched = matched + 1 end
					if readError then errors = errors + 1 end
				end
			end
			if candidate and sampleCount < 8 then
				local token = string.gsub(tostring(unit), '%s+', '')
				if now - (state.enumLog[token] or -90) >= 1 then
					state.enumLog[token] = now
					sampleCount = sampleCount + 1
					Log(bot, 'candidate_visibility', string.format(
						'token=%s unit=%s name_status=%s unit_seen=%s position_status=%s location_seen=%s info_allowed=%d %s',
						token, name, nameStatus, Flag(seen, seenStatus), positionStatus, Flag(locationSeen, locationStatus), visible and 1 or 0, readDetails))
				end
			end
		else
			if nullStatus ~= 'ok' then errors = errors + 1 end
		end
	end
	state.cursor = first + checked
	if state.cursor > count then state.cursor = 1 end
	for token, seen in pairs(state.seen) do
		if not touched[token] and now - seen.last >= 2 then
			Log(bot, 'not_observed', 'token='..token..' ended_confirmed=0')
			state.seen[token] = nil
		end
	end
	for token, last in pairs(state.enumLog) do if now - last > 5 then state.enumLog[token] = nil end end
	if now >= state.nextPulse or candidates > 0 then
		-- 有载体时每次扫描给出流水线计数，空场每5秒心跳，避免错过4秒技能。
		if now >= state.nextPulse then state.nextPulse = now + 5 end
		Log(bot, 'pipeline', string.format(
			'list_status=%s units_total=%d checked=%d valid=%d unit_visible=%d location_visible=%d candidate_enumerated=%d candidate_unit_visible=%d candidate_location_visible=%d matched=%d api_errors=%d paginated=%d observe_only=1',
			listStatus, count, checked, valid, unitVisible, locationVisible, candidates, candidateVisible, candidateLocation, matched, errors, count > 256 and 1 or 0))
	end
end
return Observer
