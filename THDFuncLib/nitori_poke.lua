local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")
local NitoriCombat = require(GetScriptDirectory() .. "/THDFuncLib/nitori_combat")

local NitoriPoke = {}

local HERO_NAME = "npc_dota_hero_spectre"
local NITORI02 = "ability_thdots_nitori02"
local NITORI01 = "ability_thdots_nitori01"
local NITORI03 = "ability_thdots_nitori03"
local FLIGHT_MODIFIER = "modifier_ability_thdots_nitori01"
local CHARGE_MODIFIER = "modifier_ability_thdots_nitori02"
local SEARCH_RANGE = 1450
local INNER_RANGE = 650
local HOLD_RANGE = 950
local PRESSURED_HOLD_RANGE = 1050
local TOWER_DANGER_RANGE = 900
local OWN_SIDE_MIN_PROJECTION = 0.3
local ACTION_LOCK_TIME = 0.3
local SNAPSHOT_INTERVAL = 0.2
local MOVE_THINK_INTERVAL = 0.2
local HARVEST_MIN_RANGE = 350
local HARVEST_MAX_RANGE = 1150
local HARVEST_DAMAGE_SAFETY = 0.85
local TOWER_DIVE_DAMAGE_SAFETY = 0.75
local TOWER_DIVE_MIN_HP = 0.8
local HIGH_GROUND_DIVE_DAMAGE_SAFETY = 0.7
local HIGH_GROUND_DIVE_MIN_HP = 0.85
local HARVEST_TIMEOUT = 6.5

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

local function IsSpellProfile(bot)
	return bot ~= nil
		and SafeCall(bot, "GetUnitName", "") == HERO_NAME
		and BotProfile.GetProfile(bot) == BotProfile.SUPPORT
end

local function ShouldYield(bot)
	if J.Retreat ~= nil and J.Retreat.ShouldYield ~= nil
	and J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
	then
		return true
	end
	return J.IsSeriouslyRetreating ~= nil and J.IsSeriouslyRetreating(bot)
end

local function IsVisibleEnemy(bot, enemy)
	return enemy ~= nil
		and not SafeCall(enemy, "IsNull", false)
		and SafeCall(enemy, "IsAlive", false)
		and SafeCall(enemy, "CanBeSeen", false)
		and SafeCall(enemy, "GetTeam", bot:GetTeam()) ~= bot:GetTeam()
		and not SafeCall(enemy, "IsInvulnerable", false)
		and not J.IsSuspiciousIllusion(enemy)
end

local function GetSnapshot(bot)
	local now = DotaTime()
	local state = bot.thdNitoriPokeSnapshot
	if state ~= nil and now - state.time < SNAPSHOT_INTERVAL then return state end

	local enemies = {}
	local centerX, centerY = 0, 0
	local nearestDistance = math.huge
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, SEARCH_RANGE, true, BOT_MODE_NONE)) do
		if IsVisibleEnemy(bot, enemy) and GetUnitToUnitDistance(bot, enemy) <= SEARCH_RANGE then
			local location = enemy:GetLocation()
			table.insert(enemies, enemy)
			centerX = centerX + location.x
			centerY = centerY + location.y
			nearestDistance = math.min(nearestDistance, GetUnitToUnitDistance(bot, enemy))
		end
	end

	state = {
		time = now,
		enemies = enemies,
		center = #enemies > 0 and Vector(centerX / #enemies, centerY / #enemies, 0) or nil,
		nearestDistance = nearestDistance,
	}
	bot.thdNitoriPokeSnapshot = state
	return state
end

local function IsEnemyTowerDanger(bot, location)
	if UNIT_LIST_ENEMY_BUILDINGS == nil or GetUnitList == nil then return false end
	for _, building in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
		if building ~= nil
		and SafeCall(building, "IsAlive", false)
		and SafeCall(building, "CanBeSeen", false)
		and SafeCall(building, "IsTower", false)
		and SafeCall(building, "GetTeam", bot:GetTeam()) ~= bot:GetTeam()
		and GetUnitToLocationDistance(building, location) < TOWER_DANGER_RANGE
		then
			return true
		end
	end
	return false
end

local function RotateDirection(x, y, degrees)
	local radians = math.rad(degrees)
	local cosine, sine = math.cos(radians), math.sin(radians)
	return x * cosine - y * sine, x * sine + y * cosine
end

local function GetLocationDistance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function GetSafeRingLocation(bot, snapshot)
	if snapshot.center == nil then return nil end
	local botLocation = bot:GetLocation()
	local teamFountain = J.GetTeamFountain ~= nil and J.GetTeamFountain() or botLocation
	local dx = teamFountain.x - snapshot.center.x
	local dy = teamFountain.y - snapshot.center.y
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1 then
		-- 极端回退仍沿当前较安全的一侧，避免生成无方向的环带点。
		dx = botLocation.x - snapshot.center.x
		dy = botLocation.y - snapshot.center.y
		length = math.sqrt(dx * dx + dy * dy)
		if length < 1 then dx, dy, length = -1, 0, 1 end
	end
	dx, dy = dx / length, dy / length

	local pressured = snapshot.nearestDistance < INNER_RANGE or GetHP(bot) < 0.45
	local holdRange = pressured and PRESSURED_HOLD_RANGE or HOLD_RANGE
	local bestLocation, bestScore = nil, math.huge
	for _, angle in ipairs({0, 25, -25, 50, -50, 70, -70}) do
		local rx, ry = RotateDirection(dx, dy, angle)
		local candidate = Vector(
			snapshot.center.x + rx * holdRange,
			snapshot.center.y + ry * holdRange,
			botLocation.z or 0
		)
		local ownSideProjection = rx * dx + ry * dy
		if ownSideProjection >= OWN_SIDE_MIN_PROJECTION
		and IsLocationPassable(candidate)
		and not IsEnemyTowerDanger(bot, candidate)
		then
			local score = GetLocationDistance(botLocation, candidate) - ownSideProjection * 120
			if score < bestScore then
				bestLocation, bestScore = candidate, score
			end
		end
	end
	if bestLocation ~= nil then return bestLocation end

	-- 没有己方侧安全点时停在当前位置，不会为维持距离主动绕到敌人后方。
	return botLocation
end

local function IsCastLifecycleProtected(bot)
	if bot:HasModifier(FLIGHT_MODIFIER) or bot:HasModifier(CHARGE_MODIFIER) then return true end
	local ability02 = bot:GetAbilityByName(NITORI02)
	if ability02 ~= nil
	and (SafeCall(ability02, "IsInAbilityPhase", false) or SafeCall(ability02, "IsChanneling", false))
	then
		return true
	end
	if DotaTime() - (bot.nitoriLastCombatActionTime or -90) <= ACTION_LOCK_TIME then return true end
	if BOT_ACTION_TYPE_USE_ABILITY ~= nil
	and SafeCall(bot, "GetCurrentActionType", -1) == BOT_ACTION_TYPE_USE_ABILITY
	then
		return true
	end
	return false
end

local function IsMovementBlocked(bot)
	return SafeCall(bot, "IsStunned", false)
		or SafeCall(bot, "IsNightmared", false)
		or SafeCall(bot, "IsRooted", false)
		or SafeCall(bot, "IsChanneling", false)
		or SafeCall(bot, "IsCastingAbility", false)
		or SafeCall(bot, "IsUsingAbility", false)
end

local function CanPoke(bot, snapshot)
	if not IsSpellProfile(bot) or not SafeCall(bot, "IsAlive", false) then return false end
	if ShouldYield(bot) then return false end
	if J.IsInLaningPhase() and SafeCall(bot, "GetActiveMode", BOT_MODE_NONE) == BOT_MODE_LANING then
		-- 对线期交还给正常对线模式，只由技能入口进行远程消耗，不强制维持团战环带。
		return false
	end
	local ability02 = bot:GetAbilityByName(NITORI02)
	if ability02 == nil or not SafeCall(ability02, "IsTrained", false) then return false end
	if snapshot == nil or #snapshot.enemies == 0 then return false end

	local teamFight = J.IsInTeamFight(bot, SEARCH_RANGE) or #snapshot.enemies >= 2
	local supportedEngage = J.IsGoingOnSomeone(bot) and J.GetAllyCount(bot, SEARCH_RANGE) >= 1
	return teamFight or supportedEngage
end

local function ClearHarvest(bot)
	bot.thdNitoriHarvestState = nil
end

local function GetAbilityDuration(ability)
	local level = math.max(SafeCall(ability, "GetLevel", 1), 1)
	local fallback = ({3.0, 3.5, 4.0, 4.5})[level] or 4.5
	local duration = SafeCall(ability, "GetSpecialValueFloat", nil, "duration")
	if duration == nil or duration <= 0 then duration = fallback end
	return duration
end

local function GetProjectedLocation(origin, toward, distance)
	local dx, dy = toward.x - origin.x, toward.y - origin.y
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1 then return origin end
	return Vector(origin.x + dx / length * distance, origin.y + dy / length * distance, origin.z or 0)
end

local function IsHarvestCandidate(bot, target, ability01, ability03, snapshot)
	if not IsVisibleEnemy(bot, target) or SafeCall(target, "IsMagicImmune", false) then return false end
	if ability01 == nil or ability03 == nil
		or not SafeCall(ability01, "IsFullyCastable", false)
		or not SafeCall(ability03, "IsFullyCastable", false)
	then
		return false
	end
	if SafeCall(bot, "GetMana", 0) < 150 or GetHP(bot) < 0.65 then return false end

	local distance = GetUnitToUnitDistance(bot, target)
	if distance < HARVEST_MIN_RANGE or distance > HARVEST_MAX_RANGE then return false end
	local targetLocation = target:GetLocation()
	local landing = GetProjectedLocation(bot:GetLocation(), targetLocation, 333 * GetAbilityDuration(ability01))
	if not IsLocationPassable(landing) then return false end
	local highGroundTowers = NitoriCombat.GetEnemyHighGroundTowers(landing, TOWER_DANGER_RANGE)
	for _, tower in pairs(NitoriCombat.GetEnemyHighGroundTowers(targetLocation, TOWER_DANGER_RANGE)) do
		local duplicate = false
		for _, existing in pairs(highGroundTowers) do
			if existing == tower then duplicate = true break end
		end
		if not duplicate then table.insert(highGroundTowers, tower) end
	end
	local highGroundDive = #highGroundTowers > 0
	local towerDive = highGroundDive
		or IsEnemyTowerDanger(bot, landing)
		or IsEnemyTowerDanger(bot, targetLocation)

	local nearbyEnemies = 0
	for _, enemy in pairs(snapshot.enemies) do
		if GetUnitToUnitDistance(target, enemy) <= 700 then nearbyEnemies = nearbyEnemies + 1 end
	end
	local nearbyAllies = J.GetAllyCount(bot, 1000)
	if nearbyAllies < 1 or nearbyEnemies > nearbyAllies + 1 then return false end
	local teamFightHarvest = J.IsInTeamFight(bot, 1200) or #snapshot.enemies >= 2
	if teamFightHarvest and nearbyAllies + 1 <= nearbyEnemies then
		-- 团战只有我方英雄总数明确占优时，才允许从远程 Poke 切换为突进斩杀。
		return false
	end
	if highGroundDive then
		if not J.IsInTeamFight(bot, 1200) or nearbyAllies < 2 then return false end
		for _, tower in pairs(highGroundTowers) do
			if not SafeCall(tower, "CanBeSeen", false) then return false end
			local towerTarget = SafeCall(tower, "GetAttackTarget", nil)
			if towerTarget == nil or towerTarget == bot
				or not SafeCall(towerTarget, "IsAlive", false)
				or not SafeCall(towerTarget, "IsHero", false)
				or SafeCall(towerTarget, "GetTeam", -1) ~= bot:GetTeam()
			then
				return false
			end
		end
	end
	if towerDive then
		local minimumHP = highGroundDive and HIGH_GROUND_DIVE_MIN_HP or TOWER_DIVE_MIN_HP
		if GetHP(bot) < minimumHP
			or SafeCall(bot, "WasRecentlyDamagedByTower", false, 1.0)
			or nearbyAllies < nearbyEnemies
		then
			return false
		end
	end

	local actualDamage = NitoriCombat.GetHarvestActualDamage(bot, target, ability03)
	local damageSafety = highGroundDive and HIGH_GROUND_DIVE_DAMAGE_SAFETY
		or (towerDive and TOWER_DIVE_DAMAGE_SAFETY or HARVEST_DAMAGE_SAFETY)
	return SafeCall(target, "GetHealth", math.huge) <= actualDamage * damageSafety,
		highGroundDive, teamFightHarvest
end

local function FindHarvestTarget(bot, snapshot)
	local ability01 = bot:GetAbilityByName(NITORI01)
	local ability03 = bot:GetAbilityByName(NITORI03)
	local best, bestScore, bestHighGroundDive, bestTeamFightHarvest = nil, -math.huge, false, false
	for _, enemy in pairs(snapshot.enemies) do
		local valid, highGroundDive, teamFightHarvest = IsHarvestCandidate(bot, enemy, ability01, ability03, snapshot)
		if valid then
			local damage = math.max(NitoriCombat.GetHarvestActualDamage(bot, enemy, ability03), 1)
			local score = (1 - SafeCall(enemy, "GetHealth", damage) / damage) * 10
				- GetUnitToUnitDistance(bot, enemy) / HARVEST_MAX_RANGE
			if score > bestScore then
				best, bestScore = enemy, score
				bestHighGroundDive = highGroundDive == true
				bestTeamFightHarvest = teamFightHarvest == true
			end
		end
	end
	return best, bestHighGroundDive, bestTeamFightHarvest
end

local function UpdateHarvestState(bot, snapshot)
	local state = bot.thdNitoriHarvestState
	if state ~= nil then
		if DotaTime() > state.expires or not IsVisibleEnemy(bot, state.target) or ShouldYield(bot) then
			ClearHarvest(bot)
			return nil
		end
		if state.launched then
			if bot:HasModifier(FLIGHT_MODIFIER) then state.flightSeen = true end
			if (state.flightSeen and not bot:HasModifier(FLIGHT_MODIFIER))
			or (not state.flightSeen and DotaTime() - state.launchTime > 0.8)
			then
				ClearHarvest(bot)
				return nil
			end
			return state
		end
		local ability01 = bot:GetAbilityByName(NITORI01)
		local ability03 = bot:GetAbilityByName(NITORI03)
		local valid, highGroundDive, teamFightHarvest = IsHarvestCandidate(bot, state.target, ability01, ability03, snapshot)
		if not valid then
			ClearHarvest(bot)
			return nil
		end
		state.allowHighGroundHarvest = highGroundDive == true
		state.requireTeamFightAdvantage = teamFightHarvest == true
		return state
	end

	local target, highGroundDive, teamFightHarvest = FindHarvestTarget(bot, snapshot)
	if target == nil then return nil end
	state = {
		target = target,
		expires = DotaTime() + HARVEST_TIMEOUT,
		allowHighGroundHarvest = highGroundDive == true,
		requireTeamFightAdvantage = teamFightHarvest == true,
	}
	bot.thdNitoriHarvestState = state
	return state
end

function NitoriPoke.GetHarvestTarget(bot)
	local state = bot ~= nil and bot.thdNitoriHarvestState or nil
	if state == nil or DotaTime() > state.expires then return nil end
	if not IsVisibleEnemy(bot, state.target) then return nil end
	return state.target
end

function NitoriPoke.GetModeDesire(bot)
	local snapshot = IsSpellProfile(bot) and GetSnapshot(bot) or nil
	local active = CanPoke(bot, snapshot)
	bot.thdNitoriPokeActive = active
	if not active then
		ClearHarvest(bot)
		return BOT_MODE_DESIRE_NONE
	end
	UpdateHarvestState(bot, snapshot)
	return BOT_MODE_DESIRE_VERYHIGH + 0.05
end

function NitoriPoke.Think(bot)
	-- mode_roam_generic 会为所有英雄调用 Think，先做常量级过滤再扫描单位。
	if not IsSpellProfile(bot) then return false end
	local snapshot = GetSnapshot(bot)
	if not CanPoke(bot, snapshot) then
		bot.thdNitoriPokeActive = false
		return false
	end
	bot.thdNitoriPokeActive = true
	local harvest = UpdateHarvestState(bot, snapshot)
	if IsCastLifecycleProtected(bot) then return true end
	-- 不使用 J.CanNotUseAction：其中的旧队列动作正可能是需要被覆盖的 Valve 贴脸攻击。
	if IsMovementBlocked(bot) then return true end
	if DotaTime() < (bot.thdNitoriPokeNextMoveTime or -90) then return true end
	bot.thdNitoriPokeNextMoveTime = DotaTime() + MOVE_THINK_INTERVAL

	if harvest ~= nil and not harvest.launched then
		-- 收割阶段只朝锁定目标转向；真正的突进和连招仍由英雄技能入口逐帧执行。
		if not SafeCall(bot, "IsFacingLocation", false, harvest.target:GetLocation(), 25) then
			J.ActionMoveToLocation(bot, "nitori_spell_harvest_face", harvest.target:GetLocation(), 0.2, 80)
		end
		return true
	end
	if harvest ~= nil then return true end

	local location = GetSafeRingLocation(bot, snapshot)
	if location ~= nil then
		-- 只发移动指令维持施法环带；英雄技能 Think 可以随时用更高价值的施法覆盖移动。
		J.ActionMoveToLocation(bot, "nitori_spell_poke", location, 0.3, 80)
	end
	return true
end

function NitoriPoke.OnEnd(bot)
	if bot == nil then return end
	bot.thdNitoriPokeActive = false
	bot.thdNitoriPokeSnapshot = nil
	bot.thdNitoriPokeNextMoveTime = nil
	-- 任务所有权已释放，已启动收割的施法/命中状态仍由英雄入口收尾。
	if not IsCastLifecycleProtected(bot) then ClearHarvest(bot) end
end

return NitoriPoke
