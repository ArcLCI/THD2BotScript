local CombatPower = {}

local function IsFiniteNumber(value)
	return type(value) == 'number'
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function IsInspectable(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and unit:IsNull() then return false end
	if unit.CanBeSeen ~= nil and not unit:CanBeSeen() then return false end
	if unit.IsAlive ~= nil and not unit:IsAlive() then return false end
	return true
end

local function IsValidDefenseSnapshot(snapshot)
	return type(snapshot) == 'table'
		and IsFiniteNumber(snapshot.armor)
		and IsFiniteNumber(snapshot.magicResistance)
		and IsFiniteNumber(snapshot.evasion)
		and snapshot.evasion >= 0
		and snapshot.evasion <= 1
end

local function IsValidAttackSnapshot(snapshot)
	return type(snapshot) == 'table'
		and IsFiniteNumber(snapshot.attackDamage)
		and snapshot.attackDamage >= 0
		and IsFiniteNumber(snapshot.attackPeriod)
		and snapshot.attackPeriod > 0
end

function CombatPower.GetDefenseSnapshot(unit)
	if unit == nil then return nil end

	local ok, inspectable, health, maxHealth, armor, magicResistance, evasion = pcall(function()
		if not IsInspectable(unit) then return false end
		return true,
			unit:GetHealth(),
			unit:GetMaxHealth(),
			unit:GetArmor(),
			unit:GetMagicResist(),
			unit:GetEvasion()
	end)
	if not ok or not inspectable
		or not IsFiniteNumber(health)
		or not IsFiniteNumber(maxHealth)
		or not IsFiniteNumber(armor)
		or not IsFiniteNumber(magicResistance)
		or not IsFiniteNumber(evasion)
	then
		return nil
	end

	return {
		health = math.max(0, health),
		maxHealth = math.max(0, maxHealth),
		armor = armor,
		magicResistance = magicResistance,
		evasion = math.max(0, math.min(1, evasion)),
	}
end

function CombatPower.GetAttackSnapshot(unit)
	if unit == nil then return nil end

	local ok, inspectable, attackDamage, attackPeriod, attackRange = pcall(function()
		if not IsInspectable(unit) then return false end
		return true, unit:GetAttackDamage(), unit:GetSecondsPerAttack(), unit:GetAttackRange()
	end)
	if not ok or not inspectable
		or not IsFiniteNumber(attackDamage)
		or not IsFiniteNumber(attackPeriod)
		or not IsFiniteNumber(attackRange)
		or attackPeriod <= 0
	then
		return nil
	end

	return {
		attackDamage = math.max(0, attackDamage),
		attackPeriod = attackPeriod,
		attackRange = math.max(0, attackRange),
	}
end

-- Dota 2 7.20 起沿用的护甲曲线；abs 使负护甲按同一曲线增伤。
function CombatPower.PhysicalDamageMultiplier(armor)
	if not IsFiniteNumber(armor) then return nil end
	return math.max(0, 1 - (0.052 * armor) / (0.9 + 0.048 * math.abs(armor)))
end

function CombatPower.MagicDamageMultiplier(magicResistance)
	if not IsFiniteNumber(magicResistance) then return nil end
	return math.max(0, 1 - magicResistance)
end

function CombatPower.ApplyResistance(rawDamage, damageType, armor, magicResistance)
	if not IsFiniteNumber(rawDamage) or rawDamage < 0 then return nil end
	if damageType == DAMAGE_TYPE_PHYSICAL then
		local multiplier = CombatPower.PhysicalDamageMultiplier(armor)
		local damage = multiplier ~= nil and rawDamage * multiplier or nil
		return IsFiniteNumber(damage) and damage or nil
	end
	if damageType == DAMAGE_TYPE_MAGICAL then
		local multiplier = CombatPower.MagicDamageMultiplier(magicResistance)
		local damage = multiplier ~= nil and rawDamage * multiplier or nil
		return IsFiniteNumber(damage) and damage or nil
	end
	if damageType == DAMAGE_TYPE_PURE then return rawDamage end
	return nil
end

function CombatPower.EstimateIncomingDamageFromSnapshot(snapshot, rawDamage, damageType)
	if not IsValidDefenseSnapshot(snapshot) then return nil end
	return CombatPower.ApplyResistance(
		rawDamage,
		damageType,
		snapshot.armor,
		snapshot.magicResistance
	)
end

function CombatPower.EstimateIncomingDamage(target, rawDamage, damageType, fallback)
	local snapshot = CombatPower.GetDefenseSnapshot(target)
	local damage = CombatPower.EstimateIncomingDamageFromSnapshot(snapshot, rawDamage, damageType)
	if damage == nil then return fallback end
	return damage
end

function CombatPower.EstimateAttackDamageFromSnapshots(attack, defense, duration, coverage)
	if not IsValidAttackSnapshot(attack) or not IsValidDefenseSnapshot(defense) then return nil end
	if not IsFiniteNumber(duration) or duration <= 0 then return nil end
	if coverage == nil then coverage = 1 end
	if not IsFiniteNumber(coverage) or coverage < 0 or coverage > 1 then return nil end
	local rawDamage = attack.attackDamage / attack.attackPeriod * duration * coverage
	if not IsFiniteNumber(rawDamage) then return nil end
	local damage = CombatPower.EstimateIncomingDamageFromSnapshot(defense, rawDamage, DAMAGE_TYPE_PHYSICAL)
	if damage == nil then return nil end
	local result = damage * (1 - defense.evasion)
	return IsFiniteNumber(result) and result or nil
end

-- 只估算普通攻击期望伤害，不解析技能或物品，避免进入原生无目标伤害评估路径。
function CombatPower.EstimateAttackDamage(attacker, target, duration, coverage, fallback)
	local attack = CombatPower.GetAttackSnapshot(attacker)
	local defense = CombatPower.GetDefenseSnapshot(target)
	local damage = CombatPower.EstimateAttackDamageFromSnapshots(attack, defense, duration, coverage)
	if damage == nil then return fallback end
	return damage
end

function CombatPower.Estimate(unit)
	if unit == nil then return 0 end

	local ok, inspectable, attackDamage, attackPeriod, maxHealth, health, level = pcall(function()
		if not IsInspectable(unit) then return false end
		return true,
			unit:GetAttackDamage(),
			unit:GetSecondsPerAttack(),
			unit:GetMaxHealth(),
			unit:GetHealth(),
			unit:GetLevel()
	end)
	if not ok or not inspectable
		or not IsFiniteNumber(attackDamage)
		or not IsFiniteNumber(attackPeriod)
		or attackPeriod <= 0
		or not IsFiniteNumber(maxHealth)
		or not IsFiniteNumber(health)
		or not IsFiniteNumber(level)
	then
		return 0
	end

	attackDamage = math.max(0, attackDamage)
	attackPeriod = math.max(0.25, attackPeriod)
	maxHealth = math.max(0, maxHealth)
	level = math.max(1, level)
	local healthFraction = maxHealth > 0
		and math.max(0, math.min(1, health / maxHealth))
		or 1
	local rawPower = attackDamage / attackPeriod + maxHealth * 0.035 + level * 5
	local result = rawPower * (0.25 + 0.75 * healthFraction)
	return IsFiniteNumber(result) and math.max(1, result) or 0
end

-- 保留旧 GetCapability 的评分尺度，只将属性读取改为可见性保护的本地计算。
function CombatPower.EstimateLegacyCapability(unit)
	if unit == nil then return 0 end

	local ok, inspectable, attackDamage, attackRange, attackPeriod, hasYoumuPassive = pcall(function()
		if not IsInspectable(unit) then return false end
		return true,
			unit:GetAttackDamage(),
			unit:GetAttackRange(),
			unit:GetSecondsPerAttack(),
			unit.HasModifier ~= nil and unit:HasModifier('passive_youmu02_attack')
	end)
	if not ok or not inspectable
		or not IsFiniteNumber(attackDamage)
		or not IsFiniteNumber(attackRange)
		or not IsFiniteNumber(attackPeriod)
		or attackPeriod <= 0
	then
		return 0
	end

	attackDamage = math.max(0, attackDamage)
	attackRange = math.max(0, attackRange)
	attackPeriod = math.max(0.25, attackPeriod)
	if hasYoumuPassive then
		attackDamage = attackDamage * (4 / attackPeriod)
	else
		attackDamage = attackDamage * 0.5
	end
	local result = attackDamage * (attackRange / 200 + 1) / attackPeriod
	return IsFiniteNumber(result) and result or 0
end

return CombatPower
