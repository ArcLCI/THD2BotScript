local BOT_ROOT = "D:/LAF Workspace/THD/THD2BotScript"

LANE_TOP = 1
LANE_MID = 2
LANE_BOT = 3
TEAM_RADIANT = 2
TEAM_DIRE = 3

function GetScriptDirectory() return BOT_ROOT end

local Generated = dofile(BOT_ROOT .. "/THDFuncLib/lane_assignment_generated.lua")
local Overrides = dofile(BOT_ROOT .. "/THDFuncLib/lane_assignment_overrides.lua")
local BotProfile = dofile(BOT_ROOT .. "/THDFuncLib/bot_profile.lua")
local AuditConfig = dofile(BOT_ROOT .. "/THDFuncLib/lane_assignment_audit_config.lua")

package.preload[BOT_ROOT .. "/THDFuncLib/lane_assignment_audit_config"] = function() return AuditConfig end
local Audit = dofile(BOT_ROOT .. "/THDFuncLib/lane_assignment_audit.lua")
package.preload[BOT_ROOT .. "/THDFuncLib/lane_assignment_generated"] = function() return Generated end
package.preload[BOT_ROOT .. "/THDFuncLib/lane_assignment_audit"] = function() return Audit end
package.preload[BOT_ROOT .. "/THDFuncLib/lane_assignment_overrides"] = function() return Overrides end
package.preload[BOT_ROOT .. "/THDFuncLib/bot_profile"] = function() return BotProfile end

local LaneAssignment = dofile(BOT_ROOT .. "/THDFuncLib/lane_assignment.lua")

local function Assert(condition, message)
	if not condition then error(message, 2) end
end

local function AssertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "value mismatch") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

local function CountLanes(assignments)
	local counts = {[LANE_TOP] = 0, [LANE_MID] = 0, [LANE_BOT] = 0}
	for _, lane in ipairs(assignments) do counts[lane] = (counts[lane] or 0) + 1 end
	return counts
end

local expectedRadiantCounts = {
	[1] = {0, 1, 0},
	[2] = {0, 1, 1},
	[3] = {1, 1, 1},
	[4] = {1, 1, 2},
	[5] = {2, 1, 2},
	[6] = {2, 2, 2},
	[7] = {2, 2, 3},
	[8] = {3, 2, 3},
	[9] = {3, 3, 3},
	[10] = {3, 3, 4},
	[11] = {4, 3, 4},
	[12] = {4, 4, 4},
}

for count = 1, 12 do
	local assignments = LaneAssignment.BuildFallback(TEAM_RADIANT, count)
	local laneCounts = CountLanes(assignments)
	AssertEqual(#assignments, count, "fallback slot count " .. count)
	AssertEqual(laneCounts[LANE_TOP], expectedRadiantCounts[count][1], "Radiant TOP count " .. count)
	AssertEqual(laneCounts[LANE_MID], expectedRadiantCounts[count][2], "Radiant MID count " .. count)
	AssertEqual(laneCounts[LANE_BOT], expectedRadiantCounts[count][3], "Radiant BOT count " .. count)
	local direCounts = CountLanes(LaneAssignment.BuildFallback(TEAM_DIRE, count))
	AssertEqual(direCounts[LANE_TOP], laneCounts[LANE_BOT], "Dire safe/off swap TOP " .. count)
	AssertEqual(direCounts[LANE_BOT], laneCounts[LANE_TOP], "Dire safe/off swap BOT " .. count)
end

local reimuBase = LaneAssignment.GetHeroScores("npc_dota_hero_lina", nil)
AssertEqual(reimuBase.safe_core, 4, "generated Reimu safe score")
AssertEqual(reimuBase.soft_support, 14, "generated Reimu soft support score")
local reimuSupport = LaneAssignment.GetHeroScores("npc_dota_hero_lina", "support")
AssertEqual(reimuSupport.soft_support, 18, "support profile soft support increment")
AssertEqual(reimuSupport.hard_support, 19, "support profile hard support increment")
local unknownDamage = LaneAssignment.GetHeroScores("unknown", "damage")
AssertEqual(unknownDamage.safe_core, 7, "damage profile safe core increment")
AssertEqual(unknownDamage.mid, 4, "damage profile mid increment")
local unknownSpell = LaneAssignment.GetHeroScores("unknown", "damage_spell")
AssertEqual(unknownSpell.safe_core, 4, "spell profile safe core increment")
AssertEqual(unknownSpell.mid, 7, "spell profile mid increment")
local unknownFrontline = LaneAssignment.GetHeroScores("unknown", "frontline")
AssertEqual(unknownFrontline.off_core, 7, "frontline profile off core increment")
AssertEqual(unknownFrontline.soft_support, 3, "frontline profile soft support increment")

local allThreeTraits = {}
for _, dimension in ipairs(Audit.DIMENSIONS) do allThreeTraits[dimension] = 3 end
local allThreeScores = Audit.CalculateScores(allThreeTraits)
for position, score in pairs(allThreeScores) do
	AssertEqual(score, 30, "full audit score scale " .. position)
end

local damageTraits = {
	gold_scaling = 3, level_scaling = 1, lane_independence = 2, last_hit = 3,
	trading = 1, wave_control = 2, initiation = 0, follow_up = 2,
	protection = 0, roaming = 0, low_economy = 0, late_carry = 3,
}
local supportTraits = {
	gold_scaling = 0, level_scaling = 2, lane_independence = 1, last_hit = 0,
	trading = 3, wave_control = 2, initiation = 2, follow_up = 3,
	protection = 3, roaming = 2, low_economy = 3, late_carry = 0,
}
AuditConfig.heroes["npc_dota_hero_lina"] = {
	damage = {label = "damage test", traits = damageTraits},
	support = {label = "support test", traits = supportTraits},
	frontline = {label = "invalid test", traits = {gold_scaling = 4}},
}
local auditConfigValid, auditConfigErrors = Audit.ValidateConfig()
Assert(not auditConfigValid, "invalid positioning audit must fail config validation")
Assert(#auditConfigErrors == 1, "invalid positioning audit reports one config error")
local auditedDamage, _, damageSource = LaneAssignment.GetHeroScores("npc_dota_hero_lina", "damage")
AssertEqual(auditedDamage.safe_core, 25, "damage positioning audit safe score")
AssertEqual(auditedDamage.hard_support, 8, "damage positioning audit hard score")
AssertEqual(damageSource, "audit:damage", "damage positioning score source")
local auditedSupport, _, supportSource = LaneAssignment.GetHeroScores("npc_dota_hero_lina", "support")
AssertEqual(auditedSupport.safe_core, 8, "support positioning audit safe score")
AssertEqual(auditedSupport.hard_support, 26, "support positioning audit hard score")
AssertEqual(supportSource, "audit:support", "support positioning score source")
local unauditedBase, _, baseSource = LaneAssignment.GetHeroScores("npc_dota_hero_lina", nil)
AssertEqual(unauditedBase.soft_support, 14, "missing base audit keeps generated score")
AssertEqual(baseSource, "generated", "missing base audit source")
local invalidFrontline, _, invalidSource = LaneAssignment.GetHeroScores("npc_dota_hero_lina", "frontline")
AssertEqual(invalidFrontline.off_core, 10, "invalid audit falls back to profile score")
AssertEqual(invalidSource, "generated+profile", "invalid audit fallback source")

Overrides.audit_mid = {scores = {safe_core = 0, mid = 100, off_core = 0, soft_support = 0, hard_support = 0}}
Overrides.audit_off = {scores = {safe_core = 0, mid = 0, off_core = 100, soft_support = 0, hard_support = 0}}
Overrides.audit_soft = {scores = {safe_core = 0, mid = 0, off_core = 0, soft_support = 100, hard_support = 0}}
local _, auditedDetails = LaneAssignment.BuildAssignments({
	team = TEAM_RADIANT,
	players = {
		{playerID = 0, heroName = "npc_dota_hero_lina", profile = "damage", isBot = true},
		{playerID = 1, heroName = "npc_dota_hero_lina", profile = "support", isBot = true},
		{playerID = 2, heroName = "audit_mid", isBot = true},
		{playerID = 3, heroName = "audit_off", isBot = true},
		{playerID = 4, heroName = "audit_soft", isBot = true},
	},
})
AssertEqual(auditedDetails[1].position, "safe_core", "damage positioning enters team matching")
AssertEqual(auditedDetails[1].scoreSource, "audit:damage", "damage matching score source")
AssertEqual(auditedDetails[2].position, "hard_support", "support positioning enters team matching")
AssertEqual(auditedDetails[2].scoreSource, "audit:support", "support matching score source")
Overrides.audit_mid = nil
Overrides.audit_off = nil
Overrides.audit_soft = nil

Overrides["npc_dota_hero_lina"] = {
	scores = {mid = 50},
	profiles = {support = {mid = 80}},
}
AssertEqual(LaneAssignment.GetHeroScores("npc_dota_hero_lina", nil).mid, 50, "hero override replaces generated score")
AssertEqual(LaneAssignment.GetHeroScores("npc_dota_hero_lina", "support").mid, 80, "profile override has final priority")
Overrides["npc_dota_hero_lina"] = nil
AuditConfig.heroes["npc_dota_hero_lina"] = nil
Assert(Audit.ValidateConfig(), "clean audit config validates")

local positionHeroes = {
	{"test_safe", "safe_core"},
	{"test_mid", "mid"},
	{"test_off", "off_core"},
	{"test_soft", "soft_support"},
	{"test_hard", "hard_support"},
}
for _, entry in ipairs(positionHeroes) do
	Overrides[entry[1]] = {scores = {
		safe_core = entry[2] == "safe_core" and 100 or 0,
		mid = entry[2] == "mid" and 100 or 0,
		off_core = entry[2] == "off_core" and 100 or 0,
		soft_support = entry[2] == "soft_support" and 100 or 0,
		hard_support = entry[2] == "hard_support" and 100 or 0,
	}}
end

local players = {}
for index, entry in ipairs(positionHeroes) do
	players[index] = {playerID = index - 1, heroName = entry[1], isBot = true}
end
local assignments, details = LaneAssignment.BuildAssignments({team = TEAM_RADIANT, players = players})
AssertEqual(#assignments, 5, "five-position assignment count")
for index, entry in ipairs(positionHeroes) do
	AssertEqual(details[index].position, entry[2], "global matching position " .. entry[1])
end

local firstAssignments, firstDetails = LaneAssignment.BuildAssignments({
	team = TEAM_RADIANT,
	players = {
		{playerID = 0, heroName = "", isBot = true},
		{playerID = 1, heroName = "unknown", isBot = true},
		{playerID = 2, heroName = "unknown", isBot = true},
	},
})
local secondAssignments, secondDetails = LaneAssignment.BuildAssignments({
	team = TEAM_RADIANT,
	players = {
		{playerID = 0, heroName = "", isBot = true},
		{playerID = 1, heroName = "unknown", isBot = true},
		{playerID = 2, heroName = "unknown", isBot = true},
	},
})
for index = 1, 3 do
	AssertEqual(firstAssignments[index], secondAssignments[index], "unknown hero deterministic lane " .. index)
	AssertEqual(firstDetails[index].position, secondDetails[index].position, "unknown hero deterministic position " .. index)
end

local twelvePlayers = {}
for index = 1, 12 do
	twelvePlayers[index] = {playerID = index - 1, heroName = "unknown", isBot = true}
end
local twelveAssignments = LaneAssignment.BuildAssignments({team = TEAM_RADIANT, players = twelvePlayers})
local twelveCounts = CountLanes(twelveAssignments)
AssertEqual(#twelveAssignments, 12, "maximum supported team returns every assignment")
AssertEqual(twelveCounts[LANE_TOP], 4, "12-player TOP capacity")
AssertEqual(twelveCounts[LANE_MID], 4, "12-player MID capacity")
AssertEqual(twelveCounts[LANE_BOT], 4, "12-player BOT capacity")

local crowdedPlayers = {}
for index = 1, 5 do
	crowdedPlayers[index] = {
		playerID = index - 1,
		heroName = "unknown",
		isBot = index > 3,
		observedLaneRole = index <= 3 and "mid" or nil,
	}
end
local crowdedAssignments = LaneAssignment.BuildAssignments({team = TEAM_RADIANT, players = crowdedPlayers})
local crowdedCounts = CountLanes(crowdedAssignments)
AssertEqual(crowdedCounts[LANE_MID], 3, "three observed humans reserve three mid slots")
AssertEqual(crowdedCounts[LANE_TOP] + crowdedCounts[LANE_BOT], 2, "remaining Bots stay outside crowded mid")

local allMidPlayers = {}
for index = 1, 5 do
	allMidPlayers[index] = {
		playerID = index - 1,
		heroName = "unknown",
		isBot = false,
		observedLaneRole = "mid",
	}
end
local allMidAssignments = LaneAssignment.BuildAssignments({team = TEAM_RADIANT, players = allMidPlayers})
AssertEqual(CountLanes(allMidAssignments)[LANE_MID], 5, "human overflow expands observed lane capacity")

local observations = {}
AssertEqual(LaneAssignment.UpdateHumanObservation(observations, 7, LANE_TOP, -10), nil, "first observation is not confirmed")
AssertEqual(LaneAssignment.UpdateHumanObservation(observations, 7, LANE_TOP, -8.6), nil, "observation below stable time is not confirmed")
AssertEqual(LaneAssignment.UpdateHumanObservation(observations, 7, LANE_TOP, -8.4), LANE_TOP, "stable observation confirms lane")
AssertEqual(LaneAssignment.UpdateHumanObservation(observations, 7, LANE_BOT, -8.0), LANE_TOP, "new lane waits before replacing confirmation")
AssertEqual(LaneAssignment.UpdateHumanObservation(observations, 7, LANE_BOT, -6.4), LANE_BOT, "stable lane change replaces confirmation")

for _, entry in ipairs(positionHeroes) do Overrides[entry[1]] = nil end

local runtimeNow = -10
local runtimeTeam = TEAM_RADIANT
local runtimePlayerIDs = {10, 11}
local runtimeHeroes = {[10] = "npc_dota_hero_lina", [11] = "npc_dota_hero_slark"}
local humanLocation = "top"
local human = {}
function human:DistanceFromFountain() return 3000 end
function human:GetLocation() return humanLocation end
local bot = {}
function bot:GetAbilityByName() return nil end
local runtimeMembers = {human, bot}

function GetTeam() return runtimeTeam end
function GetTeamPlayers() return runtimePlayerIDs end
function DotaTime() return runtimeNow end
function GetSelectedHeroName(playerID) return runtimeHeroes[playerID] end
function IsPlayerBot(playerID) return playerID == 11 end
function GetTeamMember(index) return runtimeMembers[index] end
function GetAmountAlongLane(lane, location)
	if location == "top" then return 0.3, lane == LANE_TOP and 100 or (lane == LANE_MID and 700 or 1400) end
	return 0.3, lane == LANE_BOT and 100 or (lane == LANE_MID and 700 or 1400)
end

LaneAssignment.ResetRuntimeState()
LaneAssignment.UpdateLaneAssignments()
runtimeNow = -8.4
local observedAssignments = LaneAssignment.UpdateLaneAssignments()
AssertEqual(observedAssignments[1], LANE_TOP, "runtime stable human route is reserved")
AssertEqual(observedAssignments[2], LANE_BOT, "runtime Bot avoids observed human route")
runtimeNow = -2
humanLocation = "bot"
local lockedAssignments = LaneAssignment.UpdateLaneAssignments()
AssertEqual(lockedAssignments[1], LANE_TOP, "runtime assignment locks before zero")
AssertEqual(lockedAssignments[2], LANE_BOT, "locked Bot assignment does not oscillate")
runtimeNow = 1
runtimeHeroes[11] = "npc_dota_hero_lina"
local postZeroAssignments = LaneAssignment.UpdateLaneAssignments()
AssertEqual(postZeroAssignments[1], LANE_TOP, "post-zero lineup signals do not replace locked human lane")
AssertEqual(postZeroAssignments[2], LANE_BOT, "post-zero lineup signals do not replace locked Bot lane")

AssertEqual(Generated.metadata.heroCount, 69, "generated current roster count")
print("[PASS] THD lane assignment framework mocks")
