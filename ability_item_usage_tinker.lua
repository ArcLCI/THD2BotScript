require(GetScriptDirectory() .. "/thd2_item_usage")

local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")

local YUMEMI_Q = "ability_thdots_yumemi01"
local YUMEMI_W = "ability_thdots_yumemi02"
local YUMEMI_E = "ability_thdots_yumemi03"
local YUMEMI_EX = "ability_thdots_yumemiEx"
local YUMEMI_R = "ability_thdots_yumemi04"

local FLIGHT_MODIFIER = "modifier_thdots_yumemi02_think_interval"
local ULTIMATE_MODIFIER = "modifier_yumemi04_action"
local CROSS_MODIFIER = "modifier_thdots_yumemiEx_passive"
local SHARD_MODIFIER = "modifier_item_aghanims_shard"
local SCEPTER_MODIFIER = "modifier_item_wanbaochui"
local ROOT_MODIFIER = "modifier_item_morenjingjuan_antiblink"
local MOON_AURA_MODIFIER = "modifier_item_yueyaomishi_radiate_regen_mana_aura"

local ACTION_GUARD_TIME = 0.15
local PENDING_FLIGHT_WINDOW = 0.8
local HERO_SCAN_RANGE = 2600
local Q_PROJECTILE_SPEED = 1200
local Q_LINE_RADIUS = 200
local MOON_REGEN_PER_SECOND = 400
local MOON_DURATION = 3

local function SafeCall(object, method, default, ...)
	if object == nil then return default end
	local fn = object[method]
	if type(fn) ~= "function" then return default end
	local ok, result = pcall(fn, object, ...)
	if not ok or result == nil then return default end
	return result
end

local function SafeJ(method, default, ...)
	if J == nil or type(J[method]) ~= "function" then return default end
	local ok, result = pcall(J[method], ...)
	if not ok or result == nil then return default end
	return result
end

local function Now()
	if type(DotaTime) == "function" then return DotaTime() end
	if type(GameTime) == "function" then return GameTime() end
	return 0
end

local function MakeVector(x, y, z)
	if type(Vector) == "function" then return Vector(x, y, z or 0) end
	return { x = x, y = y, z = z or 0 }
end

local function GetLocation(unit)
	return SafeCall(unit, "GetLocation", nil)
end

local function Distance2D(first, second)
	if first == nil or second == nil then return math.huge end
	local dx = (first.x or 0) - (second.x or 0)
	local dy = (first.y or 0) - (second.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function UnitDistance(first, second)
	return Distance2D(GetLocation(first), GetLocation(second))
end

local function LocationTowards(origin, destination, distance)
	if origin == nil or destination == nil then return nil end
	local totalDistance = Distance2D(origin, destination)
	if totalDistance <= 0.01 then return origin end
	local scale = math.min(distance, totalDistance) / totalDistance
	return MakeVector(
		(origin.x or 0) + ((destination.x or 0) - (origin.x or 0)) * scale,
		(origin.y or 0) + ((destination.y or 0) - (origin.y or 0)) * scale,
		origin.z or 0
	)
end

local function LocationAlongDirection(origin, destination, distance)
	if origin == nil or destination == nil then return nil end
	local totalDistance = Distance2D(origin, destination)
	if totalDistance <= 0.01 then return origin end
	local scale = distance / totalDistance
	return MakeVector(
		(origin.x or 0) + ((destination.x or 0) - (origin.x or 0)) * scale,
		(origin.y or 0) + ((destination.y or 0) - (origin.y or 0)) * scale,
		origin.z or 0
	)
end

local function PointToSegmentDistance(point, startLocation, endLocation)
	if point == nil or startLocation == nil or endLocation == nil then return math.huge end
	local vx = (endLocation.x or 0) - (startLocation.x or 0)
	local vy = (endLocation.y or 0) - (startLocation.y or 0)
	local wx = (point.x or 0) - (startLocation.x or 0)
	local wy = (point.y or 0) - (startLocation.y or 0)
	local lengthSquared = vx * vx + vy * vy
	if lengthSquared <= 0.01 then return Distance2D(point, startLocation) end
	local projection = math.max(0, math.min(1, (wx * vx + wy * vy) / lengthSquared))
	local closest = MakeVector(
		(startLocation.x or 0) + vx * projection,
		(startLocation.y or 0) + vy * projection,
		startLocation.z or 0
	)
	return Distance2D(point, closest)
end

local function HasModifier(unit, modifierName)
	return SafeCall(unit, "HasModifier", false, modifierName)
end

local function IsPossibleIllusionSafe(unit)
	if type(IsPossibleIllusion) == "function" then
		local ok, result = pcall(IsPossibleIllusion, unit)
		if ok then return result == true end
	end
	return HasModifier(unit, "modifier_illusion")
		or HasModifier(unit, "modifier_flandre01_illusion_model")
end

local function IsVisibleRealEnemy(bot, enemy)
	if enemy == nil or enemy == bot then return false end
	if not SafeCall(enemy, "IsAlive", false) then return false end
	if not SafeCall(enemy, "IsHero", false) then return false end
	if not SafeCall(enemy, "CanBeSeen", false) then return false end
	if IsPossibleIllusionSafe(enemy) then return false end
	local botTeam = SafeCall(bot, "GetTeam", nil)
	local enemyTeam = SafeCall(enemy, "GetTeam", nil)
	return botTeam == nil or enemyTeam == nil or botTeam ~= enemyTeam
end

local function CanTargetEnemy(bot, enemy)
	return IsVisibleRealEnemy(bot, enemy)
		and not SafeCall(enemy, "IsMagicImmune", true)
		and not SafeCall(enemy, "IsInvulnerable", true)
end

local function GetNearbyHeroes(bot, range, enemy)
	local result = nil
	if type(CachedGetNearbyHeroes) == "function" then
		local ok, value = pcall(CachedGetNearbyHeroes, bot, math.min(range, HERO_SCAN_RANGE), enemy, BOT_MODE_NONE or 0)
		if ok then result = value end
	end
	if result == nil then
		result = SafeCall(bot, "GetNearbyHeroes", {}, math.min(range, HERO_SCAN_RANGE), enemy, BOT_MODE_NONE or 0)
	end
	return result or {}
end

local function GetVisibleEnemies(bot, range)
	local result = {}
	for _, enemy in pairs(GetNearbyHeroes(bot, range, true)) do
		if IsVisibleRealEnemy(bot, enemy) and UnitDistance(bot, enemy) <= range then
			table.insert(result, enemy)
		end
	end
	return result
end

local function GetNearbyAllies(bot, range)
	local result = {}
	for _, ally in pairs(GetNearbyHeroes(bot, range, false)) do
		if ally ~= nil
		and ally ~= bot
		and SafeCall(ally, "IsAlive", false)
		and SafeCall(ally, "IsHero", false)
		and not IsPossibleIllusionSafe(ally)
		and UnitDistance(bot, ally) <= range
		then
			table.insert(result, ally)
		end
	end
	return result
end

local function CountUnitsNearLocation(units, location, radius)
	local count = 0
	for _, unit in pairs(units or {}) do
		if Distance2D(GetLocation(unit), location) <= radius then count = count + 1 end
	end
	return count
end

local function GetHP(unit)
	local maxHealth = SafeCall(unit, "GetMaxHealth", 1)
	if maxHealth <= 0 then return 0 end
	return SafeCall(unit, "GetHealth", 0) / maxHealth
end

local function GetManaPercent(unit)
	local maxMana = SafeCall(unit, "GetMaxMana", 1)
	if maxMana <= 0 then return 0 end
	return SafeCall(unit, "GetMana", 0) / maxMana
end

local function GetSpecialValue(ability, name, default)
	local value = SafeCall(ability, "GetSpecialValueInt", nil, name)
	if value == nil then value = SafeCall(ability, "GetSpecialValueFloat", nil, name) end
	if value == nil then value = SafeCall(ability, "GetSpecialValueFor", nil, name) end
	return value == nil and default or value
end

local function IsAbilityReady(ability)
	return ability ~= nil
		and SafeCall(ability, "GetLevel", 0) > 0
		and SafeCall(ability, "IsFullyCastable", false)
end

local function GetAbility(bot, name)
	return SafeCall(bot, "GetAbilityByName", nil, name)
end

local function GetCrossCount(bot)
	local modifierIndex = SafeCall(bot, "GetModifierByName", -1, CROSS_MODIFIER)
	if type(modifierIndex) ~= "number" or modifierIndex < 0 then return 0 end
	return math.max(0, SafeCall(bot, "GetModifierStackCount", 0, modifierIndex))
end

local function IsGoingOnSomeone(bot)
	if SafeJ("IsGoingOnSomeone", false, bot) then return true end
	local mode = SafeCall(bot, "GetActiveMode", BOT_MODE_NONE or 0)
	return mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_ROAM
		or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_GANK
		or mode == BOT_MODE_DEFEND_ALLY
end

local function IsInTeamFight(bot, radius)
	return SafeJ("IsInTeamFight", false, bot, radius)
end

local function IsSeriouslyRetreatingSafe(bot)
	if type(IsSeriouslyRetreating) == "function" then
		local ok, result = pcall(IsSeriouslyRetreating, bot, YUMEMI_W)
		if ok then return result == true end
	end
	return SafeJ("IsSeriouslyRetreating", false, bot, YUMEMI_W)
end

local function IsAttackWindup(bot)
	return SafeJ("IsAttacking", false, bot)
end

local function GetProperTarget(bot)
	local target = SafeJ("GetProperTarget", nil, bot)
	if IsVisibleRealEnemy(bot, target) then return target end
	target = SafeCall(bot, "GetTarget", nil)
	if IsVisibleRealEnemy(bot, target) then return target end
	target = SafeCall(bot, "GetAttackTarget", nil)
	if IsVisibleRealEnemy(bot, target) then return target end
	return nil
end

local function GetFountainLocation(team)
	if type(GetShopLocation) ~= "function" then return nil end
	local ok, location = pcall(GetShopLocation, team, SHOP_HOME)
	if not ok then return nil end
	return location
end

local function GetEnemyFountainLocation()
	if type(GetOpposingTeam) ~= "function" then return nil end
	local ok, team = pcall(GetOpposingTeam)
	if not ok then return nil end
	return GetFountainLocation(team)
end

local function GetPredictedLocation(target, delay)
	local location = SafeCall(target, "GetExtrapolatedLocation", nil, math.max(0, delay or 0))
	return location or GetLocation(target)
end

local function MarkAction(bot)
	bot.yumemiLastActionTime = Now()
end

local function WasActionJustIssued(bot)
	return Now() - (bot.yumemiLastActionTime or -90) <= ACTION_GUARD_TIME
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

local function EstimateFlightMana(distance, speed, fixedManaPerSecond, manaPercentPerSecond,
	maxMana, upfrontCost, reservePercent, moonRemaining)
	if speed <= 0 then return math.huge end
	local travelTime = math.max(0, distance) / speed
	local grossCost = (upfrontCost or 50)
		+ travelTime * (fixedManaPerSecond + maxMana * manaPercentPerSecond / 100)
	local regenTime = math.min(travelTime, math.max(0, moonRemaining or 0))
	local netCost = math.max(upfrontCost or 50, grossCost - regenTime * MOON_REGEN_PER_SECOND)
	return netCost + maxMana * (reservePercent or 0), travelTime
end

local function ComputeQDamage(baseDamage, maxMana, currentMana, manaStep, bonusPercentPerStep)
	local missingMana = math.max(0, maxMana - currentMana)
	local step = math.max(1, manaStep)
	local multiplierCount = math.floor(missingMana / step)
	return baseDamage * (1 + multiplierCount * bonusPercentPerStep / 100)
end

local function ShouldUseQAtLevel(level, charges, formalFight)
	if level >= 4 then return true end
	return formalFight == true or charges >= 2
end

local function ShouldUseUltimate(isFountain, enemyCount, allyCount, hp, crossCount, inTeamFight,
	allowEmergency, recentlyDamaged)
	if isFountain and enemyCount >= 1 then return true end
	if inTeamFight and enemyCount >= 2 and allyCount >= 1 and (hp >= 0.45 or crossCount >= 2) then
		return true
	end
	return allowEmergency == true
		and recentlyDamaged == true
		and hp <= 0.35
		and enemyCount >= 1
end

local function ShouldMaintainE(hasScepter, gameTime, manaPercent, crossCount)
	if hasScepter then return false end
	if gameTime < 600 then return manaPercent >= 0.75 and crossCount < 1 end
	return manaPercent >= 0.65 and crossCount < 2
end

local function ShouldUseShardDodge(crossCount, hp, hasHeroSpellProjectile, hasAttackProjectile)
	if hasHeroSpellProjectile then return crossCount >= 3 or (hp <= 0.30 and crossCount >= 2) end
	return hasAttackProjectile and hp <= 0.30 and crossCount >= 2
end

local function GetMoonRemaining(bot)
	if not HasModifier(bot, MOON_AURA_MODIFIER) then return 0 end
	local modifierIndex = SafeCall(bot, "GetModifierByName", -1, MOON_AURA_MODIFIER)
	local remaining = SafeCall(bot, "GetModifierRemainingDuration", 0, modifierIndex)
	if remaining > 0 then return remaining end
	return math.max(0, MOON_DURATION - (Now() - (bot.yumemiMoonStoneIssuedAt or Now())))
end

local function GetReadyItem(name)
	if type(IsItemAvailable) ~= "function" then return nil end
	local item = IsItemAvailable(name)
	if item ~= nil and SafeCall(item, "IsFullyCastable", false) then return item end
	return nil
end

local function GetReadyMoonItem()
	return GetReadyItem("item_yueyaomishi") or GetReadyItem("item_yatagarasu")
end

local function IsMuted(bot)
	return SafeCall(bot, "IsMuted", false)
end

local function IsSilenced(bot)
	return SafeCall(bot, "IsSilenced", false)
end

local function UseMoonStone(bot, item)
	-- 只记录下单时刻；后续飞船必须看到真实 aura modifier 才计入回蓝。
	bot.yumemiMoonStoneIssuedAt = Now()
	return UseAbility(bot, item)
end

local function IsHardControlled(enemy)
	return SafeCall(enemy, "IsStunned", false)
		or SafeCall(enemy, "IsHexed", false)
		or SafeCall(enemy, "IsRooted", false)
		or HasModifier(enemy, ROOT_MODIFIER)
end

local function TryUseShardDodge(bot, abilityEx)
	if IsSilenced(bot)
	or not HasModifier(bot, SHARD_MODIFIER)
	or not IsAbilityReady(abilityEx)
	then
		return false
	end
	local projectiles = SafeCall(bot, "GetIncomingTrackingProjectiles", {})
	local heroSpellProjectile = false
	local attackProjectile = false
	for _, projectile in pairs(projectiles) do
		local caster = projectile.caster
		if IsVisibleRealEnemy(bot, caster) then
			if projectile.ability ~= nil then heroSpellProjectile = true end
			if projectile.is_attack == true or projectile.ability == nil then attackProjectile = true end
		end
	end
	if ShouldUseShardDodge(GetCrossCount(bot), GetHP(bot), heroSpellProjectile, attackProjectile) then
		return UseAbility(bot, abilityEx)
	end
	return false
end

local function GetFlightValues(bot, ability, distance, reservePercent)
	local speed = GetSpecialValue(ability, "move_speed", 0)
	local fixedMana = GetSpecialValue(ability, "mana_cost", 0)
	local manaPercent = GetSpecialValue(ability, "mana_cost_percent", 10)
	local maxMana = SafeCall(bot, "GetMaxMana", 0)
	local upfrontCost = SafeCall(ability, "GetManaCost", 50)
	if upfrontCost <= 0 then upfrontCost = 50 end
	local required, travelTime = EstimateFlightMana(distance, speed, fixedMana, manaPercent,
		maxMana, upfrontCost, reservePercent, GetMoonRemaining(bot))
	return required, travelTime, speed, fixedMana, manaPercent, maxMana, upfrontCost
end

local function BuildRetreatFlightPlan(bot, ability)
	if not IsAbilityReady(ability) or IsSilenced(bot) then return nil end
	if type(IsYugi04NoDisplacementActive) == "function" and IsYugi04NoDisplacementActive(bot) then return nil end
	if not IsSeriouslyRetreatingSafe(bot) then return nil end
	local origin = GetLocation(bot)
	local fountain = GetFountainLocation(SafeCall(bot, "GetTeam", nil))
	if origin == nil or fountain == nil then return nil end
	local fountainDistance = Distance2D(origin, fountain)
	if fountainDistance < 300 then return nil end
	local level = SafeCall(ability, "GetLevel", 0)
	local maxDistance = 600 + level * 250
	local distance = math.min(maxDistance, fountainDistance)
	return {
		kind = "retreat",
		location = LocationTowards(origin, fountain, distance),
		distance = distance,
		reservePercent = 0.08,
	}
end

local function BuildOffensiveFlightPlan(bot, ability, enemies, targetOverride)
	if not IsAbilityReady(ability) or IsSilenced(bot) or not IsGoingOnSomeone(bot) then return nil end
	if type(IsYugi04NoDisplacementActive) == "function" and IsYugi04NoDisplacementActive(bot) then return nil end
	if SafeCall(bot, "GetActiveModeDesire", 0) < (BOT_MODE_DESIRE_HIGH or 0.6) then return nil end
	local target = targetOverride or GetProperTarget(bot)
	if not CanTargetEnemy(bot, target) then return nil end
	local origin = GetLocation(bot)
	local targetLocation = GetLocation(target)
	if origin == nil or targetLocation == nil then return nil end
	local level = SafeCall(ability, "GetLevel", 0)
	local maxDistance = 600 + level * 250
	local distance = Distance2D(origin, targetLocation)
	local hasScepter = HasModifier(bot, SCEPTER_MODIFIER)
	local minimumDistance = hasScepter and 801 or 500
	if distance < minimumDistance or distance > maxDistance then return nil end
	if not hasScepter and GetHP(target) > 0.30 then return nil end
	if hasScepter and GetHP(bot) < 0.55 then return nil end

	local speed = GetSpecialValue(ability, "move_speed", 0)
	if speed <= 0 then return nil end
	local predicted = GetPredictedLocation(target, math.min(1.5, distance / speed))
	local location = LocationTowards(origin, predicted, maxDistance)
	local actualDistance = Distance2D(origin, location)
	if hasScepter and actualDistance <= 800 then return nil end
	local enemyFountain = GetEnemyFountainLocation()
	if enemyFountain ~= nil and Distance2D(location, enemyFountain) < 1600 then return nil end
	for _, tower in pairs(SafeCall(bot, "GetNearbyTowers", {}, maxDistance + 1200, true)) do
		local attackRange = SafeCall(tower, "GetAttackRange", 900)
		if SafeCall(tower, "IsAlive", false)
		and SafeCall(tower, "CanBeSeen", false)
		and Distance2D(GetLocation(tower), location) <= attackRange + 150
		then
			return nil
		end
	end

	if hasScepter then
		local visibleEnemyCount = CountUnitsNearLocation(enemies, location, 900)
		local allyCount = 1 + CountUnitsNearLocation(GetNearbyAllies(bot, HERO_SCAN_RANGE), location, 900)
		if allyCount < visibleEnemyCount then return nil end
	end
	return {
		kind = "offense",
		target = target,
		location = location,
		distance = actualDistance,
		reservePercent = 0.20,
	}
end

local function StorePendingFlight(bot, plan)
	bot.yumemiPendingFlight = {
		kind = plan.kind,
		target = plan.target,
		expires = Now() + PENDING_FLIGHT_WINDOW,
	}
end

local function TryPrepareFlight(bot, ability, abilityEx, plan)
	local _, _, speed, fixedMana, manaPercent, maxMana, upfrontCost =
		GetFlightValues(bot, ability, plan.distance, plan.reservePercent)
	local currentMana = SafeCall(bot, "GetMana", 0)
	if not IsMuted(bot) and GetMoonRemaining(bot) <= 0.05 then
		local moonItem = GetReadyMoonItem()
		if moonItem ~= nil then
			local moonRequired = EstimateFlightMana(plan.distance, speed, fixedMana, manaPercent,
				maxMana, upfrontCost, plan.reservePercent, MOON_DURATION)
			if currentMana >= moonRequired then
				StorePendingFlight(bot, plan)
				return UseMoonStone(bot, moonItem)
			end
		end
	end
	if plan.kind == "retreat"
	and not IsSilenced(bot)
	and HasModifier(bot, SHARD_MODIFIER)
	and IsAbilityReady(abilityEx)
	and GetCrossCount(bot) >= 2
	then
		local requiredWithoutMoon = EstimateFlightMana(plan.distance, speed, fixedMana, manaPercent,
			maxMana, upfrontCost, plan.reservePercent, 0)
		local restorePercent = GetSpecialValue(abilityEx, "mana_restore_pct", 10)
		if currentMana < requiredWithoutMoon
		and currentMana + maxMana * restorePercent / 100 >= requiredWithoutMoon
		then
			StorePendingFlight(bot, plan)
			return UseAbility(bot, abilityEx)
		end
	end
	return false
end

local function TryExecuteFlightPlan(bot, ability, abilityEx, plan)
	if plan == nil then return false end
	local requiredMana = GetFlightValues(bot, ability, plan.distance, plan.reservePercent)
	if SafeCall(bot, "GetMana", 0) >= requiredMana then
		bot.yumemiPendingFlight = nil
		return UseAbilityOnLocation(bot, ability, plan.location)
	end
	return TryPrepareFlight(bot, ability, abilityEx, plan)
end

local function TryPendingFlight(bot, ability, abilityEx, enemies)
	local pending = bot.yumemiPendingFlight
	if pending == nil then return false end
	if Now() > (pending.expires or -90) then
		bot.yumemiPendingFlight = nil
		return false
	end
	local plan = nil
	if pending.kind == "retreat" then
		plan = BuildRetreatFlightPlan(bot, ability)
	else
		plan = BuildOffensiveFlightPlan(bot, ability, enemies, pending.target)
	end
	if plan == nil then
		bot.yumemiPendingFlight = nil
		return false
	end
	local requiredMana = GetFlightValues(bot, ability, plan.distance, plan.reservePercent)
	if SafeCall(bot, "GetMana", 0) < requiredMana then return false end
	bot.yumemiPendingFlight = nil
	return UseAbilityOnLocation(bot, ability, plan.location)
end

local function IsRecentPursuer(bot, enemy)
	if SafeCall(bot, "WasRecentlyDamagedByHero", false, enemy, 2.0) then return true end
	if SafeCall(enemy, "GetAttackTarget", nil) == bot then return true end
	return SafeJ("IsChasingTarget", false, enemy, bot)
end

local function TryUseMorenjingjuan(bot, enemies, retreatOnly)
	if IsMuted(bot) then return false end
	local item = GetReadyItem("item_morenjingjuan")
	if item == nil then return false end
	local reportedRange = SafeCall(item, "GetCastRange", 600)
	local castRange = reportedRange > 0 and math.min(600, reportedRange) or 600
	local target = nil
	local closestDistance = math.huge
	if retreatOnly then
		for _, enemy in pairs(enemies) do
			local distance = UnitDistance(bot, enemy)
			if distance <= castRange
			and distance < closestDistance
			and CanTargetEnemy(bot, enemy)
			and not IsHardControlled(enemy)
			and IsRecentPursuer(bot, enemy)
			then
				target = enemy
				closestDistance = distance
			end
		end
	else
		if not IsGoingOnSomeone(bot)
		or SafeCall(bot, "GetActiveModeDesire", 0) < (BOT_MODE_DESIRE_HIGH or 0.6)
		then
			return false
		end
		target = GetProperTarget(bot)
		if not CanTargetEnemy(bot, target)
		or UnitDistance(bot, target) > castRange
		or IsHardControlled(target)
		then
			target = nil
		end
	end
	if target ~= nil then return UseAbilityOnEntity(bot, item, target) end
	return false
end

local function TryUseUltimate(bot, ability, enemies, allowEmergency)
	if IsSilenced(bot) or not IsAbilityReady(ability) then return false end
	local radius = SafeCall(ability, "GetAOERadius", 0)
	if radius <= 0 then radius = GetSpecialValue(ability, "radius", 1000) end
	if radius <= 0 then radius = 1000 end
	local commitRadius = math.min(800, radius * 0.65)
	local commitEnemies = 0
	local fountainEnemies = 0
	for _, enemy in pairs(enemies) do
		if UnitDistance(bot, enemy) <= commitRadius then commitEnemies = commitEnemies + 1 end
		if UnitDistance(bot, enemy) <= radius then fountainEnemies = fountainEnemies + 1 end
	end
	local allies = GetNearbyAllies(bot, 900)
	local isFountain = HasModifier(bot, "modifier_fountain_aura_buff")
	local recentlyDamaged = SafeCall(bot, "WasRecentlyDamagedByAnyHero", false, 1.5)
	local evaluatedEnemyCount = isFountain and fountainEnemies or commitEnemies
	if ShouldUseUltimate(isFountain, evaluatedEnemyCount, #allies, GetHP(bot), GetCrossCount(bot),
		IsInTeamFight(bot, 1200), allowEmergency, recentlyDamaged)
	then
		return UseAbility(bot, ability)
	end
	return false
end

local function GetQDamage(bot, ability)
	return ComputeQDamage(
		SafeCall(ability, "GetAbilityDamage", 0),
		SafeCall(bot, "GetMaxMana", 0),
		SafeCall(bot, "GetMana", 0),
		GetSpecialValue(ability, "damage_mult_per_mana", 100),
		GetSpecialValue(ability, "damage_mana_mult", 4)
	)
end

local function GetQRange(ability)
	local range = SafeCall(ability, "GetCastRange", 1000)
	if range <= 0 then return 1000 end
	return math.min(1000, range)
end

local function GetQCandidateScore(bot, ability, enemies, target, predicted, properTarget, killOnly)
	local origin = GetLocation(bot)
	local range = GetQRange(ability)
	local castEnd = LocationAlongDirection(origin, predicted, range)
	local hitCount = 0
	for _, enemy in pairs(enemies) do
		local enemyDistance = UnitDistance(bot, enemy)
		local delay = SafeCall(ability, "GetCastPoint", 0.1) + enemyDistance / Q_PROJECTILE_SPEED
		local enemyLocation = GetPredictedLocation(enemy, delay)
		if PointToSegmentDistance(enemyLocation, origin, castEnd) <= Q_LINE_RADIUS then
			hitCount = hitCount + 1
		end
	end
	-- 预计命中人数是首要目标，正确目标只用于同命中数时打破平局。
	local score = hitCount * 100
	if target == properTarget then score = score + 30 end
	if killOnly then score = score + 100 end
	return score, hitCount
end

local function SelectQTarget(bot, ability, enemies, killOnly)
	local properTarget = GetProperTarget(bot)
	local range = GetQRange(ability)
	local damage = GetQDamage(bot, ability)
	local bestLocation = nil
	local bestTarget = nil
	local bestScore = -1
	for _, enemy in pairs(enemies) do
		if CanTargetEnemy(bot, enemy) and UnitDistance(bot, enemy) <= range then
			local canKill = damage >= SafeCall(enemy, "GetHealth", math.huge)
			if not killOnly or canKill then
				local delay = SafeCall(ability, "GetCastPoint", 0.1) + UnitDistance(bot, enemy) / Q_PROJECTILE_SPEED
				local predicted = GetPredictedLocation(enemy, delay)
				local score = GetQCandidateScore(bot, ability, enemies, enemy, predicted, properTarget, killOnly)
				if score > bestScore then
					bestScore = score
					bestLocation = LocationTowards(GetLocation(bot), predicted, range)
					bestTarget = enemy
				end
			end
		end
	end
	return bestLocation, bestTarget
end

local function GetAbilityCharges(ability)
	return math.max(0, SafeCall(ability, "GetCurrentCharges", 2))
end

local function GetNearbyLaneCreeps(bot, range)
	return SafeCall(bot, "GetNearbyLaneCreeps", {}, range, true) or {}
end

local function SelectCreepLine(bot, ability, creeps)
	local origin = GetLocation(bot)
	local range = GetQRange(ability)
	local bestLocation = nil
	local bestCount = 0
	for _, creep in pairs(creeps) do
		if SafeCall(creep, "IsAlive", false) and UnitDistance(bot, creep) <= range then
			local location = GetLocation(creep)
			local castEnd = LocationAlongDirection(origin, location, range)
			local count = 0
			for _, other in pairs(creeps) do
				if SafeCall(other, "IsAlive", false)
				and PointToSegmentDistance(GetLocation(other), origin, castEnd) <= Q_LINE_RADIUS
				then
					count = count + 1
				end
			end
			if count > bestCount then
				bestCount = count
				bestLocation = location
			end
		end
	end
	return bestLocation, bestCount
end

local function GetSafeCrossLocation(bot, range)
	local origin = GetLocation(bot)
	local fountain = GetFountainLocation(SafeCall(bot, "GetTeam", nil))
	if origin == nil or fountain == nil then return nil end
	return LocationTowards(origin, fountain, range)
end

local function TryUseQ(bot, ability, enemies, killOnly)
	if IsSilenced(bot) or not IsAbilityReady(ability) or IsAttackWindup(bot) then return false end
	local castLocation = SelectQTarget(bot, ability, enemies, killOnly)
	if castLocation ~= nil then
		if killOnly then return UseAbilityOnLocation(bot, ability, castLocation) end
		local formalFight = IsGoingOnSomeone(bot) or IsInTeamFight(bot, 1200)
		if ShouldUseQAtLevel(SafeCall(ability, "GetLevel", 0), GetAbilityCharges(ability), formalFight) then
			return UseAbilityOnLocation(bot, ability, castLocation)
		end
	end
	return false
end

local function TryUseQUtility(bot, ability, enemies)
	if IsSilenced(bot)
	or not IsAbilityReady(ability)
	or IsAttackWindup(bot)
	or HasModifier(bot, "modifier_fountain_aura_buff")
	or GetAbilityCharges(ability) < 2
	then
		return false
	end
	if SelectQTarget(bot, ability, enemies, false) ~= nil then return false end
	local manaPercent = GetManaPercent(bot)
	local range = GetQRange(ability)
	if manaPercent >= 0.70 then
		local creepLocation, creepCount = SelectCreepLine(bot, ability, GetNearbyLaneCreeps(bot, range))
		if creepLocation ~= nil and creepCount >= 3 then
			return UseAbilityOnLocation(bot, ability, creepLocation)
		end
	end
	if HasModifier(bot, SCEPTER_MODIFIER)
	and manaPercent >= 0.75
	and GetCrossCount(bot) < 2
	then
		local safeLocation = GetSafeCrossLocation(bot, range)
		if safeLocation ~= nil then return UseAbilityOnLocation(bot, ability, safeLocation) end
	end
	return false
end

local function TryUseE(bot, ability, enemies, retreating, allowUtility)
	if IsSilenced(bot) or not IsAbilityReady(ability) then return false end
	if SafeCall(bot, "GetActiveMode", BOT_MODE_NONE or 0) == BOT_MODE_OUTPOST then return false end
	local closeEnemies = {}
	local delay = GetSpecialValue(ability, "delay", 1.0)
	for _, enemy in pairs(enemies) do
		if CanTargetEnemy(bot, enemy)
		and UnitDistance(bot, enemy) <= 300
		and Distance2D(GetPredictedLocation(enemy, delay), GetLocation(bot)) <= 300
		then
			table.insert(closeEnemies, enemy)
		end
	end
	if #closeEnemies >= 2 then return UseAbility(bot, ability) end
	for _, enemy in pairs(closeEnemies) do
		if retreating and IsRecentPursuer(bot, enemy) then return UseAbility(bot, ability) end
		if IsGoingOnSomeone(bot) and (UnitDistance(bot, enemy) <= 240 or IsHardControlled(enemy)) then
			return UseAbility(bot, ability)
		end
	end
	if not allowUtility then return false end
	if IsAttackWindup(bot) then return false end
	if #GetVisibleEnemies(bot, 850) > 0 then return false end
	local creeps = GetNearbyLaneCreeps(bot, 300)
	local aliveCreeps = 0
	for _, creep in pairs(creeps) do
		if SafeCall(creep, "IsAlive", false) then aliveCreeps = aliveCreeps + 1 end
	end
	if aliveCreeps >= 3 then return UseAbility(bot, ability) end
	if not HasModifier(bot, "modifier_fountain_aura_buff")
	and ShouldMaintainE(HasModifier(bot, SCEPTER_MODIFIER), Now(), GetManaPercent(bot), GetCrossCount(bot))
	then
		return UseAbility(bot, ability)
	end
	return false
end

local function TryUseMoonStone(bot)
	if IsMuted(bot) or HasModifier(bot, "modifier_fountain_aura_buff") then return false end
	local item = GetReadyMoonItem()
	if item == nil then return false end
	local maxMana = SafeCall(bot, "GetMaxMana", 0)
	local currentMana = SafeCall(bot, "GetMana", 0)
	local shouldUse = GetManaPercent(bot) <= 0.35 or maxMana - currentMana >= 900
	if not shouldUse and IsInTeamFight(bot, 1200) then
		local lowManaAllies = 0
		local totalMissingMana = math.max(0, maxMana - currentMana)
		for _, ally in pairs(GetNearbyAllies(bot, 1000)) do
			local allyMaxMana = SafeCall(ally, "GetMaxMana", 0)
			local allyMana = SafeCall(ally, "GetMana", 0)
			if allyMaxMana > 0 and allyMana / allyMaxMana <= 0.60 then
				lowManaAllies = lowManaAllies + 1
				totalMissingMana = totalMissingMana + allyMaxMana - allyMana
			end
		end
		shouldUse = lowManaAllies >= 2 and totalMissingMana >= 1200
	end
	if shouldUse then return UseMoonStone(bot, item) end
	return false
end

local function TryUseShardMana(bot, abilityEx)
	if IsSilenced(bot)
	or HasModifier(bot, "modifier_fountain_aura_buff")
	or not HasModifier(bot, SHARD_MODIFIER)
	or not IsAbilityReady(abilityEx)
	or GetCrossCount(bot) < 3
	then
		return false
	end
	local maxMana = SafeCall(bot, "GetMaxMana", 0)
	local currentMana = SafeCall(bot, "GetMana", 0)
	local restorePercent = GetSpecialValue(abilityEx, "mana_restore_pct", 10)
	-- 非紧急回蓝必须完整利用 10% 最大蓝量，避免用两枚防御资源换少量蓝量。
	if maxMana - currentMana >= maxMana * restorePercent / 100 then
		return UseAbility(bot, abilityEx)
	end
	return false
end

function AbilityUsageThink()
	if type(IsBotAwake) == "function" and not IsBotAwake() then return end
	local bot = GetBot()
	if bot == nil or not SafeCall(bot, "IsAlive", false) then return end
	if HasModifier(bot, FLIGHT_MODIFIER) or HasModifier(bot, ULTIMATE_MODIFIER) then return end
	if WasActionJustIssued(bot) or SafeJ("CanNotUseAction", false, bot) then return end

	local abilityQ = GetAbility(bot, YUMEMI_Q)
	local abilityW = GetAbility(bot, YUMEMI_W)
	local abilityE = GetAbility(bot, YUMEMI_E)
	local abilityEx = GetAbility(bot, YUMEMI_EX)
	local abilityR = GetAbility(bot, YUMEMI_R)
	local enemies = GetVisibleEnemies(bot, HERO_SCAN_RANGE)

	-- 灵异珠的弹道躲避必须先于任何常规输出。
	if TryUseShardDodge(bot, abilityEx) then return end
	if TryPendingFlight(bot, abilityW, abilityEx, enemies) then return end
	-- 预充能后的短窗口内保留飞船计划，避免 Q 抢走刚恢复的蓝量。
	if bot.yumemiPendingFlight ~= nil then return end

	local retreating = IsSeriouslyRetreatingSafe(bot)
	if retreating then
		if TryExecuteFlightPlan(bot, abilityW, abilityEx, BuildRetreatFlightPlan(bot, abilityW)) then return end
		if TryUseMorenjingjuan(bot, enemies, true) then return end
		if TryUseUltimate(bot, abilityR, enemies, true) then return end
	end

	if TryUseQ(bot, abilityQ, enemies, true) then return end
	if TryUseUltimate(bot, abilityR, enemies, false) then return end
	if TryUseMorenjingjuan(bot, enemies, false) then return end
	if TryExecuteFlightPlan(bot, abilityW, abilityEx, BuildOffensiveFlightPlan(bot, abilityW, enemies)) then return end
	if TryUseE(bot, abilityE, enemies, retreating, false) then return end

	-- Q 满级后不保留充能，但必须避开普攻前摇和前面的关键动作。
	if not HasModifier(bot, "modifier_fountain_aura_buff")
	and TryUseQ(bot, abilityQ, enemies, false)
	then
		return
	end
	if TryUseMoonStone(bot) then return end
	if TryUseShardMana(bot, abilityEx) then return end
	if TryUseE(bot, abilityE, enemies, retreating, true) then return end
	if TryUseQUtility(bot, abilityQ, enemies) then return end
	if type(ConsiderNeutralItems) == "function" then ConsiderNeutralItems() end
end

if YUMEMI_BOT_TEST_EXPORTS then
	YumemiBotTest = {
		EstimateFlightMana = EstimateFlightMana,
		ComputeQDamage = ComputeQDamage,
		ShouldUseQAtLevel = ShouldUseQAtLevel,
		ShouldUseUltimate = ShouldUseUltimate,
		ShouldMaintainE = ShouldMaintainE,
		ShouldUseShardDodge = ShouldUseShardDodge,
		PointToSegmentDistance = PointToSegmentDistance,
	}
end
