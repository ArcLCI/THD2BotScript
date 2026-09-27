local Config = require(GetScriptDirectory()..'/THDFuncLib/push_escort_config')
local Escort = {}

local function Distance(a, b)
	local x, y = a.x - b.x, a.y - b.y
	return math.sqrt(x * x + y * y)
end

local function CopyPoint(point)
	return point and Vector(point.x, point.y, point.z) or nil
end

local function Formation(front, objective, offset, side)
	local x, y = objective.x - front.x, objective.y - front.y
	local length = math.max(1, math.sqrt(x*x + y*y))
	return Vector(front.x + (x*offset-y*(side or 0))/length,
		front.y + (y*offset+x*(side or 0))/length, front.z)
end

-- 输入只包含调用方已核实的可见单位；本模块不扫描、不下命令。
local function SelectWave(snapshot, oldWave, generation)
	local groups, used = {}, {}
	for index, creep in ipairs(snapshot.alliedCreeps) do
		if not used[index] then
			local group, cursor = {creep}, 1
			used[index] = true
			while cursor <= #group do
				for otherIndex, other in ipairs(snapshot.alliedCreeps) do
					if not used[otherIndex] and Distance(group[cursor].location, other.location) <= Config.GROUP_DISTANCE then
						used[otherIndex] = true
						table.insert(group, other)
					end
				end
				cursor = cursor + 1
			end
			table.insert(groups, group)
		end
	end
	local chosen, chosenRetained, chosenDistance, chosenKey = nil, false, math.huge, ''
	for _, group in ipairs(groups) do
		local retained, distance, key = false, math.huge, group[1].key
		for _, creep in ipairs(group) do
			retained = retained or (oldWave ~= nil and oldWave.members[creep.unit] ~= nil)
			distance = math.min(distance, Distance(creep.location, snapshot.objectiveLocation))
			if creep.key < key then key = creep.key end
		end
		if chosen == nil or (retained and not chosenRetained)
		or (retained == chosenRetained and (distance < chosenDistance or (distance == chosenDistance and key < chosenKey))) then
			chosen, chosenRetained, chosenDistance, chosenKey = group, retained, distance, key
		end
	end
	if chosen == nil then return nil, generation end
	if not chosenRetained then generation = generation + 1 end
	local wave = {id = chosenRetained and oldWave.id or generation, members = {}, count = #chosen,
		health = 0, siegeCount = 0, distance = chosenDistance, sampledAt = snapshot.sampledAt,
		bestDistance = chosenRetained and oldWave.bestDistance or chosenDistance,
		progressAt = chosenRetained and oldWave.progressAt or snapshot.now}
	local x, y, z, frontDistance = 0, 0, 0, math.huge
	for _, creep in ipairs(chosen) do
		wave.members[creep.unit] = creep
		wave.health = wave.health + creep.health
		wave.siegeCount = wave.siegeCount + (creep.siege and 1 or 0)
		x, y, z = x+creep.location.x, y+creep.location.y, z+creep.location.z
		local distance = Distance(creep.location, snapshot.objectiveLocation)
		if distance < frontDistance then wave.front, frontDistance = creep.location, distance end
	end
	wave.location = Vector(x/wave.count, y/wave.count, z/wave.count)
	-- 只比较同一批已知单位的血量；消失或换波不伪造掉血来源。
	wave.underPressure = false
	if chosenRetained then
		for unit, creep in pairs(wave.members) do
			local old = oldWave.members[unit]
			if old ~= nil and creep.health < old.health then wave.underPressure = true end
		end
	end
	return wave, generation
end

local function WaveDistance(wave, location)
	local result = math.huge
	for _, creep in pairs(wave.members) do result = math.min(result, Distance(creep.location, location)) end
	return result
end

local function SelectThreat(snapshot, wave, previous)
	local best, bestRank, bestDistance, potential = nil, math.huge, math.huge, false
	local observation = {visible = #snapshot.enemies, near = 0, attackingWave = 0, outsideChase = 0}
	for _, enemy in ipairs(snapshot.enemies) do
		local distance = WaveDistance(wave, enemy.location)
		if distance <= Config.POTENTIAL_RANGE then potential = true; observation.near = observation.near + 1 end
		local victim = wave.members[enemy.attackTarget]
		if victim ~= nil then
			observation.attackingWave = observation.attackingWave + 1
			if distance > Config.CHASE_RANGE then observation.outsideChase = observation.outsideChase + 1 end
		end
		if victim ~= nil and distance <= Config.CHASE_RANGE then
			local rank = enemy.unit == previous and 0 or (victim.siege and 1 or 2)
			if rank < bestRank or (rank == bestRank and (distance < bestDistance
			or (distance == bestDistance and (best == nil or enemy.key < best.key)))) then
				best, bestRank, bestDistance = enemy, rank, distance
			end
		end
	end
	observation.reason = best ~= nil and 'confirmed_attack_target'
		or (observation.outsideChase > 0 and 'attacker_outside_chase'
		or (observation.visible == 0 and 'no_visible_enemy'
		or (wave.underPressure and 'wave_damage_source_unknown' or 'no_enemy_attacking_wave')))
	return best, potential, observation
end

local function SelectBlocker(snapshot, wave)
	local best, bestDistance = nil, math.huge
	for _, creep in ipairs(snapshot.enemyCreeps) do
		local distance = WaveDistance(wave, creep.location)
		local ahead = Distance(creep.location, snapshot.objectiveLocation) <= wave.distance + 300
		if (wave.members[creep.attackTarget] ~= nil or (ahead and distance <= 600))
		and (distance < bestDistance or (distance == bestDistance and (best == nil or creep.key < best.key))) then
			best, bestDistance = creep, distance
		end
	end
	return best
end

function Escort.Evaluate(snapshot, previousState)
	local state = previousState or {}
	if state.objectiveID ~= snapshot.objectiveID or state.lane ~= snapshot.lane then state = {} end
	state.objectiveID, state.lane, state.role = snapshot.objectiveID, snapshot.lane, snapshot.role
	state.expiresAt = snapshot.now + Config.CONTEXT_TTL
	state.progressReason = nil
	state.threatObservation, state.pressureReason = nil, 'no_local_wave'
	-- 战略目标附近的兵不等于本Bot已经抵达；集结不借用SIEGE/ESCORT编队状态。
	if snapshot.approach then
		state.wave, state.threat, state.potentialThreat = nil,nil,false
		state.phase, state.reason, state.untilAt = 'APPROACH','approach_lane',nil
		state.guardLocation, state.fallbacks = snapshot.approachLocation,{}
		return state,{kind = 'move', reason = 'approach_lane', location = snapshot.approachLocation}
	end
	local oldWave = state.wave
	state.wave, state.generation = SelectWave(snapshot, oldWave, state.generation or 0)
	local wave = state.wave
	state.waveLoss = wave == nil and snapshot.waveLoss or nil
	local decision = {kind = 'move', reason = 'formation'}
	if wave ~= nil then
		local followingWave = wave.distance > Distance(snapshot.botLocation,snapshot.objectiveLocation) + 300
		if oldWave == nil or oldWave.id ~= wave.id then
			state.pressureTarget, state.pressureUntil, state.pressureSpent = nil, nil, nil
		end
		if wave.bestDistance - wave.distance >= Config.PROGRESS_DISTANCE then
			wave.bestDistance, wave.progressAt = wave.distance, snapshot.now
			state.progressReason = state.blocker ~= nil and snapshot.blockerDead and 'blocker_cleared_wave_advance' or 'escort_wave_advance'
			state.pressureSpent = nil
		end
		-- 只有仍可见且确实退出护线范围的原威胁，才能产生压退进展。
		for _, enemy in ipairs(snapshot.enemies) do
			if enemy.unit == state.pressureTarget and WaveDistance(wave, enemy.location) > Config.CHASE_RANGE
			and state.pressureProgressUsed ~= state.pressureSerial then
				state.progressReason = 'escort_threat_displaced'
				state.pressureProgressUsed = state.pressureSerial
			end
		end
		local threat, potential, observation = SelectThreat(snapshot, wave, state.pressureTarget)
		state.threatObservation = observation
		local blocker = SelectBlocker(snapshot, wave)
		state.threat, state.potentialThreat = threat and threat.unit or nil, potential
		state.blocker = blocker and blocker.unit or state.blocker
		state.location = wave.location
		local pressureAllowed = threat ~= nil and snapshot.pressureSafe
		state.pressureReason = threat == nil and observation.reason or (snapshot.pressureSafe and 'eligible' or 'low_hp')
		if pressureAllowed and snapshot.role == 'cover' then
			pressureAllowed = Distance(snapshot.botLocation, threat.location) <= snapshot.attackRange
			if not pressureAllowed then state.pressureReason = 'cover_outside_attack_range' end
		end
		if pressureAllowed then
			if state.pressureSpent == threat.unit then state.pressureReason = 'pressure_budget_spent'
			elseif snapshot.role == 'building_damage' and snapshot.canSiege then state.pressureReason = 'building_role_siege'
			elseif snapshot.role == 'wave_clear' and blocker ~= nil then state.pressureReason = 'wave_clear_blocker' end
		end
		if pressureAllowed and state.pressureSpent ~= threat.unit
		and (snapshot.role ~= 'building_damage' or not snapshot.canSiege)
		and not (snapshot.role == 'wave_clear' and blocker ~= nil) then
			if state.pressureTarget ~= threat.unit or state.pressureUntil == nil then
				state.pressureTarget, state.pressureUntil = threat.unit, snapshot.now + Config.PRESSURE_DURATION
				state.pressureSerial = (state.pressureSerial or 0) + 1
			end
			if snapshot.now < state.pressureUntil then
				state.phase = 'PRESSURE'
				state.pressureReason = 'active'
				decision = {kind = 'attack', target = threat.unit, location = threat.location, reason = 'clearer', untilAt = state.pressureUntil}
			else
				state.pressureSpent = threat.unit
				state.pressureReason = 'pressure_deadline'
			end
		end
		if decision.kind ~= 'attack' then
			state.phase = snapshot.canSiege and 'SIEGE' or 'ESCORT'
			if snapshot.canSiege and snapshot.role == 'building_damage' then
				decision = {kind = 'building', reason = 'siege'}
			elseif blocker ~= nil then
				decision = {kind = 'attack', target = blocker.unit, location = blocker.location, reason = 'blocker'}
			elseif snapshot.canSiege and not potential then
				-- 角色决定优先级而非永久攻击资格：没有清兵/掩护威胁时补充拆塔。
				decision = {kind = 'building', reason = 'supplement_siege'}
			end
		end
		if followingWave and not snapshot.canSiege and decision.kind == 'move' then
			state.phase = 'REGROUP'
			state.regroupUntil = state.regroupUntil or snapshot.now + Config.REGROUP_DURATION
			decision.reason, decision.untilAt = 'meet_next_wave', state.regroupUntil
			if snapshot.now >= state.regroupUntil then decision.kind, decision.reason = 'release', 'regroup_timeout' end
		end
		local offset, side = Config.CLEAR_OFFSET, 0
		if snapshot.role == 'frontline' then offset = Config.FRONT_OFFSET
		elseif snapshot.role == 'cover' then offset, side = Config.COVER_OFFSET, snapshot.playerID % 2 == 0 and Config.COVER_SIDE or -Config.COVER_SIDE
		elseif snapshot.role == 'building_damage' then
			offset = -Config.OUTPUT_NEAR - (Config.OUTPUT_FAR-Config.OUTPUT_NEAR)*math.max(0, math.min(1, (snapshot.attackRange-300)/400))
		end
		state.guardLocation = Formation(wave.front, snapshot.objectiveLocation, offset, side)
		state.fallbacks = {Formation(wave.front, snapshot.objectiveLocation, -300), Formation(wave.front, snapshot.objectiveLocation, -600)}
		if wave.distance <= 850 then state.regroupUntil = nil end
	else
		state.threat, state.potentialThreat = nil, false
		if snapshot.canSiege and (snapshot.continuation or snapshot.creepSupport) then
			state.phase = 'SIEGE'
			decision = {kind = (snapshot.role == 'building_damage' or snapshot.supplementSafe) and 'building' or 'move',
				reason = snapshot.creepSupport and 'current_creep_support' or 'bounded_continuation'}
		else
			state.phase = 'REGROUP'
			state.regroupUntil = state.regroupUntil or snapshot.now + Config.REGROUP_DURATION
			decision.reason, decision.untilAt = 'await_wave', state.regroupUntil
			if snapshot.now >= state.regroupUntil then decision.kind, decision.reason = 'release', 'regroup_timeout' end
		end
		-- 续接窗口的非输出位留在已通过安全门的位置，不被编队带出维持半径。
		state.guardLocation = snapshot.canSiege and CopyPoint(snapshot.botLocation) or snapshot.regroupLocation
		state.fallbacks = {state.guardLocation}
	end
	if snapshot.continuation and not snapshot.creepSupport and snapshot.canSiege and (wave == nil or wave.distance > 850) then
		-- 下一波尚未到塔时仍只消费本次四秒窗口，不让掩护位跟着远处新波离开。
		if state.threat ~= nil then state.pressureReason = 'bounded_siege_priority' end
		state.phase = 'SIEGE'
		state.guardLocation, state.fallbacks = CopyPoint(snapshot.botLocation), {CopyPoint(snapshot.botLocation)}
		decision = {kind = snapshot.supplementSafe and 'building' or (snapshot.role == 'building_damage' and 'building' or 'move'),
			reason = 'bounded_continuation', untilAt = snapshot.continuationUntil}
	end
	-- 关闭的只是无兵拆塔授权；现存/下一波仍允许安全护送、清障和限时压制。
	if snapshot.mustRegroup and wave == nil and not snapshot.creepSupport then
		state.phase = 'REGROUP'
		state.regroupUntil = state.regroupUntil or snapshot.now + Config.REGROUP_DURATION
		decision = {kind = snapshot.now < state.regroupUntil and 'move' or 'release', reason = 'continuation_closed', untilAt = state.regroupUntil}
		-- 不能继续沿用前排的塔前站位，退出到接兵位置。
		state.guardLocation, state.fallbacks = snapshot.regroupLocation, {snapshot.regroupLocation}
	end
	decision.location = decision.location or state.guardLocation
	state.reason, state.untilAt = decision.reason, decision.untilAt
	return state, decision
end

function Escort.GetContext(bot)
	local state = bot and bot.THD_PushEscort
	if not Config.PUSH_ESCORT_ENABLED or state == nil or DotaTime() >= state.expiresAt then return nil end
	-- 返回独立上下文；消费者不能修改内部波次或任务期限。
	return {objectiveID = state.objectiveID, lane = state.lane, role = state.role,
		waveID = state.wave and state.wave.id, phase = state.phase, threat = state.threat,
		guardLocation = CopyPoint(state.guardLocation), expiresAt = state.expiresAt, untilAt = state.untilAt}
end

function Escort.Release(bot, reason)
	if bot == nil then return end
	bot.THD_PushEscort = nil
	bot.THD_PushEscortSample = nil
	bot.THD_PushEscortReleaseReason = reason
end

return Escort
