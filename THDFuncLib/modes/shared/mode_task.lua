-- 候选与活动任务分开保存；退出仅释放任务，绝不清理技能/物品的动作保护。
local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local ExecutionConfig = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local StrategyShadow = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/strategy_phase')
local M = {}
local function State(bot, name)
	bot.THD_ModeTasks = bot.THD_ModeTasks or {}
	bot.THD_ModeTasks[name] = bot.THD_ModeTasks[name] or {}
	return bot.THD_ModeTasks[name]
end
local function Copy(source)
	local result = {}
	for key,value in pairs(source or {}) do
		if key=='snapshot' and type(value)=='table' then
			local snapshot={}
			for name,entry in pairs(value) do
				if type(entry)=='table' then
					local nested={};for k,v in pairs(entry) do nested[k]=v end;snapshot[name]=nested
				else snapshot[name]=entry end
			end
			result[key]=snapshot
		else result[key]=value end
	end
	return result
end
-- 只用实际接近/目标掉血形成短时收益，不把提交命令或进入区域算作进展。
function M.ObserveValue(bot,name,task)
	if not ExecutionConfig.ENABLED or not task then return end
	local state,now=State(bot,name),DotaTime()
	local missionIdentity=tostring(task.objective or task.key or name)
	local identity=missionIdentity
	local target=task.target
	identity=identity..':'..tostring(target)
	local visible=target and Actions.ValidTarget(target)
	local location=visible and target:GetLocation() or task.finalGoal or task.location
	local distance=location and GetUnitToLocationDistance(bot,location)
	local health=visible and bot:GetAttackTarget()==target and target:GetHealth() or nil
	local old=state.valueObservation
	if not old or old.identity~=identity or now-old.at>2 then
		state.valueObservation={identity=identity,missionIdentity=missionIdentity,distance=distance,health=health,at=now};return
	end
	if (distance and old.distance and old.distance-distance>=48) or (health and old.health and health<old.health) then
		old.verifiedAt=now;old.distance=distance
	end
	old.health,old.at=health,now
end
function M.ProgressScore(bot,name,score,silent)
	if not ExecutionConfig.ENABLED then return score end
	local state=State(bot,name);local task=state.active;local observation=state.valueObservation
	local localJourney=task and task.finalGoal and (task.provider=='basic_lane' or task.provider=='local_fallback')
	if not task or score<=0 or (score<0.2 and not localJourney) or score>=ExecutionConfig.PROGRESS_VALUE_CAP or not observation or not observation.verifiedAt
		or observation.missionIdentity~=tostring(task.objective or task.key or name)
		or DotaTime()>=(task.deadline or math.huge)
		or DotaTime()-observation.verifiedAt>ExecutionConfig.PROGRESS_VALUE_SECONDS or not M.Valid(bot,task) then return score end
	if task.executionVersion==2 and not M.IsExecutionActive(bot,name) then return score end
	local mode=({push_1=BOT_MODE_PUSH_TOWER_TOP,push_2=BOT_MODE_PUSH_TOWER_MID,push_3=BOT_MODE_PUSH_TOWER_BOT,
		defend_1=BOT_MODE_DEFEND_TOWER_TOP,defend_2=BOT_MODE_DEFEND_TOWER_MID,defend_3=BOT_MODE_DEFEND_TOWER_BOT,rune=BOT_MODE_RUNE,roam=BOT_MODE_ROAM})[name]
	if bot:GetActiveMode()~=mode then return score end
	local adjusted=math.min(ExecutionConfig.PROGRESS_VALUE_CAP,score+ExecutionConfig.PROGRESS_VALUE_BONUS)
	if not silent and ExecutionConfig.DEBUG and DotaTime()-(state.valueLogAt or -90)>=2 then
		state.valueLogAt=DotaTime()
		print(string.format('[BOT][TaskValue] run=%s time=%.3f pid=%s owner=%s raw=%.3f value=%.3f progress_age=%.3f',
			ExecutionConfig.RUN_ID,DotaTime(),bot:GetPlayerID(),name,score,adjusted,DotaTime()-observation.verifiedAt))
	end
	return adjusted
end
function M.OpportunityScore(bot,score)
	-- 普通远行候选计入放弃现有推进/防守产出的成本；不改Attack/Retreat或紧急任务。
	for _,name in ipairs({'push_1','push_2','push_3','defend_1','defend_2','defend_3'}) do
		if M.ProgressScore(bot,name,0.5,true)>0.5 then return math.max(0,score-ExecutionConfig.LEAVE_PROGRESS_COST) end
	end
	return score
end
function M.NoteAlternative(bot,name,score,candidate)
	if not ExecutionConfig.DEBUG then return end
	local currentName=({[BOT_MODE_PUSH_TOWER_TOP]='push_1',[BOT_MODE_PUSH_TOWER_MID]='push_2',[BOT_MODE_PUSH_TOWER_BOT]='push_3',
		[BOT_MODE_DEFEND_TOWER_TOP]='defend_1',[BOT_MODE_DEFEND_TOWER_MID]='defend_2',[BOT_MODE_DEFEND_TOWER_BOT]='defend_3'})[bot:GetActiveMode()]
	if not currentName or currentName==name or not (string.find(name,'^push_') or string.find(name,'^defend_')) then return end
	local state,now=State(bot,name),DotaTime()
	if now-(state.alternativeLogAt or -90)<2 then return end
	state.alternativeLogAt=now
	local previous=State(bot,currentName);local current=previous.active
	local function Goal(task)
		if not task then return nil end
		if task.target and Actions.ValidTarget(task.target) then return task.target:GetLocation() end
		return task.finalGoal or task.location
	end
	local from,to=Goal(current),Goal(candidate)
	local separation=from and to and math.sqrt((from.x-to.x)^2+(from.y-to.y)^2) or -1
	local observation=previous.valueObservation
	local snapshot=candidate.snapshot or {}
	local function Value(value) return tostring(value):gsub('%s','_') end
	-- 仅记录切换依据，不增加或抑制任何候选分数；避免把真实回防误当抖动。
	print(string.format('[BOT][TaskAlternative] run=%s time=%.3f pid=%s from=%s to=%s current_key=%s candidate_key=%s current_desire=%.3f offered=%.3f raw=%s current_progress_age=%.3f current_action=%s goal_separation=%.1f candidate_distance=%.1f enemy_heroes=%d base_pressure=%s reason=%s',
		ExecutionConfig.RUN_ID,now,bot:GetPlayerID(),currentName,name,Value(current and current.key),Value(candidate.key),
		bot:GetActiveModeDesire(),score,Value(candidate.progressBaseScore or score),
		observation and observation.verifiedAt and now-observation.verifiedAt or -1,Value(bot:GetCurrentActionType()),separation,
		to and GetUnitToLocationDistance(bot,to) or -1,#(snapshot.lEnemyHeroesAroundLoc or {}),Value(snapshot.nEnemyUnitsAroundAncient),Value(candidate.reason)))
end
function M.Active(bot, name) return State(bot,name).active end
function M.Candidate(bot, name) return State(bot,name).candidate end
function M.RetryAt(bot,name) return State(bot,name).retryAt or -90 end
function M.Release(bot, name, reason, retry)
	local state = State(bot,name)
	if state.active and state.active.executionVersion == 2 then state.previousExecution = state.active end
	if bot.THD_ExecutionOwner == name then bot.THD_ExecutionOwner = nil end
	local hadTask=state.active~=nil or state.candidate~=nil
	if hadTask or reason=='mode_end' then state.gapAt,state.gapIdentity=nil,nil end
	state.active, state.candidate = nil, nil
	state.valueObservation=nil
	state.reason = reason
	if retry then state.retryAt = DotaTime()+retry end
	-- 无候选的负结果仍可缓存，不能把每次返回0变成下一帧全量扫描。
	if (hadTask or retry) and bot.THD_ModeDesireCache then bot.THD_ModeDesireCache[name]=nil end
end
function M.Valid(bot, task)
	if task == nil or not bot:IsAlive() then return false end
	if task.target ~= nil and not Actions.ValidTarget(task.target) then return false end
	return true
end
function M.Offer(bot, name, score, task)
	local state = State(bot,name)
	if score == nil or score <= 0 or not M.Valid(bot,task) or DotaTime() < (state.retryAt or -90) then
		state.candidate=nil
		return 0
	end
	local candidate=Copy(task)
	candidate.score, candidate.scoredAt = score, DotaTime()
	candidate.reason = candidate.reason or name
	state.candidate=candidate
	M.NoteAlternative(bot,name,score,candidate)
	return score
end
function M.Start(bot, name)
	local state=State(bot,name)
	local candidate=state.candidate
	if candidate and candidate.executionVersion == 2 then return M.CommitExecutable(bot,name) end
	if not M.Valid(bot,candidate) or DotaTime()-candidate.scoredAt > 2 then
		M.Release(bot,name,'stale_candidate'); return nil
	end
	state.active=Copy(candidate)
	state.active.startedAt, state.active.progressAt = DotaTime(), DotaTime()
	return state.active
end
-- 同模式内的新任务也在执行入口交接；评分不能直接改写正在执行的任务。
function M.Commit(bot, name)
	local state=State(bot,name)
	local candidate,active=state.candidate,state.active
	if (candidate and candidate.executionVersion == 2) or (active and active.executionVersion == 2) then
		return M.CommitExecutable(bot,name)
	end
	-- 引擎可能在零分平局时仍保留当前模式；实际进入Think也可接收新候选。
	if active == nil then return candidate~=nil and M.Start(bot,name) or nil end
	if candidate == nil or candidate.scoredAt <= active.scoredAt then return active end
	if not M.Valid(bot,candidate) then M.Release(bot,name,'candidate_invalid');return nil end
	local same=candidate.target==active.target and candidate.objective==active.objective
		and candidate.key==active.key and candidate.kind==active.kind
	if not same then return M.Start(bot,name) end
	for key,value in pairs(Copy(candidate)) do active[key]=value end
	return active
end
function M.Check(bot, name, safe)
	local state=State(bot,name)
	local task=state.active
	if task and task.executionVersion == 2 then return M.CheckExecutable(bot,name,safe) end
	if not M.Valid(bot,task) or safe == false then
		M.Release(bot,name,safe == false and 'safety_failed' or 'target_invalid'); return nil
	end
	local now=DotaTime()
	-- 施法不算任务停滞；保护记录仍由施法方决定何时到期。
	if Actions.Protected(bot,nil,true) then task.progressAt=now; return task end
	local location=task.target and task.target:GetLocation() or task.location
	if location ~= nil then
		local distance=GetUnitToLocationDistance(bot,location)
		local health=task.target and task.target:GetHealth() or nil
		if task.bestDistance == nil or distance < task.bestDistance-48
		or (health ~= nil and task.health ~= nil and health < task.health) then
			task.bestDistance, task.health, task.progressAt = distance,health,now
		end
		if task.health == nil then task.health=health end
		-- 到达集结/防守区域由本模式判断收益；不能把合法驻守当作卡住。
		if distance <= (task.arrivalRadius or 150) and task.target == nil then task.progressAt=now end
		if now-task.progressAt >= (task.stallSeconds or 6) then
			M.Release(bot,name,'no_progress',1.5); return nil
		end
	end
	return task
end
local function Token(value) return tostring(value):gsub('%s','_') end
local function ExecutionLog(bot,name,result,task)
	if not ExecutionConfig.DEBUG then return end
	local state,now = State(bot,name),DotaTime()
	local signature = tostring(task and task.key)..':'..tostring(result.status)..':'..tostring(result.reason)
	-- 三类输出各自限流，避免NO_SAFE_OPTION/GAP交替绕过同一signature的限流。
	local channel=result.status=='NO_SAFE_OPTION' and 'preparation'
		or ((result.status=='GAP' or result.status=='UNMATCHED_ACTION') and 'observation' or 'execution')
	state.executionLogs=state.executionLogs or {}
	local log=state.executionLogs[channel] or {at=-90,suppressed=0}
	state.executionLogs[channel]=log
	if now-log.at<ExecutionConfig.LOG_INTERVAL and (channel~='execution' or log.signature==signature) then
		log.suppressed=log.suppressed+1;return
	end
	local suppressed=log.suppressed
	log.at,log.signature,log.suppressed=now,signature,0
	local rejected=state.executionRejection
	if rejected and now-rejected.at>ExecutionConfig.LOG_INTERVAL then rejected=nil end
	local position=bot:GetLocation()
	local detail=rejected and rejected.detail
	local executionReason='not_committed'
	if task and task==state.active and M.IsExecutionActive then local _,why=M.IsExecutionActive(bot,name);executionReason=why end
	print(string.format('[BOT][Execution] run=%s time=%.3f pid=%s mode=%s desire=%.3f owner=%s provider=%s key=%s generation=%s status=%s reason=%s action=%s target=%s x=%s y=%s age=%s deadline=%s progress_at=%s retry_at=%s from_provider=%s to_provider=%s bot_x=%.1f bot_y=%.1f rejected_x=%s rejected_y=%s rejected_stage=%s rejected_reason=%s suppressed=%d task_reason=%s sample_index=%s sample_count=%s sample_x=%s sample_y=%s origin_passable=%s',
		ExecutionConfig.RUN_ID,now,bot:GetPlayerID(),bot:GetActiveMode(),bot:GetActiveModeDesire(),name,
		Token(task and task.provider),Token(task and task.key),Token(task and task.generation),result.status,Token(result.reason),
		bot:GetCurrentActionType(),Token(task and task.target),Token(task and task.location and task.location.x),
		Token(task and task.location and task.location.y),Token(task and now-task.preparedAt),
		Token(task and task.deadline),Token(task and task.progressAt),Token(result.retryAt or state.retryAt),Token(state.handoffFrom),Token(task and task.provider),
		position.x,position.y,Token(rejected and rejected.location and rejected.location.x),Token(rejected and rejected.location and rejected.location.y),
		Token(rejected and rejected.stage),Token(rejected and rejected.reason),suppressed,Token(task and task.reason),
		Token(detail and detail.index),Token(detail and detail.count),Token(detail and detail.point and detail.point.x),
		Token(detail and detail.point and detail.point.y),Token(detail and detail.originPassable))
		..string.format(' previous_deadline=%s candidate_deadline=%s candidate_until=%s candidate_expired=%s committed_at=%s remaining_distance=%s execution_check=%s',
			Token(result.previousDeadline),Token(result.candidateDeadline),Token(task and task.validUntil),
			Token(task and now>=(task.validUntil or -90)),Token(task and task.committedAt),
			Token(task and task.location and GetUnitToLocationDistance(bot,task.location)),Token(executionReason)))
end

function M.NoteRejection(bot,name,reason,point,stage,detail)
	if not ExecutionConfig.DEBUG then return end
	State(bot,name).executionRejection={at=DotaTime(),reason=reason,stage=stage,detail=detail,
		location=point and Vector(point.x,point.y,point.z) or nil}
end

function M.NoteExecutionReady(bot)
	if not ExecutionConfig.DEBUG or bot.THD_ExecutionReady then return end
	bot.THD_ExecutionReady=true
	print(string.format('[BOT][Execution] run=%s event=ready pid=%s enabled=%s push=%s roam=%s fallback=%s',
		ExecutionConfig.RUN_ID,bot:GetPlayerID(),tostring(ExecutionConfig.ENABLED),tostring(ExecutionConfig.PushEnabled()),
		tostring(ExecutionConfig.RoamEnabled()),tostring(ExecutionConfig.FallbackEnabled())))
end

function M.NoteNoCandidate(bot,name,reason,nextAt)
	-- 只输出准备失败的证据，不在评分期间释放/改写活动任务。
	ExecutionLog(bot,name,{status='NO_SAFE_OPTION',reason=reason,retryAt=nextAt},nil)
end

function M.ReleaseExecution(bot,name,reason,retryAt)
	local state=State(bot,name)
	M.Release(bot,name,reason)
	state.retryAt=retryAt or DotaTime()
	-- 准备缓存与执行承诺一起失效，下一次评分不能复用被拒绝的计划。
	if bot.THD_PushExecutionPlans and string.find(name,'^push_') then bot.THD_PushExecutionPlans={} end
	if bot.THD_ModeDesireCache then bot.THD_ModeDesireCache[name]=nil end
end

local function ExecutableValid(bot,task)
	if not M.Valid(bot,task) or task.executionVersion~=2 or task.key==nil or task.intent==nil then return false end
	local now=DotaTime()
	return now < (task.validUntil or -90) and now < (task.deadline or math.huge)
end

-- validUntil仅限制候选提交；已提交任务按归属、期限、进展与实际动作判断。
function M.IsExecutionActive(bot,name)
	local state=bot.THD_ModeTasks and bot.THD_ModeTasks[name]
	local task=state and state.active
	if not M.Valid(bot,task) or task.executionVersion~=2 or bot.THD_ExecutionOwner~=name then return false,'execution_not_owned' end
	local now=DotaTime()
	if now>=(task.deadline or math.huge) then return false,'execution_deadline' end
	if now<(state.retryAt or -90) then return false,'retry_pending' end
	if not task.score or task.score<=0 then return false,'execution_no_score' end
	if Actions.Protected(bot) then return true,'execution_protected' end
	if task.intent=='wait' then return task.deadline~=nil,task.deadline and 'bounded_wait' or 'execution_unbounded_wait' end
	if task.intent=='move' and task.location and GetUnitToLocationDistance(bot,task.location)<=(task.tolerance or 120) then
		-- 到位只给执行入口一次收尾窗口，不能永久阻挡其他模式接替。
		task.arrivedAt=task.arrivedAt or now
		return now-task.arrivedAt<0.5,'execution_arrived'
	end
	task.arrivedAt=nil
	if not task.externalProgress and now-(task.progressAt or task.startedAt or now)>=(task.stallSeconds or 6) then
		return false,'execution_no_progress'
	end
	if M.MatchingAction(bot,task) then return true,'execution_matching_action' end
	if now-(task.committedAt or task.startedAt or -90)<0.5 then return true,'execution_starting' end
	return false,'execution_action_missing'
end

-- 准入检查供选路、报价、提交共用；不调用其他模式评分，不占执行权或发布动作。
function M.CanOfferExecutable(bot,name,score,task)
	local now=DotaTime()
	local state=bot.THD_ModeTasks and bot.THD_ModeTasks[name]
	if not score or score<=0 then return false,'no_positive_score' end
	if not ExecutableValid(bot,task) then return false,'candidate_invalid_or_expired' end
	if state and now<(state.retryAt or -90) then return false,'retry_pending',state.retryAt end
	if Actions.Protected(bot) then return false,'protected_lifecycle' end
	local previous=state and (state.active or state.previousExecution)
	if previous and previous.key==task.key and now>=(previous.deadline or math.huge) then
		return false,'inherited_deadline_expired'
	end
	return true,'admissible'
end
local function AdmissionLog(bot,name,score,task,accepted,reason)
	if not ExecutionConfig.DEBUG then return end
	local state,now=State(bot,name),DotaTime()
	-- 常规零分不是执行失败，不再每两秒重复输出；仍保留正分报价/拒绝链。
	if reason=='no_positive_score' then return end
	if now-(state.admissionLogAt or -90)<ExecutionConfig.LOG_INTERVAL then return end
	state.admissionLogAt=now
	print(string.format('[BOT][ExecutionAdmission] run=%s time=%.3f pid=%s owner=%s key=%s provider=%s requested_score=%s offered_score=%s reason=%s retry_at=%s valid_until=%s deadline=%s',
		ExecutionConfig.RUN_ID,now,bot:GetPlayerID(),name,Token(task and task.key),Token(task and task.provider),Token(score),
		Token(accepted),Token(reason),Token(state.retryAt),Token(task and task.validUntil),Token(task and task.deadline)))
end
function M.OfferExecutable(bot,name,score,task)
	if task~=nil then task=Copy(task);task.executionVersion=2;task.owner=name end
	local activeValueTask=State(bot,name).active
	if task and activeValueTask and score==activeValueTask.score and activeValueTask.progressBaseScore then score=activeValueTask.progressBaseScore end
	if task then task.progressBaseScore=score end
	if task and (string.find(name,'^push_') or (name=='roam' and task.provider=='local_fallback' and task.finalGoal)) and State(bot,name).active
	and tostring(task.objective or task.key)==tostring(State(bot,name).active.objective or State(bot,name).active.key) then
		score=M.ProgressScore(bot,name,score or 0)
	end
	if task and score and score>0 and string.find(name,'^push_') then
		for _,other in ipairs({'push_1','push_2','push_3'}) do
			if other~=name and M.ProgressScore(bot,other,0.5,true)>0.5 then
				-- 换路需要支付放弃已有有效路程的成本，不阻挡危险退出或失效重选。
				score=math.max(0,score-ExecutionConfig.CROSS_LANE_PROGRESS_COST);break
			end
		end
	end
	local allowed,reason=M.CanOfferExecutable(bot,name,score,task)
	local kind=task and (task.provider=='gank' and 'gank'
		or ((task.provider=='basic_lane' or task.progressPolicy=='clear_wave' or task.reason=='local_clear' or task.reason=='blocker') and 'lane')
		or (string.find(name,'^push_') and 'push'))
	if kind then StrategyShadow.NoteCandidate(bot,kind,allowed and score or 0,task,name) end
	if not allowed then
		State(bot,name).candidate=nil
		AdmissionLog(bot,name,score,task,0,reason)
		return 0,reason
	end
	local offered=M.Offer(bot,name,score,task)
	AdmissionLog(bot,name,score,task,offered,offered>0 and 'offered' or 'offer_rejected')
	return offered
end

function M.CommitExecutable(bot,name)
	local state,now=State(bot,name),DotaTime()
	local candidate=state.candidate
	if not ExecutableValid(bot,candidate) then
		local active,why=M.IsExecutionActive(bot,name)
		if active then return state.active end
		local reason=state.active and why or 'no_valid_candidate'
		if state.active or candidate then M.ReleaseExecution(bot,name,reason,math.max(now,state.retryAt or now)) end
		return nil,reason
	end
	local admissible,admissionReason=M.CanOfferExecutable(bot,name,candidate.score,candidate)
	if not admissible then
		if admissionReason~='retry_pending' and admissionReason~='protected_lifecycle' then
			M.ReleaseExecution(bot,name,admissionReason)
		end
		return nil,admissionReason
	end
	local active=state.active
	if active and active.provider=='gank' and candidate.provider=='gank' and active.mission==candidate.mission
	and active.tacticalRevision and (not candidate.tacticalRevision or candidate.tacticalRevision<active.tacticalRevision) then
		-- 同使命修订只能前进；新鲜时间戳也不能把旧评分缓存变成新战术。
		state.candidate=nil
		if M.IsExecutionActive(bot,name) then return active end
		return nil,'stale_tactical_revision'
	end
	if M.IsExecutionActive(bot,name) and candidate.key==active.key
	and candidate.intent==active.intent and candidate.target==active.target
	and candidate.tacticalRevision==active.tacticalRevision and candidate.scoredAt<=active.scoredAt then return active end
	local previous=state.active or state.previousExecution
	if previous and previous.key==candidate.key and previous.generation then
		candidate.generation=previous.generation
	else state.executionGeneration=(state.executionGeneration or 0)+1;candidate.generation=state.executionGeneration end
	local nextTask=Copy(candidate)
	if not previous or previous.provider~=candidate.provider then state.handoffFrom=previous and previous.provider or 'none' end
	if previous and previous.key==candidate.key then
		for _,field in ipairs({'startedAt','progressAt','bestDistance','health','actionIntent','observedAt','arrivedAt'}) do nextTask[field]=previous[field] end
		if previous.deadline then nextTask.deadline=math.min(previous.deadline,nextTask.deadline or math.huge) end
		if previous.intent~=candidate.intent or previous.target~=candidate.target then nextTask.actionIntent=nil end
		if previous.location and candidate.location then
			local dx,dy=previous.location.x-candidate.location.x,previous.location.y-candidate.location.y
			if dx*dx+dy*dy>(candidate.tolerance or 120)^2 then nextTask.actionIntent=nil;nextTask.arrivedAt=nil end
		end
	else nextTask.startedAt,nextTask.progressAt=now,now end
	if now >= (nextTask.deadline or math.huge) then
		-- 同周期不能复活过期任务；立刻释放承诺和缓存，新周期必须使用新身份。
		ExecutionLog(bot,name,{status='INVALID',reason='commit_inherited_deadline',
			previousDeadline=previous and previous.deadline,candidateDeadline=candidate.deadline},nextTask)
		M.ReleaseExecution(bot,name,'commit_inherited_deadline',now+0.75)
		return nil,'commit_inherited_deadline'
	end
	local priorOwner=bot.THD_ExecutionOwner
	if priorOwner and priorOwner~=name then
		-- 这里只交接任务引用，不回调其他模式、不清其动作和技能保护。
		M.Release(bot,priorOwner,'execution_handoff')
	end
	nextTask.committedAt=now
	state.active=nextTask;bot.THD_ExecutionOwner=name
	return nextTask
end

function M.CheckExecutable(bot,name,safe)
	local task=State(bot,name).active
	if Actions.Protected(bot,nil,true) then return task end
	if safe==false or not M.IsExecutionActive(bot,name) then return nil end
	if task.validate then
		local valid=task.validate(bot,task)
		if not valid then return nil end
	end
	return task
end

function M.MatchingAction(bot,task)
	if task==nil then return false end
	local kind=bot:GetCurrentActionType()
	if kind==BOT_ACTION_TYPE_ATTACK then return Actions.ValidTarget(task.target) and bot:GetAttackTarget()==task.target end
	local intent=bot.THD_ActionIntent
	if kind~=BOT_ACTION_TYPE_MOVE_TO or intent==nil or intent.mode~=bot:GetActiveMode() then return false end
	if intent==task.actionIntent then return true end
	if task.location and intent.location then
		local dx,dy=task.location.x-intent.location.x,task.location.y-intent.location.y
		return dx*dx+dy*dy<=(task.tolerance or 120)^2
	end
	return false
end

function M.Capture(bot) return bot.THD_ActionSequence or 0 end
function M.ResultAfter(bot,task,before,waitUntil,reason)
	if (bot.THD_ActionSequence or 0)>before then return {status='ISSUED',reason=reason or 'submitted'} end
	if Actions.Protected(bot) then return {status='PROTECTED',reason='protected_lifecycle'} end
	if M.MatchingAction(bot,task) then return {status='CONTINUING',reason='matching_action'} end
	if waitUntil and DotaTime()<waitUntil then return {status='WAITING',reason=reason or 'bounded_wait',deadline=waitUntil} end
	return {status='BLOCKED',reason=reason or 'no_executable_action'}
end

function M.ReportExecution(bot,name,result)
	local state,now=State(bot,name),DotaTime()
	local task=state.active or state.candidate
	result=result or {status='INVALID',reason='missing_execution_result'}
	StrategyShadow.NoteExecution(bot,task,result)
	if result.status=='WAITING' and (not result.deadline or now>=result.deadline) then
		result={status='BLOCKED',reason='wait_deadline'}
	end
	if task then
		if result.status=='ISSUED' or result.status=='CONTINUING' then M.ObserveValue(bot,name,task) end
		if result.status=='ISSUED' then task.actionIntent=bot.THD_ActionIntent end
		local dt=math.min(1,math.max(0,now-(task.observedAt or now)))
		task.observedAt=now
		if result.status=='PROTECTED' then task.progressAt=(task.progressAt or now)+dt
		elseif not task.externalProgress and result.status~='COMPLETE' and result.status~='INVALID' and result.status~='BLOCKED' then
			local location=task.target and Actions.ValidTarget(task.target) and task.target:GetLocation() or task.location
			local distance=location and GetUnitToLocationDistance(bot,location) or nil
			local health=task.target and Actions.ValidTarget(task.target) and task.target:GetHealth() or nil
			if (distance and (task.bestDistance==nil or task.bestDistance-distance>=48))
			or (health and task.health and health<task.health) then task.progressAt=now;task.bestDistance=distance end
			task.health=health
			if now-(task.progressAt or now)>=(task.stallSeconds or 6) then result={status='BLOCKED',reason='no_progress'} end
		end
	end
	state.lastExecution=result;state.lastExecutionAt=now
	ExecutionLog(bot,name,result,task)
	if result.status=='BLOCKED' or result.status=='INVALID' or result.status=='COMPLETE' then
		M.ReleaseExecution(bot,name,result.reason,result.retryAt)
	end
	return result
end

function M.ObserveExecutionGap(bot,name)
	if not ExecutionConfig.DEBUG or not bot:IsAlive() then return end
	local state,now=State(bot,name),DotaTime()
	local task=state.active
	local identity=tostring(bot:GetActiveMode())..':'..tostring(task and task.key)..':'..tostring(task and task.generation)
	if state.gapIdentity~=identity then state.gapAt=nil;state.gapIdentity=identity end
	local last=state.lastExecution
	local waiting=last and last.status=='WAITING' and now<(last.deadline or -90)
	if last and string.find(last.reason or '','NO_SAFE_OPTION',1,true) and now<(state.retryAt or -90) then waiting=true end
	local protected=Actions.Protected(bot) or bot:IsStunned() or bot:IsNightmared()
		or (bot:IsRooted() and task and task.intent=='move')
		or (last and last.status=='PROTECTED' and now-(state.lastExecutionAt or -90)<0.5)
	if protected or M.MatchingAction(bot,task) or waiting then state.gapAt=nil;return end
	local action=bot:GetCurrentActionType()
	if action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE then
		state.gapAt=nil
		ExecutionLog(bot,name,{status='UNMATCHED_ACTION',reason='action_without_matching_contract'},task)
		return
	end
	state.gapAt=state.gapAt or now
	if now-state.gapAt>=ExecutionConfig.GAP_SECONDS then
		ExecutionLog(bot,name,{status='GAP',reason=state.reason or (last and last.reason) or 'no_task_or_action'},task)
	end
end

function M.HasOtherExecution(bot,name)
	for other,state in pairs(bot.THD_ModeTasks or {}) do
		if other~=name and state.active~=nil then
			local task=state.active
			if (task.executionVersion~=2 and M.Valid(bot,task) and DotaTime()-(task.scoredAt or -90)<2)
			or (task.executionVersion==2 and M.IsExecutionActive(bot,other)
				and (task.mode or ({roam=BOT_MODE_ROAM,push_1=BOT_MODE_PUSH_TOWER_TOP,push_2=BOT_MODE_PUSH_TOWER_MID,push_3=BOT_MODE_PUSH_TOWER_BOT})[other])==bot:GetActiveMode()) then return true end
		end
	end
	return false
end
return M
