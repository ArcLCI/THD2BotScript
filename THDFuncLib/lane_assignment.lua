local Generated = require(GetScriptDirectory() .. "/THDFuncLib/lane_assignment_generated")
local Audit = require(GetScriptDirectory() .. "/THDFuncLib/lane_assignment_audit")
local Overrides = require(GetScriptDirectory() .. "/THDFuncLib/lane_assignment_overrides")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")
local Config = require(GetScriptDirectory() .. "/THDFuncLib/lane_assignment_config")

local LaneAssignment = {}

LaneAssignment.POSITION_SAFE_CORE = "safe_core"
LaneAssignment.POSITION_MID = "mid"
LaneAssignment.POSITION_OFF_CORE = "off_core"
LaneAssignment.POSITION_SOFT_SUPPORT = "soft_support"
LaneAssignment.POSITION_HARD_SUPPORT = "hard_support"

local POSITION_NAMES = {
	LaneAssignment.POSITION_SAFE_CORE,
	LaneAssignment.POSITION_MID,
	LaneAssignment.POSITION_OFF_CORE,
	LaneAssignment.POSITION_SOFT_SUPPORT,
	LaneAssignment.POSITION_HARD_SUPPORT,
}

-- 先保留标准五位置，再按队伍规模补齐三路人数。
local SLOT_SEQUENCE = {
	{position = LaneAssignment.POSITION_MID, laneRole = "mid"},
	{position = LaneAssignment.POSITION_SAFE_CORE, laneRole = "safe"},
	{position = LaneAssignment.POSITION_OFF_CORE, laneRole = "off"},
	{position = LaneAssignment.POSITION_HARD_SUPPORT, laneRole = "safe"},
	{position = LaneAssignment.POSITION_SOFT_SUPPORT, laneRole = "off"},
	{position = LaneAssignment.POSITION_MID, laneRole = "mid"},
	{position = LaneAssignment.POSITION_SAFE_CORE, laneRole = "safe"},
	{position = LaneAssignment.POSITION_OFF_CORE, laneRole = "off"},
	{position = LaneAssignment.POSITION_MID, laneRole = "mid"},
	{position = LaneAssignment.POSITION_HARD_SUPPORT, laneRole = "safe"},
	{position = LaneAssignment.POSITION_SOFT_SUPPORT, laneRole = "off"},
	{position = LaneAssignment.POSITION_MID, laneRole = "mid"},
}

local PROFILE_BONUSES = {
	damage = {safe_core = 6, mid = 3},
	damage_spell = {safe_core = 3, mid = 6},
	frontline = {off_core = 6, soft_support = 2},
	support = {soft_support = 4, hard_support = 6},
}

local UNKNOWN_SCORES = {
	safe_core = 1,
	mid = 1,
	off_core = 1,
	soft_support = 1,
	hard_support = 1,
}

local OBSERVED_LANE_SCORE = 100000
local WRONG_OBSERVED_LANE_SCORE = -1000000000
local HUMAN_OBSERVE_START = -60
local HUMAN_LOCK_TIME = -3
local HUMAN_FOUNTAIN_DISTANCE = 2200
local HUMAN_LANE_MAX_DISTANCE = 900
local HUMAN_LANE_MARGIN = 300
local HUMAN_LANE_STABLE_TIME = 1.5

local runtimeState = {
	observations = {},
	locked = false,
	finalized = false,
	cachedFingerprint = nil,
	cachedAssignments = nil,
	cachedDetails = nil,
	lastPrintedFingerprint = nil,
	testMode = false,
}

local reportedAuditErrors = {}

local function CopyTable(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

local function IsPosition(position)
	for _, value in ipairs(POSITION_NAMES) do
		if value == position then return true end
	end
	return false
end

local function ApplyScoreOverrides(scores, values)
	if type(values) ~= "table" then return end
	for position, score in pairs(values) do
		if IsPosition(position) and type(score) == "number" then scores[position] = score end
	end
end

function LaneAssignment.GetHeroScores(heroName, profile)
	local generated = type(Generated.heroes) == "table" and Generated.heroes[heroName] or nil
	local scores = CopyTable(generated ~= nil and generated.scores or UNKNOWN_SCORES)
	local scoreSource = generated ~= nil and "generated" or "neutral"
	local profileBonus = PROFILE_BONUSES[profile]
	if profileBonus ~= nil then
		for position, bonus in pairs(profileBonus) do scores[position] = (scores[position] or 0) + bonus end
		scoreSource = scoreSource .. "+profile"
	end

	-- 完整人工审核按精确定位替换自动先验；没有对应定位时保持原有生成路径。
	local auditScores, auditInfo = Audit.GetScores(heroName, profile)
	if auditScores ~= nil then
		scores = auditScores
		scoreSource = "audit:" .. auditInfo.positioning
	elseif auditInfo ~= nil and auditInfo.error ~= nil then
		local errorKey = tostring(heroName) .. ":" .. tostring(auditInfo.positioning)
		if reportedAuditErrors[errorKey] == nil then
			reportedAuditErrors[errorKey] = true
			print("[BOT][LaneAssign][Audit] ignored hero=" .. tostring(heroName)
				.. " positioning=" .. tostring(auditInfo.positioning)
				.. " reason=" .. tostring(auditInfo.error))
		end
	end

	local heroOverride = Overrides[heroName]
	if type(heroOverride) == "table" then
		ApplyScoreOverrides(scores, heroOverride.scores)
		local overridden = type(heroOverride.scores) == "table"
		if type(heroOverride.profiles) == "table" then
			ApplyScoreOverrides(scores, heroOverride.profiles[profile])
			overridden = overridden or type(heroOverride.profiles[profile]) == "table"
		end
		if overridden then scoreSource = scoreSource .. "+override" end
	end
	return scores, generated, scoreSource
end

function LaneAssignment.GetLaneForRole(team, laneRole)
	if laneRole == "mid" then return LANE_MID end
	if team == TEAM_DIRE then
		return laneRole == "safe" and LANE_TOP or LANE_BOT
	end
	return laneRole == "safe" and LANE_BOT or LANE_TOP
end

function LaneAssignment.GetLaneRole(team, lane)
	if lane == LANE_MID then return "mid" end
	if team == TEAM_DIRE then
		if lane == LANE_TOP then return "safe" end
		if lane == LANE_BOT then return "off" end
	else
		if lane == LANE_BOT then return "safe" end
		if lane == LANE_TOP then return "off" end
	end
	return nil
end

local function CopySlot(slot)
	return {position = slot.position, laneRole = slot.laneRole}
end

function LaneAssignment.GetPositionSlots(count)
	local result = {}
	for index = 1, math.max(0, count or 0) do
		local source = SLOT_SEQUENCE[index]
		if source == nil then
			local extra = (index - #SLOT_SEQUENCE - 1) % 3
			if extra == 0 then source = {position = LaneAssignment.POSITION_MID, laneRole = "mid"}
			elseif extra == 1 then source = {position = LaneAssignment.POSITION_SAFE_CORE, laneRole = "safe"}
			else source = {position = LaneAssignment.POSITION_OFF_CORE, laneRole = "off"} end
		end
		result[index] = CopySlot(source)
	end
	return result
end

local function CountSlotLanes(slots)
	local counts = {safe = 0, mid = 0, off = 0}
	for _, slot in ipairs(slots) do counts[slot.laneRole] = counts[slot.laneRole] + 1 end
	return counts
end

function LaneAssignment.AdjustLaneCapacities(count, observedCounts)
	local capacities = CountSlotLanes(LaneAssignment.GetPositionSlots(count))
	observedCounts = observedCounts or {}
	for _, laneRole in ipairs({"safe", "mid", "off"}) do
		capacities[laneRole] = math.max(capacities[laneRole], observedCounts[laneRole] or 0)
	end

	local total = capacities.safe + capacities.mid + capacities.off
	local trimOrder = {"mid", "safe", "off"}
	while total > count do
		local selectedLane = nil
		local selectedSlack = -1
		for _, laneRole in ipairs(trimOrder) do
			local slack = capacities[laneRole] - (observedCounts[laneRole] or 0)
			if slack > selectedSlack then
				selectedLane = laneRole
				selectedSlack = slack
			end
		end
		if selectedLane == nil or selectedSlack <= 0 then break end
		capacities[selectedLane] = capacities[selectedLane] - 1
		total = total - 1
	end
	return capacities
end

local function NextPositionForLane(laneRole, ordinal)
	if laneRole == "mid" then return LaneAssignment.POSITION_MID end
	if laneRole == "safe" then
		return ordinal % 2 == 1 and LaneAssignment.POSITION_SAFE_CORE or LaneAssignment.POSITION_HARD_SUPPORT
	end
	return ordinal % 2 == 1 and LaneAssignment.POSITION_OFF_CORE or LaneAssignment.POSITION_SOFT_SUPPORT
end

function LaneAssignment.BuildSlotsForCapacities(capacities)
	local result = {}
	local used = {safe = 0, mid = 0, off = 0}
	for _, source in ipairs(SLOT_SEQUENCE) do
		if used[source.laneRole] < (capacities[source.laneRole] or 0) then
			table.insert(result, CopySlot(source))
			used[source.laneRole] = used[source.laneRole] + 1
		end
	end
	for _, laneRole in ipairs({"mid", "safe", "off"}) do
		while used[laneRole] < (capacities[laneRole] or 0) do
			used[laneRole] = used[laneRole] + 1
			table.insert(result, {
				position = NextPositionForLane(laneRole, used[laneRole]),
				laneRole = laneRole,
			})
		end
	end
	return result
end

local function BuildObservedCounts(players)
	local counts = {safe = 0, mid = 0, off = 0}
	for _, player in ipairs(players) do
		if counts[player.observedLaneRole] ~= nil then
			counts[player.observedLaneRole] = counts[player.observedLaneRole] + 1
		end
	end
	return counts
end

local function IsMaskBitSet(mask, index, powers)
	return math.floor(mask / powers[index]) % 2 == 1
end

local function SetMaskBit(mask, index, powers)
	return mask + powers[index]
end

local function MatchPlayers(players, slots, scoreMatrix)
	local count = #players
	local powers = {}
	for index = 1, count do powers[index] = 2 ^ (index - 1) end
	local memo = {}

	local function Solve(playerIndex, mask)
		if playerIndex > count then return 0 end
		local key = tostring(playerIndex) .. ":" .. tostring(mask)
		if memo[key] ~= nil then return memo[key].score end
		local bestScore = -math.huge
		local bestSlot = nil
		for slotIndex = 1, count do
			if not IsMaskBitSet(mask, slotIndex, powers) then
				local candidate = scoreMatrix[playerIndex][slotIndex]
					+ Solve(playerIndex + 1, SetMaskBit(mask, slotIndex, powers))
				if candidate > bestScore then
					bestScore = candidate
					bestSlot = slotIndex
				end
			end
		end
		memo[key] = {score = bestScore, slot = bestSlot}
		return bestScore
	end

	Solve(1, 0)
	local result = {}
	local mask = 0
	for playerIndex = 1, count do
		local entry = memo[tostring(playerIndex) .. ":" .. tostring(mask)]
		result[playerIndex] = entry.slot
		mask = SetMaskBit(mask, entry.slot, powers)
	end
	return result
end

function LaneAssignment.BuildAssignments(context)
	context = context or {}
	local players = context.players or {}
	if #players == 0 then return {}, {} end
	if context.ignoreHumans == true then
		local botPlayers = {}
		for _, player in ipairs(players) do
			if player.isBot == true then table.insert(botPlayers, player) end
		end

		local botAssignments, botDetails = LaneAssignment.BuildAssignments({
			team = context.team,
			players = botPlayers,
		})
		local fallback = LaneAssignment.BuildFallback(context.team, #players)
		local assignments = {}
		local details = {}
		local botIndex = 1
		for playerIndex, player in ipairs(players) do
			if player.isBot == true then
				assignments[playerIndex] = botAssignments[botIndex]
				details[playerIndex] = botDetails[botIndex]
				botIndex = botIndex + 1
			else
				-- 测试观战者保留队伍槽位，但不消耗 Bot 的分路容量。
				local lane = fallback[playerIndex] or LANE_MID
				assignments[playerIndex] = lane
				details[playerIndex] = {
					playerID = player.playerID,
					heroName = player.heroName,
					profile = player.profile,
					position = "ignored_human",
					laneRole = LaneAssignment.GetLaneRole(context.team, lane),
					lane = lane,
					score = 0,
					scoreSource = "lane_test",
					customHero = nil,
					observed = false,
					ignored = true,
				}
			end
		end
		return assignments, details
	end
	local observedCounts = BuildObservedCounts(players)
	local capacities = LaneAssignment.AdjustLaneCapacities(#players, observedCounts)
	local slots = LaneAssignment.BuildSlotsForCapacities(capacities)
	local scoreMatrix = {}
	local heroScores = {}
	local generatedData = {}
	local scoreSources = {}
	for playerIndex, player in ipairs(players) do
		heroScores[playerIndex], generatedData[playerIndex], scoreSources[playerIndex]
			= LaneAssignment.GetHeroScores(player.heroName, player.profile)
		scoreMatrix[playerIndex] = {}
		for slotIndex, slot in ipairs(slots) do
			local score = heroScores[playerIndex][slot.position] or 0
			if player.observedLaneRole ~= nil then
				if player.observedLaneRole == slot.laneRole then score = score + OBSERVED_LANE_SCORE
				else score = WRONG_OBSERVED_LANE_SCORE end
			end
			scoreMatrix[playerIndex][slotIndex] = score
		end
	end

	local matching = MatchPlayers(players, slots, scoreMatrix)
	local assignments = {}
	local details = {}
	for playerIndex, slotIndex in ipairs(matching) do
		local player = players[playerIndex]
		local slot = slots[slotIndex]
		local lane = LaneAssignment.GetLaneForRole(context.team, slot.laneRole)
		assignments[playerIndex] = lane
		details[playerIndex] = {
			playerID = player.playerID,
			heroName = player.heroName,
			profile = player.profile,
			position = slot.position,
			laneRole = slot.laneRole,
			lane = lane,
			score = heroScores[playerIndex][slot.position] or 0,
			scoreSource = scoreSources[playerIndex],
			customHero = generatedData[playerIndex] ~= nil and generatedData[playerIndex].customHero or nil,
			observed = player.observedLaneRole ~= nil,
		}
	end
	return assignments, details
end

function LaneAssignment.BuildFallback(team, count)
	local assignments = {}
	for index, slot in ipairs(LaneAssignment.GetPositionSlots(count)) do
		assignments[index] = LaneAssignment.GetLaneForRole(team, slot.laneRole)
	end
	return assignments
end

function LaneAssignment.UpdateHumanObservation(observations, playerID, candidateLane, now)
	local state = observations[playerID]
	if state == nil then
		state = {candidate = candidateLane, since = now, confirmed = nil}
		observations[playerID] = state
	elseif candidateLane ~= state.candidate then
		state.candidate = candidateLane
		state.since = now
	elseif candidateLane ~= nil and now - state.since >= HUMAN_LANE_STABLE_TIME then
		state.confirmed = candidateLane
	end
	return state.confirmed
end

local function SafeCall(defaultValue, callback)
	local ok, result, extra = pcall(callback)
	if ok then return result, extra end
	return defaultValue
end

local function DetectHumanLane(member)
	if member == nil then return nil end
	local fountainDistance = SafeCall(0, function() return member:DistanceFromFountain() end)
	if fountainDistance <= HUMAN_FOUNTAIN_DISTANCE then return nil end
	local location = SafeCall(nil, function() return member:GetLocation() end)
	if location == nil then return nil end

	local distances = {}
	for _, lane in ipairs({LANE_TOP, LANE_MID, LANE_BOT}) do
		local _, distance = SafeCall(nil, function() return GetAmountAlongLane(lane, location) end)
		if type(distance) ~= "number" then return nil end
		table.insert(distances, {lane = lane, distance = distance})
	end
	table.sort(distances, function(a, b)
		if a.distance == b.distance then return a.lane < b.lane end
		return a.distance < b.distance
	end)
	if distances[1].distance > HUMAN_LANE_MAX_DISTANCE then return nil end
	if distances[2].distance - distances[1].distance < HUMAN_LANE_MARGIN then return nil end
	return distances[1].lane
end

local function GetBotProfile(member)
	if member == nil then return nil end
	return SafeCall(nil, function() return BotProfile.GetProfile(member) end)
end

local function BuildFingerprint(team, players, locked, testMode)
	local values = {tostring(team), locked and "locked" or "open", testMode and "test" or "normal"}
	for index, player in ipairs(players) do
		table.insert(values, table.concat({
			tostring(index),
			tostring(player.playerID),
			tostring(player.heroName),
			tostring(player.isBot),
			tostring(player.profile),
			tostring(player.observedLaneRole),
		}, ":"))
	end
	return table.concat(values, "|")
end

local function LaneName(lane)
	if lane == LANE_TOP then return "TOP" end
	if lane == LANE_MID then return "MID" end
	if lane == LANE_BOT then return "BOT" end
	return tostring(lane)
end

local function PrintAssignments(team, details, locked, testMode)
	local values = {}
	for index, detail in ipairs(details) do
		table.insert(values, string.format(
			"slot=%d pid=%s hero=%s custom=%s profile=%s pos=%s lane=%s score=%s score_source=%s source=%s",
			index,
			tostring(detail.playerID),
			tostring(detail.heroName),
			tostring(detail.customHero or "unknown"),
			tostring(detail.profile or "base"),
			detail.position,
			LaneName(detail.lane),
			tostring(detail.score),
			tostring(detail.scoreSource),
			detail.ignored and "human_ignored"
				or (detail.observed and "human_observed" or "predicted")
		))
	end
	print("[BOT][LaneAssign] team=" .. tostring(team) .. " locked=" .. tostring(locked)
		.. " test=" .. tostring(testMode)
		.. " " .. table.concat(values, "; "))
end

function LaneAssignment.IsTestMode(team)
	local testMode = type(Config.testMode) == "table" and Config.testMode or nil
	if testMode == nil then return false end
	if team == TEAM_RADIANT then return testMode.radiant == true end
	if team == TEAM_DIRE then return testMode.dire == true end
	return false
end

function LaneAssignment.ResetRuntimeState()
	runtimeState.observations = {}
	runtimeState.locked = false
	runtimeState.finalized = false
	runtimeState.cachedFingerprint = nil
	runtimeState.cachedAssignments = nil
	runtimeState.cachedDetails = nil
	runtimeState.lastPrintedFingerprint = nil
	runtimeState.testMode = false
end

function LaneAssignment.UpdateLaneAssignments()
	local team = GetTeam()
	local playerIDs = GetTeamPlayers(team) or {}
	local now = SafeCall(-90, function() return DotaTime() end)
	local testMode = LaneAssignment.IsTestMode(team)
	if runtimeState.testMode ~= testMode then
		runtimeState.testMode = testMode
		runtimeState.finalized = false
		runtimeState.cachedFingerprint = nil
	end
	if now >= HUMAN_LOCK_TIME then runtimeState.locked = true end
	if runtimeState.locked and runtimeState.finalized and runtimeState.cachedAssignments ~= nil then
		return runtimeState.cachedAssignments
	end
	local players = {}
	for index, playerID in ipairs(playerIDs) do
		local heroName = SafeCall("", function() return GetSelectedHeroName(playerID) end) or ""
		local isBot = SafeCall(false, function() return IsPlayerBot(playerID) end) == true
		local member = SafeCall(nil, function() return GetTeamMember(index) end)
		local observedLane = runtimeState.observations[playerID] ~= nil
			and runtimeState.observations[playerID].confirmed or nil
		if not testMode and not runtimeState.locked and not isBot and now >= HUMAN_OBSERVE_START then
			observedLane = LaneAssignment.UpdateHumanObservation(
				runtimeState.observations,
				playerID,
				DetectHumanLane(member),
				now
			)
		end
		table.insert(players, {
			playerID = playerID,
			heroName = heroName,
			isBot = isBot,
			profile = isBot and GetBotProfile(member) or nil,
			observedLaneRole = LaneAssignment.GetLaneRole(team, observedLane),
		})
	end

	local fingerprint = BuildFingerprint(team, players, runtimeState.locked, testMode)
	if runtimeState.cachedFingerprint ~= fingerprint then
		local assignments, details = LaneAssignment.BuildAssignments({
			team = team,
			players = players,
			ignoreHumans = testMode,
		})
		runtimeState.cachedFingerprint = fingerprint
		runtimeState.cachedAssignments = assignments
		runtimeState.cachedDetails = details
		if runtimeState.lastPrintedFingerprint ~= fingerprint then
			PrintAssignments(team, details, runtimeState.locked, testMode)
			runtimeState.lastPrintedFingerprint = fingerprint
		end
	end
	if runtimeState.locked then runtimeState.finalized = true end
	return runtimeState.cachedAssignments or LaneAssignment.BuildFallback(team, #playerIDs)
end

function LaneAssignment.GetAssignedPosition(bot)
	if bot == nil then return nil end
	local playerID = SafeCall(-1, function() return bot:GetPlayerID() end)
	if playerID == nil or playerID < 0 then return nil end

	if runtimeState.cachedDetails == nil then
		SafeCall(nil, function() return LaneAssignment.UpdateLaneAssignments() end)
	end
	for _, detail in ipairs(runtimeState.cachedDetails or {}) do
		if detail.playerID == playerID and not detail.ignored and IsPosition(detail.position) then
			return detail.position
		end
	end
	return nil
end

LaneAssignment.GeneratedMetadata = Generated.metadata

return LaneAssignment
