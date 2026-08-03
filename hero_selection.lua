local loadOK, LaneAssignment = pcall(
	require,
	GetScriptDirectory() .. "/THDFuncLib/lane_assignment"
)
local printedLoadError = false
local printedRuntimeError = false

local function FallbackAssignments()
	local players = GetTeamPlayers(GetTeam()) or {}
	if loadOK and LaneAssignment ~= nil then
		return LaneAssignment.BuildFallback(GetTeam(), #players)
	end

	-- 即使框架加载失败也返回确定性分路，不重新落回原版英雄分路表。
	local sequence = {LANE_MID, nil, nil, nil, nil, LANE_MID, nil, nil, LANE_MID, nil, nil, LANE_MID}
	local safeLane = GetTeam() == TEAM_DIRE and LANE_TOP or LANE_BOT
	local offLane = GetTeam() == TEAM_DIRE and LANE_BOT or LANE_TOP
	sequence[2], sequence[3], sequence[4], sequence[5] = safeLane, offLane, safeLane, offLane
	sequence[7], sequence[8], sequence[10], sequence[11] = safeLane, offLane, safeLane, offLane
	local result = {}
	for index = 1, #players do result[index] = sequence[index] or LANE_MID end
	return result
end

function UpdateLaneAssignments()
	if not loadOK or LaneAssignment == nil then
		if not printedLoadError then
			printedLoadError = true
			print("[BOT][LaneAssign] framework load failed: " .. tostring(LaneAssignment))
		end
		return FallbackAssignments()
	end

	local ok, assignments = pcall(LaneAssignment.UpdateLaneAssignments)
	if ok and type(assignments) == "table" then return assignments end
	if not printedRuntimeError then
		printedRuntimeError = true
		print("[BOT][LaneAssign] planner failed: " .. tostring(assignments))
	end
	return FallbackAssignments()
end
