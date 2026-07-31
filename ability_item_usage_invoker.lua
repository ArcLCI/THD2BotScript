require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")

local bot = GetBot()
local COMBO_TIMEOUT = 12.0
local LANE_COMBO_KILL_HP = 0.55
local WFR_TARGET_RANGE_RATIO = 0.85

local ELEMENTS = {
	Q = "ability_thdots_patchouli_fire",
	W = "ability_thdots_patchouli_water",
	E = "ability_thdots_patchouli_wood",
	D = "ability_thdots_patchouli_metal",
	F = "ability_thdots_patchouli_earth",
}

-- 合成技能表同时描述元素顺序和施法类型，状态机只依赖这一个映射。
local SPELLS = {
	QQR = {name = "ability_thdots_patchouli_fire_fire", elements = {"Q", "Q"}, cast = "none"},
	QWR = {name = "ability_thdots_patchouli_fire_water", elements = {"Q", "W"}, cast = "enemy"},
	QER = {name = "ability_thdots_patchouli_fire_wood", elements = {"Q", "E"}, cast = "point"},
	QDR = {name = "ability_thdots_patchouli_fire_metal", elements = {"Q", "D"}, cast = "enemy"},
	QFR = {name = "ability_thdots_patchouli_fire_earth", elements = {"Q", "F"}, cast = "point"},
	WWR = {name = "ability_thdots_patchouli_water_water", elements = {"W", "W"}, cast = "point"},
	WER = {name = "ability_thdots_patchouli_water_wood", elements = {"W", "E"}, cast = "self"},
	WDR = {name = "ability_thdots_patchouli_water_metal", elements = {"W", "D"}, cast = "point"},
	WFR = {name = "ability_thdots_patchouli_water_earth", elements = {"W", "F"}, cast = "point"},
	EER = {name = "ability_thdots_patchouli_wood_wood", elements = {"E", "E"}, cast = "self"},
	EDR = {name = "ability_thdots_patchouli_wood_metal", elements = {"E", "D"}, cast = "point"},
	EFR = {name = "ability_thdots_patchouli_wood_earth", elements = {"E", "F"}, cast = "enemy"},
	DDR = {name = "ability_thdots_patchouli_metal_metal", elements = {"D", "D"}, cast = "enemy"},
	DFR = {name = "ability_thdots_patchouli_metal_earth", elements = {"D", "F"}, cast = "point"},
	FFR = {name = "ability_thdots_patchouli_earth_earth", elements = {"F", "F"}, cast = "point"},
}

-- 每五个合成技能是一段贤者之石窗口；CONTROL和TSUNDERE是装备步骤，不计层数。
local COMBOS = {
	lane_recover = {"EER", "EFR", "FFR", "WER", "WFR"},
	lane_pressure = {"EER", "WWR", "EFR", "FFR", "WFR"},
	double_default = {"EER", "WWR", "EFR", "FFR", "QFR", "WDR", "DFR", "WFR", "EDR", "DDR"},
	double_recover = {"EER", "WER", "EFR", "FFR", "QFR", "WWR", "WDR", "DFR", "EDR", "WFR"},
	double_ally = {"WWR", "EFR", "FFR", "WDR", "EDR", "DFR", "WFR", "QFR", "QWR", "DDR"},
	double_chase = {"EER", "WWR", "EFR", "WDR", "DFR", "EDR", "WFR", "FFR", "WER", "DDR"},
	double_item = {"EER", "WER", "CONTROL", "FFR", "WDR", "DFR", "EDR", "TSUNDERE", "WFR", "QFR", "WWR", "DDR"},
	triple = {"EER", "WER", "CONTROL", "FFR", "WDR", "DFR", "EDR", "EFR", "WWR", "QFR", "QER", "QWR", "QDR", "QQR", "DDR", "WFR"},
}

local comboState = nil
local elementTracker = {
	ready = false,
	pending = nil,
	oldest = nil,
	newest = nil,
}

local function ResetElementTracker()
	elementTracker.ready = false
	elementTracker.pending = nil
	elementTracker.oldest = nil
	elementTracker.newest = nil
end

local function RecordElementInput(elementKey)
	if not elementTracker.ready then
		if elementTracker.pending == nil then
			elementTracker.pending = elementKey
			return
		end
		elementTracker.oldest = elementTracker.pending
		elementTracker.newest = elementKey
		elementTracker.pending = nil
		elementTracker.ready = true
		return
	end
	elementTracker.oldest = elementTracker.newest
	elementTracker.newest = elementKey
end

local function TrackedPairMatches(elements)
	if not elementTracker.ready or elements == nil then return false end
	local first = elements[1]
	local second = elements[2]
	return (elementTracker.oldest == first and elementTracker.newest == second)
		or (elementTracker.oldest == second and elementTracker.newest == first)
end

local function GetNextSynthSpell()
	if comboState == nil then return nil end
	for index = comboState.index + 1, #comboState.steps do
		local spell = SPELLS[comboState.steps[index]]
		if spell ~= nil then return spell end
	end
	return nil
end

local function BuildElementPlan(spell)
	local first = spell.elements[1]
	local second = spell.elements[2]
	if elementTracker.ready then
		if TrackedPairMatches(spell.elements) then return {} end
		-- 两槽按输入先后覆盖；保留最新且仍被目标配方需要的属性，只补另一个属性。
		if elementTracker.newest == first then return {second} end
		if elementTracker.newest == second then return {first} end
	end

	-- 无法安全复用时重新输入完整配方；将下一技能共享的属性放在最后，便于下一步继续保留。
	local nextSpell = GetNextSynthSpell()
	if first ~= second and nextSpell ~= nil then
		local nextNeedsFirst = nextSpell.elements[1] == first or nextSpell.elements[2] == first
		local nextNeedsSecond = nextSpell.elements[1] == second or nextSpell.elements[2] == second
		if nextNeedsFirst and not nextNeedsSecond then
			first, second = second, first
		end
	end
	return {first, second}
end

local function IsValidUnit(unit)
	return unit ~= nil and not unit:IsNull() and unit:IsAlive() and unit:CanBeSeen()
end

local function IsValidEnemyHero(unit)
	return IsValidUnit(unit)
		and unit:IsHero()
		and not J.IsSuspiciousIllusion(unit)
		and J.CanBeAttacked(unit)
end

local function IsTeleporting(unit)
	return unit:HasModifier("modifier_teleporting")
		or unit:HasModifier("modifier_teleporting_root_logic")
end

local function GetVisibleEnemies(range)
	local result = {}
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if IsValidEnemyHero(enemy) and GetUnitToUnitDistance(bot, enemy) <= range then
			table.insert(result, enemy)
		end
	end
	return result
end

local function GetPrimaryTarget()
	local target = J.GetProperTarget(bot)
	if IsValidEnemyHero(target) then return target end
	local best = nil
	local bestScore = -100000
	for _, enemy in pairs(GetVisibleEnemies(1600)) do
		local score = (1 - J.GetHP(enemy)) * 100
		if enemy:IsChanneling() or IsTeleporting(enemy) then score = score + 200 end
		if score > bestScore then
			best = enemy
			bestScore = score
		end
	end
	return best
end

local function GetAbility(name)
	if name == nil then return nil end
	return bot:GetAbilityByName(name)
end

local function TryUseElement(elementKey)
	local element = GetAbility(ELEMENTS[elementKey])
	if element == nil
	or element:GetLevel() <= 0
	or bot:IsSilenced()
	or not element:IsFullyCastable()
	then
		return false
	end
	bot:Action_UseAbility(element)
	RecordElementInput(elementKey)
	return true
end

local function IsAbilityReady(ability)
	return ability ~= nil
		and ability:GetLevel() > 0
		and ability:GetCooldownTimeRemaining() <= 0
end

local function IsItemReady(name)
	local item = IsItemAvailable(name)
	if item ~= nil and item:IsFullyCastable() then return item end
	return nil
end

local function HasTalent(name)
	local talent = GetAbility(name)
	return talent ~= nil and talent:GetLevel() > 0
end

local function GetStoneWindow()
	return HasTalent("special_bonus_unique_patchouli_6") and 4.75 or 3.25
end

local function HasAllElements()
	for _, name in pairs(ELEMENTS) do
		local ability = GetAbility(name)
		if ability == nil or ability:GetLevel() <= 0 then return false end
	end
	return true
end

local function ResetCombo()
	comboState = nil
end

local function AdvanceCombo()
	if comboState == nil then return end
	comboState.index = comboState.index + 1
	comboState.phase = "prepare"
	comboState.elementStage = 0
	comboState.elementPlan = nil
	comboState.expectedDeadline = nil
	comboState.controlStage = nil
	if comboState.index > #comboState.steps then ResetCombo() end
end

local function DetermineControlMode(target)
	local yukkuri = IsItemReady("item_yukkuri_stick")
	local distance = GetUnitToUnitDistance(bot, target)
	if yukkuri ~= nil and distance > yukkuri:GetCastRange() then yukkuri = nil end
	if yukkuri ~= nil then return "yukkuri" end
	return nil
end

local function GetSpellManaCost(ability)
	if ability == nil then return 0 end
	local ok, cost = pcall(function() return ability:GetManaCost() end)
	if ok and cost ~= nil then return cost end
	return 0
end

local function GetSpellTargetRange(code, ability)
	if ability == nil then return 0 end
	if code ~= "WFR" then return ability:GetCastRange() + 40 end

	local water = GetAbility(ELEMENTS.W)
	local waterLevel = water ~= nil and water:GetLevel() or 0
	local projectileRange = ability:GetSpecialValueInt("range")
		+ ability:GetSpecialValueInt("ex_range") * waterLevel
	if projectileRange <= 0 then projectileRange = ability:GetCastRange() end

	-- 大洪水的1700施法距离大于实际弹道；只在真实飞行距离的85%内索敌，给移动和预测误差留出余量。
	return math.min(ability:GetCastRange(), projectileRange) * WFR_TARGET_RANGE_RATIO
end

local function IsComboReady(name, target, allowCooldownSkip)
	local steps = COMBOS[name]
	if steps == nil or not IsValidEnemyHero(target) then return false, nil end
	local manaCost = 0
	local controlMode = nil
	local cooldownCount = 0
	for _, step in ipairs(steps) do
		if SPELLS[step] ~= nil then
			local ability = GetAbility(SPELLS[step].name)
			if ability == nil or ability:GetLevel() <= 0 then return false, nil end
			if ability:GetCooldownTimeRemaining() > 0 then
				cooldownCount = cooldownCount + 1
				if not allowCooldownSkip or cooldownCount > 1 then return false, nil end
			else
				manaCost = manaCost + GetSpellManaCost(ability)
			end
			if SPELLS[step].cast ~= "none" and SPELLS[step].cast ~= "self"
			and GetUnitToUnitDistance(bot, target) > GetSpellTargetRange(step, ability)
			then return false, nil end
		elseif step == "CONTROL" then
			controlMode = DetermineControlMode(target)
			if controlMode == nil then return false, nil end
		elseif step == "TSUNDERE" and IsItemReady("item_tsundere") == nil then
			return false, nil
		end
	end
	return bot:GetMana() >= manaCost + 100, controlMode
end

local function StartCombo(name, target, allowCooldownSkip)
	local ready, controlMode = IsComboReady(name, target, allowCooldownSkip)
	if not ready then return false end
	comboState = {
		name = name,
		steps = COMBOS[name],
		index = 1,
		target = target,
		startedAt = DotaTime(),
		phase = "prepare",
		elementStage = 0,
		spellCount = 0,
		segmentStart = nil,
		controlMode = controlMode,
		skipUnavailable = allowCooldownSkip == true,
		skippedUnavailable = 0,
	}
	return true
end

local function IsReaperPathClear(ability, target)
	if ability == nil or not IsValidUnit(target) then return false end
	local startLoc = bot:GetLocation()
	local targetLoc = target:GetExtrapolatedLocation(ability:GetCastPoint() + 0.15)
	local lineX = targetLoc.x - startLoc.x
	local lineY = targetLoc.y - startLoc.y
	local lineLengthSqr = lineX * lineX + lineY * lineY
	if lineLengthSqr <= 1 then return false end

	local hitbox = ability:GetSpecialValueInt("hitbox_radius")
	if hitbox <= 0 then hitbox = 120 end
	local blockRadiusSqr = (hitbox + 20) * (hitbox + 20)
	local function IsBlockingUnit(unit)
		if unit == target or not IsValidUnit(unit) or not J.CanBeAttacked(unit) then return false end
		local location = unit:GetLocation()
		local projection = ((location.x - startLoc.x) * lineX + (location.y - startLoc.y) * lineY)
			/ lineLengthSqr
		if projection <= 0 or projection >= 1 then return false end
		local closestX = startLoc.x + lineX * projection
		local closestY = startLoc.y + lineY * projection
		local offsetX = location.x - closestX
		local offsetY = location.y - closestY
		return offsetX * offsetX + offsetY * offsetY <= blockRadiusSqr
	end

	-- 生命收割者命中首个敌方单位即停止；独立施法时只在目标前方弹道净空时使用。
	for _, unitList in ipairs({UNIT_LIST_ENEMY_HEROES, UNIT_LIST_ENEMY_CREEPS}) do
		for _, unit in pairs(GetUnitList(unitList)) do
			if IsBlockingUnit(unit) then return false end
		end
	end
	return true
end

local function StartSingle(code, target, castLocation)
	local spell = SPELLS[code]
	local ability = spell ~= nil and GetAbility(spell.name) or nil
	if spell == nil or not IsAbilityReady(ability) then return false end
	if bot:GetMana() < GetSpellManaCost(ability) then return false end
	for _, elementKey in ipairs(spell.elements) do
		local element = GetAbility(ELEMENTS[elementKey])
		if element == nil or element:GetLevel() <= 0 then return false end
	end
	if spell.cast == "enemy" and not IsValidUnit(target) then return false end
	if castLocation ~= nil then
		if spell.cast ~= "point"
		or GetUnitToLocationDistance(bot, castLocation) > GetSpellTargetRange(code, ability)
		then
			return false
		end
	elseif spell.cast ~= "none" and spell.cast ~= "self"
	and IsValidUnit(target)
	and GetUnitToUnitDistance(bot, target) > GetSpellTargetRange(code, ability)
	then return false end
	if spell.cast == "self"
	and target ~= nil
	and target ~= bot
	and (not IsValidUnit(target) or GetUnitToUnitDistance(bot, target) > ability:GetCastRange() + 40)
	then return false end
	if code == "EDR" and castLocation == nil and not IsReaperPathClear(ability, target) then return false end
	comboState = {
		name = "single_" .. code,
		steps = {code},
		index = 1,
		target = target or bot,
		startedAt = DotaTime(),
		phase = "prepare",
		elementStage = 0,
		spellCount = 0,
		singleCastTarget = target,
		castLocation = castLocation,
	}
	return true
end

local function GetWaterSpiritTarget()
	local ability = GetAbility(SPELLS.WER.name)
	if not IsAbilityReady(ability) then return nil end

	local water = GetAbility(ELEMENTS.W)
	local wood = GetAbility(ELEMENTS.E)
	local healthRestore = ability:GetSpecialValueInt("base_health")
		+ (wood ~= nil and wood:GetLevel() or 0) * ability:GetSpecialValueInt("ex_health")
	local manaRestore = ability:GetSpecialValueInt("base_mana")
		+ (water ~= nil and water:GetLevel() or 0) * ability:GetSpecialValueInt("ex_mana")
	local bestTarget = nil
	local bestScore = -1
	local candidates = {bot}
	for _, ally in pairs(bot:GetNearbyHeroes(ability:GetCastRange() + 40, false, BOT_MODE_NONE) or {}) do
		if ally ~= bot then table.insert(candidates, ally) end
	end

	-- 水精灵不再只在本体重伤时使用：较明显的血蓝缺口即可恢复，也会支援施法范围内更缺资源的队友。
	for _, ally in ipairs(candidates) do
		if IsValidUnit(ally) and ally:IsHero() then
			local missingHealth = ally:GetMaxHealth() - ally:GetHealth()
			local missingMana = ally:GetMaxMana() - ally:GetMana()
			local usefulHealth = J.GetHP(ally) < 0.86 and missingHealth >= healthRestore * 0.40
			local usefulMana = ally:GetMaxMana() > 0
				and J.GetMP(ally) < 0.76
				and missingMana >= manaRestore * 0.40
			if usefulHealth or usefulMana then
				local score = math.min(missingHealth, healthRestore) / math.max(healthRestore, 1)
					+ math.min(missingMana, manaRestore) / math.max(manaRestore, 1)
				if ally == bot then score = score + 0.15 end
				if J.GetHP(ally) < 0.45 then score = score + 1.25 end
				if ally:WasRecentlyDamagedByAnyHero(2.0) then score = score + 0.35 end
				if score > bestScore then
					bestTarget = ally
					bestScore = score
				end
			end
		end
	end
	return bestTarget
end

local function TryStartReaperTreeHeal()
	if J.GetHP(bot) > 0.46 then return false end
	local ability = GetAbility(SPELLS.EDR.name)
	if not IsAbilityReady(ability) then return false end

	local projectileRange = ability:GetSpecialValueInt("range")
	local treeSearchRange = ability:GetCastRange()
	if projectileRange > 0 then treeSearchRange = math.min(treeSearchRange, projectileRange) end
	local bestLocation = nil
	local bestDistance = 100000
	for _, treeId in pairs(bot:GetNearbyTrees(treeSearchRange) or {}) do
		local location = GetTreeLocation(treeId)
		local distance = GetUnitToLocationDistance(bot, location)
		if distance >= 32 and distance < bestDistance then
			bestLocation = location
			bestDistance = distance
		end
	end
	if bestLocation == nil then return false end

	-- 收割者碰到树也会立即结算治疗；危急且没有更直接的恢复手段时瞄准最近树木。
	return StartSingle("EDR", bot, bestLocation)
end

local function GetCastLocation(ability, target, castLocation)
	if castLocation ~= nil then return castLocation end
	if not IsValidUnit(target) then return bot:GetLocation() end
	local castPoint = ability ~= nil and ability:GetCastPoint() or 0
	return target:GetExtrapolatedLocation(castPoint + 0.15)
end

local function CastSynthSpell(spell, ability, target, singleCastTarget, castLocation)
	if spell.cast == "none" then
		bot:Action_UseAbility(ability)
	elseif spell.cast == "self" then
		local friendlyTarget = singleCastTarget or bot
		if not IsValidUnit(friendlyTarget) then return false end
		bot:Action_UseAbilityOnEntity(ability, friendlyTarget)
	elseif spell.cast == "enemy" then
		if not IsValidUnit(target) then return false end
		bot:Action_UseAbilityOnEntity(ability, target)
	else
		bot:Action_UseAbilityOnLocation(ability, GetCastLocation(ability, target, castLocation))
	end
	return true
end

local ProcessCombo

local function ProcessControlStep()
	local target = comboState.target
	if not IsValidEnemyHero(target) then ResetCombo(); return false end
	if comboState.controlStage == "wait_yukkuri" then
		if target:HasModifier("modifier_item_yukkuri_stick_debuff") or target:IsHexed() then
			AdvanceCombo()
			return ProcessCombo()
		elseif DotaTime() >= comboState.controlDeadline then
			ResetCombo()
		end
		return false
	end

	-- 三维书已由三位一体替换；控制槽固定使用悠闲棒，命中确认后立即继续连段。
	local yukkuri = IsItemReady("item_yukkuri_stick")
	if yukkuri == nil then ResetCombo(); return false end
	bot:Action_UseAbilityOnEntity(yukkuri, target)
	comboState.controlStage = "wait_yukkuri"
	comboState.controlDeadline = DotaTime() + 0.18
	return true
end

ProcessCombo = function()
	if comboState == nil then return false end
	if DotaTime() - comboState.startedAt > COMBO_TIMEOUT then ResetCombo(); return false end
	if not IsValidUnit(comboState.target) then ResetCombo(); return false end

	local step = comboState.steps[comboState.index]
	if step == nil then ResetCombo(); return false end
	if step == "CONTROL" then return ProcessControlStep() end
	if step == "TSUNDERE" then
		local item = IsItemReady("item_tsundere")
		if item == nil then ResetCombo(); return false end
		bot:Action_UseAbility(item)
		AdvanceCombo()
		return true
	end

	local spell = SPELLS[step]
	local ability = spell ~= nil and GetAbility(spell.name) or nil
	if spell == nil or ability == nil then ResetCombo(); return false end

	-- 施法后先验证冷却变化；拒绝把被打断或未接受的指令当成已完成步骤。
	if comboState.phase == "verify" then
		if ability:GetCooldownTimeRemaining() > 0 or not ability:IsFullyCastable() then
			comboState.spellCount = comboState.spellCount + 1
			if (comboState.spellCount - 1) % 5 == 0 then
				comboState.segmentStart = comboState.pendingCastTime
			end
			if comboState.spellCount % 5 == 0 then comboState.segmentStart = nil end
			AdvanceCombo()
			return ProcessCombo()
		elseif DotaTime() >= comboState.verifyDeadline then
			ResetCombo()
		end
		return false
	end

	if ability:GetCooldownTimeRemaining() > 0 then
		if comboState.skipUnavailable and comboState.skippedUnavailable < 1 then
			-- 团战降级连段只容忍一个预先冷却的技能；跳过步骤但不计贤者之石层数。
			comboState.skippedUnavailable = comboState.skippedUnavailable + 1
			AdvanceCombo()
			return ProcessCombo()
		end
		ResetCombo()
		return false
	end

	local visible = ability.IsHidden == nil or not ability:IsHidden()
	if not visible then
		if comboState.elementPlan == nil then
			comboState.elementPlan = BuildElementPlan(spell)
			comboState.elementStage = 0
			-- 记录与游戏侧显示不一致时不能冒险省略属性，完整输入一次配方即可重新建立有序记录。
			if #comboState.elementPlan == 0 then
				ResetElementTracker()
				comboState.elementPlan = {spell.elements[1], spell.elements[2]}
			end
		end
		-- 元素切换分成独立Think，保证任何一帧都只有一个Action；可信记录允许只补一个共享属性。
		if comboState.elementStage < #comboState.elementPlan then
			local elementKey = comboState.elementPlan[comboState.elementStage + 1]
			if not TryUseElement(elementKey) then return false end
			comboState.elementStage = comboState.elementStage + 1
			if comboState.elementStage == #comboState.elementPlan then
				comboState.expectedDeadline = DotaTime() + 0.25
			end
			return true
		end
		if comboState.expectedDeadline ~= nil and DotaTime() > comboState.expectedDeadline then
			ResetElementTracker()
			ResetCombo()
		end
		return false
	end
	if elementTracker.ready and not TrackedPairMatches(spell.elements) then
		-- 合成技能已经正确显示但本地顺序记录失配，先丢弃记录；下一技能会用完整配方重新同步。
		ResetElementTracker()
	end

	if not IsAbilityReady(ability) or bot:GetMana() < GetSpellManaCost(ability) then ResetCombo(); return false end
	if comboState.segmentStart ~= nil
	and DotaTime() - comboState.segmentStart >= GetStoneWindow()
	then
		ResetCombo()
		return false
	end
	local castLocation = comboState.castLocation
	if step == "WFR" and castLocation == nil then
		castLocation = GetCastLocation(ability, comboState.target, nil)
	end
	if step == "WFR"
	and GetUnitToLocationDistance(bot, castLocation) > GetSpellTargetRange(step, ability)
	then
		ResetCombo()
		return false
	end
	if CastSynthSpell(spell, ability, comboState.target, comboState.singleCastTarget, castLocation) then
		comboState.phase = "verify"
		comboState.pendingCastTime = DotaTime()
		-- 不人为等待技能间隔；这里只给约0.2秒施法前摇留下验收余量，冷却一变化就立即推进下一步。
		comboState.verifyDeadline = DotaTime() + math.max(0.32, ability:GetCastPoint() + 0.12)
		return true
	end
	ResetCombo()
	return false
end

local function TryEmergencyItem(enemies)
	local trinity = IsItemReady("item_trinity")
	local nearbyFightEnemies = 0
	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= 1200 then
			nearbyFightEnemies = nearbyFightEnemies + 1
		end
	end
	local shouldPreShield = nearbyFightEnemies >= 2 and J.IsInTeamFight(bot, 1200)
	if trinity ~= nil
	and (shouldPreShield or ConsiderItemShield(trinity) > BOT_ACTION_DESIRE_NONE)
	then
		-- 团战形成时提前获得护盾和状态抗性；即时施放可插入连段且不清空当前步骤。
		bot:Action_UseAbility(trinity)
		return true
	end
	local tsundere = IsItemReady("item_tsundere")
	if tsundere ~= nil and J.GetHP(bot) < 0.28 and bot:WasRecentlyDamagedByAnyHero(1.5) then
		ResetCombo()
		bot:Action_UseAbility(tsundere)
		return true
	end
	local yukkuri = IsItemReady("item_yukkuri_stick")
	if yukkuri ~= nil and J.IsSeriouslyRetreating(bot) then
		local pursuer = nil
		local bestScore = -100000
		for _, enemy in pairs(enemies) do
			local distance = GetUnitToUnitDistance(bot, enemy)
			if distance <= yukkuri:GetCastRange()
			and not enemy:IsStunned()
			and not enemy:IsHexed()
			and not enemy:IsRooted()
			then
				local recentlyDamaged = bot:WasRecentlyDamagedByHero(enemy, 2.0)
				if recentlyDamaged or distance <= 500 then
					local score = (recentlyDamaged and 1000 or 0) - distance
					if score > bestScore then
						pursuer = enemy
						bestScore = score
					end
				end
			end
		end
		if pursuer ~= nil then
			ResetCombo()
			bot:Action_UseAbilityOnEntity(yukkuri, pursuer)
			return true
		end
	end
	return false
end

local function TryInterrupt(enemies)
	for _, enemy in pairs(enemies) do
		if enemy:IsChanneling() or IsTeleporting(enemy) then
			local yukkuri = IsItemReady("item_yukkuri_stick")
			if yukkuri ~= nil and GetUnitToUnitDistance(bot, enemy) <= yukkuri:GetCastRange() then
				ResetCombo()
				bot:Action_UseAbilityOnEntity(yukkuri, enemy)
				return true
			end
			ResetCombo()
			local lake = GetAbility(SPELLS.WWR.name)
			local interruptCode = IsAbilityReady(lake)
				and GetUnitToUnitDistance(bot, enemy) <= lake:GetCastRange() + 40
				and "WWR" or "WFR"
			if StartSingle(interruptCode, enemy) then
				return ProcessCombo()
			end
		end
	end
	return false
end

local function CountEnemies(enemies, range)
	local count = 0
	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= range then count = count + 1 end
	end
	return count
end

local function CountCoolingSynthSpells()
	local count = 0
	for _, spell in pairs(SPELLS) do
		local ability = GetAbility(spell.name)
		if ability ~= nil
		and ability:GetLevel() > 0
		and ability:GetCooldownTimeRemaining() > 0
		then
			count = count + 1
		end
	end
	return count
end

local function IsHardDisabled(target)
	return target:IsStunned() or target:IsHexed() or target:IsRooted()
		or GetModifiersTimeLeft(target, ModifierNamesStun) > 0.6
end

local function IsLaneComboKillWindow(target)
	return IsValidEnemyHero(target) and J.GetHP(target) <= LANE_COMBO_KILL_HP
end

local function ShouldReserveLaneCombo(target)
	if bot:GetActiveMode() ~= BOT_MODE_LANING
	or J.IsSeriouslyRetreating(bot)
	or not HasAllElements()
	or not IsLaneComboKillWindow(target)
	or GetUnitToUnitDistance(bot, target) > 750
	then
		return false
	end
	local ready = IsComboReady("lane_pressure", target, false)
	return not ready
end

local function TryStartFixedCombo(target, enemies)
	if not HasAllElements() or not IsValidEnemyHero(target) then return false end
	if GetUnitToUnitDistance(bot, target) > 750 then return false end
	local mode = bot:GetActiveMode()
	local nearbyEnemyCount = CountEnemies(enemies, 1200)
	local teamFight = nearbyEnemyCount >= 2 and J.IsInTeamFight(bot, 1200)
	local coolingSpells = teamFight and CountCoolingSynthSpells() or 0
	if coolingSpells >= 2 then
		-- 多技能冷却时不再强凑固定顺序，交给后续单技能决策选择当前可用技能。
		return false
	end
	local allowTeamFightSkip = teamFight and coolingSpells == 1

	-- 对线进入击杀线，或其他模式偶遇不超过两名敌人时，越过Bot模式直接尝试抓单连段。
	local forcePickCombo = (mode == BOT_MODE_LANING and IsLaneComboKillWindow(target))
		or (mode ~= BOT_MODE_LANING and nearbyEnemyCount <= 2)
	if forcePickCombo then
		if mode ~= BOT_MODE_LANING
		and J.GetHP(target) > LANE_COMBO_KILL_HP
		and StartCombo("triple", target, false)
		then return true end
		if DetermineControlMode(target) ~= nil
		and IsItemReady("item_tsundere") ~= nil
		and StartCombo("double_item", target, false)
		then return true end
		if StartCombo("double_default", target, false) then return true end
		if StartCombo("lane_pressure", target, false) then return true end
	end

	-- 对线只在击杀窗口执行完整连段；条件未齐时由保留逻辑等待，不使用团战跳步规则。
	if mode == BOT_MODE_LANING then return false end

	local highValueSingle = J.IsGoingOnSomeone(bot)
		and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
		and target:GetLevel() >= bot:GetLevel() - 2
	if (teamFight or highValueSingle)
	and StartCombo("triple", target, allowTeamFightSkip)
	then return true end

	if DetermineControlMode(target) ~= nil
	and IsItemReady("item_tsundere") ~= nil
	and StartCombo("double_item", target, allowTeamFightSkip)
	then return true end
	if IsHardDisabled(target)
	and StartCombo("double_ally", target, allowTeamFightSkip)
	then return true end
	if (J.GetHP(bot) < 0.72 or J.GetMP(bot) < 0.72)
	and StartCombo("double_recover", target, allowTeamFightSkip)
	then return true end
	if J.IsGoingOnSomeone(bot)
	and not target:IsFacingLocation(bot:GetLocation(), 100)
	and StartCombo("double_chase", target, allowTeamFightSkip)
	then return true end
	if (J.IsGoingOnSomeone(bot) or teamFight)
	and StartCombo("double_default", target, allowTeamFightSkip)
	then return true end
	return false
end

local function TryStartSingleSpell(target, enemies)
	local waterSpiritTarget = GetWaterSpiritTarget()
	if waterSpiritTarget ~= nil and StartSingle("WER", waterSpiritTarget) then return true end
	if TryStartReaperTreeHeal() then return true end

	local opportunisticFight = IsValidEnemyHero(target) and CountEnemies(enemies, 1200) <= 2
	local seriousRetreat = J.IsSeriouslyRetreating(bot)
	if (J.IsGoingOnSomeone(bot)
		or J.IsInTeamFight(bot, 1200)
		or (seriousRetreat and J.IsSeriouslyRetreating(bot, SPELLS.EER.name))
		or opportunisticFight)
	and not bot:HasModifier("modifier_thdots_patchouli_wood_wood_effect")
	and StartSingle("EER", bot)
	then return true end

	if IsValidEnemyHero(target) then
		local mode = bot:GetActiveMode()
		local shouldCast = mode == BOT_MODE_LANING
			or J.IsGoingOnSomeone(bot)
			or J.IsInTeamFight(bot, 1200)
			or seriousRetreat
			or opportunisticFight
		if shouldCast and (mode ~= BOT_MODE_LANING or J.GetMP(bot) >= 0.25) then
			local order = {}
			if not IsHardDisabled(target) then
				order = {"EFR", "FFR", "WWR", "QFR"}
			end
			-- 完整连段不可用时先补控制与地形，再用水银降魔抗，随后固定优先巨石、洪水、收割者爆发。
			for _, code in ipairs({"WDR", "DFR", "WFR", "EDR",
				"QER", "QWR", "QDR", "DDR", "QQR"})
			do
				table.insert(order, code)
			end
			for _, code in ipairs(order) do
				local registeredRetreatCast = not seriousRetreat
					or J.IsSeriouslyRetreating(bot, SPELLS[code].name)
				if registeredRetreatCast and StartSingle(code, target) then return true end
			end
		end
	end

	local mode = bot:GetActiveMode()
	if J.GetMP(bot) >= 0.50 and (mode == BOT_MODE_FARM or J.IsPushing(bot) or J.IsDefending(bot)) then
		local creeps = bot:GetNearbyLaneCreeps(850, true) or {}
		if #creeps >= 4 and StartSingle("QER", creeps[1]) then return true end
	end
	if J.IsDoingRoshan(bot) or J.IsPushing(bot) or mode == BOT_MODE_FARM then
		if StartSingle("QQR", bot) then return true end
	end
	return false
end

local function TryYukkuriSetup(target, enemies)
	local yukkuri = IsItemReady("item_yukkuri_stick")
	if yukkuri == nil
	or not IsValidEnemyHero(target)
	or IsHardDisabled(target)
	or GetUnitToUnitDistance(bot, target) > yukkuri:GetCastRange()
	then
		return false
	end

	local mode = bot:GetActiveMode()
	local laneSetup = mode == BOT_MODE_LANING and J.GetHP(target) <= 0.70
	local isolatedSetup = CountEnemies(enemies, 1200) <= 2 and J.GetHP(target) <= 0.75
	if laneSetup or isolatedSetup or J.IsGoingOnSomeone(bot) then
		-- 完整连段无法启动时用提前成型的悠闲棒留人，为下一轮控制/伤害技能创造命中窗口。
		bot:Action_UseAbilityOnEntity(yukkuri, target)
		return true
	end
	return false
end

local function TryHorseItems()
	local horseKing = IsItemReady("item_horse_king")
	if horseKing ~= nil and ConsiderItemHorseKing(horseKing) > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(horseKing)
		return true
	end
	local horseRed = IsItemReady("item_horse_red")
	if horseRed ~= nil and ConsiderItemHorseRed(horseRed) > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(horseRed)
		return true
	end
	return false
end

local function TryYatagarasu()
	local item = IsItemReady("item_yatagarasu")
	if item == nil then return false end
	local usefulAllies = 0
	for _, ally in pairs(bot:GetNearbyHeroes(600, false, BOT_MODE_NONE) or {}) do
		if IsValidUnit(ally)
		and ally:GetMaxMana() - ally:GetMana() >= 120
		then
			usefulAllies = usefulAllies + 1
		end
	end
	local selfMissingMana = bot:GetMaxMana() - bot:GetMana()
	if (selfMissingMana >= 180 and J.GetMP(bot) <= 0.65)
	or usefulAllies >= 2
	then
		bot:Action_UseAbility(item)
		return true
	end
	return false
end

local function GetCurrentElementPair()
	for code, spell in pairs(SPELLS) do
		local ability = GetAbility(spell.name)
		if ability ~= nil and (ability.IsHidden == nil or not ability:IsHidden()) then
			return string.sub(code, 1, 2)
		end
	end
	return nil
end

local function CanUseElement(elementKey)
	local ability = GetAbility(ELEMENTS[elementKey])
	return ability ~= nil and ability:GetLevel() > 0
end

local function GetIdleElementKey(enemies, target)
	local hp = J.GetHP(bot)
	local mp = J.GetMP(bot)
	local mode = bot:GetActiveMode()

	if J.IsRetreating(bot, ELEMENTS.F, { legacyModeDesire = BOT_MODE_DESIRE_VERYHIGH })
	then return "F" end
	if hp < 0.58 then return "E" end
	if J.IsGoingOnSomeone(bot) then
		if IsValidEnemyHero(target)
		and GetUnitToUnitDistance(bot, target) > bot:GetAttackRange() + 150
		then return "F" end
		return "Q"
	end
	if bot:WasRecentlyDamagedByAnyHero(2.0) and #enemies > 0 then return "D" end
	if mp < 0.45 then return "W" end
	if mode == BOT_MODE_LANING then
		if hp < 0.80 then return "E" end
		return "Q"
	end
	if mode == BOT_MODE_FARM or J.IsPushing(bot) or J.IsDefending(bot) then return "Q" end
	if #enemies > 0 then return "D" end
	if hp < 0.85 then return "E" end
	if mp < 0.75 then return "W" end
	return "D"
end

local function TryIdleElementStance(enemies, target)
	if bot:IsSilenced() then return false end
	local desired = GetIdleElementKey(enemies, target)
	if not CanUseElement(desired) then
		-- 前六级元素尚未学全时，按生存、输出的顺序退回到已学习属性。
		for _, fallback in ipairs({"D", "Q", "W", "E", "F"}) do
			if CanUseElement(fallback) then desired = fallback; break end
		end
	end
	if not CanUseElement(desired) then return false end
	if GetCurrentElementPair() == desired .. desired then return false end

	-- 空闲姿态逐次挂入同一元素：双火补刀压制、双木回复、双土追逃，双水回蓝、双金抗压。
	return TryUseElement(desired)
end

local function TryPrepareLaneComboElements()
	if not CanUseElement("E") or GetCurrentElementPair() == "EE" then return false end
	-- 等待击杀连段冷却时预先挂双木，对应lane_pressure首个EER并同时提供生命恢复。
	return TryUseElement("E")
end

function AbilityUsageThink()
	-- 帕秋莉连段需要逐帧输入属性，不能使用IsBotAwake内置的0.25秒全局门控。
	if bot == nil or bot:IsIllusion() or bot:IsHexed() or bot:IsStunned() then return end
	-- 元素切换可以取消合成技能后摇；仅让既有连段越过IsUsingAbility，不放宽施法前摇、控制或排队动作。
	if comboState ~= nil
	and bot:IsAlive()
	and bot:IsUsingAbility()
	and not bot:IsCastingAbility()
	and not bot:IsChanneling()
	and not bot:IsStunned()
	and not bot:IsNightmared()
	and not J.HasQueuedAction(bot)
	and not (bot:IsInvulnerable() and not bot:HasModifier("modifier_fountain_invulnerability"))
	then
		ProcessCombo()
		return
	end
	if J.CanNotUseAction(bot) then return end

	local enemies = GetVisibleEnemies(1800)
	local target = GetPrimaryTarget()

	if TryEmergencyItem(enemies) then return end
	if TryInterrupt(enemies) then return end
	-- 八咫乌为零前摇即时回蓝，可插入连段任意位置；不改变当前步骤和元素状态。
	if TryYatagarasu() then return end
	if comboState ~= nil then ProcessCombo(); return end

	-- 抓单/线杀连段优先于当前Bot模式和普通装备动作，避免模式缓存错过短暂击杀窗口。
	if TryStartFixedCombo(target, enemies) then ProcessCombo(); return end
	local reserveLaneCombo = ShouldReserveLaneCombo(target)
	if not reserveLaneCombo and TryYukkuriSetup(target, enemies) then return end
	if TryHorseItems() then return end
	if reserveLaneCombo then
		if TryPrepareLaneComboElements() then return end
		ConsiderNeutralItems()
		return
	end

	if TryStartSingleSpell(target, enemies) then ProcessCombo(); return end
	if TryIdleElementStance(enemies, target) then return end

	-- 中立物品固定放在末尾，之后不再允许任何技能或装备覆盖它的指令。
	ConsiderNeutralItems()
end
