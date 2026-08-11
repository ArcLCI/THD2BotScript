require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")

local CHEN01 = "ability_thdots_chen01"
local CHEN02 = "ability_thdots_chen02"
local CHEN03 = "ability_thdots_chen03"
local CHEN04 = "ability_thdots_chen04"
local CHEN_WANBAO = "ability_thdots_chen_wanbaochui"

local ROLLING_MODIFIER = "modifier_ability_thdots_chen01"
local ULTIMATE_MODIFIER = "modifier_ability_thdots_chen04"
local WANBAO_MODIFIER = "modifier_item_wanbaochui"
local HORSE_KING_MODIFIER = "modifier_item_horse_king_open"
local DRAGON_STAR_MODIFIER = "modifier_item_dragon_star_buff"
local TRINITY_MODIFIER = "modifier_item_trinity_active_shield"

local COMBO_WINDOW = 4.5
local ACTION_GUARD_TIME = 0.05
local HERO_SCAN_RANGE = 1200
local CHEN03_COMBAT_RADIUS = 500
local FARM_RESERVE_RANGE = 1000
local ROLL_PREDICTION_TIME = 0.35

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

local function FindCombatTarget(bot, enemies, ability01)
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
	return bestTarget
end

local function ClearCombo(bot)
	bot.thdOrangeCombo = nil
end

local function StartCombo(bot, target, ability02)
	local nearRange = ability02 ~= nil and math.max(SafeCall(ability02, "GetCastRange", 400), 400) or 400
	bot.thdOrangeCombo = {
		target = target,
		expiresAt = DotaTime() + COMBO_WINDOW,
		remote = GetUnitToUnitDistance(bot, target) > nearRange + 50,
		ultimateIssued = false,
		rollIssued = false,
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

local function GetPredictedRollLocation(bot, target, ability)
	local targetLocation = SafeCall(target, "GetExtrapolatedLocation", target:GetLocation(), ROLL_PREDICTION_TIME)
	return ProjectLocation(bot:GetLocation(), targetLocation, GetRollRange(ability))
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
	local underPressure = #enemies > 0
		and (seriousRetreat or SafeCall(bot, "WasRecentlyDamagedByAnyHero", false, 2.5))
		and (seriousRetreat or GetHP(bot) < 0.65)
	if not underPressure then return false end

	local dragonStar = GetReadyItem("item_dragon_star")
	if dragonStar ~= nil and not bot:HasModifier(DRAGON_STAR_MODIFIER) then
		return UseAbility(bot, dragonStar)
	end
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

local function ContinueCombo(bot, state, ability01, ability02, ability03, ability04)
	local target = state.target
	local silenced = SafeCall(bot, "IsSilenced", false)
	if not bot:HasModifier(ULTIMATE_MODIFIER)
	and not state.ultimateIssued
	and not silenced
	and IsCastable(ability04)
	then
		state.ultimateIssued = true
		return UseAbility(bot, ability04)
	end

	if state.remote and not state.rollIssued
	and not silenced
	and not SafeCall(bot, "IsRooted", false)
	and IsCastable(ability01)
	then
		state.rollIssued = true
		return UseAbilityOnLocation(bot, ability01, GetPredictedRollLocation(bot, target, ability01))
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
		state.rollIssued = false
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
	-- 滚动由游戏侧 modifier 驱动位移；生命周期内任何技能、装备或中立物品命令都会破坏动作管线。
	if bot:HasModifier(ROLLING_MODIFIER) then return end
	if WasActionJustIssued(bot) or J.CanNotUseAction(bot) then return end

	local ability01 = GetAbility(bot, CHEN01)
	local ability02 = GetAbility(bot, CHEN02)
	local ability03 = GetAbility(bot, CHEN03)
	local ability04 = GetAbility(bot, CHEN04)
	local wanbao = GetAbility(bot, CHEN_WANBAO)
	local enemies = GetVisibleEnemyHeroes(bot, HERO_SCAN_RANGE)

	if TrySeriousRetreat(bot, enemies, ability01, ability02, ability03, wanbao) then return end

	local state = GetValidCombo(bot)
	if state ~= nil and ContinueCombo(bot, state, ability01, ability02, ability03, ability04) then return end

	if state == nil then
		local target = FindCombatTarget(bot, enemies, ability01)
		if target ~= nil then
			state = StartCombo(bot, target, ability02)
			if ContinueCombo(bot, state, ability01, ability02, ability03, ability04) then return end
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
	}
end

----------------------------------------------------------------------------------------------------
