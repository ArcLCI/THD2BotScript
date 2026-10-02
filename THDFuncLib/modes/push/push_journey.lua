-- 护送与基础兵线后备共用行程；只记录几何进展，不授予移动或塔区权限。
local Geometry=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Routes=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/local_route_candidates')
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local P={}
local function Copy(point) return Vector(point.x,point.y,point.z) end
local function Log(bot,route,event,reason)
	if not Config.DEBUG then return end
	local now=DotaTime()
	if (event=='progress' or event=='blocked') and now-(route.logAt or -90)<2 then return end
	route.logAt=now
	local position=bot:GetLocation()
	print(string.format('[BOT][PushJourney] run=%s time=%.3f pid=%s lane=%s serial=%s event=%s reason=%s x=%.1f y=%.1f goal_x=%.1f goal_y=%.1f remaining=%.1f best=%.1f deadline=%.3f history=%d',
		Config.RUN_ID,now,bot:GetPlayerID(),route.lane,route.serial,event,tostring(reason),position.x,position.y,
		route.goal.x,route.goal.y,Geometry.Distance(position,route.goal),route.best,route.deadline,#route.history))
end
function P.Current(bot,lane,target)
	local route=bot.THD_PushJourneys and bot.THD_PushJourneys[lane]
	if route and (not target or route.target==target) then return route end
end
function P.Complete(bot,lane,target)
	local route=P.Current(bot,lane,target)
	if not route then return false end
	-- 迟到、未执行或已释放的旧记录只收尾，不追认成成功行程。
	local reason=route.failedAt and (route.failure or 'push_journey_failed') or (DotaTime()>=route.deadline and 'push_journey_late_arrival')
		or (not route.startedAt and 'push_journey_not_executed')
	if not reason then
		local valid,why=P.Check(bot,route)
		if not valid then reason=why end
	end
	Log(bot,route,reason and 'closed' or 'complete',reason or 'local_objective_reached')
	bot.THD_PushJourneys[lane]=nil
	return not reason
end
function P.Check(bot,route)
	if not route or P.Current(bot,route.lane)~=route then return false,'push_journey_replaced' end
	if not bot:IsAlive() then return false,'push_journey_dead' end
	if not route.target or route.target:IsNull() or (route.target:CanBeSeen() and not route.target:IsAlive()) then return false,'push_journey_target_lost' end
	if route.failedAt then return false,route.failure end
	local now=DotaTime()
	local remaining=Geometry.Distance(bot:GetLocation(),route.goal)
	if route.startedAt and route.best-remaining>=48 then
		route.best,route.progressAt=remaining,now;Log(bot,route,'progress','net_approach')
	end
	local reason=now>=route.deadline and 'push_journey_deadline'
		or (route.startedAt and now-route.progressAt>=12 and 'push_journey_no_net_progress')
	if reason then route.failedAt,route.failure=now,reason;Log(bot,route,'released',reason);return false,reason end
	return true
end
function P.Prepare(bot,lane,target,goal)
	bot.THD_PushJourneys=bot.THD_PushJourneys or {}
	local previous=bot.THD_PushJourneys[lane]
	if previous and previous.target==target then
		local valid,reason=P.Check(bot,previous)
		if valid then return previous end
		if previous.failedAt and DotaTime()<previous.failedAt+8 then return nil,reason end
	end
	local now=DotaTime()
	local route={lane=lane,target=target,goal=Copy(goal),serial=(previous and previous.serial or 0)+1,
		deadline=now+30,best=Geometry.Distance(bot:GetLocation(),goal),history={}}
	-- 同目标失败后的短期重试保留已走路段，不能立刻重复原来的小环。
	if previous and previous.target==target and previous.failedAt and now<previous.failedAt+30 then
		for _,point in ipairs(previous.history) do route.history[#route.history+1]=point end
	end
	bot.THD_PushJourneys[lane]=route
	Log(bot,route,'prepared','fixed_goal');return route
end
function P.PointAllowed(bot,route,point)
	local valid,reason=P.Check(bot,route)
	if not valid then return false,reason end
	if not point then return false,'push_journey_missing_point' end
	local origin=bot:GetLocation()
	if route.point and Geometry.Distance(point,route.point)<1 then return true end
	for _,old in ipairs(route.history) do
		if Geometry.Distance(point,old)<128 then return false,'push_journey_return_to_history' end
	end
	if route.stepOrigin and Geometry.Distance(origin,route.stepOrigin)>48 then
		local incoming,outgoing=origin-route.stepOrigin,point-origin
		local length=incoming:Length2D()*outgoing:Length2D()
		if length>1 and (incoming.x*outgoing.x+incoming.y*outgoing.y)/length < -0.25 then return false,'push_journey_reverse' end
	end
	if Geometry.Distance(point,route.goal)>Geometry.Distance(origin,route.goal)+64 then return false,'push_journey_away_from_goal' end
	return true
end
function P.Select(bot,route,safe)
	local valid,reason=P.Check(bot,route)
	if not valid then return nil,reason end
	if route.point and GetUnitToLocationDistance(bot,route.point)>48 and safe(route.point) then return route.point end
	local candidates=Routes.Journey(bot:GetLocation(),route.goal,true)
	if GetUnitToLocationDistance(bot,route.goal)<=600 then table.insert(candidates,1,{location=route.goal}) end
	local lastReason='push_journey_no_safe_step'
	for index,entry in ipairs(candidates) do
		if index>Config.LOCAL_ROUTE_MAX_CHECKS then break end
		local point=entry.location
		local allowed,why=P.PointAllowed(bot,route,point)
		if allowed and GetUnitToLocationDistance(bot,point)>48 and GetUnitToLocationDistance(bot,point)<=600 then
			local ok,rejection=safe(point)
			if ok then return point end
			lastReason=rejection or lastReason
		elseif why then lastReason=why end
	end
	Log(bot,route,'blocked',lastReason);return nil,'push_journey_no_safe_step:'..lastReason
end
function P.Attach(plan,route)
	plan.pushJourney=route;plan.finalGoal=route.goal
	plan.deadline=math.min(plan.deadline or route.deadline,route.deadline)
	plan.tolerance=48
end
function P.NoteStep(bot,route,point)
	if not route or not point then return end
	local now=DotaTime()
	if not route.startedAt then route.startedAt,route.progressAt=now,now;route.best=Geometry.Distance(bot:GetLocation(),route.goal) end
	if not route.point or Geometry.Distance(point,route.point)>32 then
		if route.stepOrigin then route.history[#route.history+1]=route.stepOrigin end
		while #route.history>8 do table.remove(route.history,1) end
		route.stepOrigin,route.point=Copy(bot:GetLocation()),Copy(point)
		Log(bot,route,'step','accepted_not_arrival')
	end
end
return P
