local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local YuukaUnits = require(GetScriptDirectory()..'/THDFuncLib/yuuka_units')

local YuukaCombo = {}

local HERO_NAME = "npc_dota_hero_venomancer"
local YUUKA01 = "ability_thdots_yuuka01"
local YUUKA02 = "ability_thdots_yuuka02"
local YUUKA04 = "ability_thdots_yuuka04"
local YUUKA_EX = "ability_thdots_YuukaEx"
local YUUKA_EX2 = "ability_thdots_YuukaEx2"
local COMBO_TIMEOUT = 8.0
local LANE_PRESSURE_HP = 0.65
local LANE_PRESSURE_RANGE = 900

local function GetAbility(bot, name)
	local ability = bot:GetAbilityByName(name)
	if ability == nil then return nil end
	if ability.IsTrained ~= nil and not ability:IsTrained() then return nil end
	return ability
end

local function IsCastable(ability)
	return ability ~= nil and ability:IsFullyCastable()
end

local function GetManaCost(ability)
	if ability == nil or ability.GetManaCost == nil then return 0 end
	local ok, value = pcall(function() return ability:GetManaCost() end)
	return ok and value or 0
end

local function IsAlive(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil then
		local ok, result = pcall(function() return unit:IsNull() end)
		if not ok or result then return false end
	end
	if unit.IsAlive == nil then return false end
	local ok, result = pcall(function() return unit:IsAlive() end)
	return ok and result == true
end

local function IsValidTarget(bot, target)
	return IsAlive(target)
		and target.GetTeam ~= nil
		and target:GetTeam() ~= bot:GetTeam()
		and IsValidCastTarget(target, true, true)
end

local function IsEnemyTowerNearby(bot, range)
	if bot.GetNearbyTowers == nil then return false end
	local ok, towers = pcall(function() return bot:GetNearbyTowers(range, true) end)
	return ok and towers ~= nil and #towers > 0
end

local function GetYuuka01Radius(ability)
	if ability ~= nil and ability.GetAOERadius ~= nil then
		local ok, radius = pcall(function() return ability:GetAOERadius() end)
		if ok and radius ~= nil and radius > 0 then return radius end
	end
	local radii = {125, 150, 175, 200}
	return radii[math.max(ability:GetLevel(), 1)] or 200
end

local function FindComboTarget(bot, ability02)
	local castRange = ability02:GetCastRange()
	local target = J.GetProperTarget(bot)
	if IsValidTarget(bot, target) and GetUnitToUnitDistance(bot, target) <= castRange then
		return target
	end

	local best = nil
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, math.min(castRange, 1600), true, BOT_MODE_NONE)) do
		if IsValidTarget(bot, enemy) and GetUnitToUnitDistance(bot, enemy) <= castRange
		and (best == nil or enemy:GetHealth() < best:GetHealth())
		then
			best = enemy
		end
	end
	return best
end

local function GetAbilities(bot)
	return {
		one = GetAbility(bot, YUUKA01),
		two = GetAbility(bot, YUUKA02),
		ultimate = GetAbility(bot, YUUKA04),
		ex = GetAbility(bot, YUUKA_EX),
		ex2 = GetAbility(bot, YUUKA_EX2),
	}
end

local function HasSafeLaneNumbers(bot)
	local enemyCount = 0
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, LANE_PRESSURE_RANGE, true, BOT_MODE_NONE)) do
		if IsValidTarget(bot, enemy) then enemyCount = enemyCount + 1 end
	end

	local allyCount = 1
	for _, ally in pairs(CachedGetNearbyHeroes(bot, LANE_PRESSURE_RANGE, false, BOT_MODE_NONE)) do
		local isIllusion = false
		if ally ~= nil and ally.IsIllusion ~= nil then
			local ok, result = pcall(function() return ally:IsIllusion() end)
			isIllusion = ok and result == true
		end
		if IsAlive(ally) and not isIllusion then allyCount = allyCount + 1 end
	end
	return enemyCount <= allyCount
end

local function IsEnemyTowerNearTarget(target, range)
	if target == nil or UNIT_LIST_ENEMY_BUILDINGS == nil or GetUnitList == nil then return false end
	for _, building in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS) or {}) do
		if IsAlive(building) and building.CanBeSeen ~= nil and building:CanBeSeen()
		then
			local unitName = building.GetUnitName ~= nil and building:GetUnitName() or ""
			if string.find(unitName, "tower", 1, true) ~= nil
			and GetUnitToUnitDistance(target, building) <= range
			then
				return true
			end
		end
	end
	return false
end

local function Clear(bot)
	bot.thdYuukaCombo = nil
end

function YuukaCombo.IsActive(bot)
	return bot ~= nil and bot.thdYuukaCombo ~= nil
end

function YuukaCombo.CanBegin(bot)
	if bot == nil or bot:GetUnitName() ~= HERO_NAME or YuukaCombo.IsActive(bot)
	or bot:IsSilenced() or J.IsRetreating(bot)
	or not (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	or IsEnemyTowerNearby(bot, 750)
	then
		return false
	end

	local abilities = GetAbilities(bot)
	if not IsCastable(abilities.one) or not IsCastable(abilities.two) or not IsCastable(abilities.ex2) then
		return false
	end
	local target = FindComboTarget(bot, abilities.two)
	if target == nil then return false end
	if not J.IsInTeamFight(bot, 1200) and not J.WeAreStronger(bot, 1000) then return false end

	local useUltimate = IsCastable(abilities.ultimate) and YuukaUnits.GetIllusion(bot) == nil
	if useUltimate and not IsCastable(abilities.ex) then return false end
	local manaRequired = GetManaCost(abilities.one) + GetManaCost(abilities.two) + GetManaCost(abilities.ex2)
	if useUltimate then
		manaRequired = manaRequired + GetManaCost(abilities.ex) + GetManaCost(abilities.ultimate)
	end
	if bot.GetMana ~= nil and bot:GetMana() < manaRequired then return false end
	return true, target, useUltimate
end

function YuukaCombo.CanBeginLanePressure(bot)
	if bot == nil or bot:GetUnitName() ~= HERO_NAME or YuukaCombo.IsActive(bot)
	or bot:IsSilenced() or J.IsRetreating(bot)
	or not J.IsInLaningPhase() or bot:GetActiveMode() ~= BOT_MODE_LANING
	or DotaTime() < (bot.yuukaNextLaneHarassTime or -90)
	or J.GetHP(bot) < LANE_PRESSURE_HP
	or IsEnemyTowerNearby(bot, LANE_PRESSURE_RANGE)
	or not J.WeAreStronger(bot, LANE_PRESSURE_RANGE)
	or not HasSafeLaneNumbers(bot)
	then
		return false
	end

	local abilities = GetAbilities(bot)
	if not IsCastable(abilities.one) or not IsCastable(abilities.two) or not IsCastable(abilities.ex2) then
		return false
	end
	local target = FindComboTarget(bot, abilities.two)
	if target == nil then return false end
	if IsEnemyTowerNearTarget(target, 750) then return false end

	local manaRequired = GetManaCost(abilities.one) + GetManaCost(abilities.two) + GetManaCost(abilities.ex2)
	if bot.GetMana ~= nil and bot:GetMana() < manaRequired then return false end
	return true, target
end

local function Start(bot, target, useUltimate, lanePressure)
	bot.thdYuukaCombo = {
		target = target,
		useUltimate = useUltimate,
		lanePressure = lanePressure == true,
		stage = useUltimate and "plant" or "cast_two",
		startedAt = DotaTime(),
		deadline = DotaTime() + COMBO_TIMEOUT,
		nextActionTime = DotaTime(),
		stageDeadline = DotaTime() + 2.0,
	}
	if lanePressure then bot.yuukaNextLaneHarassTime = DotaTime() + 8 end
	return true
end

function YuukaCombo.Begin(bot)
	local canBegin, target, useUltimate = YuukaCombo.CanBegin(bot)
	if not canBegin then return false end
	return Start(bot, target, useUltimate, false)
end

function YuukaCombo.BeginLanePressure(bot)
	local canBegin, target = YuukaCombo.CanBeginLanePressure(bot)
	if not canBegin then return false end
	-- 对线压制固定从二技能起手，不消耗大招或永久花朵。
	return Start(bot, target, false, true)
end

local function AbortIfNeeded(bot, state)
	if J.IsRetreating(bot) or bot:IsSilenced() or DotaTime() > state.deadline
	or not IsValidTarget(bot, state.target)
	then
		Clear(bot)
		return true
	end
	return false
end

local function FindDashLocation(bot, state, abilityEx2)
	local castRange = abilityEx2:GetCastRange()
	-- Bot 只提交目的地点；游戏侧负责解析附近所属花或万宝槌直达位置。
	if GetUnitToUnitDistance(bot, state.target) <= castRange then return state.target:GetLocation() end
	return nil
end

function YuukaCombo.Think(bot)
	local state = bot ~= nil and bot.thdYuukaCombo or nil
	if state == nil then return false end
	if AbortIfNeeded(bot, state) then return false end
	if J.CanNotUseAction(bot) or DotaTime() < state.nextActionTime then return true end

	local abilities = GetAbilities(bot)
	if state.stage == "plant" then
		if not IsCastable(abilities.ex) then Clear(bot) return false end
		bot:Action_UseAbility(abilities.ex)
		state.stage = "cast_ultimate"
		state.nextActionTime = DotaTime() + 0.3
		state.stageDeadline = DotaTime() + 1.4
		YuukaUnits.Invalidate(bot)
		return true
	end

	if state.stage == "cast_ultimate" then
		if IsCastable(abilities.ultimate) then
			-- EX 花固定生成在本体前方 100；对当前位置施法即可由游戏侧在 250 范围内锁定。
			bot:Action_UseAbilityOnLocation(abilities.ultimate, bot:GetLocation())
			state.stage = "wait_illusion"
			state.nextActionTime = DotaTime() + 0.3
			state.stageDeadline = DotaTime() + 1.5
			YuukaUnits.Invalidate(bot)
			return true
		end
		if DotaTime() > state.stageDeadline then Clear(bot) return false end
		return true
	end

	if state.stage == "wait_illusion" then
		if YuukaUnits.GetIllusion(bot, true) ~= nil then
			state.stage = "cast_two"
		elseif DotaTime() > state.stageDeadline then
			Clear(bot)
			return false
		else
			return true
		end
	end

	if state.stage == "cast_two" then
		if not IsCastable(abilities.two)
		or GetUnitToUnitDistance(bot, state.target) > abilities.two:GetCastRange()
		then
			Clear(bot)
			return false
		end
		bot:Action_UseAbilityOnEntity(abilities.two, state.target)
		state.stage = "dash"
		state.nextActionTime = DotaTime() + 0.65
		state.stageDeadline = DotaTime() + 1.8
		YuukaUnits.Invalidate(bot)
		return true
	end

	if state.stage == "dash" then
		if IsCastable(abilities.ex2) then
			local dashLocation = FindDashLocation(bot, state, abilities.ex2)
			if dashLocation ~= nil then
				bot:Action_UseAbilityOnLocation(abilities.ex2, dashLocation)
				state.stage = "cast_one"
				state.nextActionTime = DotaTime() + 0.4
				state.stageDeadline = DotaTime() + 1.2
				return true
			end
		end
		if DotaTime() > state.stageDeadline then Clear(bot) return false end
		return true
	end

	if state.stage == "cast_one" then
		if IsCastable(abilities.one) then
			local radius = GetYuuka01Radius(abilities.one)
			if GetUnitToUnitDistance(bot, state.target) <= radius + 125 then
				bot:Action_UseAbility(abilities.one)
				Clear(bot)
				return true
			end
		end
		if DotaTime() > state.stageDeadline then Clear(bot) return false end
		return true
	end

	Clear(bot)
	return false
end

function YuukaCombo.GetModeDesire(bot)
	if bot == nil or bot:GetUnitName() ~= HERO_NAME or not YuukaCombo.IsActive(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	local state = bot.thdYuukaCombo
	if AbortIfNeeded(bot, state) then return BOT_MODE_DESIRE_NONE end
	return BOT_MODE_DESIRE_ABSOLUTE
end

return YuukaCombo
