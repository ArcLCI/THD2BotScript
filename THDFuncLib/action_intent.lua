-- 普通移动/普攻的意图复用；施法队列和模式任务不归此模块所有。
local A = {}

function A.Protect(unit, ability, startMargin)
	unit.THD_ActionProtection = {ability=ability, untilTime=DotaTime()+(startMargin or 0.35)}
end

function A.ValidTarget(target)
	return target ~= nil and not target:IsNull() and target:CanBeSeen() and target:IsAlive()
end

function A.Protected(unit, owner, lifecycleOnly)
	if unit == nil or unit:IsNull() or not unit:IsAlive() then return true end
	if A.KasenProtected(unit) then return true end
	if unit:IsCastingAbility() or unit:IsChanneling() then return true end
	-- 队列仅阻止普通动作覆盖；未来的技能/施法接近不能无限抬高模式评分或暂停进展预算。
	if not lifecycleOnly then
		if unit:IsUsingAbility() then return true end
		-- 团队评估会传入其他英雄；沿用J.HasQueuedAction的自机边界，不以同队/同PlayerID推断控制权。
		-- 召唤物仍检查正在施法的状态；此通用查询不尝试枚举或猜测其队列权限。
		if unit==GetBot() then
			if unit:GetCurrentActionType() == BOT_ACTION_TYPE_USE_ABILITY then return true end
			for index=0,unit:NumQueuedActions()-1 do
				if unit:GetQueuedActionType(index)==BOT_ACTION_TYPE_USE_ABILITY then return true end
			end
		end
	end
	local ability = unit:GetCurrentActiveAbility()
	if ability ~= nil and not ability:IsNull()
	and (ability:IsInAbilityPhase() or ability:IsChanneling()) then return true end
	local now = DotaTime()
	-- 英雄模块的已提交启动窗口独立于模式；只保护pending，不锁住普攻增益期。
	local flandre,sunny=unit.flandreUltimateState,unit.sunnyUltimateState
	if flandre~=nil and flandre.phase=='pending' and now<=(flandre.pendingUntil or -90) then return true end
	if sunny~=nil and sunny.phase=='pending' and now<=(sunny.pendingUntil or -90) then return true end
	local protection = unit.THD_ActionProtection
	if protection ~= nil then
		local protectedAbility = protection.ability
		if now < protection.untilTime or (protectedAbility ~= nil and not protectedAbility:IsNull()
		and (protectedAbility:IsInAbilityPhase() or protectedAbility:IsChanneling())) then return true end
		unit.THD_ActionProtection = nil
	end
	return now < (unit.THD_SagumeActionUntil or -90)
		or now < (unit.THD_TeiActionUntil or -90)
		or (owner ~= 'tei_turn' and unit.THD_TeiBackstep ~= nil and now <= unit.THD_TeiBackstep.expires)
end

-- 只锁华扇已提交动作，不锁候选接管或鬼脉结束后的普攻增益。
function A.KasenProtected(unit)
	if unit == nil or unit:GetUnitName() ~= 'npc_dota_hero_bristleback' or not unit:IsAlive() then return false end
	if DotaTime() < (unit.THD_KasenActionUntil or -90)
	or unit:HasModifier('modifier_thdots_kasen04ex_takedamage') then return true end
	local q = unit:GetAbilityByName('ability_thdots_kasen01')
	return q ~= nil and (q:IsInAbilityPhase() or q:IsChanneling())
end

local function Distance(a, b)
	return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end

function A.Forget(unit)
	if unit ~= nil then unit.THD_ActionIntent = nil end
end

function A.Attack(unit, target, once)
	if not A.ValidTarget(target) or A.Protected(unit) then return false, false end
	if target:IsInvulnerable() or target:IsAttackImmune() or target:HasModifier('modifier_fountain_glyph') then return false,false end
	-- 动作仍然存活时复用；一次攻击完成回到空闲后才允许下一次攻击。
	if unit:GetCurrentActionType() == BOT_ACTION_TYPE_ATTACK and unit:GetAttackTarget() == target then
		return true, false
	end
	unit:Action_AttackUnit(target, once == true)
	unit.THD_ActionIntent = nil
	return true, true
end

function A.Move(unit, location, tolerance, kind, force, owner)
	if location == nil or A.Protected(unit, owner) then return false, false end
	kind = kind or 'move'
	local actionType = kind == 'direct' and BOT_ACTION_TYPE_MOVE_TO_DIRECTLY
		or kind == 'attack_move' and BOT_ACTION_TYPE_ATTACKMOVE or BOT_ACTION_TYPE_MOVE_TO
	local previous = unit.THD_ActionIntent
	local now, current = DotaTime(), unit:GetLocation()
	local mode = unit==GetBot() and unit:GetActiveMode() or BOT_MODE_NONE
	if not force and previous ~= nil and previous.kind == kind and previous.mode == mode and previous.owner==owner
	and unit:GetCurrentActionType() == actionType and Distance(previous.location, location) <= (tolerance or 100) then
		local remaining = Distance(current, previous.location)
		if previous.bestDistance - remaining >= 32 then
			previous.bestDistance, previous.progressAt = remaining, now
		end
		-- API不暴露原生移动目的地；无位移时有限重试，任务层另行判定无进展退出。
		if now - previous.progressAt < 1.2 or Distance(current, location) <= 32 then return true, false end
	end
	if kind == 'direct' then unit:Action_MoveDirectly(location)
	elseif kind == 'attack_move' then unit:Action_AttackMove(location)
	else unit:Action_MoveToLocation(location) end
	unit.THD_ActionIntent = {kind=kind, mode=mode, owner=owner, location=Vector(location.x,location.y,location.z),
		bestDistance=Distance(current,location), progressAt=now}
	return true, true
end

function A.GuardDesire(unit, mode, callback)
	return function(...)
		-- 每个英雄仅记一次版本，不扫描额外目标或打印逐帧诊断。
		if unit.THD_ModeLifecycleVersion~='MODE-LIFECYCLE-20260920-R2' then
			unit.THD_ModeLifecycleVersion='MODE-LIFECYCLE-20260920-R2'
			print(string.format('[BOT][ModeLifecycle] version=%s event=loaded team=%d player=%d dota_time=%.3f',
				unit.THD_ModeLifecycleVersion,unit:GetTeam(),unit:GetPlayerID(),DotaTime()))
		end
		local turn=unit.THD_TeiBackstep
		if turn~=nil and (turn.phase=='await_mode' or turn.phase=='turn') and DotaTime()<=turn.expires then return BOT_MODE_DESIRE_NONE end
		-- 仅在已提交动作的生命周期内保护当前模式，不给普通收益增加全局倍率。
		if unit:IsAlive() and A.Protected(unit,nil,true) then
			return unit:GetActiveMode()==mode and BOT_MODE_DESIRE_ABSOLUTE or BOT_MODE_DESIRE_NONE
		end
		return callback(...)
	end
end

return A
