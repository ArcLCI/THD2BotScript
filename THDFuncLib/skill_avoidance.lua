local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local G = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Z = require(GetScriptDirectory()..'/THDFuncLib/skill_zones')
local P = require(GetScriptDirectory()..'/THDFuncLib/skill_avoidance_geometry')
local Tower = require(GetScriptDirectory()..'/THDFuncLib/tower_safety')
local Threat = require(GetScriptDirectory()..'/THDFuncLib/skill_threat')
local Skill = {}
local function Safe(default, fn) local ok,v=pcall(fn); if ok and v~=nil then return v end; return default end
local function Now() return Safe(0,DotaTime) end
local function Copy(p) return G.MakeVector(p.x,p.y,p.z) end
local function State(bot)
	if bot.THD_SkillAvoidance == nil then bot.THD_SkillAvoidance={active=false, generation=0, ignored={}} end
	return bot.THD_SkillAvoidance
end
-- 同一来源固定进入边界；退出使用更外侧边界，避免减速结束导致原地反复接管。
local function EntryInside(bot,state,zones)
	state.boundaries=state.boundaries or {}
	local now,current,live,inside=Now(),bot:GetLocation(),{},{}
	local physical=P.Margin(bot)-P.Speed(bot)*Config.SKILL_SCAN_INTERVAL
	for _,z in ipairs(zones) do
		live[z.key]=true
		local boundary=state.boundaries[z.key]
		local margin=boundary and math.max(physical,boundary.entry) or P.Margin(bot)
		if G.PointInCircle(current,z,margin) then table.insert(inside,z) end
	end
	for key,b in pairs(state.boundaries) do if not live[key] or now>=b.expiresAt then state.boundaries[key]=nil end end
	return inside
end
local function ExitMargin(bot,state)
	state.exitMargin=math.max(state.exitMargin or 0,P.Margin(bot)+Config.SKILL_EXIT_HYSTERESIS)
	return state.exitMargin
end
local function ExitReason(state,zones)
	local live={}
	for _,z in ipairs(zones) do live[z.key]=true end
	for _,z in ipairs(state.zones or {}) do if live[z.key] then return 'safe_exit' end end
	return 'source_expired'
end
local function LogBoundary(bot,state,event,zones)
	local current=bot:GetLocation()
	for _,z in ipairs(zones or state.zones or {}) do
		local boundary=state.boundaries and state.boundaries[z.key]
		Z.Log(bot,event,string.format('generation=%d key=%s x=%.1f y=%.1f center_x=%.1f center_y=%.1f distance=%.1f radius=%.1f live_margin=%.1f entry_margin=%.1f exit_margin=%.1f speed=%.1f remaining=%.3f mode=%s action=%s',
			state.generation,z.key,current.x,current.y,z.center.x,z.center.y,G.Distance(current,z.center),z.radius,
			P.Margin(bot),boundary and boundary.entry or P.Margin(bot),state.exitMargin or 0,P.Speed(bot),z.expiresAt-Now(),
			tostring(Safe(-1,function() return bot:GetActiveMode() end)),tostring(Safe(-1,function() return bot:GetCurrentActionType() end))))
	end
end
local function Protected(bot)
	if Safe(false,function() return bot:IsCastingAbility() or bot:IsUsingAbility() or bot:IsChanneling() end)
	or Safe(-1,function() return bot:NumQueuedActions() end)~=0
	or Safe(false,function() return bot:HasModifier('modifier_teleporting') or bot:HasModifier('modifier_ability_thdots_chen01') end) then return true end
	local ability=Safe(nil,function() return bot:GetCurrentActiveAbility() end)
	return ability~=nil and Safe(true,function() return ability:IsInAbilityPhase() or ability:IsChanneling() end)
end
local function NoteProtected(bot,state)
	if Now() < (state.nextProtectedLog or -90) then return end
	state.nextProtectedLog=Now()+0.5
	Z.Log(bot,'escape_protected',string.format('generation=%d deadline=%.3f queued=%s casting=%s channeling=%s',
		state.generation,state.deadline,tostring(Safe(-1,function() return bot:NumQueuedActions() end)),
		tostring(Safe(false,function() return bot:IsCastingAbility() or bot:IsUsingAbility() end)),
		tostring(Safe(false,function() return bot:IsChanneling() end))))
end
-- 分别记录两个接口的状态；查询失败继续保守阻止移动，不与真实控制混为一谈。
local function MovementState(bot)
	local stunOK,stunned=pcall(function() return bot:IsStunned() end)
	local rootOK,rooted=pcall(function() return bot:IsRooted() end)
	stunOK=stunOK and type(stunned)=='boolean';rootOK=rootOK and type(rooted)=='boolean'
	local reason=stunOK and stunned and 'stunned' or rootOK and rooted and 'rooted'
		or (not stunOK or not rootOK) and 'movement_query_failed' or nil
	return reason,{stunned=stunOK and tostring(stunned) or 'query_failed',rooted=rootOK and tostring(rooted) or 'query_failed'}
end
local function LogMovement(bot,state,site,reason,status)
	Z.Log(bot,'movement_gate',string.format('generation=%d site=%s reason=%s stunned=%s rooted=%s deadline=%.3f deadline_reached=%d active=%d acquired=%d',
		state.generation,site,reason,status.stunned,status.rooted,state.deadline or -1, state.deadline and Now()>=state.deadline and 1 or 0,state.active and 1 or 0,state.acquired and 1 or 0))
end
local function Towers(bot) local obs=Tower.Observe(bot,'skill_avoidance'); return obs.available and obs.towers or nil end
local function Signature(zones) local keys={}; for _,z in ipairs(zones) do table.insert(keys,z.key) end; return table.concat(keys,'|') end
local function Stop(bot,state,task)
	local order=state.order
	if task then order=state.taskOrder end
	if order==nil or Protected(bot) then return false end
	if Safe(-1,function() return bot:GetActiveMode() end)~=order.mode
	or Safe(-1,function() return bot:GetCurrentActionType() end)~=(order.actionType or BOT_ACTION_TYPE_MOVE_TO)
	or (task and Now()-(order.confirmedAt or order.at)>1) then return false end
	bot:Action_ClearActions(true)
	if task then state.taskOrder=nil else state.order=nil end
	return true
end
local function AuditRoute(bot,state,zones)
	local mode=Safe(-1,function() return bot:GetActiveMode() end)
	if state.taskOrder~=nil and state.taskOrder.mode~=mode then state.taskOrder=nil end
	local route=state.route
	if route~=nil and (route.mode~=mode or (route.sourceSignature or route.signature)~=Signature(zones)) then
		local stopped=Stop(bot,state,true)
		if route.mode==mode then state.resumeOwner=route.owner end
		state.route=nil
		Z.Log(bot,'route_invalidated',string.format('owner=%s reason=mode_or_sources_changed stopped=%d',route.owner,stopped and 1 or 0))
	end
end
local function Ignore(state,zones) for _,z in ipairs(zones) do state.ignored[z.key]=z.expiresAt end end
local function Release(bot,state,reason,failed,zones)
	if not state.active then return end
	local stopped=Stop(bot,state,false)
	LogBoundary(bot,state,'escape_release_boundary',state.zones)
	if failed then
		local involved, initial = {}, {}
		for _,z in ipairs(state.zones or {}) do initial[z.key]=true end
		for _,z in ipairs(zones or state.zones or {}) do
			if initial[z.key] or G.PointInCircle(bot:GetLocation(),z,P.Margin(bot)) then table.insert(involved,z) end
		end
		Ignore(state,involved)
	end
	Z.Log(bot,'escape_released',string.format('generation=%d reason=%s failed=%d held_for=%.3f stopped=%d acquired=%d phase=%s',state.generation,reason,failed and 1 or 0,Now()-state.startedAt,stopped and 1 or 0,state.acquired and 1 or 0,state.phase or 'escape'))
	state.active=false;state.order=nil;state.target=nil;state.phase=nil;bot.THD_SkillEscapeActive=false
end
-- 撤退桥接沿用同一动作所有权，但独立记录时限；每个来源只尝试一次，不无限续租。
local function DecisionContext(bot,state)
	local ctx={};for k,v in pairs(Threat.Context(bot)) do ctx[k]=v end
	local intent=state.observedIntent
	if not state.active and intent and ctx.mode==intent.mode and Now()-intent.at<=1 then
		ctx.goal=intent.goal;ctx.goalKind='task_'..intent.owner
	end
	if state.active then
		ctx.committed={};for _,z in ipairs(state.zones or {}) do ctx.committed[z.key]=true end
		if state.intentGoal then ctx.goal=state.intentGoal;ctx.goalKind=state.intentKind;ctx.retreat=state.intentRetreat==true end
	end
	return ctx
end
-- 未开始桥接也要可归因；按原因和来源节流，不能把日志条数当作规划次数。
local function BridgeGate(bot,state,zones,ctx,reason,extra)
	if #zones==0 then return end
	state.bridgeDiagnostics=state.bridgeDiagnostics or {}
	local key=reason..':'..Signature(zones)
	if Now()<(state.bridgeDiagnostics[key] or -90) then return end
	state.bridgeDiagnostics[key]=Now()+1
	local current=bot:GetLocation()
	Z.Log(bot,'bridge_gate',string.format('generation=%d active=%d reason=%s keys=%s mode=%s retreat=%d goal_kind=%s x=%.1f y=%.1f goal_x=%.1f goal_y=%.1f %s',
		state.generation,state.active and 1 or 0,reason,Signature(zones),tostring(ctx.mode),ctx.retreat and 1 or 0,ctx.goalKind or 'none',
		current.x,current.y,ctx.goal and ctx.goal.x or 0,ctx.goal and ctx.goal.y or 0,extra or ''))
end
local function BridgePathProbe(bot,state,zones,ctx)
	local current,margin,speed=bot:GetLocation(),P.Margin(bot),P.Speed(bot)
	for _,z in ipairs(zones) do
		local distance=P.EntryDistance(current,ctx.goal,z,margin)
		local intersects=distance<math.huge
		local eta=intersects and distance/speed or -1
		local remaining=z.expiresAt-Now()
		local reason=not intersects and 'no_intersection' or eta>=remaining+Config.SKILL_TIME_MARGIN and 'expires_before_entry'
			or eta>=Config.SKILL_LOOKAHEAD_TIME and 'outside_lookahead' or 'blocked_in_window'
		Z.Log(bot,'bridge_path_probe',string.format('generation=%d key=%s reason=%s entry_distance=%.1f eta=%.3f remaining=%.3f margin=%.1f x=%.1f y=%.1f center_x=%.1f center_y=%.1f radius=%.1f goal_x=%.1f goal_y=%.1f',
			state.generation,z.key,reason,intersects and distance or -1,eta,remaining,margin,current.x,current.y,z.center.x,z.center.y,z.radius,ctx.goal.x,ctx.goal.y))
	end
end
local function StartBridge(bot,state,zones,ctx)
	if not ctx.retreat then BridgeGate(bot,state,zones,ctx,'not_retreat');return false end
	if not ctx.goal then BridgeGate(bot,state,zones,ctx,'goal_unavailable');return false end
	state.bridgeUsed=state.bridgeUsed or {}
	local now=Now()
	if state.active and now>=state.deadline then BridgeGate(bot,state,zones,ctx,'escape_deadline');return false end
	if now<(state.bridgePlanAt or -90) then BridgeGate(bot,state,zones,ctx,'plan_cooldown');return false end
	state.bridgePlanAt=now+0.5
	state.bridgeAttempts=state.bridgeAttempts or {}
	for key,expires in pairs(state.bridgeUsed) do if now>=expires then state.bridgeUsed[key]=nil end end
	local eligible=false
	for _,z in ipairs(zones) do if not state.bridgeUsed[z.key] and not state.ignored[z.key] and (state.bridgeAttempts[z.key] or 0)<2 then eligible=true end end
	if not eligible then
		local used,ignored,limited=0,0,0
		for _,z in ipairs(zones) do
			if state.bridgeUsed[z.key] then used=used+1 end
			if state.ignored[z.key] then ignored=ignored+1 end
			if (state.bridgeAttempts[z.key] or 0)>=2 then limited=limited+1 end
		end
		BridgeGate(bot,state,zones,ctx,'no_eligible_source',string.format('used=%d ignored=%d attempts_exhausted=%d',used,ignored,limited));return false
	end
	local towers=Towers(bot)
	if not towers then BridgeGate(bot,state,zones,ctx,'tower_observation_unavailable');return false end
	BridgePathProbe(bot,state,zones,ctx)
	ctx.allowLocalRetreatGoal=ctx.goalKind=='own_ancient_direction'
	ctx.bridgeBudget=math.min(Config.SKILL_RETREAT_BRIDGE_TIME,state.active and state.startedAt+Config.SKILL_ESCAPE_TIME+Config.SKILL_RETREAT_BRIDGE_TIME-now or Config.SKILL_RETREAT_BRIDGE_TIME)
	local points,reason,count,resolvedGoal=P.FindDetour(bot,ctx.goal,zones,towers,now,ctx)
	if reason~='clear' then for _,z in ipairs(zones) do state.bridgeAttempts[z.key]=(state.bridgeAttempts[z.key] or 0)+1 end end
	if not points then
		BridgeGate(bot,state,zones,ctx,reason,'candidates='..tostring(count))
		if reason~='clear' then Z.Log(bot,'bridge_unhandled','reason='..reason..' goal_kind='..tostring(ctx.goalKind)) end
		return false
	end
	local fresh=not state.active
	if not fresh then
		LogBoundary(bot,state,'escape_exit_boundary',state.zones)
		Z.Log(bot,'escape_phase_complete',string.format('generation=%d reason=safe_exit next=bridge',state.generation))
	end
	if fresh then
		state.generation=state.generation+1;state.startedAt=now;state.acquired=false;state.active=true
		state.zones=zones;state.exitMargin=P.Margin(bot)+Config.SKILL_EXIT_HYSTERESIS
	end
	for _,z in ipairs(zones) do state.bridgeUsed[z.key]=z.expiresAt end
	state.phase='bridge';state.bridgePoints=points;state.bridgeIndex=1;state.bridgeSignature=Signature(zones)
	state.intentGoal=Copy(resolvedGoal or ctx.goal);state.intentKind=ctx.goalKind;state.intentRetreat=true
	if resolvedGoal and G.Distance(resolvedGoal,ctx.goal)>1 then
		state.intentKind='validated_local_retreat'
		Z.Log(bot,'bridge_goal_resolved',string.format('generation=%d projected_x=%.1f projected_y=%.1f goal_x=%.1f goal_y=%.1f',state.generation,ctx.goal.x,ctx.goal.y,resolvedGoal.x,resolvedGoal.y))
	end
	state.deadline=math.min(now+Config.SKILL_RETREAT_BRIDGE_TIME,state.startedAt+Config.SKILL_ESCAPE_TIME+Config.SKILL_RETREAT_BRIDGE_TIME)
	state.progress=Copy(bot:GetLocation());state.progressAt=now;state.nextAction=-90;state.target=points[1]
	if fresh then Z.Log(bot,'escape_requested',string.format('generation=%d keys=%s candidates=%d target_x=%.1f target_y=%.1f deadline=%.3f partial=0 phase=bridge',
		state.generation,Signature(zones),count,state.target.x,state.target.y,state.deadline)) end
	Z.Log(bot,'bridge_started',string.format('generation=%d waypoints=%d deadline=%.3f goal_x=%.1f goal_y=%.1f goal_kind=%s',
		state.generation,#points,state.deadline,state.intentGoal.x,state.intentGoal.y,tostring(state.intentKind)))
	return true
end
local function BridgeThink(bot,state,zones,ctx)
	local current=bot:GetLocation()
	if Signature(zones)~=state.bridgeSignature then Release(bot,state,'bridge_sources_changed',false);return true end
	local towers=Towers(bot)
	if not towers then Release(bot,state,'bridge_towers_unavailable',true,zones);return true end
	local margin=P.Margin(bot)
	if #P.LiveForSegment(current,state.intentGoal,zones,margin,P.Speed(bot),Now())==0
	and P.SafeSegment(current,state.intentGoal,zones,towers,margin) then
		Z.Log(bot,'bridge_handoff',string.format('generation=%d reason=projected_segment_clear goal_kind=%s',state.generation,tostring(state.intentKind)))
		Release(bot,state,'bridge_handoff',false);return true
	end
	if G.Distance(current,state.progress)>=48 then state.progress=Copy(current);state.progressAt=Now() end
	if Now()-state.progressAt>=1 then Release(bot,state,'bridge_stalled',true,zones);return true end
	while state.bridgeIndex<#state.bridgePoints and state.bridgePoints[state.bridgeIndex] and G.Distance(current,state.bridgePoints[state.bridgeIndex])<=24 do state.bridgeIndex=state.bridgeIndex+1 end
	local target=state.bridgePoints[state.bridgeIndex]
	if not target then Release(bot,state,'bridge_waypoint_missing',true,zones);return true end
	local safe,reason,detail=P.SafeSegment(current,target,zones,towers,margin)
	if not safe then
		local constraint=detail and detail.constraint
		local sample=detail and detail.sample
		local point=sample and sample.point
		Z.Log(bot,'bridge_segment_rejected',string.format('generation=%d waypoint=%d reason=%s kind=%s constraint_key=%s from_x=%.1f from_y=%.1f to_x=%.1f to_y=%.1f margin=%.1f remaining_budget=%.3f constraint_x=%.1f constraint_y=%.1f constraint_radius=%.1f sample_x=%.1f sample_y=%.1f sample_index=%d sample_steps=%d',
			state.generation,state.bridgeIndex,tostring(reason),detail and detail.kind or 'unknown',constraint and tostring(constraint.key) or 'none',
			current.x,current.y,target.x,target.y,margin,state.deadline-Now(),constraint and constraint.center.x or 0,constraint and constraint.center.y or 0,constraint and constraint.radius or 0,
			point and point.x or 0,point and point.y or 0,sample and sample.index or -1,sample and sample.steps or -1))
		Release(bot,state,'bridge_segment_unsafe',true,zones);return true
	end
	-- 追兵快照更新后重新检查当前段，明显增加受击风险时有限交还，不硬走旧路线。
	local _,risk=Threat.RouteCost(ctx,current,{target},state.intentGoal)
	if risk>0.35 then Release(bot,state,'bridge_pursuer_risk',true,zones);return true end
	if Now()>=state.nextAction then
		state.nextAction=Now()+0.18;bot:Action_MoveToLocation(target)
		state.order={mode=BOT_MODE_EVASIVE_MANEUVERS,at=Now(),target=Copy(target)}
		Z.Log(bot,'bridge_move',string.format('generation=%d waypoint=%d x=%.1f y=%.1f target_x=%.1f target_y=%.1f pursuit_risk=%.3f',
			state.generation,state.bridgeIndex,current.x,current.y,target.x,target.y,risk))
	end
	return true
end
function Skill.IsActive(bot) return bot~=nil and State(bot).active end
function Skill.GetDesire(bot)
	local state=State(bot)
	if not Z.Enabled() or not Safe(false,function() return bot:IsAlive() end) then
		Release(bot,state,'disabled_or_dead',false);Z.Update(bot);return BOT_MODE_DESIRE_NONE
	end
	local now,rawZones=Now(),Z.Get(bot)
	AuditRoute(bot,state,rawZones)
	if #rawZones==0 and not (state.active and Protected(bot)) then Release(bot,state,'source_expired',false);state.boundaries={};state.bridgeUsed={};state.bridgeAttempts={};state.bridgeDiagnostics={};return BOT_MODE_DESIRE_NONE end
	local ctx=DecisionContext(bot,state)
	local zones=Threat.SelectZones(bot,rawZones,ctx,ctx.goal,'escape')
	for key,expires in pairs(state.ignored) do if now>=expires then state.ignored[key]=nil end end
	local inside={}
	local hazardous={};for _,z in ipairs(zones) do hazardous[z.key]=true end
	for _,z in ipairs(EntryInside(bot,state,rawZones)) do if hazardous[z.key] then table.insert(inside,z) end end
	if state.active then
		if Protected(bot) then
			if not state.acquired then Release(bot,state,'protected_before_start',false);return BOT_MODE_DESIRE_NONE end
			NoteProtected(bot,state);return BOT_MODE_DESIRE_ABSOLUTE
		end
		if Safe(false,function() return bot:IsInvulnerable() end) then Release(bot,state,'invulnerable',false);return BOT_MODE_DESIRE_NONE end
		if #zones==0 then Release(bot,state,#rawZones==0 and 'source_expired' or 'threat_tolerable',false);return BOT_MODE_DESIRE_NONE end
		if state.phase~='bridge' and #P.Inside(bot:GetLocation(),zones,ExitMargin(bot,state))==0 then
			if state.acquired and StartBridge(bot,state,zones,ctx) then return BOT_MODE_DESIRE_ABSOLUTE end
			Release(bot,state,ExitReason(state,rawZones),false);return BOT_MODE_DESIRE_NONE
		end
		local movementReason,movementStatus=MovementState(bot)
		if now>=state.deadline or movementReason then
			local reason=movementReason or 'time_budget';LogMovement(bot,state,'GetDesire',reason,movementStatus)
			Release(bot,state,reason,true,zones);return BOT_MODE_DESIRE_NONE
		end
		return BOT_MODE_DESIRE_ABSOLUTE
	end
	if Protected(bot) then BridgeGate(bot,state,rawZones,ctx,'protected');return BOT_MODE_DESIRE_NONE end
	local movementReason,movementStatus=MovementState(bot)
	if movementReason then
		BridgeGate(bot,state,rawZones,ctx,movementReason,'stunned='..movementStatus.stunned..' rooted='..movementStatus.rooted);return BOT_MODE_DESIRE_NONE
	end
	if Safe(false,function() return bot:IsInvulnerable() end) then BridgeGate(bot,state,rawZones,ctx,'invulnerable');return BOT_MODE_DESIRE_NONE end
	if #zones==0 then BridgeGate(bot,state,rawZones,ctx,'threat_tolerable') end
	if #inside>0 then BridgeGate(bot,state,zones,ctx,'inside_egress_first') end
	if #inside==0 then
		if #zones>0 and StartBridge(bot,state,zones,ctx) then return BOT_MODE_DESIRE_ABSOLUTE end
		return BOT_MODE_DESIRE_NONE
	end
	local eligible=false
	for _,z in ipairs(inside) do if state.ignored[z.key]==nil then eligible=true end end
	if not eligible then return BOT_MODE_DESIRE_NONE end
	local towers=Towers(bot)
	local target,count,partial
	state.exitMargin=P.Margin(bot)+Config.SKILL_EXIT_HYSTERESIS
	for _,z in ipairs(inside) do
		local boundary=state.boundaries[z.key]
		if boundary then state.exitMargin=math.max(state.exitMargin,boundary.entry+Config.SKILL_EXIT_HYSTERESIS) end
	end
	if towers~=nil then target,count,partial=P.FindExit(bot,zones,towers,Config.SKILL_ESCAPE_TIME,nil,state.exitMargin,ctx) end
	if target==nil then
		Ignore(state,inside)
		Z.Log(bot,'escape_unhandled','reason=no_safe_candidate keys='..Signature(inside))
		return BOT_MODE_DESIRE_NONE
	end
	state.active=true;state.acquired=false;state.generation=state.generation+1;state.startedAt=now;state.deadline=now+Config.SKILL_ESCAPE_TIME
	state.phase='escape';state.intentGoal=ctx.goal and Copy(ctx.goal) or nil;state.intentKind=ctx.goalKind;state.intentRetreat=ctx.retreat
	state.target=target;state.partial=partial;state.zones=inside;state.replans=0;state.candidates=count;state.progress=Copy(bot:GetLocation());state.progressAt=now;state.nextAction=-90
	for _,z in ipairs(inside) do
		local prior=state.boundaries[z.key]
		if prior==nil then state.boundaries[z.key]={entry=P.Margin(bot),expiresAt=z.expiresAt} end
		Z.Log(bot,'escape_trigger',string.format('generation=%d key=%s kind=%s',state.generation,z.key,prior and 'reentry' or 'first'))
	end
	LogBoundary(bot,state,'escape_request_boundary',inside)
	-- 请求欲望不等于赢得模式；实际Think接管前不能锁住默认撤退或物品逻辑。
	Z.Log(bot,'escape_requested',string.format('generation=%d keys=%s candidates=%d target_x=%.1f target_y=%.1f deadline=%.3f partial=%d',state.generation,Signature(inside),count,target.x,target.y,state.deadline,partial and 1 or 0))
	return BOT_MODE_DESIRE_ABSOLUTE
end
function Skill.Think(bot)
	local state=State(bot)
	if not state.active then return false end
	if Protected(bot) then
		if not state.acquired then Release(bot,state,'protected_before_start',false);return true end
		NoteProtected(bot,state);return true
	end
	local now,rawZones=Now(),Z.Get(bot)
	local ctx=DecisionContext(bot,state)
	local zones=Threat.SelectZones(bot,rawZones,ctx,ctx.goal,'escape')
	if not Z.Enabled() then Release(bot,state,'disabled',false);return true end
	if #zones==0 then Release(bot,state,#rawZones==0 and 'source_expired' or 'threat_tolerable',false);return true end
	if state.phase~='bridge' and #P.Inside(bot:GetLocation(),zones,ExitMargin(bot,state))==0 then
		if not state.acquired or not StartBridge(bot,state,zones,ctx) then Release(bot,state,ExitReason(state,rawZones),false);return true end
	end
	local movementReason,movementStatus=MovementState(bot)
	if now>=state.deadline or movementReason then
		local reason=now>=state.deadline and 'time_budget' or movementReason
		LogMovement(bot,state,'Think',reason,movementStatus);Release(bot,state,reason,true,zones);return true
	end
	if Safe(-1,function() return bot:GetActiveMode() end)~=BOT_MODE_EVASIVE_MANEUVERS then return false end
	if not state.acquired then
		state.acquired=true;bot.THD_SkillEscapeActive=true
		Z.Log(bot,'escape_acquired',string.format('generation=%d deadline=%.3f',state.generation,state.deadline))
	end
	if state.phase=='bridge' then return BridgeThink(bot,state,zones,ctx) end
	local current,towers=bot:GetLocation(),Towers(bot)
	if state.partial and G.Distance(current,state.target)<=24 then Release(bot,state,'partial_step_complete',true,zones);return true end
	if G.Distance(current,state.progress)>=48 then state.progress=Copy(current);state.progressAt=now end
	local unsafe=towers==nil or not P.SafeSegment(current,state.target,zones,towers,ExitMargin(bot,state))
		or (not state.partial and #P.Inside(state.target,zones,ExitMargin(bot,state))>0) or now-state.progressAt>=Config.SKILL_STALL_TIME
	if unsafe then
		Stop(bot,state,false)
		if state.replans>=1 or towers==nil then Release(bot,state,'no_progress_or_unsafe',true,zones);return true end
		local target,count,partial=P.FindExit(bot,zones,towers,state.deadline-now,state.target,ExitMargin(bot,state),ctx)
		state.replans=state.replans+1;state.candidates=state.candidates+(count or 0)
		if target==nil then Release(bot,state,'replan_failed',true,zones);return true end
		state.target=target;state.partial=partial;state.progress=Copy(current);state.progressAt=now;state.nextAction=-90
		Z.Log(bot,'escape_replanned',string.format('generation=%d candidates_total=%d target_x=%.1f target_y=%.1f',state.generation,state.candidates,target.x,target.y))
		return true
	end
	if now>=state.nextAction then
		state.nextAction=now+0.18
		bot:Action_MoveToLocation(state.target)
		state.order={mode=BOT_MODE_EVASIVE_MANEUVERS,at=now,target=Copy(state.target)}
		Z.Log(bot,'escape_move',string.format('generation=%d x=%.1f y=%.1f target_x=%.1f target_y=%.1f',state.generation,current.x,current.y,state.target.x,state.target.y))
	end
	return true
end
function Skill.OnEnd(bot) Release(bot,State(bot),'mode_ended',true) end
function Skill.SupportsTask(name)
	return type(name)=='string' and (string.sub(name,1,10)=='lane_work_' or string.sub(name,1,5)=='rune_' or name=='idle_available_rune')
end
function Skill.NoteTaskMove(bot,owner,target,kind,actionType)
	State(bot).taskOrder={owner=owner,mode=bot:GetActiveMode(),target=Copy(target),at=Now(),confirmedAt=Now(),actionType=actionType or BOT_ACTION_TYPE_MOVE_TO}
	if kind=='detour' or kind=='task_egress' then
		local current=bot:GetLocation()
		Z.Log(bot,'route_move',string.format('owner=%s kind=%s x=%.1f y=%.1f target_x=%.1f target_y=%.1f',owner,kind,current.x,current.y,target.x,target.y))
	end
end
function Skill.RejectTaskMove(bot,owner,reason)
	local state=State(bot)
	if state.taskOrder~=nil and state.taskOrder.owner==owner then Stop(bot,state,true) end
	if state.route~=nil then state.route.blocked=true end
	Z.Log(bot,'route_unhandled','owner='..owner..' reason='..reason)
end
function Skill.ResolveMove(bot,owner,goal)
	local state=State(bot)
	if not Z.Enabled() then state.route=nil;return goal,'original' end
	if state.active or Protected(bot) then return nil,'protected' end
	if Safe(false,function() return bot:IsInvulnerable() end) then state.route=nil;return goal,'original' end
	local now,rawZones=Now(),Z.Get(bot)
	AuditRoute(bot,state,rawZones)
	local ctx=#rawZones>0 and Threat.Context(bot) or nil
	local zones=ctx and Threat.SelectZones(bot,rawZones,ctx,goal,owner) or {}
	local mode=bot:GetActiveMode()
	state.observedIntent={goal=Copy(goal),owner=owner,mode=mode,at=now}
	if state.taskOrder~=nil and state.taskOrder.owner==owner and state.taskOrder.mode==mode then state.taskOrder.confirmedAt=now end
	local current,margin=bot:GetLocation(),P.Margin(bot)
	if #zones>0 and now>=(state.intentLogAt or -90) then
		state.intentLogAt=now+1
		Z.Log(bot,'move_intent',string.format('owner=%s x=%.1f y=%.1f goal_x=%.1f goal_y=%.1f',owner,current.x,current.y,goal.x,goal.y))
	end
	if #P.Inside(current,zones,margin)>0 then
		-- 交还控制后仍允许原任务沿已验证的向外目标离开，不能用来源抑制把任务冻在圈内。
		local towers=Towers(bot)
		if towers~=nil and #P.Inside(goal,zones,margin)==0 and P.SafeSegment(current,goal,zones,towers,margin) then
			state.route=nil
			return goal,'task_egress'
		end
		if state.taskOrder~=nil and state.taskOrder.owner==owner then Stop(bot,state,true) end
		return nil,'inside_skill_zone'
	end
	local sig=Signature(zones)
	local route=state.route
	local force=state.resumeOwner==owner
	state.resumeOwner=nil
	if route~=nil and (route.owner~=owner or route.mode~=mode or G.Distance(goal,route.goal)>96 or route.signature~=sig) then
		if state.taskOrder~=nil and state.taskOrder.owner==owner then Stop(bot,state,true) end
		Z.Log(bot,'route_invalidated','owner='..owner..' reason=intent_or_sources_changed')
		state.route=nil;route=nil;force=true
	end
	if #P.LiveForSegment(current,goal,zones,margin,P.Speed(bot),now)==0 then
		if route~=nil then
			if state.taskOrder~=nil and state.taskOrder.owner==owner then Stop(bot,state,true) end
			Z.Log(bot,'route_released','owner='..owner..' reason=clear_or_expires_before_arrival')
		end
		state.route=nil;return goal,'original',force or route~=nil
	end
	if route~=nil and route.blocked then return nil,'route_blocked' end
	local towers=Towers(bot)
	if towers==nil then Skill.RejectTaskMove(bot,owner,'tower_observation_missing');return nil,'unavailable' end
	if route~=nil then
		if G.Distance(current,route.progress)>=48 then route.progress=Copy(current);route.progressAt=now end
		local stalled=now-route.progressAt>=1
		while route.points[route.index]~=nil and G.Distance(current,route.points[route.index])<=24 do route.index=route.index+1 end
		local target=route.points[route.index]
		if target~=nil then
			local live=P.LiveForSegment(current,target,zones,margin,P.Speed(bot),now)
			if not stalled and P.SafeSegment(current,target,live,towers,margin) then return target,'detour' end
		end
		if state.taskOrder~=nil and state.taskOrder.owner==owner then Stop(bot,state,true) end
		force=true
		if (route.replans or 0)>=1 then route.blocked=true;Skill.RejectTaskMove(bot,owner,'route_invalidated_twice');return nil,'unavailable' end
	end
	local points,reason,count=P.FindDetour(bot,goal,zones,towers,now,ctx)
	if points==nil and reason=='clear' then state.route=nil;return goal,'original',force end
	state.route={owner=owner,mode=mode,goal=Copy(goal),signature=sig,sourceSignature=Signature(rawZones),points=points,index=1,progress=Copy(current),progressAt=now,replans=route~=nil and 1 or 0,blocked=points==nil}
	if points==nil then Skill.RejectTaskMove(bot,owner,reason);return nil,reason end
	Z.Log(bot,'route_created',string.format('owner=%s candidates=%d waypoints=%d goal_x=%.1f goal_y=%.1f',owner,count,#points,goal.x,goal.y))
	return points[1],'detour',force
end
return Skill
