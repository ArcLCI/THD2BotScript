require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")
local YuukaUnits = require(GetScriptDirectory() .. "/THDFuncLib/yuuka_units")
local YuukaCombo = require(GetScriptDirectory() .. "/THDFuncLib/yuuka_combo")
local RoamInitiation = require(GetScriptDirectory() .. "/THDFuncLib/roam_initiation")

local YUUKA01 = "ability_thdots_yuuka01"
local YUUKA02 = "ability_thdots_yuuka02"
local YUUKA03 = "ability_thdots_yuuka03"
local YUUKA04 = "ability_thdots_yuuka04"
local YUUKA_EX = "ability_thdots_YuukaEx"
local YUUKA_EX2 = "ability_thdots_YuukaEx2"
local WANBAO_MODIFIER = "modifier_item_wanbaochui"
local ACTION_GUARD_TIME = 0.05

local function GetProfile(bot)
	return BotProfile.GetProfileOrDefault(bot, BotProfile.FRONTLINE)
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

local function MarkItemAction(bot)
	bot.yuukaLastItemActionTime = DotaTime()
end

local function WasItemActionJustIssued(bot)
	return DotaTime() - (bot.yuukaLastItemActionTime or -90) <= ACTION_GUARD_TIME
end

local function GetAbilityManaCost(ability)
	if ability == nil or ability.GetManaCost == nil then return 0 end
	local ok, value = pcall(function() return ability:GetManaCost() end)
	return ok and value or 0
end

local function HasManaFor(bot, ability, reserve)
	if bot.GetMana == nil then return true end
	return bot:GetMana() >= GetAbilityManaCost(ability) + (reserve or 0)
end

local function IsVisibleRealEnemy(bot, target, allowMagicImmune)
	return target ~= nil
		and target.GetTeam ~= nil
		and target:GetTeam() ~= bot:GetTeam()
		and IsValidCastTarget(target, true, true, {allowMagicImmune = allowMagicImmune == true})
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

local function TryRoamInitiation(bot, ability, initiation)
	if initiation == nil
		or initiation.abilityName ~= YUUKA02
		or initiation.castMode ~= 'entity'
		or initiation.status ~= 'pending'
		or not IsCastable(ability)
		or initiation.target == nil
	then
		return false
	end
	local target = initiation.target
	if not IsVisibleRealEnemy(bot, target) then return false end
	local castRange = initiation.castRange or ability:GetCastRange()
	if GetUnitToUnitDistance(bot, target) > castRange then return false end

	-- gank 先手必须锁定任务目标，不能让连续技或普通目标选择抢先消耗二技能。
	bot:Action_UseAbilityOnEntity(ability, target)
	RoamInitiation.MarkIssued(bot, YUUKA02, target)
	return true
end

local function IsStableHardControlled(target)
	if target:IsStunned() or target:IsHexed() then return true end
	if GetModifiersTimeLeft ~= nil then
		local ok, remaining = pcall(function() return GetModifiersTimeLeft(target, ModifierNamesStun) end)
		if ok and remaining ~= nil and remaining > 0.5 then return true end
	end
	return false
end

local function IsTeleportingSafely(target)
	if IsTeleporting == nil then return false end
	local ok, result = pcall(function() return IsTeleporting(target) end)
	return ok and result == true
end

local function IsEnemyTowerNearby(bot, range)
	if bot.GetNearbyTowers == nil then return false end
	local ok, towers = pcall(function() return bot:GetNearbyTowers(range, true) end)
	return ok and towers ~= nil and #towers > 0
end

local function IsLaningPressureWindow(bot)
	return J.IsInLaningPhase()
		and bot:GetActiveMode() == BOT_MODE_LANING
		and not J.IsRetreating(bot)
end

local function GetYuuka01Radius(ability)
	if ability == nil then return 0 end
	if ability.GetAOERadius ~= nil then
		local ok, radius = pcall(function() return ability:GetAOERadius() end)
		if ok and radius ~= nil and radius > 0 then return radius end
	end
	if ability.GetSpecialValueInt ~= nil then
		local ok, radius = pcall(function() return ability:GetSpecialValueInt("AOERadius") end)
		if ok and radius ~= nil and radius > 0 then return radius end
	end
	local radii = {125, 150, 175, 200}
	return radii[math.max(ability:GetLevel(), 1)] or 200
end

local function GetYuuka03Radius(ability)
	if ability ~= nil and ability.GetAOERadius ~= nil then
		local ok, radius = pcall(function() return ability:GetAOERadius() end)
		if ok and radius ~= nil and radius > 0 then return radius end
	end
	return 800
end

local function GetYuuka02Damage(bot, ability)
	local damage = ability:GetSpecialValueInt("damage")
	return damage * (1 + bot:GetSpellAmp())
end

local function FindEmergencyYuuka02Target(bot, ability)
	if not IsCastable(ability) then return nil end
	local castRange = ability:GetCastRange()
	local killTarget = nil
	for _, enemy in pairs(GetVisibleEnemies(bot, castRange)) do
		if not IsStableHardControlled(enemy) then
			if enemy:IsChanneling() or IsTeleportingSafely(enemy) then return enemy end
			if J.CanKillTarget(enemy, GetYuuka02Damage(bot, ability), DAMAGE_TYPE_MAGICAL)
			and (killTarget == nil or enemy:GetHealth() < killTarget:GetHealth())
			then
				killTarget = enemy
			end
		end
	end
	return killTarget
end

local function FindRetreatTarget(bot, ability, requireSerious)
	if not IsCastable(ability) or not J.IsRetreating(bot) then return nil end
	if requireSerious and not J.IsSeriouslyRetreating(bot, YUUKA_EX2) then return nil end
	local enemies = GetVisibleEnemies(bot, 1200, true)
	if UNIT_LIST_ENEMY_BUILDINGS ~= nil then
		for _, building in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS)) do
			if building ~= nil and building.IsNull ~= nil and not building:IsNull()
			and building.IsAlive ~= nil and building:IsAlive()
			and building.CanBeSeen ~= nil and building:CanBeSeen()
			and building.GetTeam ~= nil and building:GetTeam() ~= bot:GetTeam()
			then
				table.insert(enemies, building)
			end
		end
	end
	local fountain = GetShopLocation(bot:GetTeam(), SHOP_HOME)
	return YuukaUnits.GetBestRetreatTarget(
		bot,
		ability:GetCastRange(),
		bot:HasModifier(WANBAO_MODIFIER),
		fountain,
		enemies
	)
end

local function FindEmergencyRetreatTarget(bot, ability)
	return FindRetreatTarget(bot, ability, true)
end

local function FindCloseMeleePursuer(bot, ability)
	if not IsCastable(ability) or not J.IsRetreating(bot)
	or not bot:WasRecentlyDamagedByAnyHero(3.0)
	then
		return nil
	end
	local radius = GetYuuka01Radius(ability)
	for _, enemy in pairs(GetVisibleEnemies(bot, radius + 75, true)) do
		local attackRange = enemy.GetAttackRange ~= nil and enemy:GetAttackRange() or 150
		if attackRange <= 350 and GetUnitToUnitDistance(bot, enemy) <= radius + 75 then
			return enemy
		end
	end
	return nil
end

local function HasRetreatFollowup(bot)
	return bot.yuukaRetreatFollowup ~= nil
end

local function GetDirectedJumpItem()
	-- 牛逼跳跃会消耗完美跳跃，过渡期间仍保留旧装备作为回退。
	return IsItemAvailable("item_nb9ball") or IsItemAvailable("item_wanmeitiaoyuezhuangzhi")
end

local function TryStartRetreatRing(bot, ability01)
	if HasRetreatFollowup(bot) or FindCloseMeleePursuer(bot, ability01) == nil then return false end
	-- 贴身近战追击者先用花环阻断，下一步再选择可靠的位移手段脱离花圈。
	bot:Action_UseAbility(ability01)
	bot.yuukaRetreatFollowup = {
		readyAt = DotaTime() + 0.3,
		deadline = DotaTime() + 1.6,
	}
	return true
end

local function TryContinueRetreatFollowup(bot, abilityEx2)
	local state = bot.yuukaRetreatFollowup
	if state == nil then return false end
	if not J.IsRetreating(bot) or DotaTime() > state.deadline then
		bot.yuukaRetreatFollowup = nil
		return false
	end
	if DotaTime() < state.readyAt then return true end

	local retreatTarget = FindRetreatTarget(bot, abilityEx2, false)
	if retreatTarget ~= nil then
		bot:Action_UseAbilityOnLocation(abilityEx2, retreatTarget:GetLocation())
		bot.yuukaRetreatFollowup = nil
		return true
	end

	local directedJump = GetDirectedJumpItem()
	if directedJump ~= nil and directedJump:IsFullyCastable() then
		bot:Action_UseAbilityOnLocation(directedJump, GetShopLocation(bot:GetTeam(), SHOP_HOME))
		MarkItemAction(bot)
		bot.yuukaRetreatFollowup = nil
		return true
	end

	local randomJump = IsItemAvailable("item_9ball")
	if randomJump ~= nil and randomJump:IsFullyCastable() then
		bot:Action_UseAbility(randomJump)
		MarkItemAction(bot)
		bot.yuukaRetreatFollowup = nil
		return true
	end

	bot.yuukaRetreatFollowup = nil
	return false
end

local function CountNearbyEnemies(bot, range)
	return #GetVisibleEnemies(bot, range, true)
end

local function UseNoTargetItem(bot, itemName, desire)
	local item = IsItemAvailable(itemName)
	if item == nil or not item:IsFullyCastable() or desire <= BOT_ACTION_DESIRE_NONE then return false end
	bot:Action_UseAbility(item)
	MarkItemAction(bot)
	return true
end

local function ConsiderFlowerUmbrella(bot, profile)
	local enemyCount = CountNearbyEnemies(bot, 1000)
	if enemyCount >= 2 and (J.IsInTeamFight(bot, 1200) or J.IsGoingOnSomeone(bot)) then
		return BOT_ACTION_DESIRE_HIGH
	end
	if profile == BotProfile.DAMAGE and enemyCount >= 1 and J.IsGoingOnSomeone(bot)
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	then
		-- 输出定位主动开伞强化攻速和减甲，不必等到自身血量下降。
		return BOT_ACTION_DESIRE_HIGH
	end
	if enemyCount >= 1 and bot:WasRecentlyDamagedByAnyHero(2.5) and J.GetHP(bot) < 0.72 then
		return BOT_ACTION_DESIRE_MODERATE
	end
	return BOT_ACTION_DESIRE_NONE
end

local function ConsiderTrinity(bot, item, profile)
	local sharedDesire = ConsiderItemShield(item)
	if sharedDesire ~= nil and sharedDesire > BOT_ACTION_DESIRE_NONE then return sharedDesire end
	local enemyCount = CountNearbyEnemies(bot, 1200)
	if enemyCount >= 2 and J.IsInTeamFight(bot, 1200) then return BOT_ACTION_DESIRE_HIGH end
	if profile == BotProfile.DAMAGE and enemyCount >= 1 and J.IsGoingOnSomeone(bot)
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	then
		-- 输出定位接战前开启护盾与状态抗性，避免连段被控制打断。
		return BOT_ACTION_DESIRE_HIGH
	end
	if enemyCount >= 1 and bot:WasRecentlyDamagedByAnyHero(2.0) and J.GetHP(bot) < 0.75 then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end

local function TryUseActiveItems(bot, profile, abilityEx2)
	if J.CanNotUseAction(bot) or bot:IsMuted() then return false end

	local dragonStar = IsItemAvailable("item_dragon_star")
	if dragonStar ~= nil and dragonStar:IsFullyCastable() then
		local pressuredRetreat = J.IsSeriouslyRetreating(bot)
			and bot:WasRecentlyDamagedByAnyHero(2.5)
			and CountNearbyEnemies(bot, 1000) > 0
		local committedFight = J.IsGoingOnSomeone(bot)
			and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
			and CountNearbyEnemies(bot, 800) > 0
		if pressuredRetreat or committedFight then
			bot:Action_UseAbility(dragonStar)
			MarkItemAction(bot)
			return true
		end
	end

	local trinity = IsItemAvailable("item_trinity")
	if trinity ~= nil and trinity:IsFullyCastable()
	and UseNoTargetItem(bot, "item_trinity", ConsiderTrinity(bot, trinity, profile))
	then return true end

	if profile == BotProfile.FRONTLINE then
		local esdw = IsItemAvailable("item_esdw")
		if esdw ~= nil and esdw:IsFullyCastable()
		and UseNoTargetItem(bot, "item_esdw", ConsiderItemShield(esdw))
		then return true end
	end
	if UseNoTargetItem(bot, "item_flower_umbrella", ConsiderFlowerUmbrella(bot, profile)) then return true end

	local jump = GetDirectedJumpItem()
	if jump ~= nil and jump:IsFullyCastable() then
		local desire, location
		if jump:GetName() == "item_nb9ball" then
			-- 升级版按真实的999距离决策，避免仍按完美跳跃的500距离使用。
			desire, location = ConsiderItemJump(jump, 100, 600, 999)
		else
			desire, location = ConsiderItemJump(jump)
		end
		if desire ~= nil and desire > BOT_ACTION_DESIRE_NONE and location ~= nil then
			bot:Action_UseAbilityOnLocation(jump, location)
			MarkItemAction(bot)
			return true
		end
	end

	local randomJump = IsItemAvailable("item_9ball")
	if randomJump ~= nil and randomJump:IsFullyCastable()
	and (jump == nil or not jump:IsFullyCastable())
	and (abilityEx2 == nil or not abilityEx2:IsFullyCastable())
	and J.IsSeriouslyRetreating(bot)
	and J.GetHP(bot) < 0.25
	and bot:WasRecentlyDamagedByAnyHero(2.0)
	and CountNearbyEnemies(bot, 350) > 0
	then
		-- 随机跳跃无法指定方向，只在所有确定性位移均不可用的濒死窗口兜底。
		bot:Action_UseAbility(randomJump)
		MarkItemAction(bot)
		return true
	end
	return false
end

local function ConsiderYuuka02(bot, ability)
	if not IsCastable(ability) then return nil end
	local castRange = ability:GetCastRange()
	local enemies = GetVisibleEnemies(bot, castRange)
	local properTarget = J.GetProperTarget(bot)

	if J.IsRetreating(bot) and bot:WasRecentlyDamagedByAnyHero(3.0) then
		for _, enemy in pairs(enemies) do
			if not IsStableHardControlled(enemy) then return enemy end
		end
	end

	if J.IsInTeamFight(bot, 1200) then
		local best = nil
		for _, enemy in pairs(enemies) do
			if not IsStableHardControlled(enemy)
			and (best == nil or enemy:GetHealth() < best:GetHealth())
			then best = enemy end
		end
		if best ~= nil then return best end
	end

	if J.IsGoingOnSomeone(bot)
	and IsVisibleRealEnemy(bot, properTarget)
	and GetUnitToUnitDistance(bot, properTarget) <= castRange
	and not IsStableHardControlled(properTarget)
	and HasManaFor(bot, ability, 50)
	then
		return properTarget
	end

	if IsLaningPressureWindow(bot)
	and DotaTime() >= (bot.yuukaNextLaneHarassTime or -90)
	and HasManaFor(bot, ability, 65)
	and J.GetHP(bot) >= 0.55
	and not IsEnemyTowerNearby(bot, 750)
	then
		local best = nil
		for _, enemy in pairs(enemies) do
			if not IsStableHardControlled(enemy)
			and (best == nil or enemy:GetHealth() < best:GetHealth())
			then best = enemy end
		end
		if best ~= nil then return best end
	end
	return nil
end

local function HasEnemyInFlowerRing(bot, unit, radius)
	if unit == nil then return nil end
	for _, enemy in pairs(CachedGetNearbyHeroes(unit, radius, true, BOT_MODE_NONE)) do
		if IsVisibleRealEnemy(bot, enemy, true) and GetUnitToUnitDistance(unit, enemy) <= radius then
			return enemy
		end
	end
	return nil
end

local function ConsiderYuuka01(bot, ability, profile)
	if not IsCastable(ability) then return false end
	local radius = GetYuuka01Radius(ability)
	local target = HasEnemyInFlowerRing(bot, bot, radius)
	if target == nil then
		target = HasEnemyInFlowerRing(bot, YuukaUnits.GetIllusion(bot), radius)
	end
	if target == nil then return false end

	if J.IsRetreating(bot) and bot:WasRecentlyDamagedByAnyHero(3.0) then return true end
	if J.IsGoingOnSomeone(bot) and HasManaFor(bot, ability, 50) then return true end
	if profile == BotProfile.DAMAGE and J.IsInTeamFight(bot, 1200) and HasManaFor(bot, ability, 50) then
		return true
	end
	if IsLaningPressureWindow(bot)
	and DotaTime() >= (bot.yuukaNextLaneHarassTime or -90)
	and HasManaFor(bot, ability, 65)
	and J.GetHP(bot) >= 0.6
	and not IsEnemyTowerNearby(bot, 650)
	then
		return true
	end
	return false
end

local function ConsiderYuuka03(bot, ability, profile)
	if not IsCastable(ability) or not HasManaFor(bot, ability, 50) then return nil end
	local location, score = YuukaUnits.GetBestGardenLocation(bot, ability:GetCastRange(), GetYuuka03Radius(ability))
	if location == nil then return nil end

	if J.IsInTeamFight(bot, 1200) and score >= 4 then return location end
	if J.IsGoingOnSomeone(bot) and score >= (profile == BotProfile.FRONTLINE and 3 or 4) then return location end
	if (J.IsPushing(bot) or J.IsDefending(bot)) and score >= 4 then return location end
	if J.GetHP(bot) < 0.55 and score >= 3 and CountNearbyEnemies(bot, 1000) > 0 then return location end
	if IsLaningPressureWindow(bot) and score >= 4 and HasManaFor(bot, ability, 100) then return location end
	return nil
end

local function GetUltimateFocus(bot)
	local properTarget = J.GetProperTarget(bot)
	if IsVisibleRealEnemy(bot, properTarget) and GetUnitToUnitDistance(bot, properTarget) <= 1200 then
		return properTarget
	end
	local best = nil
	for _, enemy in pairs(GetVisibleEnemies(bot, 1200, true)) do
		if best == nil or enemy:GetHealth() < best:GetHealth() then best = enemy end
	end
	return best
end

local function ConsiderYuuka04(bot, ability, abilityEx, profile)
	if not IsCastable(ability) or J.IsRetreating(bot) or YuukaUnits.GetIllusion(bot) ~= nil then return nil, nil end
	if not HasManaFor(bot, ability, 50) then return nil, nil end

	local enemies = GetVisibleEnemies(bot, 1200, true)
	local focus = GetUltimateFocus(bot)
	local teamFight = #enemies >= 2 or J.IsInTeamFight(bot, 1200)
	local engage = focus ~= nil and J.IsGoingOnSomeone(bot) and J.WeAreStronger(bot, 1200)
	local pushing = J.IsPushing(bot)
	if profile == BotProfile.DAMAGE then
		engage = engage and focus:GetHealth() <= focus:GetMaxHealth() * 0.7
	end
	if not teamFight and not engage and not pushing then return nil, nil end

	local flower = YuukaUnits.GetBestUltimateFlower(bot, ability:GetCastRange(), focus)
	if flower ~= nil and (focus == nil or GetUnitToUnitDistance(flower, focus) <= 1000) then
		return "cast", flower
	end

	local currentCount = YuukaUnits.GetFlowerCount(bot)
	local maxCount = YuukaUnits.GetMaxFlowerCount(bot, abilityEx)
	if IsCastable(abilityEx) and currentCount < maxCount and HasManaFor(bot, abilityEx, 50) then
		-- 明确的大招窗口没有合法花朵时，先在当前朝向补种，下一 Think 再选择新花。
		if focus ~= nil and not bot:IsFacingLocation(focus:GetLocation(), 20) then
			return "face", focus:GetLocation()
		end
		return "plant", abilityEx
	end
	return nil, nil
end

local function ConsiderYuukaEx2Engage(bot, ability)
	if not IsCastable(ability) or J.IsRetreating(bot) or not HasManaFor(bot, ability, 0) then return nil end
	local target = J.GetProperTarget(bot)
	local castRange = ability:GetCastRange()
	if not J.IsGoingOnSomeone(bot)
	or not IsVisibleRealEnemy(bot, target)
	or GetUnitToUnitDistance(bot, target) > castRange
	or IsEnemyTowerNearby(bot, 750)
	then
		return nil
	end

	local committed = target:IsStunned() or target:IsHexed()
		or target:GetHealth() <= target:GetMaxHealth() * 0.3
		or J.WeAreStronger(bot, 1000)
	if not committed then return nil end
	if bot:HasModifier(WANBAO_MODIFIER) then return target end

	local flower, targetDistance = YuukaUnits.GetNearestFlowerTo(bot, target, castRange)
	if flower ~= nil and targetDistance <= 350
	and GetUnitToUnitDistance(bot, target) >= targetDistance + 200
	then
		return flower
	end
	return nil
end

local function ConsiderYuukaExPlant(bot, ability, profile)
	if not IsCastable(ability) or J.IsRetreating(bot) then return false, nil end
	local illusion = YuukaUnits.GetIllusion(bot)
	local currentCount = YuukaUnits.GetFlowerCount(bot)
	local maxCount = YuukaUnits.GetMaxFlowerCount(bot, ability)
	local newFlowers = illusion ~= nil and 2 or 1
	if currentCount + newFlowers > maxCount then return false, nil end
	if DotaTime() < (bot.yuukaNextPlantingTime or -90) then return false, nil end
	if not HasManaFor(bot, ability, profile == BotProfile.DAMAGE and 100 or 50) then return false, nil end
	if CountNearbyEnemies(bot, 900) > 0 and bot:WasRecentlyDamagedByAnyHero(3.0) then return false, nil end
	if YuukaUnits.CountFlowersNearLocation(bot, bot:GetLocation(), 550, true) >= 2 then return false, nil end

	local target = J.GetProperTarget(bot)
	local faceLocation = nil
	if IsVisibleRealEnemy(bot, target, true) and GetUnitToUnitDistance(bot, target) <= 1600 then
		faceLocation = target:GetLocation()
	end
	return true, faceLocation
end

function MyItemUsageThink()
	local bot = GetBot()
	if not IsBotAwake() or J.CanNotUseAction(bot) or WasItemActionJustIssued(bot) then return false end
	if YuukaCombo.IsActive(bot) or YuukaCombo.CanBegin(bot)
	or YuukaCombo.CanBeginLanePressure(bot) or HasRetreatFollowup(bot)
	then return false end
	local ability02 = GetAbility(bot, YUUKA02)
	local ability01 = GetAbility(bot, YUUKA01)
	local abilityEx2 = GetAbility(bot, YUUKA_EX2)
	if not bot:IsSilenced() then
		if FindCloseMeleePursuer(bot, ability01) ~= nil then return false end
		if FindEmergencyRetreatTarget(bot, abilityEx2) ~= nil then return false end
		if FindEmergencyYuuka02Target(bot, ability02) ~= nil then return false end
		if IsLaningPressureWindow(bot) and ConsiderYuuka01(bot, ability01, GetProfile(bot)) then return false end
	end
	return TryUseActiveItems(bot, GetProfile(bot), abilityEx2)
end

function AbilityUsageThink()
	if not IsBotAwake() then return end
	local bot = GetBot()
	if J.CanNotUseAction(bot) or WasItemActionJustIssued(bot) then return end

	local profile = GetProfile(bot)
	local ability01 = GetAbility(bot, YUUKA01)
	local ability02 = GetAbility(bot, YUUKA02)
	local ability03 = GetAbility(bot, YUUKA03)
	local ability04 = GetAbility(bot, YUUKA04)
	local abilityEx = GetAbility(bot, YUUKA_EX)
	local abilityEx2 = GetAbility(bot, YUUKA_EX2)

	local initiation = RoamInitiation.GetIntent(bot)
	if initiation ~= nil then
		if TryRoamInitiation(bot, ability02, initiation) then return end
		if RoamInitiation.ShouldHoldGenericAction(bot) then return end
	end

	if not bot:IsSilenced() then
		if TryContinueRetreatFollowup(bot, abilityEx2) then return end
		if TryStartRetreatRing(bot, ability01) then return end

		local retreatTarget = FindEmergencyRetreatTarget(bot, abilityEx2)
		if retreatTarget ~= nil then
			bot:Action_UseAbilityOnLocation(abilityEx2, retreatTarget:GetLocation())
			return
		end

		-- 连段开始后只有撤退可以中止，打断、装备与常规技能都不能改变既定顺序。
		if YuukaCombo.IsActive(bot) and YuukaCombo.Think(bot) then return end

		local emergencyTarget = FindEmergencyYuuka02Target(bot, ability02)
		if emergencyTarget ~= nil then
			bot:Action_UseAbilityOnEntity(ability02, emergencyTarget)
			return
		end
	end

	if YuukaCombo.Think(bot) then return end
	if IsLaningPressureWindow(bot) and ConsiderYuuka01(bot, ability01, profile) then
		-- 敌人已经贴身时直接用花圈压制，避免先放二技能触发共享节流。
		bot:Action_UseAbility(ability01)
		bot.yuukaNextLaneHarassTime = DotaTime() + 7
		return
	end
	if YuukaCombo.BeginLanePressure(bot) and YuukaCombo.Think(bot) then return end
	if YuukaCombo.Begin(bot) and YuukaCombo.Think(bot) then return end

	if TryUseActiveItems(bot, profile, abilityEx2) then return end
	if bot:IsSilenced() then
		ConsiderNeutralItems()
		return
	end

	local ultimateAction, ultimateTarget = ConsiderYuuka04(bot, ability04, abilityEx, profile)
	if ultimateAction == "cast" then
		bot:Action_UseAbilityOnLocation(ability04, ultimateTarget:GetLocation())
		YuukaUnits.Invalidate(bot)
		return
	elseif ultimateAction == "plant" then
		bot:Action_UseAbility(abilityEx)
		bot.yuukaNextPlantingTime = DotaTime() + 2.5
		YuukaUnits.Invalidate(bot)
		return
	elseif ultimateAction == "face" then
		bot:Action_MoveToLocation(ultimateTarget)
		return
	end

	local engageTarget = ConsiderYuukaEx2Engage(bot, abilityEx2)
	if engageTarget ~= nil then
		bot:Action_UseAbilityOnLocation(abilityEx2, engageTarget:GetLocation())
		return
	end

	local yuuka02Target = ConsiderYuuka02(bot, ability02)
	if yuuka02Target ~= nil then
		bot:Action_UseAbilityOnEntity(ability02, yuuka02Target)
		if IsLaningPressureWindow(bot) then bot.yuukaNextLaneHarassTime = DotaTime() + 6 end
		return
	end

	if ConsiderYuuka01(bot, ability01, profile) then
		bot:Action_UseAbility(ability01)
		if IsLaningPressureWindow(bot) then bot.yuukaNextLaneHarassTime = DotaTime() + 7 end
		return
	end

	local gardenLocation = ConsiderYuuka03(bot, ability03, profile)
	if gardenLocation ~= nil then
		bot:Action_UseAbilityOnLocation(ability03, gardenLocation)
		return
	end

	local shouldPlant, faceLocation = ConsiderYuukaExPlant(bot, abilityEx, profile)
	if shouldPlant then
		if faceLocation ~= nil and not bot:IsFacingLocation(faceLocation, 20) then
			bot:Action_MoveToLocation(faceLocation)
			return
		end
		bot:Action_UseAbility(abilityEx)
		bot.yuukaNextPlantingTime = DotaTime() + (profile == BotProfile.FRONTLINE and 2.5 or 3.5)
		YuukaUnits.Invalidate(bot)
		return
	end

	-- 中立装备固定在本轮末尾，不能覆盖撤退、打断、主动物品或花阵技能。
	ConsiderNeutralItems()
end

----------------------------------------------------------------------------------------------------
