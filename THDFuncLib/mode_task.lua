-- 候选与活动任务分开保存；退出仅释放任务，绝不清理技能/物品的动作保护。
local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
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
function M.Active(bot, name) return State(bot,name).active end
function M.Candidate(bot, name) return State(bot,name).candidate end
function M.Release(bot, name, reason, retry)
	local state = State(bot,name)
	local hadTask=state.active~=nil or state.candidate~=nil
	state.active, state.candidate = nil, nil
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
	return score
end
function M.Start(bot, name)
	local state=State(bot,name)
	local candidate=state.candidate
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
return M
