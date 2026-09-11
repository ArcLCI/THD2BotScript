local Retreat = {}
local Capabilities = require(GetScriptDirectory()..'/THDFuncLib/aba_retreat_capabilities')
local CombatPower = require(GetScriptDirectory()..'/THDFuncLib/combat_power')

-- 总开关：false 时只停用统一撤退框架，技能和道具仍使用 Valve 撤退模式判断。
Retreat.ENABLED = false

Retreat.NONE = 0
Retreat.CAUTION = 1
Retreat.HIGH = 2
Retreat.CRITICAL = 3

Retreat.TACTIC_RETREAT = 'RETREAT'
Retreat.TACTIC_DEFENSE_THEN_RETREAT = 'DEFENSE_THEN_RETREAT'
Retreat.TACTIC_CONTROL_RETREAT = 'CONTROL_RETREAT'
Retreat.TACTIC_COUNTERKILL_WINDOW = 'COUNTERKILL_WINDOW'
Retreat.TACTIC_TOWER_COVERED_WINDOW = 'TOWER_COVERED_WINDOW'

local FULL_UPDATE_INTERVAL = 0.18
local PREDICTION_HORIZON = 3.0
local HIGH_HOLD_TIME = 1.5
local TOWER_HOLD_TIME = 2.0
local CRITICAL_HOLD_TIME = 2.5
local HIGH_GROUND_TOWER_DESIRE = 1.0
local CRITICAL_DESIRE = 1.05
local TOWER_SCAN_RANGE = 1800
local TOWER_EXIT_BUFFER = 200
local TOWER_EXIT_TIME_MARGIN = 0.50
local COUNTER_KILL_HORIZON = 2.0
local LANING_PHASE_END_TIME = 8 * 60
local LANING_OUTNUMBER_RISK_CAP = 0.08
local LANING_POWER_RISK = 0.05
local LANING_PRESSURE_HEALTH_THRESHOLD = 0.70

local function IsValidUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and unit:IsNull() then return false end
	if unit.IsAlive ~= nil and not unit:IsAlive() then return false end
	return true
end

local function CanInspectUnit(unit)
	return IsValidUnit(unit)
		and unit.CanBeSeen ~= nil
		and unit:CanBeSeen()
end

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

function Retreat.IsEnabled()
	return Retreat.ENABLED ~= false
end

local function GetHealthPercent(unit)
	if not IsValidUnit(unit) or unit:GetMaxHealth() <= 0 then return 0 end
	return unit:GetHealth() / unit:GetMaxHealth()
end

local function GetManaPercent(unit)
	if not IsValidUnit(unit) or unit:GetMaxMana() <= 0 then return 1 end
	return unit:GetMana() / unit:GetMaxMana()
end

local function GetUnitKey(unit)
	if unit == nil then return 'nil' end
	if unit.entindex ~= nil then
		local ok, index = pcall(function() return unit:entindex() end)
		if ok and index ~= nil then return 'ent:'..tostring(index) end
	end
	if unit.GetEntityIndex ~= nil then
		local ok, index = pcall(function() return unit:GetEntityIndex() end)
		if ok and index ~= nil then return 'idx:'..tostring(index) end
	end
	local ok, name = pcall(function() return unit:GetUnitName() end)
	if ok and name ~= nil then
		local locationOk, location = pcall(function() return unit:GetLocation() end)
		if locationOk and location ~= nil then
			return name..':'..tostring(math.floor(location.x / 64))..':'..tostring(math.floor(location.y / 64))
		end
		return name
	end
	return tostring(unit)
end

local function IsHighGroundTower(tower)
	if not IsValidUnit(tower) then return false end
	local name = tower:GetUnitName()
	return string.find(name, 'tower3', 1, true) ~= nil
		or string.find(name, 'tower4', 1, true) ~= nil
end

local function GetAbilitySpecial(tower, abilityName, specialName, fallback)
	local ability = tower:GetAbilityByName(abilityName)
	if ability == nil then return fallback end

	local ok, value = pcall(function() return ability:GetSpecialValueInt(specialName) end)
	if ok and value ~= nil and value > 0 then return value end
	ok, value = pcall(function() return ability:GetSpecialValueFloat(specialName) end)
	if ok and value ~= nil and value > 0 then return value end
	return fallback
end

--[[
	高地塔的原版被动 modifier 名称可能随引擎变化，因此按来源技能识别层数。
	敌方 modifier 对 Bot 不可见时，上层会改用实际攻击时间和受击记录估算。
]]
local function GetModifierStateByAbility(unit, abilityName, sourceUnit)
	if not IsValidUnit(unit) or unit.NumModifiers == nil then return nil, nil end

	for i = 0, unit:NumModifiers() - 1 do
		local ok, sourceAbility = pcall(function() return unit:GetModifierSourceAbility(i) end)
		if ok and sourceAbility ~= nil then
			local abilityOk, sourceName = pcall(function() return sourceAbility:GetName() end)
			local matchesSource = true
			if sourceUnit ~= nil and sourceAbility.GetCaster ~= nil then
				local casterOk, caster = pcall(function() return sourceAbility:GetCaster() end)
				if casterOk and caster ~= nil then matchesSource = caster == sourceUnit end
			end
			if abilityOk and sourceName == abilityName and matchesSource then
				local stackOk, stack = pcall(function() return unit:GetModifierStackCount(i) end)
				local durationOk, duration = pcall(function() return unit:GetModifierRemainingDuration(i) end)
				return stackOk and stack or 0, durationOk and duration or nil
			end
		end
	end

	return nil, nil
end

local function EnsureState(bot)
	if bot.THD_RetreatState == nil then
		bot.THD_RetreatState = {
			severity = Retreat.NONE,
			desire = nil,
			forceDesire = false,
			reasons = {},
			towerAggro = {},
			lastFullUpdate = -90,
			highUntil = -90,
			towerUntil = -90,
			criticalUntil = -90,
		}
	end
	return bot.THD_RetreatState
end

local function GetIncomingTowerProjectiles(bot)
	local result = {}
	local ok, projectiles = pcall(function() return bot:GetIncomingTrackingProjectiles() end)
	if not ok or projectiles == nil then return result end

	for _, projectile in pairs(projectiles) do
		if projectile ~= nil and projectile.is_attack and IsValidUnit(projectile.caster)
		and projectile.caster:IsTower() then
			local key = GetUnitKey(projectile.caster)
			if result[key] == nil then
				result[key] = { tower = projectile.caster, count = 0 }
			end
			result[key].count = result[key].count + 1
		end
	end

	return result
end

local function CollectThreateningTowers(bot, incoming)
	local towers = {}
	-- 原生 GetNearbyTowers 最大只支持 1600；使用建筑列表保留 1800 的塔威胁检测范围。
	for _, tower in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
		if CanInspectUnit(tower)
		and tower.IsTower ~= nil
		and tower:IsTower()
		and GetUnitToUnitDistance(bot, tower) <= TOWER_SCAN_RANGE
		then
			towers[GetUnitKey(tower)] = tower
		end
	end
	for key, data in pairs(incoming) do
		if IsValidUnit(data.tower) then towers[key] = data.tower end
	end
	return towers
end

local function UpdateEstimatedTowerStacks(bot, tower, record, resetTime, maxFervor)
	local now = DotaTime()
	local attackTarget = tower:GetAttackTarget()
	local targetKey = GetUnitKey(attackTarget)
	local lastAttackTime = tower:GetLastAttackTime()
	local targetChanged = record.lastTargetKey ~= nil and record.lastTargetKey ~= targetKey

	if record.lastTargetKey == nil or targetChanged then
		record.estimatedFervor = 0
		-- 切换目标前的最后攻击不属于新的 Fervor 序列。
		record.lastObservedAttackTime = lastAttackTime
	end
	record.lastTargetKey = targetKey

	if attackTarget == bot
	and lastAttackTime ~= nil
	and lastAttackTime > (record.lastObservedAttackTime or -90) + 0.01
	then
		record.lastObservedAttackTime = lastAttackTime
		record.estimatedFervor = math.min(maxFervor, (record.estimatedFervor or 0) + 1)
	end

	-- 伤害层数只在确认近期受到塔伤害后增加，避免把尚未命中的弹道重复计算。
	if attackTarget == bot
	and bot:WasRecentlyDamagedByTower(0.30)
	and lastAttackTime ~= nil
	and lastAttackTime > (record.lastCountedHitAttackTime or -90) + 0.01
	then
		record.lastCountedHitAttackTime = lastAttackTime
		record.estimatedFury = (record.estimatedFury or 0) + 1
		record.lastBotHitTime = now
	end

	if record.lastBotHitTime == nil or now - record.lastBotHitTime > resetTime then
		record.estimatedFury = 0
	end
end

local function GetSafeAttackValue(unit, methodName, fallback)
	local method = unit[methodName]
	if method == nil then return fallback end
	local ok, value = pcall(function() return method(unit) end)
	if not ok or value == nil then return fallback end
	return value
end

local function SimulateTower(bot, tower, record, incomingCount, horizon, protection)
	local canInspect = CanInspectUnit(tower)
	local highGround = record.highGround == true
	if canInspect then
		highGround = IsHighGroundTower(tower)
		record.highGround = highGround
	end

	-- 与当前 T3/T4 三级被动一致；缺失热血战魂时不再虚构攻速增长。
	local damagePerStack = record.damagePerStack or (highGround and 15 or 0)
	local resetTime = record.resetTime or 15
	local attackSpeedPerStack = record.attackSpeedPerStack or 0
	local maxFervor = record.maxFervor or 0
	if canInspect and highGround then
		damagePerStack = GetAbilitySpecial(tower, 'tower_ursa_fury_swipes', 'damage_per_stack', 15)
		resetTime = GetAbilitySpecial(tower, 'tower_ursa_fury_swipes', 'bonus_reset_time', 15)
		attackSpeedPerStack = GetAbilitySpecial(tower, 'tower_troll_warlord_fervor', 'attack_speed', 0)
		maxFervor = GetAbilitySpecial(tower, 'tower_troll_warlord_fervor', 'max_stacks', 0)
		record.damagePerStack = damagePerStack
		record.resetTime = resetTime
		record.attackSpeedPerStack = attackSpeedPerStack
		record.maxFervor = maxFervor
	end

	if canInspect then UpdateEstimatedTowerStacks(bot, tower, record, resetTime, maxFervor) end

	local furyStack = 0
	local fervorStack = 0
	if highGround then
		local directFury = GetModifierStateByAbility(bot, 'tower_ursa_fury_swipes', tower)
		local directFervor = canInspect and GetModifierStateByAbility(tower, 'tower_troll_warlord_fervor', tower) or nil
		furyStack = directFury ~= nil and directFury or (record.estimatedFury or 0)
		fervorStack = directFervor ~= nil and directFervor or (record.estimatedFervor or 0)
	end

	if canInspect then
		record.baseDamage = math.max(0, GetSafeAttackValue(tower, 'GetAttackDamage', record.baseDamage or 0))
		record.currentPeriod = math.max(0.20, GetSafeAttackValue(tower, 'GetSecondsPerAttack', record.currentPeriod or 1.0))
		record.currentIAS = math.max(20, GetSafeAttackValue(tower, 'GetAttackSpeed', record.currentIAS or 100))
	end
	local baseDamage = record.baseDamage or 0
	local currentPeriod = record.currentPeriod or 1.0
	local currentIAS = record.currentIAS or 100
	local baseIAS = math.max(20, currentIAS - attackSpeedPerStack * fervorStack)
	local botDefense = CombatPower.GetDefenseSnapshot(bot)
	local predictedDamage = 0
	local unavoidableDamage = 0
	local rawPredictedDamage = 0
	local rawUnavoidableDamage = 0
	local hitCount = 0
	local preventedHitCount = 0
	local preventedAttackCount = 0
	local rawFuryStack = furyStack
	local projectileSpeed = math.max(0, GetSafeAttackValue(tower, 'GetAttackProjectileSpeed', 0))
	local projectileTravel = 0.25
	if projectileSpeed > 0 then
		projectileTravel = GetUnitToUnitDistance(bot, tower) / projectileSpeed
	end

	for i = 1, incomingCount do
		local rawDamage = CombatPower.EstimateIncomingDamageFromSnapshot(
			botDefense,
			baseDamage + damagePerStack * rawFuryStack,
			DAMAGE_TYPE_PHYSICAL
		) or math.huge
		rawPredictedDamage = rawPredictedDamage + rawDamage
		rawUnavoidableDamage = rawUnavoidableDamage + rawDamage
		rawFuryStack = rawFuryStack + 1

		local impactOffset = projectileTravel + (i - 1) * 0.02
		local resolution = Capabilities.ResolveAttack(protection, tower, impactOffset)
		if resolution.preventsHit then
			preventedHitCount = preventedHitCount + 1
		else
			local damage = CombatPower.EstimateIncomingDamageFromSnapshot(
				botDefense,
				baseDamage + damagePerStack * furyStack,
				DAMAGE_TYPE_PHYSICAL
			)
			if damage == nil then
				damage = math.huge
			else
				damage = damage * resolution.damageMultiplier
			end
			predictedDamage = predictedDamage + damage
			unavoidableDamage = unavoidableDamage + damage
			furyStack = furyStack + 1
		end
		hitCount = hitCount + 1
	end

	local locked = canInspect and tower:GetAttackTarget() == bot
	if locked then
		local now = DotaTime()
		local lastAttackTime = GetSafeAttackValue(tower, 'GetLastAttackTime', -90)
		local nextAttackAt = lastAttackTime + currentPeriod - now
		if lastAttackTime < -80 or nextAttackAt < 0.05 then nextAttackAt = 0.05 end

		while nextAttackAt <= horizon and hitCount < 20 do
			local rawDamage = CombatPower.EstimateIncomingDamageFromSnapshot(
				botDefense,
				baseDamage + damagePerStack * rawFuryStack,
				DAMAGE_TYPE_PHYSICAL
			) or math.huge
			rawPredictedDamage = rawPredictedDamage + rawDamage
			rawFuryStack = rawFuryStack + 1

			local resolution = Capabilities.ResolveAttack(protection, tower, nextAttackAt)
			if resolution.preventsAttack then
				preventedAttackCount = preventedAttackCount + 1
			elseif resolution.preventsHit then
				preventedHitCount = preventedHitCount + 1
				if highGround then fervorStack = math.min(maxFervor, fervorStack + 1) end
			else
				local damage = CombatPower.EstimateIncomingDamageFromSnapshot(
					botDefense,
					baseDamage + damagePerStack * furyStack,
					DAMAGE_TYPE_PHYSICAL
				)
				if damage == nil then
					damage = math.huge
				else
					damage = damage * resolution.damageMultiplier
				end
				predictedDamage = predictedDamage + damage
				furyStack = furyStack + 1
				if highGround then fervorStack = math.min(maxFervor, fervorStack + 1) end
			end
			hitCount = hitCount + 1

			local futureIAS = math.max(20, baseIAS + attackSpeedPerStack * fervorStack)
			local futurePeriod = math.max(0.20, currentPeriod * currentIAS / futureIAS)
			nextAttackAt = nextAttackAt + futurePeriod
		end
	end

	return {
		tower = tower,
		highGround = highGround,
		locked = locked,
		unseenIncoming = not canInspect and incomingCount > 0,
		incomingCount = incomingCount,
		predictedDamage = predictedDamage,
		unavoidableDamage = unavoidableDamage,
		rawPredictedDamage = rawPredictedDamage,
		rawUnavoidableDamage = rawUnavoidableDamage,
		hitCount = hitCount,
		preventedHitCount = preventedHitCount,
		preventedAttackCount = preventedAttackCount,
		furyStack = furyStack,
		rawFuryStack = rawFuryStack,
		fervorStack = fervorStack,
		attackRange = record.attackRange or 900,
		maxIncomingImpact = incomingCount > 0 and projectileTravel + (incomingCount - 1) * 0.02 or 0,
	}
end

local function GetTowerExitTime(bot, details)
	if bot:IsRooted() or bot:IsStunned() or bot:IsHexed()
	or bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling()
	then
		return nil, {}
	end
	local botLocation = bot:GetLocation()
	local awayX = 0
	local awayY = 0
	local activeDetails = {}
	for _, detail in pairs(details) do
		if detail.highGround and (detail.locked or detail.incomingCount > 0) and IsValidUnit(detail.tower) then
			local towerLocation = detail.tower:GetLocation()
			local dx = botLocation.x - towerLocation.x
			local dy = botLocation.y - towerLocation.y
			local length = math.sqrt(dx * dx + dy * dy)
			if length > 1 then
				awayX = awayX + dx / length
				awayY = awayY + dy / length
			end
			table.insert(activeDetails, detail)
		end
	end
	if #activeDetails == 0 then return nil, activeDetails end

	local awayLength = math.sqrt(awayX * awayX + awayY * awayY)
	if awayLength <= 0.01 then
		local firstTowerLocation = activeDetails[1].tower:GetLocation()
		awayX = botLocation.x - firstTowerLocation.x
		awayY = botLocation.y - firstTowerLocation.y
		awayLength = math.max(1, math.sqrt(awayX * awayX + awayY * awayY))
	end
	awayX = awayX / awayLength
	awayY = awayY / awayLength

	local exitDistance = 0
	for _, detail in pairs(activeDetails) do
		local towerLocation = detail.tower:GetLocation()
		local relX = botLocation.x - towerLocation.x
		local relY = botLocation.y - towerLocation.y
		local radius = (detail.attackRange or 900) + TOWER_EXIT_BUFFER
		local distanceSquared = relX * relX + relY * relY
		if distanceSquared < radius * radius then
			local projection = relX * awayX + relY * awayY
			local discriminant = projection * projection + radius * radius - distanceSquared
			local needed = -projection + math.sqrt(math.max(0, discriminant))
			exitDistance = math.max(exitDistance, needed)
		end
	end

	local speed = 300
	if bot.GetCurrentMovementSpeed ~= nil then
		local ok, currentSpeed = pcall(function() return bot:GetCurrentMovementSpeed() end)
		if ok and currentSpeed ~= nil and currentSpeed > 0 then speed = currentSpeed end
	end
	return exitDistance / math.max(1, speed) + TOWER_EXIT_TIME_MARGIN, activeDetails
end

--[[
	塔伤害按每座塔逐击模拟。三、四塔同时递增伤害与攻速；普通塔仅使用实时攻击周期。
	多座四塔的结果会汇总，已经发出的弹道单独标记为不可避免伤害。
]]
function Retreat.GetTowerThreat(bot, horizon, protection, forceAnalysis)
	horizon = horizon or PREDICTION_HORIZON
	if not Retreat.IsEnabled() and forceAnalysis ~= true then
		return {
			active = false,
			locked = false,
			highGroundLock = false,
			predictedDamage = 0,
			unavoidableDamage = 0,
			rawPredictedDamage = 0,
			rawUnavoidableDamage = 0,
			towerCount = 0,
			maxFuryStack = 0,
			rawMaxFuryStack = 0,
			maxFervorStack = 0,
			unseenIncoming = false,
			coveredHighGroundLock = false,
			coverageRemaining = 0,
			coveredUntil = -90,
			coverageReason = nil,
			exitTime = nil,
			details = {},
			escapeTower = nil,
		}
	end
	-- Push 的高地授权即使不接管 Valve retreat，也需要复用同一套只读塔伤预测来做安全门。
	protection = protection or Capabilities.GetSnapshot(bot)
	local state = EnsureState(bot)
	local now = DotaTime()
	if horizon == PREDICTION_HORIZON
	and state.lastTowerThreat ~= nil
	and now - (state.lastTowerThreatTime or -90) < 0.03
	then
		return state.lastTowerThreat
	end

	local incoming = GetIncomingTowerProjectiles(bot)
	local towers = CollectThreateningTowers(bot, incoming)
	local result = {
		active = false,
		locked = false,
		highGroundLock = false,
		predictedDamage = 0,
		unavoidableDamage = 0,
		rawPredictedDamage = 0,
		rawUnavoidableDamage = 0,
		towerCount = 0,
		maxFuryStack = 0,
		rawMaxFuryStack = 0,
		maxFervorStack = 0,
		unseenIncoming = false,
		coveredHighGroundLock = false,
		coverageRemaining = 0,
		coveredUntil = -90,
		coverageReason = nil,
		exitTime = nil,
		details = {},
		escapeTower = nil,
	}

	for key, tower in pairs(towers) do
		local incomingCount = incoming[key] ~= nil and incoming[key].count or 0
		local record = state.towerAggro[key]
		if record == nil then
			record = { estimatedFury = 0, estimatedFervor = 0 }
			state.towerAggro[key] = record
		end
		local canInspect = CanInspectUnit(tower)
		local locked = canInspect and tower:GetAttackTarget() == bot
		local recentlyThreatened = false
		if canInspect then
			local distance = GetUnitToUnitDistance(bot, tower)
			local attackRange = GetSafeAttackValue(tower, 'GetAttackRange', record.attackRange or 900)
			record.attackRange = attackRange
			recentlyThreatened = bot:WasRecentlyDamagedByTower(1.0) and distance <= attackRange + 350
		end
		if locked or incomingCount > 0 or recentlyThreatened then
			local detail = SimulateTower(bot, tower, record, incomingCount, horizon, protection)
			table.insert(result.details, detail)
			result.active = true
			result.locked = result.locked or detail.locked
			result.highGroundLock = result.highGroundLock or (detail.highGround and (detail.locked or incomingCount > 0))
			result.predictedDamage = result.predictedDamage + detail.predictedDamage
			result.unavoidableDamage = result.unavoidableDamage + detail.unavoidableDamage
			result.rawPredictedDamage = result.rawPredictedDamage + detail.rawPredictedDamage
			result.rawUnavoidableDamage = result.rawUnavoidableDamage + detail.rawUnavoidableDamage
			result.towerCount = result.towerCount + 1
			result.maxFuryStack = math.max(result.maxFuryStack, detail.furyStack)
			result.rawMaxFuryStack = math.max(result.rawMaxFuryStack, detail.rawFuryStack)
			result.maxFervorStack = math.max(result.maxFervorStack, detail.fervorStack)
			result.unseenIncoming = result.unseenIncoming or detail.unseenIncoming
			if result.escapeTower == nil or detail.predictedDamage > result.escapeTower.predictedDamage then
				result.escapeTower = detail
			end
		end
	end

	if result.highGroundLock and not result.unseenIncoming then
		local exitTime, activeDetails = GetTowerExitTime(bot, result.details)
		if exitTime ~= nil then
			local towers = {}
			local requiredCoverage = exitTime
			for _, detail in pairs(activeDetails) do
				table.insert(towers, detail.tower)
				requiredCoverage = math.max(requiredCoverage, detail.maxIncomingImpact or 0)
			end
			local coverageRemaining, coverageReason = Capabilities.GetTowerCoverageRemaining(protection, towers)
			result.exitTime = exitTime
			result.coverageRemaining = coverageRemaining
			result.coverageReason = coverageReason
			if coverageRemaining > requiredCoverage + TOWER_EXIT_TIME_MARGIN then
				result.coveredHighGroundLock = true
				-- 退出时间本身包含路径余量，截止点再单独保留半秒，避免保护刷新边界上的误判。
				result.coveredUntil = now + coverageRemaining - exitTime - TOWER_EXIT_TIME_MARGIN
			end
		end
	end

	if horizon == PREDICTION_HORIZON then
		state.lastTowerThreat = result
		state.lastTowerThreatTime = now
	end
	return result
end

local function IsKnownIllusion(hero)
	if not CanInspectUnit(hero) or not hero:IsHero() then return false end
	if hero:GetTeam() == GetTeam() then return hero:IsIllusion() end

	-- Bot API 禁止对敌方直接调用 IsIllusion，只使用可见 modifier 和公开玩家状态判断。
	if hero:HasModifier('modifier_illusion')
	or hero:HasModifier('modifier_flandre01_illusion_model')
	then
		return true
	end

	local playerId = hero:GetPlayerID()
	if playerId ~= nil and playerId >= 0 then
		if not IsHeroAlive(playerId) then return true end
		if GetHeroLevel(playerId) > hero:GetLevel() then return true end
	end
	return false
end

local function IsRealVisibleHero(hero)
	return CanInspectUnit(hero)
		and hero:IsHero()
		and not IsKnownIllusion(hero)
end

local function GetCombatPower(hero)
	return CombatPower.Estimate(hero)
end

local function GetEnemyContext(bot)
	local visibleEnemies = {}
	local seenPlayerIds = {}
	local enemyCount = 0
	local enemyPower = 0
	local pursuer = nil
	local beingChased = false

	for _, enemy in pairs(bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)) do
		if IsRealVisibleHero(enemy) then
			local playerId = enemy:GetPlayerID()
			seenPlayerIds[playerId] = true
			enemyCount = enemyCount + 1
			enemyPower = enemyPower + GetCombatPower(enemy)
			table.insert(visibleEnemies, enemy)
			local isChasing = enemy:GetAnimActivity() == ACTIVITY_RUN
				and bot:GetAnimActivity() == ACTIVITY_RUN
				and enemy:IsFacingLocation(bot:GetLocation(), 25)
				and not bot:IsFacingLocation(enemy:GetLocation(), 150)
			if isChasing then beingChased = true end
			if enemy:GetAttackTarget() == bot or isChasing or bot:WasRecentlyDamagedByHero(enemy, 2.0) then
				if pursuer == nil or GetUnitToUnitDistance(bot, enemy) < GetUnitToUnitDistance(bot, pursuer) then
					pursuer = enemy
				end
			end
		end
	end

	for _, playerId in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if not seenPlayerIds[playerId] and IsHeroAlive(playerId) then
			local info = GetHeroLastSeenInfo(playerId)
			local lastSeen = info ~= nil and info[1] or nil
			if lastSeen ~= nil
			and lastSeen.time_since_seen <= 3.0
			and GetUnitToLocationDistance(bot, lastSeen.location) <= 2200
			then
				enemyCount = enemyCount + 1
			end
		end
	end

	return visibleEnemies, enemyCount, enemyPower, pursuer, beingChased
end

local function GetAllyContext(bot)
	local allyCount = 1
	local allyPower = GetCombatPower(bot)
	for _, ally in pairs(bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)) do
		if IsRealVisibleHero(ally) and ally ~= bot then
			allyCount = allyCount + 1
			allyPower = allyPower + GetCombatPower(ally)
		end
	end
	return allyCount, allyPower
end

local function GetNonHeroPredictedDamage(bot, horizon, protection)
	local threat = { predictedDamage = 0, rawPredictedDamage = 0 }
	local botDefense = CombatPower.GetDefenseSnapshot(bot)
	for _, creep in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
		if CanInspectUnit(creep)
		and not creep:IsHero()
		and not creep:IsTower()
		and GetUnitToUnitDistance(bot, creep) <= 1200
		and creep:GetAttackTarget() == bot
		then
			local attack = CombatPower.GetAttackSnapshot(creep)
			local period = attack ~= nil and math.max(0.3, attack.attackPeriod) or horizon
			local hitCount = attack ~= nil and math.max(1, math.floor(horizon / period)) or 1
			local rawPerHit = attack ~= nil
				and CombatPower.EstimateIncomingDamageFromSnapshot(
					botDefense,
					attack.attackDamage,
					DAMAGE_TYPE_PHYSICAL
				)
				or math.huge
			for i = 1, hitCount do
				local impactOffset = math.min(0.25, period) + (i - 1) * period
				threat.rawPredictedDamage = threat.rawPredictedDamage + rawPerHit
				local resolution = Capabilities.ResolveAttack(protection, creep, impactOffset)
				if not resolution.preventsAttack and not resolution.preventsHit then
					threat.predictedDamage = threat.predictedDamage + rawPerHit * resolution.damageMultiplier
				end
			end
		end
	end
	return threat
end

local function GetHeroAttackPredictedDamage(bot, visibleEnemies, horizon, protection)
	local threat = { predictedDamage = 0, rawPredictedDamage = 0 }
	local botDefense = CombatPower.GetDefenseSnapshot(bot)
	for _, enemy in pairs(visibleEnemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		local attackRange = GetSafeAttackValue(enemy, 'GetAttackRange', 150)
		local threatening = enemy:GetAttackTarget() == bot
			or bot:WasRecentlyDamagedByHero(enemy, 2.0)
			or (distance <= attackRange + 180 and enemy:IsFacingLocation(bot:GetLocation(), 35))
		if threatening then
			local attack = CombatPower.GetAttackSnapshot(enemy)
			local period = attack ~= nil and math.max(0.3, attack.attackPeriod) or horizon
			local hitCount = attack ~= nil and math.max(1, math.floor(horizon / period)) or 1
			local rawPerHit = attack ~= nil
				and CombatPower.EstimateIncomingDamageFromSnapshot(
					botDefense,
					attack.attackDamage,
					DAMAGE_TYPE_PHYSICAL
				)
				or math.huge
			for i = 1, hitCount do
				local impactOffset = math.min(0.25, period) + (i - 1) * period
				threat.rawPredictedDamage = threat.rawPredictedDamage + rawPerHit
				local resolution = Capabilities.ResolveAttack(protection, enemy, impactOffset)
				if not resolution.preventsAttack and not resolution.preventsHit then
					threat.predictedDamage = threat.predictedDamage + rawPerHit * resolution.damageMultiplier
				end
			end
		end
	end
	return threat
end

local function GetIncomingHeroAttackProjectileThreat(bot, protection)
	local threat = {
		predictedDamage = 0,
		rawPredictedDamage = 0,
		count = 0,
		lethal = false,
		baseLethal = false,
	}
	local botDefense = CombatPower.GetDefenseSnapshot(bot)
	local ok, projectiles = pcall(function() return bot:GetIncomingTrackingProjectiles() end)
	if not ok or projectiles == nil then return threat end

	for _, projectile in pairs(projectiles) do
		local caster = projectile ~= nil and projectile.caster or nil
		if projectile ~= nil and projectile.is_attack
		and IsValidUnit(caster) and caster:IsHero() and not caster:IsTower()
		then
			local attack = CombatPower.GetAttackSnapshot(caster)
			local rawDamage = attack ~= nil
				and CombatPower.EstimateIncomingDamageFromSnapshot(
					botDefense,
					attack.attackDamage,
					DAMAGE_TYPE_PHYSICAL
				)
				or math.huge
			local impactOffset = 0.10
			local speed = GetSafeAttackValue(caster, 'GetAttackProjectileSpeed', 0)
			if speed > 0 and projectile.location ~= nil then
				local botLocation = bot:GetLocation()
				local dx = botLocation.x - projectile.location.x
				local dy = botLocation.y - projectile.location.y
				impactOffset = math.sqrt(dx * dx + dy * dy) / speed
			end
			local resolution = Capabilities.ResolveAttack(protection, caster, impactOffset)
			threat.rawPredictedDamage = threat.rawPredictedDamage + rawDamage
			if not resolution.preventsHit then
				threat.predictedDamage = threat.predictedDamage + rawDamage * resolution.damageMultiplier
			end
			threat.count = threat.count + 1
		end
	end
	threat.baseLethal = threat.rawPredictedDamage >= bot:GetHealth()
	threat.lethal = threat.predictedDamage >= bot:GetHealth()
	return threat
end

local function EvaluateContext(bot, enemyCount, allyCount, enemyPower, allyPower, pursuer, beingChased, damage)
	local predictedHealth = bot:GetHealth() + bot:GetHealthRegen() * PREDICTION_HORIZON
		- damage.tower - damage.creep - damage.heroAttack
	local predictedHealthPercent = predictedHealth / math.max(1, bot:GetMaxHealth())
	local predictedManaPercent = Clamp((bot:GetMana() + bot:GetManaRegen() * PREDICTION_HORIZON) / math.max(1, bot:GetMaxMana()), 0, 1)
	local resource = Clamp(predictedHealthPercent, 0, 1) * 0.9 + predictedManaPercent * 0.1
	local risk = ((1 - resource) + (1 - resource) ^ 4) / 2
	local reasons = {}
	local recentlyDamagedByHero = bot:WasRecentlyDamagedByAnyHero(2.0)
	local recentlyDamagedByTower = bot:WasRecentlyDamagedByTower(1.0)
	local meaningfulCreepPressure = damage.creep >= bot:GetHealth() * 0.10
	local meaningfulHeroAttackPressure = damage.heroAttack >= bot:GetHealth() * 0.10
	local hp = GetHealthPercent(bot)
	local laneHealthPressure = recentlyDamagedByHero and hp <= LANING_PRESSURE_HEALTH_THRESHOLD
		or (meaningfulHeroAttackPressure or meaningfulCreepPressure)
			and predictedHealthPercent <= LANING_PRESSURE_HEALTH_THRESHOLD
	local directPressure = recentlyDamagedByTower
		or beingChased
		or damage.tower > 0
		or laneHealthPressure
	local softenLaneDisadvantage = DotaTime() < LANING_PHASE_END_TIME and not directPressure
	local laneDisadvantageSoftened = false

	if recentlyDamagedByHero then risk = risk + 0.12; table.insert(reasons, 'hero_damage') end
	if recentlyDamagedByTower then risk = risk + 0.12; table.insert(reasons, 'tower_damage') end
	if enemyCount > allyCount then
		local outnumberRisk = math.min(0.54, (enemyCount - allyCount) * 0.18)
		if softenLaneDisadvantage then
			outnumberRisk = math.min(outnumberRisk, LANING_OUTNUMBER_RISK_CAP)
			laneDisadvantageSoftened = true
		end
		risk = risk + outnumberRisk
		table.insert(reasons, 'outnumbered')
	end
	if enemyPower > allyPower * 1.15 and enemyCount > 0 then
		local powerRisk = 0.20
		if softenLaneDisadvantage then
			powerRisk = LANING_POWER_RISK
			laneDisadvantageSoftened = true
		end
		risk = risk + powerRisk
		table.insert(reasons, 'enemy_stronger')
	end
	-- 对线期只观察人数/战力劣势；敌人真正攻击、追击或形成伤害预测后再恢复完整风险。
	if laneDisadvantageSoftened then table.insert(reasons, 'lane_disadvantage_softened') end
	if pursuer ~= nil then risk = risk + 0.12; table.insert(reasons, 'pursued') end
	if beingChased then table.insert(reasons, 'confirmed_chase') end
	if laneHealthPressure and DotaTime() < LANING_PHASE_END_TIME then table.insert(reasons, 'lane_health_pressure') end
	if meaningfulCreepPressure then risk = risk + 0.12; table.insert(reasons, 'creep_damage') end
	if meaningfulHeroAttackPressure then table.insert(reasons, 'hero_attack_projection') end
	if allyCount > enemyCount and enemyCount > 0 and allyPower > enemyPower * 1.15 then risk = risk - 0.20 end
	if enemyCount == 0 and not bot:WasRecentlyDamagedByAnyHero(3.0) and damage.tower <= 0 then risk = risk - 0.25 end

	local severity = Retreat.NONE
	local desire = nil
	local hardCritical = false
	if predictedHealth <= 0 or predictedHealthPercent <= 0.12
		or hp <= 0.25 and enemyCount > 0 and (recentlyDamagedByHero or recentlyDamagedByTower)
	then
		severity = Retreat.CRITICAL
		desire = CRITICAL_DESIRE
		hardCritical = true
	elseif enemyCount >= 3 and allyCount <= 2 and not softenLaneDisadvantage then
		severity = Retreat.HIGH
		desire = 0.95
	elseif risk >= 0.68 then
		severity = Retreat.HIGH
		desire = 0.92 + Clamp((risk - 0.68) / 0.5, 0, 1) * 0.05
	elseif risk >= 0.45 then
		severity = Retreat.CAUTION
	end

	return {
		predictedHealth = predictedHealth,
		predictedHealthPercent = predictedHealthPercent,
		resource = resource,
		risk = risk,
		reasons = reasons,
		severity = severity,
		desire = desire,
		hardCritical = hardCritical,
	}
end

local function UpdateFullContext(bot, state, towerThreat, protection)
	local visibleEnemies, enemyCount, enemyPower, pursuer, beingChased = GetEnemyContext(bot)
	local allyCount, allyPower = GetAllyContext(bot)
	local creepThreat = GetNonHeroPredictedDamage(bot, PREDICTION_HORIZON, protection)
	local heroAttackThreat = GetHeroAttackPredictedDamage(bot, visibleEnemies, PREDICTION_HORIZON, protection)
	local projectileThreat = GetIncomingHeroAttackProjectileThreat(bot, protection)
	local protectedHeroDamage = math.max(heroAttackThreat.predictedDamage, projectileThreat.predictedDamage)
	local baseHeroDamage = math.max(heroAttackThreat.rawPredictedDamage, projectileThreat.rawPredictedDamage)
	local base = EvaluateContext(bot, enemyCount, allyCount, enemyPower, allyPower, pursuer, beingChased, {
		tower = towerThreat.rawPredictedDamage or towerThreat.predictedDamage,
		creep = creepThreat.rawPredictedDamage,
		heroAttack = baseHeroDamage,
	})
	local protected = EvaluateContext(bot, enemyCount, allyCount, enemyPower, allyPower, pursuer, beingChased, {
		-- 覆盖窗口成立时，Bot会在保护结束前离开塔射程，不能继续按原地站满三秒估算后续塔伤。
		tower = towerThreat.coveredHighGroundLock and 0 or towerThreat.predictedDamage,
		creep = creepThreat.predictedDamage,
		heroAttack = protectedHeroDamage,
	})
	if projectileThreat.baseLethal then
		base.severity = Retreat.CRITICAL
		base.desire = math.max(base.desire or 0, CRITICAL_DESIRE)
		base.hardCritical = true
		table.insert(base.reasons, 'lethal_projectile')
	end
	if projectileThreat.lethal then
		protected.severity = Retreat.CRITICAL
		protected.desire = math.max(protected.desire or 0, CRITICAL_DESIRE)
		protected.hardCritical = true
		table.insert(protected.reasons, 'lethal_projectile')
	end

	state.visibleEnemies = visibleEnemies
	state.enemyCount = enemyCount
	state.allyCount = allyCount
	state.enemyPower = enemyPower
	state.allyPower = allyPower
	state.pursuer = pursuer
	state.beingChased = beingChased
	state.creepPredictedDamage = creepThreat.predictedDamage
	state.rawCreepPredictedDamage = creepThreat.rawPredictedDamage
	state.heroAttackPredictedDamage = heroAttackThreat.predictedDamage
	state.rawHeroAttackPredictedDamage = heroAttackThreat.rawPredictedDamage
	state.projectileThreat = projectileThreat
	state.lethalProjectile = projectileThreat.lethal
	state.baseLethalProjectile = projectileThreat.baseLethal
	state.predictedHealth = protected.predictedHealth
	state.predictedHealthPercent = protected.predictedHealthPercent
	state.resource = protected.resource
	state.risk = protected.risk
	state.basePredictedHealth = base.predictedHealth
	state.baseRisk = base.risk
	state.baseReasons = base.reasons
	state.rawReasons = protected.reasons
	state.contextBaseSeverity = base.severity
	state.contextBaseDesire = base.desire
	state.contextBaseHardCritical = base.hardCritical
	state.contextRawSeverity = protected.severity
	state.contextRawDesire = protected.desire
	state.contextRawHardCritical = protected.hardCritical
	state.baseSeverity = base.severity
	state.baseDesire = base.desire
	state.baseHardCritical = base.hardCritical
	state.rawSeverity = protected.severity
	state.rawDesire = protected.desire
	state.rawHardCritical = protected.hardCritical
end

local function ApplyTowerOverrides(bot, state, towerThreat, severity, desire, useRaw)
	if not towerThreat.active then return severity, desire end
	if not useRaw and towerThreat.coveredHighGroundLock then return severity, desire end

	local hp = bot:GetHealth()
	local hpPercent = GetHealthPercent(bot)
	local predictedDamage = useRaw and (towerThreat.rawPredictedDamage or towerThreat.predictedDamage)
		or towerThreat.predictedDamage
	local unavoidableDamage = useRaw and (towerThreat.rawUnavoidableDamage or towerThreat.unavoidableDamage)
		or towerThreat.unavoidableDamage
	local maxFuryStack = useRaw and (towerThreat.rawMaxFuryStack or towerThreat.maxFuryStack)
		or towerThreat.maxFuryStack
	local predictedPercent = predictedDamage / math.max(1, hp)
	local critical = unavoidableDamage >= hp
		or predictedPercent >= 0.55
		or (hp - predictedDamage) / math.max(1, bot:GetMaxHealth()) <= 0.12
		or (maxFuryStack >= 4 and hpPercent <= 0.50)

	if critical then
		return Retreat.CRITICAL, math.max(desire or 0, CRITICAL_DESIRE)
	end

	if towerThreat.highGroundLock and (useRaw or not towerThreat.coveredHighGroundLock) then
		return math.max(severity, Retreat.HIGH), math.max(desire or 0, HIGH_GROUND_TOWER_DESIRE)
	end
	if towerThreat.unseenIncoming then
		-- 已失去塔视野时不能读取其攻击状态；仅凭已确认的在途普攻保守撤离。
		return math.max(severity, Retreat.HIGH), math.max(desire or 0, 0.96)
	end

	if towerThreat.locked and (bot:WasRecentlyDamagedByTower(1.0) or predictedPercent >= 0.25)
		or maxFuryStack >= 2
	then
		return math.max(severity, Retreat.HIGH), math.max(desire or 0, 0.96)
	end

	return severity, desire
end

local CONTROL_MODIFIERS = {
	'modifier_item_pocket_watch_pause',
	'modifier_item_yuetufensuijvren_pause',
	'modifier_stunsystem_pause',
	'modifier_item_yukkuri_stick_debuff',
}

local function GetExistingControlTime(enemy)
	if not enemy:IsStunned() and not enemy:IsRooted() and not enemy:IsHexed() then return 0 end
	local longest = 0
	for _, modifierName in pairs(CONTROL_MODIFIERS) do
		local index = enemy:GetModifierByName(modifierName)
		if index ~= nil and index >= 0 then
			local ok, remaining = pcall(function() return enemy:GetModifierRemainingDuration(index) end)
			if ok and remaining ~= nil and remaining > longest then longest = remaining end
		end
	end
	-- 无法确认来源和剩余时间的控制不作乐观假设，允许调用方按自身前摇重新判断。
	return longest
end

local function IsSuspiciousControlTarget(enemy)
	return IsKnownIllusion(enemy)
end

local function SelectControlTarget(bot, enemies, castRange, options, pursuer)
	options = options or {}
	castRange = castRange or 1600
	local minimumControlTime = options.minimumControlTime or 0.5
	local bestTarget = nil
	local bestPriority = -1
	local bestControlTime = 0
	for _, enemy in pairs(enemies or {}) do
		local blocked = false
		for _, modifierName in pairs(options.blockedModifiers or {}) do
			if enemy:HasModifier(modifierName) then blocked = true; break end
		end
		if IsRealVisibleHero(enemy)
		and not IsSuspiciousControlTarget(enemy)
		and not enemy:IsInvulnerable()
		and not blocked
		and (options.allowMagicImmune == true or not enemy:IsMagicImmune())
		and GetUnitToUnitDistance(bot, enemy) <= castRange
		then
			local existingControl = GetExistingControlTime(enemy)
			if existingControl < minimumControlTime then
				local priority = 0
				if bot:WasRecentlyDamagedByHero(enemy, 2.0) then
					priority = 40000
				elseif enemy:GetAttackTarget() == bot then
					priority = 30000
				elseif enemy == pursuer then
					priority = 20000
				else
					priority = 10000
				end
				priority = priority - GetUnitToUnitDistance(bot, enemy)
				if bestTarget == nil or priority > bestPriority then
					bestTarget = enemy
					bestPriority = priority
					bestControlTime = existingControl
				end
			end
		end
	end
	return bestTarget, bestControlTime
end

local function GetCurrentCombatTarget(bot)
	local target = nil
	if bot.GetTarget ~= nil then
		local ok, result = pcall(function() return bot:GetTarget() end)
		if ok then target = result end
	end
	if (not IsRealVisibleHero(target) or IsSuspiciousControlTarget(target))
	and bot.GetAttackTarget ~= nil
	then
		local ok, result = pcall(function() return bot:GetAttackTarget() end)
		if ok then target = result end
	end
	return target
end

local function SafeEstimatedDamage(attacker, target, horizon, fallback)
	fallback = fallback or 0
	if not IsValidUnit(attacker) or not IsValidUnit(target) then return fallback end
	return CombatPower.EstimateAttackDamage(attacker, target, horizon, 1, fallback)
end

local function RejectCounterKill(reason, target)
	return { valid = false, target = target, reason = reason }
end

local function EvaluateCounterKill(bot, state, towerThreat, currentSeverity)
	local target = GetCurrentCombatTarget(bot)
	if currentSeverity ~= Retreat.HIGH then return RejectCounterKill('not_soft_high', target) end
	if state.rawHardCritical then return RejectCounterKill('hard_critical', target) end
	if GetHealthPercent(bot) <= 0.20 then return RejectCounterKill('low_health', target) end
	if state.enemyCount ~= 1 then return RejectCounterKill('enemy_count', target) end
	if towerThreat.active then return RejectCounterKill('tower_threat', target) end
	if (state.creepPredictedDamage or 0) >= bot:GetHealth() * 0.10 then return RejectCounterKill('creep_threat', target) end
	if not IsRealVisibleHero(target) or IsSuspiciousControlTarget(target) then return RejectCounterKill('invalid_target', target) end
	if target:IsInvulnerable() or target:IsAttackImmune() then return RejectCounterKill('protected_target', target) end

	local foundTarget = false
	for _, enemy in pairs(state.visibleEnemies or {}) do
		if enemy == target then foundTarget = true; break end
	end
	if not foundTarget then return RejectCounterKill('target_not_visible_enemy', target) end

	local mode = bot:GetActiveMode()
	local attackingMode = mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_ROAM
		or (BOT_MODE_GANK ~= nil and mode == BOT_MODE_GANK)
	if not attackingMode or bot:GetActiveModeDesire() < BOT_MODE_DESIRE_HIGH then
		return RejectCounterKill('no_attack_intent', target)
	end
	if bot:IsStunned() or bot:IsHexed() or bot:IsNightmared() or bot:IsDisarmed()
		or bot:IsChanneling() or bot:IsUsingAbility() then
		return RejectCounterKill('cannot_act', target)
	end
	if bot.CanAttack ~= nil and not bot:CanAttack() then
		return RejectCounterKill('cannot_attack', target)
	end

	local outgoingDamage = SafeEstimatedDamage(bot, target, COUNTER_KILL_HORIZON, 0)
	local customDamage = Capabilities.GetCustomCounterDamage(bot, target, COUNTER_KILL_HORIZON)
	outgoingDamage = math.max(outgoingDamage, customDamage or 0)
	local incomingDamage = SafeEstimatedDamage(target, bot, COUNTER_KILL_HORIZON, math.huge)
	local postTradeHealth = bot:GetHealth() - incomingDamage
	local result = {
		valid = false,
		target = target,
		outgoingDamage = outgoingDamage,
		incomingDamage = incomingDamage,
		postTradeHealth = postTradeHealth,
		damageMargin = outgoingDamage / math.max(1, target:GetHealth()),
	}
	if outgoingDamage < target:GetHealth() * 1.20 then
		result.reason = 'insufficient_damage'
		return result
	end
	if incomingDamage > bot:GetHealth() * 0.55 then
		result.reason = 'incoming_damage'
		return result
	end
	if postTradeHealth < bot:GetMaxHealth() * 0.30 then
		result.reason = 'insufficient_post_trade_health'
		return result
	end
	result.valid = true
	result.reason = 'counterkill_window'
	return result
end

--[[
	统一撤退状态只接管明确高危场景；普通风险保留给 Valve 默认撤退模式。
	高危、塔风险和致命风险分别使用迟滞，避免模式在阈值附近反复切换。
]]
function Retreat.GetState(bot)
	local state = EnsureState(bot)
	if not Retreat.IsEnabled() then
		if state.frameworkEnabled ~= false then
			state.highUntil = -90
			state.towerUntil = -90
			state.criticalUntil = -90
			state.lastFullUpdateBucket = nil
			state.lastTowerThreat = nil
			state.towerAggro = {}
		end
		state.frameworkEnabled = false
		state.severity = Retreat.NONE
		state.rawSeverity = Retreat.NONE
		state.baseSeverity = Retreat.NONE
		state.desire = nil
		state.rawDesire = nil
		state.baseDesire = nil
		state.rawHardCritical = false
		state.baseHardCritical = false
		state.contextRawSeverity = Retreat.NONE
		state.contextBaseSeverity = Retreat.NONE
		state.contextRawDesire = nil
		state.contextBaseDesire = nil
		state.contextRawHardCritical = false
		state.contextBaseHardCritical = false
		state.tactic = nil
		state.protection = nil
		state.readyDefense = nil
		state.control = nil
		state.counterKill = { valid = false, reason = 'framework_disabled' }
		state.towerThreat = Retreat.GetTowerThreat(bot, PREDICTION_HORIZON)
		state.visibleEnemies = {}
		state.enemyCount = 0
		state.allyCount = 0
		state.pursuer = nil
		state.beingChased = false
		state.risk = 0
		state.baseRisk = 0
		state.rawReasons = {}
		state.baseReasons = {}
		state.lethalProjectile = false
		state.baseLethalProjectile = false
		state.fountainHold = false
		state.forceDesire = false
		state.reasons = { 'framework_disabled' }
		return state
	end
	state.frameworkEnabled = true
	if not IsValidUnit(bot) or bot:IsIllusion() then
		state.severity = Retreat.NONE
		state.rawSeverity = Retreat.NONE
		state.baseSeverity = Retreat.NONE
		state.desire = nil
		state.rawDesire = nil
		state.tactic = nil
		state.forceDesire = false
		return state
	end

	local now = DotaTime()
	local protection = Capabilities.GetSnapshot(bot)
	state.protection = protection
	local towerThreat = Retreat.GetTowerThreat(bot, PREDICTION_HORIZON, protection)
	state.towerThreat = towerThreat

	local playerId = bot:GetPlayerID()
	local updateOffset = math.max(0, playerId) % 5 * (FULL_UPDATE_INTERVAL / 5)
	local updateBucket = math.floor((now + updateOffset) / FULL_UPDATE_INTERVAL)
	if state.lastFullUpdateBucket ~= updateBucket then
		UpdateFullContext(bot, state, towerThreat, protection)
		state.lastFullUpdate = now
		state.lastFullUpdateBucket = updateBucket
	end

	if bot:HasModifier('modifier_fountain_aura_buff') then
		local needsHealing = GetHealthPercent(bot) < 0.92 or GetManaPercent(bot) < 0.70
		state.fountainHold = needsHealing
		state.severity = needsHealing and Retreat.CAUTION or Retreat.NONE
		state.rawSeverity = state.severity
		state.baseSeverity = state.severity
		state.desire = needsHealing and 0.78 or nil
		state.rawDesire = state.desire
		state.tactic = nil
		state.control = nil
		state.counterKill = RejectCounterKill('fountain', nil)
		state.forceDesire = needsHealing
		state.reasons = needsHealing and { 'fountain_recovery' } or {}
		return state
	end
	state.fountainHold = false

	local baseSeverity = state.contextBaseSeverity or Retreat.NONE
	local baseDesire = state.contextBaseDesire
	baseSeverity, baseDesire = ApplyTowerOverrides(bot, state, towerThreat, baseSeverity, baseDesire, true)
	local baseHardCritical = state.contextBaseHardCritical == true or baseSeverity >= Retreat.CRITICAL

	local rawSeverity = state.contextRawSeverity or Retreat.NONE
	local rawDesire = state.contextRawDesire
	rawSeverity, rawDesire = ApplyTowerOverrides(bot, state, towerThreat, rawSeverity, rawDesire, false)
	local rawHardCritical = state.contextRawHardCritical == true or rawSeverity >= Retreat.CRITICAL

	if GetHealthPercent(bot) <= 0.12 then
		baseSeverity = Retreat.CRITICAL
		baseDesire = math.max(baseDesire or 0, CRITICAL_DESIRE)
		baseHardCritical = true
		rawSeverity = Retreat.CRITICAL
		rawDesire = math.max(rawDesire or 0, CRITICAL_DESIRE)
		rawHardCritical = true
	end
	state.baseSeverity = baseSeverity
	state.baseDesire = baseDesire
	state.baseHardCritical = baseHardCritical
	state.rawSeverity = rawSeverity
	state.rawDesire = rawDesire
	state.rawHardCritical = rawHardCritical

	if rawSeverity >= Retreat.CRITICAL then
		state.criticalUntil = now + CRITICAL_HOLD_TIME
	elseif rawSeverity >= Retreat.HIGH then
		state.highUntil = now + HIGH_HOLD_TIME
	end
	if towerThreat.active and rawSeverity >= Retreat.HIGH and not towerThreat.coveredHighGroundLock then
		state.towerUntil = now + TOWER_HOLD_TIME
		state.lastTowerDesire = rawDesire
	end

	local severity = rawSeverity
	local desire = rawDesire
	if now < state.criticalUntil then
		severity = Retreat.CRITICAL
		desire = math.max(desire or 0, CRITICAL_DESIRE)
	elseif now < state.towerUntil then
		severity = math.max(severity, Retreat.HIGH)
		desire = math.max(desire or 0, state.lastTowerDesire or 0.96)
	elseif now < state.highUntil then
		severity = math.max(severity, Retreat.HIGH)
		desire = math.max(desire or 0, 0.92)
	end

	local coveredTowerWindow = towerThreat.coveredHighGroundLock
		and now < (towerThreat.coveredUntil or -90)
		and rawSeverity < Retreat.HIGH
		and not rawHardCritical
	if coveredTowerWindow then
		severity = math.max(rawSeverity, Retreat.CAUTION)
		desire = nil
	end

	local counterKill = EvaluateCounterKill(bot, state, towerThreat, severity)
	state.counterKill = counterKill
	if counterKill.valid then
		severity = Retreat.CAUTION
		desire = nil
	end

	local controlRange = 1600
	if protection.customControl ~= nil then
		controlRange = protection.customControl.range or controlRange
	end
	local controlTarget, existingControl = SelectControlTarget(
		bot,
		state.visibleEnemies,
		controlRange,
		{ minimumControlTime = 0.5 },
		state.pursuer
	)
	local hasEffectiveControl = Capabilities.HasEffectiveControl(protection)
	-- 普通 HIGH 撤退只接管走位；控制技能必须留给真正的紧急撤退。
	if hasEffectiveControl and severity < Retreat.CRITICAL then
		hasEffectiveControl = false
	end
	state.control = {
		available = hasEffectiveControl,
		target = controlTarget,
		type = protection.customControl ~= nil and protection.customControl.controlType or nil,
		duration = protection.customControl ~= nil and protection.customControl.duration or 0,
		genericStunHint = protection.stunDuration or 0,
		genericSlowHint = protection.slowDuration or 0,
		customControl = protection.customControl,
		candidates = protection.controlCandidates,
		existingControl = existingControl,
	}
	local readyDefense = Capabilities.GetReadyDefense(protection)
	state.readyDefense = readyDefense
	if coveredTowerWindow then
		state.tactic = Retreat.TACTIC_TOWER_COVERED_WINDOW
	elseif counterKill.valid then
		state.tactic = Retreat.TACTIC_COUNTERKILL_WINDOW
	elseif severity >= Retreat.CRITICAL and readyDefense ~= nil then
		state.tactic = Retreat.TACTIC_DEFENSE_THEN_RETREAT
	elseif severity >= Retreat.CRITICAL and hasEffectiveControl and controlTarget ~= nil then
		state.tactic = Retreat.TACTIC_CONTROL_RETREAT
	elseif severity >= Retreat.HIGH then
		state.tactic = Retreat.TACTIC_RETREAT
	else
		state.tactic = nil
	end

	local reasons = {}
	for _, reason in pairs(state.rawReasons or {}) do table.insert(reasons, reason) end
	if coveredTowerWindow then
		table.insert(reasons, 'tower_covered_window')
	elseif towerThreat.highGroundLock then
		table.insert(reasons, 'high_ground_tower_lock')
	elseif towerThreat.active then
		table.insert(reasons, 'tower_threat')
	elseif now < state.towerUntil then
		table.insert(reasons, 'tower_threat_hold')
	end
	if GetHealthPercent(bot) <= 0.12 then table.insert(reasons, 'critical_health') end
	if counterKill.valid then table.insert(reasons, 'counterkill_window') end
	if readyDefense ~= nil and severity >= Retreat.CRITICAL then table.insert(reasons, 'defense_ready') end
	if hasEffectiveControl and controlTarget ~= nil and severity >= Retreat.CRITICAL then table.insert(reasons, 'escape_control_ready') end

	state.severity = severity
	state.desire = severity >= Retreat.HIGH and desire or nil
	state.forceDesire = state.desire ~= nil
	state.reasons = reasons
	return state
end

function Retreat.GetDesire(bot)
	if not Retreat.IsEnabled() then return nil end
	local state = Retreat.GetState(bot)
	if state.forceDesire then return state.desire end
	return nil
end

function Retreat.ShouldYield(bot, severity)
	if not Retreat.IsEnabled() then return false end
	severity = severity or Retreat.HIGH
	if type(severity) == 'string' then severity = Retreat[severity] or Retreat.HIGH end
	return Retreat.GetState(bot).severity >= severity
end

function Retreat.ShouldPrepareDefense(bot, abilityName)
	if abilityName == nil then return false end
	if not Retreat.IsEnabled() then
		if not IsValidUnit(bot)
		or bot:GetActiveMode() ~= BOT_MODE_RETREAT
		or bot:GetActiveModeDesire() < BOT_MODE_DESIRE_VERYHIGH
		or bot:HasModifier('modifier_fountain_aura_buff')
		then
			return false
		end
		return true
	end
	local state = Retreat.GetState(bot)
	return state.severity >= Retreat.CRITICAL
		and Capabilities.IsDefenseReady(state.protection, abilityName)
end

function Retreat.ShouldUseAbility(bot, abilityName, options)
	if not IsValidUnit(bot) or abilityName == nil then return false end
	options = options or {}
	if not Retreat.IsEnabled() then
		local legacyRetreat = bot:GetActiveMode() == BOT_MODE_RETREAT
			and bot:GetActiveModeDesire() >= math.max(
				options.legacyModeDesire or BOT_MODE_DESIRE_VERYHIGH,
				BOT_MODE_DESIRE_VERYHIGH
			)
			and not bot:HasModifier('modifier_fountain_aura_buff')
		local legacyEvasive = options.legacyEvasiveManeuvers
			and bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS
			and bot:WasRecentlyDamagedByAnyHero(2.0)
		return legacyRetreat == true or legacyEvasive == true
	end

	local record = Capabilities.GetRetreatAbilityRecord(abilityName)
	if record == nil
	or record.useStatus == 'SUPPRESSED'
	or record.useStatus == 'COMMENTED_OUT'
	then
		return false
	end

	local severity = math.max(options.severity or Retreat.CRITICAL, Retreat.CRITICAL)
	local legacyRetreat = bot:GetActiveMode() == BOT_MODE_RETREAT
	local legacyModeDesire = math.max(
		options.legacyModeDesire or BOT_MODE_DESIRE_VERYHIGH,
		BOT_MODE_DESIRE_VERYHIGH
	)
	if legacyRetreat then
		legacyRetreat = bot:GetActiveModeDesire() >= legacyModeDesire
			and not bot:HasModifier('modifier_fountain_aura_buff')
	end
	if not legacyRetreat and options.legacyEvasiveManeuvers
	and bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS
	and bot:WasRecentlyDamagedByAnyHero(2.0)
	then
		legacyRetreat = Retreat.GetState(bot).severity >= severity
	end
	if legacyRetreat then return true end

	-- 最终严重度已经包含反杀及高地塔保护窗口；非 CRITICAL 时只撤退走位，不消耗技能。
	return Retreat.GetState(bot).severity >= severity
end

function Retreat.GetControlTarget(bot, castRange, options)
	if not Retreat.IsEnabled() then
		local visibleEnemies, _, _, pursuer = GetEnemyContext(bot)
		return SelectControlTarget(bot, visibleEnemies, castRange, options, pursuer)
	end
	local state = Retreat.GetState(bot)
	return SelectControlTarget(
		bot,
		state.visibleEnemies,
		castRange,
		options,
		state.pursuer
	)
end

function Retreat.GetSeverityName(severity)
	if severity >= Retreat.CRITICAL then return 'CRITICAL' end
	if severity >= Retreat.HIGH then return 'HIGH' end
	if severity >= Retreat.CAUTION then return 'CAUTION' end
	return 'NONE'
end

return Retreat
