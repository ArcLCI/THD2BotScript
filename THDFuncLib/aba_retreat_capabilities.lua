local Capabilities = {}
local RetreatAbilityRecords = require(GetScriptDirectory() .. '/THDFuncLib/aba_retreat_ability_records')

local CURRENT_FRAME_COVERAGE = 0.03
local HIGH_REDUCTION_MULTIPLIER = 0.40
local DEFAULT_MAX_CONTROL_COMMIT = 0.60

-- 这些名称均来自地图侧实际 modifier；这里只描述 Bot 可观察到的战斗语义。
local modifierEffects = {
	modifier_aya_fantasy_find = {
		allMultiplier = 0.20,
		evasion = 1.0,
		fixedDuration = 1.2,
		observationMargin = 0.25,
		sourceAbility = 'aya_fantasy',
	},
	modifier_tensi_wanbaochui_buff = {
		allMultiplier = 0,
		sourceAbility = 'ability_thdots_tensiex',
	},
	modifier_ability_thdots_kagerou06_invulnerable = {
		attackImmune = true,
		allMultiplier = 0,
	},
	modifier_minamitsu04_Invincible = {
		attackImmune = true,
		allMultiplier = 0,
	},
}

local invulnerableModifiers = {
	'modifier_invulnerable',
	'modifier_item_tsundere_invulnerable',
	'modifier_sanae04_invulnerable',
	'modifier_mirror_image',
	'modifier_ability_thdots_kogasa03',
	'modifier_suwako02_change',
	'modifier_thdots_yukari02_hidden',
	'modifier_ability_thdots_child03_light',
	'modifier_ability_thdots_kisume02_invin',
	'modifier_ability_thdots_kisume05_target',
	'modifier_ability_thdots_kokoro04_caster_wanbaochui',
	'modifier_ability_miko01_disappearing',
	'modifier_phenx_egg_caster',
	'modifier_ability_thdots_parseeEx_invin',
	'modifier_ability_thdots_shion_04_caster',
	'modifier_ability_thdots_sumirekoEx',
	'modifier_ability_thdots_youmu2_04_invin',
	'modifier_ability_thdots_youmu2_04_caster_dummy',
}

local attackImmuneModifiers = {
	'modifier_ability_thdots_hatateEx',
	'modifier_ability_thdots_kagerou06_invulnerable',
	'modifier_thdots_komachi_04',
	'modifier_minamitsu02_vortex_target',
	'modifier_minamitsu04_Invincible',
	'modifier_thdots_nue04_states',
	'modifier_thdots_ranex_buff',
	'modifier_thdots_Remilia03_think_interval',
	'modifier_thdots_sanae04_target',
	'modifier_thdotsr_star03_ward',
	'modifier_thdots_suika03_states',
	'modifier_thdots_youmu04_states',
	'modifier_thdots_yuyukoEx',
	'modifier_ability_thdots_keine02_invincible',
	'modifier_ability_miko04_speed',
	'modifier_ability_thdots_parsee03_dummy',
	'modifier_ability_thdots_shion_04_caster',
	'modifier_ability_thdots_sunny05',
	'modifier_ability_thdots_tojiko05',
	'modifier_ability_thdots_yorihime_01_buff',
	'modifier_thdots_yuyuko03_aura_lyz',
}

local physicalImmuneModifiers = {
	'modifier_thdots_minoriko02_buff',
	'modifier_thdots_sanae04_target',
	'modifier_thdots_Suika_04',
	'modifier_thdots_youmu04_states',
	'modifier_ability_thdots_ellen02',
	'modifier_ability_thdots_keine02_invincible',
	'modifier_ability_thdots_lyrica04',
	'modifier_ability_miko04_speed',
	'modifier_ability_thdots_parsee03_dummy',
	'modifier_ability_dota2x_reimu03_ally',
	'modifier_ability_thdots_seiga05_target',
	'modifier_thdots_yuyuko03_aura_lyz',
}

for _, modifierName in pairs(invulnerableModifiers) do
	modifierEffects[modifierName] = modifierEffects[modifierName] or {}
	modifierEffects[modifierName].invulnerable = true
	modifierEffects[modifierName].allMultiplier = 0
end

for _, modifierName in pairs(attackImmuneModifiers) do
	modifierEffects[modifierName] = modifierEffects[modifierName] or {}
	modifierEffects[modifierName].attackImmune = true
end

for _, modifierName in pairs(physicalImmuneModifiers) do
	modifierEffects[modifierName] = modifierEffects[modifierName] or {}
	modifierEffects[modifierName].physicalMultiplier = 0
end

local defensiveAbilities = {
	aya_fantasy = {
		activeModifier = 'modifier_aya_fantasy_find',
		actionSupported = true,
	},
}

local customControls = {}
for abilityName, record in pairs(RetreatAbilityRecords.GetAll()) do
	local control = record.control
	if control ~= nil
	and (record.controlStatus == RetreatAbilityRecords.CONTROL_STATUS.ENABLED
		or record.controlStatus == RetreatAbilityRecords.CONTROL_STATUS.CANDIDATE)
	then
		customControls[abilityName] = {
			controlType = control.type,
			duration = control.duration or 0,
			slow = control.slow or 0,
			range = control.range or 0,
			registeredCastPoint = control.castPoint,
			registeredChannelTime = control.channelTime or 0,
			effectDelay = control.effectDelay or 0,
			maxCommitTime = control.maxCommitTime,
			requiresSetup = control.requiresSetup == true,
			allowChannel = control.allowChannel == true,
			channelLifecycleProtected = control.channelLifecycleProtected == true,
			minimumSeverity = control.minimumSeverity,
			actionSupported = true,
		}
	end
end

local controlExclusions = {
	-- 咲夜一技能只有先使用天生技能并命中线性弹道后才定身，不是独立的撤退硬控。
	ability_thdots_sakuya01 = 'requires_ex_setup_and_projectile_hit',
}

local function IsValidUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and unit:IsNull() then return false end
	if unit.IsAlive ~= nil and not unit:IsAlive() then return false end
	return true
end

local function SafeCallNumber(unit, methodName, fallback, ...)
	if unit == nil or unit[methodName] == nil then return fallback end
	local args = { ... }
	local ok, value = pcall(function() return unit[methodName](unit, unpack(args)) end)
	if not ok or type(value) ~= 'number' then return fallback end
	return value
end

local function GetCapabilityState(bot)
	if bot.THD_RetreatCapabilityState == nil then
		bot.THD_RetreatCapabilityState = {
			observedModifiers = {},
			knownAbsent = {},
		}
	end
	return bot.THD_RetreatCapabilityState
end

local function GetModifierRemaining(bot, modifierName, definition, state, now)
	local index = bot:GetModifierByName(modifierName)
	if index == nil or index < 0 then
		state.observedModifiers[modifierName] = nil
		return 0, false
	end

	local ok, remaining = pcall(function() return bot:GetModifierRemainingDuration(index) end)
	if ok and type(remaining) == 'number' and remaining >= 0 then
		return remaining, true
	end

	if definition.fixedDuration ~= nil
	and (state.observedModifiers[modifierName] ~= nil or state.knownAbsent[modifierName] == true)
	then
		local observedAt = state.observedModifiers[modifierName]
		if observedAt == nil then
			observedAt = now
			state.observedModifiers[modifierName] = observedAt
		end
		local margin = definition.observationMargin or 0
		return math.max(0, definition.fixedDuration - (now - observedAt) - margin), true
	end

	return CURRENT_FRAME_COVERAGE, false
end

local function CopyEffect(definition, modifierName, remaining, knownRemaining)
	return {
		modifier = modifierName,
		sourceAbility = definition.sourceAbility,
		remaining = remaining,
		knownRemaining = knownRemaining,
		invulnerable = definition.invulnerable == true,
		attackImmune = definition.attackImmune == true,
		magicImmune = definition.magicImmune == true,
		allMultiplier = definition.allMultiplier or 1,
		physicalMultiplier = definition.physicalMultiplier or 1,
		magicalMultiplier = definition.magicalMultiplier or 1,
		evasion = definition.evasion or 0,
	}
end

local function HasEffectFlag(effects, flag)
	for _, effect in pairs(effects) do
		if effect[flag] == true then return true end
	end
	return false
end

local function AddGenericEffect(effects, flag)
	local effect = {
		modifier = nil,
		remaining = CURRENT_FRAME_COVERAGE,
		knownRemaining = false,
		invulnerable = false,
		attackImmune = false,
		magicImmune = false,
		allMultiplier = 1,
		physicalMultiplier = 1,
		magicalMultiplier = 1,
		evasion = 0,
	}
	effect[flag] = true
	if flag == 'invulnerable' then effect.allMultiplier = 0 end
	table.insert(effects, effect)
end

local function CanUseAbility(bot, ability)
	if not IsValidUnit(bot) or ability == nil then return false end
	if ability.IsNull ~= nil and ability:IsNull() then return false end
	if ability.IsPassive ~= nil and ability:IsPassive() then return false end
	if ability.IsHidden ~= nil and ability:IsHidden() then return false end
	if ability.IsTrained ~= nil and not ability:IsTrained() then return false end
	if ability.IsActivated ~= nil and not ability:IsActivated() then return false end
	if ability.IsFullyCastable == nil or not ability:IsFullyCastable() then return false end
	return not bot:IsSilenced()
		and not bot:IsStunned()
		and not bot:IsHexed()
		and not bot:IsNightmared()
		and not bot:HasModifier('modifier_teleporting')
		and not bot:IsCastingAbility()
		and not bot:IsChanneling()
		and not bot:IsUsingAbility()
end

local function IsCastLifecycleLocked(bot)
	if bot:IsCastingAbility() or bot:IsChanneling() or bot:IsUsingAbility() then return true end
	if bot.GetAbilityInSlot == nil then return false end
	for i = 0, 23 do
		local ability = bot:GetAbilityInSlot(i)
		if ability ~= nil then
			local inPhase = ability.IsInAbilityPhase ~= nil and ability:IsInAbilityPhase()
			local channeling = ability.IsChanneling ~= nil and ability:IsChanneling()
			if inPhase or channeling then return true end
		end
	end
	return false
end

local function EvaluateControlAbility(bot, abilityName, definition)
	local result = {
		ability = abilityName,
		controlType = definition.controlType,
		duration = definition.duration or 0,
		slow = definition.slow or 0,
		range = definition.range or 0,
		available = false,
		minimumSeverity = definition.minimumSeverity,
		reason = nil,
	}
	if not definition.actionSupported then result.reason = 'missing_action_path'; return result end
	local ability = bot:GetAbilityByName(abilityName)
	if not CanUseAbility(bot, ability) then result.reason = 'not_castable'; return result end
	if IsCastLifecycleLocked(bot) then result.reason = 'cast_lifecycle_locked'; return result end

	local castPoint = SafeCallNumber(ability, 'GetCastPoint', definition.registeredCastPoint)
	local channelTime = SafeCallNumber(ability, 'GetChannelTime', definition.registeredChannelTime)
	if castPoint == nil or channelTime == nil then result.reason = 'unknown_cast_timing'; return result end
	result.castPoint = castPoint
	result.channelTime = channelTime
	result.commitTime = castPoint + (definition.effectDelay or 0)
	if result.commitTime > (definition.maxCommitTime or DEFAULT_MAX_CONTROL_COMMIT) then
		result.reason = 'cast_commit_too_long'
		return result
	end
	if channelTime > 0 then
		if not definition.allowChannel then result.reason = 'channel_not_retreat_safe'; return result end
		if not definition.channelLifecycleProtected then result.reason = 'channel_path_unprotected'; return result end
	end
	if definition.requiresSetup then
		if definition.setupCondition == nil then result.reason = 'setup_unmodelled'; return result end
		local ok, ready = pcall(definition.setupCondition, bot, ability)
		if not ok or not ready then result.reason = 'setup_unmet'; return result end
	end

	local isHardControl = result.controlType == 'HARD' and result.duration >= 0.6
	local isStrongSlow = result.controlType == 'SLOW' and result.slow >= 0.30 and result.duration >= 1.0
	if not isHardControl and not isStrongSlow then result.reason = 'control_too_weak'; return result end
	result.available = true
	result.reason = 'ready'
	result.score = (isHardControl and 20000 or 10000)
		+ result.duration * 100 + result.range * 0.01 - result.commitTime * 100
	return result
end

function Capabilities.GetSnapshot(bot)
	local snapshot = {
		active = {},
		readyDefenses = {},
		isInvulnerable = false,
		isAttackImmune = false,
		isMagicImmune = false,
		hasHighReduction = false,
		stunDuration = 0,
		slowDuration = 0,
		customControl = nil,
		controlCandidates = {},
	}
	if not IsValidUnit(bot) then return snapshot end

	local now = DotaTime()
	local state = GetCapabilityState(bot)
	for modifierName, definition in pairs(modifierEffects) do
		if bot:HasModifier(modifierName) then
			local remaining, knownRemaining = GetModifierRemaining(bot, modifierName, definition, state, now)
			state.knownAbsent[modifierName] = false
			local effect = CopyEffect(definition, modifierName, remaining, knownRemaining)
			table.insert(snapshot.active, effect)
			if effect.allMultiplier <= HIGH_REDUCTION_MULTIPLIER
			or effect.physicalMultiplier <= HIGH_REDUCTION_MULTIPLIER
			or effect.magicalMultiplier <= HIGH_REDUCTION_MULTIPLIER
			then
				snapshot.hasHighReduction = true
			end
		else
			state.observedModifiers[modifierName] = nil
			state.knownAbsent[modifierName] = true
		end
	end

	snapshot.isInvulnerable = bot:IsInvulnerable()
	snapshot.isAttackImmune = bot:IsAttackImmune()
	snapshot.isMagicImmune = bot:IsMagicImmune()
	if snapshot.isInvulnerable and not HasEffectFlag(snapshot.active, 'invulnerable') then
		AddGenericEffect(snapshot.active, 'invulnerable')
	end
	if snapshot.isAttackImmune and not HasEffectFlag(snapshot.active, 'attackImmune') then
		AddGenericEffect(snapshot.active, 'attackImmune')
	end
	if snapshot.isMagicImmune and not HasEffectFlag(snapshot.active, 'magicImmune') then
		AddGenericEffect(snapshot.active, 'magicImmune')
	end

	for abilityName, definition in pairs(defensiveAbilities) do
		local ability = bot:GetAbilityByName(abilityName)
		if definition.actionSupported and CanUseAbility(bot, ability)
		and (definition.activeModifier == nil or not bot:HasModifier(definition.activeModifier))
		then
			snapshot.readyDefenses[abilityName] = true
		end
	end
	snapshot.stunDuration = SafeCallNumber(bot, 'GetStunDuration', 0, true)
	snapshot.slowDuration = SafeCallNumber(bot, 'GetSlowDuration', 0, true)
	local bestControlScore = -math.huge
	for abilityName, definition in pairs(customControls) do
		local candidate = EvaluateControlAbility(bot, abilityName, definition)
		snapshot.controlCandidates[abilityName] = candidate
		if candidate.available and (candidate.score or 0) > bestControlScore then
			bestControlScore = candidate.score or 0
			snapshot.customControl = candidate
		end
	end
	for abilityName, reason in pairs(controlExclusions) do
		if bot:GetAbilityByName(abilityName) ~= nil then
			snapshot.controlCandidates[abilityName] = {
				ability = abilityName,
				available = false,
				reason = reason,
			}
		end
	end
	return snapshot
end

local function EffectCoversOffset(effect, offset)
	return offset <= math.max(0, effect.remaining or 0) + 0.001
end

local function AttackerCannotMiss(attacker)
	if not IsValidUnit(attacker) or attacker.IsUnableToMiss == nil then return false end
	local ok, result = pcall(function() return attacker:IsUnableToMiss() end)
	return ok and result == true
end

function Capabilities.ResolveDamage(snapshot, damageType, impactOffset, piercesMagicImmunity)
	local result = { damageMultiplier = 1, protected = false, reason = nil }
	if snapshot == nil then return result end
	impactOffset = math.max(0, impactOffset or 0)
	for _, effect in pairs(snapshot.active or {}) do
		if EffectCoversOffset(effect, impactOffset) then
			local multiplier = effect.allMultiplier or 1
			if damageType == DAMAGE_TYPE_PHYSICAL then
				multiplier = math.min(multiplier, effect.physicalMultiplier or 1)
			elseif damageType == DAMAGE_TYPE_MAGICAL then
				multiplier = math.min(multiplier, effect.magicalMultiplier or 1)
				if effect.magicImmune and not piercesMagicImmunity then multiplier = 0 end
			end
			if effect.invulnerable then multiplier = 0 end
			if multiplier < result.damageMultiplier then
				result.damageMultiplier = math.max(0, multiplier)
				result.protected = true
				result.reason = effect.invulnerable and 'invulnerable'
					or (effect.magicImmune and damageType == DAMAGE_TYPE_MAGICAL and 'magic_immune')
					or 'damage_reduction'
			end
		end
	end
	return result
end

function Capabilities.ResolveAttack(snapshot, attacker, impactOffset)
	local result = {
		damageMultiplier = 1,
		preventsAttack = false,
		preventsHit = false,
		reason = nil,
	}
	if snapshot == nil then return result end
	impactOffset = math.max(0, impactOffset or 0)

	for _, effect in pairs(snapshot.active or {}) do
		if EffectCoversOffset(effect, impactOffset) then
			result.damageMultiplier = math.min(result.damageMultiplier, effect.allMultiplier or 1)
			result.damageMultiplier = math.min(result.damageMultiplier, effect.physicalMultiplier or 1)
			if effect.invulnerable then
				result.preventsAttack = true
				result.preventsHit = true
				result.reason = 'invulnerable'
			elseif effect.attackImmune then
				result.preventsAttack = true
				result.preventsHit = true
				result.reason = result.reason or 'attack_immune'
			elseif (effect.evasion or 0) >= 1 and not AttackerCannotMiss(attacker) then
				result.preventsHit = true
				result.reason = result.reason or 'evasion'
			end
		end
	end
	return result
end

function Capabilities.GetTowerCoverageRemaining(snapshot, towers)
	if snapshot == nil or towers == nil or #towers == 0 then return 0, nil end
	local bestRemaining = 0
	local bestReason = nil
	for _, effect in pairs(snapshot.active or {}) do
		if effect.knownRemaining and (effect.remaining or 0) > bestRemaining then
			local preventsEveryTower = effect.invulnerable or effect.attackImmune
			local reason = effect.invulnerable and 'invulnerable' or (effect.attackImmune and 'attack_immune' or nil)
			if not preventsEveryTower and (effect.evasion or 0) >= 1 then
				preventsEveryTower = true
				reason = 'evasion'
				for _, tower in pairs(towers) do
					if AttackerCannotMiss(tower) then
						preventsEveryTower = false
						break
					end
				end
			end
			if preventsEveryTower then
				bestRemaining = effect.remaining
				bestReason = reason
			end
		end
	end
	return bestRemaining, bestReason
end

function Capabilities.IsDefenseReady(snapshot, abilityName)
	return snapshot ~= nil
		and snapshot.readyDefenses ~= nil
		and snapshot.readyDefenses[abilityName] == true
end

function Capabilities.GetReadyDefense(snapshot)
	if snapshot == nil then return nil end
	for abilityName, ready in pairs(snapshot.readyDefenses or {}) do
		if ready then return abilityName end
	end
	return nil
end

function Capabilities.HasEffectiveControl(snapshot)
	if snapshot == nil then return false end
	-- GetStunDuration(true) 无法暴露贡献技能，不能据此判断前摇、引导和组合条件。
	return snapshot.customControl ~= nil
end

function Capabilities.GetRetreatAbilityRecord(abilityName)
	return RetreatAbilityRecords.Get(abilityName)
end

function Capabilities.GetRetreatAbilityRecords()
	return RetreatAbilityRecords.GetAll()
end

function Capabilities.GetRetreatAbilityStatistics()
	return RetreatAbilityRecords.GetStatistics()
end

function Capabilities.GetCustomCounterDamage(bot, target, horizon)
	-- 复杂自定义连招必须按技能逐项核对后才能登记；空实现意味着只采用 Bot API 的保守估算。
	return 0
end

return Capabilities
