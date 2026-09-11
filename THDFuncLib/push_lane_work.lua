local TowerSafety = require(GetScriptDirectory()..'/THDFuncLib/tower_safety')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Wasteland = require(GetScriptDirectory()..'/THDFuncLib/wasteland_strategy')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Config = require(GetScriptDirectory()..'/THDFuncLib/bot_diagnostics_config')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Work = {}

Work.ENABLED = true
local SEARCH_INTERVAL = 1.0
local SAFETY_INTERVAL = 0.5
local MAX_DISTANCE = 1400
local REACH_DISTANCE = 180
local TASK_DURATION = 12.0
local NO_PROGRESS_TIME = 3.0
local TOWER_MARGIN = 96
local DESIRE = {clear_wave = 0.28, escort_wave = 0.22, stage_lane = 0.18, approach_lane = 0.16}

local function State(bot)
	if bot.THD_PushLaneWork == nil then
		bot.THD_PushLaneWork = {generation = 0, nextSearch = -90, nextSafety = -90}
	end
	return bot.THD_PushLaneWork
end

local function Copy(location)
	return Geometry.MakeVector(location.x, location.y, location.z)
end

local function VisibleUnit(unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
end

local function Log(bot, task, event, reason)
	if Config.DEBUG_LOG ~= true or task == nil then return end
	local current = bot:GetLocation()
	print(string.format('[BOT][LaneWork] run=%s team=%s player=%s generation=%s lane=%s kind=%s event=%s reason=%s dota_time=%.3f action_intent_count=%d x=%.1f y=%.1f target_x=%.1f target_y=%.1f distance=%.1f expires_at=%.3f goal_x=%.1f goal_y=%.1f',
		tostring(Config.RUN_ID), tostring(bot:GetTeam()), tostring(bot:GetPlayerID()),
		tostring(task.generation), tostring(task.lane), tostring(task.kind), event, tostring(reason),
		DotaTime(), task.actions or 0, current.x, current.y, task.location.x, task.location.y,
		Geometry.Distance(current, task.location), task.expiresAt,
		(task.goal or task.location).x, (task.goal or task.location).y))
end

function Work.Release(bot, reason, lane)
	if bot == nil or bot.THD_PushLaneWork == nil then return end
	local state = bot.THD_PushLaneWork
	local task = state.task
	if task == nil or (lane ~= nil and task.lane ~= lane) then return end
	Log(bot, task, 'released', reason)
	state.task = nil
	state.nextSearch = math.max(state.nextSearch, DotaTime() + 1.0)
	if reason == 'no_progress' or reason == 'expired' then
		state.rejectedLocation = Copy(task.location)
		state.rejectedUntil = DotaTime() + 8.0
	end
	-- 不清队列、不清 GetTarget；它们可能已属于正常攻击、技能或其他模式。
end

function Work.Leave(bot, reason, lane)
	Work.Release(bot, reason, lane)
	local state = bot ~= nil and bot.THD_PushLaneWork or nil
	if state ~= nil and (lane == nil or state.deniedLane == lane) then state.deniedLane = nil end
end

local function ProtectedPhase(bot)
	local ability = bot:GetCurrentActiveAbility()
	if ability == nil then return false end
	local ok, protected = pcall(function()
		return ability:IsInAbilityPhase() or ability:IsChanneling()
	end)
	return not ok or protected
end

local function OwnershipBlock(bot)
	if not Work.ENABLED or not Wasteland.IsEnabled() then return 'disabled' end
	if not bot:IsAlive() or bot:IsIllusion() or bot:GetLevel() <= 15 then return 'invalid_or_laning' end
	if J.CanNotUseAction(bot) or ProtectedPhase(bot) then return 'protected_or_unavailable' end
	if J.GetHP(bot) < 0.55 or bot:WasRecentlyDamagedByAnyHero(2.0)
	or bot:WasRecentlyDamagedByTower(2.0) then return 'recent_danger_or_low_hp' end
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then return 'high_retreat' end
	if J.IsRoshanCommitmentActive(bot) then return 'roshan_commitment' end
	local objective = Wasteland.GetPushObjective(true)
	if objective ~= nil and Wasteland.IsPushObjectiveReservedParticipant(bot, objective) then
		return 'objective_reserved'
	end
	local mode, desire = bot:GetActiveMode(), bot:GetActiveModeDesire()
	-- 仅普通空窗接管；不放宽 ROAM 角色，也不压低 Valve 的战斗/撤退分数。
	if desire > 0 and (mode == BOT_MODE_ATTACK or mode == BOT_MODE_RETREAT
		or mode == BOT_MODE_ROAM or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_DEFEND_TOWER_TOP or mode == BOT_MODE_DEFEND_TOWER_MID
		or mode == BOT_MODE_DEFEND_TOWER_BOT or mode == BOT_MODE_RUNE or mode == BOT_MODE_OUTPOST) then
		return 'other_active_task'
	end
	local target = bot:GetAttackTarget()
	if VisibleUnit(target) and target:IsHero() and target:GetTeam() ~= bot:GetTeam() then
		return 'local_combat'
	end
	local base = Wasteland.GetBaseThreatSnapshot(nil, bot)
	if base ~= nil and base.hardEmergency == true then return 'base_emergency' end
	return nil
end

local function RefreshSafety(bot, state)
	local now = DotaTime()
	if now < state.nextSafety then return end
	state.nextSafety = now + SAFETY_INTERVAL
	state.enemies = {}
	-- 只读 Bot API 的最近目击点，最多五个敌方玩家；没有全地图单位扫描。
	for _, id in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local info = GetHeroLastSeenInfo(id)
			local seen = info ~= nil and info[1] or nil
			if seen ~= nil and seen.time_since_seen < 5.0 then
				table.insert(state.enemies, seen.location)
			end
		end
	end
end

local function SafeSegment(bot, state, location)
	local current = bot:GetLocation()
	local distance = Geometry.Distance(current, location)
	if distance > MAX_DISTANCE then return false, 'beyond_local_range' end
	local observation = TowerSafety.Observe(bot, 'push_lane')
	if observation.available ~= true then return false, 'tower_snapshot_stale' end
	if not Geometry.ValidateMovementSegment(current, location, observation.towers, TOWER_MARGIN) then
		return false, 'tower_segment'
	end
	for _, enemy in ipairs(state.enemies or {}) do
		if Geometry.SegmentDistanceToPoint(current, location, enemy) < 1200 then return false, 'recent_enemy_near_segment' end
	end
	-- 保守检查整段局部地形/视野；不假定一个可走终点意味着途中没有障碍。
	local steps = math.max(1, math.ceil(distance / 180))
	for i = 1, steps do
		local point = Geometry.MakeVector(current.x + (location.x - current.x) * i / steps,
			current.y + (location.y - current.y) * i / steps, location.z)
		if not IsLocationPassable(point) then return false, 'impassable_segment' end
		if not IsLocationVisible(point) then return false, 'unseen_segment' end
	end
	return true
end

local function CanChoose(bot, state, location)
	local safe, reason
	if state.rejectedUntil ~= nil and DotaTime() < state.rejectedUntil
	and Geometry.Distance(location, state.rejectedLocation) < 300 then
		safe, reason = false, 'recent_failed_location'
	else
		safe, reason = SafeSegment(bot, state, location)
	end
	if not safe then state.lastRejection = reason end
	return safe
end

local function Choose(bot, state, lane)
	state.lastRejection = 'no_local_creep_or_staging_point'
	local current = bot:GetLocation()
	local best, bestDistance = nil, math.huge
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(1200, true)) do
		if VisibleUnit(creep) and J.CanBeAttacked(creep) then
			local location = creep:GetLocation()
			local distance = Geometry.Distance(current, location)
			if distance < bestDistance and CanChoose(bot, state, location) then
				best = {kind = 'clear_wave', unit = creep, location = Copy(location)}
				bestDistance = distance
			end
		end
	end
	if best ~= nil then return best end
	local homeward = GetLaneFrontLocation(bot:GetTeam(), lane, -1800)
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(1200, false)) do
		if VisibleUnit(creep) then
			local location = creep:GetLocation()
			local distance = Geometry.Distance(location, homeward)
			if distance > 1 then
				local scale = math.min(240, distance) / distance
				location = Geometry.MakeVector(location.x + (homeward.x - location.x) * scale,
					location.y + (homeward.y - location.y) * scale, location.z)
			end
			if Geometry.Distance(current, location) > REACH_DISTANCE
			and CanChoose(bot, state, location) then
				return {kind = 'escort_wave', unit = creep, location = Copy(location)}
			end
		end
	end
	-- 冻结一个安全集合点；已在该点就不伪造任务，也不持续向敌方 Ancient 续步。
	local distantGoals = {}
	for _, offset in ipairs({-1200, -1800, -2400}) do
		local location = GetLaneFrontLocation(bot:GetTeam(), lane, offset)
		if CanChoose(bot, state, location) then
			if Geometry.Distance(current, location) <= REACH_DISTANCE then
				state.lastRejection = 'already_staged'
				return nil
			end
			return {kind = 'stage_lane', location = Copy(location)}
		end
		if state.lastRejection == 'beyond_local_range'
		and Geometry.Distance(current, location) <= 6000 then
			table.insert(distantGoals, {location = location, offset = offset})
		end
	end
	-- 远处真实集合目标只授权一段可见、安全的短程接近，抵达后必须重新竞争。
	-- 优先保留上面的近处任务；最多检查三目标 x 三步长，不放宽 siege/伤害门槛。
	for _, goal in ipairs(distantGoals) do
		local location = goal.location
		local distance = Geometry.Distance(current, location)
		for _, step in ipairs({900, 600, 360}) do
			local target = Geometry.MakeVector(current.x + (location.x - current.x) * step / distance,
				current.y + (location.y - current.y) * step / distance, current.z)
			if CanChoose(bot, state, target) then
				return {kind = 'approach_lane', location = Copy(target), goal = Copy(location), offset = goal.offset}
			end
		end
	end
	return nil
end

local function Validate(bot, state, task)
	local now = DotaTime()
	if now >= task.expiresAt then return false, 'expired' end
	if task.kind == 'approach_lane' and Geometry.Distance(task.goal,
		GetLaneFrontLocation(bot:GetTeam(), task.lane, task.offset)) > 600 then
		return false, 'lane_goal_changed'
	end
	if task.unit ~= nil then
		if not VisibleUnit(task.unit) then return false, 'target_lost' end
		if task.kind == 'clear_wave' then
			if not J.CanBeAttacked(task.unit) then return false, 'target_unattackable' end
			task.location = Copy(task.unit:GetLocation())
			if Geometry.Distance(task.origin, task.location) > MAX_DISTANCE then return false, 'target_left_area' end
		elseif Geometry.Distance(task.unit:GetLocation(), task.location) > 600 then
			return false, 'escort_moved_on'
		end
	end
	local safe, safetyReason = SafeSegment(bot, state, task.location)
	if not safe then return false, safetyReason end
	local distance = Geometry.Distance(bot:GetLocation(), task.location)
	if task.kind ~= 'clear_wave' and distance <= REACH_DISTANCE then return false, 'arrived' end
	local health = task.kind == 'clear_wave' and task.unit:GetHealth() or nil
	if task.bestDistance - distance >= 48
	or (health ~= nil and task.lastHealth ~= nil and health < task.lastHealth) then
		task.lastProgressAt = now
		task.bestDistance = math.min(task.bestDistance, distance)
	end
	task.lastHealth = health
	if now - task.lastProgressAt >= NO_PROGRESS_TIME then return false, 'no_progress' end
	return true
end

function Work.GetDesire(bot, lane, denialReason)
	local state = State(bot)
	state.deniedLane = lane
	CandidateDebug.Detail('siege_denial', denialReason)
	local blocked = OwnershipBlock(bot)
	if denialReason ~= 'eligible_below_4' and denialReason ~= 'average_level_below_23' then
		blocked = blocked or 'siege_safety_denial'
	end
	if blocked ~= nil then
		Work.Release(bot, blocked)
		CandidateDebug.Note('lane_work_' .. blocked)
		return BOT_MODE_DESIRE_NONE
	end
	RefreshSafety(bot, state)
	if state.task ~= nil and state.task.lane ~= lane then Work.Release(bot, 'lane_changed') end
	if state.task ~= nil then
		local valid, reason = Validate(bot, state, state.task)
		if not valid then Work.Release(bot, reason) end
	end
	if state.task == nil and DotaTime() >= state.nextSearch then
		state.nextSearch = DotaTime() + SEARCH_INTERVAL
		local task = Choose(bot, state, lane)
		if task ~= nil then
			state.generation = state.generation + 1
			task.generation, task.lane = state.generation, lane
			task.origin = Copy(bot:GetLocation())
			task.expiresAt = DotaTime() + TASK_DURATION
			task.lastProgressAt = DotaTime()
			task.bestDistance = Geometry.Distance(task.origin, task.location)
			task.lastHealth = task.kind == 'clear_wave' and task.unit:GetHealth() or nil
			task.actions = 0
			state.task = task
			Log(bot, task, 'created', denialReason)
		end
	end
	if state.task == nil then
		CandidateDebug.Note('lane_work_no_safe_task')
		CandidateDebug.Detail('lane_work_last_rejection', state.lastRejection)
		CandidateDebug.Detail('lane_work_next_search', state.nextSearch)
		return BOT_MODE_DESIRE_NONE
	end
	CandidateDebug.Note('lane_work_' .. state.task.kind)
	CandidateDebug.Detail('lane_work_generation', state.task.generation)
	CandidateDebug.Detail('lane_work_expires', state.task.expiresAt)
	return DESIRE[state.task.kind]
end

function Work.TryThink(bot, lane)
	local state = bot.THD_PushLaneWork
	if state == nil or state.deniedLane ~= lane then return false end
	-- 即使任务已经失效，也消费这帧旧 push Think，绝不落入建筑或 AttackMove 分支。
	local task = state.task
	if task == nil or task.lane ~= lane then return true end
	local blocked = OwnershipBlock(bot)
	if blocked ~= nil then Work.Release(bot, blocked); return true end
	RefreshSafety(bot, state)
	local valid, reason = Validate(bot, state, task)
	if not valid then Work.Release(bot, reason); return true end
	local acted
	if task.kind == 'clear_wave' then
		-- Bot 无 IsAttacking 成员；仅“攻击动作且目标相同”才保留现有普攻。
		local ok, actionType, attackTarget = pcall(function()
			return bot:GetCurrentActionType(), bot:GetAttackTarget()
		end)
		if not ok or type(actionType) ~= 'number' or type(BOT_ACTION_TYPE_ATTACK) ~= 'number' then
			Work.Release(bot, 'attack_state_unavailable')
			return true
		end
		if actionType ~= BOT_ACTION_TYPE_ATTACK or attackTarget ~= task.unit then
			acted = J.ActionAttackUnit(bot, 'lane_work_clear_wave', task.unit, true, 0.35)
		elseif task.attackPreservedLogged ~= true then
			-- 每个任务最多一条，区分沿用真实攻击与没有进入动作分支。
			task.attackPreservedLogged = true
			Log(bot, task, 'attack_preserved', 'same_target_attack')
		end
	else
		acted = J.ActionMoveToLocation(bot, 'lane_work_' .. task.kind, task.location, 0.35, 120, function(point) return SafeSegment(bot, state, point) end)
	end
	if acted then
		-- 共享动作助手命中节流也返回 true；这里计意图，不冒充引擎实际下单数。
		task.actions = task.actions + 1
		if task.actions == 1 then Log(bot, task, 'started', 'first_action_intent') end
	end
	if DotaTime() - (task.lastLogAt or DotaTime()) >= 2.0 then
		Log(bot, task, 'progress', 'executing')
		task.lastLogAt = DotaTime()
	end
	task.lastLogAt = task.lastLogAt or DotaTime()
	return true
end

return Work
