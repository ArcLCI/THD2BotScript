local J = require(GetScriptDirectory() .. '/THDFuncLib/thd_func')
local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/avoidance_geometry')
local TowerSafety = require(GetScriptDirectory() .. '/THDFuncLib/tower_safety')
local CombatPower = require(GetScriptDirectory() .. '/THDFuncLib/combat_power')
local SkillMovement = require(GetScriptDirectory() .. '/THDFuncLib/skill_avoidance')
local B = {}

local ABILITY = 'ability_thdots_tei02'
local MOTION = 'modifier_ability_thdots_tei02_back'
local RUN = 'TEI-R3-20260919'
local TURN_TIMEOUT = 0.65
local TURN_TOLERANCE = 8
local MAX_TURN_TRAVEL = 48

local function Special(ability, name, fallback)
	local value = ability:GetSpecialValueFloat(name)
	return value ~= nil and value > 0 and value or fallback
end

local function Valid(bot, unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
		and unit:GetTeam() ~= bot:GetTeam() and not unit:IsInvulnerable()
end

local function Log(bot, state, event, reason)
	local direction = state.direction or Vector(0, 0, 0)
	print(string.format('[BOT][Tei] run=%s team=%d player=%d event=backstep_%s reason=%s kind=%s facing=%.1f hop_dx=%.3f hop_dy=%.3f blast_targets=%d game_time=%.2f',
		RUN, bot:GetTeam(), bot:GetPlayerID(), event, reason or 'none', state.kind, bot:GetFacing(), direction.x, direction.y, state.blastTargets or 0, DotaTime()))
end

local function Finish(bot, state, reason, stopTurn)
	-- 只取消本模块在当前规避模式内发出的转身移动，不能打断已经开始的施法。
	if stopTurn and state.issuedMove and bot:IsAlive() and bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS
	and not bot:IsCastingAbility() and not bot:IsUsingAbility() and not bot:IsChanneling()
	and not bot:HasModifier(MOTION) then bot:Action_ClearActions(true) end
	Log(bot, state, state.phase == 'cast' and 'end' or 'cancel', reason)
	bot.THD_TeiBackstep = nil
	bot.THD_TeiBackstepRetry = DotaTime() + 0.8
end

local function State(bot)
	if bot == nil then return nil end
	local state = bot.THD_TeiBackstep
	if state == nil then return nil end
	if not bot:IsAlive() then Finish(bot, state, 'dead', false); return nil end
	if DotaTime() > state.expires then
		Finish(bot, state, state.phase == 'turn' and 'turn_timeout' or 'cast_timeout', state.phase == 'turn')
		return nil
	end
	return state
end

function B.IsActive(bot) return State(bot) ~= nil end

local function HopDistance(bot, ability)
	local distance, step = Special(ability, 'distance', 550), 120
	if bot:HasModifier('modifier_item_wanbaochui') then distance, step = distance * 2, step * 2 end
	-- 位移每0.03秒推进固定步长；按最后一步越过标称距离的终点检查。
	return math.ceil(distance / step) * step
end

local function Survey(bot)
	local enemies = {}
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)) do
		if Valid(bot, enemy) and not J.IsSuspiciousIllusion(enemy) then table.insert(enemies, enemy) end
	end
	return enemies
end

local function Nearest(location, enemies)
	local distance, nearest = math.huge, nil
	for _, enemy in ipairs(enemies) do
		local d = Geometry.Distance(location, enemy:GetLocation())
		if d < distance then distance, nearest = d, enemy end
	end
	return distance, nearest
end

local function Rotate(direction, degrees)
	local a = math.rad(degrees)
	return Vector(direction.x * math.cos(a) - direction.y * math.sin(a),
		direction.x * math.sin(a) + direction.y * math.cos(a), 0)
end

local function TurnSurvivable(bot, enemies, ability, turnTime)
	local incoming = 0
	for _, enemy in ipairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() + 150
		or enemy:GetAttackTarget() == bot then
			local damage = CombatPower.EstimateAttackDamage(enemy, bot, math.max(0.1, turnTime + ability:GetCastPoint()), 1)
			if damage == nil then return false end
			incoming = incoming + damage
		end
	end
	local defense = CombatPower.GetDefenseSnapshot(bot)
	return defense ~= nil and incoming < defense.health * 0.65
end

local function SafeLanding(bot, state, landing, enemies, observation)
	local origin = bot:GetLocation()
	if observation.available ~= true
	or not Geometry.ValidateMovementSegment(origin, landing, observation.towers, 96)
	or not Geometry.ValidateLocalTerrainSegment(origin, landing, true) then return false end
	-- 不允许位移路径从敌人贴身区域穿过去；已被贴脸时至少不能更贴近。
	for _, enemy in ipairs(enemies) do
		local startDistance = GetUnitToUnitDistance(bot, enemy)
		if Geometry.SegmentDistanceToPoint(origin, landing, enemy:GetLocation()) < math.min(180, startDistance - 10) then return false end
	end
	local before = Nearest(origin, enemies)
	local after = Nearest(landing, enemies)
	if after < 400 then return false end
	if state.kind == 'escape' then return after >= before + 100 end
	if not Valid(bot, state.target) then return false end
	-- 接敌/侧跳同时检查落点附近人数，不能只用起点附近的友军作为掩护。
	local localEnemies, localAllies = 0, 1
	for _, enemy in ipairs(enemies) do
		if Geometry.Distance(landing, enemy:GetLocation()) <= 1000 then localEnemies = localEnemies + 1 end
	end
	for _, ally in pairs(CachedGetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)) do
		if ally ~= bot and ally:IsAlive() and not J.IsSuspiciousIllusion(ally)
		and Geometry.Distance(landing, ally:GetLocation()) <= 1000 then localAllies = localAllies + 1 end
	end
	if localEnemies > localAllies + (state.kind == 'chase' and 0 or 1) then return false end
	local predicted = state.target:GetExtrapolatedLocation(0.35)
	local targetDistance = Geometry.Distance(landing, predicted)
	if state.kind == 'kite' then
		return after >= before + 100 and targetDistance <= bot:GetAttackRange() + 150
	end
	return targetDistance >= 400 and targetDistance <= bot:GetAttackRange() + 75
		and targetDistance <= GetUnitToUnitDistance(bot, state.target) - 200
end

local function TurnPoint(bot, direction, observation)
	-- API没有纯转身命令，给出短直线移动引导；到位即用技能替换，实际移动限48。
	local origin = bot:GetLocation()
	local point = origin - direction * 72
	if observation.available ~= true
	or not Geometry.ValidateMovementSegment(origin, point, observation.towers, 96)
	or not Geometry.ValidateLocalTerrainSegment(origin, point, true) then return nil end
	return point
end

local function MissionValid(bot, state, ability, enemies)
	if #enemies == 0 then return false end
	if state.kind == 'escape' then return true end
	if not Valid(bot, state.target) or state.target:IsAttackImmune() or bot:IsDisarmed() then return false end
	if bot:WasRecentlyDamagedByTower(2.0) then return false end
	local danger = TowerSafety.Scan(bot)
	if danger.unseenIncoming or danger.incomingCount > 0 then return false end
	local hp = J.GetHP(bot)
	if hp < (state.kind == 'chase' and 0.65 or 0.4) then return false end
	local count = 0
	for _, enemy in ipairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= 1000 then count = count + 1 end
	end
	local allies = 1
	for _, ally in pairs(CachedGetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE)) do
		if ally ~= bot and ally:IsAlive() and not J.IsSuspiciousIllusion(ally) then allies = allies + 1 end
	end
	if count > allies + (state.kind == 'chase' and 0 or 1) then return false end
	if state.kind == 'chase' then
		return bot:GetMana() >= ability:GetManaCost() + state.manaReserve
			and GetUnitToUnitDistance(bot, state.target) > bot:GetAttackRange() + 150
	end
	-- 贴脸威胁已经解除时不再为了放炸弹进行多余位移。
	return Nearest(bot:GetLocation(), enemies) <= 450
end

function B.Start(bot, ability, kind, target, manaReserve)
	if State(bot) ~= nil or DotaTime() < (bot.THD_TeiBackstepRetry or -90) then return false end
	if J.IsTowerEscapeActive(bot) or SkillMovement.IsActive(bot) then return false end
	if bot:IsSilenced() or bot:IsRooted() or not ability or ability:GetLevel() == 0 or not ability:IsFullyCastable() then return false end
	local enemies = Survey(bot)
	local near, nearest = Nearest(bot:GetLocation(), enemies)
	local state = {kind = kind, target = target, manaReserve = manaReserve or 0, phase = 'turn'}
	if kind == 'kite' or not Valid(bot, target) then state.target = nearest end
	if not MissionValid(bot, state, ability, enemies) then return false end
	local origin = bot:GetLocation()
	local distance = HopDistance(bot, ability)
	local directions = {}
	local base
	if kind == 'chase' then
		if GetUnitToUnitDistance(bot, state.target) <= bot:GetAttackRange() + 200
		or GetUnitToUnitDistance(bot, state.target) > distance + bot:GetAttackRange() + 75 then return false end
		base = (state.target:GetExtrapolatedLocation(0.35) - origin):Normalized()
		for _, angle in ipairs({0, -15, 15, -30, 30}) do table.insert(directions, Rotate(base, angle)) end
	else
		base = (origin - nearest:GetLocation()):Normalized()
		for angle = 0, 330, 30 do table.insert(directions, Rotate(base, angle)) end
		local ancient = GetAncient(bot:GetTeam())
		if ancient ~= nil then table.insert(directions, (ancient:GetLocation() - origin):Normalized()) end
	end
	local facing = math.rad(bot:GetFacing())
	table.insert(directions, Vector(-math.cos(facing), -math.sin(facing), 0))
	local observation = TowerSafety.Observe(bot, 'tei_backstep_plan')
	local best, bestScore
	for _, direction in ipairs(directions) do
		local landing = origin + direction * distance
		if direction:Length2D() > 0.9 and SafeLanding(bot, state, landing, enemies, observation) then
			local facePoint = origin - direction * 72
			local aligned = bot:IsFacingLocation(facePoint, TURN_TOLERANCE)
			if (aligned or TurnPoint(bot, direction, observation) ~= nil)
			and TurnSurvivable(bot, enemies, ability, aligned and 0 or TURN_TIMEOUT) then
				local after = Nearest(landing, enemies)
				local score = after - near + (aligned and 120 or 0)
				if kind ~= 'escape' then score = score - math.abs(Geometry.Distance(landing, state.target:GetExtrapolatedLocation(0.35)) - 500) end
				if kind == 'escape' then
					local ancient = GetAncient(bot:GetTeam())
					if ancient ~= nil then score = score + (Geometry.Distance(origin, ancient:GetLocation()) - Geometry.Distance(landing, ancient:GetLocation())) * 0.2 end
				end
				if bestScore == nil or score > bestScore then best, bestScore = direction, score end
			end
		end
	end
	if best == nil then return false end
	state.direction = best
	-- 替身在施法原地约1秒后爆炸；这里只记录预测覆盖，不把延迟伤害当成必中斩杀。
	state.blastTargets = 0
	for _, enemy in ipairs(enemies) do
		if not enemy:IsMagicImmune()
		and Geometry.Distance(origin, enemy:GetExtrapolatedLocation(Special(ability, 'duration', 1) + ability:GetCastPoint())) <= Special(ability, 'radius', 350) - 40 then
			state.blastTargets = state.blastTargets + 1
		end
	end
	state.startLocation = Vector(origin.x, origin.y, origin.z)
	state.expires = DotaTime() + TURN_TIMEOUT
	state.lastMove = -90
	bot.THD_TeiBackstep = state
	Log(bot, state, 'plan', 'safe_candidate')
	return true
end

function B.GetDesire(bot)
	return State(bot) ~= nil and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE
end

function B.Think(bot)
	local state = State(bot)
	if state == nil then return false end
	local ability = bot:GetAbilityByName(ABILITY)
	if ability == nil then Finish(bot, state, 'missing_ability', false); return true end
	if state.phase == 'cast' then
		if bot:HasModifier(MOTION) then return true end
		if ability:IsInAbilityPhase() then
			-- 被动反击也可能在前摇中改变朝向；技能尚未触发时只允许这个明确的安全取消。
			local facePoint = bot:GetLocation() - state.direction * 72
			if not bot:IsFacingLocation(facePoint, TURN_TOLERANCE) then
				bot:Action_ClearActions(true)
				bot.THD_TeiActionUntil = nil
				Finish(bot, state, 'facing_changed_during_cast', false)
			end
			return true
		end
		if ability:GetCooldownTimeRemaining() > 0 then Finish(bot, state, 'cooldown_confirmed', false) end
		return true
	end
	if bot:IsSilenced() or bot:IsRooted() or bot:IsStunned() or bot:IsHexed() or bot:IsNightmared()
	or not ability:IsFullyCastable() then Finish(bot, state, 'disabled', true); return true end
	if bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling() then
		Finish(bot, state, 'other_cast', false); return true
	end
	if Geometry.Distance(bot:GetLocation(), state.startLocation) > MAX_TURN_TRAVEL then
		Finish(bot, state, 'turn_travel_limit', true); return true
	end
	local enemies = Survey(bot)
	local facePoint = bot:GetLocation() - state.direction * 72
	local aligned = bot:IsFacingLocation(facePoint, TURN_TOLERANCE)
	if not MissionValid(bot, state, ability, enemies)
	or not TurnSurvivable(bot, enemies, ability, aligned and 0 or math.max(0, state.expires - DotaTime())) then
		Finish(bot, state, 'mission_or_health_changed', true); return true
	end
	local origin = bot:GetLocation()
	local distance = HopDistance(bot, ability)
	local observation = TowerSafety.Observe(bot, 'tei_backstep_turn')
	if not SafeLanding(bot, state, origin + state.direction * distance, enemies, observation) then
		Finish(bot, state, 'landing_changed', true); return true
	end
	if aligned then
		-- 最后按真实朝向重算一次，不把已发出的转身命令当作已经转好。
		local a = math.rad(bot:GetFacing())
		local actualDirection = Vector(-math.cos(a), -math.sin(a), 0)
		for _, margin in ipairs({-TURN_TOLERANCE, 0, TURN_TOLERANCE}) do
			if not SafeLanding(bot, state, origin + Rotate(actualDirection, margin) * distance, enemies, observation) then
				Finish(bot, state, 'facing_margin_unsafe', true); return true
			end
		end
		state.phase = 'cast'
		state.expires = DotaTime() + ability:GetCastPoint() + 0.55
		bot.THD_TeiActionUntil = DotaTime() + ability:GetCastPoint() + 0.35
		bot:Action_UseAbility(ability)
		Log(bot, state, 'cast', 'facing_confirmed')
		return true
	end
	local point = TurnPoint(bot, state.direction, observation)
	if point == nil then Finish(bot, state, 'turn_path_changed', true); return true end
	if DotaTime() - state.lastMove >= 0.10 then
		state.lastMove = DotaTime()
		state.issuedMove = true
		bot:Action_MoveToLocation(point)
	end
	return true
end

function B.OnEnd(bot)
	local state = State(bot)
	if state == nil then return false end
	if state.phase == 'turn' then Finish(bot, state, 'mode_lost', false) end
	return true
end

return B
