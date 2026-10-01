-- ROAM 内部同模式交接；原生 Attack/Retreat 仍由引擎仲裁，不主动抢回模式。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Tasks=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_task')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Auxiliary=require(GetScriptDirectory()..'/THDFuncLib/modes/roam/roam_auxiliary')
local Gank=require(GetScriptDirectory()..'/THDFuncLib/modes/roam/roam_gank')
local GankConfig=require(GetScriptDirectory()..'/THDFuncLib/modes/roam/roam_config')
local Fallback=require(GetScriptDirectory()..'/THDFuncLib/modes/laning/local_lane_fallback')
local E={}
local function State(bot)
	bot.THD_RoamExecution=bot.THD_RoamExecution or {nextPrepare=-90}
	return bot.THD_RoamExecution
end
local function EndProvider(bot,reason)
	local state=State(bot)
	if state.provider=='auxiliary' then Auxiliary.OnEnd()
	elseif state.provider=='gank' then Gank.OnEnd(bot,reason)
	elseif state.provider=='local_fallback' then Fallback.End(bot,state.task,reason) end
	state.provider,state.key,state.task=nil,nil,nil
end
local function Prepare(bot,force,exclude)
	local state,now=State(bot),DotaTime()
	-- 正候选必须仍可提交；失效后不把0.75秒准备缓存当作执行承诺。
	if not force and now<state.nextPrepare and (not state.plan or
		(now<(state.plan.validUntil or -90) and now<(state.plan.deadline or math.huge)
		and Tasks.Valid(bot,state.plan))) then return state.plan,state.score,state.reason,state.nextPrepare end
	state.nextPrepare=now+Config.PLAN_INTERVAL
	if Fallback.NeedsExitPlan(bot) then
		-- 高地内Roam只竞争可执行的退出计划；不能以普通远行或拾取接管后才寻找出口。
		local plan,reason,nextAt=Fallback.Prepare(bot)
		state.plan,state.score,state.reason=plan,Fallback.Desire(plan),reason or (plan and plan.reason) or 'no_safe_exit_plan'
		state.nextPrepare=math.min(state.nextPrepare,plan and plan.validUntil or state.nextPrepare)
		state.nextCandidateAt=nextAt or state.nextPrepare
		if not plan then Tasks.NoteNoCandidate(bot,'roam',state.reason,state.nextCandidateAt) end
		return plan,state.score,state.reason,state.nextCandidateAt
	end
	local score,source=Auxiliary.GetDesire()
	local gankRejection
	local plan=score and score>0 and Auxiliary.PrepareExecutable(score,source) or nil
	if plan and plan.key==exclude then plan=nil end
	if not plan and type(GankConfig.IsEnabled)=='function' and GankConfig.IsEnabled() then
		score=Gank.GetDesire(bot)
		if score and score>0 then plan,gankRejection=Gank.PrepareExecutable(bot) end
		if plan and plan.mission and plan.mission.phase~='engage' then score=Tasks.OpportunityScore(bot,score) end
		if plan and plan.key==exclude then plan=nil end
	end
	local reason,nextAt
	if not plan then
		plan,reason,nextAt=Fallback.Prepare(bot)
		score=Fallback.Desire(plan)
		if not plan and gankRejection then reason='gank:'..gankRejection..'|fallback:'..tostring(reason) end
	end
	state.plan,state.score,state.reason=plan,score or 0,reason or (plan and plan.reason) or 'no_safe_option'
	if plan then state.nextPrepare=math.min(state.nextPrepare,plan.validUntil or now,plan.deadline or math.huge) end
	state.nextCandidateAt=nextAt or state.nextPrepare
	if not plan then Tasks.NoteNoCandidate(bot,'roam',state.reason,state.nextCandidateAt) end
	return plan,state.score,state.reason,state.nextCandidateAt
end
function E.GetDesire(bot)
	if not bot or not bot:IsAlive() then return 0 end
	Tasks.NoteExecutionReady(bot)
	if bot:GetActiveMode()==BOT_MODE_ROAM then Tasks.ObserveExecutionGap(bot,'roam') end
	local confirmation=Auxiliary.PendingConfirmation()
	if Actions.Protected(bot) or (confirmation and DotaTime()<confirmation) then
		return bot:GetActiveMode()==BOT_MODE_ROAM and bot:GetActiveModeDesire() or 0
	end
	local plan,score=Prepare(bot,false)
	return Tasks.OfferExecutable(bot,'roam',score,plan)
end
local function Commit(bot)
	local task,rejection=Tasks.CommitExecutable(bot,'roam')
	if not task then State(bot).reason='commit:'..tostring(rejection);return nil end
	local state=State(bot)
	local changed=state.provider~=task.provider
	if changed then EndProvider(bot,'preempted') end
	if task.provider=='auxiliary' and (changed or state.key~=task.key) then Auxiliary.OnStart(task.auxiliary)
	elseif task.provider=='gank' and changed then
		if not Gank.OnStart(bot) then
			-- 已有有效 mission 不需要重复 Start；首次提交失败不能假装开始执行。
			local existing=Gank.PrepareExecutable(bot)
			if not existing then return nil end
		end
	end
	state.provider,state.key,state.task=task.provider,task.key,task
	-- Think内修订和评分缓存使用同一候选；禁止下一次评分重新发布旧修订。
	state.plan,state.score,state.reason=task,task.score,task.reason
	state.nextPrepare=math.min(state.nextPrepare,task.validUntil or DotaTime(),task.deadline or math.huge)
	return task
end
function E.OnStart(bot) Commit(bot) end
function E.OnEnd(bot)
	local confirmation=Auxiliary.PendingConfirmation()
	if bot:IsAlive() and (Actions.Protected(bot) or (confirmation and DotaTime()<confirmation)) then
		-- 模式结束不等于技能/物品生命周期结束；保留 provider 的终态收集上下文。
		State(bot).detached=true
	else EndProvider(bot,'mode_end') end
	Tasks.ReleaseExecution(bot,'roam','mode_end')
	local state=State(bot);state.plan=nil;state.nextPrepare=-90
end
local function Execute(bot,task)
	if task.provider=='auxiliary' then return Auxiliary.ExecutePlan(task)
	elseif task.provider=='gank' then return Gank.ExecutePlan(bot,task)
	elseif task.provider=='local_fallback' then return Fallback.Execute(bot,task) end
	return {status='INVALID',reason='unknown_provider'}
end
function E.Think(bot)
	Tasks.ObserveExecutionGap(bot,'roam')
	local state=State(bot)
	-- 已提交旅行先收集引导/落点终态，仅允许原旅行生命周期明确支持的动作。
	if state.provider=='gank' and Gank.AdvanceCommittedTravel(bot) then
		Tasks.ReportExecution(bot,'roam',{status='PROTECTED',reason='committed_travel'});return
	end
	if J.CanNotUseAction(bot) then Tasks.ReportExecution(bot,'roam',{status='PROTECTED',reason='protected_or_unavailable'});return end
	local confirmation=Auxiliary.PendingConfirmation()
	if confirmation and DotaTime()<confirmation and state.task then
		local result=Execute(bot,state.task)
		if result.status=='BLOCKED' or result.status=='COMPLETE' then result={status='WAITING',reason='inventory_confirmation',deadline=confirmation} end
		Tasks.ReportExecution(bot,'roam',result);return
	end
	if DotaTime()<Tasks.RetryAt(bot,'roam') then return end
	local task=Commit(bot)
	if not task then
		local plan,score=Prepare(bot,true)
		local offered,rejection=Tasks.OfferExecutable(bot,'roam',score,plan)
		if offered>0 then task=Commit(bot)
		elseif plan then state.reason='admission:'..tostring(rejection) end
	end
	if not task then
		EndProvider(bot,'no_candidate')
		Tasks.ReportExecution(bot,'roam',{status='BLOCKED',reason='NO_SAFE_OPTION:'..tostring(state.reason),retryAt=state.nextCandidateAt or state.nextPrepare})
		return
	end
	local before=Tasks.Capture(bot)
	local result=Execute(bot,task)
	if result.replan and task.provider=='gank' and Tasks.Capture(bot)==before and not Actions.Protected(bot) then
		-- 同使命战术修订只重提候选一次，不调用EndProvider清掉整次Gank。
		local replacement=Gank.PrepareExecutable(bot)
		if replacement and Tasks.OfferExecutable(bot,'roam',task.score,replacement)>0 then
			local nextTask=Commit(bot)
			if nextTask then task=nextTask;result=Execute(bot,nextTask) end
		end
	end
	if result.status=='COMPLETE' and Tasks.Capture(bot)==before and not Actions.Protected(bot) then
		Tasks.ReportExecution(bot,'roam',result)
		EndProvider(bot,'complete')
		local plan,score=Prepare(bot,true,task.key)
		if Tasks.OfferExecutable(bot,'roam',score,plan)>0 then
			local nextTask=Commit(bot)
			if nextTask then task=nextTask;result=Execute(bot,nextTask)
			else result={status='INVALID',reason='handoff_commit_failed'} end
		else result={status='BLOCKED',reason='NO_SAFE_OPTION:'..tostring(state.reason),retryAt=state.nextCandidateAt or state.nextPrepare} end
	end
	if result.status=='BLOCKED' or result.status=='INVALID' then
		result.retryAt=result.retryAt or DotaTime()+Config.PLAN_INTERVAL
		EndProvider(bot,result.reason)
		state.plan=nil;state.nextPrepare=result.retryAt
	end
	local reported=Tasks.ReportExecution(bot,'roam',result)
	if (reported.status=='BLOCKED' or reported.status=='INVALID') and state.provider~=nil then
		EndProvider(bot,reported.reason);state.plan=nil;state.nextPrepare=DotaTime()+Config.PLAN_INTERVAL
	end
end
return E
