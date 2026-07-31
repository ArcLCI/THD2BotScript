require(GetScriptDirectory() .. "/thd2_item_usage")
local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local FlandreUltimate = require(GetScriptDirectory() .. "/THDFuncLib/flandre_ultimate")

local MIRROR_ABILITY = "naga_siren_mirror_image"
local ULTIMATE_ABILITY = "ability_thdots_flandre04"
local MIRROR_COMBAT_RANGE = 900
local MIRROR_RETREAT_RANGE = 800
local ULTIMATE_ILLUSION_RANGE = 3000
local MIN_ULTIMATE_ILLUSIONS = 2
local MIRROR_SETUP_TIME = 1.5
local DODGEABLE_CONTROL_RANGE = 700
local UNDODGEABLE_CONTROL_RANGE = 320
local LOW_HP_PROJECTILE_DODGE_RATIO = 0.18
local DODGEABLE_DAMAGE_RANGE = 520
local UNDODGEABLE_DAMAGE_RANGE = 260

-- 当前地图中已确认会产生追踪弹道的控制；同时保留常见原版点控名用于兼容。
local TRACKING_CONTROL_ABILITIES = {
	ability_thdots_daiyousei02 = true, -- 根缚
	ability_thdots_kasen02 = true, -- 眩晕
	ability_thdots_minoriko01 = true, -- 眩晕
	ability_thdots_sumireko02 = true, -- 眩晕与击退
	ability_thdots_medicine01 = true, -- 已有Medicine效果时眩晕
	ability_thdots_wriggle03 = true, -- 沉默
	item_tentacle = true, -- 根缚
	vengefulspirit_magic_missile = true,
	sven_storm_bolt = true,
	chaos_knight_chaos_bolt = true,
	skeleton_king_hellfire_blast = true,
	wraith_king_wraithfire_blast = true,
	naga_siren_ensnare = true,
	witch_doctor_paralyzing_cask = true,
	oracle_fortunes_end = true,
	item_rod_of_atos = true,
	item_gungir = true,
}

local CONTROL_DURATION_SPECIALS = {
	"stun_duration",
	"stun_time",
	"root_duration",
	"ensnare_duration",
	"silence_duration",
	"SilenceDuration",
}

local lastMirrorCastTime = -100

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
		and not J.IsSuspiciousIllusion(unit)
		and J.CanBeAttacked(unit)
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

local function GetProperEnemyHero(bot)
	local target = J.GetProperTarget(bot)
	if IsValidEnemyHero(target) then return target end
	return nil
end

local function GetPlayerID(unit)
	if unit == nil then return -1 end
	if unit.GetPlayerID ~= nil then
		local ok, id = pcall(function() return unit:GetPlayerID() end)
		if ok and id ~= nil then return id end
	end
	if unit.GetPlayerOwnerID ~= nil then
		local ok, id = pcall(function() return unit:GetPlayerOwnerID() end)
		if ok and id ~= nil then return id end
	end
	return -1
end

local function GetOwnedIllusions(bot, radius)
	local illusions = {}
	local playerID = GetPlayerID(bot)
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES)) do
		local unitPlayerID = GetPlayerID(unit)
		local sameOwner = unitPlayerID == playerID
		if unitPlayerID < 0 or playerID < 0 then
			sameOwner = unit:GetUnitName() == bot:GetUnitName()
		end
		if IsValidVisibleUnit(unit)
		and unit:IsIllusion()
		and sameOwner
		and GetUnitToUnitDistance(bot, unit) <= radius
		then
			table.insert(illusions, unit)
		end
	end
	return illusions
end

local function GetExpectedUltimateAttackCount(bot, ability)
	local baseCount = 1
	if ability ~= nil and ability.GetSpecialValueInt ~= nil then
		local ok, value = pcall(function() return ability:GetSpecialValueInt("attack_count") end)
		if ok and value ~= nil and value > 0 then baseCount = value end
	end
	return baseCount + #GetOwnedIllusions(bot, ULTIMATE_ILLUSION_RANGE)
end

local function IsTeleporting(enemy)
	return enemy:HasModifier("modifier_teleporting")
		or enemy:HasModifier("modifier_teleporting_root_logic")
end

local function GetAbilityName(ability)
	if ability == nil then return nil end
	if ability.GetName ~= nil then
		local ok, name = pcall(function() return ability:GetName() end)
		if ok and name ~= nil then return name end
	end
	if ability.GetAbilityName ~= nil then
		local ok, name = pcall(function() return ability:GetAbilityName() end)
		if ok and name ~= nil then return name end
	end
	return nil
end

local function IsTrackingControlAbility(ability)
	local abilityName = GetAbilityName(ability)
	if abilityName ~= nil and TRACKING_CONTROL_ABILITIES[abilityName] then return true end
	if ability == nil or ability.GetSpecialValueFloat == nil then return false end
	for _, specialName in pairs(CONTROL_DURATION_SPECIALS) do
		local ok, duration = pcall(function() return ability:GetSpecialValueFloat(specialName) end)
		if ok and duration ~= nil and duration > 0.2 then return true end
	end
	return false
end

local function IsEnemyProjectileCaster(bot, caster)
	if caster == nil then return false end
	if caster.IsNull ~= nil and caster:IsNull() then return false end
	return caster:GetTeam() ~= bot:GetTeam()
end

local function HasIncomingTrackingThreat(bot)
	if bot.GetIncomingTrackingProjectiles == nil then return false end
	local ok, projectiles = pcall(function() return bot:GetIncomingTrackingProjectiles() end)
	if not ok or projectiles == nil then return false end

	for _, projectile in pairs(projectiles) do
		if not projectile.is_attack
		and projectile.ability ~= nil
		and IsEnemyProjectileCaster(bot, projectile.caster)
		and projectile.location ~= nil
		then
			local isControl = IsTrackingControlAbility(projectile.ability)
			-- 极低生命时也躲避纯伤害技能弹道；普通攻击弹道不消耗镜像。
			local isLethalDamageRisk = J.GetHP(bot) <= LOW_HP_PROJECTILE_DODGE_RATIO
			local triggerRange = nil
			if isControl then
				triggerRange = projectile.is_dodgeable == false
					and UNDODGEABLE_CONTROL_RANGE
					or DODGEABLE_CONTROL_RANGE
			elseif isLethalDamageRisk then
				triggerRange = projectile.is_dodgeable == false
					and UNDODGEABLE_DAMAGE_RANGE
					or DODGEABLE_DAMAGE_RANGE
			end
			if triggerRange ~= nil
			and GetUnitToLocationDistance(bot, projectile.location) <= triggerRange
			then
				return true
			end
		end
	end
	return false
end

local function CanUseEmergencyMirror(bot, ability)
	return IsAbilityReady(ability)
		and bot:IsAlive()
		and not bot:IsSilenced()
		and not bot:IsStunned()
		and not bot:IsHexed()
		and not bot:IsNightmared()
		and not bot:IsInvulnerable()
		and not bot:IsCastingAbility()
		and not bot:IsUsingAbility()
		and not bot:IsChanneling()
end

local function HasUsefulDisableRemaining(enemy)
	return enemy:IsHexed()
		or GetModifiersTimeLeft(enemy, ModifierNamesStun) >= 0.5
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

local function IsUnderEnemyTower(bot, target)
	local towers = bot:GetNearbyTowers(1600, true)
	if towers == nil then return false end
	for _, tower in pairs(towers) do
		if IsValidVisibleUnit(tower)
		and GetUnitToUnitDistance(tower, target) <= 880
		then
			return true
		end
	end
	return false
end

local function ConsiderDragonStar(bot, enemies)
	local item = IsItemAvailable("item_dragon_star")
	if item == nil or not item:IsFullyCastable() then return false end
	local ultimateTarget = FlandreUltimate.GetLockedTarget(bot)
	if FlandreUltimate.IsActive(bot)
	and IsValidEnemyHero(ultimateTarget)
	and GetUnitToUnitDistance(bot, ultimateTarget) <= 950
	then
		bot:Action_UseAbility(item)
		return true
	end

	if J.IsSeriouslyRetreating(bot)
	and bot:WasRecentlyDamagedByAnyHero(2.0)
	and CountNearbyEnemies(bot, enemies, 1000) > 0
	then
		bot:Action_UseAbility(item)
		return true
	end

	if (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and CountNearbyEnemies(bot, enemies, 750) > 0
	and (CountNearbyEnemies(bot, enemies, 1200) >= 2 or J.GetHP(bot) < 0.65)
	then
		bot:Action_UseAbility(item)
		return true
	end

	return false
end

local function TryUseTrinity()
	local item = IsItemAvailable("item_trinity")
	if item ~= nil
	and item:IsFullyCastable()
	and ConsiderItemShield(item) > BOT_ACTION_DESIRE_NONE
	then
		GetBot():Action_UseAbility(item)
		return true
	end
	return false
end

local function ConsiderYukkuriInterrupt(bot, enemies)
	local item = IsItemAvailable("item_yukkuri_stick")
	if item == nil or not item:IsFullyCastable() then return false end
	local castRange = item:GetCastRange()

	for _, enemy in pairs(enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= castRange
		and CanCastStunOnTarget(enemy)
		and not HasUsefulDisableRemaining(enemy)
		and (enemy:IsChanneling() or IsTeleporting(enemy))
		then
			bot:Action_UseAbilityOnEntity(item, enemy)
			return true
		end
	end
	return false
end

local function ConsiderYukkuriOffensive(bot)
	local item = IsItemAvailable("item_yukkuri_stick")
	if item == nil or not item:IsFullyCastable() then return false end
	local target = GetProperEnemyHero(bot)
	if target ~= nil
	and J.IsGoingOnSomeone(bot)
	and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
	and GetUnitToUnitDistance(bot, target) <= item:GetCastRange()
	and CanCastStunOnTarget(target)
	and not HasUsefulDisableRemaining(target)
	then
		bot:Action_UseAbilityOnEntity(item, target)
		return true
	end
	return false
end

local function GetNearbyFarmUnitCount(bot, radius)
	local count = 0
	local laneCreeps = bot:GetNearbyLaneCreeps(radius, true)
	if laneCreeps ~= nil then count = count + #laneCreeps end
	local neutralCreeps = bot:GetNearbyNeutralCreeps(radius)
	if neutralCreeps ~= nil then count = count + #neutralCreeps end
	return count
end

local function ConsiderMirrorImage(bot, ability, enemies)
	if bot:IsSilenced() or not IsAbilityReady(ability) then
		return BOT_ACTION_DESIRE_NONE
	end

	local target = GetProperEnemyHero(bot)
	if (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	and target ~= nil
	and GetUnitToUnitDistance(bot, target) <= MIRROR_COMBAT_RANGE
	then
		return BOT_ACTION_DESIRE_VERYHIGH
	end

	if bot:GetActiveMode() == BOT_MODE_LANING and J.GetMP(bot) >= 0.45 then
		for _, enemy in pairs(enemies) do
			if GetUnitToUnitDistance(bot, enemy) <= 700
			and (not IsUnderEnemyTower(bot, enemy)
				or (bot:GetAttackTarget() == enemy
					and GetUnitToUnitDistance(bot, enemy) <= bot:GetAttackRange() + 150))
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end

	if bot:WasRecentlyDamagedByAnyHero(1.5)
	and CountNearbyEnemies(bot, enemies, MIRROR_RETREAT_RANGE) > 0
	and (J.IsSeriouslyRetreating(bot, 'naga_siren_mirror_image') or J.GetHP(bot) < 0.45)
	then
		return BOT_ACTION_DESIRE_VERYHIGH
	end

	if J.IsDoingRoshan(bot) and J.IsRoshan(J.GetProperTarget(bot)) then
		return BOT_ACTION_DESIRE_HIGH
	end

	local mode = bot:GetActiveMode()
	if J.GetMP(bot) >= 0.55
	and (mode == BOT_MODE_FARM or J.IsPushing(bot) or J.IsDefending(bot))
	and GetNearbyFarmUnitCount(bot, 800) >= 4
	then
		return BOT_ACTION_DESIRE_MODERATE
	end

	return BOT_ACTION_DESIRE_NONE
end

local function GetUltimateTarget(bot, enemies)
	local target = GetProperEnemyHero(bot)
	if target ~= nil and not target:IsInvulnerable() and not target:IsAttackImmune() then return target end

	local bestTarget = nil
	for _, enemy in pairs(enemies or {}) do
		if IsValidEnemyHero(enemy)
		and (bestTarget == nil
			or J.GetHP(enemy) < J.GetHP(bestTarget)
			or (J.GetHP(enemy) == J.GetHP(bestTarget)
				and GetUnitToUnitDistance(bot, enemy) < GetUnitToUnitDistance(bot, bestTarget)))
		then
			bestTarget = enemy
		end
	end
	return bestTarget
end

local function ConsiderUltimateEmergency(bot, ability, enemies)
	if bot:IsSilenced()
	or not IsAbilityReady(ability)
	or bot:HasModifier("modifier_thdots_flandre_04_multi")
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end
	-- 至少回收两个分身才值得消耗大招，紧急分支也不能绕过此限制。
	if #GetOwnedIllusions(bot, ULTIMATE_ILLUSION_RANGE) < MIN_ULTIMATE_ILLUSIONS then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end

	if J.GetHP(bot) < 0.35 and J.IsSeriouslyRetreating(bot, 'ability_thdots_flandre04') then
		for _, enemy in pairs(enemies) do
			if GetUnitToUnitDistance(bot, enemy) <= 800
			and bot:WasRecentlyDamagedByHero(enemy, 2.0)
			then
				return BOT_ACTION_DESIRE_ABSOLUTE, enemy, "retreat"
			end
		end
	end

	local target = GetUltimateTarget(bot, enemies)
	if target ~= nil and J.IsGoingOnSomeone(bot) then
		local distance = GetUnitToUnitDistance(bot, target)
		local escaping = distance > bot:GetAttackRange() + 100
			and distance <= 900
			and not target:IsFacingLocation(bot:GetLocation(), 120)
		if J.GetHP(target) <= 0.25 or escaping then
			return BOT_ACTION_DESIRE_ABSOLUTE, target, J.GetHP(target) <= 0.25 and "finish" or "chase"
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil
end

local function ConsiderUltimateNormal(bot, ability, enemies)
	if bot:IsSilenced()
	or not IsAbilityReady(ability)
	or bot:HasModifier("modifier_thdots_flandre_04_multi")
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end

	local illusions = GetOwnedIllusions(bot, ULTIMATE_ILLUSION_RANGE)
	if #illusions < MIN_ULTIMATE_ILLUSIONS then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end
	if DotaTime() - lastMirrorCastTime < MIRROR_SETUP_TIME then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end

	local target = GetUltimateTarget(bot, enemies)
	local nearbyEnemyCount = CountNearbyEnemies(bot, enemies, 1200)
	if nearbyEnemyCount >= 2
	and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
	then
		return BOT_ACTION_DESIRE_VERYHIGH, target, "teamfight"
	end

	if target ~= nil and J.IsGoingOnSomeone(bot) then
		local distance = GetUnitToUnitDistance(bot, target)
		if distance <= bot:GetAttackRange() + 350 then
			return BOT_ACTION_DESIRE_HIGH, target, "engage"
		end
		if J.GetHP(target) <= 0.45 and distance <= bot:GetAttackRange() + 200 then
			return BOT_ACTION_DESIRE_HIGH, target, "finish"
		end
		if bot:HasModifier("modifier_item_wanbaochui")
		and distance <= bot:GetAttackRange() + 150
		then
			return BOT_ACTION_DESIRE_HIGH, target, "engage"
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil
end

local function TryUseHorseKing()
	local item = IsItemAvailable("item_horse_king")
	if item ~= nil
	and item:IsFullyCastable()
	and ConsiderItemHorseKing(item) > BOT_ACTION_DESIRE_NONE
	then
		GetBot():Action_UseAbility(item)
		return true
	end
	return false
end

local function TryUseHorseRed()
	local item = IsItemAvailable("item_horse_red")
	if item ~= nil
	and item:IsFullyCastable()
	and ConsiderItemHorseRed(item) > BOT_ACTION_DESIRE_NONE
	then
		GetBot():Action_UseAbility(item)
		return true
	end
	return false
end

function AbilityUsageThink()
	if not IsBotAwake() then return end

	local bot = GetBot()
	local mirrorImage = bot:GetAbilityByName(MIRROR_ABILITY)
	local ultimate = bot:GetAbilityByName(ULTIMATE_ABILITY)
	FlandreUltimate.Update(bot)

	-- Action_UseAbility 会替换普通移动/攻击命令，使镜像能在弹道命中前完成失去目标。
	if CanUseEmergencyMirror(bot, mirrorImage) and HasIncomingTrackingThreat(bot) then
		bot:Action_UseAbility(mirrorImage)
		lastMirrorCastTime = DotaTime()
		return
	end

	if J.CanNotUseAction(bot) then return end

	local enemies = GetVisibleEnemyHeroes()

	if TryUseTrinity() then return end
	if ConsiderDragonStar(bot, enemies) then return end
	if ConsiderYukkuriInterrupt(bot, enemies) then return end

	-- 大招期间保留全部物品逻辑，只停止普通镜像和重复大招施法。
	if FlandreUltimate.IsActive(bot) then
		if ConsiderYukkuriOffensive(bot) then return end
		if TryUseHorseKing() then return end
		if TryUseHorseRed() then return end
		ConsiderNeutralItems()
		return
	end

	local desire, target, reason = ConsiderUltimateEmergency(bot, ultimate, enemies)
	if desire > BOT_ACTION_DESIRE_NONE then
		FlandreUltimate.BeginCast(bot, ultimate, target, reason, GetExpectedUltimateAttackCount(bot, ultimate))
		bot:Action_UseAbility(ultimate)
		return
	end

	desire = ConsiderMirrorImage(bot, mirrorImage, enemies)
	if desire > BOT_ACTION_DESIRE_NONE then
		bot:Action_UseAbility(mirrorImage)
		lastMirrorCastTime = DotaTime()
		return
	end

	if ConsiderYukkuriOffensive(bot) then return end

	desire, target, reason = ConsiderUltimateNormal(bot, ultimate, enemies)
	if desire > BOT_ACTION_DESIRE_NONE then
		FlandreUltimate.BeginCast(bot, ultimate, target, reason, GetExpectedUltimateAttackCount(bot, ultimate))
		bot:Action_UseAbility(ultimate)
		return
	end

	if TryUseHorseKing() then return end
	if TryUseHorseRed() then return end

	-- 中立物品放在末尾，之后不再提交任何 action。
	ConsiderNeutralItems()
end

----------------------------------------------------------------------------------------------------
