local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")

local X = {}

local HERO_NAME = "npc_dota_hero_naga_siren"
local ULTIMATE_ABILITY = "ability_thdots_flandre04"
local ULTIMATE_MODIFIER = "modifier_thdots_flandre_04_multi"

local MAX_PURSUE_RANGE = 2000
local LAST_SEEN_CHASE_TIME = 2.0
local NO_TARGET_RELEASE_TIME = 2.0
local REACQUIRE_CHECK_INTERVAL = 0.25
local NEXT_ATTACK_MARGIN = 0.35
local BURN_MIN_WINDOW = 4.0
local BURN_TIME_BUFFER = 1.0
local TOWER_DANGER_RANGE = 900
local ALLY_SUPPORT_RANGE = 900
local LOW_TOWER_DIVE_HP = 0.55
local THINK_INTERVAL = 0.10

local IMMEDIATE_SPECIAL_TARGETS = {
	npc_dota_phoenix_sun = true,
}

local BUILDING_PROTECTION_MODIFIERS = {
	"modifier_backdoor_protection",
	"modifier_backdoor_protection_in_base",
	"modifier_backdoor_protection_active",
}

local function IsNullUnit(unit)
	if unit == nil then return true end
	if unit.IsNull == nil then return false end
	local ok, result = pcall(function() return unit:IsNull() end)
	return ok and result == true
end

local function IsAlive(unit)
	if IsNullUnit(unit) or unit.IsAlive == nil then return false end
	local ok, result = pcall(function() return unit:IsAlive() end)
	return ok and result == true
end

local function CanBeSeen(unit)
	if IsNullUnit(unit) or unit.CanBeSeen == nil then return false end
	local ok, result = pcall(function() return unit:CanBeSeen() end)
	return ok and result == true
end

local function GetEntityIndex(unit)
	if IsNullUnit(unit) or unit.entindex == nil then return math.huge end
	local ok, result = pcall(function() return unit:entindex() end)
	if ok and result ~= nil then return result end
	return math.huge
end

local function GetUnitKey(unit)
	return tostring(GetEntityIndex(unit))
end

local function GetSafeUnitList(listType)
	local ok, units = pcall(function() return GetUnitList(listType) end)
	if ok and units ~= nil then return units end
	return {}
end

local function GetState(bot)
	if bot.flandreUltimateState == nil then
		bot.flandreUltimateState = {
			phase = "idle",
			remainingAttacks = 0,
			remainingDuration = 0,
			controlReleased = false,
			noTargetSince = nil,
			lastReacquireCheckTime = -90,
			lastOrderTime = -90,
			lastThinkTime = -90,
		}
	end
	return bot.flandreUltimateState
end

local function ResetState(bot)
	bot.flandreUltimateState = {
		phase = "idle",
		remainingAttacks = 0,
		remainingDuration = 0,
		controlReleased = false,
		noTargetSince = nil,
		lastReacquireCheckTime = -90,
		lastOrderTime = -90,
		lastThinkTime = -90,
	}
	return bot.flandreUltimateState
end

local function GetModifierState(bot)
	if bot.GetModifierByName == nil then return -1, 0, 0 end
	local ok, index = pcall(function() return bot:GetModifierByName(ULTIMATE_MODIFIER) end)
	if not ok or index == nil or index < 0 then return -1, 0, 0 end

	local stack = 0
	local duration = 0
	local stackOk, stackResult = pcall(function() return bot:GetModifierStackCount(index) end)
	if stackOk and stackResult ~= nil then stack = math.max(stackResult, 0) end
	local durationOk, durationResult = pcall(function() return bot:GetModifierRemainingDuration(index) end)
	if durationOk and durationResult ~= nil then duration = math.max(durationResult, 0) end
	return index, stack, duration
end

local function IsHighPriorityRetreat(bot)
	return J.Retreat ~= nil
		and J.Retreat.ShouldYield ~= nil
		and J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
end

local function HasModifier(unit, modifierName)
	if IsNullUnit(unit) or unit.HasModifier == nil then return false end
	local ok, result = pcall(function() return unit:HasModifier(modifierName) end)
	return ok and result == true
end

local function IsFountainProtected(unit)
	return HasModifier(unit, "modifier_fountain_aura_buff")
		or HasModifier(unit, "modifier_fountain_invulnerability")
end

local function IsBuildingProtected(unit)
	if not unit:IsBuilding() then return false end
	for _, modifierName in pairs(BUILDING_PROTECTION_MODIFIERS) do
		if HasModifier(unit, modifierName) then return true end
	end
	return false
end

local function IsAttackable(bot, unit)
	if not IsAlive(unit) or not CanBeSeen(unit) then return false end
	if unit:GetTeam() == bot:GetTeam() then return false end
	if not J.CanBeAttacked(unit) or IsFountainProtected(unit) then return false end
	if unit:IsBuilding() and IsBuildingProtected(unit) then return false end
	return true
end

local function IsWardLike(unit)
	local name = string.lower(unit:GetUnitName() or "")
	return string.find(name, "ward") ~= nil
		or string.find(name, "observer") ~= nil
		or string.find(name, "sentry") ~= nil
end

local function IsValidHeroTarget(bot, unit)
	return IsAttackable(bot, unit)
		and unit:IsHero()
		and not J.IsSuspiciousIllusion(unit)
end

local function GetTravelTime(bot, target)
	local distance = GetUnitToUnitDistance(bot, target)
	local travelDistance = math.max(0, distance - bot:GetAttackRange())
	local speed = math.max(1, bot:GetCurrentMovementSpeed())
	return travelDistance / speed
end

local function CanReachNextAttack(bot, state, target)
	local distance = GetUnitToUnitDistance(bot, target)
	if distance > MAX_PURSUE_RANGE then return false end
	local attackPoint = math.max(0, bot:GetAttackPoint())
	return GetTravelTime(bot, target) + attackPoint
		<= math.max(0, state.remainingDuration - NEXT_ATTACK_MARGIN)
end

local function IsUnderEnemyTower(bot, target)
	for _, building in pairs(GetSafeUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
		if IsAlive(building)
		and building.IsTower ~= nil
		and building:IsTower()
		and GetUnitToUnitDistance(building, target) <= TOWER_DANGER_RANGE
		then
			return true
		end
	end
	return false
end

local function HasAlliedSupport(bot, target)
	for _, ally in pairs(GetSafeUnitList(UNIT_LIST_ALLIED_HEROES)) do
		if ally ~= bot
		and IsAlive(ally)
		and not ally:IsIllusion()
		and GetUnitToUnitDistance(ally, target) <= ALLY_SUPPORT_RANGE
		then
			return true
		end
	end
	return false
end

local function CanKillWithUltimateAttack(bot, target)
	local ability = bot:GetAbilityByName(ULTIMATE_ABILITY)
	if ability == nil then return false end
	local ok, multiplier = pcall(function() return ability:GetSpecialValueInt("damage_multi") end)
	if not ok or multiplier == nil or multiplier <= 0 then return false end
	return J.CanKillTarget(target, bot:GetAttackDamage() * multiplier / 100, DAMAGE_TYPE_PHYSICAL)
end

local function IsSafeHeroPursuit(bot, target)
	if not IsUnderEnemyTower(bot, target) or J.GetHP(bot) >= LOW_TOWER_DIVE_HP then return true end
	return HasAlliedSupport(bot, target) or CanKillWithUltimateAttack(bot, target)
end

local function IsPursuable(bot, state, target)
	if not IsAttackable(bot, target) or not CanReachNextAttack(bot, state, target) then return false end
	if target:IsHero() and not IsSafeHeroPursuit(bot, target) then return false end
	return true
end

local function IsTeleporting(target)
	return HasModifier(target, "modifier_teleporting")
		or HasModifier(target, "modifier_teleporting_root_logic")
end

local function RememberTarget(state, target)
	if IsNullUnit(target) or not CanBeSeen(target) then return end
	state.lastKnownTargetLocation = target:GetLocation()
	state.lastTargetSeenTime = DotaTime()
end

local function IsPreferredTarget(state, properTarget, target)
	return target == state.preferredTarget or target == properTarget
end

local function IsBetterHero(bot, state, properTarget, candidate, best)
	if best == nil then return true end
	local candidateKill = CanKillWithUltimateAttack(bot, candidate)
	local bestKill = CanKillWithUltimateAttack(bot, best)
	if candidateKill ~= bestKill then return candidateKill end

	local candidateControl = candidate:IsChanneling() or IsTeleporting(candidate)
	local bestControl = best:IsChanneling() or IsTeleporting(best)
	if candidateControl ~= bestControl then return candidateControl end

	local candidatePreferred = IsPreferredTarget(state, properTarget, candidate)
	local bestPreferred = IsPreferredTarget(state, properTarget, best)
	if candidatePreferred ~= bestPreferred then return candidatePreferred end

	local candidateHP = candidate:GetHealth()
	local bestHP = best:GetHealth()
	if candidateHP ~= bestHP then return candidateHP < bestHP end

	local candidateDistance = GetUnitToUnitDistance(bot, candidate)
	local bestDistance = GetUnitToUnitDistance(bot, best)
	if candidateDistance ~= bestDistance then return candidateDistance < bestDistance end
	return GetEntityIndex(candidate) < GetEntityIndex(best)
end

local function FindBestHero(bot, state)
	local best = nil
	local properTarget = J.GetProperTarget(bot)
	for _, enemy in pairs(GetSafeUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if IsValidHeroTarget(bot, enemy)
		and CanReachNextAttack(bot, state, enemy)
		and IsSafeHeroPursuit(bot, enemy)
		and IsBetterHero(bot, state, properTarget, enemy, best)
		then
			best = enemy
		end
	end
	return best
end

local function AddUniqueUnit(units, seen, unit)
	if IsNullUnit(unit) then return end
	local key = GetUnitKey(unit)
	if not seen[key] then
		seen[key] = true
		table.insert(units, unit)
	end
end

local function CollectUnits(listTypes)
	local units = {}
	local seen = {}
	for _, listType in pairs(listTypes) do
		for _, unit in pairs(GetSafeUnitList(listType)) do
			AddUniqueUnit(units, seen, unit)
		end
	end
	return units
end

local function FindImmediateSpecialTarget(bot, state)
	local best = nil
	for _, unit in pairs(CollectUnits({UNIT_LIST_ENEMIES, UNIT_LIST_ENEMY_CREEPS})) do
		if IMMEDIATE_SPECIAL_TARGETS[unit:GetUnitName()]
		and IsPursuable(bot, state, unit)
		and (best == nil or GetUnitToUnitDistance(bot, unit) < GetUnitToUnitDistance(bot, best))
		then
			best = unit
		end
	end
	return best
end

local function IsPushMode(mode)
	return mode == BOT_MODE_PUSH_TOWER_TOP
		or mode == BOT_MODE_PUSH_TOWER_MID
		or mode == BOT_MODE_PUSH_TOWER_BOT
end

local function GetBuildingPriority(unit)
	if unit == GetAncient(GetOpposingTeam()) then return 3 end
	local name = string.lower(unit:GetUnitName() or "")
	if string.find(name, "barracks") ~= nil then return 2 end
	if unit.IsTower ~= nil and unit:IsTower() then return 1 end
	return 0
end

local function IsBetterBuilding(bot, candidate, best)
	if best == nil then return true end
	local candidatePriority = GetBuildingPriority(candidate)
	local bestPriority = GetBuildingPriority(best)
	if candidatePriority ~= bestPriority then return candidatePriority > bestPriority end
	if candidate:GetHealth() ~= best:GetHealth() then return candidate:GetHealth() > best:GetHealth() end
	return GetUnitToUnitDistance(bot, candidate) < GetUnitToUnitDistance(bot, best)
end

local function FindBestBuilding(bot, state, requirePushContext)
	if requirePushContext and not IsPushMode(state.castMode) and state.castReason ~= "push" then return nil end
	local best = nil
	for _, building in pairs(GetSafeUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
		if IsPursuable(bot, state, building) and IsBetterBuilding(bot, building, best) then
			best = building
		end
	end
	return best
end

local function IsRoshanContext(bot, state)
	return state.castMode == BOT_MODE_ROSHAN
		or J.IsRoshan(state.preferredTarget)
		or J.IsRoshan(bot:GetAttackTarget())
end

local function FindRoshan(bot, state)
	if not IsRoshanContext(bot, state) then return nil end
	for _, unit in pairs(GetSafeUnitList(UNIT_LIST_NEUTRAL_CREEPS)) do
		if J.IsRoshan(unit) and IsPursuable(bot, state, unit) then return unit end
	end
	return nil
end

local function GetFallbackPriority(unit)
	if unit:IsBuilding() then return 4 end
	if unit.IsAncientCreep ~= nil and unit:IsAncientCreep() then return 3 end
	if unit:GetTeam() == TEAM_NEUTRAL then return 2 end
	return 1
end

local function IsFallbackTarget(bot, state, unit)
	return IsPursuable(bot, state, unit)
		and not unit:IsHero()
		and not J.IsRoshan(unit)
		and not IsWardLike(unit)
end

local function IsBetterFallback(bot, candidate, best)
	if best == nil then return true end
	local candidatePriority = GetFallbackPriority(candidate)
	local bestPriority = GetFallbackPriority(best)
	if candidatePriority ~= bestPriority then return candidatePriority > bestPriority end
	if candidate:GetHealth() ~= best:GetHealth() then return candidate:GetHealth() > best:GetHealth() end
	local candidateDistance = GetUnitToUnitDistance(bot, candidate)
	local bestDistance = GetUnitToUnitDistance(bot, best)
	if candidateDistance ~= bestDistance then return candidateDistance < bestDistance end
	return GetEntityIndex(candidate) < GetEntityIndex(best)
end

local function FindBestFallback(bot, state)
	local best = nil
	local units = CollectUnits({
		UNIT_LIST_ENEMY_BUILDINGS,
		UNIT_LIST_ENEMY_CREEPS,
		UNIT_LIST_NEUTRAL_CREEPS,
		UNIT_LIST_ENEMIES,
	})
	for _, unit in pairs(units) do
		if IsFallbackTarget(bot, state, unit) and IsBetterFallback(bot, unit, best) then
			best = unit
		end
	end
	return best
end

local function IsBurnPhase(bot, state, fallback)
	local attackPoint = math.max(0, bot:GetAttackPoint())
	local attackPeriod = math.max(0.1, bot:GetSecondsPerAttack())
	local travelTime = fallback ~= nil and GetTravelTime(bot, fallback) or 0
	local finishTime = attackPoint
		+ math.max(0, state.remainingAttacks - 1) * attackPeriod
		+ travelTime
		+ BURN_TIME_BUFFER
	return state.remainingDuration <= math.max(BURN_MIN_WINDOW, finishTime)
end

local function SelectTarget(bot, state)
	if not IsNullUnit(state.lockedTarget) then
		RememberTarget(state, state.lockedTarget)
		if IsPursuable(bot, state, state.lockedTarget) then return state.lockedTarget end
		state.lockedTarget = nil
	end

	local target = FindImmediateSpecialTarget(bot, state)
	if target ~= nil then return target end
	target = FindBestHero(bot, state)
	if target ~= nil then return target end
	target = FindRoshan(bot, state)
	if target ~= nil then return target end
	target = FindBestBuilding(bot, state, true)
	if target ~= nil then return target end

	local fallback = FindBestFallback(bot, state)
	if fallback ~= nil and IsBurnPhase(bot, state, fallback) then return fallback end
	return nil
end

local function TryReacquireControl(bot, state)
	if not state.controlReleased or state.remainingAttacks <= 0 then return not state.controlReleased end
	local now = DotaTime()
	if now - (state.lastReacquireCheckTime or -90) < REACQUIRE_CHECK_INTERVAL then return false end
	state.lastReacquireCheckTime = now

	local target = SelectTarget(bot, state)
	if target == nil then return false end
	-- 仅在剩余时间仍可完成下一击时恢复控制；SelectTarget 已完成距离、塔下和可达性检查。
	state.controlReleased = false
	state.noTargetSince = nil
	state.lockedTarget = target
	state.lastThinkTime = -90
	RememberTarget(state, target)
	return true
end

function X.BeginCast(bot, ability, target, reason, expectedCount)
	local now = DotaTime()
	bot.flandreUltimateState = {
		phase = "pending",
		pendingUntil = now + 1.0,
		remainingAttacks = math.max(expectedCount or 1, 1),
		initialAttacks = math.max(expectedCount or 1, 1),
		remainingDuration = 0,
		controlReleased = false,
		noTargetSince = nil,
		lastReacquireCheckTime = -90,
		castReason = reason or "unknown",
		castMode = bot:GetActiveMode(),
		preferredTarget = target,
		lockedTarget = target,
		lastStackCount = nil,
		lastStackChangeTime = now,
		lastOrderTime = -90,
		lastThinkTime = -90,
	}
	RememberTarget(bot.flandreUltimateState, target)
end

function X.Update(bot)
	local state = GetState(bot)
	if bot:GetUnitName() ~= HERO_NAME or not bot:IsAlive() then return ResetState(bot) end

	local modifierIndex, stack, duration = GetModifierState(bot)
	if modifierIndex >= 0 then
		if state.phase ~= "active" then
			state.phase = "active"
			state.activationTime = DotaTime()
			state.lastStackChangeTime = DotaTime()
		end
		state.remainingDuration = duration
		if stack > 0 then
			if state.lastStackCount ~= nil and stack < state.lastStackCount then
				state.lastStackChangeTime = DotaTime()
				state.lockedTarget = nil
			end
			state.remainingAttacks = stack
			state.initialAttacks = math.max(state.initialAttacks or stack, stack)
			state.lastStackCount = stack
		end
		return state
	end

	if state.phase == "pending" and DotaTime() <= (state.pendingUntil or -90) then return state end
	if state.phase ~= "idle" then return ResetState(bot) end
	return state
end

function X.IsActive(bot)
	local state = X.Update(bot)
	return state.phase == "active" and state.remainingAttacks > 0
end

function X.GetLockedTarget(bot)
	local state = X.Update(bot)
	if state.phase ~= "active" then return nil end
	return state.lockedTarget
end

function X.GetModeDesire(bot)
	if bot:GetUnitName() ~= HERO_NAME then return BOT_MODE_DESIRE_NONE end
	local state = X.Update(bot)
	if state.phase ~= "active"
	or state.remainingAttacks <= 0
	or IsHighPriorityRetreat(bot)
	then
		return BOT_MODE_DESIRE_NONE
	end
	if state.controlReleased and not TryReacquireControl(bot, state) then
		return BOT_MODE_DESIRE_NONE
	end
	return BOT_MODE_DESIRE_ABSOLUTE
end

function X.Think(bot)
	if bot:GetUnitName() ~= HERO_NAME then return false end
	local state = X.Update(bot)
	if state.phase ~= "active" or state.remainingAttacks <= 0 then return false end
	if IsHighPriorityRetreat(bot) then return false end
	if state.controlReleased and not TryReacquireControl(bot, state) then return false end
	if J.CanNotUseAction(bot) then return true end

	local now = DotaTime()
	if now - (state.lastThinkTime or -90) < THINK_INTERVAL then return true end
	state.lastThinkTime = now

	local target = SelectTarget(bot, state)
	if target ~= nil then
		state.noTargetSince = nil
		state.lockedTarget = target
		RememberTarget(state, target)
		J.SetTargetIfChanged(bot, target, 0.15)
		J.ActionAttackUnit(bot, "flandre_ultimate_attack", target, false, 0.25)
		state.lastOrderTime = now
		return true
	end

	if state.noTargetSince == nil then state.noTargetSince = now end
	if now - state.noTargetSince >= NO_TARGET_RELEASE_TIME then
		-- 连续一段时间没有任何有效目标后暂时让权；目标重新出现且仍可完成攻击时允许恢复。
		state.controlReleased = true
		state.lockedTarget = nil
		state.lastReacquireCheckTime = now
		return false
	end

	if state.lastKnownTargetLocation ~= nil
	and now - (state.lastTargetSeenTime or -90) <= LAST_SEEN_CHASE_TIME
	and GetUnitToLocationDistance(bot, state.lastKnownTargetLocation) <= MAX_PURSUE_RANGE
	then
		J.ActionMoveToLocation(bot, "flandre_ultimate_last_seen", state.lastKnownTargetLocation, 0.25, 80)
		state.lastOrderTime = now
		return true
	end

	-- 宽限期内只打断旧的低价值攻击；超时后由上面的让权分支结束直接控制。
	if bot:GetAttackTarget() ~= nil then
		J.ActionMoveToLocation(bot, "flandre_ultimate_hold", bot:GetLocation(), 0.35, 40)
		state.lastOrderTime = now
	end
	return true
end

return X
