local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Exit = {}

local function Safe(default,callback)
	local ok,value = pcall(callback)
	if ok and value ~= nil then return value end
	return default
end
local function Point(value) return Vector(value.x,value.y,value.z) end
local function IsLocation(value)
	if type(value) ~= 'table' and type(value) ~= 'userdata' then return false end
	return Safe(false,function() return type(value.x)=='number' and type(value.y)=='number' end)
end
local function State(bot)
	if bot.THD_HighGroundExit == nil then bot.THD_HighGroundExit = {towers = {}, generation = 0, retryAt = -90} end
	return bot.THD_HighGroundExit
end
local function Log(bot,state,event,reason)
	if not Config.HIGH_GROUND_EXIT_DEBUG then return end
	local now,route = DotaTime(),state.route
	if (event == 'moving' or event == 'unavailable') and now-(state.logAt or -90)<2 then return end
	state.logAt = now
	local position = Safe(Vector(0,0,0),function() return bot:GetLocation() end)
	print(string.format('[BOT][HighGroundExit] run=%s time=%.3f pid=%s event=%s reason=%s generation=%s alive=%s mask=%s lane=%s policy=%s phase=%s x=%.1f y=%.1f goal_x=%s goal_y=%s deadline=%s',
		Config.HIGH_GROUND_EXIT_VERSION,now,Safe(-1,function() return bot:GetPlayerID() end),event,tostring(reason),state.generation,tostring(state.aliveCount),tostring(state.mask),
		tostring(route and route.lane),tostring(route and route.policy),tostring(route and route.phase),position.x,position.y,
		tostring(route and route.goal.x),tostring(route and route.goal.y),tostring(route and route.deadline)))
end

-- 开局缓存地图固定位置，塔死后继续使用；查询异常不视为塔已死亡。
function Exit.Observe(bot)
	local state,now = State(bot),DotaTime()
	if not Config.HIGH_GROUND_EXIT_ENABLED then return state end
	if now < (state.nextScan or -90) then return state end
	state.nextScan = now + Config.HIGH_GROUND_EXIT_SCAN_INTERVAL
	local team = GetOpposingTeam()
	local ancient = Safe(nil,function() return GetAncient(team) end)
	local center = ancient and Safe(nil,function() return ancient:GetLocation() end)
	if IsLocation(center) then state.center = Point(center) end
	local definitions = {{lane=LANE_TOP,id=TOWER_TOP_3},{lane=LANE_MID,id=TOWER_MID_3},{lane=LANE_BOT,id=TOWER_BOT_3}}
	local count,complete,mask = 0,true,{}
	for index,definition in ipairs(definitions) do
		local entry = state.towers[index] or {lane=definition.lane,id=definition.id}
		state.towers[index] = entry
		local ok,tower = pcall(GetTower,team,definition.id)
		entry.known = ok
		if ok and tower ~= nil then
			local alive = Safe(nil,function() return not tower:IsNull() and tower:IsAlive() end)
			entry.known = alive ~= nil
			entry.alive = alive == true
			-- false不是nil，死亡塔不能通过and表达式把布尔值送进几何函数。
			local location = nil
			if alive == true then location = Safe(nil,function() return tower:GetLocation() end) end
			if IsLocation(location) and IsLocation(state.center)
			and Geometry.Distance(location,state.center) > 400 and Geometry.Distance(location,state.center) < 6000 then
				entry.location = Point(location)
				-- 不可见塔不能查询动态射程；pcall不会阻止引擎输出视野违规警告。
				-- 未观测过时采用游戏KV的T3基础射程750，之后保留最后可见值。
				entry.range = entry.range or 750
				if Safe(false,function() return tower:CanBeSeen() end) then
					local range = tonumber(Safe(nil,function() return tower:GetAttackRange() end))
					if range ~= nil and range > 0 then entry.range = range end
				end
				entry.height = Safe(nil,function() return GetHeightLevel(location) end)
			end
		elseif ok then entry.alive = false end
		if not entry.known or entry.location == nil then complete = false end
		if entry.alive then count = count+1 end
		mask[index] = entry.known and (entry.alive and '1' or '0') or '?'
	end
	state.aliveCount,state.complete = count,complete and state.center ~= nil
	state.mask = table.concat(mask,'')
	return state
end

local function SignedDistance(a,b,p)
	return ((b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x))/math.max(1,Geometry.Distance(a,b))
end

local function Inside(bot,state)
	if not state.complete then return false end
	local position = bot:GetLocation()
	local radius,minHeight = 0,math.huge
	for _, tower in ipairs(state.towers) do
		radius = math.max(radius,Geometry.Distance(tower.location,state.center))
		if tower.height ~= nil then minHeight = math.min(minHeight,tower.height) end
	end
	state.baseRadius = radius+1400
	if Geometry.Distance(position,state.center) > state.baseRadius then return false end
	local height = Safe(nil,function() return GetHeightLevel(position) end)
	if height ~= nil and minHeight < math.huge and height < minHeight then return false end
	for index=1,2 do
		local a,b = state.towers[index].location,state.towers[index+1].location
		local direction = SignedDistance(a,b,state.center) >= 0 and 1 or -1
		if SignedDistance(a,b,position)*direction < -96 then return false end
	end
	return true
end

local function MakeRoute(bot,state,entry)
	local tower,center = entry.location,state.center
	local inward = (center-tower):Normalized()
	local side = Vector(-inward.y,inward.x,0)
	local gate = nil
	-- 活塔中心有碰撞，取其内侧的近点；仍按该塔实际位置选最近出口。
	for _, offset in ipairs({0,160,-160,280,-280}) do
		local point = entry.alive and tower+inward*180+side*offset or tower+side*offset
		if Safe(false,function() return IsLocationPassable(point) end) then gate = point; break end
	end
	if gate == nil then return nil end
	local amount = GetAmountAlongLane(entry.lane,tower).amount
	local own = GetAncient(bot:GetTeam())
	if own == nil then return nil end
	local ownAmount = GetAmountAlongLane(entry.lane,own:GetLocation()).amount
	local direction = ownAmount < amount and -1 or 1
	local outside = nil
	for _, delta in ipairs({0.015,0.025,0.035,0.045,0.06,0.08}) do
		local point = GetLocationAlongLane(entry.lane,math.max(0,math.min(1,amount+direction*delta)))
		if Geometry.Distance(point,tower) >= (entry.alive and entry.range or 450)+Config.HIGH_GROUND_EXIT_MARGIN
		and Safe(false,function() return IsLocationPassable(point) end) then outside=point; break end
	end
	if outside == nil then return nil end
	local now = DotaTime()
	local distance = Geometry.Distance(bot:GetLocation(),gate)+Geometry.Distance(gate,outside)
	local duration = math.min(Config.HIGH_GROUND_EXIT_MAX_TIME,math.max(4,distance/math.max(150,bot:GetCurrentMovementSpeed())+3))
	return {lane=entry.lane,id=entry.id,entry=Point(tower),gate=Point(gate),outside=Point(outside),goal=Point(gate),
		towerMask=state.mask,
		policy=state.aliveCount==3 and 'nearest_live_cross' or 'nearest_destroyed_gap',phase='TO_GATE',
		startedAt=now,deadline=now+duration,progressAt=now,progressLocation=Point(bot:GetLocation()),
		bestDistance=Geometry.Distance(bot:GetLocation(),gate)}
end

function Exit.Reset(bot,reason)
	if bot == nil then return end
	local state = State(bot)
	if state.route ~= nil then Log(bot,state,'released',reason) end
	state.route = nil
end

function Exit.NoteAction(bot,accepted,issued)
	local state = State(bot)
	if issued then Log(bot,state,'issued','move_to')
	elseif not accepted then Log(bot,state,'unavailable','action_rejected') end
end

function Exit.Update(bot,scan,active,paused)
	if not Config.HIGH_GROUND_EXIT_ENABLED then return nil end
	local state,now = Exit.Observe(bot),DotaTime()
	if not state.complete then
		if state.route ~= nil then
			state.retryAt = now+Config.HIGH_GROUND_EXIT_RETRY
			Exit.Reset(bot,'tower_state_unknown')
			return nil,'tower_state_unknown'
		end
		if scan.triggered and state.center and Geometry.Distance(bot:GetLocation(),state.center) < 5000 then
			Log(bot,state,'unavailable','tower_layout_unknown')
		end
		return nil
	end
	local inside = Inside(bot,state)
	local route = state.route
	local previous = nil
	if route ~= nil and inside and not paused and route.phase == 'TO_GATE' and route.towerMask ~= state.mask then
		-- 新塔被拆时重新按缺口选择；已经出门后不掉头，原预算也不延长。
		previous,route = route,nil
	end
	if route == nil then
		local retreating = bot:GetActiveMode() == BOT_MODE_RETREAT and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE
		if now < state.retryAt or not inside or not (scan.triggered or active or retreating) then return nil end
		local selected,distance = nil,math.huge
		for _, entry in ipairs(state.towers) do
			if state.aliveCount == 3 or not entry.alive then
				local d = Geometry.Distance(bot:GetLocation(),entry.location)
				if d < distance then selected,distance = entry,d end
			end
		end
		route = selected and MakeRoute(bot,state,selected)
		if route == nil then
			state.retryAt=now+Config.HIGH_GROUND_EXIT_RETRY
			if previous then Exit.Reset(bot,'exit_unreachable'); return nil,'exit_unreachable' end
			return nil
		end
		if previous then route.startedAt,route.deadline = previous.startedAt,previous.deadline end
		state.route,state.generation = route,state.generation+1
		Log(bot,state,'selected','tower_state_policy')
	end
	local current = bot:GetLocation()
	if paused then
		route.progressAt=now
		route.progressLocation=Point(current)
		Log(bot,state,'moving','protected_or_controlled')
		return route
	end
	local reason = nil
	if not inside and (Geometry.Distance(current,state.center) > (state.baseRadius or 4500)
		or (not scan.triggered and #(scan.containingZones or {})==0)) then reason='left_high_ground' end
	local direction = (route.outside-route.entry):Normalized()
	local projection = (current.x-route.entry.x)*direction.x + (current.y-route.entry.y)*direction.y
	if route.phase == 'TO_GATE' and (Geometry.Distance(current,route.gate) <= Config.HIGH_GROUND_EXIT_REACH or projection >= 120) then
		route.phase,route.goal,route.progressAt = 'OUTWARD',Point(route.outside),now
		route.bestDistance = Geometry.Distance(current,route.goal)
		Log(bot,state,'phase','gate_reached')
	end
	if route.phase == 'OUTWARD' and Geometry.Distance(current,route.outside) <= 180 then reason='exit_reached' end
	local distance = Geometry.Distance(current,route.goal)
	if distance < route.bestDistance-64 or Geometry.Distance(current,route.progressLocation) >= 96 then
		route.progressAt,route.progressLocation = now,Point(current)
		route.bestDistance = math.min(route.bestDistance,distance)
	end
	if reason == nil and now >= route.deadline then reason='deadline' end
	if reason == nil and now-route.progressAt >= Config.HIGH_GROUND_EXIT_STALL then reason='no_progress' end
	if reason ~= nil then
		state.retryAt = now+Config.HIGH_GROUND_EXIT_RETRY
		Exit.Reset(bot,reason)
		return nil,reason
	end
	Log(bot,state,'moving','exit_route')
	return route
end

return Exit
