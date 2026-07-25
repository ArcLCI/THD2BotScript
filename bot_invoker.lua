require(GetScriptDirectory() .. "/bot_generic")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")

local owner = GetBot()
local FIRE_UNIT = "npc_thdots_unit_patchouli_fire_fire"
local MAX_WORK_DISTANCE = 1500
local SCOUT_DISTANCE = 700
local SCOUT_COMBAT_DISTANCE = 900
local ATTACK_INTERVAL = 0.45
local MOVE_INTERVAL = 0.65

local function IsValidUnit(unit)
	return unit ~= nil and not unit:IsNull() and unit:IsAlive()
end

local function IsValidEnemyHero(unit)
	return IsValidUnit(unit)
		and unit:IsHero()
		and unit:CanBeSeen()
		and not J.IsSuspiciousIllusion(unit)
		and J.CanBeAttacked(unit)
end

local function GetEntityKey(unit)
	if unit ~= nil and unit.entindex ~= nil then
		local ok, index = pcall(function() return unit:entindex() end)
		if ok then return tostring(index) end
	end
	return tostring(unit)
end

local function ThrottledAttack(unit, target)
	if not IsValidUnit(target) then return end
	unit.patchouliMinionState = unit.patchouliMinionState or {}
	local state = unit.patchouliMinionState
	local key = GetEntityKey(target)
	if state.action == "attack" and state.key == key
	and DotaTime() - (state.time or -100) < ATTACK_INTERVAL
	then return end
	unit:Action_AttackUnit(target, true)
	state.action, state.key, state.time = "attack", key, DotaTime()
end

local function ThrottledMove(unit, location)
	unit.patchouliMinionState = unit.patchouliMinionState or {}
	local state = unit.patchouliMinionState
	local key = tostring(math.floor(location.x / 120)) .. ":" .. tostring(math.floor(location.y / 120))
	if state.action == "move" and state.key == key
	and DotaTime() - (state.time or -100) < MOVE_INTERVAL
	then return end
	unit:Action_MoveToLocation(location)
	state.action, state.key, state.time = "move", key, DotaTime()
end

local function IsTowerAttacking(unit)
	for _, tower in pairs(unit:GetNearbyTowers(1000, true) or {}) do
		if IsValidUnit(tower) and tower:GetAttackTarget() == unit then return true end
	end
	return false
end

local function IsUnderEnemyTower(unit, target)
	for _, tower in pairs(unit:GetNearbyTowers(1600, true) or {}) do
		if IsValidUnit(tower) and GetUnitToUnitDistance(tower, target) <= 850 then
			return true
		end
	end
	return false
end

local function IsLocationUnderEnemyTower(location)
	for _, tower in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS) or {}) do
		if IsValidUnit(tower)
		and tower:IsTower()
		and GetUnitToLocationDistance(tower, location) <= 850
		then
			return true
		end
	end
	return false
end

local function GetHeroTarget(unit)
	local target = J.GetProperTarget(owner)
	if IsValidEnemyHero(target)
	and GetUnitToUnitDistance(owner, target) <= MAX_WORK_DISTANCE
	then return target end
	local best = nil
	local bestScore = -math.huge
	for _, enemy in pairs(unit:GetNearbyHeroes(900, true, BOT_MODE_NONE) or {}) do
		if IsValidEnemyHero(enemy) then
			local score = (1 - J.GetHP(enemy)) * 100
			if enemy:IsChanneling() then score = score + 200 end
			if score > bestScore then best, bestScore = enemy, score end
		end
	end
	return best
end

local function GetLaneHarassTarget(unit)
	local best = nil
	local bestScore = -math.huge
	for _, enemy in pairs(unit:GetNearbyHeroes(900, true, BOT_MODE_NONE) or {}) do
		if IsValidEnemyHero(enemy)
		and GetUnitToUnitDistance(owner, enemy) <= MAX_WORK_DISTANCE
		and not IsUnderEnemyTower(unit, enemy)
		then
			local score = (1 - J.GetHP(enemy)) * 100
			if enemy:GetAttackRange() >= 400 then score = score + 20 end
			if enemy:IsChanneling() then score = score + 100 end
			if score > bestScore then best, bestScore = enemy, score end
		end
	end
	return best
end

local function GetFarmTarget(unit)
	local weakest = nil
	local hp = math.huge
	for _, creep in pairs(unit:GetNearbyLaneCreeps(750, true) or {}) do
		if IsValidUnit(creep) and creep:GetHealth() < hp then weakest, hp = creep, creep:GetHealth() end
	end
	for _, creep in pairs(unit:GetNearbyNeutralCreeps(650) or {}) do
		if IsValidUnit(creep) and creep:GetHealth() < hp then weakest, hp = creep, creep:GetHealth() end
	end
	return weakest
end

local function GetLaneLastHitTarget(unit)
	local best = nil
	local lowestHealth = math.huge
	for _, creep in pairs(unit:GetNearbyLaneCreeps(800, true) or {}) do
		if IsValidUnit(creep) and creep:CanBeSeen() and J.CanBeAttacked(creep) then
			local delay = J.GetAttackProDelayTime(unit, creep)
			if J.WillKillTarget(creep, unit:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL, delay)
			and creep:GetHealth() < lowestHealth
			then
				best = creep
				lowestHealth = creep:GetHealth()
			end
		end
	end
	return best
end

local function GetForwardReferenceLocation()
	local target = J.GetProperTarget(owner)
	if IsValidUnit(target)
	and target:CanBeSeen()
	and target:GetTeam() == GetOpposingTeam()
	then
		return target:GetLocation()
	end

	local attackTarget = owner:GetAttackTarget()
	if IsValidUnit(attackTarget)
	and attackTarget:CanBeSeen()
	and attackTarget:GetTeam() == GetOpposingTeam()
	then
		return attackTarget:GetLocation()
	end

	local lane = owner:GetAssignedLane()
	if lane == LANE_TOP or lane == LANE_MID or lane == LANE_BOT then
		local laneFront = GetLaneFrontLocation(GetOpposingTeam(), lane, 0)
		if laneFront ~= nil then return laneFront end
	end

	local ancient = GetAncient(GetOpposingTeam())
	return IsValidUnit(ancient) and ancient:GetLocation() or nil
end

local function GetForwardScoutLocation()
	if not owner:IsAlive() then return nil end
	local reference = GetForwardReferenceLocation()
	if reference == nil then return nil end

	local ownerLocation = owner:GetLocation()
	local direction = reference - ownerLocation
	if direction:Length2D() < 50 then return nil end

	local distance = (J.IsGoingOnSomeone(owner) or J.IsInTeamFight(owner, 1200))
		and SCOUT_COMBAT_DISTANCE
		or SCOUT_DISTANCE
	local location = ownerLocation + direction:Normalized() * distance

	-- 前出点不能把火元素直接送进敌塔；危险时逐级收缩到本体位置。
	if IsLocationUnderEnemyTower(location) then
		location = ownerLocation + direction:Normalized() * 350
		if IsLocationUnderEnemyTower(location) then
			location = ownerLocation
		end
	end
	return location
end

local function FireElementThink(unit)
	if not IsValidUnit(unit)
	or unit:IsStunned()
	or unit:IsNightmared()
	or unit:IsUsingAbility()
	then return end

	-- 残血、被塔攻击或脱离工作半径时优先回到帕秋莉，避免召唤物无意义送死。
	if unit:GetHealth() / math.max(1, unit:GetMaxHealth()) < 0.25
	or IsTowerAttacking(unit)
	or (owner:IsAlive() and GetUnitToUnitDistance(owner, unit) > MAX_WORK_DISTANCE)
	then
		ThrottledMove(unit, owner:IsAlive() and owner:GetLocation() or GetAncient(GetTeam()):GetLocation())
		return
	end

	-- 英雄交战优先集中同一目标，持续施法者与低血目标由目标函数自然提高优先级。
	local heroTarget = GetHeroTarget(unit)
	if heroTarget ~= nil and (J.IsGoingOnSomeone(owner) or J.IsInTeamFight(owner, 1200)) then
		ThrottledAttack(unit, heroTarget)
		return
	end

	local isLaning = owner:GetActiveMode() == BOT_MODE_LANING

	-- 对线期优先消耗；没有安全英雄目标时只抢可一击收掉的兵，避免无脑推线。
	if isLaning
	and unit:GetHealth() / math.max(1, unit:GetMaxHealth()) >= 0.35
	then
		local laneTarget = GetLaneHarassTarget(unit)
		if laneTarget ~= nil then
			ThrottledAttack(unit, laneTarget)
			return
		end
	end
	if isLaning then
		local lastHitTarget = GetLaneLastHitTarget(unit)
		if lastHitTarget ~= nil then
			ThrottledAttack(unit, lastHitTarget)
			return
		end
	end

	-- 非对线阶段在前排发现安全目标时先手接敌，为本体提供视野和接战信息。
	if not isLaning
	and heroTarget ~= nil
	and not J.IsRetreating(owner)
	and unit:GetHealth() / math.max(1, unit:GetMaxHealth()) >= 0.45
	and not IsUnderEnemyTower(unit, heroTarget)
	then
		ThrottledAttack(unit, heroTarget)
		return
	end

	local target = J.GetProperTarget(owner)
	if J.IsDoingRoshan(owner) and J.IsRoshan(target) then
		ThrottledAttack(unit, target)
		return
	end

	-- 推进与附近发育共享短距离目标选择，不允许火元素跨线独立分推。
	local farmTarget = GetFarmTarget(unit)
	if farmTarget ~= nil and (J.IsPushing(owner) or J.IsDefending(owner) or owner:GetActiveMode() == BOT_MODE_FARM) then
		ThrottledAttack(unit, farmTarget)
		return
	end
	if J.IsPushing(owner) then
		for _, building in pairs(unit:GetNearbyTowers(850, true) or {}) do
			if IsValidUnit(building) then ThrottledAttack(unit, building); return end
		end
	end

	-- 无明确攻击任务时，火元素沿本体目标或分路前线方向前出，承担视野和先手接敌。
	if owner:IsAlive() and not isLaning and not J.IsRetreating(owner) then
		local scoutLocation = GetForwardScoutLocation()
		if scoutLocation ~= nil and GetUnitToLocationDistance(unit, scoutLocation) > 140 then
			ThrottledMove(unit, scoutLocation)
			return
		end
	end

	if owner:IsAlive() and GetUnitToUnitDistance(owner, unit) > 450 then
		ThrottledMove(unit, owner:GetLocation())
	end
end

function MinionThink(hMinionUnit)
	if hMinionUnit ~= nil and hMinionUnit:GetUnitName() == FIRE_UNIT then
		FireElementThink(hMinionUnit)
		return
	end
	THD2MinionThink(hMinionUnit)
end
