-- 战略影子层：消费可见观察与已有候选，不调用GetDesire、不发布游戏命令。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/strategy_phase_config')
local Power=require(GetScriptDirectory()..'/THDFuncLib/combat_power')
local S={}
local teams={}
local function Clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function Visible(u) return u and not u:IsNull() and u:CanBeSeen() and u:IsAlive() and u:IsHero() and not u:IsIllusion() end
local function State(team)
	teams[team]=teams[team] or {own={},enemy={},candidate={},nextOwn=-90,nextEvaluation=-90,logAt=-90}
	return teams[team]
end
local function Observe(map,u,now)
	if not Visible(u) or u:GetPlayerID()<0 then return end
	local id=u:GetPlayerID();local old=map[id]
	if old and now-old.at<Config.SAMPLE_INTERVAL then return end
	map[id]={at=now,worth=u:GetNetWorth(),level=u:GetLevel(),power=Power.Estimate(u)}
end
function S.ObserveStrategy(bot,enemies)
	if not Config.STRATEGY_SHADOW_ENABLED then return end
	local now,team=DotaTime(),bot:GetTeam();local state=State(team)
	if now>=state.nextOwn then
		state.nextOwn=now+Config.SAMPLE_INTERVAL
		for i=1,#GetTeamPlayers(team) do Observe(state.own,GetTeamMember(i),now) end
	end
	for _,enemy in ipairs(enemies or {}) do
		if Visible(enemy) and enemy:GetTeam()~=team then Observe(state.enemy,enemy,now) end
	end
end
-- 各字段独立统计有效样本；API的-1不是经济观测，也不能增加经济置信度。
local function Average(map,count,now)
	local result={worth=0,level=0,power=0,weight=0,observed=0,maxAge=0,fieldConfidence={}}
	local totals={worth=0,level=0,power=0}
	for _,v in pairs(map) do
		local weight=Clamp(1-(now-v.at)/Config.OBSERVATION_AGE,0,1)
		if weight>0 then result.observed=result.observed+1;result.maxAge=math.max(result.maxAge,now-v.at) end
		for _,field in ipairs({'worth','level','power'}) do
			local value=v[field]
			if type(value)=='number' and value==value and value>=0 and value<math.huge then
				result[field]=result[field]+value*weight;totals[field]=totals[field]+weight
			end
		end
		result.weight=result.weight+weight
	end
	result.confidence=math.min(1,result.weight/math.max(1,count))
	for _,field in ipairs({'worth','level','power'}) do
		result.fieldConfidence[field]=math.min(1,totals[field]/math.max(1,count))
		result[field]=totals[field]>0 and result[field]/totals[field] or nil
	end
	return result
end
local function Blend(a,b,t)
	return {lane=a.lane+(b.lane-a.lane)*t,push=a.push+(b.push-a.push)*t,gank=a.gank+(b.gank-a.gank)*t}
end
function S.EvaluatePreferences(snapshot)
	local now=snapshot.now;local half=Config.BLEND_HALF_WINDOW
	local weights,phase
	if now<Config.PHASE_EARLY+half then
		weights=Blend(Config.EARLY,Config.MID,Clamp((now-Config.PHASE_EARLY+half)/(2*half),0,1));phase='early_to_mid'
	else weights=Blend(Config.MID,Config.LATE,Clamp((now-Config.PHASE_LATE+half)/(2*half),0,1));phase='mid_to_late' end
	local a,b=snapshot.own,snapshot.enemy;local confidence=math.min(a.confidence,b.confidence)
	local economicConfidence=math.min(a.fieldConfidence.worth,b.fieldConfidence.worth)
	local levelConfidence=math.min(a.fieldConfidence.level,b.fieldConfidence.level)
	local powerConfidence=math.min(a.fieldConfidence.power,b.fieldConfidence.power)
	local economicReliable=economicConfidence>=Config.MIN_CONFIDENCE and a.worth~=nil and b.worth~=nil and b.worth>0
	local economy=economicReliable and Clamp((a.worth/b.worth-1)/0.25,-1,1)*economicConfidence or 0
	local level=a.level and b.level and Clamp((a.level-b.level)/3,-1,1)*levelConfidence or 0
	local power=a.power and b.power and b.power>0 and Clamp((a.power/b.power-1)/0.5,-1,1)*powerConfidence or 0
	local advantage=0.45*economy+0.20*level+0.35*power
	if advantage>=0 then weights.lane=weights.lane-0.10*advantage;weights.push=weights.push+0.15*advantage;weights.gank=weights.gank-0.05*advantage
	else local amount=-advantage;weights.lane=weights.lane+0.15*amount;weights.push=weights.push-0.10*amount;weights.gank=weights.gank-0.05*amount end
	return {phase=phase,weights=weights,advantage=advantage,confidence=confidence,economyReliable=economicReliable,economicConfidence=economicConfidence,levelConfidence=levelConfidence,powerConfidence=powerConfidence}
end
function S.EvaluateProposal(proposal,context)
	if not proposal or not proposal.score or proposal.score<=0 then return nil end
	local preference=context.weights[proposal.kind] or 1/3
	local phaseTerm=Clamp((preference-1/3)*0.3,-0.10,0.10)
	local travel=math.min(0.15,math.max(0,proposal.eta or 0)/12*0.15)
	local opportunity=Clamp(proposal.opportunityCost or 0,0,0.20)
	local continuation=proposal.progress and 0.05 or 0
	return {value=Clamp(proposal.score+phaseTerm-travel-opportunity+continuation,0,1),phaseTerm=phaseTerm,
		travelCost=travel,opportunityCost=opportunity,continuation=continuation,eligible=proposal.executable==true}
end
function S.NoteCandidate(bot,kind,score,task,source)
	if not Config.STRATEGY_SHADOW_ENABLED then return end
	S.ObserveStrategy(bot,nil)
	local now=DotaTime();local state=State(bot:GetTeam())
	if now>=state.nextEvaluation then
		state.nextEvaluation=now+Config.SAMPLE_INTERVAL
		state.ownSummary=Average(state.own,#GetTeamPlayers(bot:GetTeam()),now)
		state.enemySummary=Average(state.enemy,#GetTeamPlayers(GetOpposingTeam()),now)
		state.preferences=S.EvaluatePreferences({now=now,own=state.ownSummary,enemy=state.enemySummary})
		local tag=state.preferences.advantage>0.2 and 'ahead' or (state.preferences.advantage< -0.2 and 'behind' or 'balanced')
		if state.pendingTag==tag then state.tagCount=state.tagCount+1 else state.pendingTag,state.tagCount=tag,1 end
		if state.tagCount>=2 then state.tag=tag end
	end
	local context=state.preferences
	if not context then return end
	local eta=task and task.location and GetUnitToLocationDistance(bot,task.location)/math.max(100,bot:GetCurrentMovementSpeed()) or 0
	local recent=bot.THD_RecentStrategicProgress
	local progress=recent and recent.kind==kind and now-recent.at<2
	local cost=0
	if kind=='gank' then
		if recent and now-recent.at<2 then cost=recent.kind=='push' and 0.20 or (recent.kind=='lane' and 0.10 or 0) end
	end
	local advice=S.EvaluateProposal({kind=kind,score=score,eta=eta,opportunityCost=cost,progress=progress,
		executable=task and task.executionVersion==2},context)
	local key=tostring(bot:GetPlayerID())..':'..tostring(source or kind)
	state.candidate[key]={kind=kind,at=now,untilAt=task and task.validUntil or now+Config.SAMPLE_INTERVAL,
		score=score,advice=advice,provider=task and task.provider or 'native_delegated'}
	bot.THD_StrategyProposalLog=bot.THD_StrategyProposalLog or {}
	if advice and now-(bot.THD_StrategyProposalLog[kind] or -90)>=Config.LOG_INTERVAL then
		bot.THD_StrategyProposalLog[kind]=now
		print(string.format('[BOT][StrategyProposal] run=%s time=%.2f pid=%s kind=%s source=%s executable=%s base=%.3f value=%.3f phase_term=%.3f travel_cost=%.3f opportunity_cost=%.3f continuity=%.3f hp=%.3f mana=%.3f',
			Config.RUN_ID,now,bot:GetPlayerID(),kind,tostring(source),tostring(advice.eligible),score,advice.value,
			advice.phaseTerm,advice.travelCost,advice.opportunityCost,advice.continuation,
			bot:GetHealth()/math.max(1,bot:GetMaxHealth()),bot:GetMana()/math.max(1,bot:GetMaxMana())))
	end
	if now-state.logAt<Config.LOG_INTERVAL then return end
	state.logAt=now
	local function Value(k)
		local best=nil
		for _,c in pairs(state.candidate) do
			if c.kind==k and now<c.untilAt and c.advice and c.advice.eligible and (not best or c.advice.value>best) then best=c.advice.value end
		end
		return best and string.format('%.3f',best) or 'unknown'
	end
	print(string.format('[BOT][StrategyShadow] run=%s time=%.2f team=%s phase=%s advantage=%.3f confidence=%.3f economy_reliable=%s label=%s lane_weight=%.3f push_weight=%.3f gank_weight=%.3f lane_value=%s push_value=%s gank_value=%s own_observed=%d enemy_observed=%d enemy_max_age=%.1f own_worth=%s enemy_worth=%s economy_confidence=%.3f level_confidence=%.3f power_confidence=%.3f policy_enabled=false',
		Config.RUN_ID,now,bot:GetTeam(),context.phase,context.advantage,context.confidence,tostring(context.economyReliable),state.tag or 'unconfirmed',
		context.weights.lane,context.weights.push,context.weights.gank,Value('lane'),Value('push'),Value('gank'),
		state.ownSummary.observed,state.enemySummary.observed,state.enemySummary.maxAge,
		tostring(state.ownSummary.worth or 'unknown'),tostring(state.enemySummary.worth or 'unknown'),
		context.economicConfidence,context.levelConfidence,context.powerConfidence))
end
function S.NoteGankOutcome(bot,missionID)
	if not Config.STRATEGY_SHADOW_ENABLED then return end
	local old=bot.THD_StrategyGankOutcome
	if old and old.missionID==missionID then return end
	bot.THD_StrategyGankOutcome={missionID=missionID,at=DotaTime()}
end
function S.NoteProgress(bot,kind)
	local now=DotaTime()
	bot.THD_RecentStrategicProgress={kind=kind,at=now}
	local outcome=bot.THD_StrategyGankOutcome
	-- 仅记录击杀观察后的建筑掉血关联，不把时间关联当作击杀或拆塔归因。
	if kind=='push' and outcome and not outcome.reported and now-outcome.at<=30 then
		outcome.reported=true
		print(string.format('[BOT][StrategyOutcome] run=%s time=%.2f pid=%s mission=%s event=building_progress_after_gank elapsed=%.2f attribution=temporal_only',
			Config.RUN_ID,now,bot:GetPlayerID(),tostring(outcome.missionID),now-outcome.at))
	end
end
function S.NoteExecution(bot,task,result)
	if not Config.STRATEGY_SHADOW_ENABLED or not task or (result.status~='ISSUED' and result.status~='CONTINUING') then return end
	if task.provider~='gank' and task.provider~='escort' and task.provider~='assemble' and task.provider~='basic_lane' and task.provider~='lane_work' then return end
	local target=task.target
	if not target or target:IsNull() or not target:CanBeSeen() or not target:IsAlive() or bot:GetAttackTarget()~=target then return end
	local now=DotaTime();local previous=bot.THD_StrategyTargetHealth
	local health=target:GetHealth()
	if previous and previous.target==target and now-previous.at<2 and health<previous.health then
		local kind=task.provider=='gank' and 'gank' or (target:IsHero() and nil or (target:IsBuilding() and 'push' or 'lane'))
		if kind then S.NoteProgress(bot,kind) end
	end
	bot.THD_StrategyTargetHealth={target=target,health=health,at=now}
end
return S
