require(GetScriptDirectory() .. "/bot_generic")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local Wasteland = require(GetScriptDirectory() .. "/THDFuncLib/wasteland_strategy")
local CombatPower = require(GetScriptDirectory() .. "/THDFuncLib/combat_power")

local bot = GetBot()
local WOLF_UNIT_NAME = "ability_momiji_Spawn_unit"
local AURA_DISTANCE = 900
local MAX_WORK_DISTANCE = 1400
local ATTACK_INTERVAL = 0.45
local MOVE_INTERVAL = 0.65
local LOCATION_BUCKET = 180
local BLOCK_MOVE_INTERVAL = 0.25
local BLOCK_LOCATION_BUCKET = 60
local BLOCK_AHEAD_DISTANCE = 120

local function IsValidUnit(unit)
	return unit ~= nil
		and not unit:IsNull()
		and unit:IsAlive()
		and unit:CanBeSeen()
end

local function IsWolfBusy(wolf)
	return wolf:IsInvulnerable()
		or wolf:IsStunned()
		or wolf:IsNightmared()
		or wolf:IsUsingAbility()
		or wolf:IsCastingAbility()
		or wolf:IsChanneling()
end

local function GetUnitKey(unit)
	if not IsValidUnit(unit) then return "nil" end
	if unit.entindex ~= nil then
		local ok, index = pcall(function() return unit:entindex() end)
		if ok then return tostring(index) end
	end
	return unit:GetUnitName()
end

local function GetEntityIndex(unit)
	if unit ~= nil and unit.entindex ~= nil then
		local ok, index = pcall(function() return unit:entindex() end)
		if ok then return index end
	end
	return math.huge
end

local function GetAllWolves()
	local wolves = {}
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES)) do
		if IsValidUnit(unit) and unit:GetUnitName() == WOLF_UNIT_NAME then
			table.insert(wolves, unit)
		end
	end
	table.sort(wolves, function(a, b) return GetEntityIndex(a) < GetEntityIndex(b) end)
	return wolves
end

local function IsDesignatedBlocker(wolf, target)
	local blocker = nil
	local bestDistance = math.huge
	for _, candidate in pairs(GetAllWolves()) do
		if J.GetHP(candidate) >= 0.35 then
			local distance = target ~= nil
				and GetUnitToUnitDistance(candidate, target)
				or GetEntityIndex(candidate)
			if distance < bestDistance then
				blocker = candidate
				bestDistance = distance
			end
		end
	end
	return blocker == wolf
end

local function HasTalent(name)
	local talent = bot:GetAbilityByName(name)
	return talent ~= nil and talent:GetLevel() > 0
end

local function GetLocationKey(location, bucket)
	bucket = bucket or LOCATION_BUCKET
	local x = math.floor(location.x / bucket + 0.5)
	local y = math.floor(location.y / bucket + 0.5)
	return tostring(x) .. ":" .. tostring(y)
end

local function ShouldThrottle(wolf, actionName, targetKey, interval)
	if wolf.momijiActionState == nil then
		wolf.momijiActionState = {}
	end
	local last = wolf.momijiActionState[actionName]
	local now = DotaTime()
	if last ~= nil and last.key == targetKey and now - last.time < interval then
		return true
	end
	wolf.momijiActionState[actionName] = { key = targetKey, time = now }
	return false
end

local function AttackUnit(wolf, target)
	if not IsValidUnit(target) or not J.CanBeAttacked(target) then return false end
	local isBuilding = target.IsBuilding ~= nil
		and select(2, pcall(function() return target:IsBuilding() end)) == true
	if isBuilding then
		local allowed = Wasteland.CanControlledUnitAttackBuilding(bot, target)
		if not allowed then return false end
	end
	if not ShouldThrottle(wolf, "attack", GetUnitKey(target), ATTACK_INTERVAL) then
		wolf:Action_AttackUnit(target, false)
	end
	return true
end

local function MoveToLocation(wolf, location, actionName, interval, bucket)
	if location == nil then return false end
	actionName = actionName or "move"
	interval = interval or MOVE_INTERVAL
	if not ShouldThrottle(wolf, actionName, GetLocationKey(location, bucket), interval) then
		wolf:Action_MoveToLocation(location)
	end
	return true
end

local function ClampToWorkDistance(location)
	local ownerLocation = bot:GetLocation()
	local offset = location - ownerLocation
	if offset:Length2D() > MAX_WORK_DISTANCE then
		return ownerLocation + offset:Normalized() * MAX_WORK_DISTANCE
	end
	return location
end

local function GetChaseBlockLocation(target)
	local targetLocation = target:GetLocation()
	local predicted = target:GetExtrapolatedLocation(0.65)
	local moveDirection = predicted - targetLocation
	if moveDirection:Length2D() < 10 then
		moveDirection = targetLocation - bot:GetLocation()
	end
	if moveDirection:Length2D() < 10 then
		return targetLocation
	end
	return ClampToWorkDistance(predicted + moveDirection:Normalized() * BLOCK_AHEAD_DISTANCE)
end

local function GetRetreatBlockLocation(chaser)
	local predicted = chaser:GetExtrapolatedLocation(0.25)
	local towardOwner = bot:GetLocation() - predicted
	if towardOwner:Length2D() < 10 then return predicted end
	return predicted + towardOwner:Normalized() * BLOCK_AHEAD_DISTANCE
end

local function MoveToBlockLocation(wolf, location)
	return MoveToLocation(wolf, location, "block", BLOCK_MOVE_INTERVAL, BLOCK_LOCATION_BUCKET)
end

local function GetFormationLocation(wolf)
	local index = 1
	if wolf.entindex ~= nil then
		local ok, result = pcall(function() return wolf:entindex() end)
		if ok then index = result end
	end
	local angle = math.rad(index % 360)
	local distance = 350 + index % 401
	return bot:GetLocation() + Vector(math.cos(angle) * distance, math.sin(angle) * distance, 0)
end

local function IsTargetedByTower(wolf)
	local towers = wolf:GetNearbyTowers(1000, true)
	if towers == nil then return false end
	for _, tower in pairs(towers) do
		if IsValidUnit(tower) and tower:GetAttackTarget() == wolf then
			return true
		end
	end
	return false
end

local function GetRetreatLocation(wolf)
	local ownerNearEnemyTower = false
	if bot:IsAlive() then
		local towers = bot:GetNearbyTowers(900, true)
		ownerNearEnemyTower = towers ~= nil and #towers > 0
	end
	if bot:IsAlive()
	and not J.IsSeriouslyRetreating(bot)
	and not ownerNearEnemyTower
	and GetUnitToUnitDistance(wolf, bot) <= MAX_WORK_DISTANCE
	then
		return GetFormationLocation(wolf)
	end
	return GetTeamFountain()
end

local function GetWeakest(units)
	if units == nil then return nil end
	local weakest = nil
	local lowestHealth = math.huge
	for _, unit in pairs(units) do
		local health = J.Utils.GetVisibleHealth(unit)
		if IsValidUnit(unit) and health ~= nil and J.CanBeAttacked(unit) and health < lowestHealth then
			weakest = unit
			lowestHealth = health
		end
	end
	return weakest
end

local function IsHeroTargetSafe(wolf, target)
	if GetUnitToUnitDistance(bot, target) > MAX_WORK_DISTANCE then return false end
	local targetIsUnderTower = false
	for _, building in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
		if IsValidUnit(building)
		and building:IsTower()
		and GetUnitToUnitDistance(building, target) <= 900
		then
			targetIsUnderTower = true
			break
		end
	end
	if not targetIsUnderTower then return true end
	return GetUnitToUnitDistance(bot, target) <= 900
		and (bot:GetAttackTarget() == target or J.IsInTeamFight(bot, 1200))
		and not IsTargetedByTower(wolf)
end

local function IsValidEnemyHero(target)
	return IsValidUnit(target)
		and target:IsHero()
		and not J.IsSuspiciousIllusion(target)
		and J.CanBeAttacked(target)
end

local function GetBestCombatTarget(wolf)
	local properTarget = J.GetProperTarget(bot)
	local bestTarget = nil
	local bestScore = -math.huge
	local enemies = bot:GetNearbyHeroes(MAX_WORK_DISTANCE, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemies) do
		if IsValidEnemyHero(enemy) and IsHeroTargetSafe(wolf, enemy) then
			local attack = CombatPower.GetAttackSnapshot(enemy)
			local defense = CombatPower.GetDefenseSnapshot(enemy)
			if attack ~= nil and defense ~= nil then
				local hp = defense.maxHealth > 0 and defense.health / defense.maxHealth or 1
				local score = (1 - hp) * 140
				if attack.attackRange >= 400 then score = score + 40 end
				score = score + math.max(0, 2200 - defense.maxHealth) / 45
				score = score + math.min(attack.attackDamage, 300) / 10
				if enemy:IsChanneling() then score = score + 60 end
				if enemy == properTarget then score = score + 20 end
				score = score - GetUnitToUnitDistance(wolf, enemy) / 80
				if score > bestScore then
					bestTarget = enemy
					bestScore = score
				end
			end
		end
	end
	return bestTarget
end

local function GetLaningHarassTarget(wolf)
	if bot:GetActiveMode() ~= BOT_MODE_LANING then return nil end

	local minimumHP = 0.65
	if HasTalent("special_bonus_unique_momiji_2") then
		minimumHP = 0.35
	elseif HasTalent("special_bonus_unique_momiji_1") then
		minimumHP = 0.45
	end
	if J.GetHP(wolf) < minimumHP then return nil end

	local bestTarget = nil
	local bestScore = -math.huge
	local enemies = wolf:GetNearbyHeroes(1000, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemies) do
		if IsValidEnemyHero(enemy)
		and GetUnitToUnitDistance(bot, enemy) <= 1200
		and IsHeroTargetSafe(wolf, enemy)
		then
			local score = (1 - J.GetHP(enemy)) * 100
			if enemy:GetAttackRange() >= 400 then score = score + 30 end
			score = score - GetUnitToUnitDistance(wolf, enemy) / 100
			if score > bestScore then
				bestTarget = enemy
				bestScore = score
			end
		end
	end
	return bestTarget
end

local function GetRetreatChaser()
	local closest = nil
	local closestDistance = math.huge
	local enemies = bot:GetNearbyHeroes(AURA_DISTANCE, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		if IsValidEnemyHero(enemy)
		and (bot:WasRecentlyDamagedByHero(enemy, 2.0) or J.IsChasingTarget(enemy, bot))
		and distance < closestDistance
		then
			closest = enemy
			closestDistance = distance
		end
	end
	return closest
end

local function IsPursuingTarget(target)
	if J.IsChasingTarget(bot, target) then return true end
	if not J.IsGoingOnSomeone(bot) then return false end
	return GetUnitToUnitDistance(bot, target) > bot:GetAttackRange() + 100
		and bot:IsFacingLocation(target:GetLocation(), 40)
		and not target:IsFacingLocation(bot:GetLocation(), 120)
end

local function GetPushBuilding(wolf)
	local barracks = wolf:GetNearbyBarracks(900, true)
	local target = GetWeakest(barracks)
	if target ~= nil then return target end

	local towers = wolf:GetNearbyTowers(900, true)
	target = GetWeakest(towers)
	if target ~= nil then return target end

	local fillers = wolf:GetNearbyFillers(900, true)
	target = GetWeakest(fillers)
	if target ~= nil then return target end

	local ancient = GetAncient(GetOpposingTeam())
	if IsValidUnit(ancient)
	and not ancient:IsInvulnerable()
	and GetUnitToUnitDistance(wolf, ancient) <= 900
	then
		return ancient
	end
	return nil
end

local function MomijiWolfThink(wolf)
	if not IsValidUnit(wolf) or IsWolfBusy(wolf) then return end

	if not bot:IsAlive() then
		MoveToLocation(wolf, GetTeamFountain())
		return
	end

	local ownerDistance = GetUnitToUnitDistance(wolf, bot)
	if ownerDistance > MAX_WORK_DISTANCE then
		MoveToLocation(wolf, GetFormationLocation(wolf))
		return
	end

	local hp = J.GetHP(wolf)
	if hp < 0.25 or IsTargetedByTower(wolf) then
		MoveToLocation(wolf, GetRetreatLocation(wolf))
		return
	end

	if J.IsSeriouslyRetreating(bot) then
		local chaser = GetRetreatChaser()
		if chaser ~= nil and hp >= 0.45 then
			if IsDesignatedBlocker(wolf, chaser) then
				MoveToBlockLocation(wolf, GetRetreatBlockLocation(chaser))
			else
				AttackUnit(wolf, chaser)
			end
			return
		end
		MoveToLocation(wolf, GetRetreatLocation(wolf))
		return
	end

	local target = J.GetProperTarget(bot)
	if IsValidEnemyHero(target)
	and J.IsGoingOnSomeone(bot)
	and IsPursuingTarget(target)
	and IsDesignatedBlocker(wolf, target)
	and GetUnitToUnitDistance(wolf, target) <= 1200
	and IsHeroTargetSafe(wolf, target)
	then
		-- 固定一只狼移动到敌人预测前方卡位，其余狼继续输出。
		MoveToBlockLocation(wolf, GetChaseBlockLocation(target))
		return
	end

	local laningTarget = GetLaningHarassTarget(wolf)
	if laningTarget ~= nil then
		AttackUnit(wolf, laningTarget)
		return
	end

	if J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1400) then
		local combatTarget = GetBestCombatTarget(wolf)
		if combatTarget ~= nil then
			AttackUnit(wolf, combatTarget)
			return
		end
	end

	if IsValidUnit(target) and J.IsRoshan(target) and J.IsDoingRoshan(bot) then
		if GetUnitToUnitDistance(bot, target) <= MAX_WORK_DISTANCE then
			AttackUnit(wolf, target)
			return
		end
	end

	if J.IsPushing(bot) or J.IsDefending(bot) then
		local laneTarget = GetWeakest(wolf:GetNearbyLaneCreeps(900, true))
		if laneTarget ~= nil and GetUnitToUnitDistance(bot, laneTarget) <= MAX_WORK_DISTANCE then
			AttackUnit(wolf, laneTarget)
			return
		end
		if J.IsPushing(bot) then
			local building = GetPushBuilding(wolf)
			if building ~= nil
			and GetUnitToUnitDistance(bot, building) <= MAX_WORK_DISTANCE
			and AttackUnit(wolf, building)
			then
				return
			end
		end
	end

	local mode = bot:GetActiveMode()
	if mode == BOT_MODE_FARM or mode == BOT_MODE_LANING then
		local farmTarget = GetWeakest(wolf:GetNearbyLaneCreeps(800, true))
		if farmTarget == nil and mode == BOT_MODE_FARM then
			farmTarget = GetWeakest(wolf:GetNearbyNeutralCreeps(800))
		end
		if farmTarget ~= nil and GetUnitToUnitDistance(bot, farmTarget) <= MAX_WORK_DISTANCE then
			AttackUnit(wolf, farmTarget)
			return
		end
	end

	-- 无任务时留在恢复与四技能光环范围内。
	if ownerDistance > 750 or ownerDistance < 300 then
		MoveToLocation(wolf, GetFormationLocation(wolf))
	end
end

----------------------------------------------------------------------------------------------------

function MinionThink(hMinionUnit)
	if hMinionUnit ~= nil
	and not hMinionUnit:IsNull()
	and hMinionUnit:GetUnitName() == WOLF_UNIT_NAME
	then
		MomijiWolfThink(hMinionUnit)
		return
	end
	THD2MinionThink(hMinionUnit)
end

----------------------------------------------------------------------------------------------------
