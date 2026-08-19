require(GetScriptDirectory() .. "/thd2_item_usage")

local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

local TOSS_NAME = "tiny_toss"
local MIST_NAME = "ability_thdots_suika03"
local ULTIMATE_NAME = "ability_thdots_suika04"
local MIST_MODIFIER = "modifier_thdots_suika03_states"
local ULTIMATE_MODIFIER = "modifier_thdots_Suika_04"
local TOSS_NO_TARGET_TALENT = "special_bonus_unique_tiny_5"
local TOSS_DAMAGE_BY_LEVEL = {150, 200, 250, 300}
local TOSS_BONUS_DAMAGE_PCT = 30
local DRAGON_MODIFIER = "modifier_item_dragon_star_buff"
local FLOWER_MODIFIER = "modifier_item_flower_umbrella_spellstart_buff"
local ESDW_MODIFIER = "modifier_item_esdw_active_shield"
local TRINITY_MODIFIER = "modifier_item_trinity_active_shield"
local SMASH_BLADE_MODIFIER = "modifier_item_yuetufensuijvren_buff"
local HORSE_KING_MODIFIER = "modifier_item_horse_king_open"
local ACTION_CONFIRM_WINDOW = 0.35
local PAYLOAD_ALLY_MARGIN = 30
local PAYLOAD_SELECTION_MARGIN = 20
local RESCUE_SCAN_RANGE = 900
local RESCUE_STATE_DURATION = 3.0
local RESCUE_MOVE_INTERVAL = 0.20
local LANE_TOSS_START_RANGE = 500
local LANE_TOSS_CHASE_RANGE = 650
local LANE_TOSS_TOWER_SCAN_RANGE = 1600
local LANE_TOSS_ENEMY_TOWER_BUFFER = 1200
local LANE_TOSS_ANCHOR_TOWER_RANGE = 450
local LANE_TOSS_MIN_TOWER_GAIN = 300
local LANE_TOSS_STATE_DURATION = 1.8
local LANE_TOSS_MOVE_INTERVAL = 0.20
local LANE_TOSS_RETRY_DELAY = 4.0
local LANE_TOSS_SCAN_INTERVAL = 0.30
local LANE_TOSS_ACTIVE_THINK_INTERVAL = 0.03

-- 仅允许耐久、近身且具备开团职责的队友被主动投向敌阵。
local OFFENSIVE_ALLY_TOSS_WHITELIST = {
	["npc_dota_hero_centaur"] = true,       -- 星熊勇仪
	["npc_dota_hero_mars"] = true,          -- 寅丸星
	["npc_dota_hero_earth_spirit"] = true,  -- 梅林
	["npc_dota_hero_ogre_magi"] = true,     -- 诹访子
	["npc_dota_hero_sven"] = true,          -- 依姬
}

local function SafeCall(defaultValue, fn)
	local ok, result = pcall(fn)
	if ok and result ~= nil then return result end
	return defaultValue
end

local function GetProfile(bot)
	return BotProfile.GetProfileOrDefault(bot, BotProfile.FRONTLINE)
end

local function GetAbility(bot, name)
	local ability = bot:GetAbilityByName(name)
	if ability == nil or not ability:IsTrained() then return nil end
	return ability
end

local function IsCastable(ability)
	return ability ~= nil and ability:IsFullyCastable()
end

local function GetReadyItem(name)
	local item = IsItemAvailable(name)
	if item == nil or not item:IsFullyCastable() then return nil end
	return item
end

local function IsValidEnemyHero(bot, target)
	return target ~= nil
		and not SafeCall(true, function() return target:IsNull() end)
		and SafeCall(false, function() return target:IsAlive() end)
		and SafeCall(false, function() return target:IsHero() end)
		and SafeCall(bot:GetTeam(), function() return target:GetTeam() end) ~= bot:GetTeam()
		and SafeCall(false, function() return target:CanBeSeen() end)
		and not SafeCall(false, function() return target:IsInvulnerable() end)
		and not SafeCall(false, function() return target:IsMagicImmune() end)
		and not J.IsSuspiciousIllusion(target)
end

local function IsHardDisabled(target)
	return SafeCall(false, function() return target:IsStunned() end)
		or SafeCall(false, function() return target:IsHexed() end)
end

local function IsKillProtected(target)
	return target:HasModifier("modifier_abaddon_aphotic_shield")
		or target:HasModifier("modifier_abaddon_borrowed_time")
		or target:HasModifier("modifier_dazzle_shallow_grave")
		or target:HasModifier("modifier_oracle_false_promise_timer")
		or target:HasModifier("modifier_templar_assassin_refraction_absorb")
end

local function CountVisibleEnemies(bot, range)
	local count = 0
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, range, true, BOT_MODE_NONE)) do
		if IsValidEnemyHero(bot, enemy) then count = count + 1 end
	end
	return count
end

local function FindClosestVisibleEnemy(bot, range)
	local closest = nil
	local closestDistance = math.huge
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, range, true, BOT_MODE_NONE)) do
		if IsValidEnemyHero(bot, enemy) then
			local distance = GetUnitToUnitDistance(bot, enemy)
			if distance < closestDistance then
				closest = enemy
				closestDistance = distance
			end
		end
	end
	return closest
end

local function GetHandle(bot, name)
	local ability = bot:GetAbilityByName(name)
	if ability ~= nil then return ability end
	return IsItemAvailable(name)
end

local function GetCooldown(handle)
	return handle ~= nil and SafeCall(0, function() return handle:GetCooldownTimeRemaining() end) or 0
end

local function MarkPendingAction(bot, handle, modifierName)
	local name = handle:GetName()
	local tracksMovement = name == "item_9ball"
		or name == "item_wanmeitiaoyuezhuangzhi"
		or name == "item_nb9ball"
	bot.suikaPendingAction = {
		name = name,
		issuedAt = DotaTime(),
		deadline = DotaTime() + ACTION_CONFIRM_WINDOW,
		oldCooldown = GetCooldown(handle),
		oldMana = bot:GetMana(),
		modifierName = modifierName,
		location = tracksMovement and bot:GetLocation() or nil,
	}
end

local function ClearPendingAction(bot)
	bot.suikaPendingAction = nil
end

local function HasPendingAction(bot)
	local pending = bot.suikaPendingAction
	if pending == nil then return false end

	if pending.modifierName ~= nil and bot:HasModifier(pending.modifierName) then
		ClearPendingAction(bot)
		return false
	end

	local handle = GetHandle(bot, pending.name)
	if handle ~= nil and GetCooldown(handle) > pending.oldCooldown + 0.05 then
		ClearPendingAction(bot)
		return false
	end
	if bot:GetMana() < pending.oldMana - 0.5 then
		ClearPendingAction(bot)
		return false
	end
	if pending.location ~= nil and GetUnitToLocationDistance(bot, pending.location) >= 80 then
		ClearPendingAction(bot)
		return false
	end
	if DotaTime() < pending.deadline then return true end

	if DotaTime() - (bot.suikaLastConfirmTimeout or -90) > 10 then
		print("[BOT][Suika] action confirmation timeout: " .. tostring(pending.name))
		bot.suikaLastConfirmTimeout = DotaTime()
	end
	ClearPendingAction(bot)
	return false
end

local function UseNoTarget(bot, handle, modifierName)
	MarkPendingAction(bot, handle, modifierName)
	bot:Action_UseAbility(handle)
	return true
end

local function UseOnEntity(bot, handle, target, modifierName)
	MarkPendingAction(bot, handle, modifierName)
	bot:Action_UseAbilityOnEntity(handle, target)
	return true
end

local function UseOnLocation(bot, handle, location, modifierName)
	MarkPendingAction(bot, handle, modifierName)
	bot:Action_UseAbilityOnLocation(handle, location)
	return true
end

local function IsPayloadCandidate(bot, unit, radius)
	return unit ~= nil
		and unit ~= bot
		and not SafeCall(true, function() return unit:IsNull() end)
		and SafeCall(false, function() return unit:IsAlive() end)
		and SafeCall(false, function() return unit:CanBeSeen() end)
		and not SafeCall(false, function() return unit:IsInvulnerable() end)
		and GetUnitToUnitDistance(bot, unit) <= radius
end

local function GetPayloadState(bot, radius)
	local nearest = nil
	local nearestDistance = math.huge
	local nearestAllyDistance = math.huge
	local secondDistance = math.huge
	local nearestKind = nil
	local groups = {
		{units = CachedGetNearbyHeroes(bot, radius, true, BOT_MODE_NONE), kind = "enemy_hero"},
		{units = CachedGetNearbyHeroes(bot, radius, false, BOT_MODE_NONE), kind = "ally_hero"},
		{units = bot:GetNearbyCreeps(radius, true), kind = "enemy_creep"},
		{units = bot:GetNearbyCreeps(radius, false), kind = "ally_creep"},
	}

	for _, group in pairs(groups) do
		for _, unit in pairs(group.units or {}) do
			if IsPayloadCandidate(bot, unit, radius) then
				local distance = GetUnitToUnitDistance(bot, unit)
				if SafeCall(bot:GetTeam(), function() return unit:GetTeam() end) == bot:GetTeam() then
					nearestAllyDistance = math.min(nearestAllyDistance, distance)
				end
				if distance < nearestDistance then
					secondDistance = nearestDistance
					nearest = unit
					nearestDistance = distance
					nearestKind = group.kind
				elseif distance < secondDistance then
					secondDistance = distance
				end
			end
		end
	end
	return nearest, nearestDistance, nearestAllyDistance, secondDistance, nearestKind
end

local function CapturePayloadState(bot, radius)
	local nearest, distance, nearestAllyDistance, secondDistance, kind = GetPayloadState(bot, radius)
	return {
		nearest = nearest,
		distance = distance,
		nearestAllyDistance = nearestAllyDistance,
		secondDistance = secondDistance,
		kind = kind,
	}
end

local function IsSafeEnemyPayload(bot, target, radius, state)
	if not IsValidEnemyHero(bot, target) then return false end
	state = state or CapturePayloadState(bot, radius)
	return state.nearest == target
		and state.nearestAllyDistance >= state.distance + PAYLOAD_ALLY_MARGIN
		and state.secondDistance >= state.distance + PAYLOAD_SELECTION_MARGIN
end

local function IsApprovedOffensiveAlly(bot, ally)
	if ally == nil
		or SafeCall(-1, function() return ally:GetTeam() end) ~= bot:GetTeam()
		or not SafeCall(false, function() return ally:IsHero() end)
		or not OFFENSIVE_ALLY_TOSS_WHITELIST[SafeCall("", function() return ally:GetUnitName() end)]
		or J.GetHP(ally) < 0.55
		or SafeCall(false, function() return J.IsRetreating(ally) end)
	then
		return false
	end
	return SafeCall(false, function() return J.IsGoingOnSomeone(ally) end)
end

local function IsValidRescueAlly(bot, ally)
	return ally ~= nil
		and ally ~= bot
		and not SafeCall(true, function() return ally:IsNull() end)
		and SafeCall(false, function() return ally:IsAlive() end)
		and SafeCall(false, function() return ally:IsHero() end)
		and SafeCall(-1, function() return ally:GetTeam() end) == bot:GetTeam()
		and SafeCall(false, function() return ally:CanBeSeen() end)
		and not SafeCall(false, function() return ally:IsIllusion() end)
end

local function IsEndangeredRescueAlly(bot, ally)
	if not IsValidRescueAlly(bot, ally) then return false end
	local enemies = 0
	for _, enemy in pairs(CachedGetNearbyHeroes(ally, 700, true, BOT_MODE_NONE)) do
		if IsValidEnemyHero(bot, enemy) then enemies = enemies + 1 end
	end
	if enemies == 0 or not SafeCall(false, function() return ally:WasRecentlyDamagedByAnyHero(2.5) end) then
		return false
	end

	local hp = J.GetHP(ally)
	return hp <= 0.22
		or (hp <= 0.42 and SafeCall(false, function() return J.IsSeriouslyRetreating(ally) end))
end

local function FindEndangeredRescueAlly(bot)
	local bestAlly = nil
	local bestScore = math.huge
	for _, ally in pairs(CachedGetNearbyHeroes(bot, RESCUE_SCAN_RANGE, false, BOT_MODE_NONE)) do
		if IsEndangeredRescueAlly(bot, ally) then
			local score = J.GetHP(ally) * 1000 + GetUnitToUnitDistance(bot, ally) / 100
			if score < bestScore then
				bestAlly = ally
				bestScore = score
			end
		end
	end
	return bestAlly
end

local function GetOffensivePayload(bot, target, radius, allowAllyHero, state)
	if not IsValidEnemyHero(bot, target) then return nil end
	state = state or CapturePayloadState(bot, radius)
	if state.nearest == nil
		or state.secondDistance < state.distance + PAYLOAD_SELECTION_MARGIN
	then
		return nil
	end
	if state.nearest == target and state.kind == "enemy_hero"
	and state.nearestAllyDistance >= state.distance + PAYLOAD_ALLY_MARGIN
	then
		return state.nearest
	end
	if state.kind == "enemy_creep" or state.kind == "ally_creep" then return state.nearest end
	if allowAllyHero and state.kind == "ally_hero" and IsApprovedOffensiveAlly(bot, state.nearest) then
		return state.nearest
	end
	return nil
end

local function HasNoTargetTossTalent(bot)
	local talent = bot:GetAbilityByName(TOSS_NO_TARGET_TALENT)
	return talent ~= nil and talent:GetLevel() > 0
end

local function CastToss(bot, ability, target)
	if HasNoTargetTossTalent(bot) then
		return UseOnLocation(bot, ability, target:GetLocation(), nil)
	end
	return UseOnEntity(bot, ability, target, nil)
end

local function ConsiderEmergencyMist(bot, ability, profile)
	if not IsCastable(ability) or bot:HasModifier(MIST_MODIFIER) then return false end
	local enemies = CountVisibleEnemies(bot, 800)
	if enemies == 0 then return false end

	local hp = J.GetHP(bot)
	if hp <= 0.28 then return true end
	local retreatLimit = profile == BotProfile.FRONTLINE and 0.48 or 0.36
	return hp <= retreatLimit
		and J.IsSeriouslyRetreating(bot)
		and bot:WasRecentlyDamagedByAnyHero(2.5)
end

local function GetTossRadius(ability)
	return math.max(ability:GetSpecialValueInt("grab_radius"), 1)
end

local function GetTossCastRange(ability)
	return math.max(SafeCall(0, function() return ability:GetCastRange() end), GetTossRadius(ability))
end

local function ClearRescueToss(bot)
	bot.suikaRescueToss = nil
end

local function IsSafeRescueAnchor(bot, ally, unit, radius, castRange, fountain, allyFountainDistance)
	if unit == nil or unit == bot or unit == ally
		or not IsPayloadCandidate(bot, unit, castRange)
		or SafeCall(-1, function() return unit:GetTeam() end) ~= bot:GetTeam()
	then
		return false
	end

	local distance = GetUnitToUnitDistance(bot, unit)
	if distance <= radius + PAYLOAD_SELECTION_MARGIN then return false end
	return GetUnitToLocationDistance(unit, fountain) <= allyFountainDistance - 150
end

local function FindSafeRescueAnchor(bot, ally, radius, castRange)
	local fountain = J.GetTeamFountain()
	local allyFountainDistance = GetUnitToLocationDistance(ally, fountain)
	local best = nil
	local bestDistance = math.huge
	local groups = {
		CachedGetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE),
		bot:GetNearbyCreeps(castRange, false),
	}
	for _, units in pairs(groups) do
		for _, unit in pairs(units or {}) do
			if IsSafeRescueAnchor(bot, ally, unit, radius, castRange, fountain, allyFountainDistance) then
				local fountainDistance = GetUnitToLocationDistance(unit, fountain)
				if fountainDistance < bestDistance then
					best = unit
					bestDistance = fountainDistance
				end
			end
		end
	end
	return best
end

local function GetSafeRescueLocation(bot, castRange)
	local fountain = J.GetTeamFountain()
	local fountainDistance = fountain ~= nil and GetUnitToLocationDistance(bot, fountain) or 0
	if fountainDistance <= 1 then return nil end
	local travelDistance = math.min(math.max(castRange - 50, 1), math.max(fountainDistance - 100, 1))
	local location = J.GetLocationTowardDistanceLocation(bot, fountain, travelDistance)
	if IsLocationPassable ~= nil
	and not SafeCall(false, function() return IsLocationPassable(location) end)
	then
		return nil
	end
	return location
end

local function TryRescueAlly(bot, ability)
	if not IsCastable(ability)
		or J.GetHP(bot) <= 0.42
		or SafeCall(false, function() return J.IsSeriouslyRetreating(bot) end)
	then
		ClearRescueToss(bot)
		return false
	end

	local now = DotaTime()
	local state = bot.suikaRescueToss
	if state == nil then
		local ally = FindEndangeredRescueAlly(bot)
		if ally == nil then return false end
		state = {
			ally = ally,
			deadline = now + RESCUE_STATE_DURATION,
			nextMoveAt = now,
		}
		bot.suikaRescueToss = state
	end

	local ally = state.ally
	if now > state.deadline
		or not IsEndangeredRescueAlly(bot, ally)
		or GetUnitToUnitDistance(bot, ally) > RESCUE_SCAN_RANGE + 150
	then
		ClearRescueToss(bot)
		return false
	end

	local radius = GetTossRadius(ability)
	local castRange = GetTossCastRange(ability)
	local nearest, distance, _, secondDistance, kind = GetPayloadState(bot, radius)
	local allyIsSafePayload = nearest == ally
		and kind == "ally_hero"
		and secondDistance >= distance + PAYLOAD_SELECTION_MARGIN
	if allyIsSafePayload then
		if HasNoTargetTossTalent(bot) then
			local location = GetSafeRescueLocation(bot, castRange)
			if location ~= nil then
				ClearRescueToss(bot)
				return UseOnLocation(bot, ability, location, nil)
			end
		else
			local anchor = FindSafeRescueAnchor(bot, ally, radius, castRange)
			if anchor ~= nil then
				ClearRescueToss(bot)
				return UseOnEntity(bot, ability, anchor, nil)
			end
		end
	end

	-- 投掷只会抓取萃香身边最近单位；救援阶段持续贴近目标并锁住本帧动作。
	if now >= state.nextMoveAt then
		bot:Action_MoveToLocation(ally:GetLocation())
		state.nextMoveAt = now + RESCUE_MOVE_INTERVAL
	end
	return true
end

local function ClearLaneTowerToss(bot, retryDelay)
	bot.suikaLaneTowerToss = nil
	if retryDelay ~= nil then
		bot.suikaNextLaneTossTime = DotaTime() + retryDelay
	end
end

local function IsAliveTower(bot, tower)
	return tower ~= nil
		and not SafeCall(true, function() return tower:IsNull() end)
		and SafeCall(false, function() return tower:IsAlive() end)
		and SafeCall(-1, function() return tower:GetTeam() end) == bot:GetTeam()
end

local function HasSafeLaneTossNumbers(bot)
	local enemyCount = CountVisibleEnemies(bot, 900)
	local allyCount = 1
	for _, ally in pairs(CachedGetNearbyHeroes(bot, 900, false, BOT_MODE_NONE)) do
		if IsValidRescueAlly(bot, ally) then allyCount = allyCount + 1 end
	end
	return enemyCount > 0 and enemyCount <= allyCount
end

local function IsLaneTowerTossContext(bot, ability)
	if not IsCastable(ability)
		or bot:IsSilenced()
		or not J.IsInLaningPhase()
		or SafeCall(BOT_MODE_NONE, function() return bot:GetActiveMode() end) ~= BOT_MODE_LANING
		or J.GetHP(bot) < 0.65
		or J.GetMP(bot) < 0.45
		or J.IsRetreating(bot)
		or J.IsGoingOnSomeone(bot)
		or bot:WasRecentlyDamagedByAnyHero(1.5)
		or not J.WeAreStronger(bot, 900)
		or not HasSafeLaneTossNumbers(bot)
	then
		return false
	end

	local enemyTowers = SafeCall({}, function()
		return bot:GetNearbyTowers(LANE_TOSS_ENEMY_TOWER_BUFFER, true)
	end)
	return #enemyTowers == 0
end

local function FindClosestAlliedLaneTower(bot)
	local closest = nil
	local closestDistance = math.huge
	for _, tower in pairs(SafeCall({}, function()
		return bot:GetNearbyTowers(LANE_TOSS_TOWER_SCAN_RANGE, false)
	end)) do
		if IsAliveTower(bot, tower) then
			local distance = GetUnitToUnitDistance(bot, tower)
			if distance < closestDistance then
				closest = tower
				closestDistance = distance
			end
		end
	end
	return closest
end

local function IsEnemyTowerNearLaneTarget(bot, target)
	for _, tower in pairs(SafeCall({}, function()
		return bot:GetNearbyTowers(LANE_TOSS_TOWER_SCAN_RANGE, true)
	end)) do
		if tower ~= nil
		and SafeCall(false, function() return tower:IsAlive() end)
		and GetUnitToUnitDistance(target, tower) <= 750
		then
			return true
		end
	end
	return false
end

local function IsLaneTowerAnchor(bot, target, tower, unit, radius, castRange, targetTowerDistance)
	if unit == nil or unit == bot or unit == target
		or not IsPayloadCandidate(bot, unit, castRange)
		or SafeCall(-1, function() return unit:GetTeam() end) ~= bot:GetTeam()
	then
		return false
	end

	local botDistance = GetUnitToUnitDistance(bot, unit)
	local towerDistance = GetUnitToUnitDistance(unit, tower)
	return botDistance > radius + PAYLOAD_SELECTION_MARGIN
		and towerDistance <= LANE_TOSS_ANCHOR_TOWER_RANGE
		and towerDistance <= targetTowerDistance - LANE_TOSS_MIN_TOWER_GAIN
end

local function FindLaneTowerAnchor(bot, target, tower, radius, castRange)
	local targetTowerDistance = GetUnitToUnitDistance(target, tower)
	local best = nil
	local bestTowerDistance = math.huge
	local groups = {
		CachedGetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE),
		bot:GetNearbyCreeps(castRange, false),
	}
	for _, units in pairs(groups) do
		for _, unit in pairs(units or {}) do
			if IsLaneTowerAnchor(bot, target, tower, unit, radius, castRange, targetTowerDistance) then
				local towerDistance = GetUnitToUnitDistance(unit, tower)
				if towerDistance < bestTowerDistance then
					best = unit
					bestTowerDistance = towerDistance
				end
			end
		end
	end
	return best
end

local function FindLaneTowerTossSetup(bot, ability)
	local tower = FindClosestAlliedLaneTower(bot)
	if tower == nil then return nil, nil end

	local radius = GetTossRadius(ability)
	local castRange = GetTossCastRange(ability)
	local bestTarget = nil
	local bestScore = math.huge
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, LANE_TOSS_START_RANGE, true, BOT_MODE_NONE)) do
		if IsValidEnemyHero(bot, enemy)
		and not IsHardDisabled(enemy)
		and not IsEnemyTowerNearLaneTarget(bot, enemy)
		and GetUnitToUnitDistance(enemy, tower) >= LANE_TOSS_ANCHOR_TOWER_RANGE + LANE_TOSS_MIN_TOWER_GAIN
		then
			local anchor = FindLaneTowerAnchor(bot, enemy, tower, radius, castRange)
			if anchor ~= nil then
				local score = GetUnitToUnitDistance(bot, enemy) + J.GetHP(enemy) * 100
				if score < bestScore then
					bestTarget = enemy
					bestScore = score
				end
			end
		end
	end
	return bestTarget, tower
end

local function TryLaneTowerToss(bot, ability)
	local now = DotaTime()
	local state = bot.suikaLaneTowerToss
	if state == nil then
		if now < (bot.suikaNextLaneTossTime or -90)
			or now < (bot.suikaNextLaneTossScanAt or -90)
			or not IsLaneTowerTossContext(bot, ability)
		then
			return false
		end
		bot.suikaNextLaneTossScanAt = now + LANE_TOSS_SCAN_INTERVAL

		local target, tower = FindLaneTowerTossSetup(bot, ability)
		if target == nil then return false end
		state = {
			target = target,
			tower = tower,
			deadline = now + LANE_TOSS_STATE_DURATION,
			nextMoveAt = now,
			nextCheckAt = now,
		}
		bot.suikaLaneTowerToss = state
	end
	if now < state.nextCheckAt then return true end
	state.nextCheckAt = now + LANE_TOSS_ACTIVE_THINK_INTERVAL

	local target = state.target
	local tower = state.tower
	if now > state.deadline
		or not IsLaneTowerTossContext(bot, ability)
		or not IsAliveTower(bot, tower)
		or not IsValidEnemyHero(bot, target)
		or IsHardDisabled(target)
		or IsEnemyTowerNearLaneTarget(bot, target)
		or GetUnitToUnitDistance(bot, target) > LANE_TOSS_CHASE_RANGE
	then
		ClearLaneTowerToss(bot, LANE_TOSS_RETRY_DELAY)
		return false
	end

	local radius = GetTossRadius(ability)
	local castRange = GetTossCastRange(ability)
	local anchor = FindLaneTowerAnchor(bot, target, tower, radius, castRange)
	if anchor == nil then
		ClearLaneTowerToss(bot, LANE_TOSS_RETRY_DELAY)
		return false
	end

	local payloadState = CapturePayloadState(bot, radius)
	if IsSafeEnemyPayload(bot, target, radius, payloadState) then
		ClearLaneTowerToss(bot, LANE_TOSS_RETRY_DELAY)
		if HasNoTargetTossTalent(bot) then
			return UseOnLocation(bot, ability, anchor:GetLocation(), nil)
		end
		return UseOnEntity(bot, ability, anchor, nil)
	end

	-- 对线拉回只追一小段；抓取对象尚未成为唯一最近载荷时绝不提前施法。
	if now >= state.nextMoveAt then
		bot:Action_MoveToLocation(target:GetLocation())
		state.nextMoveAt = now + LANE_TOSS_MOVE_INTERVAL
	end
	return true
end

local function ConsiderTossInterrupt(bot, ability)
	if not IsCastable(ability) then return nil end
	local radius = GetTossRadius(ability)
	local castRange = GetTossCastRange(ability)
	local payloadState = CapturePayloadState(bot, radius)
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)) do
		if GetOffensivePayload(bot, enemy, radius, false, payloadState) ~= nil
		and not IsHardDisabled(enemy)
		and (enemy:IsChanneling() or IsTeleporting(enemy))
		then
			return enemy
		end
	end
	return nil
end

local function GetTossDamage(bot, ability)
	local level = SafeCall(0, function() return ability:GetLevel() end)
	local damage = TOSS_DAMAGE_BY_LEVEL[level]
	if damage == nil then return 0 end

	-- 原生 Tiny Toss 的伤害特殊值查询在无目标上下文时可能进入 C++ 目标修正路径并崩溃，按当前 KV 等级表估算。
	return damage * (1 + TOSS_BONUS_DAMAGE_PCT / 100) * (1 + bot:GetSpellAmp())
end

local function ConsiderToss(bot, ability)
	if not IsCastable(ability) then return nil end
	local radius = GetTossRadius(ability)
	local castRange = GetTossCastRange(ability)
	local enemies = CachedGetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
	local payloadState = CapturePayloadState(bot, radius)

	-- 参考 Tiny：可用身边友/敌小兵作为载荷，但击杀分支不牺牲友方英雄。
	for _, enemy in pairs(enemies) do
		if GetOffensivePayload(bot, enemy, radius, false, payloadState) ~= nil
		and not IsKillProtected(enemy)
		and J.CanKillTarget(enemy, GetTossDamage(bot, ability), DAMAGE_TYPE_MAGICAL)
		then
			return enemy
		end
	end

	if J.IsSeriouslyRetreating(bot) and bot:WasRecentlyDamagedByAnyHero(2.0) then
		for _, enemy in pairs(enemies) do
			if IsSafeEnemyPayload(bot, enemy, radius, payloadState)
			and not IsHardDisabled(enemy)
			and bot:WasRecentlyDamagedByHero(enemy, 2.5)
			then
				return enemy
			end
		end
	end

	local target = J.GetProperTarget(bot)
	if not J.IsGoingOnSomeone(bot)
		or not IsValidEnemyHero(bot, target)
		or GetUnitToUnitDistance(bot, target) > castRange
		or GetOffensivePayload(bot, target, radius, true, payloadState) == nil
		or IsHardDisabled(target)
	then
		return nil
	end
	local allies = #CachedGetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE) + 1
	local nearbyEnemies = CountVisibleEnemies(bot, 1000)
	if nearbyEnemies > allies + 1 then return nil end
	return target
end

local function TryUseShield(bot)
	local item = GetReadyItem("item_trinity") or GetReadyItem("item_esdw")
	if item == nil then return false end
	local modifier = item:GetName() == "item_trinity" and TRINITY_MODIFIER or ESDW_MODIFIER
	if bot:HasModifier(modifier) then return false end

	local enemyCount = CountVisibleEnemies(bot, 1200)
	local sharedDesire = ConsiderItemShield(item)
	local preCommit = enemyCount >= 2 and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	local underPressure = enemyCount > 0 and bot:WasRecentlyDamagedByAnyHero(2.0) and J.GetHP(bot) < 0.70
	if preCommit or underPressure or (sharedDesire ~= nil and sharedDesire > BOT_ACTION_DESIRE_NONE) then
		return UseNoTarget(bot, item, modifier)
	end
	return false
end

local function TryUseFlowerUmbrella(bot, profile)
	if profile ~= BotProfile.FRONTLINE then return false end
	local item = GetReadyItem("item_flower_umbrella")
	if item == nil or bot:HasModifier(FLOWER_MODIFIER) then return false end
	local enemyCount = CountVisibleEnemies(bot, 1000)
	local allyCount = #CachedGetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE) + 1
	local committed = enemyCount >= 2 and allyCount >= 2
		and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	local pressured = enemyCount > 0 and bot:WasRecentlyDamagedByAnyHero(2.0) and J.GetHP(bot) < 0.70
	if committed or pressured then return UseNoTarget(bot, item, FLOWER_MODIFIER) end
	return false
end

local function TryUseDragonStar(bot)
	local item = GetReadyItem("item_dragon_star")
	if item == nil or bot:HasModifier(DRAGON_MODIFIER) then return false end
	local enemyCount = CountVisibleEnemies(bot, 1000)
	local retreat = J.IsSeriouslyRetreating(bot)
		and enemyCount > 0 and bot:WasRecentlyDamagedByAnyHero(2.0)
	local target = J.GetProperTarget(bot)
	local commit = (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
		and IsValidEnemyHero(bot, target)
		and GetUnitToUnitDistance(bot, target) <= 800
	if retreat or commit then return UseNoTarget(bot, item, DRAGON_MODIFIER) end
	return false
end

local function IsSafeJumpLocation(location)
	if location == nil then return false end
	if IsLocationPassable == nil then return true end
	return SafeCall(false, function() return IsLocationPassable(location) end)
end

local function GetDirectedJumpItem()
	-- 牛逼跳跃会消耗完美跳跃，合成前后统一从同一入口取得当前可用装备。
	return GetReadyItem("item_nb9ball") or GetReadyItem("item_wanmeitiaoyuezhuangzhi")
end

local function TryUseDirectedJump(bot)
	local item = GetDirectedJumpItem()
	if item == nil then return false end
	local castRange = item:GetName() == "item_nb9ball" and 999 or 499
	local desire, location = ConsiderItemJump(item, 100, 600, castRange)
	if desire ~= nil and desire > BOT_ACTION_DESIRE_NONE and IsSafeJumpLocation(location) then
		return UseOnLocation(bot, item, location, nil)
	end
	return false
end

local function TryUseSmashBlade(bot, profile)
	if profile ~= BotProfile.DAMAGE then return false end
	local item = GetReadyItem("item_yuetufensuijvren")
	if item == nil then return false end
	local desire, target = ConsiderItemStun(item)
	if desire ~= nil and desire > BOT_ACTION_DESIRE_NONE
	and IsValidEnemyHero(bot, target)
	and not IsHardDisabled(target)
	then
		-- 巨刃主动会自行追击目标；保留冲锋状态直到命中或自然结束。
		return UseOnEntity(bot, item, target, SMASH_BLADE_MODIFIER)
	end
	return false
end

local function TryUseHorseKing(bot)
	local item = GetReadyItem("item_horse_king")
	if item == nil then return false end
	local desire = ConsiderItemHorseKing(item)
	if desire ~= nil and desire > BOT_ACTION_DESIRE_NONE then
		local modifier = bot:HasModifier(HORSE_KING_MODIFIER) and nil or HORSE_KING_MODIFIER
		return UseNoTarget(bot, item, modifier)
	end
	return false
end

local function TryUseRandomJump(bot, mist)
	local item = GetReadyItem("item_9ball")
	if item == nil or GetDirectedJumpItem() ~= nil then return false end
	if IsCastable(mist) and not bot:IsSilenced() then return false end
	if J.GetHP(bot) < 0.25
	and J.IsSeriouslyRetreating(bot)
	and bot:WasRecentlyDamagedByAnyHero(2.0)
	and CountVisibleEnemies(bot, 350) > 0
	then
		return UseNoTarget(bot, item, nil)
	end
	return false
end

local function TryUseActiveItems(bot, profile, mist)
	if J.CanNotUseAction(bot) or bot:IsMuted() then return false end
	if TryUseShield(bot) then return true end
	if TryUseFlowerUmbrella(bot, profile) then return true end
	if TryUseDragonStar(bot) then return true end
	if TryUseSmashBlade(bot, profile) then return true end
	if TryUseDirectedJump(bot) then return true end
	if TryUseHorseKing(bot) then return true end
	if TryUseRandomJump(bot, mist) then return true end
	return false
end

local function ConsiderUltimate(bot, ability, profile)
	if not IsCastable(ability) or bot:HasModifier(ULTIMATE_MODIFIER) or J.IsRetreating(bot) then return false end
	if J.GetHP(bot) <= 0.28 then return false end

	local target = J.GetProperTarget(bot)
	if not IsValidEnemyHero(bot, target) then target = FindClosestVisibleEnemy(bot, 700) end
	if not IsValidEnemyHero(bot, target)
		or SafeCall(false, function() return target:IsAttackImmune() end)
		or GetUnitToUnitDistance(bot, target) > 700
	then
		return false
	end

	local enemyCount = CountVisibleEnemies(bot, 1000)
	local allyCount = #CachedGetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE) + 1
	if enemyCount > allyCount + 1 then return false end

	if profile == BotProfile.DAMAGE then
		return (J.IsGoingOnSomeone(bot) and J.WeAreStronger(bot, 1000))
			or (enemyCount >= 2 and J.IsInTeamFight(bot, 1200))
	end
	return J.IsGoingOnSomeone(bot)
		or J.IsInTeamFight(bot, 1200)
		or (enemyCount > 0 and bot:WasRecentlyDamagedByAnyHero(2.0))
end

function AbilityUsageThink()
	if not IsBotAwake() then return end
	local bot = GetBot()
	if bot:HasModifier(MIST_MODIFIER) or HasPendingAction(bot) then return end
	if bot:HasModifier(SMASH_BLADE_MODIFIER) then return end
	if J.CanNotUseAction(bot) or bot:IsUsingAbility() or bot:IsChanneling() then return end

	local profile = GetProfile(bot)
	local toss = GetAbility(bot, TOSS_NAME)
	local mist = GetAbility(bot, MIST_NAME)
	local ultimate = GetAbility(bot, ULTIMATE_NAME)

	if not bot:IsSilenced() and ConsiderEmergencyMist(bot, mist, profile) then
		ClearRescueToss(bot)
		ClearLaneTowerToss(bot, LANE_TOSS_RETRY_DELAY)
		UseNoTarget(bot, mist, MIST_MODIFIER)
		return
	end

	if not bot:IsSilenced() then
		local interruptTarget = ConsiderTossInterrupt(bot, toss)
		if interruptTarget ~= nil then
			CastToss(bot, toss, interruptTarget)
			return
		end
	end

	if not bot:IsSilenced() and TryRescueAlly(bot, toss) then return end
	if TryLaneTowerToss(bot, toss) then return end

	if TryUseActiveItems(bot, profile, mist) then return end
	if bot:IsSilenced() then
		ConsiderNeutralItems()
		return
	end

	if ConsiderUltimate(bot, ultimate, profile) then
		UseNoTarget(bot, ultimate, ULTIMATE_MODIFIER)
		return
	end

	local tossTarget = ConsiderToss(bot, toss)
	if tossTarget ~= nil then
		CastToss(bot, toss, tossTarget)
		return
	end

	ConsiderNeutralItems()
end
