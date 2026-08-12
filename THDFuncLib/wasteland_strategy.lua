local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

local Strategy = {}

-- Wasteland 部署保持开启；Nostalgia 部署必须把本开关设为 false，关闭后完全沿用旧逻辑。
Strategy.ENABLED = true
Strategy.BALANCE_START_TIME = 15 * 60
Strategy.BALANCE_END_TIME = 20 * 60
Strategy.OUTER_TOWER_DEADLINE = 30 * 60
Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND = 25
Strategy.MIN_LEVEL_LEAD = 1.0
Strategy.MIN_KILL_RATIO = 1.25
Strategy.MAX_LEVEL_DEFICIT_FOR_KILL_LEAD = 0.5
Strategy.BALANCED_ROAM_PROPOSAL_DESIRE = 0.82
Strategy.ADVANTAGE_ROAM_PROPOSAL_DESIRE = 0.78
Strategy.ADVANTAGE_OUTER_PUSH_DESIRE = 0.92
Strategy.OUTER_PUSH_START_TIME = 9 * 60
Strategy.OUTER_COMMIT_DURATION = 12.0
Strategy.OUTER_COMMIT_DESIRE = 0.94
Strategy.CONVERSION_OPPORTUNITY_DURATION = 12.0
Strategy.DEBUG = true

local outerCommitments = {}
local conversionOpportunities = {}
local towerSnapshotMilestones = {}

local OUTER_TOWERS = {}
for _, towerID in ipairs({TOWER_TOP_1, TOWER_TOP_2, TOWER_MID_1, TOWER_MID_2, TOWER_BOT_1, TOWER_BOT_2}) do
	if towerID ~= nil then table.insert(OUTER_TOWERS, towerID) end
end

local LANE_OUTER_TOWERS = {}
if LANE_TOP ~= nil then LANE_OUTER_TOWERS[LANE_TOP] = {TOWER_TOP_1, TOWER_TOP_2} end
if LANE_MID ~= nil then LANE_OUTER_TOWERS[LANE_MID] = {TOWER_MID_1, TOWER_MID_2} end
if LANE_BOT ~= nil then LANE_OUTER_TOWERS[LANE_BOT] = {TOWER_BOT_1, TOWER_BOT_2} end

local PUSH_MODES = {}
if BOT_MODE_PUSH_TOWER_TOP ~= nil then PUSH_MODES[BOT_MODE_PUSH_TOWER_TOP] = true end
if BOT_MODE_PUSH_TOWER_MID ~= nil then PUSH_MODES[BOT_MODE_PUSH_TOWER_MID] = true end
if BOT_MODE_PUSH_TOWER_BOT ~= nil then PUSH_MODES[BOT_MODE_PUSH_TOWER_BOT] = true end

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function GetTeamKey()
	return Safe(nil, function() return GetTeam() end)
end

local function GetNow()
	return Safe(0, function() return DotaTime() end) or 0
end

local function GetPlayerID(bot)
	return bot ~= nil and Safe(-1, function() return bot:GetPlayerID() end) or -1
end

local function Debug(bot, message)
	if Strategy.DEBUG ~= true then return end
	print(string.format('[BOT][Objective] pid=%s %s game_time=%.1f',
		tostring(GetPlayerID(bot)), tostring(message), GetNow()))
end

local function GetEnemyTower(towerID)
	if towerID == nil then return nil end
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	if enemyTeam == nil then return nil end
	return Safe(nil, function() return GetTower(enemyTeam, towerID) end)
end

local function GetLaneOuterTower(lane)
	for tier, towerID in ipairs(LANE_OUTER_TOWERS[lane] or {}) do
		local tower = GetEnemyTower(towerID)
		if tower ~= nil then return tower, tier, towerID end
	end
	return nil, nil, nil
end

local function IsCommitValid(commit, now)
	if type(commit) ~= 'table' or now >= (commit.expireAt or -9999) then return false end
	local tower = GetEnemyTower(commit.towerID)
	if tower == nil then return false end
	commit.tower = tower
	return true
end

local function ClearCommit(team, reason, bot)
	local commit = outerCommitments[team]
	if commit == nil then return end
	outerCommitments[team] = nil
	Debug(bot, string.format('action=outer_commit_release lane=%s tier=%s source=%s reason=%s elapsed=%.1f first_attack=%s',
		tostring(commit.lane), tostring(commit.tier), tostring(commit.source), tostring(reason),
		math.max(0, GetNow() - (commit.createdAt or GetNow())), tostring(commit.firstAttackTime ~= nil)))
end

local function GetStrictAverageLevel(team)
	local players = Safe({}, function() return GetTeamPlayers(team) end) or {}
	-- 用户要求按五名英雄平均等级放行；名单不完整时 fail-closed，避免误上高。
	if #players ~= 5 then return nil end
	local total = 0
	for _, playerID in ipairs(players) do
		local level = Safe(nil, function() return GetHeroLevel(playerID) end)
		if type(level) ~= 'number' or level < 1 then return nil end
		total = total + level
	end
	return total / #players
end

local function CountEnemyOuterTowers()
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	if enemyTeam == nil or #OUTER_TOWERS == 0 then return nil end
	local count = 0
	for _, towerID in ipairs(OUTER_TOWERS) do
		local ok, tower = pcall(function() return GetTower(enemyTeam, towerID) end)
		-- 塔查询失败属于未知状态，不能被误判为六座外塔已经全部拆完。
		if not ok then return nil end
		if tower ~= nil then
			count = count + 1
		end
	end
	return count
end

function Strategy.IsEnabled()
	return Strategy.ENABLED == true
end

function Strategy.IsTeamAhead(state)
	if type(state) ~= 'table' then return false end
	local allyAverage = tonumber(state.allyAverageLevel)
	local enemyAverage = tonumber(state.enemyAverageLevel)
	if allyAverage == nil or enemyAverage == nil then return false end
	if (tonumber(state.allyAlive) or 0) < (tonumber(state.enemyAlive) or 0) then return false end
	if allyAverage - enemyAverage >= Strategy.MIN_LEVEL_LEAD then return true end
	local allyKills = math.max(0, tonumber(state.allyKills) or 0)
	local enemyKills = math.max(0, tonumber(state.enemyKills) or 0)
	local killRatio = (allyKills + 1) / (enemyKills + 1)
	return killRatio >= Strategy.MIN_KILL_RATIO
		and allyAverage + Strategy.MAX_LEVEL_DEFICIT_FOR_KILL_LEAD >= enemyAverage
end

function Strategy.GetState()
	local team = Safe(nil, function() return GetTeam() end)
	local enemyTeam = Safe(nil, function() return GetOpposingTeam() end)
	local state = {
		time = Safe(0, function() return DotaTime() end) or 0,
		outerTowersRemaining = CountEnemyOuterTowers(),
		allyAverageLevel = team ~= nil and GetStrictAverageLevel(team) or nil,
		enemyAverageLevel = enemyTeam ~= nil and GetStrictAverageLevel(enemyTeam) or nil,
		allyAlive = Safe(0, function() return J.GetNumOfAliveHeroes(false) end) or 0,
		enemyAlive = Safe(0, function() return J.GetNumOfAliveHeroes(true) end) or 0,
		allyKills = Safe(0, function() return J.GetNumOfTeamTotalKills(false) end) or 0,
		enemyKills = Safe(0, function() return J.GetNumOfTeamTotalKills(true) end) or 0,
	}
	state.teamAhead = Strategy.IsTeamAhead(state)
	state.conversionOpportunity = Strategy.GetConversionOpportunity()
	state.outerCommitment = Strategy.GetOuterTowerCommitment()
	return state
end

function Strategy.GetOuterTowerCommitment()
	if not Strategy.IsEnabled() then return nil end
	local team = GetTeamKey()
	if team == nil then return nil end
	local now = GetNow()
	local commit = outerCommitments[team]
	if commit ~= nil and not IsCommitValid(commit, now) then
		ClearCommit(team, GetEnemyTower(commit.towerID) == nil and 'tower_destroyed' or 'expired')
		return nil
	end
	return commit
end

function Strategy.NoteRoamKill(lane, missionID, bot)
	if not Strategy.IsEnabled() then return false end
	local team = GetTeamKey()
	if team == nil then return false end
	local now = GetNow()
	conversionOpportunities[team] = {
		lane = lane,
		missionID = missionID,
		createdAt = now,
		expireAt = now + Strategy.CONVERSION_OPPORTUNITY_DURATION,
	}
	Debug(bot, string.format('action=conversion_opportunity source=roam_kill mission=%s lane=%s duration=%.1f',
		tostring(missionID or 'unknown'), tostring(lane or 'auto'), Strategy.CONVERSION_OPPORTUNITY_DURATION))
	return true
end

function Strategy.GetConversionOpportunity()
	if not Strategy.IsEnabled() then return nil end
	local team = GetTeamKey()
	if team == nil then return nil end
	local opportunity = conversionOpportunities[team]
	if opportunity ~= nil and GetNow() >= (opportunity.expireAt or -9999) then
		conversionOpportunities[team] = nil
		return nil
	end
	return opportunity
end

function Strategy.TryCreateOuterTowerCommitment(bot, lane, state)
	if not Strategy.IsEnabled() or LANE_OUTER_TOWERS[lane] == nil then return nil end
	state = state or Strategy.GetState()
	local now = tonumber(state.time) or GetNow()
	if now < Strategy.OUTER_PUSH_START_TIME or tonumber(state.outerTowersRemaining) == 0 then return nil end

	local opportunity = state.conversionOpportunity or Strategy.GetConversionOpportunity()
	local source = nil
	if opportunity ~= nil and (opportunity.lane == nil or opportunity.lane == lane) then
		source = 'roam_kill'
	elseif (tonumber(state.allyAlive) or 0) > (tonumber(state.enemyAlive) or 0) then
		source = 'alive_advantage'
	elseif state.teamAhead == true or Strategy.IsTeamAhead(state) then
		source = 'team_ahead'
	end
	if source == nil then return nil end

	local team = GetTeamKey()
	if team == nil then return nil end
	local existing = Strategy.GetOuterTowerCommitment()
	if existing ~= nil then
		if existing.lane == lane then
			existing.expireAt = math.max(existing.expireAt or now, now + Strategy.OUTER_COMMIT_DURATION)
			existing.lastRefreshTime = now
		end
		return existing
	end

	local tower, tier, towerID = GetLaneOuterTower(lane)
	if tower == nil or tier > 2 then return nil end
	local commit = {
		lane = lane,
		tier = tier,
		towerID = towerID,
		tower = tower,
		source = source,
		missionID = opportunity ~= nil and opportunity.missionID or nil,
		createdAt = now,
		lastRefreshTime = now,
		expireAt = now + Strategy.OUTER_COMMIT_DURATION,
	}
	outerCommitments[team] = commit
	Debug(bot, string.format('action=outer_commit_start lane=%s tier=%s source=%s mission=%s duration=%.1f ally_alive=%s enemy_alive=%s ally_avg=%s enemy_avg=%s',
		tostring(lane), tostring(tier), tostring(source), tostring(commit.missionID or 'none'),
		Strategy.OUTER_COMMIT_DURATION, tostring(state.allyAlive), tostring(state.enemyAlive),
		tostring(state.allyAverageLevel), tostring(state.enemyAverageLevel)))
	return commit
end

function Strategy.ReleaseOuterTowerCommitment(reason, bot)
	local team = GetTeamKey()
	if team == nil or outerCommitments[team] == nil then return false end
	ClearCommit(team, reason or 'released', bot)
	return true
end

function Strategy.NoteOuterTowerAttack(bot, lane, tower)
	local commit = Strategy.GetOuterTowerCommitment()
	if commit == nil or commit.lane ~= lane or tower == nil then return false end
	if commit.firstAttackTime == nil then
		commit.firstAttackTime = GetNow()
		Debug(bot, string.format('action=outer_commit_first_attack lane=%s tier=%s source=%s delay=%.1f',
			tostring(lane), tostring(commit.tier), tostring(commit.source),
			math.max(0, commit.firstAttackTime - (commit.createdAt or commit.firstAttackTime))))
	end
	commit.expireAt = math.max(commit.expireAt or GetNow(), GetNow() + Strategy.OUTER_COMMIT_DURATION)
	return true
end

function Strategy.ObserveOuterTowerSnapshot(bot, state)
	if not Strategy.IsEnabled() then return end
	state = state or Strategy.GetState()
	local team = GetTeamKey()
	if team == nil then return end
	towerSnapshotMilestones[team] = towerSnapshotMilestones[team] or {}
	for _, milestone in ipairs({10 * 60, 15 * 60, 20 * 60, 25 * 60, 30 * 60}) do
		if (tonumber(state.time) or 0) >= milestone and not towerSnapshotMilestones[team][milestone] then
			towerSnapshotMilestones[team][milestone] = true
			local values = {}
			for _, lane in ipairs({LANE_TOP, LANE_MID, LANE_BOT}) do
				for tier, towerID in ipairs(LANE_OUTER_TOWERS[lane] or {}) do
					local tower = GetEnemyTower(towerID)
					local health = tower ~= nil and Safe(nil, function() return tower:GetHealth() end) or nil
					table.insert(values, string.format('%s_t%d=%s:%s', tostring(lane), tier,
						tower ~= nil and 'alive' or 'dead', health ~= nil and tostring(health) or 'na'))
				end
			end
			Debug(bot, string.format('action=outer_tower_snapshot milestone=%s remaining=%s towers=%s',
				tostring(milestone), tostring(state.outerTowersRemaining), table.concat(values, ',')))
		end
	end
end

function Strategy.ShouldHoldHighGround(laneBuildingTier, averageLevel)
	if not Strategy.IsEnabled() or (tonumber(laneBuildingTier) or 1) < 3 then return false end
	local level = tonumber(averageLevel)
	if level == nil then
		local team = Safe(nil, function() return GetTeam() end)
		level = team ~= nil and GetStrictAverageLevel(team) or nil
	end
	return level == nil or level < Strategy.MIN_TEAM_AVERAGE_LEVEL_FOR_HIGH_GROUND
end

function Strategy.AdjustPushDesire(baseDesire, laneBuildingTier, state, lane)
	if not Strategy.IsEnabled() then return baseDesire end
	if Strategy.ShouldHoldHighGround(laneBuildingTier,
		state ~= nil and state.allyAverageLevel or nil)
	then
		return BOT_MODE_DESIRE_NONE
	end
	state = state or Strategy.GetState()
	local commit = state.outerCommitment or Strategy.GetOuterTowerCommitment()
	if commit ~= nil and (lane == nil or commit.lane == lane) and (tonumber(laneBuildingTier) or 3) <= 2 then
		return math.max(baseDesire or BOT_MODE_DESIRE_NONE, Strategy.OUTER_COMMIT_DESIRE)
	end
	local now = tonumber(state.time) or 0
	if (tonumber(laneBuildingTier) or 3) <= 2
		and now >= Strategy.BALANCE_START_TIME
		and now < Strategy.OUTER_TOWER_DEADLINE
		and (state.teamAhead == true or Strategy.IsTeamAhead(state))
	then
		return math.max(baseDesire or BOT_MODE_DESIRE_NONE, Strategy.ADVANTAGE_OUTER_PUSH_DESIRE)
	end
	return baseDesire
end

function Strategy.AdjustRoamProposalDesire(baseDesire, state)
	if not Strategy.IsEnabled() then return baseDesire end
	state = state or Strategy.GetState()
	if state.outerCommitment ~= nil or Strategy.GetOuterTowerCommitment() ~= nil then
		return BOT_MODE_DESIRE_NONE
	end
	-- 只有明确观测到 0 座外塔时才恢复原优先级；读取失败不能被误判为已经拆完。
	if tonumber(state.outerTowersRemaining) == 0 then return baseDesire end
	local now = tonumber(state.time) or 0
	if now >= Strategy.BALANCE_START_TIME and now < Strategy.BALANCE_END_TIME then
		return math.min(baseDesire, Strategy.BALANCED_ROAM_PROPOSAL_DESIRE)
	end
	if now >= Strategy.BALANCE_END_TIME and now < Strategy.OUTER_TOWER_DEADLINE
		and (state.teamAhead == true or Strategy.IsTeamAhead(state))
	then
		return math.min(baseDesire, Strategy.ADVANTAGE_ROAM_PROPOSAL_DESIRE)
	end
	return baseDesire
end

function Strategy.ShouldProtectOuterPushParticipant(position, activeMode, state)
	if not Strategy.IsEnabled() or PUSH_MODES[activeMode] ~= true then return false end
	if position ~= 'mid' and position ~= 'off_core' and position ~= 'safe_core' then return false end
	state = state or Strategy.GetState()
	if state.outerCommitment ~= nil or Strategy.GetOuterTowerCommitment() ~= nil then return true end
	-- 只有明确确认外塔为 0 才解除核心位的推进承诺；未知状态继续 fail-closed。
	if tonumber(state.outerTowersRemaining) == 0 then return false end
	local now = tonumber(state.time) or 0
	if now >= Strategy.BALANCE_START_TIME and now < Strategy.BALANCE_END_TIME then return true end
	return now >= Strategy.BALANCE_END_TIME and now < Strategy.OUTER_TOWER_DEADLINE
		and (state.teamAhead == true or Strategy.IsTeamAhead(state))
end

function Strategy.GetStrictTeamAverageLevel()
	local team = Safe(nil, function() return GetTeam() end)
	return team ~= nil and GetStrictAverageLevel(team) or nil
end

function Strategy.ResetForTests()
	outerCommitments = {}
	conversionOpportunities = {}
	towerSnapshotMilestones = {}
end

return Strategy
