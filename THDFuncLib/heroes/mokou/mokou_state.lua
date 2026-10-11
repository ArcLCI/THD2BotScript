local Actions = require(GetScriptDirectory() .. '/THDFuncLib/action_intent')
local J = require(GetScriptDirectory() .. '/THDFuncLib/thd_func')
local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/modes/evasive/avoidance_geometry')
local TowerSafety = require(GetScriptDirectory() .. '/THDFuncLib/modes/shared/tower_safety')
local CombatPower = require(GetScriptDirectory() .. '/THDFuncLib/combat_power')
local SkillMovement = require(GetScriptDirectory() .. '/THDFuncLib/modes/evasive/skill_avoidance')
local Config = require(GetScriptDirectory() .. '/THDFuncLib/heroes/mokou/mokou_config')
local Threat = require(GetScriptDirectory() .. '/THDFuncLib/heroes/mokou/mokou_threat')
local M = {}
local Q, E, EX, R = 'ability_thdots_mokou01', 'ability_thdots_mokou03', 'ability_thdots_mokouEx', 'ability_thdots_mokou04'
local MOTION, EGG = 'modifier_thdots_Mokou01_think_interval', 'modifier_phenx_egg_caster'
local REFRESH, ULT = 'modifier_thdots_Mokou_ex', 'modifier_thdots_Mokou_04'
local CHARGE = 'modifier_item_yuetufensuijvren_buff'

function M.IsHero(bot)
	return bot ~= nil and bot:GetUnitName() == 'npc_dota_hero_chaos_knight' and not bot:IsIllusion()
end

local function Special(ability, key, fallback)
	if ability == nil then return fallback end
	local value = ability:GetSpecialValueFloat(key)
	return value ~= nil and value > 0 and value or fallback
end

local function Ready(ability)
	return ability ~= nil and not ability:IsNull() and (ability:IsItem() or ability:GetLevel() > 0)
		and ability:IsActivated() and ability:IsFullyCastable()
end

local function Item(bot, name)
	if bot:IsMuted() then return nil end
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and item:GetName() == name and Ready(item) then return item end
	end

end

local function Valid(bot, unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
		and unit:GetTeam() ~= bot:GetTeam() and not unit:IsInvulnerable()
end

local function Log(bot, state, event, reason)
	if not Config.DEBUG and not (Config.CHASE_DEBUG and
		(state.reason == 'chase_q' or state.reason == 'combat_q' or state.reason == 'combat_refresh')) then return end
	local hit = state.hit or {}
	local travel = state.origin and Geometry.Distance(state.origin, bot:GetLocation()) or 0
	local remaining = Valid(bot, state.target) and GetUnitToUnitDistance(bot, state.target) or -1
	print(string.format('[BOT][Mokou] run=%s time=%.2f pid=%d event=%s reason=%s ability=%s self_damage=%.1f incoming=%.1f hit_min=%.3f hit_max=%.3f travel=%.1f target_distance=%.1f landing=%s',
		Config.RUN_ID, DotaTime(), bot:GetPlayerID(), event, reason or state.reason,
		state.ability:GetName(), state.selfDamage or 0, hit.damage or 0, hit.earliest or -1, hit.latest or -1, travel, remaining, state.landingKind or 'none'))
end

local function Finish(bot, reason)
	local state = bot.THD_MokouAction
	if state ~= nil then Log(bot, state, 'release', reason) end
	bot.THD_MokouAction = nil
	bot.THD_MokouRetryAt = DotaTime() + 0.15
end

function M.IsProtected(bot) return Actions.MokouProtected(bot) end

function M.Update(bot)
	if not M.IsHero(bot) then return nil end
	local state = bot.THD_MokouAction
	if not bot:IsAlive() then
		if state ~= nil then Finish(bot, 'dead') end
		bot.THD_MokouHealthSample = nil
		bot.THD_MokouRefresh = nil
		bot.THD_MokouRecoverySample = nil
		bot.THD_MokouThreat = nil
		return nil
	end
	if state == nil then return nil end
	local now = DotaTime()
	if state.phase == 'issued' then
		if state.ability:GetName() == EX and bot:HasModifier(REFRESH) then
			-- 只保留用途，不预排Q；下一次决策仍重新检查血量、落点及目标。
			bot.THD_MokouRefresh = {reason = state.reason, target = state.target, mode = state.mode, expires = now + 1.5}
			Log(bot, state, 'confirmed', REFRESH)
			Finish(bot, 'refresh_confirmed')
			return nil
		end
		local active = state.modifier ~= nil and bot:HasModifier(state.modifier)
		if active and not state.confirmed then
			state.confirmed = true
			Log(bot, state, 'confirmed', state.modifier)
		end
		if state.modifier == CHARGE and active then
			-- 冲锋由游戏侧移动；仅在目标失效、危险或无进展时有意停止。
			local invalid = not Valid(bot, state.target)
			local distance = not invalid and GetUnitToUnitDistance(bot, state.target) or math.huge
			if distance < (state.bestDistance or math.huge) - 25 then
				state.bestDistance, state.progressAt = distance, now
			end
			if invalid or bot:GetHealth() < bot:GetMaxHealth() * 0.15
			or now - (state.progressAt or state.issuedAt) > 0.8 or now >= state.expires then
				-- GetDesire也会维护状态，此处只记取消原因，实际停止仅由模式Think执行。
				state.cancelReason = invalid and 'charge_target_lost' or 'charge_unsafe_or_stalled'
				return state
			end
		end
		if state.confirmed and not active then Finish(bot, 'lifecycle_ended'); return nil end
		local ability = state.ability
		local casting = ability ~= nil and not ability:IsNull() and (ability:IsInAbilityPhase() or ability:IsChanneling())
		if now >= state.confirmUntil and not active and not casting then
			if not state.modifier and ability:GetCooldownTimeRemaining() > 0 then
				Log(bot, state, 'confirmed', 'cooldown')
			end
			Finish(bot, state.modifier and 'start_unconfirmed' or 'cast_window_ended')
			return nil
		end
	end
	if now > state.expires then Finish(bot, 'timeout'); return nil end
	return state
end

local function CombatMode(mode)
	return mode == BOT_MODE_ATTACK or mode == BOT_MODE_ROAM or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_GANK or mode == BOT_MODE_DEFEND_ALLY
end

local function Context(bot, mode, lockedTarget)
	local c = {enemies = {}, mode = mode or bot:GetActiveMode(), incoming = 0, nearest = math.huge}
	for _, enemy in ipairs(CachedGetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)) do
		if Valid(bot, enemy) and not J.IsSuspiciousIllusion(enemy) then
			table.insert(c.enemies, enemy)
			local distance = GetUnitToUnitDistance(bot, enemy)
			c.nearest = math.min(c.nearest, distance)
			if not enemy:IsStunned() and not enemy:IsDisarmed()
			and (distance <= enemy:GetAttackRange() + 300 or enemy:GetAttackTarget() == bot) then
				c.incoming = c.incoming + (CombatPower.EstimateAttackDamage(enemy, bot, 1.5, 1) or bot:GetMaxHealth() * 0.2)
			end
		end
	end
	local now, health = DotaTime(), bot:GetHealth()
	local sample = bot.THD_MokouHealthSample
	c.pressure = bot:WasRecentlyDamagedByAnyHero(2)
	-- 原生伤害估算不能完整认识自定义技能，以最近实际掉血补足短期危险判断。
	if sample == nil or now - sample.at > 1 then sample = {health = health, at = now, loss = 0} end
	if now - sample.at >= 0.2 then
		sample.loss = math.max(0, sample.health - health) / (now - sample.at) * 1.5
		sample.health, sample.at = health, now
	end
	if c.pressure then c.incoming = math.max(c.incoming, sample.loss or 0) end
	c.observedLoss = c.pressure and (sample.loss or 0) or 0
	bot.THD_MokouHealthSample = sample
	c.hp = health / bot:GetMaxHealth()
	c.retreat = c.mode == BOT_MODE_RETREAT or (c.pressure and c.hp < 0.30)
	local function HeroTarget(target)
		return Valid(bot, target) and target:IsHero() and not J.IsSuspiciousIllusion(target) and not target:IsAttackImmune()
	end
	c.target, c.targetSource = bot:GetTarget(), 'stored_target'
	if not HeroTarget(c.target) then c.target, c.targetSource = bot:GetAttackTarget(), 'attack_target' end
	if lockedTarget ~= nil then c.target, c.targetSource = lockedTarget, 'candidate_target' end
	-- 原生进攻模式未填写脚本目标时，从可见敌人中取最近的有效英雄，不额外要求移动采样。
	if lockedTarget == nil and not HeroTarget(c.target) and CombatMode(c.mode) then
		local nearest = math.huge
		for _, enemy in ipairs(c.enemies) do
			local distance = GetUnitToUnitDistance(bot, enemy)
			if HeroTarget(enemy) and distance < nearest then
				nearest, c.target, c.targetSource = distance, enemy, 'attack_mode_nearest'
			end
		end
	end
	c.combat = Valid(bot, c.target) and c.target:IsHero() and not J.IsSuspiciousIllusion(c.target)
		and not c.target:IsAttackImmune() and (CombatMode(c.mode) or bot:GetAttackTarget() == c.target)
	local refresh = bot.THD_MokouRefresh
	if refresh ~= nil and now <= refresh.expires then
		if refresh.reason == 'escape_refresh' then c.retreat = true end
		if refresh.reason == 'combat_refresh' and lockedTarget == nil then
			c.target, c.targetSource = refresh.target, 'refresh_target'
			c.combat = HeroTarget(c.target) and CombatMode(c.mode)
		end
		-- 收割刷新不沿用丢失视野的目标，也不把原逃生刷新改作追敌。
		c.refresh = refresh
	else bot.THD_MokouRefresh = nil end
	return c
end

local function Nearest(location, enemies)
	local distance = math.huge
	for _, enemy in ipairs(enemies) do distance = math.min(distance, Geometry.Distance(location, enemy:GetLocation())) end
	return distance
end

local function SafeLanding(bot, location, c, retreat, qGlide)
	if location == nil or not IsLocationPassable(location) then return false, 'landing_blocked' end
	local observation = TowerSafety.Observe(bot, 'mokou_movement')
	if observation.available ~= true then return false, 'tower_snapshot_missing' end
	local origin = bot:GetLocation()
	if not Geometry.ValidateMovementSegment(origin, location, observation.towers, 96, retreat) then return false, 'tower_path' end
	if qGlide then
		-- 游戏Q逐步SetOrigin，可越过步行障碍；仍要求可见可落地终点及完整防越塔检查。
		if not IsLocationVisible(location) then return false, 'landing_unseen' end
		return true -- 追击Q的优势判断由专属入口负责，不重复套人数和45%生命门槛。
	elseif not Geometry.ValidateLocalTerrainSegment(origin, location, true) then return false, 'walking_path' end
	local after = Nearest(location, c.enemies)
	if retreat then return after > c.nearest + 150 and after > 400 end
	local enemies, allies = 0, 1
	for _, enemy in ipairs(c.enemies) do
		if Geometry.Distance(location, enemy:GetLocation()) < 800 then enemies = enemies + 1 end
	end
	for _, ally in ipairs(CachedGetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)) do
		if ally ~= bot and ally:IsAlive() and Geometry.Distance(location, ally:GetLocation()) < 900 then allies = allies + 1 end
	end
	if enemies > allies then return false, 'outnumbered' end
	if enemies > 0 and c.hp < 0.45 then return false, 'low_health' end
	return true
end

local function EscapePoint(bot, range, c)
	local ancient = GetAncient(bot:GetTeam())
	if ancient == nil then return nil end
	local origin, goal = bot:GetLocation(), ancient:GetLocation()
	if Geometry.Distance(origin, goal) < 1 then return nil end
	local direction = (goal - origin):Normalized()
	for _, angle in ipairs({0, 45, -45, 90, -90}) do
		local radians = math.rad(angle)
		local vector = Vector(direction.x * math.cos(radians) - direction.y * math.sin(radians),
			direction.x * math.sin(radians) + direction.y * math.cos(radians), 0)
		local location = origin + vector * math.min(range, Geometry.Distance(origin, goal))
		if SafeLanding(bot, location, c, true) then return location end
	end
	return nil
end

local function Amplification(bot)
	-- 2019文档未说明返回单位；沿用探女模型对比例/百分数返回值的兼容。
	local value = bot:GetSpellAmp()
	return 1 + math.max(0, value > 3 and value / 100 or value)
end

local function QDamage(bot, q, refreshed)
	local raw = q:GetAbilityDamage()
	local talent = bot:GetAbilityByName('special_bonus_unique_mokou_3')
	if talent ~= nil and talent:GetLevel() > 0 then raw = raw + Special(talent, 'value', 0) end
	if bot:HasModifier('modifier_item_wanbaochui') then raw = raw + bot:GetMaxHealth() * Special(q, 'damage_wanbaochui', 10) / 100 end
	local amp = Amplification(bot)
	local selfDamage = bot:GetActualIncomingDamage(raw * amp * (refreshed and 2 or 1), DAMAGE_TYPE_MAGICAL)
	return raw * amp * (refreshed and 0.5 or 1), selfDamage
end

local function Survives(bot, damage, c)
	return bot:GetHealth() - damage > math.max(bot:GetMaxHealth() * Config.SELF_DAMAGE_RESERVE, c.incoming)
end

local function Recoverable(bot, e, c)
	if c.hp > Config.RECOVERY_HEALTH or c.pressure or c.nearest < Config.RECOVERY_NEAR_THREAT
	or bot:HasModifier('modifier_fountain_aura_buff') or bot:WasRecentlyDamagedByCreep(3) then
		bot.THD_MokouRecoverySample = nil
		return false
	end
	local sample = bot.THD_MokouRecoverySample
	local now, hp = DotaTime(), bot:GetHealth()
	if sample == nil or sample.quietSince == nil or now - sample.at > 1 or hp < sample.health then sample = {quietSince = now} end
	sample.at, sample.health = now, hp
	bot.THD_MokouRecoverySample = sample
	if now - sample.quietSince < Config.RECOVERY_QUIET_TIME then return false end
	local duration = Special(e, 'duration', 7) + 0.75
	local visible = {}
	-- 仅在低血量恢复候选时检查可见英雄；不把1600范围外的可见敌人误当成失踪。
	for _, enemy in ipairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if enemy ~= nil and not enemy:IsNull() and enemy:CanBeSeen() and enemy:IsAlive() then
			visible[enemy:GetPlayerID()] = true
			local distance = GetUnitToUnitDistance(bot, enemy)
			local reach = math.max(700, enemy:GetAttackRange() + 200)
			local speed = math.max(300, enemy:GetCurrentMovementSpeed())
			if distance < Config.RECOVERY_NEAR_THREAT or distance <= reach + speed * duration then return false end
		end
	end
	local sheltered = bot:DistanceFromFountain() <= 1200
	if not sheltered then
		for _, tower in ipairs(bot:GetNearbyTowers(900, false)) do
			if tower:IsAlive() then sheltered = true; break end
		end
	end
	-- 新鲜目击按接近时间判断；较旧的近处目击保留警戒，完全未知敌情要求己方塔/泉水掩护。
	for _, id in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) and not visible[id] then
			local seen = GetHeroLastSeenInfo(id)
			if seen == nil or #seen == 0 then
				if not sheltered then return false end
			else
				for _, last in ipairs(seen) do
					local age = last.time_since_seen
					local distance = Geometry.Distance(bot:GetLocation(), last.location)
					if age <= Config.RECOVERY_RECENT_SIGHT then
						if distance <= 700 + 400 * (duration + age) then return false end
					elseif age <= Config.RECOVERY_STALE_SIGHT then
						if distance <= Config.RECOVERY_UNKNOWN_RADIUS then return false end
						if distance <= 700 + 400 * (duration + Config.RECOVERY_RECENT_SIGHT) and not sheltered then return false end
					elseif not sheltered then return false end
				end
			end
		end
	end
	return true
end

local function Candidate(ability, reason, location, target, selfDamage)
	return {ability = ability, reason = reason, location = location, target = target, selfDamage = selfDamage}
end

local function ChaseNote(bot, reason, c, selfDamage)
	if not Config.CHASE_DEBUG or DotaTime() < (bot.THD_MokouChaseLogAt or -90) then return end
	bot.THD_MokouChaseLogAt = DotaTime() + Config.CHASE_LOG_INTERVAL
	local distance = Valid(bot, c.target) and GetUnitToUnitDistance(bot, c.target) or -1
	print(string.format('[BOT][MokouChase] run=%s time=%.2f pid=%d reason=%s source=%s mode=%s distance=%.1f hp=%.1f self_damage=%.1f',
		Config.RUN_ID, DotaTime(), bot:GetPlayerID(), reason, c.targetSource or 'none', tostring(c.mode), distance, bot:GetHealth(), selfDamage or 0))
end

local function LocalAdvantage(bot, c)
	if c.localAdvantage ~= nil then return c.localAdvantage end
	-- 优势按局部战力比较；不再要求人数更多，允许有战力优势的单挑追击。
	local ours, theirs = CombatPower.Estimate(bot), 0
	local counted = {}
	for _, ally in ipairs(CachedGetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)) do
		if ally ~= bot and ally:IsAlive() and not ally:IsIllusion() then ours = ours + CombatPower.Estimate(ally) end
	end
	for _, enemy in ipairs(c.enemies) do
		theirs = theirs + CombatPower.Estimate(enemy)
		counted[enemy] = true
	end
	if not counted[c.target] then theirs = theirs + CombatPower.Estimate(c.target) end
	c.localAdvantage = ours > theirs
	return c.localAdvantage
end

local function ChaseQ(bot, c, q, selfDamage)
	if not CombatMode(c.mode) or not c.combat then return nil, 'no_attack_target' end
	if c.retreat or bot:IsSilenced() or bot:IsRooted() or IsYugi04NoDisplacementActive(bot) then return nil, 'cannot_pursue' end
	if not Ready(q) then return nil, 'q_unavailable' end
	local distance = GetUnitToUnitDistance(bot, c.target)
	if distance <= bot:GetAttackRange() + 25 then return nil, 'already_in_attack_range' end
	if bot:GetHealth() <= selfDamage + 25 then return nil, 'lethal_self_damage' end
	if not LocalAdvantage(bot, c) then return nil, 'no_local_advantage' end
	local range = math.max(0, q:GetCastRange() - 20)
	local origin = bot:GetLocation()
	local predicted = c.target:GetExtrapolatedLocation(q:GetCastPoint() + math.min(distance, range) / Special(q, 'move_speed', 1500))
	local gap = Geometry.Distance(origin, predicted)
	if gap <= 0 or range <= 0 then return nil, 'invalid_landing' end
	local travel = math.min(range, math.max(0, gap - bot:GetAttackRange() * 0.5))
	local point = origin + (predicted - origin):Normalized() * travel
	-- 只从可见移动推断敌人在后撤，不读取敌方Bot模式；稳定远离时优先落在其前方堵截。
	local current = c.target:GetLocation()
	local dx, dy = predicted.x - current.x, predicted.y - current.y
	local motion = math.sqrt(dx * dx + dy * dy)
	if motion > 20 and c.target:GetMovementDirectionStability() >= 0.5
	and dx * (current.x - origin.x) + dy * (current.y - origin.y) > 0 then
		local ahead = predicted + Vector(dx / motion, dy / motion, 0) * 120
		if Geometry.Distance(origin, ahead) <= range and SafeLanding(bot, ahead, c, false, true) then
			local candidate = Candidate(q, 'chase_q', ahead, c.target, selfDamage)
			candidate.landingKind = 'intercept'
			return candidate, 'intercept_ready'
		end
	end
	local safe, reason = SafeLanding(bot, point, c, false, true)
	if not safe then return nil, reason end
	local candidate = Candidate(q, 'chase_q', point, c.target, selfDamage)
	candidate.landingKind = 'close_gap'
	return candidate, 'close_gap_ready'
end

local combatEquipment = {
	item_glutton_spork = true, item_trinity = true, item_dragon_star = true,
	item_yuetufensuijvren = true, item_autumn_leaves = true, item_camera = true,
	item_horse_king = true, item_nb9ball = true,
}

local function CombatQ(bot, c, q, ex)
	if not CombatMode(c.mode) or not c.combat or c.retreat or bot:IsSilenced() or bot:IsRooted()
	or IsYugi04NoDisplacementActive(bot) or c.target:IsMagicImmune()
	or q == nil or q:GetLevel() == 0 or not q:IsActivated() then return nil end
	local upgraded = bot:HasModifier('modifier_item_wanbaochui')
	local equipment = 0
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and combatEquipment[item:GetName()] then equipment = equipment + 1 end
	end
	-- 不用游戏时间冒充装备成型：两件核心装备或实际万宝槌标记才开放常规补伤害。
	if not upgraded and equipment < 2 then return nil end
	local refreshed = bot:HasModifier(REFRESH)
	local reset = not Ready(q)
	if reset and (not upgraded or refreshed or not Ready(ex)
		or q:GetCooldownTimeRemaining() <= Config.OFFENSIVE_REFRESH_MIN_COOLDOWN) then return nil end
	local damage, cost = QDamage(bot, q, refreshed or reset)
	local reserve = (refreshed or reset) and Config.REFRESH_Q_RESERVE
		or upgraded and Config.UPGRADED_Q_RESERVE or Config.COMBAT_Q_RESERVE
	if bot:GetHealth() - cost <= math.max(bot:GetMaxHealth() * reserve, c.incoming) then return nil end
	if not LocalAdvantage(bot, c) or c.target:GetActualIncomingDamage(damage, DAMAGE_TYPE_MAGICAL) <= 0 then return nil end
	local origin = bot:GetLocation()
	local radius = math.max(0, Special(q, 'damage_radius', 400) - 40)
	local range = math.max(0, q:GetCastRange() - 20)
	local point = origin
	local targetPoint = c.target:GetExtrapolatedLocation(q:GetCastPoint() + 0.02)
	-- 已贴身时原地爆炸补伤害；只在需要覆盖目标时短位移，尽快恢复普攻。
	if Geometry.Distance(origin, targetPoint) > radius then
		targetPoint = c.target:GetExtrapolatedLocation(q:GetCastPoint() + range / Special(q, 'move_speed', 1500))
		local distance = Geometry.Distance(origin, targetPoint)
		local travel = math.min(range, math.max(0, distance - radius * 0.5))
		if distance <= 0 then return nil end
		point = origin + (targetPoint - origin):Normalized() * travel
	end
	if Geometry.Distance(point, targetPoint) > radius or not SafeLanding(bot, point, c, false, true) then return nil end
	local candidate = Candidate(reset and ex or q, reset and 'combat_refresh' or 'combat_q', point, c.target, cost)
	-- 刷新使用无目标指令，预案落点不能传给Ex；Q落点在确认刷新后重新计算。
	if reset then candidate.location = nil end
	candidate.landingKind = reset and 'refresh_for_damage' or 'damage'
	return candidate
end

local function HasUncertainProtection(bot)
	-- 不猜测陌生护盾/免死是否能抵消自伤；只在绝境候选处扫描自身modifier。
	for index = 0, bot:NumModifiers() - 1 do
		local name = bot:GetModifierName(index) or ''
		if string.find(name, 'shield', 1, true) or string.find(name, 'barrier', 1, true)
		or string.find(name, 'grave', 1, true) or string.find(name, 'invulner', 1, true)
		or string.find(name, 'fountain', 1, true) then return true end
	end
	return false
end

local function Evaluate(bot, mode)
	local c = Context(bot, mode)
	local q, e, ex, r = bot:GetAbilityByName(Q), bot:GetAbilityByName(E), bot:GetAbilityByName(EX), bot:GetAbilityByName(R)
	local spells = not bot:IsSilenced()
	local mobility = spells and not bot:IsRooted() and not IsYugi04NoDisplacementActive(bot)
	local refreshed = bot:HasModifier(REFRESH)
	local qDamage, selfDamage = 0, math.huge
	if q ~= nil and q:GetLevel() > 0 then qDamage, selfDamage = QDamage(bot, q, refreshed) end
	local shield = Item(bot, 'item_trinity')
	if shield ~= nil and not bot:HasModifier('modifier_item_trinity_active_shield')
	and c.nearest < 1000 and (c.retreat or (c.pressure and c.hp < 0.75)) then return Candidate(shield, 'shield') end
	local dragon = Item(bot, 'item_dragon_star')
	if dragon ~= nil and not bot:HasModifier('modifier_item_dragon_star_buff') and c.nearest < 1000
	and (c.retreat or c.combat or (c.pressure and c.hp < 0.75)) then return Candidate(dragon, 'purge') end
	local jump = not bot:IsRooted() and not IsYugi04NoDisplacementActive(bot)
		and (Item(bot, 'item_nb9ball') or Item(bot, 'item_wanmeitiaoyuezhuangzhi')) or nil
	if c.retreat and c.nearest < 1400 then
		if jump ~= nil then
			local point = EscapePoint(bot, Special(jump, 'AbilityCastRange', 499), c)
			if point then return Candidate(jump, 'escape_jump', point) end
		end
		if mobility and q ~= nil and q:GetLevel() > 0 then
			local point = EscapePoint(bot, q:GetCastRange(), c)
			if point and Ready(q) and Survives(bot, selfDamage, c) then return Candidate(q, 'escape_q', point, nil, selfDamage) end
			if point and not Ready(q) and q:GetCooldownTimeRemaining() > 0 and Ready(ex) and not refreshed then
				local _, cost = QDamage(bot, q, true)
				if Survives(bot, cost, c) then return Candidate(ex, 'escape_refresh', nil, nil, cost) end
			end
		end
	end
	if spells and Ready(r) and not bot:HasModifier(ULT) and c.nearest < 900
	and ((c.combat and not c.retreat) or (c.retreat and not bot:IsRooted())) then
		local cost = bot:GetActualIncomingDamage(bot:GetHealth() * Special(r, 'costhp', 25) / 100 * Amplification(bot), DAMAGE_TYPE_MAGICAL)
		local talent = bot:GetAbilityByName('special_bonus_unique_mokou_1')
		if talent ~= nil and talent:GetLevel() > 0 then cost = 0 end
		if Survives(bot, cost, c) then return Candidate(r, c.retreat and 'escape_r' or 'combat_r', nil, nil, cost) end
	end
	local horse = Item(bot, 'item_horse_king')
	if horse ~= nil and c.refresh == nil then
		local wanted = (c.combat or (c.retreat and c.nearest < 1200)) and bot:GetMana() > bot:GetMaxMana() * 0.15
		if horse:GetToggleState() ~= wanted then return Candidate(horse, wanted and 'horse_on' or 'horse_off') end
	end
	if spells and Ready(e) and Recoverable(bot, e, c) then return Candidate(e, 'safe_recovery') end
	local red = Item(bot, 'item_horse_red')
	if red ~= nil and c.hp < 0.8 and not c.pressure and c.nearest > 1200
	and not bot:HasModifier('modifier_fountain_aura_buff') then return Candidate(red, 'recovery_item') end
	if c.refresh == nil then
		local chase, reason = ChaseQ(bot, c, q, selfDamage)
		if CombatMode(c.mode) and #c.enemies > 0 then ChaseNote(bot, reason, c, selfDamage) end
		if chase ~= nil then return chase end
	end
	if c.refresh == nil or c.refresh.reason == 'combat_refresh' then
		local combat = CombatQ(bot, c, q, ex)
		if combat ~= nil then return combat end
	end
	if not c.retreat and c.combat and c.refresh == nil then
		local distance = GetUnitToUnitDistance(bot, c.target)
		local location = c.target:GetExtrapolatedLocation(0.25)
		if distance > bot:GetAttackRange() + 100 and jump ~= nil then
			local range = Special(jump, 'AbilityCastRange', 499)
			local delta = location - bot:GetLocation()
			local length = Geometry.Distance(location, bot:GetLocation())
			if length > 0 and length <= range + bot:GetAttackRange() then
				local point = bot:GetLocation() + delta:Normalized() * math.min(range, math.max(0, length - bot:GetAttackRange() * 0.7))
				if SafeLanding(bot, point, c, false) then return Candidate(jump, 'chase_jump', point, c.target) end
			end
		end
		local charge = Item(bot, 'item_yuetufensuijvren')
		if charge ~= nil and distance > bot:GetAttackRange() + 50 and distance <= Special(charge, 'AbilityCastRange', 550)
		and not c.target:IsMagicImmune() and SafeLanding(bot, location, c, false) then return Candidate(charge, 'charge', nil, c.target) end
	end
	if mobility and q ~= nil and q:GetLevel() > 0 and not c.retreat
	and (c.refresh == nil or c.refresh.reason == 'kill_refresh') then
		for _, enemy in ipairs(c.enemies) do
			local point = enemy:GetExtrapolatedLocation(0.1 + GetUnitToUnitDistance(bot, enemy) / Special(q, 'move_speed', 1500))
			if (c.refresh == nil or c.refresh.target == enemy) and not enemy:IsMagicImmune() and Geometry.Distance(bot:GetLocation(), point) <= q:GetCastRange()
			and SafeLanding(bot, point, c, false) then
				local threshold = enemy:GetHealth() + math.max(0, enemy:GetHealthRegen()) + 20
				if Ready(q) and enemy:GetActualIncomingDamage(qDamage, DAMAGE_TYPE_MAGICAL) > threshold
				and Survives(bot, selfDamage, c) then return Candidate(q, 'kill_q', point, enemy, selfDamage) end
				if not Ready(q) and q:GetCooldownTimeRemaining() > 0 and Ready(ex) and not refreshed then
					local damage, cost = QDamage(bot, q, true)
					if enemy:GetActualIncomingDamage(damage, DAMAGE_TYPE_MAGICAL) > threshold and Survives(bot, cost, c) then
						return Candidate(ex, 'kill_refresh', nil, enemy, cost)
					end
				end
			end
		end
	end
	-- 绝境分支最后评估；不以自伤换人，不把可能存在的护盾当成可确认的自杀。
	if Config.ALLOW_DESPERATE_DENY and mobility and q ~= nil and q:GetLevel() > 0
	and c.hp <= Config.DENY_HEALTH and c.pressure and c.observedLoss >= bot:GetHealth()
	and not bot:IsInvulnerable() and not bot:HasModifier('modifier_item_trinity_active_shield')
	and not bot:HasModifier('modifier_item_dragon_star_buff') and not HasUncertainProtection(bot) then
		local walk = EscapePoint(bot, math.min(450, bot:GetCurrentMovementSpeed()), c)
		local threshold = bot:GetHealth() + math.max(0, bot:GetHealthRegen()) * 0.5 + 20
		local observation = TowerSafety.Observe(bot, 'mokou_deny')
		local aid = false
		for _, ally in ipairs(CachedGetNearbyHeroes(bot, 900, false, BOT_MODE_NONE)) do
			if ally ~= bot and ally:IsAlive() then aid = true; break end
		end
		-- 未知地形/塔状态、可用无自伤跳跃或近处队友，都不能当作已证明无路可逃。
		if walk == nil and jump == nil and observation.available == true and not aid and c.nearest < 900 then
			if Ready(q) and selfDamage > threshold then return Candidate(q, 'desperate_deny', bot:GetLocation(), nil, selfDamage) end
			if not Ready(q) and q:GetCooldownTimeRemaining() > 0 and Ready(ex) and not refreshed then
				local _, cost = QDamage(bot, q, true)
				if cost > threshold then return Candidate(ex, 'deny_refresh', nil, nil, cost) end
			end
		end
	end
	local clear = c.mode == BOT_MODE_FARM or c.mode == BOT_MODE_PUSH_TOWER_TOP or c.mode == BOT_MODE_PUSH_TOWER_MID
		or c.mode == BOT_MODE_PUSH_TOWER_BOT or c.mode == BOT_MODE_DEFEND_TOWER_TOP
		or c.mode == BOT_MODE_DEFEND_TOWER_MID or c.mode == BOT_MODE_DEFEND_TOWER_BOT
	if clear and mobility and Ready(q) and not refreshed and c.refresh == nil and c.nearest > 1400 and Survives(bot, selfDamage, c) then
		local farming = c.mode == BOT_MODE_FARM
		local aoe = CachedFindAoELocation(bot, 1, true, false, bot:GetLocation(), q:GetCastRange(),
			Special(q, 'damage_radius', 400), 0.5, farming and qDamage * 0.5 or 0)
		if aoe.count >= (farming and 3 or 4) and SafeLanding(bot, aoe.targetloc, c, false) then
			return Candidate(q, 'clear_q', aoe.targetloc, nil, selfDamage)
		end
	end
	return nil
end

local function ImminentCandidate(bot)
	if not Config.ALLOW_DESPERATE_DENY or not Config.ALLOW_IMMINENT_DENY or not M.IsHero(bot)
	or not bot:IsAlive() or bot:IsInvulnerable() or bot:IsStunned() or bot:IsHexed() or bot:IsSilenced()
	or bot:IsRooted() or IsYugi04NoDisplacementActive(bot) or Actions.Protected(bot)
	or J.IsTowerEscapeActive(bot) or SkillMovement.IsActive(bot) then return nil end
	local q = bot:GetAbilityByName(Q)
	if not Ready(q) or HasUncertainProtection(bot) then return nil end
	local _, cost = QDamage(bot, q, bot:HasModifier(REFRESH))
	local qDelay = q:GetCastPoint() + 0.02 + Config.IMMINENT_ORDER_MARGIN + Config.IMMINENT_SCAN_INTERVAL
	if cost <= bot:GetHealth() + math.max(0, bot:GetHealthRegen()) * qDelay + 20 then
		bot.THD_MokouThreat = nil
		return nil
	end
	local hit = Threat.Observe(bot, qDelay)
	if hit == nil then return nil end
	-- 新分支不要求先掉血或低于10%；必须已经有可见致命攻击证据，且Q比最早命中更快。
	-- 能开盾或用跳跃躲掉弹道时仍让生存动作优先，不为拒绝击杀收益主动放弃生路。
	if Item(bot, 'item_trinity') ~= nil or Item(bot, 'item_esdw') ~= nil then return nil end
	if hit.dodgeable and (Item(bot, 'item_nb9ball') ~= nil or Item(bot, 'item_wanmeitiaoyuezhuangzhi') ~= nil) then return nil end
	if hit.kind == 'melee_windup' then
		if GetUnitToUnitDistance(bot, hit.source) + bot:GetCurrentMovementSpeed() * hit.earliest
		> hit.source:GetAttackRange() + 128 then return nil end
		local c = Context(bot)
		if EscapePoint(bot, bot:GetCurrentMovementSpeed() * hit.earliest, c) ~= nil then return nil end
		if Item(bot, 'item_nb9ball') ~= nil or Item(bot, 'item_wanmeitiaoyuezhuangzhi') ~= nil then return nil end
	end
	local candidate = Candidate(q, 'imminent_deny', bot:GetLocation(), nil, cost)
	candidate.hit = hit
	return candidate
end

function M.PrepareImminent(bot)
	if not M.IsHero(bot) then return false end
	local now = DotaTime()
	if now < (bot.THD_MokouThreatAt or -90) then return false end
	bot.THD_MokouThreatAt = now + Config.IMMINENT_SCAN_INTERVAL
	local candidate = ImminentCandidate(bot)
	if candidate == nil then return false end
	if bot.THD_MokouAction ~= nil then Finish(bot, 'imminent_threat_preempts_candidate') end
	candidate.phase, candidate.mode = 'await_mode', bot:GetActiveMode()
	candidate.expires = now + Config.IMMINENT_ORDER_MARGIN
	bot.THD_MokouGeneration = (bot.THD_MokouGeneration or 0) + 1
	candidate.generation = bot.THD_MokouGeneration
	bot.THD_MokouAction = candidate
	Log(bot, candidate, 'candidate', candidate.hit.kind)
	return true
end

function M.Prepare(bot)
	if not M.IsHero(bot) or not bot:IsAlive() or bot:IsStunned() or bot:IsHexed() or J.CanNotUseAction(bot)
	or SkillMovement.IsActive(bot) or DotaTime() < (bot.THD_MokouRetryAt or -90) then return false end
	if M.Update(bot) ~= nil then return true end
	local mode = bot:GetActiveMode()
	if mode == BOT_MODE_EVASIVE_MANEUVERS then
		local refresh = bot.THD_MokouRefresh
		-- 短动作刚结束时等待原生仲裁恢复，避免把自己的规避模式误认成战斗结束而关彗星。
		if refresh == nil or DotaTime() > refresh.expires then return false end
		mode = refresh.mode
	end
	local state = Evaluate(bot, mode)
	if state == nil then return false end
	state.phase, state.mode = 'await_mode', mode
	bot.THD_MokouGeneration = (bot.THD_MokouGeneration or 0) + 1
	state.generation = bot.THD_MokouGeneration
	state.expires = DotaTime() + Config.CANDIDATE_TIMEOUT
	bot.THD_MokouAction = state
	Log(bot, state, 'candidate')
	return true
end

function M.GetDesire(bot)
	local state = M.Update(bot)
	if state == nil then return M.IsProtected(bot) and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE end
	if state.phase == 'await_mode' and (J.IsTowerEscapeActive(bot) or SkillMovement.IsActive(bot)) then
		Finish(bot, 'safety_owner'); return 0
	end
	return BOT_MODE_DESIRE_ABSOLUTE
end

function M.Think(bot)
	local state = M.Update(bot)
	if state == nil then return M.IsProtected(bot) end
	if state.cancelReason ~= nil then
		if bot == GetBot() and bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS then
			bot:Action_ClearActions(true)
			Actions.Forget(bot)
			Finish(bot, state.cancelReason)
		end
		return true
	end
	if state.phase ~= 'await_mode' then return true end
	if bot:GetActiveMode() ~= BOT_MODE_EVASIVE_MANEUVERS then return true end
	-- 接管后重新评估，Ex刷新后也必须重新证明下一次Q有收益且安全，绝不盲排连招。
	local current
	if state.reason == 'imminent_deny' then current = ImminentCandidate(bot)
	elseif state.reason == 'combat_q' or state.reason == 'combat_refresh' then
		local c = Context(bot, state.mode, state.target)
		current = CombatQ(bot, c, bot:GetAbilityByName(Q), bot:GetAbilityByName(EX))
	elseif state.reason == 'chase_q' then
		-- 模式接管后复用候选目标，只复核追击条件，避免原生GetTarget清空或普通物品抢占取消Q。
		local c = Context(bot, state.mode, state.target)
		local q = bot:GetAbilityByName(Q)
		local cost = math.huge
		if Ready(q) then local ignored; ignored, cost = QDamage(bot, q, bot:HasModifier(REFRESH)) end
		local reason
		current, reason = ChaseQ(bot, c, q, cost)
		if current == nil then ChaseNote(bot, 'commit_' .. reason, c, cost) end
	else current = Evaluate(bot, state.mode) end
	if current == nil or current.ability ~= state.ability or current.reason ~= state.reason then
		Finish(bot, 'candidate_changed'); return true
	end
	if bot:IsStunned() or bot:IsHexed() or Actions.Protected(bot) then Finish(bot, 'action_unavailable'); return true end
	local ability, now = current.ability, DotaTime()
	state.target, state.location, state.selfDamage = current.target, current.location, current.selfDamage
	state.hit = current.hit
	state.landingKind = current.landingKind
	state.origin = bot:GetLocation()
	state.phase, state.issuedAt = 'issued', now
	if ability:GetName() == Q then bot.THD_MokouRefresh = nil end
	-- 自己支付的生命不能被下一轮当成敌方爆发，从而误触发绝境自杀。
	if ability:GetName() == Q or ability:GetName() == R then bot.THD_MokouHealthSample = nil end
	state.confirmUntil = now + ability:GetCastPoint() + Config.CONFIRM_MARGIN
	local name = ability:GetName()
	state.modifier = name == Q and MOTION or name == E and EGG or name == 'item_yuetufensuijvren' and CHARGE or nil
	state.expires = state.confirmUntil + (name == E and Special(ability, 'duration', 7) + 0.5
		or name == Q and Special(ability, 'move_duration', 1) + 0.3
		or name == 'item_yuetufensuijvren' and Special(ability, 'default_buff_duration', 5) or 0.1)
	bot:Action_ClearActions(false)
	Actions.Forget(bot)
	if state.location ~= nil then bot:Action_UseAbilityOnLocation(ability, state.location)
	elseif name == 'item_yuetufensuijvren' then bot:Action_UseAbilityOnEntity(ability, state.target)
	else bot:Action_UseAbility(ability) end
	Actions.NoteIssued(bot, 'ability', state.target, state.location)
	Log(bot, state, 'issued')
	return true
end

function M.OnEnd(bot)
	local state = M.Update(bot)
	if state == nil then return M.IsProtected(bot) end
	if state.phase == 'await_mode' then Finish(bot, 'mode_lost') end
	return true
end

return M
