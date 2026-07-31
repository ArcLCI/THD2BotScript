require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")

local WOLF_UNIT_NAME = "ability_momiji_Spawn_unit"
local MOMIJI03_MIN_ACQUIRE_RANGE = 700
local MOMIJI03_EXTRA_ACQUIRE_RANGE = 550

local function GetBuildProfile(bot)
	local profile = BotProfile.GetProfile(bot)
	if profile ~= nil then return profile end
	-- 新物理加点与前排加点会出现相同技能等级组合，不能再靠技能等级可靠反推定位。
	return BotProfile.FRONTLINE
end

local function IsAbilityReady(ability)
	if ability == nil then return false end
	if ability.IsNull ~= nil and ability:IsNull() then return false end
	if ability.IsTrained ~= nil and not ability:IsTrained() then return false end
	return ability:IsFullyCastable()
end

local function IsValidVisibleUnit(unit)
	return unit ~= nil
		and not unit:IsNull()
		and unit:IsAlive()
		and unit:CanBeSeen()
end

local function IsValidEnemyHero(unit)
	return IsValidVisibleUnit(unit)
		and unit:IsHero()
		and IsValidCastTarget(unit, true, true)
end

local function IsInCastRange(bot, target, castRange)
	return target ~= nil and GetUnitToUnitDistance(bot, target) <= castRange
end

local function GetVisibleEnemyHeroes()
	local enemies = {}
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if IsValidEnemyHero(enemy) then
			table.insert(enemies, enemy)
		end
	end
	return enemies
end

local function CountNearbyEnemies(bot, enemies, radius)
	local count = 0
	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= radius then
			count = count + 1
		end
	end
	return count
end

local function GetProperEnemyHero(bot)
	local target = J.GetProperTarget(bot)
	if IsValidEnemyHero(target) then
		return target
	end
	return nil
end

local function GetBestHeroCluster(enemies, radius, castPoint)
	local bestLocation = nil
	local bestCount = 0
	for _, candidate in pairs(enemies) do
		local location = candidate:GetExtrapolatedLocation(castPoint)
		local count = 0
		for _, enemy in pairs(enemies) do
			if GetUnitToLocationDistance(enemy, location) <= radius then
				count = count + 1
			end
		end
		if count > bestCount then
			bestCount = count
			bestLocation = location
		end
	end
	return bestCount, bestLocation
end

local function GetBestCreepCluster(radius)
	local creeps = {}
	for _, creep in pairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
		if IsValidVisibleUnit(creep) and creep:IsCreep() then
			table.insert(creeps, creep)
		end
	end

	local bestLocation = nil
	local bestCount = 0
	for _, candidate in pairs(creeps) do
		local location = candidate:GetLocation()
		local count = 0
		for _, creep in pairs(creeps) do
			if GetUnitToLocationDistance(creep, location) <= radius then
				count = count + 1
			end
		end
		if count > bestCount then
			bestCount = count
			bestLocation = location
		end
	end
	return bestCount, bestLocation
end

local function GetAliveWolves()
	local wolves = {}
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES)) do
		if IsValidVisibleUnit(unit) and unit:GetUnitName() == WOLF_UNIT_NAME then
			table.insert(wolves, unit)
		end
	end
	return wolves
end

local function GetExpectedWolfCount(bot)
	local talent = bot:GetAbilityByName("special_bonus_unique_momiji_1")
	return 2 + ((talent ~= nil and talent:GetLevel() > 0) and 1 or 0)
end

local function GetAverageHealthPercent(units)
	if #units == 0 then return 0 end
	local total = 0
	for _, unit in pairs(units) do
		total = total + J.GetHP(unit)
	end
	return total / #units
end

local function GetMomiji03AcquireRange(ability)
	return math.max(MOMIJI03_MIN_ACQUIRE_RANGE, ability:GetCastRange() + MOMIJI03_EXTRA_ACQUIRE_RANGE)
end

local function IsTeleporting(enemy)
	return enemy:HasModifier("modifier_teleporting")
		or enemy:HasModifier("modifier_teleporting_root_logic")
end

local function ConsiderMomiji03Emergency(bot, ability, enemies)
	if bot:IsSilenced() or not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local castRange = ability:GetCastRange()
	local acquireRange = GetMomiji03AcquireRange(ability)

	-- 回城和传送不一定稳定表现为 IsChanneling，显式检查两个传送 modifier。
	for _, enemy in pairs(enemies) do
		if IsInCastRange(bot, enemy, castRange + 50) and IsTeleporting(enemy) then
			return BOT_ACTION_DESIRE_ABSOLUTE, enemy
		end
	end

	for _, enemy in pairs(enemies) do
		if IsInCastRange(bot, enemy, castRange + 50) and enemy:IsChanneling() then
			return BOT_ACTION_DESIRE_ABSOLUTE, enemy
		end
	end

	local damage = ability:GetAbilityDamage()
	for _, enemy in pairs(enemies) do
		if IsInCastRange(bot, enemy, acquireRange)
		and J.CanKillTarget(enemy, damage, DAMAGE_TYPE_MAGICAL)
		then
			return BOT_ACTION_DESIRE_VERYHIGH, enemy
		end
	end

	-- 强控制无需等到技能本身能够斩杀；进攻时主动压制七成血以下目标并衔接普攻。
	if J.IsGoingOnSomeone(bot) then
		local pressureTarget = nil
		local lowestHP = 1.1
		for _, enemy in pairs(enemies) do
			local hp = J.GetHP(enemy)
			if hp <= 0.7
			and hp < lowestHP
			and IsInCastRange(bot, enemy, acquireRange)
			then
				pressureTarget = enemy
				lowestHP = hp
			end
		end
		if pressureTarget ~= nil then
			return BOT_ACTION_DESIRE_VERYHIGH, pressureTarget
		end
	end

	if J.IsSeriouslyRetreating(bot, 'ability_thdots_momiji03') then
		local closest = nil
		local closestDistance = math.huge
		for _, enemy in pairs(enemies) do
			local distance = GetUnitToUnitDistance(bot, enemy)
			if distance <= castRange + 250
			and distance < closestDistance
			and bot:WasRecentlyDamagedByHero(enemy, 2.0)
			then
				closest = enemy
				closestDistance = distance
			end
		end
		if closest ~= nil then
			return BOT_ACTION_DESIRE_VERYHIGH, closest
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

local function ConsiderMomiji03Offensive(bot, ability, enemies)
	if bot:IsSilenced() or not IsAbilityReady(ability) or not J.IsGoingOnSomeone(bot) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local acquireRange = GetMomiji03AcquireRange(ability)
	local target = GetProperEnemyHero(bot)
	if target ~= nil and IsInCastRange(bot, target, acquireRange) then
		return BOT_ACTION_DESIRE_VERYHIGH, target
	end

	local closest = nil
	local closestDistance = math.huge
	for _, enemy in pairs(enemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		if distance <= acquireRange and distance < closestDistance then
			closest = enemy
			closestDistance = distance
		end
	end
	if closest ~= nil then
		return BOT_ACTION_DESIRE_HIGH, closest
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

local function ConsiderMomiji04(bot, ability, enemies)
	if bot:IsSilenced()
	or not bot:HasModifier("modifier_item_wanbaochui")
	or not IsAbilityReady(ability)
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nearbyEnemies = 0
	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= 1400 then
			nearbyEnemies = nearbyEnemies + 1
		end
	end
	if nearbyEnemies >= 2
	and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1400))
	then
		return BOT_ACTION_DESIRE_VERYHIGH
	end

	if J.IsSeriouslyRetreating(bot, 'ability_thdots_momiji04') and nearbyEnemies >= 1 then
		return BOT_ACTION_DESIRE_VERYHIGH
	end

	local target = GetProperEnemyHero(bot)
	if J.IsGoingOnSomeone(bot) and target ~= nil then
		local distance = GetUnitToUnitDistance(bot, target)
		if distance > bot:GetAttackRange() + 100 and distance <= 1600 then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	for i = 1, #GetTeamPlayers(GetTeam()) do
		local ally = GetTeamMember(i)
		if ally ~= nil and ally:IsAlive() then
			local enemiesNearAlly = 0
			for _, enemy in pairs(enemies) do
				if GetUnitToUnitDistance(ally, enemy) <= 1200 then
					enemiesNearAlly = enemiesNearAlly + 1
				end
			end
			if enemiesNearAlly >= 2 and J.IsInTeamFight(ally, 1200) then
				return BOT_ACTION_DESIRE_VERYHIGH
			end
			if enemiesNearAlly >= 1
			and J.GetHP(ally) < 0.35
			and ally:WasRecentlyDamagedByAnyHero(2.0)
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

local function ConsiderMomiji02(bot, ability, enemies)
	if bot:IsSilenced() or not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	-- 二技能的 KV 施法距离为 0，但游戏侧按全图点目标处理。
	local radius = ability:GetSpecialValueInt("radius")
	local castPoint = ability:GetCastPoint()
	local heroCount, heroLocation = GetBestHeroCluster(enemies, radius, castPoint)
	if heroCount >= 2 then
		return BOT_ACTION_DESIRE_VERYHIGH, heroLocation
	end

	local target = J.GetProperTarget(bot)
	if J.IsDoingRoshan(bot) and J.IsRoshan(target) then
		return BOT_ACTION_DESIRE_HIGH, target:GetLocation()
	end

	local heroTarget = GetProperEnemyHero(bot)
	if J.IsGoingOnSomeone(bot)
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and heroTarget ~= nil
	then
		return BOT_ACTION_DESIRE_HIGH, heroTarget:GetExtrapolatedLocation(castPoint)
	end

	if J.IsDefending(bot) or J.IsPushing(bot) or bot:GetActiveMode() == BOT_MODE_LANING then
		if J.GetMP(bot) >= 0.4 then
			local creepCount, creepLocation = GetBestCreepCluster(radius)
			if creepCount >= 4 then
				return BOT_ACTION_DESIRE_MODERATE, creepLocation
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

local function ConsiderMomiji01(bot, ability)
	if bot:IsSilenced() or not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE
	end

	local wolves = GetAliveWolves()
	local expectedCount = GetExpectedWolfCount(bot)
	if #wolves >= expectedCount then
		return BOT_ACTION_DESIRE_NONE
	end

	local mode = bot:GetActiveMode()
	local isCombat = J.IsGoingOnSomeone(bot)
	local isObjective = J.IsDoingRoshan(bot) or J.IsPushing(bot)
	local isFarm = mode == BOT_MODE_FARM
	local isDefend = J.IsDefending(bot)
	local laneCreeps = bot:GetNearbyLaneCreeps(800, true)
	local hasLaningWave = mode == BOT_MODE_LANING
		and J.GetMP(bot) >= 0.5
		and laneCreeps ~= nil
		and #laneCreeps >= 3

	if #wolves > 0 then
		local packIsWeak = GetAverageHealthPercent(wolves) < 0.45
		if not packIsWeak and not isCombat and not isObjective then
			return BOT_ACTION_DESIRE_NONE
		end
	end

	if isCombat or isObjective or isFarm or isDefend or hasLaningWave then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end

local function TryUseTsundere(bot, enemies)
	local item = IsItemAvailable("item_tsundere")
	if item == nil or not item:IsFullyCastable() then return false end

	local underPressure = bot:WasRecentlyDamagedByAnyHero(1.5)
	local nearbyEnemies = CountNearbyEnemies(bot, enemies, 850)
	if underPressure
	and nearbyEnemies > 0
	and (J.GetHP(bot) < 0.35 or (J.IsSeriouslyRetreating(bot) and J.GetHP(bot) < 0.55))
	then
		bot:Action_UseAbility(item)
		return true
	end
	return false
end

local function TryUseTrinity(bot, enemies)
	local item = IsItemAvailable("item_trinity") or IsItemAvailable("item_esdw")
	if item == nil or not item:IsFullyCastable() then return false end
	local shouldPreShield = CountNearbyEnemies(bot, enemies, 1200) >= 2
		and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	if shouldPreShield or ConsiderItemShield(item) > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(item)
		return true
	end
	return false
end

local function TryUseFlowerUmbrella(bot, enemies, profile)
	if profile ~= BotProfile.FRONTLINE then return false end
	local item = IsItemAvailable("item_flower_umbrella")
	if item == nil or not item:IsFullyCastable() then return false end

	local nearbyEnemies = CountNearbyEnemies(bot, enemies, 1200)
	local isCommittedFight = nearbyEnemies >= 2 and J.IsInTeamFight(bot, 1200)
	local isCommittedAttack = nearbyEnemies >= 1
		and J.IsGoingOnSomeone(bot)
		and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	local isUnderPressure = nearbyEnemies >= 1
		and bot:WasRecentlyDamagedByAnyHero(2.0)
		and (J.GetHP(bot) < 0.7 or J.IsSeriouslyRetreating(bot))

	-- 花伞护盾按每名友军的力量逐次格挡物理伤害，开团前或承压时提前覆盖队伍。
	if isCommittedFight or isCommittedAttack or isUnderPressure then
		bot:Action_UseAbility(item)
		return true
	end
	return false
end

local function TryUseDragonStar(bot, enemies, profile)
	local item = IsItemAvailable("item_dragon_star")
	if item == nil or not item:IsFullyCastable() then return false end

	if J.IsSeriouslyRetreating(bot)
	and bot:WasRecentlyDamagedByAnyHero(2.0)
	and CountNearbyEnemies(bot, enemies, 1000) > 0
	then
		bot:Action_UseAbility(item)
		return true
	end

	local isEngaging = J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200)
	local engageRange = profile == BotProfile.FRONTLINE and 950 or 800
	if isEngaging
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and CountNearbyEnemies(bot, enemies, engageRange) > 0
	then
		bot:Action_UseAbility(item)
		return true
	end
	return false
end

local function IsAlreadyHardDisabled(enemy)
	return enemy:IsStunned() or enemy:IsHexed()
end

local function TryUseYukkuri(bot, enemies, profile, interruptOnly)
	if profile ~= BotProfile.FRONTLINE then return false end
	local item = IsItemAvailable("item_yukkuri_stick")
	if item == nil or not item:IsFullyCastable() then return false end
	local castRange = item:GetCastRange()

	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= castRange
		and CanCastStunOnTarget(enemy)
		and not IsAlreadyHardDisabled(enemy)
		and (enemy:IsChanneling() or IsTeleporting(enemy))
		then
			bot:Action_UseAbilityOnEntity(item, enemy)
			return true
		end
	end
	if interruptOnly then return false end

	if J.IsSeriouslyRetreating(bot) then
		local closest = nil
		local closestDistance = math.huge
		for _, enemy in pairs(enemies) do
			local distance = GetUnitToUnitDistance(bot, enemy)
			if distance <= castRange
			and distance < closestDistance
			and not IsAlreadyHardDisabled(enemy)
			and bot:WasRecentlyDamagedByHero(enemy, 2.0)
			then
				closest = enemy
				closestDistance = distance
			end
		end
		if closest ~= nil then
			bot:Action_UseAbilityOnEntity(item, closest)
			return true
		end
	end

	local target = GetProperEnemyHero(bot)
	if target ~= nil
	and J.IsGoingOnSomeone(bot)
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and GetUnitToUnitDistance(bot, target) <= castRange
	and CanCastStunOnTarget(target)
	and not IsAlreadyHardDisabled(target)
	then
		bot:Action_UseAbilityOnEntity(item, target)
		return true
	end
	return false
end

local function TryUseRetreatHorseKing(bot)
	if not J.IsSeriouslyRetreating(bot) then return false end
	local item = IsItemAvailable("item_horse_king")
	if item ~= nil and item:IsFullyCastable() and ConsiderItemHorseKing(item) > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(item)
		return true
	end
	return false
end

local function TryUseHorseKing(bot)
	local horseKing = IsItemAvailable("item_horse_king")
	if horseKing ~= nil
	and horseKing:IsFullyCastable()
	and ConsiderItemHorseKing(horseKing) > BOT_ACTION_DESIRE_NONE
	then
		bot:Action_UseAbility(horseKing)
		return true
	end
	return false
end


local function TryUseHorseRed(bot)
	local horseRed = IsItemAvailable("item_horse_red")
	if horseRed ~= nil
	and horseRed:IsFullyCastable()
	and ConsiderItemHorseRed(horseRed) > BOT_ACTION_DESIRE_NONE
	then
		bot:Action_UseAbility(horseRed)
		return true
	end
	return false
end

function AbilityUsageThink()
	if not IsBotAwake() then return end

	local bot = GetBot()
	if J.CanNotUseAction(bot) then return end

	local ability01 = bot:GetAbilityByName("ability_thdots_momiji01")
	local ability02 = bot:GetAbilityByName("ability_thdots_momiji02")
	local ability03 = bot:GetAbilityByName("ability_thdots_momiji03")
	local ability04 = bot:GetAbilityByName("ability_thdots_momiji04")
	local enemies = GetVisibleEnemyHeroes()
	local profile = GetBuildProfile(bot)

	local desire, target = ConsiderMomiji03Emergency(bot, ability03, enemies)
	if desire > BOT_ACTION_DESIRE_NONE and target ~= nil then
		bot:Action_UseAbilityOnEntity(ability03, target)
		return
	end
	-- 三技能够不到时，前排路线再用800距离油库里处理持续施法和传送。
	if TryUseYukkuri(bot, enemies, profile, true) then return end

	if TryUseTsundere(bot, enemies) then return end
	if TryUseTrinity(bot, enemies) then return end
	if TryUseRetreatHorseKing(bot) then return end
	if TryUseDragonStar(bot, enemies, profile) then return end
	if TryUseFlowerUmbrella(bot, enemies, profile) then return end
	-- 红马仅在共享 helper 判定脱战恢复安全时抢在进攻技能前使用。
	if TryUseHorseRed(bot) then return end
	if TryUseYukkuri(bot, enemies, profile, false) then return end

	desire = ConsiderMomiji04(bot, ability04, enemies)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(ability04)
		return
	end

	local location
	desire, location = ConsiderMomiji02(bot, ability02, enemies)
	if desire > BOT_ACTION_DESIRE_NONE and location ~= nil then
		bot:Action_UseAbilityOnLocation(ability02, location)
		return
	end

	desire = ConsiderMomiji01(bot, ability01)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(ability01)
		return
	end

	desire, target = ConsiderMomiji03Offensive(bot, ability03, enemies)
	if desire > BOT_ACTION_DESIRE_NONE and target ~= nil then
		bot:Action_UseAbilityOnEntity(ability03, target)
		return
	end

	if TryUseHorseKing(bot) then return end

	-- 中立物品放在末尾，确保本次 Think 不会再有 action 覆盖它。
	ConsiderNeutralItems()
end

----------------------------------------------------------------------------------------------------
