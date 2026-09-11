local G = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Threat = require(GetScriptDirectory()..'/THDFuncLib/skill_threat')
local Z = require(GetScriptDirectory()..'/THDFuncLib/skill_zones')
local Effects = require(GetScriptDirectory()..'/THDFuncLib/skill_effects')
local P = {}
local function Safe(default, fn) local ok, v = pcall(fn); if ok and v ~= nil then return v end; return default end
function P.Margin(bot) return Config.SKILL_SAFETY_MARGIN + math.max(0, Safe(32, function() return bot:GetBoundingRadius() end))
	+ P.Speed(bot)*Config.SKILL_SCAN_INTERVAL end
function P.Speed(bot) return math.max(1, Safe(300, function() return bot:GetCurrentMovementSpeed() end)) end
function P.EntryDistance(a, b, zone, margin)
	local length = G.Distance(a, b)
	local r = zone.radius + margin
	if G.PointInCircle(a, zone, margin) then return 0 end
	if length < 0.01 then return math.huge end
	local dx, dy = (b.x-a.x)/length, (b.y-a.y)/length
	local cx, cy = zone.center.x-a.x, zone.center.y-a.y
	local projection = cx*dx + cy*dy
	local perpendicular = cx*cx + cy*cy - projection*projection
	if perpendicular > r*r then return math.huge end
	local distance = projection - math.sqrt(math.max(0, r*r-perpendicular))
	if distance < 0 or distance > length then return math.huge end
	return distance
end
function P.LiveForSegment(a, b, zones, margin, speed, now, elapsed)
	local active = {}
	for _, zone in ipairs(zones) do
		local entry = P.EntryDistance(a, b, zone, margin)
		local timed=Effects.BurstExposure(a,b,zone,speed,now,elapsed,margin,false)
		if timed==true or (timed==nil and entry < math.huge and (elapsed or 0) + entry/speed < zone.expiresAt-now+Config.SKILL_TIME_MARGIN) then table.insert(active, zone) end
	end
	return active
end
function P.SafeSegment(a, b, zones, towers, margin)
	-- 技能执行不继承塔围攻许可；塔约束允许已在圈内的向外进展，不要求一步离开大塔圆。
	local ok,reason,detail=G.ValidateMovementSegment(a,b,zones,margin,true)
	if not ok then return false,reason,{kind='skill',constraint=detail} end
	ok,reason,detail=G.ValidateMovementSegment(a,b,towers,math.max(96,margin),true)
	if not ok then return false,reason,{kind='tower',constraint=detail} end
	ok,reason,detail=G.ValidateLocalTerrainSegment(a,b,false)
	if not ok then return false,reason,{kind='terrain',sample=detail} end
	return true
end
function P.Inside(point, zones, margin)
	local result = {}
	for _, zone in ipairs(zones) do if G.PointInCircle(point, zone, margin) then table.insert(result, zone) end end
	return result
end
function P.FindExit(bot, zones, towers, remainingBudget, rejected, exitMargin, context)
	-- 主动脱离的候选与退出判定共用滞回外边界，任务绕行仍使用原安全余量。
	local origin, margin = bot:GetLocation(), math.max(P.Margin(bot), exitMargin or 0)
	local containing = P.Inside(origin, zones, margin)
	if #containing == 0 then return nil, 0 end
	local cx, cy = 0, 0
	for _, zone in ipairs(containing) do cx, cy = cx+zone.center.x, cy+zone.center.y end
	cx, cy = cx/#containing, cy/#containing
	local base = math.atan2(origin.y-cy, origin.x-cx)
	local best, score, count, partial = nil, math.huge, 0, false
	for i=0,7 do
		count = count+1
		local angle = base + i*math.pi/4 + (rejected ~= nil and math.pi/8 or 0)
		local dx, dy, distance = math.cos(angle), math.sin(angle), 0
		for _, zone in ipairs(containing) do
			local x, y = origin.x-zone.center.x, origin.y-zone.center.y
			local projection = x*dx+y*dy
			local r = zone.radius+margin+48
			distance = math.max(distance, -projection+math.sqrt(math.max(0,projection*projection+r*r-x*x-y*y)))
		end
		-- 减速时完整出口可能超过2秒；允许预算内的向外短步，但绝不记作已安全离圈。
		distance=math.min(distance,P.Speed(bot)*remainingBudget*0.9)
		local target = G.MakeVector(origin.x+dx*distance, origin.y+dy*distance, origin.z)
		local deficit=0
		for _,zone in ipairs(zones) do deficit=deficit+math.max(0,zone.radius+margin-G.Distance(target,zone.center)) end
		local value=deficit*10+distance
		if context then value=value+Threat.ExitPenalty(context,origin,target) end
		if distance>=32 and (rejected == nil or G.Distance(target,rejected) >= 80)
		and P.SafeSegment(origin,target,zones,towers,margin) and value<score then
			best,score,partial=target,value,deficit>0
		end
	end
	if best and context then Threat.LogChoice(bot,'exit',count,score) end
	return best, count, partial
end
-- 每条左右候选只记录首个否决段，保留原校验顺序与布尔结果。
local function TraceCandidate(bot,plan,source,direction,stage,index,a,b,margin,total,reason,detail)
	local constraint=detail and detail.constraint
	local sample=detail and detail.sample
	local point=sample and sample.point
	Z.Log(bot,'detour_candidate',string.format('plan=%d generation=%d request=%d variant=%s source_key=%s side=%s stage=%s segment=%d reason=%s constraint_kind=%s constraint_key=%s from_x=%.1f from_y=%.1f to_x=%.1f to_y=%.1f margin=%.1f path_length=%.1f constraint_x=%.1f constraint_y=%.1f constraint_radius=%.1f sample_x=%.1f sample_y=%.1f sample_index=%d sample_steps=%d',
		plan,bot.THD_SkillAvoidance and bot.THD_SkillAvoidance.generation or 0,bot.THD_DetourRequestSeq or 0,bot.THD_DetourVariant or 'base',source.key,direction==1 and 'ccw' or 'cw',stage,index,reason,
		detail and detail.kind or 'none',constraint and tostring(constraint.key) or 'none',a.x,a.y,b.x,b.y,margin,total,
		constraint and constraint.center.x or 0,constraint and constraint.center.y or 0,constraint and constraint.radius or 0,
		point and point.x or 0,point and point.y or 0,sample and sample.index or -1,sample and sample.steps or -1))
end
-- 原生撤退投射点只是方向；只在末段失败时尝试有界、连续可走的局部接续点。
local function LocalRetreatGoal(bot,plan,origin,goal,zones,towers,margin,total)
	local length=G.Distance(origin,goal)
	if length<176 then return nil end
	local checked={}
	for _,distance in ipairs({math.min(512,length-48),384,256,128}) do
		if distance>=128 and distance<length and not checked[distance] and total+distance<=2400 then
			checked[distance]=true
			local point=G.MakeVector(origin.x+(goal.x-origin.x)*distance/length,origin.y+(goal.y-origin.y)*distance/length,origin.z)
			local clear=#P.Inside(point,zones,margin)==0
			local safe,reason,detail=P.SafeSegment(origin,point,zones,towers,margin)
			Z.Log(bot,'local_goal_probe',string.format('request=%d plan=%d distance=%.1f result=%s reason=%s from_x=%.1f from_y=%.1f goal_x=%.1f goal_y=%.1f projected_x=%.1f projected_y=%.1f',
				bot.THD_DetourRequestSeq,plan,distance,safe and clear and 'accepted' or 'rejected',not clear and 'inside_zone' or reason or 'clear',origin.x,origin.y,point.x,point.y,goal.x,goal.y))
			if safe and clear then return point end
		end
	end
	return nil
end
-- 接管前只保留预算内可到达且下一段可安全交还的前缀，不要求跑完整个圆弧。
local function BudgetedBridge(bot,origin,path,goal,zones,towers,margin,budget)
	local previous,total,prefix=origin,0,{}
	for index,point in ipairs(path) do
		total=total+G.Distance(previous,point)
		local eta=total/P.Speed(bot)+0.25+index*0.05
		if eta>budget then return nil,eta,'handoff_over_budget' end
		local safe=P.SafeSegment(previous,point,zones,towers,margin)
		if not safe then return nil,eta,'prefix_not_currently_safe' end
		table.insert(prefix,point)
		if #P.Inside(point,zones,margin)==0 and P.SafeSegment(point,goal,zones,towers,margin) then return prefix,eta,'ready' end
		previous=point
	end
	return nil,0,'no_safe_handoff'
end
local function FindDetourVariant(bot, goal, zones, towers, now, context, padding, maxAngle, variant)
	local origin, margin, speed = bot:GetLocation(), P.Margin(bot), P.Speed(bot)
	local danger, nearest = nil, math.huge
	for _, zone in ipairs(zones) do
		local distance = P.EntryDistance(origin, goal, zone, margin)
		local timed=Effects.BurstExposure(origin,goal,zone,speed,now,0,margin,true)
		if timed~=false and distance/speed < Config.SKILL_LOOKAHEAD_TIME and distance/speed < zone.expiresAt-now+Config.SKILL_TIME_MARGIN
		and distance < nearest then danger,nearest=zone,distance end
	end
	if danger == nil then return nil, 'clear', 0 end
	if G.PointInCircle(goal,danger,margin) then return nil, 'goal_inside', 0 end
	bot.THD_DetourPlanSeq=(bot.THD_DetourPlanSeq or 0)+1
	local plan=bot.THD_DetourPlanSeq
	-- 圆外切分折线使用外接半径；留出到点容差，不能用圆上弦穿过危险边界。
	bot.THD_DetourVariant=variant
	local orbit = (danger.radius+margin+48+padding)/math.cos(maxAngle/2)
	local a = math.atan2(origin.y-danger.center.y, origin.x-danger.center.x)
	local b = math.atan2(goal.y-danger.center.y, goal.x-danger.center.x)
	local best, bestLength, candidates, bestSide, bestGoal = nil, math.huge, 0, nil, nil
	for _, direction in ipairs({1,-1}) do
		candidates=candidates+1
		local sweep = ((b-a)*direction)%(2*math.pi)
		local steps = math.max(1,math.ceil(sweep/maxAngle))
		local path, previous, total, valid = {}, origin, 0, true
		for i=0,steps do
			local angle=a+direction*sweep*i/steps
			local point=G.MakeVector(danger.center.x+orbit*math.cos(angle),danger.center.y+orbit*math.sin(angle),origin.z)
			local active=P.LiveForSegment(previous,point,zones,margin,speed,now,total/speed)
			local safe,reason,detail=P.SafeSegment(previous,point,active,towers,margin)
			if not safe then
				TraceCandidate(bot,plan,danger,direction,i==0 and 'entry' or 'arc',i,previous,point,margin,total,reason,detail)
				valid=false;break
			end
			total=total+G.Distance(previous,point)
			if total>2400 then
				TraceCandidate(bot,plan,danger,direction,'arc',i,previous,point,margin,total,'path_length_limit',{kind='budget'})
				valid=false;break
			end
			table.insert(path,point);previous=point
		end
		-- 后续目标段也参与安全与追兵代价比较，避免只选一个局部好看的出口。
		local routeGoal=goal
		local live=P.LiveForSegment(previous,goal,zones,margin,speed,now,total/speed)
		if valid then
			local safe,reason,detail=P.SafeSegment(previous,goal,live,towers,margin)
			if not safe then
				TraceCandidate(bot,plan,danger,direction,'goal_link',steps+1,previous,goal,margin,total,reason,detail)
				local replacement=context and context.allowLocalRetreatGoal and LocalRetreatGoal(bot,plan,previous,goal,zones,towers,margin,total) or nil
				if replacement then routeGoal=replacement else valid=false end
			end
		end
		if valid and context and context.bridgeBudget then
			local prefix,eta,reason=BudgetedBridge(bot,origin,path,routeGoal,zones,towers,margin,context.bridgeBudget)
			Z.Log(bot,'bridge_budget_plan',string.format('request=%d plan=%d side=%s result=%s eta=%.3f budget=%.3f original_waypoints=%d retained_waypoints=%d',
				bot.THD_DetourRequestSeq,plan,direction==1 and 'ccw' or 'cw',reason,eta,context.bridgeBudget,#path,prefix and #prefix or 0))
			if prefix then path=prefix else valid=false end
		end
		local value=total
		if valid and context then
			local full={};for _,point in ipairs(path) do table.insert(full,point) end;table.insert(full,routeGoal)
			value=Threat.RouteCost(context,origin,full,goal)*600
		end
		if valid then TraceCandidate(bot,plan,danger,direction,'complete',steps+1,origin,routeGoal,margin,total,'accepted',nil) end
		if valid and value<bestLength then best,bestLength,bestSide,bestGoal=path,value,direction==1 and 'ccw' or 'cw',routeGoal end
	end
	return best, best~=nil and 'detour' or 'no_local_route', candidates, bestLength, bestSide, bestGoal
end
-- 先保留原两侧方案；只有都不可行才增加两档外扩，不能绕过地形/塔/技能校验。
function P.FindDetour(bot,goal,zones,towers,now,context)
	bot.THD_DetourRequestSeq=(bot.THD_DetourRequestSeq or 0)+1
	local points,reason,count,score,side,resolvedGoal=FindDetourVariant(bot,goal,zones,towers,now,context,0,math.pi/4,'base')
	if points then
		if context then Threat.LogChoice(bot,'detour',count,score,side) end
		return points,reason,count,resolvedGoal
	end
	if reason~='no_local_route' then return nil,reason,count end
	local best,bestScore,bestSide,bestVariant,bestGoal=nil,math.huge,nil,nil,nil
	for _,padding in ipairs({128,256}) do
		local candidate,candidateReason,candidateCount,candidateScore,candidateSide,candidateGoal=FindDetourVariant(bot,goal,zones,towers,now,context,padding,math.pi/8,'outer_'..padding)
		count=count+candidateCount
		if candidate and candidateScore<bestScore then best,bestScore,bestSide,bestVariant,bestGoal=candidate,candidateScore,candidateSide,padding,candidateGoal end
	end
	Z.Log(bot,'detour_fallback',string.format('request=%d candidates=%d result=%s padding=%d waypoints=%d',bot.THD_DetourRequestSeq,count,best and 'selected' or 'unavailable',bestVariant or 0,best and #best or 0))
	if best and context then Threat.LogChoice(bot,'detour',count,bestScore,bestSide) end
	return best,best and 'detour' or 'no_local_route',count,bestGoal
end
return P
