require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")
local NitoriCombat = require(GetScriptDirectory() .. "/THDFuncLib/nitori_combat")

local NITORI01 = "ability_thdots_nitori01"
local NITORI02 = "ability_thdots_nitori02"
local NITORI03 = "ability_thdots_nitori03"
local NITORI04 = "ability_thdots_nitori04"
local FLIGHT_MODIFIER = "modifier_ability_thdots_nitori01"
local CHARGE_MODIFIER = "modifier_ability_thdots_nitori02"
local EMPOWER_MODIFIER = "modifier_ability_thdots_nitori03_passive"
local DRAGON_MODIFIER = "modifier_item_dragon_star_buff"
local HORSE_KING_MODIFIER = "modifier_item_horse_king_open"
local ACTION_GUARD_TIME = 0.05
local DELAYED_DRAGON_WINDOW = 5.25
local NITORI02_PREDICTION = 1.15
local NITORI02_LENGTH = 1200
local NITORI02_HALF_WIDTH = 200

local function GetProfile(bot)
	-- 标记缺失或非法时固定回退输出，不从技能等级反推定位。
	local profile = BotProfile.GetProfile(bot)
	if profile ~= BotProfile.DAMAGE and profile ~= BotProfile.DAMAGE_SPELL then
		return BotProfile.DAMAGE
	end
	return profile
end

local function GetAbility(bot, name)
	local ability = bot:GetAbilityByName(name)
	if ability == nil then return nil end
	if ability.IsTrained ~= nil and not ability:IsTrained() then return nil end
	return ability
end

local function IsCastable(ability)
	return ability ~= nil and ability:IsFullyCastable()
end

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

local function IsVisibleRealEnemy(bot, target, allowMagicImmune)
	if target == nil or SafeCall(target, "IsNull", false) then return false end
	if not SafeCall(target, "IsAlive", true) or not SafeCall(target, "CanBeSeen", true) then return false end
	if SafeCall(target, "GetTeam", bot:GetTeam()) == bot:GetTeam() then return false end
	if SafeCall(target, "IsHero", false) and J.IsSuspiciousIllusion(target) then return false end
	if not allowMagicImmune and SafeCall(target, "IsMagicImmune", false) then return false end
	return not SafeCall(target, "IsInvulnerable", false)
end

local function GetVisibleEnemies(bot, range, allowMagicImmune)
	local result = {}
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, math.min(range, 1600), true, BOT_MODE_NONE)) do
		if IsVisibleRealEnemy(bot, enemy, allowMagicImmune)
		and GetUnitToUnitDistance(bot, enemy) <= range
		then
			table.insert(result, enemy)
		end
	end
	return result
end

local function IsTeleportingSafely(target)
	if IsTeleporting == nil then return false end
	local ok, result = pcall(function() return IsTeleporting(target) end)
	return ok and result == true
end

local function IsHardDisabled(target)
	return SafeCall(target, "IsStunned", false) or SafeCall(target, "IsHexed", false)
end

local function MarkItemAction(bot)
	bot.nitoriLastItemActionTime = DotaTime()
	bot.nitoriLastCombatActionTime = DotaTime()
end

local function UseAbility(bot, ability)
	bot:Action_UseAbility(ability)
	bot.nitoriLastCombatActionTime = DotaTime()
end

local function UseAbilityOnEntity(bot, ability, target)
	bot:Action_UseAbilityOnEntity(ability, target)
	bot.nitoriLastCombatActionTime = DotaTime()
end

local function UseAbilityOnLocation(bot, ability, location)
	bot:Action_UseAbilityOnLocation(ability, location)
	bot.nitoriLastCombatActionTime = DotaTime()
end

local function WasItemActionJustIssued(bot)
	return DotaTime() - (bot.nitoriLastItemActionTime or -90) <= ACTION_GUARD_TIME
end

local function UseNoTargetItem(bot, item)
	bot:Action_UseAbility(item)
	MarkItemAction(bot)
	return true
end

local function TryUseYukkuri(bot, enemies, profile, interruptOnly)
	if profile ~= BotProfile.DAMAGE_SPELL then return false end
	local item = IsItemAvailable("item_yukkuri_stick")
	if item == nil or not item:IsFullyCastable() then return false end
	local castRange = SafeCall(item, "GetCastRange", 600)

	for _, enemy in pairs(enemies) do
		if IsVisibleRealEnemy(bot, enemy, false)
		and GetUnitToUnitDistance(bot, enemy) <= castRange
		and not IsHardDisabled(enemy)
		and (SafeCall(enemy, "IsChanneling", false) or IsTeleportingSafely(enemy))
		then
			bot:Action_UseAbilityOnEntity(item, enemy)
			MarkItemAction(bot)
			return true
		end
	end
	if interruptOnly then return false end

	local target = J.GetProperTarget(bot)
	if J.IsGoingOnSomeone(bot)
	and IsVisibleRealEnemy(bot, target, false)
	and GetUnitToUnitDistance(bot, target) <= castRange
	and not IsHardDisabled(target)
	then
		bot:Action_UseAbilityOnEntity(item, target)
		MarkItemAction(bot)
		return true
	end
	return false
end

local function TryUsePomojinlingli(bot, enemies, profile, interruptOnly)
	if profile ~= BotProfile.DAMAGE_SPELL then return false end
	local item = IsItemAvailable("item_pomojinlingli")
	if item == nil or not item:IsFullyCastable() then return false end
	local castRange = SafeCall(item, "GetCastRange", 750)

	for _, enemy in pairs(enemies) do
		if IsVisibleRealEnemy(bot, enemy, false)
		and GetUnitToUnitDistance(bot, enemy) <= castRange
		and not IsHardDisabled(enemy)
		and SafeCall(enemy, "IsChanneling", false)
		and not IsTeleportingSafely(enemy)
		then
			bot:Action_UseAbilityOnEntity(item, enemy)
			MarkItemAction(bot)
			return true
		end
	end
	if interruptOnly then return false end

	local target = J.GetProperTarget(bot)
	if J.IsGoingOnSomeone(bot)
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and IsVisibleRealEnemy(bot, target, false)
	and not IsTeleportingSafely(target)
	and GetUnitToUnitDistance(bot, target) <= castRange
	and not IsHardDisabled(target)
	then
		-- 先施加沉默与伤害记录，再让后续炮击触发结束时的追加魔法伤害。
		bot:Action_UseAbilityOnEntity(item, target)
		MarkItemAction(bot)
		return true
	end
	return false
end

local function TryUseTrinity(bot, enemies)
	local item = IsItemAvailable("item_trinity")
	if item == nil or not item:IsFullyCastable() then return false end
	local underPressure = bot:WasRecentlyDamagedByAnyHero(2.0)
		and #enemies > 0 and (GetHP(bot) < 0.55 or J.IsSeriouslyRetreating(bot))
	local preShield = #enemies >= 2 and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	if underPressure or preShield then return UseNoTargetItem(bot, item) end
	return false
end

local function HasScepterPower(bot)
	return SafeCall(bot, "HasScepter", false) or bot:HasModifier("modifier_item_wanbaochui")
end

local function HasExtendedNitori01Duration(bot)
	local talent = GetAbility(bot, "special_bonus_unique_nitori_3")
	return talent ~= nil and SafeCall(talent, "GetLevel", 0) > 0
end

local function ShouldDelayDragonStar(bot)
	return HasScepterPower(bot)
		and HasExtendedNitori01Duration(bot)
		and IsCastable(GetAbility(bot, NITORI01))
end

local function TryUseDragonStar(bot, enemies)
	local item = IsItemAvailable("item_dragon_star")
	if item == nil or not item:IsFullyCastable() then return false end
	if J.IsSeriouslyRetreating(bot, NITORI01)
	and bot:WasRecentlyDamagedByAnyHero(2.0) and #enemies > 0
	then
		return UseNoTargetItem(bot, item)
	end
	local target = J.GetProperTarget(bot)
	if (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and IsVisibleRealEnemy(bot, target, true)
	and GetUnitToUnitDistance(bot, target) <= 1000
	then
		-- 推进器延长到6秒后，提前开启的6秒龙星无法稳定覆盖结束自晕，改在飞行中补开。
		if ShouldDelayDragonStar(bot) then return false end
		return UseNoTargetItem(bot, item)
	end
	return false
end

local function TryUseHorseRed(bot, enemies)
	local item = IsItemAvailable("item_horse_red")
	if item == nil or not item:IsFullyCastable() then return false end
	if #enemies == 0 and not bot:WasRecentlyDamagedByAnyHero(4.0)
	and GetHP(bot) < 0.72 and not J.IsGoingOnSomeone(bot)
	then
		return UseNoTargetItem(bot, item)
	end
	return false
end

local function TryUseHorseKing(bot, enemies)
	local item = IsItemAvailable("item_horse_king")
	if item == nil or not item:IsFullyCastable() then return false end
	local active = bot:HasModifier(HORSE_KING_MODIFIER)
	local shouldEnable = (#enemies > 0 and GetMP(bot) > 0.2
		and (J.IsGoingOnSomeone(bot) or J.IsSeriouslyRetreating(bot)))
	local shouldDisable = active and (#enemies == 0 or GetMP(bot) < 0.16
		or (not J.IsGoingOnSomeone(bot) and not J.IsRetreating(bot)))
	if (shouldEnable and not active) or shouldDisable then return UseNoTargetItem(bot, item) end
	return false
end

local function TryUseActiveItems(bot, enemies, profile, interruptOnly)
	-- 控制、护盾和强驱散按开团链顺序逐帧执行；每次只发出一个动作。
	if TryUsePomojinlingli(bot, enemies, profile, true) then return true end
	if TryUseYukkuri(bot, enemies, profile, true) then return true end
	if interruptOnly then return false end
	if TryUseTrinity(bot, enemies) then return true end
	if TryUsePomojinlingli(bot, enemies, profile, false) then return true end
	if TryUseYukkuri(bot, enemies, profile, false) then return true end
	if TryUseDragonStar(bot, enemies) then return true end
	if TryUseHorseRed(bot, enemies) then return true end
	if TryUseHorseKing(bot, enemies) then return true end
	return false
end

local function GetSpecialValue(ability, key, fallback)
	local value = SafeCall(ability, "GetSpecialValueInt", nil, key)
	if value == nil then value = SafeCall(ability, "GetSpecialValueFloat", nil, key) end
	return value ~= nil and value or fallback
end

local function GetLocation(unit)
	return SafeCall(unit, "GetLocation", Vector(0, 0, 0))
end

local function MakeVector(x, y, z)
	return Vector(x, y, z or 0)
end

local function ProjectLocation(startLocation, towardLocation, distance)
	local dx = towardLocation.x - startLocation.x
	local dy = towardLocation.y - startLocation.y
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1 then return startLocation end
	return MakeVector(startLocation.x + dx / length * distance,
		startLocation.y + dy / length * distance, startLocation.z or 0)
end

local function IsPassable(location)
	if IsLocationPassable == nil then return true end
	local ok, result = pcall(function() return IsLocationPassable(location) end)
	return not ok or result == true
end

local function IsEnemyTowerDanger(bot, location)
	if UNIT_LIST_ENEMY_BUILDINGS == nil then return false end
	for _, building in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
		if building ~= nil and SafeCall(building, "IsAlive", true)
		and SafeCall(building, "CanBeSeen", true)
		and SafeCall(building, "IsTower", true)
		and GetUnitToLocationDistance(building, location) <= 900
		and J.GetAllyCount(bot, 1000) < J.GetEnemyCount(bot, 1000)
		then
			return true
		end
	end
	return false
end

local function HasDragonProtection(bot)
	if bot:HasModifier(DRAGON_MODIFIER) then return true end
	-- 兼容游戏侧物品采用的旧修饰器命名。
	return bot:HasModifier("modifier_item_dragon_star")
end

local function GetModifierRemainingTime(unit, modifierName)
	local index = SafeCall(unit, "GetModifierByName", -1, modifierName)
	if index == nil or index == -1 then return nil end
	return SafeCall(unit, "GetModifierRemainingDuration", nil, index)
end

local function TryUseDelayedDragonStar(bot)
	if not bot:HasModifier(FLIGHT_MODIFIER)
	or not HasScepterPower(bot)
	or not HasExtendedNitori01Duration(bot)
	or HasDragonProtection(bot)
	then
		return false
	end
	local item = IsItemAvailable("item_dragon_star")
	if item == nil or not item:IsFullyCastable() then return false end
	local remaining = GetModifierRemainingTime(bot, FLIGHT_MODIFIER)
	-- 无法读取剩余时间时在首个飞行帧兜底开启；正常路径延后约0.75秒以覆盖结束自晕。
	if remaining == nil or remaining <= DELAYED_DRAGON_WINDOW then
		return UseNoTargetItem(bot, item)
	end
	return false
end

local function GetNitori01Duration(ability)
	local fallback = ({3.0, 3.5, 4.0, 4.5})[math.max(SafeCall(ability, "GetLevel", 1), 1)] or 4.5
	local duration = SafeCall(ability, "GetSpecialValueFloat", nil, "duration")
	if duration == nil or duration <= 0 then return fallback end
	return duration
end

local function IsSafeNitori01Landing(bot, ability, towardLocation)
	local distance = 333 * GetNitori01Duration(ability)
	local endpoint = ProjectLocation(GetLocation(bot), towardLocation, distance)
	return IsPassable(endpoint) and not IsEnemyTowerDanger(bot, endpoint)
end

local function ConsiderNitori01(bot, ability, enemies)
	if not IsCastable(ability) or bot:IsRooted() then return false end
	local fountain = GetShopLocation(bot:GetTeam(), SHOP_HOME)
	if J.IsSeriouslyRetreating(bot, NITORI01) and #enemies > 0
	and bot:IsFacingLocation(fountain, 25)
	then
		local botDistance = GetUnitToLocationDistance(bot, fountain)
		local endpoint = ProjectLocation(GetLocation(bot), fountain, 333 * GetNitori01Duration(ability))
		local closest = enemies[1]
		for _, enemy in pairs(enemies) do
			if GetUnitToUnitDistance(bot, enemy) < GetUnitToUnitDistance(bot, closest) then closest = enemy end
		end
		if IsPassable(endpoint)
		and GetUnitToLocationDistance(closest, endpoint) > GetUnitToUnitDistance(bot, closest) + 250
		and GetUnitToLocationDistance(bot, endpoint) > math.min(botDistance, 300)
		then
			return true
		end
	end

	local target = J.GetProperTarget(bot)
	if not (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	or bot:GetActiveModeDesire() < BOT_MODE_DESIRE_HIGH
	or not IsVisibleRealEnemy(bot, target, true)
	then
		return false
	end
	local distance = GetUnitToUnitDistance(bot, target)
	if distance < 350 or distance > 1150 or not bot:IsFacingLocation(GetLocation(target), 25) then return false end
	if not IsSafeNitori01Landing(bot, ability, GetLocation(target)) then return false end

	local minimumHP = GetProfile(bot) == BotProfile.DAMAGE_SPELL and 0.65 or 0.6
	if HasScepterPower(bot) and not HasDragonProtection(bot) then
		minimumHP = 0.8
		if J.GetAllyCount(bot, 1000) < J.GetEnemyCount(bot, 1000) then return false end
	end
	return GetHP(bot) >= minimumHP
end

local function GetHarvestTarget(bot)
	local state = bot.thdNitoriHarvestState
	if state == nil or DotaTime() > (state.expires or -90) then return nil end
	if not IsVisibleRealEnemy(bot, state.target, false) then return nil end
	return state.target
end

local function ConsiderNitori01Harvest(bot, ability, target)
	if target == nil or not IsCastable(ability) or bot:IsRooted() then return false end
	local distance = GetUnitToUnitDistance(bot, target)
	if distance < 350 or distance > 1150 then return false end
	if not bot:IsFacingLocation(GetLocation(target), 25) then return false end
	local landingDistance = 333 * GetNitori01Duration(ability)
	local landing = ProjectLocation(GetLocation(bot), GetLocation(target), landingDistance)
	if not IsPassable(landing) then return false end
	local highGroundDanger = NitoriCombat.IsEnemyHighGroundTowerDanger(landing, 900)
		or NitoriCombat.IsEnemyHighGroundTowerDanger(GetLocation(target), 900)
	local harvestState = bot.thdNitoriHarvestState
	if highGroundDanger and (harvestState == nil or not harvestState.allowHighGroundHarvest) then return false end
	local allyCount = J.GetAllyCount(bot, 1000)
	local enemyCount = J.GetEnemyCount(bot, 1000)
	if GetHP(bot) < 0.65 or allyCount < enemyCount then return false end
	if harvestState ~= nil and harvestState.requireTeamFightAdvantage
	and allyCount + 1 <= enemyCount
	then
		return false
	end
	return true
end

local function MarkHarvestLaunched(bot)
	local state = bot.thdNitoriHarvestState
	if state == nil then return end
	state.launched = true
	state.launchTime = DotaTime()
	state.expires = DotaTime() + 7.0
end

local function DistanceToRaySegment(point, origin, endpoint)
	local vx, vy = endpoint.x - origin.x, endpoint.y - origin.y
	local wx, wy = point.x - origin.x, point.y - origin.y
	local lengthSquared = vx * vx + vy * vy
	if lengthSquared <= 0 then return math.huge, 0 end
	local t = math.max(0, math.min(1, (wx * vx + wy * vy) / lengthSquared))
	local px, py = origin.x + vx * t, origin.y + vy * t
	local dx, dy = point.x - px, point.y - py
	return math.sqrt(dx * dx + dy * dy), t
end

local function GetPredictedLocation(unit)
	local predicted = SafeCall(unit, "GetExtrapolatedLocation", nil, NITORI02_PREDICTION)
	return predicted or GetLocation(unit)
end

local function GetLineCandidates(bot, profile)
	local candidates = {}
	local function AddUnits(list, weight, kind)
		for _, unit in pairs(list or {}) do
			if unit ~= nil and SafeCall(unit, "IsAlive", true) and SafeCall(unit, "CanBeSeen", true)
			and GetUnitToUnitDistance(bot, unit) <= NITORI02_LENGTH + 100
			then
				table.insert(candidates, {unit = unit, location = GetPredictedLocation(unit), weight = weight, kind = kind})
			end
		end
	end
	AddUnits(GetVisibleEnemies(bot, NITORI02_LENGTH + 100, false), 5, "hero")
	AddUnits(SafeCall(bot, "GetNearbyLaneCreeps", {}, NITORI02_LENGTH + 100, true), 1, "creep")
	AddUnits(SafeCall(bot, "GetNearbyNeutralCreeps", {}, NITORI02_LENGTH + 100), 1, "creep")
	local buildingMana = profile == BotProfile.DAMAGE_SPELL and 0.35 or 0.7
	if GetMP(bot) >= buildingMana and #GetVisibleEnemies(bot, NITORI02_LENGTH, false) == 0 then
		local enemyBuildings = UNIT_LIST_ENEMY_BUILDINGS ~= nil
			and GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)
			or SafeCall(bot, "GetNearbyTowers", {}, NITORI02_LENGTH, true)
		AddUnits(enemyBuildings, 2, "building")
	end
	return candidates
end

local function ScoreNitori02Line(bot, endpoint, candidates)
	local origin = GetLocation(bot)
	local hits = {}
	local score = 0
	for _, candidate in pairs(candidates) do
		local distance, along = DistanceToRaySegment(candidate.location, origin, endpoint)
		if distance <= NITORI02_HALF_WIDTH and along > 0 then
			table.insert(hits, {candidate = candidate, along = along})
			score = score + candidate.weight
		end
	end
	table.sort(hits, function(a, b) return a.along < b.along end)
	return score, hits
end

local function GetNitori02Damage(bot, ability, priorHits)
	local base = GetSpecialValue(ability, "damage", ({90, 140, 190, 240})[SafeCall(ability, "GetLevel", 1)] or 90)
	local talent = GetAbility(bot, "special_bonus_unique_nitori_2")
	local noDecay = talent ~= nil and SafeCall(talent, "GetLevel", 0) > 0
	local factor = noDecay and 1 or math.max(0, 1 - 0.1 * priorHits)
	return base + SafeCall(bot, "GetIntellect", 0) * 2 * factor
end

local function IsLaningPressureWindow(bot)
	return J.IsInLaningPhase()
		and bot:GetActiveMode() == BOT_MODE_LANING
		and not J.IsRetreating(bot)
end

local function FindLaningNitori02Target(bot, candidates, profile)
	if not IsLaningPressureWindow(bot)
	or GetMP(bot) < (profile == BotProfile.DAMAGE_SPELL and 0.5 or 0.65)
	or GetHP(bot) < 0.6
	or bot:WasRecentlyDamagedByAnyHero(2.5)
	or J.GetEnemyCount(bot, 450) > 0
	or #SafeCall(bot, "GetNearbyTowers", {}, 850, true) > 0
	then
		return nil
	end

	local bestEndpoint, bestScore = nil, -math.huge
	for _, candidate in pairs(candidates) do
		local distance = GetUnitToUnitDistance(bot, candidate.unit)
		if candidate.kind == "hero" and distance >= 550 and distance <= NITORI02_LENGTH then
			local endpoint = ProjectLocation(GetLocation(bot), candidate.location, NITORI02_LENGTH)
			local _, hits = ScoreNitori02Line(bot, endpoint, candidates)
			for index, hit in ipairs(hits) do
				if hit.candidate.unit == candidate.unit then
					local priorHits = index - 1
					-- 对线只接受至多一个前置单位，避免用高蓝耗炮击打出过度衰减的消耗。
					if priorHits <= 1 then
						local score = (1 - priorHits * 0.25) + (1 - GetHP(candidate.unit))
						if score > bestScore then bestEndpoint, bestScore = endpoint, score end
					end
					break
				end
			end
		end
	end
	return bestEndpoint
end

local function ConsiderNitori02(bot, ability, profile)
	if not IsCastable(ability) or bot:HasModifier(FLIGHT_MODIFIER) then return nil end
	local candidates = GetLineCandidates(bot, profile)
	if profile == BotProfile.DAMAGE_SPELL and J.IsPushing(bot)
	and GetMP(bot) >= 0.35 and #GetVisibleEnemies(bot, NITORI02_LENGTH, false) == 0
	then
		local buildingEndpoint, buildingScore = nil, -math.huge
		for _, candidate in pairs(candidates) do
			if candidate.kind == "building" and not SafeCall(candidate.unit, "IsInvulnerable", false) then
				local endpoint = ProjectLocation(GetLocation(bot), candidate.location, NITORI02_LENGTH)
				local score = ScoreNitori02Line(bot, endpoint, candidates)
				if score > buildingScore then buildingEndpoint, buildingScore = endpoint, score end
			end
		end
		-- 法术路线拥有额外基础回蓝，安全推进时主动用炮击同时压塔和清理塔前单位。
		if buildingEndpoint ~= nil then return buildingEndpoint end
	end
	local bestEndpoint, bestScore, bestHits = nil, 0, nil
	for _, candidate in pairs(candidates) do
		local endpoint = ProjectLocation(GetLocation(bot), candidate.location, NITORI02_LENGTH)
		local score, hits = ScoreNitori02Line(bot, endpoint, candidates)
		if score > bestScore then bestEndpoint, bestScore, bestHits = endpoint, score, hits end
	end
	if bestEndpoint == nil then return nil end

	for index, hit in ipairs(bestHits) do
		if hit.candidate.kind == "hero"
		and J.CanKillTarget(hit.candidate.unit, GetNitori02Damage(bot, ability, index - 1), DAMAGE_TYPE_MAGICAL)
		then
			return bestEndpoint
		end
	end
	if J.IsSeriouslyRetreating(bot, NITORI02) then
		local closestDistance = math.huge
		for _, hit in ipairs(bestHits) do
			if hit.candidate.kind == "hero" then
				closestDistance = math.min(closestDistance, GetUnitToUnitDistance(bot, hit.candidate.unit))
			end
		end
		-- 近身时一秒自晕比减速更危险，撤退路径不强行蓄力。
		if closestDistance >= 450 then return bestEndpoint end
		return nil
	end
	local laningTarget = FindLaningNitori02Target(bot, candidates, profile)
	if laningTarget ~= nil then return laningTarget end
	if profile == BotProfile.DAMAGE_SPELL and GetMP(bot) >= 0.35
	and (J.IsInTeamFight(bot, 1200) or J.IsGoingOnSomeone(bot))
	then
		for _, hit in ipairs(bestHits) do
			if hit.candidate.kind == "hero" then return bestEndpoint end
		end
	end
	if bestScore >= 8 and (J.IsInTeamFight(bot, 1200) or J.IsGoingOnSomeone(bot)) then return bestEndpoint end
	local creepHits = 0
	for _, hit in ipairs(bestHits) do if hit.candidate.kind == "creep" then creepHits = creepHits + 1 end end
	local clearThreshold = profile == BotProfile.DAMAGE_SPELL and 3 or 4
	local clearMana = profile == BotProfile.DAMAGE_SPELL and 0.4 or 0.55
	if creepHits >= clearThreshold and GetMP(bot) >= clearMana then return bestEndpoint end
	return nil
end

local function GetNitori03Damage(bot, ability)
	return NitoriCombat.GetNitori03RawDamage(bot, ability)
end

local function ConsiderNitori03(bot, ability, enemies, inFlight)
	if not IsCastable(ability) then return false end
	local closeHeroes = {}
	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= 250 then table.insert(closeHeroes, enemy) end
	end
	for _, enemy in pairs(closeHeroes) do
		if J.CanKillTarget(enemy, GetNitori03Damage(bot, ability), DAMAGE_TYPE_MAGICAL) then return true end
	end
	if #closeHeroes > 0 and (inFlight or J.IsInTeamFight(bot, 700) or J.IsSeriouslyRetreating(bot, NITORI03)) then return true end
	if #closeHeroes > 0 and IsLaningPressureWindow(bot)
	and GetMP(bot) >= 0.55 and GetHP(bot) >= 0.55
	and not bot:WasRecentlyDamagedByAnyHero(2.0)
	and #SafeCall(bot, "GetNearbyTowers", {}, 700, true) == 0
	then
		-- 敌人主动贴近时用近身反应压血线，保留足够蓝量并避开敌塔反打。
		return true
	end
	local creeps = SafeCall(bot, "GetNearbyLaneCreeps", {}, 250, true)
	if #creeps >= 3 and GetMP(bot) >= 0.45 then return true end
	return false
end

local function GetExpectedFunnelCount(bot, ability)
	if ability == nil then return 0 end
	local level = math.max(SafeCall(ability, "GetLevel", 1), 1)
	local base = GetSpecialValue(ability, "number", ({3, 4, 5})[level] or 5)
	local talent = GetAbility(bot, "special_bonus_unique_nitori_5")
	if talent ~= nil and SafeCall(talent, "GetLevel", 0) > 0 then base = base + 3 end
	return base
end

local function FindNitori04Target(bot, ability, enemies)
	if not IsCastable(ability) then return nil end
	local castRange = SafeCall(ability, "GetCastRange", 800)
	local funnelCount = GetExpectedFunnelCount(bot, ability)
	local best, bestScore = nil, -math.huge
	for _, enemy in pairs(enemies) do
		if IsVisibleRealEnemy(bot, enemy, false)
		and GetUnitToUnitDistance(bot, enemy) <= castRange
		then
			local cluster = 0
			for _, other in pairs(enemies) do
				if GetUnitToUnitDistance(enemy, other) <= 250 then cluster = cluster + 1 end
			end
			-- 优先能承受浮游炮持续输出的团战中心，避免浪费在濒死目标上。
			local durability = GetHP(enemy) >= 0.2 and GetHP(enemy) or -0.5
			local score = cluster * 10 + durability * math.min(funnelCount, 8) / 2
			if score > bestScore then best, bestScore = enemy, score end
		end
	end
	if best ~= nil and (bestScore >= 20 or J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200)) then return best end
	return nil
end

local function TryConsumeEmpoweredAttack(bot, inFlight)
	local profile = GetProfile(bot)
	local harvestState = bot.thdNitoriHarvestState
	local harvestTarget = profile == BotProfile.DAMAGE_SPELL
		and harvestState ~= nil and harvestState.launched
		and GetHarvestTarget(bot) or nil
	if profile ~= BotProfile.DAMAGE and harvestTarget == nil then return false end
	if not bot:HasModifier(EMPOWER_MODIFIER) then return false end
	if not inFlight and not J.IsGoingOnSomeone(bot) and not J.IsInTeamFight(bot, 700) then return false end
	local target = harvestTarget or J.GetProperTarget(bot)
	if not IsVisibleRealEnemy(bot, target, true) then return false end
	local attackRange = SafeCall(bot, "GetAttackRange", 150) + 100
	if GetUnitToUnitDistance(bot, target) > attackRange or IsEnemyTowerDanger(bot, GetLocation(target)) then return false end
	bot:Action_AttackUnit(target, true)
	bot.nitoriLastCombatActionTime = DotaTime()
	if harvestTarget ~= nil then bot.thdNitoriHarvestState.attackIssued = true end
	return true
end

local function TryUseHarvestNitori03(bot, ability, target)
	if target == nil or not IsCastable(ability) then return false end
	if GetUnitToUnitDistance(bot, target) > 250 then return false end
	UseAbility(bot, ability)
	if bot.thdNitoriHarvestState ~= nil then bot.thdNitoriHarvestState.ability03Issued = true end
	return true
end

function AbilityUsageThink()
	local bot = GetBot()
	if bot == nil or not SafeCall(bot, "IsAlive", true) then return end
	local ability01 = GetAbility(bot, NITORI01)
	local ability02 = GetAbility(bot, NITORI02)
	local ability03 = GetAbility(bot, NITORI03)
	local ability04 = GetAbility(bot, NITORI04)

	-- 炮击前摇和一秒蓄力自晕期间必须保持动作，不允许任何替换命令。
	if (ability02 ~= nil and (SafeCall(ability02, "IsInAbilityPhase", false) or SafeCall(ability02, "IsChanneling", false)))
	or bot:HasModifier(CHARGE_MODIFIER)
	then
		return
	end
	if WasItemActionJustIssued(bot) or J.CanNotUseAction(bot) then return end

	local profile = GetProfile(bot)
	local enemies = GetVisibleEnemies(bot, 1300, true)
	local inFlight = bot:HasModifier(FLIGHT_MODIFIER)
	if inFlight then
		-- 延后开启龙星覆盖推进器结束自晕；追击中先打掉已有强化普攻，再用技能刷新。
		if TryUseDelayedDragonStar(bot) then return end
		local harvestTarget = GetHarvestTarget(bot)
		if harvestTarget ~= nil then
			if TryConsumeEmpoweredAttack(bot, true) then return end
			if TryUseHarvestNitori03(bot, ability03, harvestTarget) then return end
			return
		end
		if TryConsumeEmpoweredAttack(bot, true) then return end
		-- 飞行中绝不施放炮击；万宝槌窗口随后使用浮游炮和低冷却近身反应。
		local ultimateTarget = FindNitori04Target(bot, ability04, enemies)
		if ultimateTarget ~= nil then
			UseAbilityOnEntity(bot, ability04, ultimateTarget)
			return
		end
		if ConsiderNitori03(bot, ability03, enemies, true) then
			UseAbility(bot, ability03)
			return
		end
		if ConsiderNeutralItems ~= nil then ConsiderNeutralItems() end
		return
	end

	if TryUseActiveItems(bot, enemies, profile, false) then return end

	if ConsiderNitori03(bot, ability03, enemies, false)
	and J.IsSeriouslyRetreating(bot, NITORI03)
	then
		UseAbility(bot, ability03)
		return
	end
	if TryConsumeEmpoweredAttack(bot, false) then return end
	if J.IsSeriouslyRetreating(bot, NITORI01) and ConsiderNitori01(bot, ability01, enemies) then
		UseAbility(bot, ability01)
		return
	end
	if profile == BotProfile.DAMAGE_SPELL then
		local harvestTarget = GetHarvestTarget(bot)
		if harvestTarget ~= nil then
			local state = bot.thdNitoriHarvestState
			if state ~= nil and not state.launched
			and ConsiderNitori01Harvest(bot, ability01, harvestTarget)
			then
				UseAbility(bot, ability01)
				MarkHarvestLaunched(bot)
			end
			return
		end
		-- 法术输出先放浮游炮与阳电子炮；推进器只在炮击窗口均不可用时追击。
		local spellUltimateTarget = FindNitori04Target(bot, ability04, enemies)
		if spellUltimateTarget ~= nil then
			UseAbilityOnEntity(bot, ability04, spellUltimateTarget)
			return
		end
		local spellLineTarget = ConsiderNitori02(bot, ability02, profile)
		if spellLineTarget ~= nil then
			UseAbilityOnLocation(bot, ability02, spellLineTarget)
			return
		end
		if ConsiderNitori03(bot, ability03, enemies, false) then
			UseAbility(bot, ability03)
			return
		end
		local keepPokeDistance = bot.thdNitoriPokeActive
			or J.IsInTeamFight(bot, 1300)
			or IsLaningPressureWindow(bot)
		if not keepPokeDistance and ConsiderNitori01(bot, ability01, enemies) then
			UseAbility(bot, ability01)
			return
		end
		if ConsiderNeutralItems ~= nil then ConsiderNeutralItems() end
		return
	end
	if ConsiderNitori01(bot, ability01, enemies) then
		UseAbility(bot, ability01)
		return
	end
	local ultimateTarget = FindNitori04Target(bot, ability04, enemies)
	if ultimateTarget ~= nil then
		UseAbilityOnEntity(bot, ability04, ultimateTarget)
		return
	end
	local lineTarget = ConsiderNitori02(bot, ability02, profile)
	if lineTarget ~= nil then
		UseAbilityOnLocation(bot, ability02, lineTarget)
		return
	end
	if ConsiderNitori03(bot, ability03, enemies, false) then
		UseAbility(bot, ability03)
		return
	end
	if ConsiderNeutralItems ~= nil then ConsiderNeutralItems() end
end

if NITORI_BOT_TEST_EXPORTS then
	NitoriBotTest = {
		GetProfile = GetProfile,
		GetNitori02Damage = GetNitori02Damage,
		ScoreNitori02Line = ScoreNitori02Line,
		GetExpectedFunnelCount = GetExpectedFunnelCount,
		FindNitori04Target = FindNitori04Target,
		TryConsumeEmpoweredAttack = TryConsumeEmpoweredAttack,
	}
end

----------------------------------------------------------------------------------------------------
