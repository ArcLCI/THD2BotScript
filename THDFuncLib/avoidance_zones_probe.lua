local Probe = {}

-- 危险原生 API 探针默认必须关闭；仅在完全重启后的专用本地对局中临时开启。
Probe.ENABLED = false
Probe.MIN_DOTA_TIME = 1.0
Probe.TARGET_TEAM = TEAM_RADIANT

local attempted = false
local state = {
	status = 'idle',
	playerId = nil,
	dotaTime = nil,
	zoneCount = nil,
	error = nil,
}

local function SetState(status, playerId, dotaTime, zoneCount, err)
	state.status = status
	state.playerId = playerId
	state.dotaTime = dotaTime
	state.zoneCount = zoneCount
	state.error = err
end

local function GetFirstBotPlayerID(team)
	local ok, playerId = pcall(function()
		local players = GetTeamPlayers(team)
		if type(players) ~= 'table' then return nil end
		for _, id in ipairs(players) do
			if IsPlayerBot(id) then return id end
		end
		return nil
	end)
	if not ok then return nil end
	return playerId
end

local function CountRawTableEntries(value)
	if type(value) ~= 'table' then return nil end
	local count = 0
	for _ in next, value do count = count + 1 end
	return count
end

function Probe.TryRun(bot)
	if Probe.ENABLED ~= true or attempted then return false end
	if bot == nil then return false end

	local ok, team, playerId, dotaTime = pcall(function()
		return bot:GetTeam(), bot:GetPlayerID(), DotaTime()
	end)
	if not ok or team ~= Probe.TARGET_TEAM then return false end
	if type(dotaTime) ~= 'number' or dotaTime < Probe.MIN_DOTA_TIME then return false end
	if playerId ~= GetFirstBotPlayerID(team) then return false end

	attempted = true
	SetState('before-call', playerId, dotaTime, nil, nil)
	print(string.format(
		'[BOT][NativeApiProbe] api=GetAvoidanceZones stage=before-call team=%s player=%s dota_time=%.2f',
		tostring(team),
		tostring(playerId),
		dotaTime
	))

	-- pcall 只能记录 Lua 错误，无法拦截 C++ 层 access violation；崩溃时不会出现 after-call。
	local callOK, zones = pcall(function() return GetAvoidanceZones() end)
	if not callOK then
		SetState('lua-error', playerId, dotaTime, nil, tostring(zones))
		print(string.format(
			'[BOT][NativeApiProbe] api=GetAvoidanceZones stage=after-call result=lua-error error=%s',
			tostring(zones)
		))
		return true
	end

	local zoneCount = CountRawTableEntries(zones)
	SetState('returned', playerId, dotaTime, zoneCount, nil)
	print(string.format(
		'[BOT][NativeApiProbe] api=GetAvoidanceZones stage=after-call result=returned value_type=%s zone_count=%s',
		type(zones),
		tostring(zoneCount)
	))
	return true
end

function Probe.GetState()
	return {
		status = state.status,
		playerId = state.playerId,
		dotaTime = state.dotaTime,
		zoneCount = state.zoneCount,
		error = state.error,
	}
end

return Probe
