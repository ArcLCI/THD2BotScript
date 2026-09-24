local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local BotProfile = require(GetScriptDirectory() .. "/THDFuncLib/bot_profile")
local SunnyUltimate = require(GetScriptDirectory() .. "/THDFuncLib/sunny_ultimate")
local RoamInitiation = require(GetScriptDirectory() .. "/THDFuncLib/roam_initiation")

local SUNNY01 = "ability_thdots_sunny01"
local SUNNY02 = "ability_thdots_sunny02"
local SUNNY03 = "ability_thdots_sunny03"
local SUNNY04 = "ability_thdots_sunny04"
local SUNNY05 = "ability_thdots_sunny05"
local SUNNY01_MODIFIER = "modifier_ability_thdots_sunny01"
local ACTION_GUARD_TIME = 0.05

local function MarkAction(bot)
	bot.sunnyLastActionTime = DotaTime()
end

local function WasActionJustIssued(bot)
	return DotaTime() - (bot.sunnyLastActionTime or -90) <= ACTION_GUARD_TIME
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

local function IsVisibleRealEnemy(bot, target)
	return target ~= nil
		and not target:IsNull()
		and target:CanBeSeen()
		and target:IsAlive()
		and target:IsHero()
		and target:GetTeam() ~= bot:GetTeam()
		and not target:IsInvulnerable()
		and not target:IsMagicImmune()
		and not J.IsSuspiciousIllusion(target)
end

local function GetAbilityRadius(ability)
	if ability == nil then return 0 end
	local radius = ability:GetSpecialValueInt("radius")
	if radius == nil or radius <= 0 then radius = ability:GetCastRange() end
	return math.max(radius or 0, 0)
end

local function IsLaningPressureWindow(bot)
	return J.IsInLaningPhase()
		and bot:GetActiveMode() == BOT_MODE_LANING
		and not J.IsRetreating(bot)
end

local function FindLaningHarassTarget(bot, range)
	if not IsLaningPressureWindow(bot) then return nil end
	local properTarget = J.GetProperTarget(bot)
	local bestTarget = nil
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, range, true, BOT_MODE_NONE)) do
		if IsVisibleRealEnemy(bot, enemy) then
			if enemy == properTarget then return enemy end
			if bestTarget == nil or enemy:GetHealth() < bestTarget:GetHealth() then
				bestTarget = enemy
			end
		end
	end
	return bestTarget
end

local function ShouldPreserveRetreatInvisibility(bot)
	return J.IsRetreating(bot) and bot:HasModifier(SUNNY01_MODIFIER)
end

local function ConsiderSunnyNeutralItems(bot)
	if ShouldPreserveRetreatInvisibility(bot) then
		-- 撤退隐身是当前最高价值的保命状态；中立主动装备会触发施法事件并使隐身提前结束。
		return
	end
	ConsiderNeutralItems()
end

local function IsStableHardControlled(target)
	return target:IsStunned()
		or target:IsHexed()
		or GetModifiersTimeLeft(target, ModifierNamesStun) > 0.5
end

local function FindEmergencySunny02Target(bot, ability)
	if not IsCastable(ability) then return nil end
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, GetAbilityRadius(ability), true, BOT_MODE_NONE)) do
		if IsVisibleRealEnemy(bot, enemy)
		and not IsStableHardControlled(enemy)
		and (enemy:IsChanneling() or IsTeleporting(enemy))
		then
			return enemy
		end
	end
	return nil
end

local function UseTargetItem(bot, itemName, consider)
	local item = IsItemAvailable(itemName)
	if item == nil or not item:IsFullyCastable() then return false end
	local desire, target = consider(item)
	if desire ~= nil and desire > BOT_ACTION_DESIRE_NONE and target ~= nil then
		bot:Action_UseAbilityOnEntity(item, target)
		MarkAction(bot)
		return true
	end
	return false
end

local function UseNoTargetItem(bot, itemName, consider)
	local item = IsItemAvailable(itemName)
	if item == nil or not item:IsFullyCastable() then return false end
	local desire = consider(item)
	if desire ~= nil and desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(item)
		MarkAction(bot)
		return true
	end
	return false
end

local function ConsiderFlowerUmbrella(bot, item)
	if not item:IsFullyCastable() then return BOT_ACTION_DESIRE_NONE end
	local enemies = CachedGetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
	local allies = CachedGetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE)
	if #enemies >= 2 and (#allies >= 2 or J.IsInTeamFight(bot, 1200)) then
		return BOT_ACTION_DESIRE_HIGH
	end
	if #enemies >= 1 and bot:WasRecentlyDamagedByAnyHero(2.5) and #allies >= 1 then
		return BOT_ACTION_DESIRE_MODERATE
	end
	return BOT_ACTION_DESIRE_NONE
end

local function ConsiderTrinity(bot, item)
	if not item:IsFullyCastable() then return BOT_ACTION_DESIRE_NONE end
	local sharedDesire = ConsiderItemShield(item)
	if sharedDesire ~= nil and sharedDesire > BOT_ACTION_DESIRE_NONE then
		return sharedDesire
	end

	local enemies = CachedGetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
	if #enemies >= 2 and J.IsInTeamFight(bot, 1200) then
		-- 三位一体只有 6 秒持续时间；团战已经形成时预开，利用护盾和状态抗性覆盖第一轮控制。
		return BOT_ACTION_DESIRE_HIGH
	end
	if #enemies >= 1
	and bot:WasRecentlyDamagedByAnyHero(2.0)
	and J.GetHP(bot) < 0.75
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end

local function TryUseActiveItems(bot, profile)
	if J.CanNotUseAction(bot) or bot:IsMuted() then return false end

	if profile == BotProfile.SUPPORT then
		if UseTargetItem(bot, "item_tuzhushen", ConsiderItemQiJiZhiXing) then return true end
		if UseTargetItem(bot, "item_qijizhixing", ConsiderItemQiJiZhiXing) then return true end
		if UseTargetItem(bot, "item_yukkuri_stick", ConsiderItemYukkuriStick) then return true end
	end

	if UseTargetItem(bot, "item_third_eyes", ConsiderItemXinYan) then return true end

	if profile == BotProfile.SUPPORT then
		if UseNoTargetItem(bot, "item_trinity", function(item)
			return ConsiderTrinity(bot, item)
		end) then return true end
		if UseNoTargetItem(bot, "item_esdw", ConsiderItemShield) then return true end
		if UseNoTargetItem(bot, "item_flower_umbrella", function(item)
			return ConsiderFlowerUmbrella(bot, item)
		end) then return true end
	end
	return false
end

function MyItemUsageThink()
	local bot = GetBot()
	if not IsBotAwake() or J.CanNotUseAction(bot) or SunnyUltimate.IsActive(bot) then return false end
	-- 二技能紧急打断必须先于所有主动物品；此处让 AbilityUsageThink 获得本轮动作权。
	if not bot:IsSilenced() and FindEmergencySunny02Target(bot, GetAbility(bot, SUNNY02)) ~= nil then return false end
	return TryUseActiveItems(bot, GetProfile(bot))
end

local function ConsiderSunny01(bot, ability, ability02)
	if not IsCastable(ability) or bot:HasModifier(SUNNY01_MODIFIER) then return false end
	local enemies = CachedGetNearbyHeroes(bot, 900, true, BOT_MODE_NONE)
	if J.IsSeriouslyRetreating(bot)
	and #enemies > 0
	and (bot:WasRecentlyDamagedByAnyHero(3.0) or J.GetHP(bot) < 0.42)
	then
		return true
	end

	local target = J.GetProperTarget(bot)
	local isLaningPressure = false
	if not J.IsGoingOnSomeone(bot) or not IsVisibleRealEnemy(bot, target) then
		target = FindLaningHarassTarget(bot, 900)
		isLaningPressure = target ~= nil
		if not isLaningPressure
		or ability02 == nil
		or (not ability02:IsFullyCastable() and ability02:GetCooldownTimeRemaining() > 3.0)
		then
			return false
		end
	end
	local distance = GetUnitToUnitDistance(bot, target)
	local stunRadius = GetAbilityRadius(ability02)
	if distance <= stunRadius + 75 or distance > 900 or J.GetHP(bot) < 0.55 then return false end
	if #bot:GetNearbyTowers(800, true) > 0 then return false end
	return isLaningPressure or J.WeAreStronger(bot, 900)
end

local function GetSunny02Damage(bot, ability)
	local damage = ability:GetSpecialValueInt("damage")
	local intBonus = ability:GetSpecialValueFloat("int_bonus")
	return (damage + bot:GetAttributeValue(ATTRIBUTE_INTELLECT) * intBonus) * (1 + bot:GetSpellAmp())
end

local function ConsiderSunny02(bot, ability)
	if not IsCastable(ability) then return false end
	local enemies = CachedGetNearbyHeroes(bot, GetAbilityRadius(ability), true, BOT_MODE_NONE)
	local validEnemies = {}
	for _, enemy in pairs(enemies) do
		if IsVisibleRealEnemy(bot, enemy) and not IsStableHardControlled(enemy) then
			table.insert(validEnemies, enemy)
			if J.CanKillTarget(enemy, GetSunny02Damage(bot, ability), DAMAGE_TYPE_MAGICAL) then
				return true
			end
		end
	end
	if #validEnemies == 0 then return false end

	if J.IsRetreating(bot)
	and bot:WasRecentlyDamagedByAnyHero(3.0)
	then
		return true
	end
	if IsLaningPressureWindow(bot)
	and J.GetHP(bot) >= 0.45
	and #bot:GetNearbyTowers(750, true) == 0
	then
		-- 桑尼技能无蓝耗，敌人进入实际半径后直接用二技能换血并制造补刀压力。
		return true
	end
	if #validEnemies >= 2 and J.IsInTeamFight(bot, 1200) then return true end
	local target = J.GetProperTarget(bot)
	return J.IsGoingOnSomeone(bot) and IsVisibleRealEnemy(bot, target)
		and GetUnitToUnitDistance(bot, target) <= GetAbilityRadius(ability)
end

local function ShouldPreserveInvisibility(bot, ability02)
	return bot:HasModifier(SUNNY01_MODIFIER)
		and ability02 ~= nil
		and (ability02:IsFullyCastable() or ability02:GetCooldownTimeRemaining() <= 3.0)
		and #bot:GetNearbyTowers(800, true) == 0
end

local function GetSunny03Damage(bot, ability)
	local damage = ability:GetSpecialValueInt("damage")
	local intBonus = ability:GetSpecialValueFloat("int_bonus")
	return (damage + bot:GetAttributeValue(ATTRIBUTE_INTELLECT) * intBonus) * (1 + bot:GetSpellAmp())
end

local function ConsiderSunny03(bot, ability, ability02, profile)
	if not IsCastable(ability) or ShouldPreserveInvisibility(bot, ability02) then return nil end
	local castRange = ability:GetCastRange()
	local enemies = CachedGetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
	local properTarget = J.GetProperTarget(bot)
	local bestKill = nil
	local currentTarget = nil
	local bestPressure = nil
	local bestLanePressure = nil
	for _, enemy in pairs(enemies) do
		if IsVisibleRealEnemy(bot, enemy) and GetUnitToUnitDistance(bot, enemy) <= castRange then
			if J.CanKillTarget(enemy, GetSunny03Damage(bot, ability), DAMAGE_TYPE_MAGICAL) then
				if bestKill == nil or enemy:GetHealth() < bestKill:GetHealth() then bestKill = enemy end
			elseif enemy == properTarget and J.IsGoingOnSomeone(bot) then
				currentTarget = enemy
			elseif IsLaningPressureWindow(bot)
			and J.GetHP(bot) >= 0.35
			and (bestLanePressure == nil or enemy:GetHealth() < bestLanePressure:GetHealth())
			then
				-- 对线期不受蓝量约束，优先用三技能持续压低血量并施加减疗。
				bestLanePressure = enemy
			elseif profile == BotProfile.SUPPORT
			and (J.IsInTeamFight(bot, 1200) or enemy:GetHealth() < enemy:GetMaxHealth() * 0.85)
			and (bestPressure == nil or enemy:GetHealth() < bestPressure:GetHealth())
			then
				bestPressure = enemy
			end
		end
	end
	return bestKill or currentTarget or bestLanePressure or bestPressure
end

local function HasAlliedSupport(bot, target)
	for _, ally in pairs(CachedGetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)) do
		if ally ~= bot
		and ally:IsAlive()
		and not ally:IsIllusion()
		and GetUnitToUnitDistance(ally, target) <= 900
		then
			return true
		end
	end
	return false
end

local function ConsiderSunny04(bot, ability, profile)
	if not IsCastable(ability) or J.IsRetreating(bot) then return nil, nil end
	local enemies = CachedGetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
	local properTarget = J.GetProperTarget(bot)
	local valid = {}
	for _, enemy in pairs(enemies) do
		if IsVisibleRealEnemy(bot, enemy) then table.insert(valid, enemy) end
	end
	if #valid == 0 then return nil, nil end

	local target = nil
	if IsVisibleRealEnemy(bot, properTarget) and GetUnitToUnitDistance(bot, properTarget) <= 1200 then
		target = properTarget
	else
		table.sort(valid, function(a, b) return a:GetHealth() < b:GetHealth() end)
		target = valid[1]
	end

	if profile == BotProfile.SUPPORT then
		local count = math.max(ability:GetSpecialValueInt("base_count"), 1)
		local constant = math.max(ability:GetSpecialValueInt("constant"), 1)
		count = count + math.floor(bot:GetMaxHealth() / constant)
		local damage = ability:GetSpecialValueInt("damage") * count
		local killWindow = J.CanKillTarget(target, damage * (1 + bot:GetSpellAmp()), DAMAGE_TYPE_MAGICAL)
		local alliedSupport = HasAlliedSupport(bot, target)
		local teamFight = #valid >= 2 and (J.IsInTeamFight(bot, 1200) or alliedSupport)
		if not teamFight and not alliedSupport and not killWindow then return nil, nil end
	else
		if #valid < 2 and not (J.IsGoingOnSomeone(bot) and target == properTarget and J.WeAreStronger(bot, 1200)) then
			return nil, nil
		end
	end
	return target, #valid >= 2 and "teamfight" or "engage"
end

local function ConsiderSunny05(bot, ability, profile)
	if ability == nil or ability:IsHidden() or not ability:IsFullyCastable() then return nil end
	if bot:HasModifier("modifier_fountain_aura_buff") or bot:HasModifier("modifier_fountain_invulnerability") then
		return nil
	end
	if J.IsRetreating(bot) then return nil end

	if profile == BotProfile.FRONTLINE then
		-- 前排路线在万宝槌解锁后常态复制自己，让幻象持续携带火凤凰之翼的灼烧。
		return bot
	end

	local enemies = CachedGetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
	local bestAlly = nil
	local castRange = ability:GetCastRange()
	if #enemies > 0 then
		for _, ally in pairs(CachedGetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)) do
			if ally ~= bot
			and ally:IsAlive()
			and not ally:IsIllusion()
			and ally:GetHealth() >= ally:GetMaxHealth() * 0.30
			and ally:WasRecentlyDamagedByAnyHero(3.0)
			and (bestAlly == nil or ally:GetHealth() > bestAlly:GetHealth())
			then
				bestAlly = ally
			end
		end
	end
	if bestAlly ~= nil then return bestAlly end
	if J.IsInTeamFight(bot, 1200) or J.IsPushing(bot) then return bot end
	return nil
end

function AbilityUsageThink()
	if not IsBotAwake() then return end
	local bot = GetBot()
	if SunnyUltimate.IsActive(bot) or J.CanNotUseAction(bot) or WasActionJustIssued(bot) then return end

	local profile = GetProfile(bot)
	local ability01 = GetAbility(bot, SUNNY01)
	local ability02 = GetAbility(bot, SUNNY02)
	local ability03 = GetAbility(bot, SUNNY03)
	local ability04 = GetAbility(bot, SUNNY04)
	local ability05 = bot:GetAbilityByName(SUNNY05)

	-- 无目标范围控制以任务目标为距离锚点，进入效果半径后才交给技能接管。
	local initiation = RoamInitiation.GetIntent(bot)
	if initiation ~= nil then
		local target = initiation.target
		local castRange = initiation.castRange or GetAbilityRadius(ability02)
		if initiation.abilityName == SUNNY02
			and initiation.castMode == 'no_target'
			and initiation.status == 'pending'
			and IsCastable(ability02)
			and IsVisibleRealEnemy(bot, target)
			and GetUnitToUnitDistance(bot, target) <= castRange
		then
			bot:Action_UseAbility(ability02)
			RoamInitiation.MarkIssued(bot, ability02:GetName(), target)
			return
		end
		if RoamInitiation.ShouldHoldGenericAction(bot) then return end
	end

	if not bot:IsSilenced() and FindEmergencySunny02Target(bot, ability02) ~= nil then
		bot:Action_UseAbility(ability02)
		return
	end
	if TryUseActiveItems(bot, profile) then return end
	if bot:IsSilenced() then
		ConsiderSunnyNeutralItems(bot)
		return
	end

	local ultimateTarget, reason = ConsiderSunny04(bot, ability04, profile)
	if ultimateTarget ~= nil then
		if not bot:IsFacingLocation(ultimateTarget:GetLocation(), 18) then
			Actions.Move(bot, ultimateTarget:GetLocation(),10)
			return
		end
		SunnyUltimate.BeginCast(bot, ultimateTarget, reason)
		bot:Action_UseAbility(ability04)
		return
	end

	if ConsiderSunny02(bot, ability02) then
		bot:Action_UseAbility(ability02)
		return
	end

	local sunny03Target = ConsiderSunny03(bot, ability03, ability02, profile)
	if sunny03Target ~= nil then
		bot:Action_UseAbilityOnEntity(ability03, sunny03Target)
		return
	end

	if ConsiderSunny01(bot, ability01, ability02) then
		bot:Action_UseAbility(ability01)
		return
	end

	local sunny05Target = ConsiderSunny05(bot, ability05, profile)
	if sunny05Target ~= nil then
		bot:Action_UseAbilityOnEntity(ability05, sunny05Target)
		return
	end

	-- 中立装备固定在本轮末尾，避免它覆盖更高优先级的救人、打断或技能动作。
	ConsiderSunnyNeutralItems(bot)
end

----------------------------------------------------------------------------------------------------
