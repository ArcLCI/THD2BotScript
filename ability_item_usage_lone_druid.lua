require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')


----------------------------------------------------------------------------------------------------

local lastExTreeLocation = nil
local lastExTreeTime = -100

local function IsAbilityReady(ability)
	if ability == nil then return false end
	if ability.IsNull ~= nil and ability:IsNull() then return false end
	if ability.IsTrained ~= nil and not ability:IsTrained() then return false end
	return ability:IsFullyCastable()
end

local function IsValidEnemyHero(target)
	return target ~= nil
		and target:IsHero()
		and IsValidCastTarget(target, true, false)
		and not IsPossibleIllusion(target)
end

local function IsDisabledTarget(target)
	return target ~= nil and (target:IsStunned() or target:IsRooted())
end

local function IsCombatMode(bot)
	local mode = bot:GetActiveMode()
	return mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_GANK
		or mode == BOT_MODE_ROAM
		or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_DEFEND_ALLY
end

local function GetManaPercent(bot)
	if bot:GetMaxMana() <= 0 then return 0 end
	return bot:GetMana() / bot:GetMaxMana()
end

local function GetPreferredEnemyHero(bot, enemies)
	local target = J.GetProperTarget(bot)
	if IsValidEnemyHero(target) then
		return target
	end

	for _, enemy in pairs(enemies) do
		if IsValidEnemyHero(enemy) then
			return enemy
		end
	end

	return nil
end

local function IsLocationInCastRange(bot, location, castRange)
	return location ~= nil
		and J.GetLocationToLocationDistance(bot:GetLocation(), location) <= castRange
end

local function TryUseHorseItems(bot)
	if bot:IsMuted() or bot:IsUsingAbility() then return false end

	-- 马王需要同时负责开启和关闭，优先处理其切换状态。
	local itemHorseKing = IsItemAvailable("item_horse_king")
	if itemHorseKing ~= nil and itemHorseKing:IsFullyCastable() then
		local desire = ConsiderItemHorseKing(itemHorseKing)
		if desire > BOT_ACTION_DESIRE_NONE then
			bot:Action_UseAbility(itemHorseKing)
			return true
		end
	end

	local itemHorseRed = IsItemAvailable("item_horse_red")
	if itemHorseRed ~= nil and itemHorseRed:IsFullyCastable() then
		local desire = ConsiderItemHorseRed(itemHorseRed)
		if desire > BOT_ACTION_DESIRE_NONE then
			bot:Action_UseAbility(itemHorseRed)
			return true
		end
	end

	return false
end

----------------------------------------------------------------------------------------------------

local function ConsiderAbilityShizuha01(bot, ability)
	if not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local castRange = ability:GetCastRange()
	local radius = ability:GetSpecialValueInt("radius")
	local castPoint = ability:GetCastPoint()
	local enemies = CachedGetNearbyHeroes(bot, castRange + radius, true, BOT_MODE_NONE)

	-- 多人控制优先于对当前单体目标直接施法。
	local heroAoE = CachedFindAoELocation(
		bot, 61001, true, true, bot:GetLocation(), castRange, radius, castPoint, 0
	)
	if heroAoE.count ~= nil and heroAoE.count >= 2 and heroAoE.targetloc ~= nil then
		return BOT_ACTION_DESIRE_VERYHIGH, heroAoE.targetloc
	end

	if bot:GetActiveMode() == BOT_MODE_RETREAT then
		for _, enemy in pairs(enemies) do
			if IsValidEnemyHero(enemy) and bot:WasRecentlyDamagedByHero(enemy, 2.0) then
				local location = enemy:GetExtrapolatedLocation(castPoint)
				if IsLocationInCastRange(bot, location, castRange) then
					return BOT_ACTION_DESIRE_HIGH, location
				end
			end
		end
	end

	if IsCombatMode(bot) then
		local target = GetPreferredEnemyHero(bot, enemies)
		if target ~= nil then
			local location = target:GetExtrapolatedLocation(castPoint)
			if IsLocationInCastRange(bot, location, castRange) then
				return BOT_ACTION_DESIRE_HIGH, location
			end
		end
	end

	if (J.IsPushing(bot) or J.IsDefending(bot)) and GetManaPercent(bot) >= 0.45 then
		local creepAoE = CachedFindAoELocation(
			bot, 61002, true, false, bot:GetLocation(), castRange, radius, castPoint, 0
		)
		if creepAoE.count ~= nil and creepAoE.count >= 4 and creepAoE.targetloc ~= nil then
			return BOT_ACTION_DESIRE_MODERATE, creepAoE.targetloc
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

local function ConsiderAbilityShizuhaEx(bot, abilityEx, ability05)
	if not IsAbilityReady(abilityEx)
		or not bot:HasModifier("modifier_item_aghanims_shard")
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local castRange = abilityEx:GetCastRange()
	local castPoint = abilityEx:GetCastPoint()
	local treeRadius = abilityEx:GetSpecialValueInt("trees_circle_radius")
	local enemies = CachedGetNearbyHeroes(bot, castRange + treeRadius, true, BOT_MODE_NONE)
	local target = GetPreferredEnemyHero(bot, enemies)

	-- 同时拥有神杖技能时，优先造树来衔接 05。
	if IsAbilityReady(ability05) then
		local heroAoE = CachedFindAoELocation(
			bot, 61003, true, true, bot:GetLocation(), castRange, treeRadius, castPoint, 0
		)
		if heroAoE.count ~= nil and heroAoE.count >= 2 and heroAoE.targetloc ~= nil then
			return BOT_ACTION_DESIRE_VERYHIGH, heroAoE.targetloc
		end

		if target ~= nil and IsDisabledTarget(target) then
			local location = target:GetExtrapolatedLocation(castPoint)
			if IsLocationInCastRange(bot, location, castRange) then
				return BOT_ACTION_DESIRE_VERYHIGH, location
			end
		end
	end

	if IsCombatMode(bot) and target ~= nil then
		local location = target:GetExtrapolatedLocation(castPoint)
		if IsLocationInCastRange(bot, location, castRange) then
			return BOT_ACTION_DESIRE_HIGH, location
		end
	end

	if J.IsSeriouslyRetreating(bot) then
		local nearbyEnemies = CachedGetNearbyHeroes(bot, 900, true, BOT_MODE_NONE)
		for _, enemy in pairs(nearbyEnemies) do
			if IsValidEnemyHero(enemy) and bot:WasRecentlyDamagedByHero(enemy, 2.0) then
				local location = enemy:GetExtrapolatedLocation(castPoint)
				if IsLocationInCastRange(bot, location, castRange) then
					return BOT_ACTION_DESIRE_HIGH, location
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

local function CountTreesNearLocation(treeLocations, location, radius)
	local count = 0
	for _, treeLocation in pairs(treeLocations) do
		if J.GetLocationToLocationDistance(treeLocation, location) <= radius then
			count = count + 1
		end
	end
	return count
end

local function CountHeroesNearLocation(enemies, location, radius)
	local count = 0
	for _, enemy in pairs(enemies) do
		if IsValidEnemyHero(enemy)
			and J.GetLocationToLocationDistance(enemy:GetLocation(), location) <= radius
		then
			count = count + 1
		end
	end
	return count
end

local function ConsiderAbilityShizuha05(bot, ability, preferredTarget)
	if not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local castRange = ability:GetCastRange()
	local radiusBase = ability:GetSpecialValueInt("radius_base")
	local radiusMax = ability:GetSpecialValueInt("radius_max")
	local treeIds = bot:GetNearbyTrees(castRange + radiusBase)
	if treeIds == nil or #treeIds == 0 then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local treeLocations = {}
	for _, treeId in pairs(treeIds) do
		local location = GetTreeLocation(treeId)
		if location ~= nil then
			table.insert(treeLocations, location)
		end
	end
	if #treeLocations == 0 then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local enemies = CachedGetNearbyHeroes(bot, castRange + radiusMax, true, BOT_MODE_NONE)
	local target = preferredTarget
	if not IsValidEnemyHero(target) then
		target = GetPreferredEnemyHero(bot, enemies)
	end
	if target == nil then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local targetLocation = target:GetExtrapolatedLocation(ability:GetCastPoint())
	local candidates = {}
	for _, location in pairs(treeLocations) do
		if IsLocationInCastRange(bot, location, castRange) then
			table.insert(candidates, {
				location = location,
				targetDistance = J.GetLocationToLocationDistance(location, targetLocation),
			})
		end
	end

	table.sort(candidates, function(a, b)
		return a.targetDistance < b.targetDistance
	end)

	local bestLocation = nil
	local bestHeroCount = -1
	local bestTreeCount = -1
	local bestTargetDistance = 100000
	local candidateCount = math.min(#candidates, 40)

	for index = 1, candidateCount do
		local candidate = candidates[index]
		local heroCount = CountHeroesNearLocation(enemies, candidate.location, radiusMax)
		local treeCount = CountTreesNearLocation(treeLocations, candidate.location, radiusBase)

		if heroCount > bestHeroCount
			or (heroCount == bestHeroCount and treeCount > bestTreeCount)
			or (heroCount == bestHeroCount and treeCount == bestTreeCount
				and candidate.targetDistance < bestTargetDistance)
		then
			bestLocation = candidate.location
			bestHeroCount = heroCount
			bestTreeCount = treeCount
			bestTargetDistance = candidate.targetDistance
		end
	end

	if bestLocation == nil or bestTreeCount < 1 then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	if bestHeroCount >= 2 then
		return BOT_ACTION_DESIRE_VERYHIGH, bestLocation
	end

	if IsDisabledTarget(target)
	and J.GetLocationToLocationDistance(target:GetLocation(), bestLocation) <= radiusMax
	then
		return BOT_ACTION_DESIRE_HIGH, bestLocation
	end

	local isRecentExSetup = lastExTreeLocation ~= nil
		and DotaTime() - lastExTreeTime <= 1.0
		and J.GetLocationToLocationDistance(lastExTreeLocation, bestLocation) <= radiusBase
		and J.GetLocationToLocationDistance(target:GetLocation(), bestLocation) <= radiusMax
	if isRecentExSetup then
		return BOT_ACTION_DESIRE_HIGH, bestLocation
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

local function ConsiderAbilityShizuha04(bot, ability)
	if not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local castRange = ability:GetCastRange()
	local radius = ability:GetSpecialValueInt("radius")
	local castPoint = ability:GetCastPoint()
	local enemies = CachedGetNearbyHeroes(bot, castRange + radius, true, BOT_MODE_NONE)

	local heroAoE = CachedFindAoELocation(
		bot, 61004, true, true, bot:GetLocation(), castRange, radius, castPoint, 0
	)
	if heroAoE.count ~= nil and heroAoE.count >= 2 and heroAoE.targetloc ~= nil then
		return BOT_ACTION_DESIRE_VERYHIGH, heroAoE.targetloc
	end

	if IsCombatMode(bot) and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH then
		local target = GetPreferredEnemyHero(bot, enemies)
		if target ~= nil and IsDisabledTarget(target) then
			local location = target:GetExtrapolatedLocation(castPoint)
			if IsLocationInCastRange(bot, location, castRange) then
				return BOT_ACTION_DESIRE_HIGH, location
			end
		end
	end

	if J.IsDefending(bot) and #enemies == 0 then
		local creepAoE = CachedFindAoELocation(
			bot, 61005, true, false, bot:GetLocation(), castRange, radius, castPoint, 0
		)
		if creepAoE.count ~= nil and creepAoE.count >= 5 and creepAoE.targetloc ~= nil then
			return BOT_ACTION_DESIRE_MODERATE, creepAoE.targetloc
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

local function ConsiderAbilityShizuha02(bot, ability)
	if not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE
	end

	if bot:HasModifier("modifier_fountain_aura_buff")
		or bot:HasModifier("modifier_fountain_invulnerability")
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local enemies = CachedGetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
	if #enemies > 0
		or bot:WasRecentlyDamagedByAnyHero(4.0)
		or bot:WasRecentlyDamagedByTower(3.0)
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local mode = bot:GetActiveMode()
	if mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_GANK
		or (mode == BOT_MODE_RETREAT and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH)
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local missingHealth = bot:GetMaxHealth() - bot:GetHealth()
	local missingMana = bot:GetMaxMana() - bot:GetMana()
	local healAmount = ability:GetSpecialValueInt("heal_amount")
	local manaAmount = ability:GetSpecialValueInt("mana_regen_amount")
	local healthPercent = bot:GetHealth() / bot:GetMaxHealth()
	local manaPercent = GetManaPercent(bot)

	local shouldHeal = healthPercent < 0.80 and missingHealth >= healAmount * 0.50
	local shouldRestoreMana = manaPercent < 0.70 and missingMana >= manaAmount * 0.50
	if shouldHeal or shouldRestoreMana then
		return BOT_ACTION_DESIRE_HIGH
	end

	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

local function ConsiderAbilityShizuha03(bot, ability)
	if ability == nil
		or (ability.IsNull ~= nil and ability:IsNull())
		or (ability.IsTrained ~= nil and not ability:IsTrained())
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local isEnabled = ability:GetAutoCastState()
	local manaPercent = GetManaPercent(bot)
	local manaCost = ability:GetManaCost()
	local mode = bot:GetActiveMode()
	local target = J.GetProperTarget(bot)

	if isEnabled then
		local isFarming = mode == BOT_MODE_LANING or mode == BOT_MODE_FARM
		local isAttackingBasicUnit = target ~= nil and not target:IsHero()
		if manaPercent < 0.15 or isFarming or isAttackingBasicUnit then
			return BOT_ACTION_DESIRE_HIGH
		end
		return BOT_ACTION_DESIRE_NONE
	end

	if IsCombatMode(bot)
		and IsValidEnemyHero(target)
		and manaPercent >= 0.20
		and bot:GetMana() >= manaCost * 3
	then
		return BOT_ACTION_DESIRE_HIGH
	end

	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()
	local bot = GetBot()
	if bot == nil then return end

	local ability01 = bot:GetAbilityByName("ability_thdots_shizuha01")
	local ability02 = bot:GetAbilityByName("ability_thdots_shizuha02")
	local ability03 = bot:GetAbilityByName("ability_thdots_shizuha03")
	local abilityEx = bot:GetAbilityByName("ability_thdots_shizuhaEXNew")
	local ability05 = bot:GetAbilityByName("ability_thdots_shizuha05")
	local ability04 = bot:GetAbilityByName("ability_thdots_shizuha04")

	-- 指定技能的前摇和引导期间，整次决策不再发送任何 Bot action。
	if J.IsAbilityInChannelPhase(ability02) then return end
	if not IsBotAwake(bot) or J.CanNotUseAction(bot) then return end

	local desire, location = ConsiderAbilityShizuha01(bot, ability01)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbilityOnLocation(ability01, location)
		return
	end

	desire, location = ConsiderAbilityShizuhaEx(bot, abilityEx, ability05)
	if desire > BOT_ACTION_DESIRE_NONE then
		-- 记录 EX 造树点，供下一次 Think 优先衔接 05。
		lastExTreeLocation = location
		lastExTreeTime = DotaTime()
		bot:Action_UseAbilityOnLocation(abilityEx, location)
		return
	end

	local nearbyEnemies = CachedGetNearbyHeroes(bot, 2500, true, BOT_MODE_NONE)
	local preferredTarget = GetPreferredEnemyHero(bot, nearbyEnemies)
	desire, location = ConsiderAbilityShizuha05(bot, ability05, preferredTarget)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbilityOnLocation(ability05, location)
		return
	end

	desire, location = ConsiderAbilityShizuha04(bot, ability04)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbilityOnLocation(ability04, location)
		return
	end

	desire = ConsiderAbilityShizuha02(bot, ability02)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(ability02)
		return
	end

	desire = ConsiderAbilityShizuha03(bot, ability03)
	if desire > BOT_ACTION_DESIRE_NONE then
		-- 15%/20% 双阈值避免低蓝边界反复切换法球。
		ability03:ToggleAutoCast()
		return
	end

	if TryUseHorseItems(bot) then return end

	-- 中立物品置于末尾，确保其 action 不会被本次技能决策覆盖。
	ConsiderNeutralItems()
end
