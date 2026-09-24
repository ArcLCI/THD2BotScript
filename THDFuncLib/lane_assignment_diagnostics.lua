local Config = require(GetScriptDirectory() .. "/THDFuncLib/lane_assignment_config")
local Diagnostics = {}
local nextReport = {}
local reportedReady = {}

local function LaneName(lane)
	if lane == LANE_TOP then return "TOP" end
	if lane == LANE_MID then return "MID" end
	if lane == LANE_BOT then return "BOT" end
	return "UNKNOWN"
end

function Diagnostics.Observe(bot)
	local config = Config.diagnostics
	if type(config) ~= "table" or config.enabled ~= true or bot == nil then return end
	local now = DotaTime()
	local playerID = bot:GetPlayerID()
	if playerID < 0 then return end
	-- 首次入口标记不受采样时间窗限制，便于区分未执行与错过开局采样。
	if not reportedReady[playerID] then
		reportedReady[playerID] = true
		print(string.format(
			"[BOT][LaneAssignCheck] version=LA-DIAG-20260924-R2 event=ready source=laning_get_desire team=%s pid=%s time=%.1f interval=%s end_time=%s",
			tostring(bot:GetTeam()), tostring(playerID), now,
			tostring(config.interval or 15), tostring(config.endTime or 120)
		))
	end
	if now < 0 or now > (config.endTime or 120) then return end
	if now < (nextReport[playerID] or 0) then return end
	nextReport[playerID] = now + math.max(1, config.interval or 15)

	-- 只读取自己的引擎分路，避免跨脚本重算规划，也不依赖超过五人的队友句柄枚举。
	local lane = bot:GetAssignedLane()
	local team = bot:GetTeam()
	print(string.format(
		"[BOT][LaneAssignCheck] version=LA-DIAG-20260924-R2 event=sample source=laning_get_desire team=%s pid=%s time=%.1f team_size=%d hero=%s assigned=%s lane_id=%s",
		tostring(team), tostring(playerID), now, #(GetTeamPlayers(team) or {}),
		bot:GetUnitName(), LaneName(lane), tostring(lane)
	))
end

return Diagnostics
