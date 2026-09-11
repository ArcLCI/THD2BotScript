-- S5技能效果模型：只使用可见来源、自身状态和可见敌人；不推断隐藏等级或读取Game真值。
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local G = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Z = require(GetScriptDirectory()..'/THDFuncLib/skill_zones')
local Combat = require(GetScriptDirectory()..'/THDFuncLib/combat_power')
local Diagnostics = require(GetScriptDirectory()..'/THDFuncLib/bot_diagnostics_config')
local T = {}
local function Safe(default,fn) local ok,v=pcall(fn);if ok and v~=nil then return v end;return default end
local function Now() return Safe(0,DotaTime) end
local function Copy(p) return G.MakeVector(p.x,p.y,p.z) end
local Effects = require(GetScriptDirectory()..'/THDFuncLib/skill_effects')
-- 仅复用已有调用采样自身位移；两段方向一致才采用趋势，跳变/停步/受控立即失效。
local function ObserveMotion(bot,now)
	local state=bot.THD_SkillMotion or {};bot.THD_SkillMotion=state
	local position=Copy(bot:GetLocation())
	local mode=Safe(-1,function() return bot:GetActiveMode() end)
	local blocked=Safe(true,function() return not bot:IsAlive() or bot:IsStunned() or bot:IsRooted() or bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling() or bot:NumQueuedActions()>0 end)
	if blocked or (state.mode and state.mode~=mode) then state.position=nil;state.vx=nil;state.ready=false end
	if blocked then return end
	if state.at and now-state.at<0.10 then return end
	local dt=state.at and now-state.at or 0
	local length=state.position and G.Distance(position,state.position) or 0
	local speed=math.max(1,Safe(1,function() return bot:GetCurrentMovementSpeed() end))
	if state.position and dt>=0.10 and dt<=0.40 and length>=8 and length<=speed*dt*1.5+48 then
		local vx,vy=(position.x-state.position.x)/dt,(position.y-state.position.y)/dt
		local magnitude=math.sqrt(vx*vx+vy*vy)
		local oldMagnitude=state.vx and math.sqrt(state.vx*state.vx+state.vy*state.vy) or 0
		state.ready=oldMagnitude>0 and (vx*state.vx+vy*state.vy)/(magnitude*oldMagnitude)>=0.85
		local scale=math.min(1,speed/math.max(1,magnitude))
		state.vx,state.vy=vx*scale,vy*scale
	else state.vx=nil;state.ready=false end
	state.position=position;state.at=now;state.mode=mode
end
function T.Context(bot)
	local now=Now()
	ObserveMotion(bot,now)
	local cached=bot.THD_SkillThreatContext
	if cached and now-cached.at<Config.SKILL_SCAN_INTERVAL then return cached end
	local position=Copy(bot:GetLocation())
	local ctx={at=now,position=position,health=math.max(1,Safe(1,function() return bot:GetHealth() end)),
		speed=math.max(1,Safe(1,function() return bot:GetCurrentMovementSpeed() end)),
		mode=Safe(-1,function() return bot:GetActiveMode() end),enemies={},pressure=0,available=true}
	ctx.tojikoStacks=Safe(-1,function()
		local index=bot:GetModifierByName('modifier_ability_thdots_tojikoEx_debuff')
		if type(index)~='number' then return -1 end
		return index>=0 and bot:GetModifierStackCount(index) or 0
	end)
	ctx.defense=Combat.GetDefenseSnapshot(bot)
	if ctx.defense==nil then ctx.available=false end
	local ok,nearby=pcall(function() return bot:GetNearbyHeroes(1600,true,BOT_MODE_NONE) end)
	if not ok or type(nearby)~='table' then ctx.available=false;nearby={} end
	for i,enemy in ipairs(nearby) do
		if i>10 then break end
		-- 敌方句柄仅在当次可见检查内使用，缓存只留下数值快照。
		if Safe(false,function() return not enemy:IsNull() and enemy:CanBeSeen() and enemy:IsAlive() end) then
			local snapshot=Safe(nil,function()
				local attack=Combat.GetAttackSnapshot(enemy)
				local p=enemy:GetLocation()
				return {position=Copy(p),range=attack and attack.attackRange or 600,
					dps=attack and Combat.EstimateAttackDamageFromSnapshots(attack,ctx.defense,1,1) or nil,
					speed=math.max(1,enemy:GetCurrentMovementSpeed())}
			end)
			if snapshot then
				if snapshot.dps==nil then ctx.available=false;snapshot.dps=100 end
				table.insert(ctx.enemies,snapshot)
				local distance=G.Distance(position,snapshot.position)
				ctx.pressure=math.max(ctx.pressure,math.max(0,1-distance/1400))
			else ctx.available=false end
		end
	end
	ctx.recentDamage=Safe(true,function() return bot:WasRecentlyDamagedByAnyHero(2) end)
	if ctx.recentDamage then ctx.pressure=math.max(ctx.pressure,0.65) end
	ctx.retreat=ctx.mode==BOT_MODE_RETREAT
	if ctx.retreat then
		-- 仅作为撤退方向候选；不是读取Valve目的地，也不保证该方向可通行。
		local anchor=Safe(nil,function() return GetAncient(bot:GetTeam()):GetLocation() end)
		if anchor then
			local distance=G.Distance(position,anchor)
			local scale=math.min(1,1800/math.max(1,distance))
			ctx.goal=G.MakeVector(position.x+(anchor.x-position.x)*scale,position.y+(anchor.y-position.y)*scale,position.z)
			ctx.goalKind='own_ancient_direction'
		end
	end
	bot.THD_SkillThreatContext=ctx
	return ctx
end
local function Contact(a,b,zone,speed,insideSpeed,remaining)
	local dx,dy=b.x-a.x,b.y-a.y
	local length=math.sqrt(dx*dx+dy*dy)
	local x,y=a.x-zone.center.x,a.y-zone.center.y
	if length<1 then return x*x+y*y<=zone.radius*zone.radius and math.min(2,remaining) or 0,0 end
	local projection=(x*dx+y*dy)/length
	local disc=projection*projection-(x*x+y*y-zone.radius*zone.radius)
	if disc<0 then return 0,0 end
	local root=math.sqrt(disc)
	local enter=math.max(0,-projection-root)
	local leave=math.min(length,-projection+root)
	if leave<=enter then return 0,0 end
	local entryTime=enter/speed
	return math.max(0,math.min((leave-enter)/insideSpeed,remaining-entryTime)),entryTime
end
function T.Effect(bot,zone,ctx,goal)
	local profile=Effects.Get(zone.abilityId)
	if not profile or not ctx.available then return {score=1,level='high',confidence='unknown',exposure=0,damage=0,slowCost=0} end
	if profile.kind=='delayed_burst' then
		-- 位置和时间必须与当前调用一致；敌人及防御快照仍保持原0.25秒缓存。
		local now,position=Now(),Copy(bot:GetLocation())
		local speed=math.max(1,Safe(ctx.speed,function() return bot:GetCurrentMovementSpeed() end))
		-- 受控/施法时不能沿旧移动目标假设会离圈；这里只收紧预测，不打断动作保护。
		local held=Safe(true,function() return bot:IsStunned() or bot:IsRooted() or bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling() end)
		local predictionGoal=held and position or goal
		local hit,reason,enter,leave=Effects.BurstExposure(position,predictionGoal or position,zone,speed,now,0,0,true)
		local motionUsed=false
		local motion=bot.THD_SkillMotion
		if not hit and not held and goal==nil and motion and motion.ready and now-motion.at<=0.25 then
			local closing=(position.x-zone.center.x)*motion.vx+(position.y-zone.center.y)*motion.vy<0
			local horizon=math.max(0,math.min(0.50,zone.impactAt-now+profile.timeSlack))
			if closing and horizon>0 then
				local projected=G.MakeVector(position.x+motion.vx*horizon,position.y+motion.vy*horizon,position.z)
				local trendHit=Effects.BurstExposure(position,projected,zone,speed,now,0,0,true)
				-- 推测趋势只提高警戒，不用推测会离开来降低已确认的危险。
				if trendHit then hit=true;reason='approaching_impact_zone';motionUsed=true end
			end
		end
		if hit==nil then return {score=1,level='high',confidence='unknown',exposure=0,damage=0,slowCost=0} end
		local raw=math.max(0,profile.rawHigh+math.max(0,ctx.defense.armor)*profile.armorFactor)
		local damage=hit and Combat.EstimateIncomingDamageFromSnapshot(ctx.defense,raw,DAMAGE_TYPE_MAGICAL) or 0
		if damage==nil then return {score=1,level='high',confidence='unknown',exposure=0,damage=0,slowCost=0} end
		-- 换算尚未校准时，不能仅靠魔抗折扣允许承受爆发；保留旧预测供对照。
		-- raw只是决策保守参考，不是包含所有增伤的实际伤害上界。
		local resistanceOnly=damage
		-- 自身已读到的屠自古易伤按Game KV的每层3%计入；未知层数不作减伤。
		local vulnerability=1+math.max(0,ctx.tojikoStacks or 0)*0.03
		damage=damage*vulnerability
		local decisionDamage=hit and math.max(raw,resistanceOnly)*vulnerability or 0
		local score=decisionDamage/ctx.health*profile.baseWeight
		return {score=score,level=score>=0.80 and 'critical' or score>=0.40 and 'high' or score>Config.SKILL_ACCEPTABLE_RISK and 'avoid' or 'tolerable',
			confidence=profile.confidence,exposure=hit and profile.timeSlack*2 or 0,damage=damage,slowCost=0,ticks=hit and 1 or 0,rawHigh=raw,
			resistanceOnly=resistanceOnly,vulnerability=vulnerability,decisionDamage=decisionDamage,damagePolicy='unmitigated_floor_self_vulnerability',predictionHeld=held,modelTime=now,modelX=position.x,modelY=position.y,motionUsed=motionUsed,timing=reason,impactIn=zone.impactAt-now,kind=profile.kind,scope=profile.scope,entryTime=enter,leaveTime=leave}
	end
	local remaining=math.max(0,zone.expiresAt-ctx.at)
	local slowed=Safe(false,function() return bot:HasModifier(profile.slowModifier) end)
	local speed=ctx.speed*(slowed and 1 or (1-profile.slow))
	local exposure,entryTime=Contact(ctx.position,goal or ctx.position,zone,ctx.speed,math.max(1,speed),remaining)
	-- tick相位未验证时按暴露窗口最大可能次数估算；不把预测当成精确实际伤害。
	local ticks=exposure>0 and math.min(math.ceil(remaining/profile.interval),math.floor(exposure/profile.interval)+1) or 0
	local damage=Combat.EstimateIncomingDamageFromSnapshot(ctx.defense,profile.rawHigh*ticks,DAMAGE_TYPE_MAGICAL)
	if damage==nil then return {score=1,level='high',confidence='unknown',exposure=exposure,damage=0,slowCost=0} end
	local slowCost=exposure>0 and ctx.pressure*profile.slow*(1+math.min(2,exposure)) or 0
	local score=damage/ctx.health*profile.baseWeight+slowCost+profile.control
	local level=score>=0.80 and 'critical' or score>=0.40 and 'high' or score>Config.SKILL_ACCEPTABLE_RISK and 'avoid' or 'tolerable'
	return {score=score,level=level,confidence=profile.confidence,exposure=exposure,entryTime=entryTime,
		damage=damage,slowCost=slowCost,ticks=ticks,rawLow=profile.rawLow,rawHigh=profile.rawHigh}
end
function T.SelectZones(bot,zones,ctx,goal,owner)
	local result={}
	bot.THD_SkillThreatLogs=bot.THD_SkillThreatLogs or {}
	local live,effects,combined={},{},0
	for _,zone in ipairs(zones) do
		local effect=T.Effect(bot,zone,ctx,goal);effects[zone.key]=effect;combined=combined+effect.score
	end
	for _,zone in ipairs(zones) do
		live[zone.key]=true
		local effect=effects[zone.key]
		-- 仅在已有决策调用中、爆发前0.75秒至后0.1秒记录，单来源最多5条，无新增扫描。
		if zone.impactAt and Diagnostics.SKILL_TRACE_LOG then
			bot.THD_ImpactProbes=bot.THD_ImpactProbes or {}
			local probe=bot.THD_ImpactProbes[zone.key] or {count=0,nextAt=-90}
			local now=Now();local remaining=zone.impactAt-now
			if remaining<=0.75 and remaining>=-0.10 and probe.count<5 and now>=probe.nextAt then
				probe.count=probe.count+1;probe.nextAt=now+0.20
				bot.THD_ImpactProbes[zone.key]=probe
				local current=bot:GetLocation()
				Z.Log(bot,'near_impact',string.format('key=%s owner=%s sample=%d impact_in=%.3f x=%.1f y=%.1f distance=%.1f radius=%.1f context_time=%.3f context_x=%.1f context_y=%.1f timing=%s stunned=%s rooted=%s casting=%s queued=%s mode=%s action=%s goal_kind=%s goal_x=%.1f goal_y=%.1f prediction_time=%.3f prediction_x=%.1f prediction_y=%.1f motion_used=%d prediction_held=%d',
					zone.key,owner,probe.count,remaining,current.x,current.y,G.Distance(current,zone.center),zone.radius,ctx.at,ctx.position.x,ctx.position.y,effect.timing or 'unknown',
					tostring(Safe('unknown',function() return bot:IsStunned() end)),tostring(Safe('unknown',function() return bot:IsRooted() end)),
					tostring(Safe('unknown',function() return bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling() end)),
					tostring(Safe(-1,function() return bot:NumQueuedActions() end)),tostring(Safe(-1,function() return bot:GetActiveMode() end)),
					tostring(Safe(-1,function() return bot:GetCurrentActionType() end)),ctx.goalKind or 'none',goal and goal.x or 0,goal and goal.y or 0,effect.modelTime or ctx.at,effect.modelX or ctx.position.x,effect.modelY or ctx.position.y,effect.motionUsed and 1 or 0,effect.predictionHeld and 1 or 0))
			end
		end
		local key=zone.key..':'..owner
		local previous=bot.THD_SkillThreatLogs[key]
		local threshold=previous and previous.decision=='avoid' and 0.12 or Config.SKILL_ACCEPTABLE_RISK
		-- 已开始的有限脱离不能因刚离开伤害半径就取消；保留S4外边界与来源寿命。
		local committed=ctx.committed and ctx.committed[zone.key] and zone.expiresAt>ctx.at
		local avoid=committed or (effect.score>0 and combined>threshold)
		if avoid then table.insert(result,zone) end
		local decision=avoid and 'avoid' or 'allow_original'
		if not previous or previous.decision~=decision or ctx.at-previous.at>=1 then
			Z.Log(bot,'threat_decision',string.format('key=%s owner=%s decision=%s level=%s score=%.3f predicted_damage=%.1f exposure=%.3f slow_cost=%.3f pressure=%.3f health=%.1f confidence=%s goal_kind=%s policy=%s combined=%.3f enemies=%d raw_high=%.1f ticks=%d timing=%s impact_in=%.3f effect_kind=%s scope=%s decision_damage=%.1f damage_policy=%s bot_magic_resist=%.4f bot_armor=%.3f bot_tojiko_stacks=%d resistance_only=%.1f self_vulnerability=%.3f prediction_time=%.3f prediction_x=%.1f prediction_y=%.1f motion_used=%d prediction_held=%d',
				zone.key,owner,decision,effect.level,effect.score,effect.damage,effect.exposure,effect.slowCost,ctx.pressure,ctx.health,effect.confidence,ctx.goalKind or 'none',committed and 'bounded_lease' or 'dynamic',combined,#ctx.enemies,effect.rawHigh or 0,effect.ticks or 0,effect.timing or 'periodic_contact',effect.impactIn or -1,effect.kind or 'periodic',effect.scope or 'periodic_circle',effect.decisionDamage or effect.damage,effect.damagePolicy or 'existing_periodic',ctx.defense and ctx.defense.magicResistance or -1,ctx.defense and ctx.defense.armor or -1,ctx.tojikoStacks or -1,effect.resistanceOnly or effect.damage,effect.vulnerability or 1,effect.modelTime or ctx.at,effect.modelX or ctx.position.x,effect.modelY or ctx.position.y,effect.motionUsed and 1 or 0,effect.predictionHeld and 1 or 0))
			bot.THD_SkillThreatLogs[key]={at=ctx.at,decision=decision,source=zone.key}
		end
	end
	for key,value in pairs(bot.THD_SkillThreatLogs) do if not live[value.source] then bot.THD_SkillThreatLogs[key]=nil end end
	for key in pairs(bot.THD_ImpactProbes or {}) do if not live[key] then bot.THD_ImpactProbes[key]=nil end end
	return result
end
-- 评分单位近似为自身生命比例；追兵沿路威胁使用保守数值采样，不模拟不可见技能。
function T.RouteCost(ctx,origin,points,goal)
	local previous,total,risk=origin,0,0
	for _,point in ipairs(points) do
		local seconds=G.Distance(previous,point)/ctx.speed
		local midpoint=G.MakeVector((previous.x+point.x)/2,(previous.y+point.y)/2,point.z)
		for _,enemy in ipairs(ctx.enemies) do
			local distance=math.min(G.Distance(previous,enemy.position),G.Distance(midpoint,enemy.position),G.Distance(point,enemy.position))
			local reach=enemy.range+enemy.speed*math.min(2,total+seconds)+120
			local coverage=math.max(0,math.min(1,(reach+300-distance)/300))
			risk=risk+enemy.dps*seconds*coverage/ctx.health
		end
		total=total+seconds;previous=point
	end
	local remaining=goal and G.Distance(previous,goal)/ctx.speed or 0
	return risk+total*0.025+remaining*0.04,risk,total
end
function T.ExitPenalty(ctx,origin,target)
	local score=T.RouteCost(ctx,origin,{target},ctx.goal)
	return score*600
end
function T.LogChoice(bot,kind,count,score,side)
	Z.Log(bot,'route_choice',string.format('kind=%s candidates=%d selected_score=%.3f side=%s',kind,count,score,side or 'radial'))
end
return T
