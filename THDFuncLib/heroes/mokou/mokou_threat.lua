local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/modes/evasive/avoidance_geometry')
local Config = require(GetScriptDirectory() .. '/THDFuncLib/heroes/mokou/mokou_config')
local T = {}

local function Number(unit,method,...)
	if not unit then return nil end
	local fn=unit[method]
	if type(fn)~='function' then return nil end
	local ok,value=pcall(fn,unit,...)
	if ok and type(value)=='number' and value==value and math.abs(value)<math.huge then return value end
end

local function VisibleEnemy(bot, unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
		and unit:GetTeam() ~= bot:GetTeam()
end

local function AttackDamage(bot, attacker)
	if bot:IsAttackImmune() or bot:GetEvasion() > 0 then return nil end
	-- 不预测暴击或攻击特效；有闪避时也不能把尚未命中的普攻当作确定致命。
	local damage=Number(attacker,'GetAttackDamage')
	local multiplier=Number(attacker,'GetAttackCombatProficiency',bot)
	-- 弹道来源未必提供完整Bot方法；系数未知不能假设为1并宣称确定致命。
	if damage==nil or multiplier==nil then
		if not bot.THD_MokouMissingAttackAPI then
			bot.THD_MokouMissingAttackAPI=true
			print('[BOT][MokouThreat] event=attack_estimate_unavailable pid='..bot:GetPlayerID()
				..' source='..attacker:GetUnitName()..' method='..(damage==nil and 'GetAttackDamage' or 'GetAttackCombatProficiency'))
		end
		return nil
	end
	local raw = damage * multiplier
	return bot:GetActualIncomingDamage(raw, DAMAGE_TYPE_PHYSICAL) * 0.8
end

local function SpellProjectile(bot, projectile)
	local ability = projectile.ability
	if ability == nil or ability:IsNull() or bot:IsMagicImmune() then return nil end
	local name, raw, speed = ability:GetName()
	-- 只纳入已核对游戏侧命中回调的即时伤害；觉02等落地后持续伤害不能拿面板当瞬伤。
	if name == 'ability_thdots_ellen01' then
		raw, speed = ability:GetSpecialValueFloat('spark_damage'), ability:GetSpecialValueFloat('wraith_speed')
	elseif name == 'ability_thdots_minoriko01' then
		raw = ability:GetSpecialValueFloat('aoe_damage') + bot:GetMaxHealth() * ability:GetSpecialValueFloat('heal_percent') / 100
		speed = 1000 -- abilityminoriko.lua 两条跟踪弹道分支均使用1000。
	else return nil end
	if raw <= 0 or speed <= 0 then return nil end
	return bot:GetActualIncomingDamage(raw, DAMAGE_TYPE_MAGICAL) * 0.8, speed
end

function T.Observe(bot, qDelay)
	local now = DotaTime()
	local state = bot.THD_MokouThreat or {attacks = {}}
	bot.THD_MokouThreat = state
	local events, nextAttacks = {}, {}
	local tooLate = false
	local function Add(kind, source, damage, earliest, latest, dodgeable)
		if damage ~= nil and latest >= 0 and earliest <= qDelay
		and damage > bot:GetHealth() + math.max(0, bot:GetHealthRegen()) * latest + 20 then tooLate = true end
		if damage ~= nil and earliest > qDelay and latest <= Config.IMMINENT_HORIZON
		and damage > bot:GetHealth() + math.max(0, bot:GetHealthRegen()) * latest + 20 then
			table.insert(events, {kind = kind, source = source, damage = damage,
				earliest = earliest, latest = latest, dodgeable = dodgeable})
		end
	end
	for _, p in ipairs(bot:GetIncomingTrackingProjectiles() or {}) do
		if p.location ~= nil and VisibleEnemy(bot, p.caster) then
			local damage, speed
			if p.is_attack then damage, speed = AttackDamage(bot, p.caster), Number(p.caster,'GetAttackProjectileSpeed')
			else damage, speed = SpellProjectile(bot, p) end
			if damage ~= nil and speed ~= nil and speed > 0 then
				-- 2019 API没有弹道速度字段，普攻取来源速度，技能用已核对的实现；预留碰撞和接管位移余量。
				local distance = Geometry.Distance(bot:GetLocation(), p.location)
				local movement = bot:GetCurrentMovementSpeed() * Config.IMMINENT_ORDER_MARGIN
				Add(p.is_attack and 'attack_projectile' or 'spell_projectile', p.caster, damage,
					math.max(0, distance - 96 - movement) / speed, (distance + movement) / speed, p.is_dodgeable)
			end
		end
	end
	local units = {}
	for _, group in ipairs({bot:GetNearbyHeroes(700, true, BOT_MODE_NONE), bot:GetNearbyLaneCreeps(700, true), bot:GetNearbyTowers(700, true)}) do
		for _, unit in ipairs(group) do units[unit] = true end
	end
	for attacker in pairs(units) do
		if VisibleEnemy(bot, attacker) then
			local activity, cycle = attacker:GetAnimActivity(), attacker:GetAnimCycle()
			local attacking = (activity == 1503 or activity == 1504) and attacker:GetAttackTarget() == bot
				and not attacker:IsStunned() and not attacker:IsDisarmed()
			local old = state.attacks[attacker]
			local sample = {at = now, cycle = cycle, attacking = attacking, release = attacker:GetLastAttackTime()}
			-- 必须观察到前摇开始/动画换轮；首次看到半截攻击动画不猜剩余时间。
			if attacking and old ~= nil and now - old.at <= 0.15 then
				if not old.attacking or cycle + 0.05 < old.cycle then sample.started = old.at
				elseif sample.release == old.release then sample.started = old.started end
			end
			nextAttacks[attacker] = sample
			if sample.started ~= nil and attacker:GetAttackRange() <= 310
			and GetUnitToUnitDistance(bot, attacker) <= attacker:GetAttackRange() + 25 then
				-- 沿用本库攻击前摇/攻速换算；不用归一化动画进度直接冒充秒数。
				local speed = attacker:GetAttackSpeed()
				if speed > 10 then speed = speed / 100 end
				local remaining = attacker:GetAttackPoint() / math.max(0.1, speed) - (now - sample.started)
				Add('melee_windup', attacker, AttackDamage(bot, attacker), remaining - Config.IMMINENT_SCAN_INTERVAL,
					remaining + Config.IMMINENT_SCAN_INTERVAL, false)
			end
		end
	end
	state.attacks = nextAttacks
	-- 另一发更早的致命命中已来不及时，不能只挑较晚的弹道声称Q仍有窗口。
	if tooLate then return nil end
	table.sort(events, function(a, b) return a.earliest < b.earliest end)
	return events[1]
end

return T
