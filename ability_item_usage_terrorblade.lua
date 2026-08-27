require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local CombatPower = require(GetScriptDirectory() .. "/THDFuncLib/combat_power")

local CHEN01 = "ability_thdots_chen01"
local CHEN02 = "ability_thdots_chen02"
local CHEN03 = "ability_thdots_chen03"
local CHEN04 = "ability_thdots_chen04"
local CHEN_WANBAO = "ability_thdots_chen_wanbaochui"

local ROLLING_MODIFIER = "modifier_ability_thdots_chen01"
local CHEN_EX_MODIFIER = "modifier_ability_thdots_chenEx"
local ULTIMATE_MODIFIER = "modifier_ability_thdots_chen04"
local WANBAO_MODIFIER = "modifier_item_wanbaochui"
local HORSE_KING_MODIFIER = "modifier_item_horse_king_open"
local DRAGON_STAR_MODIFIER = "modifier_item_dragon_star_buff"
local TRINITY_MODIFIER = "modifier_item_trinity_active_shield"

local COMBO_WINDOW = 8.0
local ACTION_GUARD_TIME = 0.05
local HERO_SCAN_RANGE = 1200
local DRAGON_STAR_ENGAGE_RANGE = 1000
local DRAGON_STAR_REACTIVE_HP = 0.75
local CHEN03_COMBAT_RADIUS = 500
local FARM_RESERVE_RANGE = 1000
local ROLL_PREDICTION_TIME = 0.35
local ROLL_RETRY_TIME = 0.35
local TOWER_SCAN_RANGE = 1600
local TOWER_RANGE_FALLBACK = 900
local TOWER_ROLL_BUFFER = 80
local TOWER_DIVE_MIN_HP = 0.80
local TOWER_DIVE_MAX_TARGET_HP = 0.45
local TOWER_DIVE_MIN_HP_ADVANTAGE = 0.30
local TOWER_DIVE_KILL_WINDOW = 2.25
local TOWER_DIVE_DAMAGE_MARGIN = 1.05

local function SafeCall(object, methodName, fallback, ...)
	if object == nil or object[methodName] == nil then return fallback end
	local args = {...}
	local ok, value = pcall(function() return object[methodName](object, unpack(args)) end)
	if ok and value ~= nil then return value end
	return fallback
end

local function GetHP(unit)
	local maximum = SafeCall(unit, "GetMaxHealth", 1)
	return maximum > 0 and SafeCall(unit, "GetHealth", 0) / maximum or 0
end

local function GetMP(unit)
	local maximum = SafeCall(unit, "GetMaxMana", 1)
	return maximum > 0 and SafeCall(unit, "GetMana", 0) / maximum or 0
end

local function GetAbility(bot, name)
	local ability = bot:GetAbilityByName(name)
	if ability == nil or SafeCall(ability, "IsNull", false) then return nil end
	if ability.IsTrained ~= nil and not ability:IsTrained() then return nil end
	return ability
end

local function IsCastable(ability)
	return ability ~= nil and SafeCall(ability, "IsFullyCastable", false)
end

local function IsAbilityOnCooldown(ability)
	return ability ~= nil and SafeCall(ability, "GetCooldownTimeRemaining", 0) > 0.05
end

local function IsValidVisibleEnemyUnit(bot, target)
	if target == nil or SafeCall(target, "IsNull", false) then return false end
	if not SafeCall(target, "IsAlive", false) or not SafeCall(target, "CanBeSeen", false) then return false end
	if SafeCall(target, "GetTeam", bot:GetTeam()) == bot:GetTeam() then return false end
	return not SafeCall(target, "IsInvulnerable", false)
end

local function IsValidEnemyHero(bot, target)
	return IsValidVisibleEnemyUnit(bot, target)
		and SafeCall(target, "IsHero", false)
		and not J.IsSuspiciousIllusion(target)
end

local function CanTargetWithChen02(bot, target)
	return IsValidEnemyHero(bot, target) and not SafeCall(target, "IsMagicImmune", false)
end

local function GetVisibleEnemyHeroes(bot, range)
	local result = {}
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, math.min(range, 1600), true, BOT_MODE_NONE)) do
		if IsValidEnemyHero(bot, enemy) and GetUnitToUnitDistance(bot, enemy) <= range then
			table.insert(result, enemy)
		end
	end
	return result
end

local function IsTeleportingSafely(target)
	if IsTeleporting ~= nil then
		local ok, result = pcall(function() return IsTeleporting(target) end)
		if ok and result then return true end
	end
	return SafeCall(target, "HasModifier", false, "modifier_teleporting")
		or SafeCall(target, "HasModifier", false, "modifier_teleporting_root_logic")
end

local function MarkAction(bot)
	bot.thdOrangeLastActionTime = DotaTime()
end

local function WasActionJustIssued(bot)
	return DotaTime() - (bot.thdOrangeLastActionTime or -90) <= ACTION_GUARD_TIME
end

local function UseAbility(bot, ability)
	bot:Action_UseAbility(ability)
	MarkAction(bot)
	return true
end

local function UseAbilityOnEntity(bot, ability, target)
	bot:Action_UseAbilityOnEntity(ability, target)
	MarkAction(bot)
	return true
end

local function UseAbilityOnLocation(bot, ability, location)
	bot:Action_UseAbilityOnLocation(ability, location)
	MarkAction(bot)
	return true
end

local function GetReadyItem(name)
	local item = IsItemAvailable(name)
	if item == nil or not SafeCall(item, "IsFullyCastable", false) then return nil end
	return item
end

local function ScoreDelayedControlTarget(isProperTarget, isChanneling, isTeleporting, distance, healthPercent)
	local score = isProperTarget and 100 or 0
	-- 二技能三秒后才控制；持续施法和传送只增加选取权重，不建立即时打断入口。
	if isChanneling or isTeleporting then score = score + 20 end
	score = score + math.max(0, 20 - distance / 60)
	score = score + math.max(0, 1 - healthPercent) * 15
	return score
end

local GetPredictedRollLocation
local CanUseChaseRoll

local function FindCombatTarget(bot, enemies, ability01, ability02, towerContext)
	if not J.IsGoingOnSomeone(bot) and not J.IsInTeamFight(bot, HERO_SCAN_RANGE) then return nil end
	local properTarget = J.GetProperTarget(bot)
	local bestTarget = nil
	local bestScore = -math.huge
	local inTeamFight = J.IsInTeamFight(bot, HERO_SCAN_RANGE)
	local rollRange = SafeCall(ability01, "GetCastRange", 600)
	if rollRange <= 0 then rollRange = SafeCall(ability01, "GetSpecialValueInt", 600, "cast_range") end
	local reachableRange = math.max(rollRange, 600) + CHEN03_COMBAT_RADIUS
	for _, enemy in pairs(enemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		if inTeamFight or distance <= reachableRange then
			local approachRange = math.max(
				SafeCall(bot, "GetAttackRange", 150) + 125,
				ability02 ~= nil and SafeCall(ability02, "GetCastRange", 400) + 25 or 425
			)
			local needsInitialRoll = distance > approachRange and IsCastable(ability01)
			local rollAllowed = not needsInitialRoll
				or CanUseChaseRoll(bot, enemy, enemies, GetPredictedRollLocation(bot, enemy, ability01), towerContext)
			if rollAllowed then
				local score = ScoreDelayedControlTarget(
					enemy == properTarget,
					SafeCall(enemy, "IsChanneling", false),
					IsTeleportingSafely(enemy),
					distance,
					GetHP(enemy)
				)
				if score > bestScore then
					bestTarget = enemy
					bestScore = score
				end
			end
		end
	end
	return bestTarget
end

local function ClearCombo(bot)
	bot.thdOrangeCombo = nil
end

local function StartCombo(bot, target)
	bot.thdOrangeCombo = {
		target = target,
		expiresAt = DotaTime() + COMBO_WINDOW,
		ultimateIssued = false,
		rollCount = 0,
		lastRollAt = -90,
		chen02Issued = false,
		chen03Issued = false,
		teethIssued = false,
	}
	return bot.thdOrangeCombo
end

local function GetValidCombo(bot)
	local state = bot.thdOrangeCombo
	if state == nil or DotaTime() > (state.expiresAt or -1) or not IsValidEnemyHero(bot, state.target) then
		ClearCombo(bot)
		return nil
	end
	return state
end

local function ProjectLocation(from, toward, distance)
	local dx = toward.x - from.x
	local dy = toward.y - from.y
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 0.01 then return from end
	local scale = math.min(distance, length) / length
	return Vector(from.x + dx * scale, from.y + dy * scale, from.z or 0)
end

local function GetRollRange(ability)
	local castRange = SafeCall(ability, "GetCastRange", 0)
	if castRange <= 0 then castRange = SafeCall(ability, "GetSpecialValueInt", 600, "cast_range") end
	if castRange <= 0 then castRange = 600 end
	return castRange
end

GetPredictedRollLocation = function(bot, target, ability)
	local targetLocation = SafeCall(target, "GetExtrapolatedLocation", target:GetLocation(), ROLL_PREDICTION_TIME)
	return ProjectLocation(bot:GetLocation(), targetLocation, GetRollRange(ability))
end

local function GetLocationDistance(first, second)
	local dx = first.x - second.x
	local dy = first.y - second.y
	return math.sqrt(dx * dx + dy * dy)
end

local function IsValidTower(tower)
	if tower == nil or SafeCall(tower, "IsNull", false) or not SafeCall(tower, "IsAlive", false) then
		return false
	end
	return true
end

local function IsHighGroundTower(tower)
	local name = SafeCall(tower, "GetUnitName", "")
	return string.find(name, "tower3", 1, true) ~= nil
		or string.find(name, "tower4", 1, true) ~= nil
end

local function LoadTowerContext(bot, context)
	if context.loaded then return end
	context.loaded = true
	context.towers = {}
	context.hasUnknownTower = false
	for _, tower in pairs(SafeCall(bot, "GetNearbyTowers", {}, TOWER_SCAN_RANGE, true)) do
		if IsValidTower(tower) and SafeCall(tower, "CanBeSeen", false) then
			table.insert(context.towers, tower)
		elseif IsValidTower(tower) then
			-- 无法读取位置的塔不能安全计算滚动落点，越塔判断按未知风险失败关闭。
			context.hasUnknownTower = true
		end
	end
end

local function GetRollTowerRisk(bot, location, context)
	LoadTowerContext(bot, context)
	local towerCount = 0
	local highGround = false
	for _, tower in pairs(context.towers) do
		local towerLocation = SafeCall(tower, "GetLocation", nil)
		if towerLocation ~= nil then
			local attackRange = SafeCall(tower, "GetAttackRange", TOWER_RANGE_FALLBACK)
			if GetLocationDistance(location, towerLocation) <= attackRange + TOWER_ROLL_BUFFER then
				towerCount = towerCount + 1
				highGround = highGround or IsHighGroundTower(tower)
			end
		end
	end
	return towerCount, highGround, context.hasUnknownTower
end

local function ShouldAllowTowerDive(botHP, targetHP, enemyCount, towerCount, highGround,
	unknownTower, hasNativeReduction, recentlyDamagedByTower, estimatedDamage, targetHealth)
	return towerCount == 1
		and not highGround
		and not unknownTower
		and hasNativeReduction
		and not recentlyDamagedByTower
		and enemyCount <= 1
		and botHP >= TOWER_DIVE_MIN_HP
		and targetHP <= TOWER_DIVE_MAX_TARGET_HP
		and botHP - targetHP >= TOWER_DIVE_MIN_HP_ADVANTAGE
		and estimatedDamage >= targetHealth * TOWER_DIVE_DAMAGE_MARGIN
end

CanUseChaseRoll = function(bot, target, enemies, location, towerContext)
	local towerCount, highGround, unknownTower = GetRollTowerRisk(bot, location, towerContext)
	if towerCount == 0 and not unknownTower then return true end
	local targetHealth = SafeCall(target, "GetHealth", math.huge)
	local estimatedDamage = CombatPower.EstimateAttackDamage(
		bot,
		target,
		TOWER_DIVE_KILL_WINDOW,
		1,
		0
	)
	return ShouldAllowTowerDive(
		GetHP(bot),
		GetHP(target),
		#enemies,
		towerCount,
		highGround,
		unknownTower,
		bot:HasModifier(CHEN_EX_MODIFIER),
		SafeCall(bot, "WasRecentlyDamagedByTower", false, 1.25),
		estimatedDamage,
		targetHealth
	)
end

local function GetChaseApproachRange(bot, state, ability02)
	local attackRange = SafeCall(bot, "GetAttackRange", 150) + 125
	local chen02Range = 0
	if not state.chen02Issued and IsCastable(ability02) then
		chen02Range = SafeCall(ability02, "GetCastRange", 400) + 25
	end
	return math.max(attackRange, chen02Range)
end

local function ShouldUseChaseRoll(distance, approachRange, rollReady, rollCount, isChasing, sinceLastRoll)
	if not rollReady or distance <= approachRange or sinceLastRoll < ROLL_RETRY_TIME then return false end
	-- 第一次用于接敌；后续短 CD 滚动只追真正背身逃跑的目标，避免原地反复冲撞。
	return rollCount == 0 or isChasing
end

local function GetSafeRollLocation(bot, ability, pursuer)
	local fountain = J.GetTeamFountain ~= nil and J.GetTeamFountain()
		or GetShopLocation(bot:GetTeam(), SHOP_HOME)
	if fountain ~= nil then
		return ProjectLocation(bot:GetLocation(), fountain, GetRollRange(ability))
	end
	if pursuer ~= nil then
		local botLocation = bot:GetLocation()
		local enemyLocation = pursuer:GetLocation()
		local away = Vector(botLocation.x * 2 - enemyLocation.x, botLocation.y * 2 - enemyLocation.y, botLocation.z or 0)
		return ProjectLocation(botLocation, away, GetRollRange(ability))
	end
	return bot:GetLocation()
end

local function ShouldUseChen03Combat(heroCount, hasCommittedTarget, hasRetreatPursuer)
	return heroCount >= 2 or hasCommittedTarget or hasRetreatPursuer
end

local function ShouldUseChen03Farm(laneCreepCount, neutralCreepCount, manaPercent, visibleEnemyCount)
	return manaPercent >= 0.55
		and visibleEnemyCount == 0
		and (laneCreepCount >= 4 or neutralCreepCount >= 3)
end

local function ShouldUseWanbao(validHeroContext, cooldownCount)
	return validHeroContext and cooldownCount >= 2
end

local function ShouldUseTeeth(ultimateActive, targetInAttackRange, chen02Settled, chen03Settled)
	return ultimateActive and targetInAttackRange and chen02Settled and chen03Settled
end

local function CountSkillCooldowns(ability01, ability02, ability03)
	local count = 0
	for _, ability in pairs({ability01, ability02, ability03}) do
		if IsAbilityOnCooldown(ability) then count = count + 1 end
	end
	return count
end

local function CountEnemiesWithin(bot, enemies, range)
	local count = 0
	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= range then count = count + 1 end
	end
	return count
end

local function GetClosestEnemyDistance(bot, enemies)
	local closestDistance = math.huge
	for _, enemy in pairs(enemies) do
		closestDistance = math.min(closestDistance, GetUnitToUnitDistance(bot, enemy))
	end
	return closestDistance
end

local function ShouldUseDragonStar(enemyCount, closestDistance, seriousRetreat,
	recentlyDamaged, hp, committed)
	if enemyCount <= 0 then return false end
	if seriousRetreat then return true end
	if recentlyDamaged and hp <= DRAGON_STAR_REACTIVE_HP then return true end
	return committed and closestDistance <= DRAGON_STAR_ENGAGE_RANGE
end

local function TryUseDragonStar(bot, enemies, committed, seriousRetreat)
	if bot:HasModifier(DRAGON_STAR_MODIFIER) then return false end
	local dragonStar = GetReadyItem("item_dragon_star")
	if dragonStar == nil then return false end
	local shouldUse = ShouldUseDragonStar(
		#enemies,
		GetClosestEnemyDistance(bot, enemies),
		seriousRetreat,
		SafeCall(bot, "WasRecentlyDamagedByAnyHero", false, 2.5),
		GetHP(bot),
		committed
	)
	return shouldUse and UseAbility(bot, dragonStar) or false
end

local function FindClosestPursuer(bot, enemies, range)
	local closest = nil
	local closestDistance = math.huge
	for _, enemy in pairs(enemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		if distance <= range and distance < closestDistance
		and SafeCall(bot, "WasRecentlyDamagedByHero", false, enemy, 3.0)
		then
			closest = enemy
			closestDistance = distance
		end
	end
	return closest
end

local function TryUseDefensiveItems(bot, enemies, seriousRetreat)
	if TryUseDragonStar(bot, enemies, false, seriousRetreat) then return true end
	local underPressure = #enemies > 0
		and (seriousRetreat or SafeCall(bot, "WasRecentlyDamagedByAnyHero", false, 2.5))
		and (seriousRetreat or GetHP(bot) < 0.65)
	if not underPressure then return false end

	local trinity = GetReadyItem("item_trinity")
	if trinity ~= nil and not bot:HasModifier(TRINITY_MODIFIER) then
		return UseAbility(bot, trinity)
	end
	return false
end

local function TryUseHorseKing(bot, committed)
	local item = GetReadyItem("item_horse_king")
	if item == nil then return false end
	local active = bot:HasModifier(HORSE_KING_MODIFIER)
	if (committed and not active) or (not committed and active) then
		return UseAbility(bot, item)
	end
	return false
end

local function TryUsePreEngagementItems(bot, enemies, state)
	if state == nil then return false end
	-- 彗星是持续开关，先开启不会损失时限；龙星后开，完整覆盖六秒接敌窗口。
	if TryUseHorseKing(bot, true) then return true end
	return TryUseDragonStar(bot, enemies, true, false)
end

local function TryUseHorseRed(bot, enemies)
	if #enemies > 0
	or J.IsGoingOnSomeone(bot)
	or J.IsRetreating(bot)
	or J.IsInTeamFight(bot, FARM_RESERVE_RANGE)
	or SafeCall(bot, "WasRecentlyDamagedByAnyHero", false, 4.0)
	or GetHP(bot) >= 0.75
	then
		return false
	end
	local item = GetReadyItem("item_horse_red")
	return item ~= nil and UseAbility(bot, item) or false
end

local function TryUseTeeth(bot, state, ability02, ability03)
	if state.teethIssued then return false end
	local target = state.target
	local attackRange = SafeCall(bot, "GetAttackRange", 150) + 50
	local inAttackRange = GetUnitToUnitDistance(bot, target) <= attackRange
	local chen02Settled = state.chen02Issued or not IsCastable(ability02) or not CanTargetWithChen02(bot, target)
	local chen03Settled = state.chen03Issued or not IsCastable(ability03)
	if not ShouldUseTeeth(bot:HasModifier(ULTIMATE_MODIFIER), inAttackRange, chen02Settled, chen03Settled) then
		return false
	end
	local teeth = GetReadyItem("item_teeth")
	if teeth == nil then return false end
	state.teethIssued = true
	return UseAbility(bot, teeth)
end

local function ContinueCombo(bot, state, ability01, ability02, ability03, ability04, enemies, towerContext)
	local target = state.target
	local silenced = SafeCall(bot, "IsSilenced", false)
	local rollLocation = GetPredictedRollLocation(bot, target, ability01)
	local shouldRoll = ShouldUseChaseRoll(
		GetUnitToUnitDistance(bot, target),
		GetChaseApproachRange(bot, state, ability02),
		not silenced and not SafeCall(bot, "IsRooted", false) and IsCastable(ability01),
		state.rollCount or 0,
		J.IsChasingTarget ~= nil and J.IsChasingTarget(bot, target),
		DotaTime() - (state.lastRollAt or -90)
	)
	if shouldRoll and not CanUseChaseRoll(bot, target, enemies, rollLocation, towerContext) then
		ClearCombo(bot)
		return false
	end
	if not bot:HasModifier(ULTIMATE_MODIFIER)
	and not state.ultimateIssued
	and not silenced
	and IsCastable(ability04)
	then
		state.ultimateIssued = true
		return UseAbility(bot, ability04)
	end

	if shouldRoll then
		state.rollCount = (state.rollCount or 0) + 1
		state.lastRollAt = DotaTime()
		return UseAbilityOnLocation(bot, ability01, rollLocation)
	end

	local ability02Range = ability02 ~= nil and SafeCall(ability02, "GetCastRange", 400) or 400
	if not state.chen02Issued
	and not silenced
	and IsCastable(ability02)
	and CanTargetWithChen02(bot, target)
	and GetUnitToUnitDistance(bot, target) <= ability02Range + 25
	then
		state.chen02Issued = true
		return UseAbilityOnEntity(bot, ability02, target)
	end

	if not state.chen03Issued
	and not silenced
	and IsCastable(ability03)
	and GetUnitToUnitDistance(bot, target) <= CHEN03_COMBAT_RADIUS
	then
		state.chen03Issued = true
		return UseAbility(bot, ability03)
	end

	return TryUseTeeth(bot, state, ability02, ability03)
end

local function TryUseWanbao(bot, target, state, ability01, ability02, ability03, wanbao)
	local validContext = IsValidEnemyHero(bot, target)
	if not IsCastable(wanbao)
	or not (SafeCall(bot, "HasScepter", false) or bot:HasModifier(WANBAO_MODIFIER))
	or not ShouldUseWanbao(validContext, CountSkillCooldowns(ability01, ability02, ability03))
	then
		return false
	end

	-- 三技能能命中时先兑现一次双倍震击；下一帧才允许万宝槌重置。
	if IsCastable(ability03) and GetUnitToUnitDistance(bot, target) <= CHEN03_COMBAT_RADIUS then
		if state ~= nil then state.chen03Issued = true end
		return UseAbility(bot, ability03)
	end
	if state ~= nil then
		state.rollCount = 0
		state.lastRollAt = -90
		state.chen02Issued = false
		state.chen03Issued = false
		state.teethIssued = false
	end
	return UseAbility(bot, wanbao)
end

local function CountVisibleFarmUnits(bot, units)
	local count = 0
	for _, unit in pairs(units or {}) do
		if IsValidVisibleEnemyUnit(bot, unit) and SafeCall(unit, "IsCreep", false) then
			count = count + 1
		end
	end
	return count
end

local function TryUseChen03Farm(bot, ability03, reserveEnemies)
	if not IsCastable(ability03) then return false end
	local laneCount = CountVisibleFarmUnits(bot, SafeCall(bot, "GetNearbyLaneCreeps", {}, CHEN03_COMBAT_RADIUS, true))
	local neutralCount = CountVisibleFarmUnits(bot, SafeCall(bot, "GetNearbyNeutralCreeps", {}, CHEN03_COMBAT_RADIUS))
	if ShouldUseChen03Farm(laneCount, neutralCount, GetMP(bot), #reserveEnemies) then
		return UseAbility(bot, ability03)
	end
	return false
end

local function TrySeriousRetreat(bot, enemies, ability01, ability02, ability03, wanbao)
	if not J.IsSeriouslyRetreating(bot, CHEN01) then return false end
	ClearCombo(bot)
	local pursuer = FindClosestPursuer(bot, enemies, 900)
	if TryUseDefensiveItems(bot, enemies, true) then return true end

	local silenced = SafeCall(bot, "IsSilenced", false)
	if not silenced and not SafeCall(bot, "IsRooted", false) and IsCastable(ability01) then
		return UseAbilityOnLocation(bot, ability01, GetSafeRollLocation(bot, ability01, pursuer))
	end
	if pursuer ~= nil and not silenced and IsCastable(ability03)
	and GetUnitToUnitDistance(bot, pursuer) <= CHEN03_COMBAT_RADIUS
	then
		return UseAbility(bot, ability03)
	end
	local ability02Range = ability02 ~= nil and SafeCall(ability02, "GetCastRange", 400) or 400
	if pursuer ~= nil and not silenced and IsCastable(ability02)
	and CanTargetWithChen02(bot, pursuer)
	and GetUnitToUnitDistance(bot, pursuer) <= ability02Range + 25
	then
		return UseAbilityOnEntity(bot, ability02, pursuer)
	end
	if pursuer ~= nil and TryUseWanbao(bot, pursuer, nil, ability01, ability02, ability03, wanbao) then
		return true
	end
	return TryUseHorseKing(bot, true)
end

local function TryUseRegularItems(bot, enemies)
	if TryUseDefensiveItems(bot, enemies, false) then return true end
	local committed = (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, HERO_SCAN_RANGE) or J.IsRetreating(bot))
		and #enemies > 0
	if TryUseHorseKing(bot, committed) then return true end
	return TryUseHorseRed(bot, enemies)
end

function AbilityUsageThink()
	local bot = GetBot()
	if bot == nil or not SafeCall(bot, "IsAlive", false) then return end
	if type(ObserveAbilityUsageTask) == 'function' then
		ObserveAbilityUsageTask(bot, 'ability_usage_unthrottled', 0)
	end
	-- 滚动由游戏侧 modifier 驱动位移；生命周期内任何技能、装备或中立物品命令都会破坏动作管线。
	if bot:HasModifier(ROLLING_MODIFIER) then return end
	if WasActionJustIssued(bot) or J.CanNotUseAction(bot) then return end

	local ability01 = GetAbility(bot, CHEN01)
	local ability02 = GetAbility(bot, CHEN02)
	local ability03 = GetAbility(bot, CHEN03)
	local ability04 = GetAbility(bot, CHEN04)
	local wanbao = GetAbility(bot, CHEN_WANBAO)
	local enemies = GetVisibleEnemyHeroes(bot, HERO_SCAN_RANGE)
	local towerContext = {loaded = false}

	if TrySeriousRetreat(bot, enemies, ability01, ability02, ability03, wanbao) then return end

	local state = GetValidCombo(bot)
	if state ~= nil then
		if TryUsePreEngagementItems(bot, enemies, state) then return end
		if ContinueCombo(bot, state, ability01, ability02, ability03, ability04, enemies, towerContext) then
			return
		end
	end
	state = GetValidCombo(bot)

	if state == nil then
		local target = FindCombatTarget(bot, enemies, ability01, ability02, towerContext)
		if target ~= nil then
			state = StartCombo(bot, target)
			if TryUsePreEngagementItems(bot, enemies, state) then return end
			if ContinueCombo(bot, state, ability01, ability02, ability03, ability04, enemies, towerContext) then
				return
			end
			state = GetValidCombo(bot)
		end
	end

	if state ~= nil
	and TryUseWanbao(bot, state.target, state, ability01, ability02, ability03, wanbao)
	then
		return
	end

	local nearbyCombatEnemies = GetVisibleEnemyHeroes(bot, CHEN03_COMBAT_RADIUS)
	local committedTargetInRange = state ~= nil
		and GetUnitToUnitDistance(bot, state.target) <= CHEN03_COMBAT_RADIUS
	if not SafeCall(bot, "IsSilenced", false)
	and IsCastable(ability03)
	and ShouldUseChen03Combat(#nearbyCombatEnemies, committedTargetInRange, false)
	then
		if state ~= nil then state.chen03Issued = true end
		UseAbility(bot, ability03)
		return
	end

	local reserveEnemies = GetVisibleEnemyHeroes(bot, FARM_RESERVE_RANGE)
	if not SafeCall(bot, "IsSilenced", false)
	and TryUseChen03Farm(bot, ability03, reserveEnemies)
	then
		return
	end

	if TryUseRegularItems(bot, enemies) then return end
	if ConsiderNeutralItems ~= nil then ConsiderNeutralItems() end
end

if ORANGE_BOT_TEST_EXPORTS then
	OrangeBotTest = {
		ScoreDelayedControlTarget = ScoreDelayedControlTarget,
		ShouldUseChen03Combat = ShouldUseChen03Combat,
		ShouldUseChen03Farm = ShouldUseChen03Farm,
		ShouldUseWanbao = ShouldUseWanbao,
		ShouldUseTeeth = ShouldUseTeeth,
		CountSkillCooldowns = CountSkillCooldowns,
		IsValidEnemyHero = IsValidEnemyHero,
		ShouldUseChaseRoll = ShouldUseChaseRoll,
		ShouldAllowTowerDive = ShouldAllowTowerDive,
		ShouldUseDragonStar = ShouldUseDragonStar,
	}
end

----------------------------------------------------------------------------------------------------
