local Config = require(GetScriptDirectory()..'/THDFuncLib/push_escort_config')
local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Movement = {}

local function Point(point) return Vector(point.x,point.y,point.z) end
local function Read(default,callback)
	local ok,value = pcall(callback)
	if ok and value ~= nil then return value end
	return default
end

local function State(bot)
	if bot.THD_PushMovement == nil then
		bot.THD_PushMovement = {failed = {}, elapsed = 0, total = 0, failures = 0, generation = 0}
	end
	return bot.THD_PushMovement
end

local function Log(bot,state,event,reason)
	if not Config.DEBUG then return end
	local now = DotaTime()
	if (event == 'sample' or event == 'hold') and now-(state.logAt or -90) < Config.LOG_INTERVAL then return end
	state.logAt = now
	local position = bot:GetLocation()
	local velocity = Read(nil,function() return bot:GetVelocity() end)
	local speed = velocity and math.sqrt(velocity.x*velocity.x+velocity.y*velocity.y) or -1
	print(string.format('[BOT][PushMovement] run=%s time=%.3f pid=%s event=%s reason=%s generation=%s objective=%s x=%.1f y=%.1f goal_x=%s goal_y=%s remaining=%s stall_s=%.2f total_stall_s=%.2f failures=%s action=%s mode=%s velocity=%.1f move_speed=%s yield_until=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),event,tostring(reason),state.generation,tostring(state.objectiveID),
		position.x,position.y,tostring(state.goal and state.goal.x),tostring(state.goal and state.goal.y),
		tostring(state.goal and Geometry.Distance(position,state.goal)),state.elapsed,state.total,state.failures,
		tostring(bot:GetCurrentActionType()),tostring(bot:GetActiveMode()),speed,
		tostring(Read(-1,function() return bot:GetCurrentMovementSpeed() end)),tostring(state.yieldUntil)))
end

local function TowerFailure(reason)
	return type(reason) == 'string' and string.find(reason,'^tower_') ~= nil
end

function Movement.Blocked(bot,point,navigation,safetyKey)
	local state,now = State(bot),DotaTime()
	local position = bot:GetLocation()
	for index = #state.failed,1,-1 do
		local failed = state.failed[index]
		-- 塔、承伤和授权变化后重新过安全门；物理无进展/地形失败仍保留原期限。
		if now >= failed.untilAt or (safetyKey ~= nil and TowerFailure(failed.reason) and failed.safetyKey ~= safetyKey) then
			table.remove(state.failed,index)
		elseif Geometry.Distance(position,failed.origin) <= 256
		and Geometry.Distance(point,failed.goal) <= Config.MOVE_FAILED_RADIUS
		and not (navigation and failed.reason == 'impassable_segment') then return true,failed.reason end
	end
	return false
end

function Movement.Reject(bot,point,reason,safetyKey)
	if point == nil then return end
	-- 视野随兵线即时变化，不把一次不可见当作持续地形障碍。
	if reason == 'unseen_goal' or reason == 'unseen_segment' then return end
	local state = State(bot)
	-- 不让已有塔区拒绝掩盖新增的物理无进展记录，二者有不同失效条件。
	for _, failed in ipairs(state.failed) do
		if DotaTime() < failed.untilAt and failed.reason == reason and failed.safetyKey == safetyKey
		and Geometry.Distance(bot:GetLocation(),failed.origin) <= 256
		and Geometry.Distance(point,failed.goal) <= Config.MOVE_FAILED_RADIUS then return end
	end
	if #state.failed >= 32 then table.remove(state.failed,1) end
	state.failed[#state.failed+1] = {origin = Point(bot:GetLocation()), goal = Point(point), reason = reason,
		safetyKey = safetyKey, untilAt = DotaTime()+Config.MOVE_FAILED_TTL}
end

local function ReleaseTracking(bot,state,reason)
	if state.goal ~= nil or state.ownedIntent ~= nil then Log(bot,state,'released',reason) end
	-- 只忘记本模块持有的意图，不清动作或其他模式的队列。
	if state.ownedIntent ~= nil and state.ownedIntent == bot.THD_ActionIntent then Actions.Forget(bot) end
	state.goal,state.holdGoal,state.holdTolerance,state.ownedIntent = nil,nil,nil,nil
	state.bestDistance,state.elapsed = nil,0
end

-- 独立于共享目标/动作发单次数的物理进展账本；不清技能队列、不下移动命令。
function Movement.Observe(bot)
	local state = State(bot)
	if not Config.PUSH_ESCORT_ENABLED then return state end
	local now = DotaTime()
	if now-(state.observedAt or -90) < 0.10 then return state end
	local dt = math.min(0.5,math.max(0,now-(state.observedAt or now)))
	state.observedAt = now
	local position = bot:GetLocation()
	if state.anchor ~= nil and Geometry.Distance(position,state.anchor) >= Config.MOVE_PROGRESS_DISTANCE then
		state.anchor = Point(position)
		state.elapsed,state.total,state.failures,state.recovering = 0,0,0,false
		state.yieldUntil = nil
	end
	local mode = bot:GetActiveMode()
	local inPush = mode == BOT_MODE_PUSH_TOWER_TOP or mode == BOT_MODE_PUSH_TOWER_MID or mode == BOT_MODE_PUSH_TOWER_BOT
	local pause = not bot:IsAlive() and 'dead' or (not inPush and 'other_mode' or nil)
	if pause == nil and Actions.Protected(bot,nil,true) then pause = 'protected_cast' end
	if pause == nil and Read(true,function() return bot:IsRooted() or bot:IsStunned() or bot:IsNightmared() end) then pause = 'controlled' end
	state.pauseReason = pause
	if pause ~= nil then
		if pause == 'dead' or pause == 'other_mode' then
			ReleaseTracking(bot,state,pause)
			-- 模式切换不刷新失败预算；死亡后交给复活的新任务重新建立记录。
			if pause == 'dead' then
				state.anchor,state.total,state.failures,state.recovering,state.yieldUntil = nil,0,0,false,nil
			end
		elseif state.goal ~= nil then Log(bot,state,'sample',pause) end
		return state
	end
	if state.goal == nil then return state end
	local remaining = Geometry.Distance(position,state.goal)
	if remaining <= math.min(state.tolerance or 80,120) then
		Log(bot,state,'arrived','goal_reached')
		state.holdGoal,state.holdTolerance = Point(state.goal),state.tolerance
		state.goal = nil
		state.elapsed,state.recovering = 0,false
		return state
	end
	if bot:GetCurrentActionType() == BOT_ACTION_TYPE_ATTACK then
		Log(bot,state,'sample','attacking')
		state.goal,state.recovering,state.yieldUntil = nil,false,nil
		state.elapsed = 0
		return state
	end
	if remaining < (state.bestDistance or remaining)-Config.MOVE_PROGRESS_DISTANCE then
		state.elapsed,state.total,state.failures,state.recovering = 0,0,0,false
		state.anchor = Point(position)
	end
	state.bestDistance = math.min(state.bestDistance or remaining,remaining)
	state.elapsed,state.total = state.elapsed+dt,state.total+dt
	if state.elapsed >= Config.MOVE_STALL_SECONDS then
		Movement.Reject(bot,state.goal,'accepted_without_motion')
		state.failures = state.failures+1
		state.recovering = true
		if state.failures >= Config.MOVE_MAX_FAILURES then state.yieldUntil = now+Config.MOVE_YIELD_SECONDS end
		Log(bot,state,'stalled','accepted_without_motion')
		ReleaseTracking(bot,state,'accepted_without_motion')
	else Log(bot,state,'sample','moving') end
	return state
end

function Movement.Accept(bot,goal,tolerance,objectiveID)
	local state = State(bot)
	state.holdGoal,state.holdTolerance = nil,nil
	state.ownedIntent = bot.THD_ActionIntent
	local first = state.goal == nil
	if first then
		state.generation = state.generation+1
		state.elapsed = 0
	end
	-- 只重置一次有限的新路线尝试；total/failures不随重发或更换建筑重置。
	if state.goal == nil or Geometry.Distance(state.goal,goal)>32 then
		state.bestDistance = Geometry.Distance(bot:GetLocation(),goal)
	end
	state.goal,state.tolerance,state.objectiveID = Point(goal),tolerance,objectiveID
	state.anchor = state.anchor or Point(bot:GetLocation())
	state.observedAt = state.observedAt or DotaTime()
	if first then Log(bot,state,'accepted',state.recovering and 'recovery_attempt' or 'new_goal') end
end

function Movement.Hold(bot,goal,tolerance,objectiveID)
	local state = State(bot)
	if goal == nil or Geometry.Distance(bot:GetLocation(),goal) > math.min(tolerance or 80,120) then return false end
	-- 到位是稳定状态，不反复重建同一个移动任务，更不把到位算成新的位移进展。
	local same = state.holdGoal ~= nil and Geometry.Distance(state.holdGoal,goal) <= 32
		and state.objectiveID == objectiveID
	if state.ownedIntent ~= nil and state.ownedIntent == bot.THD_ActionIntent
	and bot:GetCurrentActionType() == BOT_ACTION_TYPE_MOVE_TO and not Actions.Protected(bot)
	and Read(-1,function() return bot:NumQueuedActions() end) == 0 then
		-- 只停自己的无队列移动，保留技能、物品、其他模式的命令。
		bot:Action_ClearActions(false)
		Actions.Forget(bot)
	end
	state.ownedIntent = nil
	state.goal,state.holdGoal,state.holdTolerance = nil,Point(goal),tolerance
	state.objectiveID = objectiveID
	state.elapsed,state.recovering = 0,false
	if not same then Log(bot,state,'hold','already_in_position') end
	return true
end

function Movement.Yielding(bot)
	return Config.PUSH_ESCORT_ENABLED and DotaTime() < (State(bot).yieldUntil or -90)
end

function Movement.NeedsRecovery(bot)
	return State(bot).recovering == true
end

function Movement.Candidates(bot)
	local origin,result = bot:GetLocation(),{}
	for _, radius in ipairs({128,256}) do
		for index=0,7 do
			local angle = index*math.pi/4
			result[#result+1] = Vector(origin.x+math.cos(angle)*radius,origin.y+math.sin(angle)*radius,origin.z)
		end
	end
	return result
end

function Movement.NoPath(bot)
	local state = State(bot)
	if state.pauseReason ~= nil then Log(bot,state,'sample','path_rejected_while_'..state.pauseReason); return end
	ReleaseTracking(bot,state,'no_safe_path')
	state.failures = state.failures+1
	state.recovering = true
	if state.failures >= Config.MOVE_MAX_FAILURES then state.yieldUntil = DotaTime()+Config.MOVE_YIELD_SECONDS end
	Log(bot,state,'rejected','no_safe_path')
end

return Movement
