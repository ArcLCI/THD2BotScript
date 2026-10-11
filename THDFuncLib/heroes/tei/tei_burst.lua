-- 团战准备事务：整段持有动作权，每次回调确认上一项并推进；不排可被覆盖的长队列。
local Actions = require(GetScriptDirectory() .. '/THDFuncLib/action_intent')
local SkillMovement = require(GetScriptDirectory() .. '/THDFuncLib/modes/evasive/skill_avoidance')
local B = {}
local RUN = 'TEI-BURST-R8-20261011'
local R_BUFF = 'modifier_ability_thdots_tei04'
local E_BUFF = 'modifier_ability_thdots_tei03'
local ACQUIRE_TIMEOUT = 0.5
local PREPARE_TIMEOUT = 4.0
local COMBAT_GRACE = 2.0

local function ValidHandle(handle)
	return handle ~= nil and not handle:IsNull()
end

local function Ready(handle)
	return ValidHandle(handle) and handle:GetLevel() > 0 and handle:IsFullyCastable()
end

local function Remaining(bot, name)
	for index = 0, bot:NumModifiers() - 1 do
		if bot:GetModifierName(index) == name then return bot:GetModifierRemainingDuration(index) end
	end
	return 0
end

local function Item(bot, name)
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if ValidHandle(item) and item:GetName() == name then return item end
	end
	return nil
end

local function Casting(bot, step)
	return bot:IsCastingAbility() or bot:IsChanneling()
		or (step ~= nil and ValidHandle(step.handle)
			and (step.handle:IsInAbilityPhase() or step.handle:IsChanneling()))
end

local function Log(bot, state, event, reason, step)
	print(string.format('[BOT][TeiBurst] run=%s team=%d player=%d sequence=%d event=%s phase=%s flow=%s step=%s reason=%s callbacks=%d max_gap=%.3f game_time=%.3f',
		RUN, bot:GetTeam(), bot:GetPlayerID(), state.sequence, event, state.phase, state.flow or 'prepare',
		step and step.name or 'none', reason or 'none', state.callbacks or 0, state.maxGap or 0, DotaTime()))
end

local function Finish(bot, state, success, reason)
	Log(bot, state, success and (state.flow=='supplement' and 'followup_done' or 'ready') or 'abort', reason)
	bot.THD_TeiBurst = nil
	bot.THD_TeiBurstRetryAt = DotaTime() + (success and 0.5 or 1.0)
	if state.flow == 'supplement' then
		bot.THD_TeiSupplementRetryAt = success and -90 or DotaTime()+0.8
		local combat = bot.THD_TeiCombat
		if combat ~= nil and success then
			combat.lastCombatAt = DotaTime()
			combat.teethUsed = combat.teethUsed or state.teethConfirmed == true
		end
	end
	if success then
		bot.THD_TeiBurstReleasedAt = DotaTime()
		local window = 5.0
		for _, name in ipairs({R_BUFF, E_BUFF}) do
			if state.requiredBuffs[name] then window = math.min(window, Remaining(bot, name)) end
		end
		bot.THD_TeiBurstReady = {untilTime=DotaTime()+math.max(0, window-0.15), requiredBuffs=state.requiredBuffs}
		bot.THD_TeiHorseHoldUntil = bot.THD_TeiBurstReady.untilTime
		if state.flow ~= 'supplement' then
			-- 输出期不持有动作锁，未用乳牙时允许独立后补，不重新跑整套准备。
			bot.THD_TeiCombat = {lastCombatAt=DotaTime(), teethUsed=state.teethConfirmed == true
				or bot:HasModifier('modifier_item_teeth_berserk_buff'), target=state.target}
		end
	elseif state.flow ~= 'supplement' then
		bot.THD_TeiBurstReady = nil
		bot.THD_TeiCombat = nil
	end
end

function B.InCombat(bot)
	local combat = bot and bot.THD_TeiCombat
	return combat ~= nil and bot:IsAlive() and DotaTime()-combat.lastCombatAt <= COMBAT_GRACE
end

function B.RefreshCombat(bot, target, engaged, retreat)
	local combat = bot.THD_TeiCombat
	if combat == nil then return false end
	if retreat or not bot:IsAlive() then
		bot.THD_TeiCombat, bot.THD_TeiBurstReady = nil, nil
		return false
	end
	if engaged and Actions.ValidTarget(target) and GetUnitToUnitDistance(bot,target)<=1300 then
		combat.lastCombatAt, combat.target = DotaTime(), target
	end
	if not B.InCombat(bot) then bot.THD_TeiCombat,bot.THD_TeiBurstReady=nil,nil;return false end
	-- 以实际沉默状态决定能否补技能；持有乳牙或以前开过乳牙都不等于一直沉默。
	combat.stage = bot:IsSilenced() and 'silenced' or 'open'
	combat.teethUsed = combat.teethUsed or bot:HasModifier('modifier_item_teeth_berserk_buff')
	return true
end

function B.IsReady(bot)
	local ready = bot and bot.THD_TeiBurstReady
	if ready == nil or not bot:IsAlive() or DotaTime() >= ready.untilTime then return false end
	for name in pairs(ready.requiredBuffs) do
		if not bot:HasModifier(name) then return false end
	end
	return true
end

function B.IsActive(bot) return bot ~= nil and bot.THD_TeiBurst ~= nil end

function B.TimeRemaining(bot)
	if not B.IsReady(bot) then return 0 end
	return math.max(0,bot.THD_TeiBurstReady.untilTime-DotaTime())
end

function B.Start(bot, target, validate, guaranteedMooncake, owner)
	if B.IsActive(bot) or B.InCombat(bot) or B.IsReady(bot) or DotaTime() < (bot.THD_TeiBurstRetryAt or -90) then return false end
	if bot.THD_TeiBackstep ~= nil or SkillMovement.IsActive(bot) or bot:IsSilenced() or bot:IsDisarmed() or Actions.Protected(bot,owner) then return false end
	if not validate(bot, target) then return false end
	local q = bot:GetAbilityByName('ability_thdots_tei01')
	local e = bot:GetAbilityByName('ability_thdots_tei03')
	local r = bot:GetAbilityByName('ability_thdots_tei04')
	local w = bot:GetAbilityByName('ability_thdots_tei02')
	local willR = bot:HasModifier(R_BUFF) or Ready(r)
	local willE = bot:HasModifier(E_BUFF) or Ready(e)
	if not willR and not willE then return false end
	local reserve = ValidHandle(w) and w:GetLevel() > 0 and w:GetManaCost() or 50
	local coreCost = (not bot:HasModifier(R_BUFF) and Ready(r) and r:GetManaCost() or 0)
		+ (not bot:HasModifier(E_BUFF) and Ready(e) and e:GetManaCost() or 0)
	if bot:GetMana() < reserve + coreCost then return false end
	local useQ = Ready(q) and (willR or guaranteedMooncake) and bot:GetMana() >= reserve + coreCost + q:GetManaCost()
	local qCost = useQ and q:GetManaCost() or 0
	local steps, requiredBuffs = {}, {}
	local function Add(handle, buff, isItem)
		if not ValidHandle(handle) then return end
		if buff ~= nil and bot:HasModifier(buff) then
			-- 已有核心增益也要在流程结束时复核，不能拿快结束的旧增益冒充新爆发。
			if buff == R_BUFF or buff == E_BUFF then requiredBuffs[buff] = true end
			table.insert(steps, {handle=handle, name=handle:GetName(), buff=buff, isItem=isItem})
			return
		end
		if not Ready(handle) or (isItem and bot:IsMuted()) then return end
		table.insert(steps, {handle=handle, name=handle:GetName(), buff=buff, isItem=isItem})
		if buff == R_BUFF or buff == E_BUFF then requiredBuffs[buff] = true end
	end
	if bot:GetMana() > reserve + coreCost + qCost + 100 then Add(Item(bot, 'item_horse_king'), 'modifier_item_horse_king_open', true) end
	Add(r, R_BUFF, false)
	if useQ then Add(q, nil, false) end
	Add(e, E_BUFF, false)
	Add(Item(bot, 'item_trinity'), 'modifier_item_trinity_active_shield', true)
	Add(Item(bot, 'item_dragon_star'), 'modifier_item_dragon_star_buff', true)
	-- 乳牙最后开启；冷却中的E/R不能满足乳牙前置条件。
	if willR and willE then Add(Item(bot, 'item_teeth'), 'modifier_item_teeth_berserk_buff', true) end
	if #steps == 0 then return false end
	bot.THD_TeiBurstSequence = (bot.THD_TeiBurstSequence or 0) + 1
	local state = {sequence=bot.THD_TeiBurstSequence, phase='await_mode', target=target,
		steps=steps, index=1, requiredBuffs=requiredBuffs, reserve=reserve, validate=validate,
		expires=DotaTime()+ACQUIRE_TIMEOUT, callbacks=0, maxGap=0}
	local hasWork = false
	for _, step in ipairs(steps) do
		if step.buff == nil or not bot:HasModifier(step.buff) then hasWork = true; break end
	end
	if not hasWork then
		for name in pairs(requiredBuffs) do if Remaining(bot,name)<1 then return false end end
		-- 已有全部效果时只续认输出窗口，不停下正在进行的攻击。
		Finish(bot,state,true,'already_active')
		return false
	end
	bot.THD_TeiBurst = state
	bot.THD_TeiBurstReady = nil
	-- 只在开始时停止旧的普通动作；调用方和上方保护确保没有正在施法或待确认道具。
	bot:Action_ClearActions(true)
	Actions.Forget(bot)
	Log(bot, state, 'begin', 'snapshot_ready_actions')
	return true
end

function B.Supplement(bot, target, handle, buff, isItem, validate, reserve)
	if not B.InCombat(bot) or B.IsActive(bot) or DotaTime() < (bot.THD_TeiSupplementRetryAt or -90) then return false end
	if not Ready(handle) or SkillMovement.IsActive(bot) or Actions.Protected(bot) or not validate(bot,target) then return false end
	if (not isItem and bot:IsSilenced()) or (isItem and bot:IsMuted()) then return false end
	if buff ~= nil and bot:HasModifier(buff) then return false end
	local reserveMana = reserve or 50
	if bot:GetMana() < handle:GetManaCost()+reserveMana then return false end
	bot.THD_TeiBurstSequence = (bot.THD_TeiBurstSequence or 0)+1
	local required = {}
	if buff == R_BUFF or buff == E_BUFF then required[buff]=true end
	local state = {sequence=bot.THD_TeiBurstSequence, flow='supplement', phase='await_mode',
		target=target, steps={{handle=handle,name=handle:GetName(),buff=buff,isItem=isItem}},
		index=1, requiredBuffs=required, reserve=reserveMana, validate=validate,
		expires=DotaTime()+ACQUIRE_TIMEOUT, callbacks=0, maxGap=0}
	bot.THD_TeiBurst=state
	-- 每次后补仅保护一项，确认后立即放回输出，不串成第二套全量准备。
	bot:Action_ClearActions(true)
	Actions.Forget(bot)
	Log(bot,state,'followup_begin','single_ready_action',state.steps[1])
	return true
end

function B.Update(bot)
	local state = bot and bot.THD_TeiBurst
	if state == nil then return false end
	local now = DotaTime()
	state.callbacks = state.callbacks + 1
	if state.lastCallbackAt ~= nil then state.maxGap = math.max(state.maxGap, now-state.lastCallbackAt) end
	state.lastCallbackAt = now
	if not bot:IsAlive() then Finish(bot, state, false, 'dead'); return true end
	local pending = state.pending
	-- 先处理当前施法生命周期。危险可要求终止整套准备，但不靠新命令截断真实前摇。
	if now > state.expires then state.abortReason = state.phase == 'await_mode' and 'acquire_timeout' or 'prepare_timeout' end
	if pending ~= nil and Casting(bot, pending) then return true end
	if pending ~= nil then
		if not ValidHandle(pending.handle) then Finish(bot, state, false, 'pending_handle_lost'); return true end
		local confirmed = pending.buff ~= nil and bot:HasModifier(pending.buff)
			or pending.buff == nil and pending.handle:GetCooldownTimeRemaining() > pending.beforeCooldown
		if not confirmed then
			if now > pending.confirmUntil then
				-- 确认失败只撤销仍属于本步骤的未启动命令，不让它在解锁后迟到执行。
				if bot:GetCurrentActiveAbility() == pending.handle then bot:Action_ClearActions(true); Actions.Forget(bot) end
				Finish(bot, state, false, state.abortReason or 'confirmation_timeout')
			end
			return true
		end
		Log(bot, state, 'confirmed', pending.buff and 'modifier_present' or 'cooldown_changed', pending)
		if pending.name == 'item_teeth' then state.teethConfirmed = true end
		state.pending = nil
		state.index = state.index + 1
		state.phase = 'prepare'
	end
	if state.abortReason ~= nil then Finish(bot, state, false, state.abortReason); return true end
	-- 单项已确认即交还输出，即使随后被控制也不把已成功的后补记成失败。
	if state.flow == 'supplement' and state.index > #state.steps then
		Finish(bot,state,true,'single_action_confirmed');return true
	end
	if bot:IsHexed() or bot:IsStunned() or bot:IsNightmared() or bot:IsDisarmed()
	or not state.validate(bot, state.target) then Finish(bot, state, false, 'target_or_safety_changed'); return true end
	if Casting(bot) then return true end
	if bot:GetActiveMode() ~= BOT_MODE_EVASIVE_MANEUVERS then return true end
	if state.phase == 'await_mode' then
		state.phase = 'prepare'
		state.expires = now + (state.flow=='supplement' and 2.0 or PREPARE_TIMEOUT)
		Log(bot, state, 'acquired', 'mode_committed')
	end
	-- 跳过已经存在的效果不空等下一回调；每个游戏时间点最多提交一个新动作。
	while state.index <= #state.steps do
		local step = state.steps[state.index]
		if step.buff ~= nil and bot:HasModifier(step.buff) then
			Log(bot, state, 'confirmed', 'already_active', step)
			state.index = state.index + 1
		else
			if state.lastIssueAt == now then return true end
			if not Ready(step.handle) or (step.isItem and (bot:IsMuted() or Item(bot, step.name) ~= step.handle))
			or (not step.isItem and bot:IsSilenced()) then Finish(bot, state, false, 'planned_action_unavailable'); return true end
			if step.name == 'item_teeth' and (Remaining(bot, R_BUFF) < 1 or Remaining(bot, E_BUFF) < 1) then
				Finish(bot, state, false, 'teeth_missing_core_buffs'); return true
			end
			if step.name == 'ability_thdots_tei01' and not bot:HasModifier(R_BUFF) then
				local guaranteed = false
				for index=0,bot:NumModifiers()-1 do
					if bot:GetModifierName(index)=='modifier_ability_thdots_tei01_count' and bot:GetModifierStackCount(index)>=2 then guaranteed=true;break end
				end
				if not guaranteed then Finish(bot, state, false, 'mooncake_not_safe'); return true end
			end
			local needed = state.reserve
			for index=state.index,#state.steps do
				local future = state.steps[index]
				if not ValidHandle(future.handle) then Finish(bot,state,false,'planned_handle_lost');return true end
				if future.buff == nil or not bot:HasModifier(future.buff) then needed=needed+future.handle:GetManaCost() end
			end
			if bot:GetMana() < needed then Finish(bot, state, false, 'mana_reserve'); return true end
			step.beforeCooldown = step.handle:GetCooldownTimeRemaining()
			step.confirmUntil = now + math.max(0,step.handle:GetCastPoint()) + 0.8
			state.pending = step
			state.phase = 'confirm'
			state.lastIssueAt = now
			bot:Action_UseAbility(step.handle)
			Actions.NoteIssued(bot, 'tei_burst_cast')
			Log(bot, state, 'issued', 'next_step', step)
			return true
		end
	end
	for name in pairs(state.requiredBuffs) do
		if Remaining(bot, name) < 1 then Finish(bot, state, false, 'core_buff_expired'); return true end
	end
	Finish(bot, state, true, 'all_planned_actions_confirmed')
	return true
end

function B.GetDesire(bot)
	local state = bot and bot.THD_TeiBurst
	if state == nil then return BOT_MODE_DESIRE_NONE end
	if not bot:IsAlive() then Finish(bot,state,false,'dead');return BOT_MODE_DESIRE_NONE end
	if DotaTime() > state.expires then
		-- 到期也先收完本步骤的确认，绝不在待确认道具中间直接解锁。
		B.Update(bot)
		if bot.THD_TeiBurst == nil then return BOT_MODE_DESIRE_NONE end
	end
	return BOT_MODE_DESIRE_ABSOLUTE + 0.01
end

function B.OnEnd(bot)
	local state = bot and bot.THD_TeiBurst
	if state == nil then return false end
	state.abortReason = 'mode_lost'
	if not Casting(bot,state.pending) and state.pending == nil then Finish(bot,state,false,'mode_lost') end
	return true
end

return B
