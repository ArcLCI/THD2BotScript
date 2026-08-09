local BOT_ROOT = "D:/LAF Workspace/THD/THD2BotScript"

TEAM_RADIANT = 2
TEAM_DIRE = 3
LANE_TOP = 1
LANE_MID = 2
LANE_BOT = 3
TOWER_TOP_1 = 1
TOWER_TOP_2 = 2
TOWER_TOP_3 = 3
TOWER_MID_1 = 4
TOWER_MID_2 = 5
TOWER_MID_3 = 6
TOWER_BOT_1 = 7
TOWER_BOT_2 = 8
TOWER_BOT_3 = 9
UNIT_LIST_ENEMY_HEROES = 1

BOT_MODE_NONE = 0
BOT_MODE_ROAM = 1
BOT_MODE_RETREAT = 2
BOT_MODE_DEFEND_TOWER_TOP = 3
BOT_MODE_DEFEND_TOWER_MID = 4
BOT_MODE_DEFEND_TOWER_BOT = 5
BOT_MODE_PUSH_TOWER_TOP = 6
BOT_MODE_PUSH_TOWER_MID = 7
BOT_MODE_PUSH_TOWER_BOT = 8
BOT_MODE_ROSHAN = 9
BOT_MODE_DESIRE_NONE = 0
BOT_MODE_DESIRE_HIGH = 0.7
BOT_MODE_DESIRE_VERYHIGH = 0.9
BOT_MODE_DESIRE_ABSOLUTE = 1.0

local now = 100
local defendDesire = BOT_MODE_DESIRE_NONE
local members = {}
local enemies = {}
local towers = {}
local laneFronts = {}

local function Assert(condition, message)
	if not condition then error(message, 2) end
end

local function AssertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "value mismatch") .. ": expected=" .. tostring(expected)
			.. ", actual=" .. tostring(actual), 2)
	end
end

local function Location(x, y, lane, laneDistance)
	return {x = x, y = y or 0, lane = lane, laneDistance = laneDistance or 0}
end

local function Distance(first, second)
	local firstLocation = first.location or first
	local secondLocation = second.location or second
	local dx = (firstLocation.x or 0) - (secondLocation.x or 0)
	local dy = (firstLocation.y or 0) - (secondLocation.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function NewUnit(playerID, team, lane, position, x)
	local unit = {
		playerID = playerID,
		team = team,
		lane = lane,
		position = position,
		location = Location(x or 0, 0, lane, 0),
		alive = true,
		visible = true,
		hero = true,
		bot = true,
		illusion = false,
		level = 10,
		health = 1000,
		maxHealth = 1000,
		mana = 1000,
		maxMana = 1000,
		power = 100,
		speed = 400,
		activeMode = BOT_MODE_NONE,
		target = nil,
		attackTarget = nil,
		ping = nil,
		actions = {},
		chats = {},
	}
	function unit:IsNull() return false end
	function unit:IsAlive() return self.alive end
	function unit:CanBeSeen() return self.visible end
	function unit:IsHero() return self.hero end
	function unit:IsBot() return self.bot end
	function unit:IsKnownIllusion() return self.illusion end
	function unit:HasModifier(name) return name == "modifier_illusion" and self.illusion end
	function unit:GetPlayerID() return self.playerID end
	function unit:GetTeam() return self.team end
	function unit:GetAssignedLane() return self.lane end
	function unit:GetLocation() return self.location end
	function unit:GetLevel() return self.level end
	function unit:GetHealth() return self.health end
	function unit:GetMaxHealth() return self.maxHealth end
	function unit:GetMana() return self.mana end
	function unit:GetMaxMana() return self.maxMana end
	function unit:GetOffensivePower() return self.power end
	function unit:GetCurrentMovementSpeed() return self.speed end
	function unit:GetActiveMode() return self.activeMode end
	function unit:GetTarget() return self.target end
	function unit:SetTarget(target) self.target = target end
	function unit:GetAttackTarget() return self.attackTarget end
	function unit:GetMostRecentPing() return self.ping end
	function unit:WasRecentlyDamagedByAnyHero()
		if not self.bot then self.invalidBotDamageQueryCount = (self.invalidBotDamageQueryCount or 0) + 1 end
		return self.recentDamage == true
	end
	function unit:WasRecentlyDamagedByHero(source) return self.damagedBy == source end
	function unit:IsCastingAbility() return self.abilityPhase == true end
	function unit:IsUsingAbility() return self.usingAbility == true end
	function unit:IsChanneling() return self.channeling == true end
	function unit:GetNearbyHeroes(radius, enemy)
		local pool = enemy and enemies or members
		local result = {}
		for _, other in ipairs(pool) do
			if other ~= self and other.alive and other.visible and Distance(self, other) <= radius then
				table.insert(result, other)
			end
		end
		return result
	end
	function unit:ActionImmediate_Ping(xValue, yValue, normalPing)
		self.ping = {
			time = now,
			location = Location(xValue, yValue),
			normal_ping = normalPing,
		}
		table.insert(self.actions, {kind = "ping"})
	end
	function unit:ActionImmediate_Chat(message, allChat)
		table.insert(self.chats, {message = message, allChat = allChat})
	end
	return unit
end

local function NewTower(team, lane, tier, x)
	local tower = NewUnit(-1, team, lane, nil, x)
	tower.hero = false
	tower.bot = false
	tower.tier = tier
	return tower
end

function GetScriptDirectory() return BOT_ROOT end
function GetTeam() return TEAM_RADIANT end
function GetOpposingTeam() return TEAM_DIRE end
function DotaTime() return now end
function GameTime() return now end
function GetTeamMember(index) return members[index] end
function GetUnitList(listType)
	if listType == UNIT_LIST_ENEMY_HEROES then return enemies end
	return {}
end
function GetUnitToLocationDistance(unit, location) return Distance(unit, location) end
function GetUnitToUnitDistance(first, second) return Distance(first, second) end
function GetLaneFrontLocation(_, lane) return laneFronts[lane] end
function GetAmountAlongLane(lane, location)
	if location.lane == lane then return 0.5, location.laneDistance or 0 end
	return 0.5, 2000
end
function GetTower(team, towerID)
	return towers[tostring(team) .. ":" .. tostring(towerID)]
end

local J = {
	Retreat = {
		HIGH = 2,
		ShouldYield = function(unit) return unit.retreat == true end,
	},
	Utils = {
		IsTeamPushingSecondTierOrHighGround = function(unit) return unit.pushing == true end,
	},
	IsDoingRoshan = function(unit) return unit.roshan == true end,
	SetTargetIfChanged = function(unit, target)
		if unit:GetTarget() ~= target then unit:SetTarget(target) end
	end,
	CanNotUseAction = function(unit)
		return unit.abilityPhase == true or unit.usingAbility == true or unit.channeling == true
	end,
	ActionMoveToLocation = function(unit, _, location)
		table.insert(unit.actions, {kind = "move", location = location})
	end,
	ActionAttackUnit = function(unit, _, target)
		table.insert(unit.actions, {kind = "attack", target = target})
	end,
}

local Defend = {
	GetDefendDesire = function() return defendDesire end,
}

local LaneAssignment = {
	GetAssignedPosition = function(unit) return unit.position end,
}

local thdModule = BOT_ROOT .. "/THDFuncLib/thd_func"
local defendModule = BOT_ROOT .. "/THDFuncLib/aba_defend"
local laneModule = BOT_ROOT .. "/THDFuncLib/lane_assignment"
local configModule = BOT_ROOT .. "/THDFuncLib/roam_config"
local coordinatorModule = BOT_ROOT .. "/THDFuncLib/roam_coordinator"
local gankModule = BOT_ROOT .. "/THDFuncLib/roam_gank"

package.preload[thdModule] = function() return J end
package.preload[defendModule] = function() return Defend end
package.preload[laneModule] = function() return LaneAssignment end
local Config = dofile(BOT_ROOT .. "/THDFuncLib/roam_config.lua")
package.preload[configModule] = function() return Config end
local Coordinator = dofile(BOT_ROOT .. "/THDFuncLib/roam_coordinator.lua")
package.preload[coordinatorModule] = function() return Coordinator end
local Gank = dofile(BOT_ROOT .. "/THDFuncLib/roam_gank.lua")
package.preload[gankModule] = function() return Gank end

local host = NewUnit(10, TEAM_RADIANT, LANE_TOP, "safe_core", 2700)
local softSupport = NewUnit(11, TEAM_RADIANT, LANE_BOT, "soft_support", 0)
local hardSupport = NewUnit(12, TEAM_RADIANT, LANE_BOT, "hard_support", 400)
local mid = NewUnit(13, TEAM_RADIANT, LANE_MID, "mid", 800)
local offCore = NewUnit(14, TEAM_RADIANT, LANE_TOP, "off_core", 2600)
members = {host, softSupport, hardSupport, mid, offCore}

local target = NewUnit(20, TEAM_DIRE, LANE_TOP, nil, 3000)
target.bot = false
target.health = 300
target.location.laneDistance = 0
enemies = {target}

laneFronts[LANE_TOP] = Location(3000, 0, LANE_TOP)
laneFronts[LANE_MID] = Location(6000, 0, LANE_MID)
laneFronts[LANE_BOT] = Location(0, 0, LANE_BOT)

local towerIDsByLane = {
	[LANE_TOP] = {TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3},
	[LANE_MID] = {TOWER_MID_1, TOWER_MID_2, TOWER_MID_3},
	[LANE_BOT] = {TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3},
}
for lane, towerIDs in pairs(towerIDsByLane) do
	for tier, towerID in ipairs(towerIDs) do
		local allyX = lane == LANE_MID and 0 or -4000 - tier * 500
		local enemyX = lane == LANE_MID and 10000 or 6000 + tier * 1000
		towers[tostring(TEAM_RADIANT) .. ":" .. tostring(towerID)] = NewTower(TEAM_RADIANT, lane, tier, allyX)
		towers[tostring(TEAM_DIRE) .. ":" .. tostring(towerID)] = NewTower(TEAM_DIRE, lane, tier, enemyX)
	end
end

local function CountActions(unit, kind)
	local count = 0
	for _, action in ipairs(unit.actions) do
		if action.kind == kind then count = count + 1 end
	end
	return count
end

local function ResetWorld(startTime)
	now = startTime or 100
	defendDesire = BOT_MODE_DESIRE_NONE
	enemies = {target}
	target.alive = true
	target.visible = true
	target.illusion = false
	target.health = 300
	target.power = 100
	target.location = Location(3000, 0, LANE_TOP, 0)
	for _, unit in ipairs(members) do
		unit.alive = true
		unit.visible = true
		unit.level = 10
		unit.health = 1000
		unit.mana = 1000
		unit.power = 100
		unit.activeMode = BOT_MODE_NONE
		unit.target = nil
		unit.attackTarget = nil
		unit.ping = nil
		unit.actions = {}
		unit.chats = {}
		unit.recentDamage = false
		unit.damagedBy = nil
		unit.retreat = false
		unit.roshan = false
		unit.pushing = false
		unit.abilityPhase = false
		unit.usingAbility = false
		unit.channeling = false
	end
	host.location = Location(2700, 0, LANE_TOP)
	softSupport.location = Location(0, 0, LANE_BOT)
	hardSupport.location = Location(400, 0, LANE_BOT)
	mid.location = Location(800, 0, LANE_MID)
	offCore.location = Location(2600, 0, LANE_TOP)
	local enemyTopTower = towers[tostring(TEAM_DIRE) .. ":" .. tostring(TOWER_TOP_1)]
	enemyTopTower.location = Location(7000, 0, LANE_TOP)
	Config.ENABLED = true
	Config.ANNOUNCE_CHAT = true
	Coordinator.ResetForTests()
end

local function StartLeader(startTime)
	ResetWorld(startTime)
	AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_HIGH,
		"elected support receives approach desire")
	Assert(Coordinator.OnStart(softSupport), "elected support starts mission")
	softSupport.activeMode = BOT_MODE_ROAM
	return Coordinator.GetMission(softSupport)
end

-- 总开关只有严格布尔 true 才启用。
AssertEqual(Config.IsEnabled(), false, "roam gank is disabled by default")
Config.ENABLED = "true"
AssertEqual(Config.IsEnabled(), false, "string switch value fails closed")
Config.ENABLED = nil
AssertEqual(Config.IsEnabled(), false, "missing switch value fails closed")
Config.ENABLED = true
AssertEqual(Config.IsEnabled(), true, "boolean true enables roam gank")
local savedApproachTimeout = Config.APPROACH_TIMEOUT
Config.APPROACH_TIMEOUT = nil
AssertEqual(Config.IsEnabled(), false, "missing required config field fails closed")
Config.APPROACH_TIMEOUT = "12"
AssertEqual(Config.IsEnabled(), false, "wrong required config field type fails closed")
Config.APPROACH_TIMEOUT = savedApproachTimeout
AssertEqual(Config.IsEnabled(), true, "restored complete config enables roam gank")

-- 2/4/5 号位资格与对线期保护。
ResetWorld(100)
mid.level = 5
AssertEqual(Coordinator.CanInitiate(mid), false, "mid requires level six during protected laning")
mid.level = 6
AssertEqual(Coordinator.CanInitiate(mid), true, "healthy level-six mid with pushed lane may roam")
mid.recentDamage = true
AssertEqual(Coordinator.CanInitiate(mid), false, "recent hero damage blocks mid roam")
mid.recentDamage = false
mid.health = 699
AssertEqual(Coordinator.CanInitiate(mid), false, "mid health threshold is enforced")
mid.health = 1000
mid.mana = 499
AssertEqual(Coordinator.CanInitiate(mid), false, "mid mana threshold is enforced")
mid.mana = 1000
AssertEqual(Coordinator.CanInitiate(softSupport), true, "soft support may initiate")
AssertEqual(Coordinator.CanInitiate(hardSupport), true, "hard support may initiate")
local alliedBotLaneTower = towers[tostring(TEAM_RADIANT) .. ":" .. tostring(TOWER_BOT_1)]
alliedBotLaneTower.attackTarget = target
AssertEqual(Coordinator.CanInitiate(softSupport), false, "visible enemy hero on allied tower blocks support roam")
AssertEqual(alliedBotLaneTower.invalidBotDamageQueryCount or 0, 0,
	"tower never receives the bot-only damage-history API")
alliedBotLaneTower.attackTarget = nil
AssertEqual(Coordinator.CanInitiate(host), false, "position one may not cross-lane roam")
AssertEqual(Coordinator.CanInitiate(offCore), false, "position three may not cross-lane roam")
local unknown = NewUnit(99, TEAM_RADIANT, LANE_BOT, nil, 0)
AssertEqual(Coordinator.CanInitiate(unknown), false, "unknown position fails closed")
hardSupport.retreat = true
AssertEqual(Coordinator.CanInitiate(softSupport), false,
	"retreating lane teammate keeps support on its lane")
hardSupport.retreat = false
AssertEqual(Coordinator.CalculateTargetScore({
	healthFraction = 0,
	powerRatio = 1.5,
	enemyTowerDistance = 3000,
	ownSideDepth = 1,
	travelTime = 0,
	recentlyDamaged = true,
}), 1.0, "target score keeps the fixed 35/25/20/15/5 weighting")

-- 目标、发起者和跟随者选择必须确定且最多两名跨路英雄。
local proposal = Coordinator.BuildBestProposal(softSupport)
Assert(proposal ~= nil, "eligible visible lane target produces a proposal")
AssertEqual(proposal.leaderID, 11, "position bias and player ID elect soft support")
AssertEqual(#proposal.participantIDs, 2, "proposal caps cross-lane roamers at two")
AssertEqual(proposal.participantIDs[1], 11, "leader is first participant")
AssertEqual(proposal.participantIDs[2], 12, "deterministic follower is hard support")
local tieTarget = NewUnit(19, TEAM_DIRE, LANE_TOP, nil, 3000)
tieTarget.bot = false
tieTarget.health = target.health
tieTarget.location.laneDistance = 0
enemies = {target, tieTarget}
proposal = Coordinator.BuildBestProposal(softSupport)
AssertEqual(proposal.targetPlayerID, 19, "equal target score selects lower player ID")
enemies = {target}

ResetWorld(180)
softSupport.activeMode = BOT_MODE_ROAM
mid.activeMode = BOT_MODE_ROAM
softSupport:SetTarget(target)
mid:SetTarget(target)
softSupport.ping = {time = 180, location = target:GetLocation(), normal_ping = true}
mid.ping = {time = 180, location = target:GetLocation(), normal_ping = true}
AssertEqual(Coordinator.GetDesire(hardSupport), BOT_MODE_DESIRE_HIGH,
	"follower accepts one of two same-frame signals")
Assert(Coordinator.OnStart(hardSupport), "same-frame signal creates mission")
AssertEqual(Coordinator.GetMission(hardSupport).leaderID, 11,
	"same-frame signal selects lower initiator player ID")

ResetWorld(190)
hardSupport.activeMode = BOT_MODE_ROAM
mid.activeMode = BOT_MODE_ROAM
hardSupport:SetTarget(target)
mid:SetTarget(target)
hardSupport.ping = {time = 189, location = target:GetLocation(), normal_ping = true}
mid.ping = {time = 188, location = target:GetLocation(), normal_ping = true}
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_HIGH,
	"follower accepts the earliest of two valid signals")
Assert(Coordinator.OnStart(softSupport), "earliest signal creates mission")
AssertEqual(Coordinator.GetMission(softSupport).leaderID, 13,
	"earliest signal wins even when its player ID is larger")

-- 发起只发送一次普通信号和一次团队聊天；跟随者仅接受一致的原生信号。
StartLeader(200)
AssertEqual(softSupport:GetTarget(), target, "leader publishes the mission target")
AssertEqual(CountActions(softSupport, "ping"), 1, "leader sends one ping")
AssertEqual(#softSupport.chats, 1, "leader sends one chat message")
AssertEqual(softSupport.chats[1].allChat, false, "roam announcement is team chat")
Assert(softSupport.chats[1].message:find(tostring(target.playerID), 1, true) ~= nil,
	"chat identifies the target player ID")
AssertEqual(Coordinator.OnStart(softSupport), false, "duplicate OnStart has no pending mission")
AssertEqual(CountActions(softSupport, "ping"), 1, "duplicate OnStart sends no second ping")
AssertEqual(#softSupport.chats, 1, "duplicate OnStart sends no second chat")
Assert(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, softSupport.ping, now),
	"matching recent Bot roam signal is valid")
AssertEqual(Coordinator.GetDesire(hardSupport), BOT_MODE_DESIRE_HIGH,
	"selected follower accepts the leader signal")
Assert(Coordinator.OnStart(hardSupport), "selected follower starts the shared mission")
hardSupport.activeMode = BOT_MODE_ROAM
AssertEqual(hardSupport:GetTarget(), target, "follower synchronizes the same target")
AssertEqual(CountActions(hardSupport, "ping"), 0, "follower does not repeat the ping")
AssertEqual(#hardSupport.chats, 0, "follower does not repeat the chat")

local savedPing = softSupport.ping
softSupport.bot = false
AssertEqual(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, savedPing, now), false,
	"human signal is rejected")
softSupport.bot = true
softSupport.activeMode = BOT_MODE_NONE
AssertEqual(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, savedPing, now), false,
	"non-roam source is rejected")
softSupport.activeMode = BOT_MODE_ROAM
softSupport.target = tieTarget
AssertEqual(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, savedPing, now), false,
	"source target mismatch is rejected")
softSupport.target = target
savedPing.normal_ping = false
AssertEqual(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, savedPing, now), false,
	"danger ping is rejected")
savedPing.normal_ping = true
AssertEqual(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, savedPing, now + 4.1), false,
	"expired ping is rejected")
target.visible = false
AssertEqual(Coordinator.IsAnnouncementValid(hardSupport, softSupport, target, savedPing, now), false,
	"invisible target is rejected")
target.visible = true

ResetWorld(201)
softSupport.activeMode = BOT_MODE_ROAM
softSupport:SetTarget(target)
softSupport.ping = {time = now, location = target:GetLocation(), normal_ping = true}
towers[tostring(TEAM_DIRE) .. ":" .. tostring(TOWER_TOP_1)].location = Location(3100, 0, LANE_TOP)
AssertEqual(Coordinator.GetDesire(hardSupport), BOT_MODE_DESIRE_NONE,
	"otherwise valid signal is rejected when target is in tower danger")

StartLeader(210)

-- 未入选的 2 号位也观察信号并执行统一团队冷却。
AssertEqual(Coordinator.GetDesire(mid), BOT_MODE_DESIRE_NONE,
	"third cross-lane hero observes but does not join a two-person task")
now = 215
softSupport.activeMode = BOT_MODE_RETREAT
hardSupport.activeMode = BOT_MODE_RETREAT
AssertEqual(Coordinator.GetDesire(mid), BOT_MODE_DESIRE_NONE,
	"observed mission blocks a new task during team cooldown")
now = 270.1
AssertEqual(Coordinator.GetDesire(mid), BOT_MODE_DESIRE_HIGH,
	"team cooldown expires after sixty seconds")
Coordinator.Abort(mid, "test_cleanup")

-- 接近、交战和总任务时限都从原始任务起点计算，绝不被刷新。
StartLeader(300)
now = 311.9
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_HIGH,
	"approach remains active just below twelve seconds")
now = 312
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"approach releases at twelve seconds")
AssertEqual(softSupport:GetTarget(), nil, "approach timeout clears only the shared target")

StartLeader(400)
softSupport.location = Location(2200, 0, LANE_TOP)
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_VERYHIGH,
	"arrival within 900 enters engage")
now = 407.9
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_VERYHIGH,
	"engage remains active just below eight seconds")
now = 408
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"engage releases at eight seconds")

local hardLimitMission = StartLeader(500)
hardLimitMission.phase = "engage"
hardLimitMission.engageStartTime = 600
now = 521.9
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_VERYHIGH,
	"mission remains active just below hard limit")
now = 522
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"twenty-two-second hard limit overrides later phase timing")

-- 所有关键成功/取消条件必须当帧释放。
StartLeader(600)
target.visible = false
now = 602.4
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_HIGH,
	"lost target grace lasts up to 2.5 seconds")
now = 602.6
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"lost target releases after grace")

StartLeader(700)
towers[tostring(TEAM_DIRE) .. ":" .. tostring(TOWER_TOP_1)].location = Location(3100, 0, LANE_TOP)
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"target entering visible enemy tower range releases task")

StartLeader(800)
local reinforcementA = NewUnit(21, TEAM_DIRE, LANE_TOP, nil, 3200)
local reinforcementB = NewUnit(22, TEAM_DIRE, LANE_TOP, nil, 3300)
reinforcementA.bot, reinforcementB.bot = false, false
reinforcementA.power, reinforcementB.power = 1000, 1000
enemies = {target, reinforcementA, reinforcementB}
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"local power reversal releases task")

StartLeader(900)
softSupport.retreat = true
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"participant high-risk retreat releases task")

StartLeader(950)
AssertEqual(Coordinator.GetDesire(hardSupport), BOT_MODE_DESIRE_HIGH,
	"follower joins before team-wide participant release test")
Assert(Coordinator.OnStart(hardSupport), "follower starts before participant release test")
hardSupport.activeMode = BOT_MODE_ROAM
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_HIGH,
	"leader observes the joined follower")
hardSupport.retreat = true
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"leader also releases when a joined follower retreats")

StartLeader(1000)
defendDesire = BOT_MODE_DESIRE_HIGH
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"shared urgent defense releases task")

StartLeader(1100)
target.alive = false
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"target death completes and releases task")

StartLeader(1200)
AssertEqual(Coordinator.GetDesire(hardSupport), BOT_MODE_DESIRE_HIGH,
	"follower accepts mission before leader exit test")
Assert(Coordinator.OnStart(hardSupport), "follower mission starts before leader exit")
hardSupport.activeMode = BOT_MODE_ROAM
softSupport.activeMode = BOT_MODE_NONE
softSupport:SetTarget(nil)
AssertEqual(Coordinator.GetDesire(hardSupport), BOT_MODE_DESIRE_NONE,
	"follower releases when initiator leaves roam")

-- 运行时关闭开关会在下一次 GetDesire/Think 中静默释放，且关闭状态不产生副作用。
StartLeader(1300)
local chatsBeforeDisable = #softSupport.chats
local pingsBeforeDisable = CountActions(softSupport, "ping")
Config.ENABLED = false
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"runtime switch-off releases active mission immediately")
AssertEqual(softSupport:GetTarget(), nil, "runtime switch-off clears matching target")
AssertEqual(#softSupport.chats, chatsBeforeDisable, "switch-off sends no ending chat")
AssertEqual(CountActions(softSupport, "ping"), pingsBeforeDisable, "switch-off sends no ending ping")
Coordinator.ResetForTests()
softSupport.actions, softSupport.chats, softSupport.target = {}, {}, nil
AssertEqual(Coordinator.GetDesire(softSupport), BOT_MODE_DESIRE_NONE,
	"disabled framework creates no mission")
AssertEqual(Coordinator.GetMission(softSupport), nil, "disabled framework stores no mission")
AssertEqual(#softSupport.actions, 0, "disabled framework emits no action")
AssertEqual(#softSupport.chats, 0, "disabled framework emits no chat")

-- gank 执行器在技能前摇和引导阶段都不得覆盖移动或普攻。
StartLeader(1400)
softSupport.location = Location(2200, 0, LANE_TOP)
AssertEqual(Gank.GetDesire(softSupport), BOT_MODE_DESIRE_VERYHIGH,
	"gank enters engage before action guard test")
softSupport.actions = {}
softSupport.abilityPhase = true
Gank.Think(softSupport)
AssertEqual(#softSupport.actions, 0, "ability phase receives no gank action")
softSupport.abilityPhase = false
softSupport.channeling = true
Gank.Think(softSupport)
AssertEqual(#softSupport.actions, 0, "channeling receives no gank action")
softSupport.channeling = false
Gank.Think(softSupport)
AssertEqual(CountActions(softSupport, "attack"), 1, "gank resumes throttled focus attack afterward")

-- 路由器在独占辅助任务出现时取消旧 gank，辅助结束后先完整退出一次 ROAM。
local routerBot = NewUnit(50, TEAM_RADIANT, LANE_BOT, "soft_support", 0)
local routerAuxDesire = BOT_MODE_DESIRE_NONE
local routerAuxThinkCount = 0
local routerGankThinkCount = 0
local routerGankStartCount = 0
local routerAbortReasons = {}
local RouterAuxiliary = {
	GetDesire = function() return routerAuxDesire end,
	Think = function() routerAuxThinkCount = routerAuxThinkCount + 1 end,
	OnStart = function() end,
	OnEnd = function() end,
}
local RouterGank = {
	GetDesire = function() return BOT_MODE_DESIRE_HIGH end,
	OnStart = function() routerGankStartCount = routerGankStartCount + 1 return true end,
	Think = function() routerGankThinkCount = routerGankThinkCount + 1 end,
	Abort = function(_, reason) table.insert(routerAbortReasons, reason) end,
	OnEnd = function() end,
}
local RouterUtils = {
	NoteModeStart = function() end,
	AllowModeDesire = function() return true end,
}
package.loaded[configModule] = nil
package.loaded[BOT_ROOT .. "/THDFuncLib/roam_auxiliary"] = nil
package.loaded[gankModule] = nil
package.loaded[BOT_ROOT .. "/THDFuncLib/utils"] = nil
package.preload[configModule] = function() return Config end
package.preload[BOT_ROOT .. "/THDFuncLib/roam_auxiliary"] = function() return RouterAuxiliary end
package.preload[gankModule] = function() return RouterGank end
package.preload[BOT_ROOT .. "/THDFuncLib/utils"] = function() return RouterUtils end
function GetBot() return routerBot end
Config.ENABLED = true
dofile(BOT_ROOT .. "/mode_roam_generic.lua")
AssertEqual(GetDesire(), BOT_MODE_DESIRE_HIGH, "router selects gank when auxiliary is idle")
OnStart()
Think()
AssertEqual(routerGankStartCount, 1, "router starts selected gank")
AssertEqual(routerGankThinkCount, 1, "router delegates gank Think")
routerAuxDesire = BOT_MODE_DESIRE_ABSOLUTE
Think()
AssertEqual(routerAbortReasons[#routerAbortReasons], "auxiliary_preempted",
	"ability-phase auxiliary preempts and cancels old gank")
AssertEqual(routerAuxThinkCount, 1, "preempting auxiliary receives Think")
AssertEqual(routerGankThinkCount, 1, "preempted gank issues no replacement action")
routerAuxDesire = BOT_MODE_DESIRE_NONE
AssertEqual(GetDesire(), BOT_MODE_DESIRE_NONE,
	"auxiliary release forces one complete roam exit")
OnEnd()
local savedIsEnabled = Config.IsEnabled
Config.IsEnabled = nil
AssertEqual(GetDesire(), BOT_MODE_DESIRE_NONE,
	"router fails closed when config interface is missing")
Config.IsEnabled = function() return "true" end
AssertEqual(GetDesire(), BOT_MODE_DESIRE_NONE,
	"router fails closed when config interface returns the wrong type")
Config.IsEnabled = savedIsEnabled

local auxiliarySource = assert(io.open(
	BOT_ROOT .. "/THDFuncLib/roam_auxiliary.lua", "rb")):read("*a")
Assert(auxiliarySource:find("J.IsAbilityInChannelPhase", 1, true) ~= nil
	and auxiliarySource:find("ability_thdots_reisenOld03", 1, true) ~= nil,
	"auxiliary provider retains Reisen ability-phase and channel protection")
Assert(auxiliarySource:find("FlandreUltimate.GetModeDesire", 1, true) ~= nil
	and auxiliarySource:find("SunnyUltimate.GetModeDesire", 1, true) ~= nil
	and auxiliarySource:find("YuukaCombo.GetModeDesire", 1, true) ~= nil
	and auxiliarySource:find("NitoriPoke.GetModeDesire", 1, true) ~= nil,
	"all hero-specific roam controllers are isolated in the auxiliary provider")

print("test_roam_framework: OK")
