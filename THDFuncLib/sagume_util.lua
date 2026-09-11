local C = require(GetScriptDirectory()..'/THDFuncLib/sagume_config')
local Profile = require(GetScriptDirectory()..'/THDFuncLib/bot_profile')
local U = {}

function U.Safe(default, fn)
	local ok, value = pcall(fn)
	if ok and value ~= nil then return value end
	return default
end
function U.Now() return U.Safe(0, DotaTime) end
function U.Finite(v) return type(v) == 'number' and v == v and math.abs(v) < math.huge end
function U.Copy(p) return p and Vector(p.x, p.y, p.z or 0) or nil end
function U.Distance(a, b)
	if a == nil or b == nil then return math.huge end
	return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end
function U.Valid(unit)
	return unit ~= nil and U.Safe(false, function()
		return not unit:IsNull() and unit:IsAlive() and unit:CanBeSeen()
	end)
end
function U.Has(unit, name)
	return U.Valid(unit) and U.Safe(false, function() return unit:HasModifier(name) end)
end
function U.Remaining(unit, name)
	if not U.Has(unit, name) then return 0 end
	return U.Safe(math.huge, function()
		local index = unit:GetModifierByName(name)
		if index < 0 then return math.huge end
		local remaining = unit:GetModifierRemainingDuration(index)
		return remaining < 0 and math.huge or remaining
	end)
end
function U.Ability(unit, name)
	if not U.Valid(unit) then return nil end
	return U.Safe(nil, function() return unit:GetAbilityByName(name) end)
end
function U.Level(a) return a and U.Safe(0, function() return a:GetLevel() end) or 0 end
function U.Mana(a) return a and U.Safe(math.huge, function() return a:GetManaCost() end) or math.huge end
function U.CastPoint(a) return a and math.max(0, U.Safe(0.4, function() return a:GetCastPoint() end)) or 0 end
function U.Special(a, key, fallback)
	if a == nil then return fallback end
	local value = U.Safe(nil, function() return a:GetSpecialValueFloat(key) end)
	return U.Finite(value) and value ~= 0 and value or fallback
end
function U.Cooldown(a)
	if a == nil then return nil end
	-- 2019 API：剩余冷却仅对自己/友方有效，所有调用在这里强制检查阵营。
	return U.Safe(nil, function()
		local caster = a:GetCaster()
		if not U.Valid(caster) or caster:GetTeam() ~= GetBot():GetTeam() then return nil end
		local cd = a:GetCooldownTimeRemaining()
		return U.Finite(cd) and math.max(0, cd) or nil
	end)
end
function U.Castable(a)
	return a ~= nil and U.Safe(false, function() return a:IsFullyCastable() and not a:IsHidden() end)
end
function U.Busy(bot)
	return U.Safe(true, function()
		return not bot:IsAlive() or bot:IsUsingAbility() or bot:IsCastingAbility() or bot:IsChanneling()
			or bot:IsStunned() or bot:IsHexed() or bot:HasModifier('modifier_teleporting')
	end)
end
function U.Item(bot, name, includeBackpack)
	for slot = 0, includeBackpack and 14 or 5 do
		local item = U.Safe(nil, function() return bot:GetItemInSlot(slot) end)
		if item and U.Safe('', function() return item:GetName() end) == name then return item end
	end
	return nil
end
function U.Profile(bot)
	return bot.THD_SagumePurchaseProfile or Profile.GetProfileOrDefault(bot, 'damage')
end
function U.State(bot)
	if bot.THD_Sagume == nil then
		bot.THD_Sagume = {generation = 0, retryAt = 0, lastR = -90, lastW = -90, logs = {}, observations = {}}
	end
	return bot.THD_Sagume
end
function U.Log(bot, event, fields, throttle)
	if not C.DIAGNOSTICS then return end
	local state, now = U.State(bot), U.Now()
	local key = event..':'..tostring(fields and fields.reason or '')
	if now < (state.logs[key] or -90) then return end
	state.logs[key] = now + (throttle or 0)
	local parts = {}
	for k,v in pairs(fields or {}) do parts[#parts+1] = tostring(k)..'='..string.gsub(tostring(v), '%s+', '_') end
	table.sort(parts)
	print(string.format('[BOT][Sagume] run=%s team=%s player=%s generation=%d profile=%s time=%.3f event=%s %s',
		C.VERSION, tostring(bot:GetTeam()), tostring(bot:GetPlayerID()), state.generation, U.Profile(bot), now, event, table.concat(parts,' ')))
end
function U.Enemies(bot, range)
	local result = {}
	for _, enemy in pairs(U.Safe({}, function() return bot:GetNearbyHeroes(math.min(1600,range), true, BOT_MODE_NONE) end)) do
		if U.Valid(enemy) and not U.Safe(true, function() return IsPossibleIllusion(enemy) end) then result[#result+1] = enemy end
	end
	return result
end
function U.Allies(bot, range)
	local result = {bot}
	for _, ally in pairs(U.Safe({}, function() return bot:GetNearbyHeroes(math.min(1600,range), false, BOT_MODE_NONE) end)) do
		if ally ~= bot and U.Valid(ally) and not U.Safe(true, function() return ally:IsIllusion() end) then result[#result+1] = ally end
	end
	return result
end
function U.Target(bot, enemies)
	local target = U.Safe(nil, function() return bot:GetTarget() end)
	for _, enemy in ipairs(enemies) do if enemy == target then return enemy end end
	target = U.Safe(nil, function() return bot:GetAttackTarget() end)
	for _, enemy in ipairs(enemies) do if enemy == target then return enemy end end
	return nil
end
function U.EntityAllowed(bot, target, a)
	return U.Valid(target) and U.Safe(false, function()
		return not target:IsInvulnerable() and not target:IsMagicImmune()
			and GetUnitToUnitDistance(bot,target) <= math.max(0,a:GetCastRange())
	end)
end

-- 仅在效果/消耗确认后推进连段；未知或取消施法有明确超时，不留下永久动作锁。
function U.Update(bot)
	local state, now = U.State(bot), U.Now()
	if not U.Valid(bot) then
		state.pending, state.combo, state.returnOrigin = nil, nil, nil
		bot.THD_SagumeActionUntil = nil
		return false
	end
	if not U.Has(bot,C.RETURN) and not (state.pending and state.pending.name == C.W) then state.returnOrigin = nil end
	local p = state.pending
	if not p then return false end
	local a = p.item and U.Item(bot,p.name) or U.Ability(bot,p.name)
	local busy = U.Busy(bot)
	if p.name == C.W and busy and U.Distance(bot:GetLocation(),p.origin) < 64 then p.origin = U.Copy(bot:GetLocation()) end
	local cd = U.Cooldown(a)
	local confirmed = cd ~= nil and cd > (p.cooldown or 0) + 0.05
	if p.name == C.W or p.jump then
		confirmed = U.Distance(bot:GetLocation(),p.origin) > 80
			and U.Distance(bot:GetLocation(),p.destination) < 200
			and (p.jump or p.back and not U.Has(bot,C.RETURN) or not p.back and (U.Has(bot,C.BOUNCE) or U.Has(bot,C.RETURN)))
	elseif p.toggle then
		confirmed = a ~= nil and U.Safe(p.oldToggle, function() return a:GetToggleState() end) ~= p.oldToggle
	elseif p.name == C.R then
		-- 充能大招不能用物品 GetCurrentCharges 查询；消耗蓝量并结束前摇作为补充确认。
		confirmed = confirmed or (bot:GetMana() <= p.mana - p.cost + 1 and not busy and now >= p.at + p.castPoint)
	end
	if confirmed and not busy then
		if p.name == C.W then
			state.lastW = now
			state.returnOrigin = not p.back and U.Has(bot,C.RETURN) and p.origin or nil
			state.lastBlinkConfirmed = now
		elseif p.jump then
			state.lastBlinkConfirmed=now
		elseif p.name == C.R then
			state.lastR, state.returnOrigin = now, nil
			local observed=p.castTargetId and state.observations[p.castTargetId]
			if observed then observed.since=now;observed.possibleCast=now;observed.status='unknown_after_inversion' end
			state.combo = p.followup and {id=p.reason, steps=p.followup, cursor=1, expiresAt=now+6, targetId=p.targetId} or nil
		end
		state.pending = nil
		bot.THD_SagumeActionUntil = now + 0.05
		U.Log(bot,'confirmed',{ability=p.name,reason=p.reason})
		return true
	end
	if now >= p.expiresAt then
		state.pending, state.combo = nil, nil
		if p.name == C.W then state.returnOrigin = nil end
		state.retryAt = now + 0.8
		bot.THD_SagumeActionUntil = nil
		U.Log(bot,'failed',{ability=p.name,reason='confirmation_timeout'})
		return busy
	end
	return true
end
function U.Issue(bot, intent)
	local state, now = U.State(bot), U.Now()
	if not intent or state.pending or now < state.retryAt or U.Busy(bot) or not U.Castable(intent.ability) then return false end
	local a = intent.ability
	if now < (bot.THD_SagumeActionUntil or -90) then return false end
	local name = a:GetName()
	local isItem = U.Safe(false,function() return a:IsItem() end)
	if isItem and bot:IsMuted() or not isItem and bot:IsSilenced() then return false end
	if name == C.W and (bot:IsRooted() or (intent.back ~= true and U.Has(bot,C.RETURN))) then return false end
	if intent.jump and bot:IsRooted() then return false end
	if intent.target and not U.EntityAllowed(bot,intent.target,a) then return false end
	state.generation = state.generation + 1
	state.pending = {
		name=name,item=isItem,at=now,castPoint=U.CastPoint(a),
		expiresAt=now+U.CastPoint(a)+C.ACTION_TIMEOUT_MARGIN,cooldown=U.Cooldown(a),
		mana=bot:GetMana(),cost=U.Mana(a),origin=U.Copy(bot:GetLocation()),back=intent.back,
		destination=U.Copy(intent.location or (intent.back and state.returnOrigin or nil)),
		toggle=intent.toggle,oldToggle=U.Safe(false,function() return a:GetToggleState() end),
		jump=intent.jump,
		reason=intent.reason,followup=intent.followup,targetId=intent.targetId,
		castTargetId=intent.target and U.Safe(nil,function() return intent.target:GetPlayerID() end),
	}
	bot.THD_SagumeActionUntil = state.pending.expiresAt
	if intent.location then bot:Action_UseAbilityOnLocation(a,intent.location)
	elseif intent.target then bot:Action_UseAbilityOnEntity(a,intent.target)
	else bot:Action_UseAbility(a) end
	U.Log(bot,'issued',{ability=name,reason=intent.reason,target=intent.target and intent.target:GetPlayerID() or -1})
	return true
end

return U
