require(GetScriptDirectory() .. "/bot_generic")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local Wasteland = require(GetScriptDirectory() .. "/THDFuncLib/wasteland_strategy")

local bot = GetBot()
local MAX_WORK_DISTANCE = 1400
local ATTACK_INTERVAL = 0.40
local MOVE_INTERVAL = 0.60
local BLOCK_INTERVAL = 0.25
local LOCATION_BUCKET = 160
local BLOCK_LOCATION_BUCKET = 55
local BLOCK_AHEAD_DISTANCE = 120

local function IsValidUnit(unit)
	return unit ~= nil
		and not unit:IsNull()
		and unit:IsAlive()
		and unit:CanBeSeen()
end

local function IsValidEnemyHero(unit)
	return IsValidUnit(unit)
		and unit:IsHero()
		and not J.IsSuspiciousIllusion(unit)
		and J.CanBeAttacked(unit)
end

local function IsIllusionBusy(illusion)
	return illusion:IsInvulnerable()
		or illusion:IsStunned()
		or illusion:IsNightmared()
		or illusion:IsUsingAbility()
		or illusion:IsCastingAbility()
		or illusion:IsChanneling()
end

local function GetEntityIndex(unit)
	if unit ~= nil and unit.entindex ~= nil then
		local ok, index = pcall(function() return unit:entindex() end)
		if ok and index ~= nil then return index end
	end
	return math.huge
end

local function GetPlayerID(unit)
	if unit == nil then return -1 end
	if unit.GetPlayerID ~= nil then
		local ok, id = pcall(function() return unit:GetPlayerID() end)
		if ok and id ~= nil then return id end
	end
	if unit.GetPlayerOwnerID ~= nil then
		local ok, id = pcall(function() return unit:GetPlayerOwnerID() end)
		if ok and id ~= nil then return id end
	end
	return -1
end

local function GetUnitKey(unit)
	if not IsValidUnit(unit) then return "nil" end
	return tostring(GetEntityIndex(unit))
end

local function GetLocationKey(location, bucket)
	bucket = bucket or LOCATION_BUCKET
	local x = math.floor(location.x / bucket + 0.5)
	local y = math.floor(location.y / bucket + 0.5)
	return tostring(x) .. ":" .. tostring(y)
end

local function ShouldThrottle(unit, actionName, key, interval)
	if unit.flandreActionState == nil then unit.flandreActionState = {} end
	local now = DotaTime()
	local last = unit.flandreActionState[actionName]
	if last ~= nil and last.key == key and now - last.time < interval then
		return true
	end
	unit.flandreActionState[actionName] = { key = key, time = now }
	return false
end

local function AttackUnit(illusion, target)
	if not IsValidUnit(target) or not J.CanBeAttacked(target) then return false end
	local isBuilding = target.IsBuilding ~= nil
		and select(2, pcall(function() return target:IsBuilding() end)) == true
	if isBuilding then
		local allowed = Wasteland.CanControlledUnitAttackBuilding(bot, target)
		if not allowed then return false end
	end
	if not ShouldThrottle(illusion, "attack", GetUnitKey(target), ATTACK_INTERVAL) then
		illusion:Action_AttackUnit(target, false)
	end
	return true
end

local function MoveToLocation(illusion, location, actionName, interval, bucket)
	if location == nil then return false end
	actionName = actionName or "move"
	interval = interval or MOVE_INTERVAL
	if not ShouldThrottle(illusion, actionName, GetLocationKey(location, bucket), interval) then
		illusion:Action_MoveToLocation(location)
	end
	return true
end

local function GetOwnedIllusions()
	local illusions = {}
	local playerID = GetPlayerID(bot)
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES)) do
		local unitPlayerID = GetPlayerID(unit)
		if IsValidUnit(unit)
		and unit:IsIllusion()
		and unit:GetUnitName() == bot:GetUnitName()
		and (unitPlayerID == playerID or unitPlayerID < 0 or playerID < 0)
		then
			table.insert(illusions, unit)
		end
	end
	table.sort(illusions, function(a, b) return GetEntityIndex(a) < GetEntityIndex(b) end)
	return illusions
end

local function IsTargetedByTower(illusion)
	local towers = illusion:GetNearbyTowers(1000, true)
	if towers == nil then return false end
	for _, tower in pairs(towers) do
		if IsValidUnit(tower) and tower:GetAttackTarget() == illusion then
			return true
		end
	end
	return false
end

local function IsTargetUnderEnemyTower(illusion, target)
	local towers = illusion:GetNearbyTowers(1600, true)
	if towers == nil then return false end
	for _, tower in pairs(towers) do
		if IsValidUnit(tower) and GetUnitToUnitDistance(tower, target) <= 880 then
			return true
		end
	end
	return false
end

local function IsHeroTargetSafe(illusion, target)
	if not IsValidEnemyHero(target) then return false end
	if GetUnitToUnitDistance(bot, target) > MAX_WORK_DISTANCE then return false end
	if not IsTargetUnderEnemyTower(illusion, target) then return true end
	return GetUnitToUnitDistance(bot, target) <= bot:GetAttackRange() + 250
		and bot:GetAttackTarget() == target
		and not IsTargetedByTower(illusion)
end

local function GetFormationLocation(illusion)
	local index = GetEntityIndex(illusion)
	if index == math.huge then index = 1 end
	local angle = math.rad(index % 360)
	local distance = 350 + index % 351
	return bot:GetLocation() + Vector(math.cos(angle) * distance, math.sin(angle) * distance, 0)
end

local function ClampToWorkDistance(location)
	local offset = location - bot:GetLocation()
	if offset:Length2D() > MAX_WORK_DISTANCE then
		return bot:GetLocation() + offset:Normalized() * MAX_WORK_DISTANCE
	end
	return location
end

local function IsEligibleBlocker(candidate)
	return IsValidUnit(candidate)
		and candidate:IsIllusion()
		and J.GetHP(candidate) >= 0.30
		and not IsIllusionBusy(candidate)
		and not IsTargetedByTower(candidate)
end

local function FindOwnedIllusionByIndex(index)
	for _, candidate in pairs(GetOwnedIllusions()) do
		if GetEntityIndex(candidate) == index then return candidate end
	end
	return nil
end

local function IsDesignatedBlocker(illusion, target, role)
	local targetKey = GetUnitKey(target)
	local state = bot.flandreBlockState
	if state ~= nil
	and state.role == role
	and state.targetKey == targetKey
	then
		local assigned = FindOwnedIllusionByIndex(state.blockerIndex)
		if IsEligibleBlocker(assigned) then
			return assigned == illusion
		end
	end

	local blocker = nil
	local bestDistance = math.huge
	local bestIndex = math.huge
	for _, candidate in pairs(GetOwnedIllusions()) do
		if IsEligibleBlocker(candidate) then
			local distance = GetUnitToUnitDistance(candidate, target)
			local index = GetEntityIndex(candidate)
			if distance < bestDistance - 1
			or (math.abs(distance - bestDistance) <= 1 and index < bestIndex)
			then
				blocker = candidate
				bestDistance = distance
				bestIndex = index
			end
		end
	end
	if blocker ~= nil then
		bot.flandreBlockState = {
			role = role,
			targetKey = targetKey,
			blockerIndex = GetEntityIndex(blocker),
		}
	end
	return blocker == illusion
end

local function GetChaseBlockLocation(target)
	local current = target:GetLocation()
	local predicted = target:GetExtrapolatedLocation(0.60)
	local direction = predicted - current
	if direction:Length2D() < 10 then
		direction = current - bot:GetLocation()
	end
	if direction:Length2D() < 10 then return current end
	return ClampToWorkDistance(predicted + direction:Normalized() * BLOCK_AHEAD_DISTANCE)
end

local function GetRetreatBlockLocation(chaser)
	local predicted = chaser:GetExtrapolatedLocation(0.35)
	local towardOwner = bot:GetLocation() - predicted
	if towardOwner:Length2D() < 10 then return predicted end
	return ClampToWorkDistance(predicted + towardOwner:Normalized() * BLOCK_AHEAD_DISTANCE)
end

local function GetRetreatChaser()
	local closest = nil
	local closestDistance = math.huge
	local enemies = bot:GetNearbyHeroes(1000, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemies) do
		if IsValidEnemyHero(enemy)
		and (bot:WasRecentlyDamagedByHero(enemy, 2.0) or J.IsChasingTarget(enemy, bot))
		then
			local distance = GetUnitToUnitDistance(bot, enemy)
			if distance < closestDistance then
				closest = enemy
				closestDistance = distance
			end
		end
	end
	return closest
end

local function IsPursuingTarget(target)
	if not IsValidEnemyHero(target) then return false end
	if not J.IsGoingOnSomeone(bot) then return false end
	local distance = GetUnitToUnitDistance(bot, target)
	if distance <= bot:GetAttackRange() + 100 then return false end
	if target:IsFacingLocation(bot:GetLocation(), 120) then return false end
	if J.IsChasingTarget(bot, target) then return true end
	return bot:IsFacingLocation(target:GetLocation(), 40)
end

local function GetBestCombatTarget(illusion)
	local properTarget = J.GetProperTarget(bot)
	local bestTarget = nil
	local bestScore = -math.huge
	local enemies = bot:GetNearbyHeroes(MAX_WORK_DISTANCE, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemies) do
		if IsHeroTargetSafe(illusion, enemy) then
			local score = (1 - J.GetHP(enemy)) * 150
			if enemy:GetAttackRange() >= 400 then score = score + 35 end
			score = score + math.max(0, 2200 - enemy:GetMaxHealth()) / 45
			if enemy:IsChanneling() then score = score + 55 end
			if enemy == properTarget then score = score + 75 end
			if score > bestScore
			or (score == bestScore and GetEntityIndex(enemy) < GetEntityIndex(bestTarget))
			then
				bestTarget = enemy
				bestScore = score
			end
		end
	end
	return bestTarget
end

local function GetLaningHarassTarget(illusion)
	if bot:GetActiveMode() ~= BOT_MODE_LANING or J.GetHP(illusion) < 0.25 then return nil end
	local bestTarget = nil
	local bestScore = -math.huge
	local enemies = illusion:GetNearbyHeroes(900, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemies) do
		if IsHeroTargetSafe(illusion, enemy)
		and GetUnitToUnitDistance(bot, enemy) <= 1100
		then
			local score = (1 - J.GetHP(enemy)) * 100
			if enemy:GetAttackRange() >= 400 then score = score + 25 end
			score = score - GetUnitToUnitDistance(illusion, enemy) / 100
			if score > bestScore then
				bestTarget = enemy
				bestScore = score
			end
		end
	end
	return bestTarget
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

local function GetPushBuilding(illusion)
	local target = GetWeakest(illusion:GetNearbyBarracks(900, true))
	if target ~= nil then return target end
	target = GetWeakest(illusion:GetNearbyTowers(900, true))
	if target ~= nil then return target end
	target = GetWeakest(illusion:GetNearbyFillers(900, true))
	if target ~= nil then return target end
	local ancient = GetAncient(GetOpposingTeam())
	if IsValidUnit(ancient)
	and not ancient:IsInvulnerable()
	and GetUnitToUnitDistance(illusion, ancient) <= 900
	then
		return ancient
	end
	return nil
end

local function GetClosestLaneLocation(illusion)
	local lanes = { LANE_TOP, LANE_MID, LANE_BOT }
	local bestLocation = nil
	local bestDistance = math.huge
	for _, lane in pairs(lanes) do
		local location = GetLaneFrontLocation(GetTeam(), lane, 0)
		local distance = GetUnitToLocationDistance(illusion, location)
		if distance < bestDistance then
			bestLocation = location
			bestDistance = distance
		end
	end
	return bestLocation
end

local function FlandreIllusionThink(illusion)
	if not IsValidUnit(illusion) or IsIllusionBusy(illusion) then return end

	-- 四技能施法后由游戏侧负责回收，Bot 不再用移动/攻击命令覆盖它。
	if bot:HasModifier("modifier_thdots_flandre_04_multi") then return end

	if not bot:IsAlive() then
		local laneTarget = GetWeakest(illusion:GetNearbyLaneCreeps(900, true))
		if laneTarget ~= nil then
			AttackUnit(illusion, laneTarget)
		else
			MoveToLocation(illusion, GetClosestLaneLocation(illusion))
		end
		return
	end

	local ownerDistance = GetUnitToUnitDistance(illusion, bot)
	if ownerDistance > MAX_WORK_DISTANCE then
		MoveToLocation(illusion, GetFormationLocation(illusion))
		return
	end

	if IsTargetedByTower(illusion) then
		MoveToLocation(illusion, GetFormationLocation(illusion))
		return
	end

	if J.IsSeriouslyRetreating(bot) then
		local chaser = GetRetreatChaser()
		if chaser ~= nil then
			if J.GetHP(illusion) >= 0.30 and IsDesignatedBlocker(illusion, chaser, "retreat") then
				MoveToLocation(illusion, GetRetreatBlockLocation(chaser), "retreat_block", BLOCK_INTERVAL, BLOCK_LOCATION_BUCKET)
			else
				AttackUnit(illusion, chaser)
			end
		else
			MoveToLocation(illusion, GetFormationLocation(illusion))
		end
		return
	end

	local target = J.GetProperTarget(bot)
	if IsPursuingTarget(target)
	and IsHeroTargetSafe(illusion, target)
	and IsDesignatedBlocker(illusion, target, "chase")
	then
		local blockLocation = GetChaseBlockLocation(target)
		if GetUnitToLocationDistance(illusion, blockLocation) > 90 then
			MoveToLocation(illusion, blockLocation, "chase_block", BLOCK_INTERVAL, BLOCK_LOCATION_BUCKET)
		else
			AttackUnit(illusion, target)
		end
		return
	end

	local laningTarget = GetLaningHarassTarget(illusion)
	if laningTarget ~= nil then
		AttackUnit(illusion, laningTarget)
		return
	end

	if J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1400) then
		local combatTarget = GetBestCombatTarget(illusion)
		if combatTarget ~= nil then
			AttackUnit(illusion, combatTarget)
			return
		end
	end

	if IsValidUnit(target) and J.IsRoshan(target) and J.IsDoingRoshan(bot) then
		AttackUnit(illusion, target)
		return
	end

	if J.IsPushing(bot) or J.IsDefending(bot) then
		local laneTarget = GetWeakest(illusion:GetNearbyLaneCreeps(900, true))
		if laneTarget ~= nil then
			AttackUnit(illusion, laneTarget)
			return
		end
		if J.IsPushing(bot) then
			local building = GetPushBuilding(illusion)
			if building ~= nil and AttackUnit(illusion, building) then
				return
			end
		end
	end

	local mode = bot:GetActiveMode()
	if mode == BOT_MODE_FARM or mode == BOT_MODE_LANING then
		local farmTarget = GetWeakest(illusion:GetNearbyLaneCreeps(800, true))
		if farmTarget == nil and mode == BOT_MODE_FARM then
			farmTarget = GetWeakest(illusion:GetNearbyNeutralCreeps(800))
		end
		if farmTarget ~= nil and GetUnitToUnitDistance(bot, farmTarget) <= MAX_WORK_DISTANCE then
			AttackUnit(illusion, farmTarget)
			return
		end
	end

	if ownerDistance > 700 or ownerDistance < 300 then
		MoveToLocation(illusion, GetFormationLocation(illusion))
	end
end

----------------------------------------------------------------------------------------------------

function MinionThink(hMinionUnit)
	if hMinionUnit ~= nil
	and not hMinionUnit:IsNull()
	and hMinionUnit:IsIllusion()
	and hMinionUnit:GetUnitName() == bot:GetUnitName()
	then
		FlandreIllusionThink(hMinionUnit)
		return
	end
	THD2MinionThink(hMinionUnit)
end

----------------------------------------------------------------------------------------------------
