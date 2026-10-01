-- 纯局部战术决策；采样、权限和命令由调用者承担，不依赖协调器或英雄脚本。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/roam/roam_config')
local T={}
local function Clamp(x) return math.max(0,math.min(1,x)) end
local function Distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function Copy(p) return {x=p.x,y=p.y,z=p.z} end
function T.Evaluate(snapshot,previous)
	local s=previous or {anchor=Copy(snapshot.location),chaseUsed=0,revision=0,history={}}
	local now=snapshot.now
	local rejects={}
	local elapsed=s.at and now-s.at or 0
	local dt=snapshot.executing and elapsed<=0.75 and math.min(0.5,elapsed) or 0
	s.at=now
	local function Exit(reason)
		s.target=nil;s.action='handoff'
		return s,{action='handoff',reason=reason,chaseUsed=s.chaseUsed,revision=s.revision,deadline=snapshot.deadline,
			rejects=#rejects>0 and table.concat(rejects,'|') or (#snapshot.candidates==0 and 'no_visible_candidates' or reason)}
	end
	if now>=snapshot.deadline then return Exit('combat_deadline') end
	if snapshot.danger or snapshot.powerRatio<Config.MIN_CONTINUE_POWER_RATIO or snapshot.allyCount<snapshot.enemyCount then return Exit('local_danger') end
	if Distance(snapshot.location,s.anchor)>Config.TACTICS_ANCHOR_RADIUS then return Exit('anchor_limit') end
	local best,current=nil,nil
	for _,c in ipairs(snapshot.candidates) do
		local history=s.history[c.key]
		-- 失去连续观察后重新建立血量基线，不能把视野外的掉血当成本轮输出。
		if not history or now-(history.lastSeen or now)>0.75 then
			history={first=now,hp=c.health,initial=c.health};s.history[c.key]=history
		end
		c.healthProgress=c.health<history.hp
		c.reliableKill=now-history.first>=1 and history.initial-c.health>=10 and c.contributors>0 and c.ttk~=nil
		history.hp,history.lastSeen=c.health,now
		local support=c.inRange or not snapshot.supportRequired or snapshot.supportCount>0
		-- 每个可见候选保留首个拒绝门，辅助区分安全退出与战术过于保守。
		local reject=not c.safe and (c.reject or 'unsafe_path') or (not support and 'no_support')
			or (Distance(c.location,s.anchor)>Config.TACTICS_ANCHOR_RADIUS and 'anchor_limit')
		if reject then rejects[#rejects+1]=c.key..':'..reject end
		if c.safe and support and Distance(c.location,s.anchor)<=Config.TACTICS_ANCHOR_RADIUS then
			local execution=c.inRange and 1 or Clamp(1-c.eta/3)
			local kill=c.reliableKill and Clamp(1-c.ttk/6) or 0
			c.score=0.30*execution+0.30*c.threat+0.25*kill+0.15*(c.controlled and 1 or 0)
				+(c.key==s.targetKey and 0.08 or 0)-0.15*Clamp(c.eta/3)
			if c.key==s.targetKey then current=c end
			if not best or c.score>best.score or (c.score==best.score and c.key<best.key) then best=c end
		end
	end
	if not best then return Exit('no_safe_combat_target') end
	local chosen=current or best
	if current and best.key~=current.key and best.score>=current.score+Config.TACTICS_SWITCH_MARGIN then
		if s.pendingKey~=best.key then s.pendingKey,s.pendingAt=best.key,now end
		if now-s.pendingAt>=Config.TACTICS_SWITCH_STABLE then chosen=best end
	else s.pendingKey,s.pendingAt=nil,nil end
	local changed=chosen.key~=s.targetKey
	if changed then
		s.targetKey=chosen.key;s.revision=s.revision+1;s.pendingKey,s.pendingAt=nil,nil
		s.bestDistance=chosen.distance;s.staleFor=0
	end
	local progress=chosen.healthProgress or chosen.controlled
	if (s.bestDistance or chosen.distance)-chosen.distance>=Config.TACTICS_CLOSE_PROGRESS then
		progress=true;s.bestDistance=chosen.distance
	end
	if snapshot.executing then
		if progress then s.staleFor=0;s.progressAt=now else s.staleFor=(s.staleFor or 0)+dt end
		if not chosen.inRange and not chosen.healthProgress and not chosen.controlled then s.chaseUsed=s.chaseUsed+dt end
	end
	local stalled=(s.staleFor or 0)>=Config.TACTICS_NO_PROGRESS
	local spent=not chosen.inRange and s.chaseUsed>=Config.TACTICS_CHASE_BUDGET
	if stalled or spent then
		-- 收尾仅一次，必须有可见掉血及在场攻击者校准；换目标不续这个窗口。
		local finish=chosen.reliableKill and chosen.ttk<=2 and not snapshot.incomingRisk
		if finish and not s.finishUntil then s.finishUntil=math.min(now+2,snapshot.deadline);s.finishKey=chosen.key end
		if not finish or s.finishKey~=chosen.key or now>=(s.finishUntil or now) then return Exit(spent and 'chase_budget' or 'no_combat_progress') end
	end
	local action=chosen.inRange and 'attack' or 'move'
	if s.action~=action then s.revision=s.revision+1 end
	s.action,s.target=action,chosen.unit
	return s,{action=action,target=chosen.unit,targetKey=chosen.key,location=chosen.moveLocation,
		reason=changed and (chosen.threat>0 and 'respond_to_threat' or 'better_local_target') or 'continue_target',
		revision=s.revision,chaseUsed=s.chaseUsed,deadline=snapshot.deadline,score=chosen.score,
		candidateCount=#snapshot.candidates,supportCount=snapshot.supportCount,distance=chosen.distance,rejects=#rejects>0 and table.concat(rejects,'|') or 'none'}
end
function T.Publish(bot,missionID,state,decision,now)
	bot.THD_GankCombatContext={missionID=missionID,target=decision.target,targetKey=decision.targetKey,
		action=decision.action,reason=decision.reason,revision=decision.revision,expiresAt=now+Config.TACTICS_CONTEXT_TTL,
		deadline=decision.deadline,chaseUsed=state.chaseUsed,active=decision.action~='handoff'}
end
function T.GetContext(bot)
	local context=bot and bot.THD_GankCombatContext
	if not context or DotaTime()>=context.expiresAt then return nil end
	local copy={};for k,v in pairs(context) do copy[k]=v end;return copy
end
function T.Release(bot,reason)
	local c=bot.THD_GankCombatContext
	if c then
		if c.active and Config.GANK_TACTICS_DEBUG then
			print(string.format('[BOT][GankTactics] run=%s time=%.3f pid=%s mission=%s event=released reason=%s chase_used=%.2f',
				Config.GANK_TACTICS_RUN_ID,DotaTime(),bot:GetPlayerID(),tostring(c.missionID),tostring(reason),c.chaseUsed or 0))
		end
		c.active=false;c.reason=reason;c.expiresAt=math.min(c.deadline or math.huge,DotaTime()+Config.TACTICS_HANDOFF_TTL)
	end
end
return T
