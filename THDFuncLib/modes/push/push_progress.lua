-- 有界血量历史只描述可见净进展；影子估值不授予攻击/续攻权限。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/push/push_escort_config')
local P={}
local function Visible(unit)
	return unit~=nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
end
function P.Observe(objective,now,health)
	local target=objective.target
	local state=objective.netProgress
	if health~=nil and state and now-state.at<Config.SAMPLE_INTERVAL then return false end
	if not Visible(target) or health==nil then objective.netProgress=nil;return false end
	local maximum=target:GetMaxHealth()
	if not state or state.target~=target or state.maximum~=maximum or now-state.at>Config.NET_SAMPLE_GAP then
		state={target=target,maximum=maximum,at=now,samples={},creditHealth=health}
		objective.netProgress=state
	end
	if #state.samples>0 and now-state.at<Config.SAMPLE_INTERVAL then return false end
	state.at=now
	local samples=state.samples
	samples[#samples+1]={at=now,hp=health}
	while #samples>1 and now-samples[1].at>Config.NET_WINDOW do table.remove(samples,1) end
	local first=samples[1]
	state.startHealth,state.endHealth=first.hp,health
	state.span=now-first.at
	state.net=first.hp-health
	state.dps=state.span>=Config.NET_MIN_SPAN and math.max(0,state.net/state.span) or nil
	-- 每份净下降只消费一次；回血后的重复命中不能反复续租。
	local threshold=math.max(Config.NET_MIN_HEALTH,maximum*Config.NET_MIN_FRACTION)
	if state.dps and state.net>=threshold and state.creditHealth-health>=threshold then
		state.creditHealth=health;state.progressAt=now
		return true
	end
	return false
end
local function Number(value) return value and string.format('%.2f',value) or 'unknown' end
function P.Shadow(bot,objective,tower,open)
	if not Config.SIEGE_SHADOW_DEBUG or not objective then return end
	local now=DotaTime()
	local state=bot.THD_SiegeShadow
	if not state or state.objective~=objective.id or now-state.at>Config.NET_SAMPLE_GAP then
		state={objective=objective.id,at=now,hp=bot:GetHealth(),logAt=-90,samples={{at=now,hp=bot:GetHealth()}}};bot.THD_SiegeShadow=state
	end
	if now-state.at>=Config.SAMPLE_INTERVAL then
		-- 净失血仅为承伤代理，回血/护盾可使它低估真实来袭。
		local samples=state.samples
		samples[#samples+1]={at=now,hp=bot:GetHealth()}
		while #samples>1 and now-samples[1].at>Config.NET_WINDOW do table.remove(samples,1) end
		local dt=now-samples[1].at
		state.loss=dt>=Config.NET_MIN_SPAN and math.max(0,samples[1].hp-bot:GetHealth())/dt or nil
		state.hp,state.at=bot:GetHealth(),now
	end
	if now-state.logAt<Config.LOG_INTERVAL then return end
	state.logAt=now
	local target=objective.target
	local dps,attackers=0,0
	if open and Visible(target) then
		for _,member in ipairs(objective.participants or {}) do
			local unit=member.unit
			if Visible(unit) and unit:GetAttackTarget()==target and not unit:IsUsingAbility()
			and not unit:IsChanneling() and not unit:IsStunned()
			and GetUnitToUnitDistance(unit,target)<=math.min(1000,unit:GetAttackRange()+100) then
				local estimate=unit:GetEstimatedDamageToTarget(false,target,3,DAMAGE_TYPE_PHYSICAL)/3
				if estimate>0 then dps=dps+estimate;attackers=attackers+1 end
			end
		end
	end
	local net=objective.netProgress
	local fresh=net and now-net.at<=Config.NET_SAMPLE_GAP
	local hp=Visible(target) and target:GetHealth() or nil
	local risk=tower and (tower.unseenIncoming or (tower.unavoidableDamage or 0)>=bot:GetHealth()
		or (tower.predictedDamage or 0)>=bot:GetHealth()*Config.MAX_TOWER_DAMAGE_RATIO)
	-- 未恢复真实伤害事件、护盾和TP历史前，安全窗口一律unknown，不驱动行为。
	print(string.format('[BOT][SiegeShadow] run=%s time=%.3f pid=%s objective=%s open=%s attackers=%d predicted_dps=%s net_dps=%s hp_start=%s hp_end=%s span=%s ttk_estimate=%s ttk_net=%s loss_proxy=%s ttd_proxy=%s tower_damage=%s risk=%s safe_window=unknown protection_until=unknown maintain_until=%s lease_until=%s absolute_until=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),objective.id,tostring(open),attackers,Number(dps>0 and dps or nil),
		Number(fresh and net.dps or nil),Number(fresh and net.startHealth or nil),Number(fresh and net.endHealth or nil),
		Number(fresh and net.span or nil),Number(open and hp and dps>0 and hp/dps or nil),
		Number(open and hp and fresh and net.dps and net.dps>0 and hp/net.dps or nil),Number(state.loss),
		Number(state.loss and state.loss>0 and bot:GetHealth()/state.loss or nil),Number(tower and tower.predictedDamage),
		tostring(risk==true),Number(objective.escortContinuationSafeUntil),Number(objective.expiresAt),Number(objective.absoluteDeadline)))
end
return P
