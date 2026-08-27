local Flight = {}

Flight.ROUTE = 'yumemi_w'
Flight.ABILITY_NAME = 'ability_thdots_yumemi02'
Flight.ACTIVE_MODIFIER = 'modifier_thdots_yumemi02_think_interval'
Flight.SCEPTER_MODIFIER = 'modifier_item_wanbaochui'
Flight.MOON_AURA_MODIFIER = 'modifier_item_yueyaomishi_radiate_regen_mana_aura'
Flight.RESERVE_PERCENT = 0.20
Flight.SCEPTER_RESERVE_PERCENT = 0.12
Flight.MIN_TIME_SAVING = 0.50
Flight.SCEPTER_TIME_TOLERANCE = 0.35
Flight.SCEPTER_CANDIDATE_BIAS = 0.35
Flight.SCEPTER_MIN_HEALTH = 0.45
Flight.CAST_START_GRACE = 0.80
Flight.TARGET_REACQUIRE_GRACE = 2.0
Flight.LANDING_OBSERVED_RADIUS = 350
Flight.MOON_DURATION = 3.0
Flight.MOON_MIN_HERO_LEVEL = 12
Flight.MOON_MIN_ABILITY_LEVEL = 3
Flight.MOON_MIN_FLIGHT_DURATION = 1.4
Flight.MOON_POST_LANDING_TIME = 0.6
Flight.MOON_ACTIVATION_BUFFER_PERCENT = 0.05
Flight.MOON_RETRY_INTERVAL = 0.25
Flight.MOON_MAX_ORDERS = 2

local MOON_REGEN_PER_SECOND = 400
local ENEMY_FOUNTAIN_REJECT_RADIUS = 1600
local MOON_ITEM_NAME = 'item_yueyaomishi'

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok and value ~= nil then return value end
	return defaultValue
end

local function GetLocation(unit)
	if unit == nil or unit.GetLocation == nil then return nil end
	return Safe(nil, function() return unit:GetLocation() end)
end

local function Distance2D(first, second)
	if first == nil or second == nil then return math.huge end
	local dx = (first.x or 0) - (second.x or 0)
	local dy = (first.y or 0) - (second.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function GetHealthFraction(unit)
	local maxHealth = Safe(0, function() return unit:GetMaxHealth() end)
	if maxHealth <= 0 then return 0 end
	return Safe(0, function() return unit:GetHealth() end) / maxHealth
end

local function HasModifier(unit, modifierName)
	return unit ~= nil and unit.HasModifier ~= nil
		and Safe(false, function() return unit:HasModifier(modifierName) end) == true
end

local function IsValidTarget(bot, target)
	if target == nil or target == bot then return false end
	if target.IsNull ~= nil and Safe(true, function() return target:IsNull() end) then return false end
	if target.CanBeSeen == nil or not Safe(false, function() return target:CanBeSeen() end) then return false end
	if target.IsAlive ~= nil and not Safe(false, function() return target:IsAlive() end) then return false end
	if target.IsHero == nil or not Safe(false, function() return target:IsHero() end) then return false end
	if target.IsKnownIllusion ~= nil and Safe(false, function() return target:IsKnownIllusion() end) then return false end
	if HasModifier(target, 'modifier_illusion') then return false end
	if target.IsMagicImmune ~= nil and Safe(false, function() return target:IsMagicImmune() end) then return false end
	if target.IsInvulnerable ~= nil and Safe(false, function() return target:IsInvulnerable() end) then return false end
	local botTeam = Safe(nil, function() return bot:GetTeam() end)
	local targetTeam = Safe(nil, function() return target:GetTeam() end)
	return botTeam == nil or targetTeam == nil or botTeam ~= targetTeam
end

local function GetSpecialValue(ability, name, defaultValue)
	local value = nil
	if ability.GetSpecialValueInt ~= nil then
		value = Safe(nil, function() return ability:GetSpecialValueInt(name) end)
	end
	if value == nil and ability.GetSpecialValueFloat ~= nil then
		value = Safe(nil, function() return ability:GetSpecialValueFloat(name) end)
	end
	if value == nil and ability.GetSpecialValueFor ~= nil then
		value = Safe(nil, function() return ability:GetSpecialValueFor(name) end)
	end
	return value == nil and defaultValue or value
end

local function GetMoonRemaining(bot)
	if not HasModifier(bot, Flight.MOON_AURA_MODIFIER) then return 0 end
	if bot.GetModifierByName == nil or bot.GetModifierRemainingDuration == nil then return 0 end
	local index = Safe(-1, function() return bot:GetModifierByName(Flight.MOON_AURA_MODIFIER) end)
	if type(index) ~= 'number' or index < 0 then return 0 end
	return math.max(0, Safe(0, function() return bot:GetModifierRemainingDuration(index) end))
end

local function GetEnemyFountainLocation()
	if type(GetOpposingTeam) ~= 'function' or type(GetShopLocation) ~= 'function' or SHOP_HOME == nil then
		return nil
	end
	local team = Safe(nil, function() return GetOpposingTeam() end)
	if team == nil then return nil end
	return Safe(nil, function() return GetShopLocation(team, SHOP_HOME) end)
end

function Flight.EstimateMana(distance, speed, fixedManaPerSecond, manaPercentPerSecond,
	maxMana, upfrontCost, reservePercent, moonRemaining)
	if speed <= 0 then return math.huge end
	local flightDuration = math.max(0, distance) / speed
	local grossCost = (upfrontCost or 50)
		+ flightDuration * (fixedManaPerSecond + maxMana * manaPercentPerSecond / 100)
	local regenDuration = math.min(flightDuration, math.max(0, moonRemaining or 0))
	local netCost = math.max(upfrontCost or 50, grossCost - regenDuration * MOON_REGEN_PER_SECOND)
	return netCost + maxMana * (reservePercent or 0), flightDuration
end

function Flight.GetAbility(bot)
	if bot == nil or bot.GetAbilityByName == nil then return nil end
	return Safe(nil, function() return bot:GetAbilityByName(Flight.ABILITY_NAME) end)
end

function Flight.IsActive(bot)
	return HasModifier(bot, Flight.ACTIVE_MODIFIER)
end

function Flight.GetReadyMoonItem(bot)
	if bot == nil or bot.GetItemInSlot == nil then return nil end
	for slot = 0, 5 do
		local item = Safe(nil, function() return bot:GetItemInSlot(slot) end)
		if item ~= nil then
			local name = Safe(nil, function()
				if item.GetName ~= nil then return item:GetName() end
				if item.GetAbilityName ~= nil then return item:GetAbilityName() end
				return nil
			end)
			if name == MOON_ITEM_NAME
				and Safe(false, function() return item:IsFullyCastable() end)
			then
				return item
			end
		end
	end
	return nil
end

function Flight.BuildScheduledMoonPlan(bot, ability, flightDuration, drainPerSecond, upfrontCost, reserveMana)
	if bot == nil or ability == nil or flightDuration < Flight.MOON_MIN_FLIGHT_DURATION then return nil end
	if Safe(0, function() return bot:GetLevel() end) < Flight.MOON_MIN_HERO_LEVEL
		or Safe(0, function() return ability:GetLevel() end) < Flight.MOON_MIN_ABILITY_LEVEL
		or GetMoonRemaining(bot) > 0
	then
		return nil
	end
	local item = Flight.GetReadyMoonItem(bot)
	if item == nil or drainPerSecond <= 0 then return nil end

	local currentMana = Safe(0, function() return bot:GetMana() end)
	local maxMana = Safe(0, function() return bot:GetMaxMana() end)
	local activationBuffer = maxMana * Flight.MOON_ACTIVATION_BUFFER_PERCENT
	local desiredDelay = math.max(0.10,
		flightDuration - (Flight.MOON_DURATION - Flight.MOON_POST_LANDING_TIME))
	local latestAffordableDelay = math.max(0,
		(currentMana - upfrontCost - activationBuffer) / drainPerSecond)
	local activationDelay = math.min(desiredDelay, latestAffordableDelay)
	if activationDelay < 0.05 then return nil end

	local flightRegenDuration = math.min(Flight.MOON_DURATION,
		math.max(0, flightDuration - activationDelay))
	local postLandingDuration = math.max(0, Flight.MOON_DURATION - flightRegenDuration)
	local landingRequirement = upfrontCost + flightDuration * drainPerSecond
		- flightRegenDuration * MOON_REGEN_PER_SECOND + reserveMana
	local activationRequirement = upfrontCost + activationDelay * drainPerSecond + activationBuffer
	local requiredMana = math.max(upfrontCost, landingRequirement, activationRequirement)
	if currentMana < requiredMana then return nil end

	return {
		itemName = MOON_ITEM_NAME,
		activationDelay = activationDelay,
		flightRegenDuration = flightRegenDuration,
		postLandingDuration = postLandingDuration,
		requiredMana = requiredMana,
	}
end

function Flight.ArmScheduledMoon(bot, plan, now)
	if bot == nil or plan == nil or plan.flightMoonDuringFlight ~= true then return false end
	bot.yumemiFlightMoonSchedule = {
		armedAt = now or 0,
		flightStartedAt = nil,
		activationDelay = plan.flightMoonActivationDelay or 0,
		flightDuration = plan.flightDuration or plan.flightMoonFlightDuration or 0,
		itemName = plan.flightMoonItemName or MOON_ITEM_NAME,
		orderCount = 0,
		lastOrderTime = -90,
		observed = false,
	}
	return true
end

function Flight.ClearScheduledMoon(bot)
	if bot ~= nil then bot.yumemiFlightMoonSchedule = nil end
end

function Flight.TryUseScheduledMoon(bot, now)
	local state = bot ~= nil and bot.yumemiFlightMoonSchedule or nil
	if state == nil then return false, 'none' end
	local currentTime = now or 0
	if not Flight.IsActive(bot) then
		if currentTime - (state.armedAt or currentTime) > Flight.CAST_START_GRACE then
			Flight.ClearScheduledMoon(bot)
			return false, 'flight_not_started'
		end
		return false, 'waiting_flight'
	end
	if state.flightStartedAt == nil then state.flightStartedAt = currentTime end
	if HasModifier(bot, Flight.MOON_AURA_MODIFIER) then
		state.observed = true
		return false, 'observed'
	end
	if currentTime - (state.flightStartedAt or currentTime) < (state.activationDelay or 0) then
		return false, 'waiting_activation'
	end
	if state.orderCount >= Flight.MOON_MAX_ORDERS then return false, 'orders_exhausted' end
	if currentTime - (state.lastOrderTime or -90) < Flight.MOON_RETRY_INTERVAL then
		return false, 'retry_wait'
	end
	local item = Flight.GetReadyMoonItem(bot)
	if item == nil then
		return false, state.orderCount > 0 and 'accepted_unobserved' or 'item_unavailable'
	end
	if bot.Action_UseAbility == nil then return false, 'action_unavailable' end
	bot:Action_UseAbility(item)
	state.orderCount = state.orderCount + 1
	state.lastOrderTime = currentTime
	return true, 'ordered'
end

function Flight.SelectRoute(walkTime, tpPlan, flightPlan)
	local route = 'walk'
	local travelTime = walkTime
	if tpPlan ~= nil and tpPlan.travelTime < travelTime then
		route = 'tp'
		travelTime = tpPlan.travelTime
	end
	local preferFlight = flightPlan ~= nil
		and ((flightPlan.hasScepter == true
			and flightPlan.travelTime <= travelTime + Flight.SCEPTER_TIME_TOLERANCE)
			or (flightPlan.hasScepter ~= true
				and flightPlan.travelTime + Flight.MIN_TIME_SAVING < travelTime))
	if preferFlight then
		route = Flight.ROUTE
		travelTime = flightPlan.travelTime
	end
	return route, travelTime
end

function Flight.BuildPlan(bot, target, options)
	options = options or {}
	if bot == nil or Safe(nil, function() return bot:GetUnitName() end) ~= 'npc_dota_hero_tinker' then
		return nil, 'not_yumemi'
	end
	if not IsValidTarget(bot, target) then return nil, 'target_invalid' end
	if Safe(false, function() return bot:IsSilenced() end) then return nil, 'silenced' end
	if type(IsYugi04NoDisplacementActive) == 'function'
		and Safe(false, function() return IsYugi04NoDisplacementActive(bot) end)
	then
		return nil, 'displacement_blocked'
	end

	local ability = Flight.GetAbility(bot)
	if ability == nil
		or Safe(0, function() return ability:GetLevel() end) <= 0
		or not Safe(false, function() return ability:IsFullyCastable() end)
	then
		return nil, 'ability_unavailable'
	end

	local origin = GetLocation(bot)
	local observedTargetLocation = GetLocation(target)
	if origin == nil or observedTargetLocation == nil then return nil, 'location_unknown' end
	local speed = GetSpecialValue(ability, 'move_speed', 0)
	if speed <= 0 then return nil, 'speed_unknown' end

	local initialDistance = Distance2D(origin, observedTargetLocation)
	local initialDuration = initialDistance / speed
	local flightLocation = observedTargetLocation
	if target.GetExtrapolatedLocation ~= nil then
		flightLocation = Safe(observedTargetLocation, function()
			return target:GetExtrapolatedLocation(math.min(1.5, initialDuration))
		end)
	end
	local distance = Distance2D(origin, flightLocation)
	local hasScepter = HasModifier(bot, Flight.SCEPTER_MODIFIER)
	if hasScepter then
		if distance <= 800 then return nil, 'scepter_distance_too_short' end
		if GetHealthFraction(bot) < Flight.SCEPTER_MIN_HEALTH then return nil, 'health_too_low' end
	else
		local level = Safe(0, function() return ability:GetLevel() end)
		local maximumDistance = 600 + level * 250
		if distance < 500 or distance > maximumDistance then return nil, 'distance_outside_legacy_window' end
		if GetHealthFraction(target) > 0.30 then return nil, 'target_health_too_high' end
	end

	local enemyFountain = options.enemyFountainLocation or GetEnemyFountainLocation()
	if enemyFountain ~= nil and Distance2D(flightLocation, enemyFountain) < ENEMY_FOUNTAIN_REJECT_RADIUS then
		return nil, 'enemy_fountain'
	end

	local fixedMana = GetSpecialValue(ability, 'mana_cost', 0)
	local manaPercent = GetSpecialValue(ability, 'mana_cost_percent', 10)
	local maxMana = Safe(0, function() return bot:GetMaxMana() end)
	local currentMana = Safe(0, function() return bot:GetMana() end)
	local upfrontCost = Safe(50, function() return ability:GetManaCost() end)
	if upfrontCost <= 0 then upfrontCost = 50 end
	local reservePercent = options.reservePercent
	if reservePercent == nil then
		reservePercent = hasScepter and Flight.SCEPTER_RESERVE_PERCENT or Flight.RESERVE_PERCENT
	end
	local requiredMana, flightDuration = Flight.EstimateMana(distance, speed, fixedMana, manaPercent,
		maxMana, upfrontCost, reservePercent, GetMoonRemaining(bot))
	local drainPerSecond = fixedMana + maxMana * manaPercent / 100
	local moonPlan = Flight.BuildScheduledMoonPlan(bot, ability, flightDuration, drainPerSecond,
		upfrontCost, maxMana * reservePercent)
	if moonPlan ~= nil then requiredMana = moonPlan.requiredMana end
	if currentMana < requiredMana then return nil, 'mana_insufficient' end

	local castPoint = math.max(0, Safe(0.2, function() return ability:GetCastPoint() end))
	local travelTime = castPoint + flightDuration
	if options.maxTravelTime ~= nil and travelTime > options.maxTravelTime then
		return nil, 'arrival_too_late'
	end
	local plan = {
		route = Flight.ROUTE,
		abilityName = Flight.ABILITY_NAME,
		targetLocation = observedTargetLocation,
		flightLocation = flightLocation,
		distance = distance,
		flightDuration = flightDuration,
		travelTime = travelTime,
		requiredMana = requiredMana,
		hasScepter = hasScepter,
	}
	if moonPlan ~= nil then
		plan.flightMoonDuringFlight = true
		plan.flightMoonItemName = moonPlan.itemName
		plan.flightMoonActivationDelay = moonPlan.activationDelay
		plan.flightMoonFlightRegenDuration = moonPlan.flightRegenDuration
		plan.flightMoonPostLandingDuration = moonPlan.postLandingDuration
	end
	return plan, nil
end

return Flight
