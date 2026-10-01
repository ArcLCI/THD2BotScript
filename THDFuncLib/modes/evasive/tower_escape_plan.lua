-- 准备、提交、持续执行分离；本模块不在评分入口发单或占有动作锁。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_config')
local Geometry=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Routes=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/local_route_candidates')
local Exit=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/high_ground_exit')
local P={}
local function Copy(p) return p and Vector(p.x,p.y,p.z) or nil end
local function State(bot)
	bot.THD_TowerPlan=bot.THD_TowerPlan or {generation=0,retryAt=-90,nextSample=-90}
	return bot.THD_TowerPlan
end
local function Paused(bot)
	return Actions.Protected(bot) or bot:IsStunned() or bot:IsRooted() or bot:IsNightmared()
		or bot:HasModifier('modifier_teleporting') or bot:HasModifier('modifier_ability_thdots_chen01')
		or bot:NumQueuedActions()>0
end
local function Log(bot,state,event,reason)
	if not Config.DEBUG_LOG then return end
	local now=DotaTime()
	if event=='sample' and now-(state.logAt or -90)<2 then return end
	state.logAt=now
	local plan=state.plan or state.candidate or {}
	local pos=bot:GetLocation()
	print(string.format('[BOT][TowerPlan] run=%s time=%.3f pid=%s event=%s reason=%s generation=%s active=%s policy=%s phase=%s x=%.1f y=%.1f target_x=%s target_y=%s deadline=%s absolute_deadline=%s replans=%s entity=%s started_at=%s progress_at=%s traveled=%s change_kind=%s',
		Config.TOWER_PLAN_VERSION,now,bot:GetPlayerID(),event,reason,state.generation,tostring(state.active==true),
		tostring(plan.policy),tostring(plan.phase),pos.x,pos.y,tostring(plan.step and plan.step.x),tostring(plan.step and plan.step.y),
		tostring(plan.deadline),tostring(plan.absoluteDeadline),tostring(plan.replans),tostring(bot):gsub('%s','_'),
		tostring(plan.startedAt),tostring(plan.progressAt),tostring(plan.traveled or 0),
		(event=='replanned' and ((reason=='step_reached' or reason=='gate_reached') and 'waypoint' or 'material') or 'none')))
end
local function Release(bot,reason,retry)
	local state=State(bot)
	if state.plan or state.candidate then Log(bot,state,'released',reason) end
	if state.active and reason~='clearance_confirmed' and reason~='exit_reached' and reason~='left_high_ground'
	and reason~='combat_or_siege_authorized' then state.stopOwner='tower_plan_'..state.generation end
	state.plan,state.candidate,state.active=nil,nil,false
	state.replacement=nil
	state.retryAt=DotaTime()+(retry or 0)
	bot.THD_TowerEscapeActive=false
	-- 不清队列或其他模块动作；接替者由正常模式仲裁决定。
end
local function Segment(bot,point,context,highGround)
	if not point then return false end
	local origin=bot:GetLocation()
	if Geometry.Distance(origin,point)>1400 then return false end
	if not highGround and not Geometry.ValidateRecoverySegment(origin,point,context.zones,Config.DIRECT_EGRESS_SAFETY_MARGIN) then return false end
	return Geometry.ValidateLocalTerrainSegment(origin,point,false)
end
local function Step(bot,anchor,context,highGround,rejected)
	if highGround then
		for _,point in ipairs(Routes.Build(bot:GetLocation(),anchor)) do
			local excluded=false
			for _,old in ipairs(rejected or {}) do if Geometry.Distance(point,old)<120 then excluded=true;break end end
			if not excluded and Segment(bot,point,context,true) then return point end
		end
		if Geometry.Distance(bot:GetLocation(),anchor)<=120 and Segment(bot,anchor,context,true) then return Copy(anchor) end
		return nil
	end
	local full=Geometry.FindDirectEscapePoint(bot:GetLocation(),anchor,context.zones,Config.DIRECT_EGRESS_SAFETY_MARGIN)
	if full then
		for _,old in ipairs(rejected or {}) do if Geometry.Distance(full,old)<120 then full=nil;break end end
	end
	if full and Segment(bot,full,context,false) then return full end
	local point=Geometry.FindRecoveryStep(bot:GetLocation(),anchor,context.zones,Config.DIRECT_EGRESS_SAFETY_MARGIN,rejected or {})
	if point then return point end
	return Geometry.FindRecoveryStep(bot:GetLocation(),anchor,context.zones,Config.DIRECT_EGRESS_SAFETY_MARGIN,rejected or {},true)
end
local function Authorized(context)
	return not context.scan.triggered and ((context.scan.teamfightPriorityBypassCount or 0)>0
		or (context.scan.highGroundAssaultBypassCount or 0)>0)
end
local function Prepare(bot,context)
	local now=DotaTime()
	local route=Exit.Prepare(bot,context.scan)
	if not route and (not context.scan.triggered or not context.scan.anchor) then return nil,'no_confirmed_danger' end
	local anchor=route and route.gate or context.scan.anchor
	local point=Step(bot,anchor,context,route~=nil)
	if not point then return nil,'no_executable_step' end
	return {preparedAt=now,validUntil=now+Config.TOWER_PLAN_CANDIDATE_TTL,origin=Copy(bot:GetLocation()),
		anchor=Copy(anchor),step=Copy(point),route=route,phase=route and 'TO_GATE' or 'EGRESS',
		policy=route and route.policy or 'verified_egress',duration=route and route.deadline-route.startedAt or Config.TOWER_PLAN_MAX_TIME},nil
end
local function Clock(plan,paused)
	local now=DotaTime()
	if paused or plan.wasPaused then plan.deadline=math.min(plan.absoluteDeadline,plan.deadline+math.max(0,now-(plan.clockAt or now))) end
	plan.clockAt,plan.wasPaused=now,paused
end
local function Outside(bot,context)
	for _,zone in ipairs(context.zones) do
		if Geometry.PointInCircle(bot:GetLocation(),zone,Config.DIRECT_EGRESS_SAFETY_MARGIN) then return false end
	end
	return true
end
function P.New(environment)
	local C={}
	local function Context(bot,force)
		local state,now=State(bot),DotaTime()
		if force or not state.context or now>=state.nextSample then
			state.context=environment.Observe(bot);state.nextSample=now+Config.TOWER_PLAN_SAMPLE_INTERVAL
		end
		return state.context
	end
	function C.GetDesire(bot)
		local state,now=State(bot),DotaTime()
		if not state.readyLogged then state.readyLogged=true;Log(bot,state,'ready','enabled') end
		if not environment.Enabled(bot) or not bot:IsAlive() then Release(bot,'disabled_or_dead');return 0 end
		local context=Context(bot,false)
		if Authorized(context) then Release(bot,'combat_or_siege_authorized');return 0 end
		local plan=state.plan
		if plan then
			if plan.route and Exit.HasExited(bot,context.scan) then Release(bot,'left_high_ground');return 0 end
			Clock(plan,Paused(bot) or not state.active)
			if now>=plan.absoluteDeadline or (not Paused(bot) and now>=plan.deadline) then Release(bot,'deadline',Config.TOWER_PLAN_RETRY);return 0 end
			if Paused(bot) and not state.active then return 0 end
			-- 实质失效先评估替代路段再维持欲望；这里只准备，不修改正在执行的路段。
			local stalled=now-plan.progressAt>=Config.RECOVERY_STALL_TIME
				and (plan.bestStepDistance or math.huge)-Geometry.Distance(bot:GetLocation(),plan.step)<32
			if not Paused(bot) and (stalled or not Segment(bot,plan.step,context,plan.route~=nil)) then
				if plan.replans>=Config.TOWER_PLAN_MAX_REPLANS then Release(bot,'replan_budget',Config.RECOVERY_ADMISSION_INTERVAL);return 0 end
				local replacement=state.replacement
				if not replacement or now>=replacement.untilAt or replacement.plan~=plan
				or not Segment(bot,replacement.step,context,plan.route~=nil) then
					local rejected={};for _,point in ipairs(plan.rejected) do rejected[#rejected+1]=point end
					if stalled then rejected[#rejected+1]=plan.step end
					local step=Step(bot,plan.anchor,context,plan.route~=nil,rejected)
					if not step then Release(bot,'no_replacement_step',Config.TOWER_PLAN_RETRY);return 0 end
					state.replacement={plan=plan,anchor=Copy(plan.anchor),step=Copy(step),untilAt=now+Config.TOWER_PLAN_CANDIDATE_TTL}
				end
			end
			return BOT_MODE_DESIRE_ABSOLUTE
		end
		if Paused(bot) or now<state.retryAt then return 0 end
		if not context.scan.triggered and not (bot:GetActiveMode()==BOT_MODE_RETREAT
		and bot:GetActiveModeDesire()>=BOT_MODE_DESIRE_MODERATE) then state.candidate=nil;return 0 end
		if state.candidate and now<state.candidate.validUntil
		and Geometry.Distance(bot:GetLocation(),state.candidate.origin)<96
		and Segment(bot,state.candidate.step,context,state.candidate.route~=nil) then return BOT_MODE_DESIRE_ABSOLUTE end
		local candidate,reason=Prepare(bot,context)
		state.candidate=candidate
		if not candidate then
			state.retryAt=now+Config.TOWER_PLAN_RETRY
			if reason~='no_confirmed_danger' then Log(bot,state,'sample',reason) end
			return 0
		end
		Log(bot,state,'prepared','verified_step')
		return BOT_MODE_DESIRE_ABSOLUTE
	end
	function C.OnStart(bot)
		local state,now=State(bot),DotaTime()
		if Paused(bot) then return false end
		if state.plan then
			local context=Context(bot,true)
			local plan=state.plan
			local step=state.replacement and state.replacement.step or plan.step
			if Authorized(context) or now>=plan.absoluteDeadline
			or not Segment(bot,step,context,plan.route~=nil) then Release(bot,'resume_invalid',Config.TOWER_PLAN_RETRY);return false end
			state.active=true;bot.THD_TowerEscapeActive=true;return true
		end
		local candidate=state.candidate
		local context=Context(bot,true)
		if not candidate or now>=candidate.validUntil or Authorized(context)
		or not Segment(bot,candidate.step,context,candidate.route~=nil) then return false end
		state.plan=candidate;state.candidate=nil;state.active=true;state.generation=state.generation+1
		local plan=state.plan
		plan.startedAt,plan.progressAt,plan.clockAt=now,now,now
		plan.deadline=now+plan.duration;plan.absoluteDeadline=now+Config.TOWER_PLAN_MAX_TIME
		plan.progressLocation=Copy(bot:GetLocation());plan.lastLocation=Copy(bot:GetLocation())
		plan.bestStepDistance=Geometry.Distance(bot:GetLocation(),plan.step)
		plan.replans,plan.rejected=0,{}
		bot.THD_TowerEscapeActive=true
		bot.THD_TowerEscapeGeneration=(bot.THD_TowerEscapeGeneration or 0)+1
		Log(bot,state,'committed','mode_selected');return true
	end
	function C.Think(bot)
		local state,now=State(bot),DotaTime()
		-- 无效计划只在执行入口停止自己的旧移动；评分和模式交接不清动作队列。
		if state.stopOwner and not Paused(bot) then
			local intent=bot.THD_ActionIntent
			if intent and intent.owner==state.stopOwner and bot:GetCurrentActionType()==BOT_ACTION_TYPE_MOVE_TO then
				bot:Action_ClearActions(false);Actions.Forget(bot)
			end
			state.stopOwner=nil
		end
		if not environment.Enabled(bot) or not bot:IsAlive() then Release(bot,'disabled_or_dead');return false end
		if not state.plan or not state.active then if not C.OnStart(bot) then return false end end
		local plan=state.plan
		Clock(plan,Paused(bot))
		if now>=plan.absoluteDeadline then Release(bot,'absolute_deadline',Config.TOWER_PLAN_RETRY);return false end
		if Paused(bot) then plan.progressAt=now;plan.lastLocation=Copy(bot:GetLocation());return true end
		local context=Context(bot,false)
		if Authorized(context) then Release(bot,'combat_or_siege_authorized');return false end
		if now>=plan.deadline then Release(bot,'movement_deadline',Config.TOWER_PLAN_RETRY);return false end
		local current=bot:GetLocation()
		local deviation=Geometry.Distance(current,plan.lastLocation)>=Config.TOWER_PLAN_DEVIATION
		plan.traveled=(plan.traveled or 0)+Geometry.Distance(current,plan.lastLocation)
		plan.lastLocation=Copy(current)
		local stepDistance=Geometry.Distance(current,plan.step)
		if (plan.bestStepDistance or stepDistance)-stepDistance>=32 then
			plan.progressLocation,plan.progressAt=Copy(current),now;plan.replans=0
			plan.bestStepDistance=stepDistance
		end
		local changed
		if plan.route then
			if Exit.HasExited(bot,context.scan) then Release(bot,'left_high_ground');return true end
			local route=plan.route
			local direction=(route.outside-route.entry):Normalized()
			local projection=(current.x-route.entry.x)*direction.x+(current.y-route.entry.y)*direction.y
			if plan.phase=='TO_GATE' and (Geometry.Distance(current,route.gate)<=Config.HIGH_GROUND_EXIT_REACH or projection>=120) then
				plan.phase,plan.anchor='OUTWARD',Copy(route.outside);changed='gate_reached'
				Log(bot,state,'phase',changed)
			end
			if plan.phase=='OUTWARD' and Geometry.Distance(current,route.outside)<=180 then Release(bot,'exit_reached');return true end
			local layout=Exit.Observe(bot)
			if not layout.complete then Release(bot,'exit_layout_unknown',Config.TOWER_PLAN_RETRY);return false end
			if plan.phase=='TO_GATE' and layout.mask~=route.towerMask then
				local replacement=Exit.Prepare(bot,context.scan)
				if not replacement then Release(bot,'exit_changed_unavailable',Config.TOWER_PLAN_RETRY);return false end
				plan.route,plan.anchor=replacement,Copy(replacement.gate);changed='exit_changed'
			end
		elseif not context.scan.triggered and Outside(bot,context) then
			plan.clearSince=plan.clearSince or now
			if now-plan.clearSince>=Config.CLEARANCE_HOLD_TIME then Release(bot,'clearance_confirmed');return true end
		else plan.clearSince=nil end
		local reached=Geometry.Distance(current,plan.step)<=24
		local stalled=now-plan.progressAt>=Config.RECOVERY_STALL_TIME
		local unsafe=not Segment(bot,plan.step,context,plan.route~=nil)
		if changed or reached or stalled or unsafe or deviation then
			local reason=changed or (stalled and 'no_progress' or unsafe and 'segment_invalid' or deviation and 'displaced' or 'step_reached')
			if reason~='step_reached' and reason~='gate_reached' then
				plan.replans=plan.replans+1
				plan.rejected[#plan.rejected+1]=Copy(plan.step)
				if #plan.rejected>3 then table.remove(plan.rejected,1) end
			end
			if plan.replans>Config.TOWER_PLAN_MAX_REPLANS then Release(bot,'replan_budget',Config.RECOVERY_ADMISSION_INTERVAL);return false end
			local replacement=state.replacement
			local nextStep
			if replacement and replacement.plan==plan and now<replacement.untilAt
			and Geometry.Distance(replacement.anchor,plan.anchor)<1 and Segment(bot,replacement.step,context,plan.route~=nil) then nextStep=replacement.step end
			state.replacement=nil
			nextStep=nextStep or Step(bot,plan.anchor,context,plan.route~=nil,plan.rejected)
			if not nextStep then Release(bot,'no_replacement_step',Config.TOWER_PLAN_RETRY);return false end
			plan.step,plan.progressAt=Copy(nextStep),now
			plan.bestStepDistance=Geometry.Distance(current,nextStep)
			Log(bot,state,'replanned',reason)
		end
		local owner='tower_plan_'..state.generation
		local intent=bot.THD_ActionIntent
		if intent and intent.owner==owner and bot:GetCurrentActionType()==BOT_ACTION_TYPE_MOVE_TO
		and Geometry.Distance(intent.location,plan.step)<=24 then Log(bot,state,'sample','continuing');return true end
		local accepted,issued=Actions.Move(bot,plan.step,24,'move',false,owner)
		if not accepted then Release(bot,'submit_rejected',Config.TOWER_PLAN_RETRY);return false end
		Log(bot,state,issued and 'issued' or 'sample',issued and 'planned_step' or 'continuing')
		return true
	end
	function C.OnEnd(bot)
		local state=State(bot);state.active=false;bot.THD_TowerEscapeActive=false
		-- 交接只释放执行权，计划和绝对期限保留，恢复前再次验证。
		if state.plan then state.plan.wasPaused=true;Log(bot,state,'suspended','mode_end') end
	end
	function C.Reset(bot,reason) Release(bot,reason or 'reset') end
	function C.IsActionLocked(bot) return bot~=nil and (bot.THD_SkillEscapeActive==true or State(bot).active==true) end
	function C.Flush(bot)
		local state=State(bot)
		if state.stopOwner and not Paused(bot) then
			local intent=bot.THD_ActionIntent
			if intent and intent.owner==state.stopOwner and bot:GetCurrentActionType()==BOT_ACTION_TYPE_MOVE_TO then
				bot:Action_ClearActions(false);Actions.Forget(bot)
			end
			state.stopOwner=nil
		end
	end
	local Think=C.Think
	function C.Think(bot)
		local result=Think(bot)
		C.Flush(bot)
		return result
	end
	return C
end
return P
