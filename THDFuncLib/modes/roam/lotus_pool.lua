-- 原生莲花池按范围自动领取。只规划可见且有库存的局部目标，沿用ROAM执行契约。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Resources=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/map_resources')
local Items=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/map_resource_items')
local Tasks=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_task')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Consumables=require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')
local Towers=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/tower_safety')
local Geometry=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Routes=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/local_route_candidates')
local Strategy=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/wasteland_strategy')
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local L={}
local states=setmetatable({}, {__mode='k'})
local function State(bot)
	states[bot]=states[bot] or {nextSearch=-90,serial=0}
	return states[bot]
end
function L.Note(bot,reason,task,score)
	if not Config.DEBUG then return end
	local state,now=State(bot),DotaTime()
	if now-(state.decisionAt or -90)<2 then return end
	state.decisionAt=now
	print(string.format('[BOT][LotusDecision] run=%s time=%.3f pid=%s reason=%s key=%s score=%s claims=%s deadline=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),tostring(reason),tostring(task and task.key),tostring(score),tostring(task and task.claims),tostring(task and task.deadline)))
end
local function Reject(bot,reason)
	L.Note(bot,reason);return nil,reason
end
local function Value(bot,observation,distance)
	local need=J.GetHP(bot)<0.8 or bot:GetMana()/math.max(1,bot:GetMaxMana())<0.6
	local stock=Items.Count(bot)
	return math.max(0.2,math.min(0.65,Config.LOTUS_DESIRE+0.2*(1-distance/Config.LOTUS_MAX_DISTANCE)
		+math.min(3,math.max(0,observation.count-1))*0.03+(need and 0.08 or 0)-(stock>=3 and 0.15 or 0)))
end
function L.Score(bot,task)
	local observation=Resources.Get(bot,'lotus',task.resourceIndex)
	if not observation or observation.state~='ready' then return Config.FALLBACK_DESIRE end
	local distance=GetUnitToLocationDistance(bot,observation.location)
	-- 只给已执行且仍安全的圈内等待短时收尾优先级，不靠权重强抢远处资源。
	if task.claimAt and distance<=observation.radius and DotaTime()<task.deadline then return Config.LOTUS_CLAIM_DESIRE end
	local score=Value(bot,observation,distance)
	if task.committedAt and distance<=600 and task.progressAt and DotaTime()-task.progressAt<2 then
		score=math.max(score,Config.LOTUS_NEAR_DESIRE)
	end
	return score
end
local function Eligible(bot)
	if not Config.MAP_RESOURCES_ENABLED or not Config.RoamEnabled() or not bot:IsAlive() then return false,'disabled_or_dead' end
	if Actions.Protected(bot) or J.CanNotUseAction(bot) or Consumables.GetState(bot) then return false,'protected_or_inventory' end
	if J.Retreat.ShouldYield(bot,J.Retreat.HIGH) or J.IsRoshanCommitmentActive(bot) or bot:WasRecentlyDamagedByAnyHero(2) then return false,'danger_or_commitment' end
	if #(J.GetNearbyHeroes(bot,1200,true,BOT_MODE_NONE) or {})>0 then return false,'nearby_enemy' end
	local base=Strategy.GetBaseThreatSnapshot(nil,bot)
	if base and base.hardEmergency then return false,'base_emergency' end
	if not Items.CanCollect(bot) then return false,'inventory_full' end
	return true
end
local function PathSafe(bot,point,origin,towers)
	origin=origin or bot:GetLocation()
	towers=towers or Towers.Observe(bot,'lotus_pool')
	if not towers.available then return false,'tower_snapshot_unavailable' end
	local safe,reason=Geometry.ValidateMovementSegment(origin,point,towers.towers,96)
	if not safe then return false,'tower_'..tostring(reason) end
	safe,reason=Geometry.ValidateLocalTerrainSegment(origin,point,true)
	return safe,reason
end
local function ClaimPoint(bot,observation)
	local origin,center=bot:GetLocation(),observation.location
	if Geometry.Distance(origin,center)<=math.max(64,observation.radius-96) then return origin end
	local delta=origin-center;local length=math.max(1,delta:Length2D())
	local best,distance
	-- 建筑中心不作为移动终点；在真实领取圈内留出移动容差，选择可见可走的落点。
	for _,radius in ipairs({math.max(64,observation.radius-96),math.max(64,observation.radius-160)}) do
		for _,degrees in ipairs({0,30,-30,60,-60,90,-90,120,-120,150,-150,180}) do
			local angle=math.rad(degrees)
			local point=Vector(center.x+(delta.x*math.cos(angle)-delta.y*math.sin(angle))/length*radius,
				center.y+(delta.x*math.sin(angle)+delta.y*math.cos(angle))/length*radius,center.z)
			local d=Geometry.Distance(origin,point)
			if (not distance or d<distance) and IsLocationVisible(point) and IsLocationPassable(point) then best,distance=point,d end
		end
	end
	return best
end
local function ForwardPoint(origin,point,history)
	for _,previous in ipairs(history or {}) do
		if Geometry.Distance(previous,point)<=96 then return false end
	end
	local previous=history and history[#history]
	if previous then
		local incoming,outgoing=origin-previous,point-origin
		local length=incoming:Length2D()*outgoing:Length2D()
		-- 拒绝向上一段后方折返；允许沿障碍侧面继续绕行。
		if length>1 and (incoming.x*outgoing.x+incoming.y*outgoing.y)/length < -0.25 then return false end
	end
	return true
end
local function Step(bot,goal,history)
	local origin=bot:GetLocation();local candidates={}
	if Geometry.Distance(origin,goal)<=600 then candidates[#candidates+1]={location=goal} end
	for _,entry in ipairs(Routes.Journey(origin,goal,true)) do candidates[#candidates+1]=entry end
	local checks,rejects=0,{}
	local towers=Towers.Observe(bot,'lotus_pool')
	local function Check(from,to)
		if checks>=48 then return false,'route_check_budget' end
		checks=checks+1
		return PathSafe(bot,to,from,towers)
	end
	for _,entry in ipairs(candidates) do
		if checks>=48 then break end
		local point=entry.location
		if Geometry.Distance(origin,point)<=600 and ForwardPoint(origin,point,history)
			and Geometry.Distance(point,goal)<=Geometry.Distance(origin,goal)+64 then
			local safe,reason=Check(origin,point)
			if safe and entry.connector then
				-- 侧向点必须还有一段安全且净接近目标的出口，避免走入只能原路返回的死角。
				safe=false;reason='connector_no_forward_exit'
				local nextHistory={};for _,p in ipairs(history or {}) do nextHistory[#nextHistory+1]=p end
				nextHistory[#nextHistory+1]=origin
				local exits=Routes.Journey(point,goal,false)
				if Geometry.Distance(point,goal)<=600 then table.insert(exits,1,{location=goal}) end
				for index,exit in ipairs(exits) do
					if index>6 or checks>=48 then break end
					if Geometry.Distance(point,exit.location)<=600 and ForwardPoint(point,exit.location,nextHistory)
						and Geometry.Distance(exit.location,goal)<Geometry.Distance(origin,goal)-24
						and Check(point,exit.location) then safe=true;break end
				end
			end
			if safe then return point,nil,checks end
			rejects[reason or 'unknown']=true
		else rejects.return_or_nonprogress=true
		end
	end
	local reasons={};for reason in pairs(rejects) do reasons[#reasons+1]=reason end;table.sort(reasons)
	return nil,#reasons>0 and table.concat(reasons,'|') or 'no_local_candidate',checks
end
local function CanReobserve(observation)
	-- 只允许既有任务短暂接近以重获视野；旧数量不作领取/成功依据，也不延长总期限。
	return observation.state=='unknown' and observation.observedAt
		and DotaTime()-observation.observedAt<=Config.MAP_RESOURCE_OBSERVATION_TTL+2.5
end
function L.Prepare(bot)
	local state,now=State(bot),DotaTime()
	local eligible,reason=Eligible(bot)
	if not eligible then return Reject(bot,reason) end
	if Tasks.HasOtherExecution(bot,'roam') then return Reject(bot,'other_execution') end
	if state.task and now>=state.task.deadline then
		Resources.Defer(bot,'lotus',state.task.resourceIndex,'task_deadline',5)
		state.task=nil;state.nextSearch=now+1;return nil,'lotus_task_deadline'
	end
	if state.task and now<state.task.deadline then
		local observation=Resources.Get(bot,'lotus',state.task.resourceIndex)
		if observation and observation.identity==state.task.resourceIdentity and (observation.state=='ready' or CanReobserve(observation)) then
			local plan={};for k,v in pairs(state.task) do plan[k]=v end
			if not state.task.committedAt and observation.state=='ready' then plan.initialCount=observation.count;plan.inventoryBefore=Items.Count(bot) end
			plan.preparedAt,plan.validUntil=now,math.min(now+Config.CANDIDATE_TTL,plan.deadline)
			return plan
		end
	end
	if now<state.nextSearch then return nil,'lotus_search_throttled' end
	state.nextSearch=now+1
	local best,distance,bestValue
	for index=1,2 do
		local observation=Resources.Get(bot,'lotus',index)
		if observation and observation.state=='ready' and Resources.CanTry(bot,'lotus',index) then
			local d=GetUnitToLocationDistance(bot,observation.location)
			local value=d<=Config.LOTUS_MAX_DISTANCE and Value(bot,observation,d) or nil
			if value and (not bestValue or value>bestValue) then best,distance,bestValue=observation,d,value end
		end
	end
	if not best then return Reject(bot,'no_ready_pool_in_range') end
	local goal=ClaimPoint(bot,best)
	if not goal then Resources.Log(bot,best,'blocked','no_visible_claim_point');return nil,'no_visible_claim_point' end
	local point,why,checks=Step(bot,goal)
	if not point then Resources.Log(bot,best,'blocked',why);return nil,why end
	state.serial=state.serial+1
	local task={executionVersion=2,key='lotus:'..best.slot..':'..state.serial,provider='lotus_pool',intent='move',
		location=point,finalGoal=goal,resourceIndex=best.index,resourceIdentity=best.identity,
		stepOrigin=bot:GetLocation(),routeHistory={},
		initialCount=best.count,inventoryBefore=Items.Count(bot),reason='lotus_approach',progressPolicy='movement',
		preparedAt=now,validUntil=now+Config.CANDIDATE_TTL,deadline=now+Config.LOTUS_TASK_SECONDS,stallSeconds=3,tolerance=48,mode=BOT_MODE_ROAM}
	state.task=task
	if Config.DEBUG then print(string.format('[BOT][LotusRoute] run=%s time=%.3f pid=%s event=prepared slot=%d checks=%d claim_x=%.1f claim_y=%.1f claim_distance=%.1f deadline=%.3f',
		Config.RUN_ID,now,bot:GetPlayerID(),best.slot,checks,goal.x,goal.y,Geometry.Distance(goal,best.location),task.deadline)) end
	return task
end
function L.Execute(bot,task)
	State(bot).task=task
	if Actions.Protected(bot) then return {status='PROTECTED',reason='protected_lifecycle'} end
	local observation=Resources.Get(bot,'lotus',task.resourceIndex)
	if not observation or observation.identity~=task.resourceIdentity then return {status='INVALID',reason='lotus_observation_missing'} end
	if observation.state~='unknown' and observation.count<task.initialCount then
		local acquired=Items.Count(bot)>task.inventoryBefore
		Resources.Log(bot,observation,'consumed',acquired and 'inventory_increased' or 'pool_count_decreased')
		if acquired then task.claims=(task.claims or 0)+1 end
		-- 自身取得后最多再取一次；沿用原收尾期限，不能在池边无限续租。
		if acquired and task.claims<Config.LOTUS_MAX_CLAIMS and observation.state=='ready' and observation.count>0
			and DotaTime()+observation.countdown<task.deadline
			and GetUnitToLocationDistance(bot,observation.location)<=observation.radius and Eligible(bot) then
			task.initialCount,task.inventoryBefore=observation.count,Items.Count(bot)
			task.claimAt=DotaTime();task.intent='wait';task.reason='lotus_claiming'
			L.Note(bot,'next_claim_same_deadline',task,Config.LOTUS_CLAIM_DESIRE)
			return {status='WAITING',reason='lotus_claiming',deadline=task.deadline}
		end
		return {status='COMPLETE',reason=acquired and 'lotus_inventory_increased' or 'lotus_pool_consumed'}
	end
	local eligible,reason=Eligible(bot)
	if not eligible then return {status='INVALID',reason=reason} end
	if observation.state~='ready' and not CanReobserve(observation) then return {status='INVALID',reason='lotus_state_'..observation.state} end
	local distance=GetUnitToLocationDistance(bot,observation.location)
	if task.claimAt and distance>observation.radius then return {status='INVALID',reason='lotus_claim_area_left'} end
	if distance<=math.max(64,observation.radius-48) then
		if observation.state=='unknown' then
			Resources.Log(bot,observation,'reobserve','await_fresh_native_state')
			return {status='WAITING',reason='lotus_reobserve',deadline=task.deadline}
		end
		if not task.claimAt then
			task.claimAt=DotaTime();task.deadline=math.min(task.deadline,task.claimAt+observation.countdown+2)
			task.intent='wait';task.reason='lotus_claiming'
		end
		Resources.Log(bot,observation,'claiming','await_native_count_change')
		return {status='WAITING',reason='lotus_claiming',deadline=task.deadline}
	end
	local point,why=task.location,nil
	if not point or GetUnitToLocationDistance(bot,point)<=48 or not PathSafe(bot,point) then
		-- 首段起点也纳入历史；候选复制与再次接管不能丢失防折返信息。
		local history={};for _,p in ipairs(task.routeHistory or {}) do history[#history+1]=p end
		if task.stepOrigin and Geometry.Distance(bot:GetLocation(),task.stepOrigin)>48 then
			history[#history+1]=task.stepOrigin
		end
		while #history>8 do table.remove(history,1) end
		local checks
		point,why,checks=Step(bot,task.finalGoal,history)
		if Config.DEBUG then print(string.format('[BOT][LotusRoute] run=%s time=%.3f pid=%s event=advance key=%s checks=%d selected=%s reason=%s history=%d bot_x=%.1f bot_y=%.1f next_x=%s next_y=%s deadline=%.3f',
			Config.RUN_ID,DotaTime(),bot:GetPlayerID(),task.key,checks,tostring(point~=nil),tostring(why),#history,
			bot:GetLocation().x,bot:GetLocation().y,tostring(point and point.x),tostring(point and point.y),task.deadline)) end
		if point then
			task.routeHistory,task.stepOrigin=history,bot:GetLocation()
			task.bestDistance,task.arrivedAt=nil,nil
		end
	end
	if not point then return {status='BLOCKED',reason='lotus_path_'..tostring(why)} end
	task.location=point
	local before=Tasks.Capture(bot)
	J.ActionMoveToLocation(bot,'lotus_pool_approach',point,0.4,48,function(p) return PathSafe(bot,p) end)
	Resources.Log(bot,observation,'approach',observation.state=='ready' and 'native_pool_ready' or 'reacquire_pool_vision')
	return Tasks.ResultAfter(bot,task,before)
end
function L.End(bot,task,reason)
	if task then
		local observation=Resources.Get(bot,'lotus',task.resourceIndex)
		if observation and observation.identity==task.resourceIdentity and observation.count and observation.count<task.initialCount then
			Resources.Log(bot,observation,'consumed',Items.Count(bot)>task.inventoryBefore and 'inventory_increased' or 'pool_count_decreased')
		else Resources.Log(bot,observation,'released',reason or 'mode_end') end
		Resources.Defer(bot,'lotus',task.resourceIndex,reason,5)
	end
	local state=State(bot);state.task=nil;state.nextSearch=DotaTime()+1
end
return L
