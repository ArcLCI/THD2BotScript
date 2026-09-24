local Actions = require(GetScriptDirectory() .. '/THDFuncLib/action_intent')
local J = require(GetScriptDirectory() .. '/THDFuncLib/thd_func')
local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/avoidance_geometry')
local Towers = require(GetScriptDirectory() .. '/THDFuncLib/tower_safety')
local Power = require(GetScriptDirectory() .. '/THDFuncLib/combat_power')
local Consumables = require(GetScriptDirectory() .. '/THDFuncLib/consumable_inventory')
local Profiles = require(GetScriptDirectory() .. '/THDFuncLib/bot_profile')
local SkillMovement = require(GetScriptDirectory() .. '/THDFuncLib/skill_avoidance')
require(GetScriptDirectory() .. '/thd2_item_usage')
local K = {}
K.RUN = 'KASEN-FRONTLINE-20260924-R2'
local Q, W, E = 'ability_thdots_kasen01', 'ability_thdots_kasen02', 'ability_thdots_kasen03'
local R, RX = 'ability_thdots_kasen04', 'ability_thdots_kasen04_ex'
local EX, GAZE = 'ability_thdots_kasenEx', 'ability_thdots_kasen04_ex_WBC'
local SHADOW, COMPLETE = 'modifier_thdots_kasen_ex', 'modifier_thdots_kasen_ex_WBC'
local ABSORB = 'modifier_thdots_kasen04ex_takedamage'
local HORSE = 'modifier_item_horse_king_open'

function K.IsHero(bot)
	return bot ~= nil and bot:GetUnitName() == 'npc_dota_hero_bristleback' and not bot:IsIllusion()
end

function K.Form(bot)
	if bot:HasModifier(COMPLETE) then return 'complete' end
	return bot:HasModifier(SHADOW) and 'shadow' or 'normal'
end

function K.Profile(bot)
	-- 单路线容错：标记缺失或旧标记不改变当前唯一前排构筑。
	local profile = Profiles.GetProfileOrDefault(bot, Profiles.FRONTLINE)
	return profile == Profiles.FRONTLINE and profile or Profiles.FRONTLINE
end

function K.Log(bot, event, reason, ability, task, detail)
	-- 生命周期按任务去重，不再吞掉一秒内另一项任务的候选/释放。
	local lifecycle = event == 'candidate_created' or event == 'mode_acquired' or event == 'order'
		or event == 'phase_seen' or event == 'form_confirmed' or event == 'release'
	task = task or bot.THD_KasenAction
	if lifecycle and task ~= nil then
		task.logged = task.logged or {}
		if task.logged[event] then return end
		task.logged[event] = true
	end
	bot.THD_KasenLogs = bot.THD_KasenLogs or {}
	local key = event .. ':' .. (reason or 'none') .. ':' .. (ability or 'none')
	if not lifecycle and event ~= 'form_opportunity' and DotaTime() < (bot.THD_KasenLogs[key] or -90) then return end
	bot.THD_KasenLogs[key] = DotaTime() + 1
	local now = DotaTime()
	local timing = task and task.generation and string.format(' task=%d phase=%s target=%d observed=%.3f planned=%.3f acquired=%.3f issued=%.3f acquire_ms=%.1f issue_ms=%.1f',
		task.generation or 0, task.phase or 'none', task.targetID or -1, task.observedAt or -1, task.plannedAt or -1,
		task.acquiredAt or -1, task.issuedAt or -1,
		(task.acquiredAt and task.plannedAt) and (task.acquiredAt-task.plannedAt)*1000 or -1,
		(task.issuedAt and task.acquiredAt) and (task.issuedAt-task.acquiredAt)*1000 or -1) or ' task=0'
	print(string.format('[BOT][Kasen] run=%s team=%d player=%d profile=%s form=%s event=%s reason=%s ability=%s game_time=%.3f%s%s',
		K.RUN, bot:GetTeam(), bot:GetPlayerID(), K.Profile(bot), K.Form(bot), event, reason or 'none', ability or 'none', now,
		timing, detail and (' ' .. detail) or ''))
end

local function Special(ability, key, fallback)
	if ability == nil then return fallback end
	local value = ability:GetSpecialValueFloat(key)
	return value ~= nil and value > 0 and value or fallback
end

local function Ability(bot, name)
	if string.sub(name, 1, 5) == 'item_' then
		for slot = 0, 5 do
			local item = bot:GetItemInSlot(slot)
			if item ~= nil and item:GetName() == name then return item end
		end
		return nil
	end
	return bot:GetAbilityByName(name)
end

local function Ready(bot, name)
	local ability = Ability(bot, name)
	if ability == nil or ability:IsNull() then return nil, 'missing_ability' end
	if not ability:IsCooldownReady() then return nil, 'cooldown' end
	if bot:GetMana() < ability:GetManaCost() then return nil, 'mana' end
	if not ability:IsFullyCastable() then return nil, 'not_castable' end
	if ability:IsItem() then
		local readyAt = bot.THD_KasenItemReadyAt and bot.THD_KasenItemReadyAt[name] or -90
		if bot:IsMuted() then return nil, 'muted' end
		if DotaTime() < readyAt then return nil, 'backpack_cooldown' end
		return ability
	end
	if bot:IsSilenced() then return nil, 'silenced' end
	if ability:GetLevel() == 0 then return nil, 'unlearned' end
	if ability:IsHidden() or not ability:IsActivated() then return nil, 'form_unavailable' end
	local form = K.Form(bot)
	-- 常态二技能的初始激活状态不能充当形态判断；按机制额外约束。
	if (name == W or name == RX) and form == 'normal' then return nil, 'form_unavailable' end
	if (name == Q or name == E or name == R) and form == 'shadow' then return nil, 'form_unavailable' end
	if name == EX and form == 'complete' then return nil, 'form_unavailable' end
	return ability
end

local function Valid(bot, unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
		and unit:GetTeam() ~= bot:GetTeam() and not unit:IsInvulnerable()
end

local function Context(bot)
	local now = DotaTime()
	-- 只在同帧复用句柄，紧急/普通路径共享一次有界扫描，不延用0.12秒公共候选缓存。
	if bot.THD_KasenContext ~= nil and bot.THD_KasenContext.at == now then return bot.THD_KasenContext end
	local c = {enemies={}, allies={}, localEnemies=0, localAllies=1, nearest=math.huge}
	for _, unit in pairs(bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)) do
		if Valid(bot, unit) and not J.IsSuspiciousIllusion(unit) then
			table.insert(c.enemies, unit)
			local distance = GetUnitToUnitDistance(bot, unit)
			if distance < c.nearest then c.nearest, c.target = distance, unit end
			if distance <= 1000 then c.localEnemies = c.localEnemies + 1 end
		end
	end
	for _, ally in pairs(bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)) do
		if ally ~= bot and not ally:IsNull() and ally:IsAlive() and not ally:IsIllusion() then
			table.insert(c.allies, ally)
			if GetUnitToUnitDistance(bot, ally) <= 1000 then c.localAllies = c.localAllies + 1 end
		end
	end
	local proper = J.GetProperTarget(bot)
	for _, unit in ipairs(c.enemies) do if unit == proper then c.target = unit; break end end
	c.retreat = J.IsSeriouslyRetreating(bot)
	c.pressure = bot:WasRecentlyDamagedByAnyHero(2)
	c.at = now
	bot.THD_KasenContext = c
	return c
end

local function SafeAt(bot, point)
	local observation = Towers.Observe(bot, 'kasen')
	if not observation.available or bot:WasRecentlyDamagedByTower(2) then return false end
	for _, tower in ipairs(observation.towers) do
		if Geometry.PointInCircle(point, tower, 96) then return false end
	end
	-- 飞行中的普攻来源不可见时不假定安全，也不调用全局敌方信息。
	for _, projectile in pairs(bot:GetIncomingTrackingProjectiles() or {}) do
		if projectile.is_attack then
			local source = projectile.caster
			if source == nil or source:IsNull() or not source:CanBeSeen() or source:IsTower() then return false end
		end
	end
	return true
end

local function Survive(bot, c, seconds, remaining)
	local damage = 0
	for _, enemy in ipairs(c.enemies) do
		if GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() + 300 then
			local amount = Power.EstimateAttackDamage(enemy, bot, seconds, 1, nil)
			if amount == nil then return false, 'threat_unknown' end
			damage = damage + amount
		end
	end
	-- 这里只用可见普攻的保守下界筛除明显危险，不把吸伤技能当作无敌。
	return remaining > damage + bot:GetMaxHealth() * 0.15, 'incoming_damage'
end

local function Budget(bot, ability, request, c)
	if ability:IsItem() then return true end
	local remaining = bot:GetHealth()
	if K.Form(bot) == 'complete' then
		remaining = remaining * 0.85
		local floor = request.farm and 0.60 or request.emergency and 0.15 or 0.35
		if remaining < bot:GetMaxHealth() * floor then return false, 'health_budget' end
	end
	if request.farm then
		local q = Ability(bot, Q)
		if bot:GetMana() < ability:GetManaCost() + (q and q:GetManaCost() or 160) then return false, 'mana_reserve' end
	end
	local lock = ability:GetName() == Q and ability:GetChannelTime() + ability:GetCastPoint()
		or ability:GetName() == RX and 3 or ability:GetCastPoint() + 0.35
	return Survive(bot, c, math.max(0.5, lock), remaining)
end

local function Point(bot, target, range)
	local origin, location = bot:GetLocation(), target:GetLocation()
	local distance = Geometry.Distance(origin, location)
	if distance < 1 then return location end
	return origin + (location - origin):Normalized() * math.min(range, distance)
end

local function Disabled(unit)
	return unit:IsStunned() or unit:IsHexed() or unit:IsNightmared()
end

local function CountArea(c, point, radius)
	local count = 0
	for _, enemy in ipairs(c.enemies) do
		if not enemy:IsMagicImmune() and Geometry.Distance(point, enemy:GetLocation()) <= radius then count = count + 1 end
	end
	return count
end

local function CountLine(bot, units, point, width, length)
	local origin = bot:GetLocation()
	if Geometry.Distance(origin, point) < 1 then return 0 end
	local finish = origin + (point - origin):Normalized() * length
	local count = 0
	for _, unit in pairs(units) do
		if Valid(bot, unit) and not unit:IsMagicImmune()
		and Geometry.SegmentDistanceToPoint(origin, finish, unit:GetLocation()) <= width then count = count + 1 end
	end
	return count
end

local function FirstTickKills(bot, ability, target)
	local damage = Special(ability, 'damage', 80) * Special(ability, 'burn_interval', 0.5)
	local talent = Ability(bot, 'special_bonus_unique_kasen_7')
	local damageType = DAMAGE_TYPE_MAGICAL
	if talent and talent:GetLevel() > 0 then damage, damageType = damage * 2, DAMAGE_TYPE_PURE end
	return Power.EstimateIncomingDamage(target, damage, damageType, 0) >= target:GetHealth()
end

local function RetryKey(request)
	return request.name .. ':' .. tostring(request.targetID or -1) .. ':' .. request.reason
end

local function RetryBlocked(bot, request)
	return bot.THD_KasenFailedUntil ~= nil and DotaTime() < (bot.THD_KasenFailedUntil[RetryKey(request)] or -90)
end

local function FailRetry(bot, request)
	bot.THD_KasenFailedUntil = bot.THD_KasenFailedUntil or {}
	bot.THD_KasenFailedUntil[RetryKey(request)] = DotaTime() + 0.25
end

local function StatusDetail(bot)
	local active = bot:GetCurrentActiveAbility()
	local phase = active ~= nil and not active:IsNull() and active:IsInAbilityPhase()
	local channel = bot:IsChanneling()
	local absorb = bot:HasModifier(ABSORB)
	local protection = absorb and 'absorb' or channel and 'channel' or phase and 'ability_phase'
		or DotaTime() < (bot.THD_KasenActionUntil or -90) and 'issue_confirmation'
		or Consumables.IsCastConfirmationPending(bot) and 'item_confirmation'
		or J.IsTowerEscapeActive(bot) and 'tower_escape' or SkillMovement.IsActive(bot) and 'skill_escape' or 'none'
	return string.format('mode=%d desire=%.3f action=%d in_phase=%d channel=%d absorb=%d protection=%s',
		bot:GetActiveMode(), bot:GetActiveModeDesire(), bot:GetCurrentActionType(), phase and 1 or 0,
		channel and 1 or 0, absorb and 1 or 0, protection)
end

local function Finish(bot, reason)
	local state = bot.THD_KasenAction
	if state ~= nil then
		K.Log(bot, 'release', reason, state.name, state, StatusDetail(bot))
		if reason ~= 'cast_ended' and reason ~= 'effect_confirmed' and reason ~= 'form_confirmed' then FailRetry(bot, state) end
		-- 仅普通决策服从结束后的总等待；紧急路径使用上面的逐动作失败退避。
		bot.THD_KasenRetry = DotaTime() + 0.25
	end
	bot.THD_KasenAction, bot.THD_KasenActionUntil = nil, nil
end

function K.Update(bot)
	if not K.IsHero(bot) then return nil end
	if not bot:IsAlive() then
		Finish(bot, 'dead'); bot.THD_KasenForm, bot.THD_KasenFollowup, bot.THD_KasenContext = nil, nil, nil
		return nil
	end
	local now, form = DotaTime(), K.Form(bot)
	-- 主包句柄不代表副包恢复冷却已结束；独立记录最近看到的副包物品。
	if now >= (bot.THD_KasenInventoryScan or -90) then
		bot.THD_KasenInventoryScan = now + 0.25
		bot.THD_KasenItemReadyAt = bot.THD_KasenItemReadyAt or {}
		for slot = 6, 8 do
			local item = bot:GetItemInSlot(slot)
			if item ~= nil then bot.THD_KasenItemReadyAt[item:GetName()] = now + 6.25 end
		end
	end
	if bot.THD_KasenForm ~= form then
		bot.THD_KasenForm, bot.THD_KasenFormSince = form, now
		K.Log(bot, 'form', form)
	end
	local state = bot.THD_KasenAction
	if state == nil then return nil end
	local ability = Ability(bot, state.name)
	if state.phase == 'await_mode' then
		if now > state.expires then Finish(bot, 'acquire_timeout'); return nil end
		return state
	end
	-- 实际前摇/引导/自锁优先于任务超时，结束后不保留攻击增益期的锁。
	local live = ability ~= nil and (ability:IsInAbilityPhase() or ability:IsChanneling())
		or (state.name == Q and bot:IsChanneling()) or (state.name == RX and bot:HasModifier(ABSORB))
	-- Ex必须以实际目标形态确认，看到前摇不代表变身已经生效。
	if state.name == EX and form == state.expectedForm then
		K.Log(bot, 'form_confirmed', state.expectedForm, state.name, state)
		state.effectConfirmed = true
	end
	if live then
		if not state.confirmed then K.Log(bot, 'phase_seen', state.name == RX and 'absorb_seen' or 'ability_lifecycle', state.name, state) end
		state.confirmed = true
		state.phase = state.name == RX and 'absorb' or 'casting'
		return state
	end
	if state.name == EX then
		if state.effectConfirmed then Finish(bot, 'form_confirmed'); return nil end
		if state.confirmed then
			-- 允许同帧前摇结束与modifier可见性之间的短确认余量。
			state.phaseEndedAt = state.phaseEndedAt or now
			if now >= state.phaseEndedAt + 0.10 then Finish(bot, 'cast_interrupted_or_unconfirmed'); return nil end
		elseif now > state.confirmUntil then Finish(bot, 'cast_interrupted_or_unconfirmed'); return nil end
		return state
	end
	if state.confirmed then Finish(bot, 'cast_ended'); return nil end
	if now > state.confirmUntil then
		local confirmed = ability ~= nil and ability:GetCooldownTimeRemaining() > 0
			or (state.name == 'item_horse_king' and bot:HasModifier(HORSE) == state.wanted)
		Finish(bot, confirmed and 'effect_confirmed' or 'cast_failed')
		return nil
	end
	return state
end

function K.IsActive(bot) return K.Update(bot) ~= nil end
function K.IsProtected(bot) return K.IsHero(bot) and Actions.KasenProtected(bot) end

local function Offer(bot, name, reason, target, options)
	local ability = Ready(bot, name)
	if ability == nil then return false end
	local request = options or {}
	request.name, request.reason = name, reason
	request.targetID = target and target:GetPlayerID() or nil
	if RetryBlocked(bot, request) then return false end
	local previous = bot.THD_KasenAction
	if previous ~= nil then
		if previous.phase ~= 'await_mode' or previous.emergency or not request.emergency then return false end
		Finish(bot, 'superseded_by_emergency')
	end
	request.phase, request.form = 'await_mode', K.Form(bot)
	request.plannedAt = DotaTime()
	request.expires = request.plannedAt + 0.5
	request.expectedForm = name == EX and (request.form == 'normal' and 'shadow' or 'normal') or nil
	bot.THD_KasenGeneration = (bot.THD_KasenGeneration or 0) + 1
	request.generation = bot.THD_KasenGeneration
	bot.THD_KasenAction = request
	K.Log(bot, 'candidate_created', reason, name, request, StatusDetail(bot))
	return true
end

local function SafeJump(bot, c, point, retreat)
	if bot:IsRooted() or point == nil or not IsLocationPassable(point) then return false end
	local observation = Towers.Observe(bot, 'kasen_jump')
	if not observation.available
	or not Geometry.ValidateMovementSegment(bot:GetLocation(), point, observation.towers, 96, retreat)
	or not Geometry.ValidateLocalTerrainSegment(bot:GetLocation(), point, true) then return false end
	local nearest = math.huge
	local enemies, allies = 0, 1
	for _, enemy in ipairs(c.enemies) do
		local distance = Geometry.Distance(point, enemy:GetLocation())
		nearest = math.min(nearest, distance)
		if distance <= 1000 then enemies = enemies + 1 end
	end
	for _, ally in ipairs(c.allies) do
		if Geometry.Distance(point, ally:GetLocation()) <= 1000 then allies = allies + 1 end
	end
	if retreat then
		-- 允许从塔圈向外逃离，但落点必须真正脱离塔圈，不能停在更远的圈内。
		for _, tower in ipairs(observation.towers) do if Geometry.PointInCircle(point, tower, 96) then return false end end
		return nearest > c.nearest + 100
	end
	return c.localEnemies <= c.localAllies and enemies <= allies
		and bot:GetHealth() / bot:GetMaxHealth() >= 0.55 and SafeAt(bot, point)
end

local function FindTarget(c, id)
	-- 同帧缓存也先确认句柄与视野，不能将刚失效的候选直接用于发单。
	for _, enemy in ipairs(c.enemies) do
		if enemy ~= nil and not enemy:IsNull() and enemy:CanBeSeen() and enemy:IsAlive()
		and enemy:GetPlayerID() == id then return enemy end
	end
	return nil
end

local function JumpControl(bot, c, target, landing)
	if target == nil or target:IsMagicImmune() or Disabled(target) then return nil end
	local w = Ready(bot, W)
	if w and Geometry.Distance(landing, target:GetLocation()) <= w:GetCastRange()
	and Budget(bot, w, {}, c) then return W end
	local q = Ready(bot, Q)
	local follow = false
	for _, ally in ipairs(c.allies) do if GetUnitToUnitDistance(ally, target) <= 700 then follow = true end end
	if q and Geometry.Distance(landing, target:GetLocation()) <= q:GetCastRange()
	and (follow or CountArea(c, target:GetLocation(), q:GetAOERadius()) >= 2)
	and Budget(bot, q, {}, c) then return Q end
	return nil
end

local EvaluateNormalControl

local function Validate(bot, state, c)
	local function Reject(reason) return nil, nil, nil, reason end
	local ability, unavailable = Ready(bot, state.name)
	if ability == nil then return Reject(unavailable) end
	if bot:IsStunned() or bot:IsHexed() or bot:IsNightmared() then return Reject('disabled') end
	if bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling() then return Reject('other_cast') end
	if Consumables.IsCastConfirmationPending(bot) then return Reject('item_confirmation') end
	if J.IsTowerEscapeActive(bot) or SkillMovement.IsActive(bot) then return Reject('safety_owner') end
	local target = state.targetID ~= nil and FindTarget(c, state.targetID) or nil
	if state.targetID ~= nil and target == nil then return Reject('target_lost') end
	if target ~= nil and not ability:IsItem() and state.name ~= EX and target:IsMagicImmune() then return Reject('target_immune') end
	if state.reason == 'interrupt' and (target == nil or not target:IsChanneling() or Disabled(target)) then return Reject('interrupt_ended') end
	if not state.emergency and not state.farm and not ability:IsItem() then
		if c.retreat then return Reject('serious_retreat') end
		if c.localEnemies > c.localAllies then return Reject('numbers_changed') end
	end
	if state.name == Q or state.name == RX or state.name == EX then
		if not SafeAt(bot, bot:GetLocation()) then return Reject('tower_unsafe') end
	end
	if state.name == EX then
		if state.form ~= K.Form(bot) then return Reject('form_changed') end
		if state.form == 'normal' and bot:GetHealth() / bot:GetMaxHealth() < 0.55 then return Reject('entry_health') end
		if state.reason == 'rescue_normal' then
			local q = Ability(bot, Q)
			if target == nil or GetUnitToUnitDistance(bot, target) > 500 then return Reject('range_changed') end
			if q == nil or q:GetLevel() == 0 or not q:IsCooldownReady() or bot:GetMana() < q:GetManaCost() then return Reject('rescue_q_unavailable') end
		end
		if state.reason == 'farm_normal' and (#c.enemies > 0 or #bot:GetNearbyLaneCreeps(1200, true) < 3) then return Reject('farm_changed') end
		if state.reason == 'shadow_commit' then
			local w = Ability(bot, W)
			if target == nil or GetUnitToUnitDistance(bot, target) > 700 then return Reject('range_changed') end
			if w == nil or w:GetLevel() == 0 or not w:IsCooldownReady() or bot:GetMana() < w:GetManaCost() then return Reject('followup_w_unavailable') end
			-- 候选与接管均按同一套实际控制收益复核，不用Q/R单纯就绪挡住影态。
			if EvaluateNormalControl(bot, c, target) ~= nil then return Reject('normal_control_available') end
		end
	end
	local location = state.location
	if state.jump then
		if target ~= nil then
			local range = Special(ability, 'AbilityCastRange', state.name == 'item_nb9ball' and 999 or 499)
			location = Point(bot, target, math.min(range, math.max(0, GetUnitToUnitDistance(bot, target) - 200)))
			if Geometry.Distance(location, target:GetLocation()) > 325 or c.retreat then return Reject('jump_contact_changed') end
			state.followup = JumpControl(bot, c, target, location)
			if state.followup == nil then return Reject('jump_control_unavailable') end
		end
		if not SafeJump(bot, c, location, state.emergency) then return Reject('jump_unsafe') end
	elseif state.kind == 'entity' then
		if target == nil or GetUnitToUnitDistance(bot, target) > ability:GetCastRange() then return Reject('range_changed') end
	elseif state.kind == 'point' and target ~= nil then
		location = Point(bot, target, ability:GetCastRange())
		if state.name == Q then
			if CountArea(c, location, ability:GetAOERadius()) == 0 then return Reject('q_coverage_lost') end
			if state.reason == 'group_control' then
				local follow = false
				for _, ally in ipairs(c.allies) do if GetUnitToUnitDistance(ally, target) <= 700 then follow = true end end
				if not follow and CountArea(c, location, ability:GetAOERadius()) < 2 then return Reject('q_value_lost') end
			end
		elseif CountLine(bot, {target}, location, state.name == R and Special(ability, 'path_radius', 150) or 120,
			state.name == R and Special(ability, 'cast_range', 500) or 1200) == 0 then return Reject('line_coverage_lost') end
		if state.reason == 'team_control' and CountLine(bot, c.enemies, location, Special(ability,'path_radius',150), ability:GetCastRange()) < 2 then return Reject('r_value_lost') end
		if state.reason == 'kill_first_tick' and not FirstTickKills(bot, ability, target) then return Reject('kill_value_lost') end
	end
	if state.farm then
		if #c.enemies > 0 or c.retreat or not SafeAt(bot, bot:GetLocation()) then return Reject('farm_unsafe') end
		if CountLine(bot, bot:GetNearbyLaneCreeps(1200, true), location, 120, 1200) < 3 then return Reject('farm_coverage_lost') end
	end
	if state.name == RX and (not c.pressure or c.nearest > 600) then return Reject('absorb_pressure_lost') end
	if state.name == 'item_horse_king' and bot:HasModifier(HORSE) == state.wanted then return Reject('toggle_already_set') end
	-- 只为通过距离/形态/收益初筛的候选计算详细威胁，避免紧急扫描放大开销。
	local budgetOK, budgetReason = Budget(bot, ability, state, c)
	if not budgetOK then return Reject(budgetReason or 'health_budget') end
	return ability, target, location
end

local function Request(bot, name, reason, unit, options)
	local request = {}
	for key, value in pairs(options or {}) do request[key] = value end
	request.name, request.reason, request.form = name, reason, K.Form(bot)
	request.targetID = unit and unit:GetPlayerID() or nil
	return request
end

EvaluateNormalControl = function(bot, c, target)
	-- 无下单副作用；复用于正常控制选择和Ex接管前复核，紧急控制由快速分支先处理。
	if not Valid(bot, target) or target:IsMagicImmune() then return nil, 'target_invalid', 'target_invalid' end
	local q, qReason = Ready(bot, Q)
	local r, rReason = Ready(bot, R)
	local qRequest, rRequest
	local distance = GetUnitToUnitDistance(bot, target)
	if q then
		qReason = 'no_value'
		if distance <= q:GetCastRange() + q:GetAOERadius() then
			local follow = false
			for _, ally in ipairs(c.allies) do if GetUnitToUnitDistance(ally, target) <= 700 then follow = true end end
			if follow or CountArea(c, Point(bot, target, q:GetCastRange()), q:GetAOERadius()) >= 2 then
				local candidate = Request(bot, Q, 'group_control', target, {kind='point'})
				local ability, _, _, rejected = Validate(bot, candidate, c)
				if ability then qRequest, qReason = candidate, 'group_control' else qReason = rejected end
			end
		else qReason = 'out_of_range' end
	end
	if r then
		rReason = 'no_value'
		if distance <= r:GetCastRange() then
			local kill = FirstTickKills(bot, r, target)
			if kill or CountLine(bot, c.enemies, target:GetLocation(), Special(r,'path_radius',150), r:GetCastRange()) >= 2 then
				local candidate = Request(bot, R, kill and 'kill_first_tick' or 'team_control', target, {kind='point'})
				local ability, _, _, rejected = Validate(bot, candidate, c)
				if ability then rRequest, rReason = candidate, candidate.reason else rReason = rejected end
			end
		else rReason = 'out_of_range' end
	end
	return rRequest or qRequest, qReason, rReason
end

function K.GetDesire(bot)
	local state = K.Update(bot)
	if state == nil then return K.IsProtected(bot) and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE end
	if state.phase ~= 'await_mode' then return BOT_MODE_DESIRE_ABSOLUTE end
	if J.IsTowerEscapeActive(bot) or SkillMovement.IsActive(bot) then Finish(bot, 'safety_owner'); return BOT_MODE_DESIRE_NONE end
	return state.emergency and BOT_MODE_DESIRE_ABSOLUTE or 0.98
end

function K.Think(bot)
	local state = K.Update(bot)
	if state == nil then return K.IsProtected(bot) end
	if state.phase ~= 'await_mode' then return true end
	if bot:GetActiveMode() ~= BOT_MODE_EVASIVE_MANEUVERS then return true end
	state.acquiredAt = state.acquiredAt or DotaTime()
	K.Log(bot, 'mode_acquired', state.reason, state.name, state, StatusDetail(bot))
	local ability, target, location, rejected = Validate(bot, state, Context(bot))
	if ability == nil then Finish(bot, rejected or 'mission_or_safety_changed'); return true end
	local now = DotaTime()
	state.phase = 'issued'
	state.issuedAt = now
	state.confirmUntil = now + ability:GetCastPoint() + 0.35
	state.expires = state.confirmUntil + (state.name == Q and ability:GetChannelTime() or state.name == RX and 3 or 0)
	bot.THD_KasenActionUntil = state.confirmUntil
	-- 取得模式后清除旧队列，再只提交一次技能/物品；已开始的生命周期不走这里。
	bot:Action_ClearActions(false)
	Actions.Forget(bot)
	if state.kind == 'entity' then bot:Action_UseAbilityOnEntity(ability, target)
	elseif state.kind == 'point' then bot:Action_UseAbilityOnLocation(ability, location)
	else bot:Action_UseAbility(ability) end
	if state.jump and state.followup then
		bot.THD_KasenFollowup = {name=state.followup, targetID=state.targetID, expires=now+1.5}
	end
	K.Log(bot, 'order', state.reason, state.name)
	return true
end

function K.OnEnd(bot)
	local state = K.Update(bot)
	if state == nil then return false end
	if state.phase == 'await_mode' then Finish(bot, 'mode_lost') end
	return true
end

local function DefensiveItems(bot, Cast, emergency)
	for _, pair in ipairs({{'item_trinity','modifier_item_trinity_active_shield'}, {'item_esdw','modifier_item_esdw_active_shield'},
		{'item_flower_umbrella','modifier_item_flower_umbrella_spellstart_buff'}, {'item_dragon_star','modifier_item_dragon_star_buff'}}) do
		if not bot:HasModifier(pair[2]) and Cast(pair[1], 'defensive_item', nil, {emergency=emergency}) then return true end
	end
	return false
end

local function Emergency(bot, c, Cast)
	local q, w, r = Ready(bot, Q), Ready(bot, W), Ready(bot, R)
	-- 紧急路径只扫可见英雄和已具备的控制；不做清线、变身收益或库存整理。
	for _, enemy in ipairs(c.enemies) do
		if enemy:IsChanneling() and not enemy:IsMagicImmune() and not Disabled(enemy) then
			local distance = GetUnitToUnitDistance(bot, enemy)
			if w and distance <= w:GetCastRange() and Cast(W, 'interrupt', enemy, {kind='entity', emergency=true}) then return true end
			if q and distance <= q:GetCastRange()+q:GetAOERadius() and Cast(Q, 'interrupt', enemy, {kind='point', emergency=true}) then return true end
			if r and distance <= r:GetCastRange() and Cast(R, 'interrupt', enemy, {kind='point', emergency=true}) then return true end
		end
	end
	local threatened
	for _, enemy in ipairs(c.enemies) do
		local attacked = enemy:GetAttackTarget()
		if attacked == bot and c.retreat then threatened = enemy end
		for _, ally in ipairs(c.allies) do
			if attacked == ally and ally:GetHealth()/ally:GetMaxHealth() < 0.5 then threatened = enemy end
		end
	end
	if threatened and not threatened:IsMagicImmune() then
		local distance = GetUnitToUnitDistance(bot, threatened)
		if w and not Disabled(threatened) and distance <= w:GetCastRange() and Cast(W, 'rescue', threatened, {kind='entity', emergency=true}) then return true end
		if q and distance <= q:GetCastRange()+q:GetAOERadius() and Cast(Q, 'rescue', threatened, {kind='point', emergency=true}) then return true end
		if r and distance <= r:GetCastRange() and Cast(R, 'rescue', threatened, {kind='point', emergency=true}) then return true end
	end
	local pressured = c.pressure and c.nearest <= 1000 and bot:GetHealth()/bot:GetMaxHealth() < 0.70
	if pressured and DefensiveItems(bot, Cast, true) then return true end
	if c.pressure and c.nearest <= 600 and Cast(RX, 'absorb_pressure', nil, {emergency=true}) then return true end
	if c.retreat and c.pressure and c.nearest <= 800 and not bot:HasModifier('modifier_thdots_kasen04ex_WBC')
	and Cast(GAZE, 'stone_gaze', nil, {emergency=true}) then return true end
	local jump = Ready(bot, 'item_nb9ball') or Ready(bot, 'item_wanmeitiaoyuezhuangzhi')
	if c.retreat and c.pressure and c.target and not bot:IsRooted() then
		if jump then
			local ancient = GetAncient(bot:GetTeam())
			if ancient then
				local range = Special(jump, 'AbilityCastRange', jump:GetName() == 'item_nb9ball' and 999 or 499)
				local location = Point(bot, ancient, range)
				if Cast(jump:GetName(), 'escape_jump', nil, {kind='point', location=location, jump=true, emergency=true}) then return true end
			end
		elseif c.nearest <= 350 and bot:GetHealth()/bot:GetMaxHealth() < 0.25
		and Cast('item_9ball', 'last_resort_jump', nil, {emergency=true}) then return true end
	end
	if K.Form(bot) == 'shadow' and threatened and not threatened:IsMagicImmune() then
		local learnedQ = Ability(bot, Q)
		if learnedQ and learnedQ:GetLevel() > 0 and learnedQ:IsCooldownReady()
		and bot:GetMana() >= learnedQ:GetManaCost() and GetUnitToUnitDistance(bot, threatened) <= 500
		and Cast(EX, 'rescue_normal', threatened, {emergency=true}) then return true end
	end
	return false
end

local function FormOpportunity(bot, c, target, reason, qReason, rReason)
	local id = target and target:GetPlayerID() or -1
	local key = tostring(id)..':'..reason..':'..tostring(qReason)..':'..tostring(rReason)
	local now = DotaTime()
	if bot.THD_KasenOpportunityKey == key and now < (bot.THD_KasenOpportunityAt or -90)+1 then return end
	bot.THD_KasenOpportunityKey, bot.THD_KasenOpportunityAt = key, now
	local w, ex = Ability(bot, W), Ability(bot, EX)
	K.Log(bot, 'form_opportunity', reason, EX, {}, string.format('target=%d q_value=%s r_value=%s hp=%.3f enemies=%d allies=%d distance=%.1f w_cd=%.2f ex_cd=%.2f',
		id, qReason or 'none', rReason or 'none', bot:GetHealth()/bot:GetMaxHealth(), c.localEnemies, c.localAllies,
		target and GetUnitToUnitDistance(bot, target) or -1, w and w:GetCooldownTimeRemaining() or -1, ex and ex:GetCooldownTimeRemaining() or -1))
end

function K.Consider(bot)
	if not K.IsHero(bot) then return false end
	local state = K.Update(bot)
	-- 待接管的普通候选可被紧急候选替换，已下单的生命周期绝不覆盖。
	if (state ~= nil and state.phase ~= 'await_mode') or K.IsProtected(bot) then return true end
	if not bot:IsAlive() or bot:IsHexed() or bot:IsStunned() or bot:IsNightmared()
	or J.CanNotUseAction(bot) or SkillMovement.IsActive(bot) then return true end
	if Consumables.IsCastConfirmationPending(bot) or DotaTime() < (bot.THD_KasenInventoryUntil or -90) then return true end
	local now = DotaTime()
	local urgentDue = now >= (bot.THD_KasenNextUrgent or -90)
	local normalDue = state == nil and now >= (bot.THD_KasenNextScan or -90) and now >= (bot.THD_KasenRetry or -90)
	if not urgentDue and not normalDue then return state ~= nil end
	local c, form = Context(bot), K.Form(bot)
	if #c.enemies > 0 then bot.THD_KasenLastContact = now end
	local stats = bot.THD_KasenScanStats or {urgent=0, normal=0, startedAt=now, nextLog=now+15}
	bot.THD_KasenScanStats = stats
	local function Submit(request)
		request.observedAt = request.observedAt or c.at
		if RetryBlocked(bot, request) then return false, 'retry_wait' end
		local ability, target, _, rejected = Validate(bot, request, c)
		if ability == nil then
			FailRetry(bot, request)
			K.Log(bot, 'reject', rejected, request.name, {}, 'target='..tostring(request.targetID or -1)..' intent='..request.reason)
			return false, rejected
		end
		return Offer(bot, request.name, request.reason, target, request)
	end
	local function Cast(name, reason, unit, options)
		local request = Request(bot, name, reason, unit, options)
		request.observedAt = c.at
		if request.emergency then
			-- 首次观察只代表本Bot见到该条件的时间，不代表敌人真实起手时间。
			bot.THD_KasenUrgentObserved = bot.THD_KasenUrgentObserved or {}
			local key = request.form .. ':' .. RetryKey(request)
			local observed = bot.THD_KasenUrgentObserved[key]
			if observed == nil or now-observed.lastAt > 0.25 then observed = {firstAt=now} end
			observed.lastAt = now
			bot.THD_KasenUrgentObserved[key] = observed
			request.observedAt = observed.firstAt
		end
		local ability, unavailable = Ready(bot, name)
		if ability == nil then return false, unavailable end
		return Submit(request)
	end
	if urgentDue then
		bot.THD_KasenNextUrgent = now + 0.10
		stats.urgent = stats.urgent + 1
		-- 已有紧急候选保留原plannedAt，不靠反复替换延长0.5秒接管期限。
		if (state == nil or not state.emergency) and Emergency(bot, c, Cast) then return true end
	end
	if state ~= nil or not normalDue then return state ~= nil end
	bot.THD_KasenNextScan = now + 0.20
	stats.normal = stats.normal + 1
	if now >= stats.nextLog then
		K.Log(bot, 'scan_counts', 'interval', nil, {}, string.format('urgent_scans=%d normal_scans=%d window_s=%.2f',stats.urgent,stats.normal,now-stats.startedAt))
		stats.urgent, stats.normal, stats.startedAt, stats.nextLog = 0, 0, now, now+15
	end
	c.combat = J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200) or c.pressure
	local target = c.target
	local followup = bot.THD_KasenFollowup
	if followup ~= nil then
		bot.THD_KasenFollowup = nil
		local enemy = FindTarget(c, followup.targetID)
		if now <= followup.expires and not c.retreat and SafeAt(bot, bot:GetLocation()) and enemy ~= nil
		and JumpControl(bot, c, enemy, bot:GetLocation()) == followup.name
		and Cast(followup.name, followup.name == Q and 'group_control' or 'chase', enemy,
			{kind=followup.name == Q and 'point' or 'entity'}) then return true end
	end
	-- Q/R的实际收益优先；没有可执行控制才评估影态，普通三技能消耗排在变身之后。
	if c.combat and target and not target:IsMagicImmune() then
		local control, qReason, rReason = EvaluateNormalControl(bot, c, target)
		if control ~= nil then
			if form == 'normal' then FormOpportunity(bot,c,target,'normal_control_available',qReason,rReason) end
			if Submit(control) then return true end
		end
		if form == 'normal' and control == nil then
			local changed, rejected = Cast(EX, 'shadow_commit', target)
			FormOpportunity(bot,c,target,changed and 'shadow_candidate' or (rejected or 'shadow_rejected'),qReason,rReason)
			if changed then return true end
		end
	end
	local commit = c.combat and not c.retreat and c.localEnemies >= 2 and c.localEnemies <= c.localAllies
	if commit and DefensiveItems(bot, Cast, false) then return true end
	if c.localEnemies >= 2 and c.combat and not bot:HasModifier('modifier_thdots_kasen04ex_WBC')
	and Cast(GAZE, 'stone_gaze', nil) then return true end
	local q, w = Ready(bot, Q), Ready(bot, W)
	local jump = Ready(bot, 'item_nb9ball') or Ready(bot, 'item_wanmeitiaoyuezhuangzhi')
	if jump and not bot:IsRooted() and c.combat and not c.retreat and target and not target:IsMagicImmune() and (q or w) then
		local range = Special(jump, 'AbilityCastRange', jump:GetName() == 'item_nb9ball' and 999 or 499)
		local distance = GetUnitToUnitDistance(bot, target)
		if distance > 550 and distance <= range + 200
		and Cast(jump:GetName(), 'control_jump', target, {kind='point', jump=true}) then return true end
	end
	local horse = Ready(bot, 'item_horse_king')
	if horse then
		local reserve = (Ability(bot, Q) and Ability(bot, Q):GetManaCost() or 160) + 100
		local wanted = (c.combat or c.retreat) and c.nearest <= 1000 and bot:GetMana() > reserve
		if wanted ~= bot:HasModifier(HORSE) and Cast(horse:GetName(), 'horse_toggle', nil, {wanted=wanted}) then return true end
	end
	if form == 'shadow' and Ready(bot, EX) then
		local learnedE = Ability(bot, E)
		local quiet = now-(bot.THD_KasenFormSince or now) >= 6 and now-(bot.THD_KasenLastContact or -90) >= 3
			and learnedE and learnedE:GetLevel() > 0 and #bot:GetNearbyLaneCreeps(1200,true) >= 3
		if quiet and Cast(EX,'farm_normal',nil) then return true end
	end
	if c.combat and target and not target:IsMagicImmune() then
		local distance = GetUnitToUnitDistance(bot, target)
		if w and distance <= w:GetCastRange() and not Disabled(target) then
			local damage = Power.EstimateIncomingDamage(target,Special(w,'stone_damage',100),DAMAGE_TYPE_MAGICAL,0)
			if Cast(W,damage >= target:GetHealth() and 'kill' or 'chase',target,{kind='entity',emergency=c.retreat}) then return true end
		end
		if distance <= 1200 and Cast(E,'combat_wave',target,{kind='point'}) then return true end
	end
	if #c.enemies == 0 and not c.retreat and Ready(bot,E) and SafeAt(bot,bot:GetLocation()) then
		local creeps = bot:GetNearbyLaneCreeps(1200,true)
		for _, creep in pairs(creeps) do
			if Valid(bot,creep) and CountLine(bot,creeps,creep:GetLocation(),120,1200) >= 3
			and Cast(E,'wave_clear',nil,{kind='point',location=creep:GetLocation(),farm=true}) then return true end
		end
	end
	-- 只有普通决策轮允许中立物品兜底，移除外层节流后也不会变为逐帧下单。
	return false, true
end

return K
