-- 原生输出事实：只读动作、位置和可见建筑血量，不分配任务、不发单、不续租。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Buildings=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/building_rules')
local Progress=require(GetScriptDirectory()..'/THDFuncLib/modes/push/push_progress')
local Access=require(GetScriptDirectory()..'/THDFuncLib/modes/push/building_access')
local F={}
local states=setmetatable({}, {__mode='k'})
local audit=setmetatable({}, {__mode='k'})
local function Lane(mode)
	if mode==BOT_MODE_PUSH_TOWER_TOP then return LANE_TOP end
	if mode==BOT_MODE_PUSH_TOWER_MID then return LANE_MID end
	if mode==BOT_MODE_PUSH_TOWER_BOT then return LANE_BOT end
end
local function Log(bot,state,event,reason)
	if not Config.DEBUG then return end
	print(string.format('[BOT][NativePushProgress] run=%s time=%.3f pid=%d event=%s reason=%s target=%s lane=%d net=%s dps=%s',
		Config.RUN_ID,DotaTime(),bot:GetPlayerID(),event,reason,state.name,state.lane,
		tostring(state.netProgress and state.netProgress.net),tostring(state.netProgress and state.netProgress.dps)))
end
local function Clear(bot,reason)
	local state=states[bot]
	if state and state.productive then Log(bot,state,'lost',reason) end
	states[bot]=nil
end
function F.Update(bot)
	if not bot or bot:IsNull() then return nil end
	if not Config.NATIVE_PROGRESS_ENABLED or not bot:IsAlive() or not bot:IsHero() or bot:GetTeam()~=GetTeam()
	or bot:IsIllusion() then Clear(bot,'unavailable');return nil end
	local lane=Lane(bot:GetActiveMode())
	if not lane or bot:GetCurrentActionType()~=BOT_ACTION_TYPE_ATTACK
	or bot:IsUsingAbility() or bot:IsCastingAbility() or bot:IsChanneling() then Clear(bot,'mode_or_action_changed');return nil end
	local target=bot:GetAttackTarget()
	if not target or target:IsNull() or not target:CanBeSeen() or not target:IsAlive() then Clear(bot,'target_unavailable');return nil end
	if type(target.IsBuilding)~='function' or not target:IsBuilding() then Clear(bot,'not_building');return nil end
	local now=DotaTime()
	local state=states[bot]
	if state and (state.target~=target or state.lane~=lane) then Clear(bot,'target_changed');state=nil end
	-- 模式/目标每入口立即复核；建筑属性和距离每半秒最多读取一次。
	if state and now<(state.nextAt or -90) then return state end
	if not Buildings.GetManagedBuildingInfo(target) or not Buildings.CanControlledUnitAttackBuilding(bot,target) then
		Clear(bot,'building_protected');return nil
	end
	if GetUnitToUnitDistance(bot,target)>Access.Reach(bot,target)+16 then Clear(bot,'outside_attack_range');return nil end
	if not state then state={target=target,name=target:GetUnitName(),lane=lane};states[bot]=state end
	state.nextAt=now+Config.NATIVE_PROGRESS_SAMPLE_INTERVAL
	local health=target:GetHealth()
	local advanced=Progress.Observe(state,now,health)
	-- 血量回升不能用前一次掉血继续证明当前产出。
	if state.health and health>state.health+1 then state.verifiedAt=nil;advanced=false end
	state.health,state.at=health,now
	if advanced then state.verifiedAt=now end
	local productive=state.verifiedAt~=nil and now-state.verifiedAt<=Config.NATIVE_PROGRESS_FRESH_SECONDS
	if productive and (not state.productive or now-(state.logAt or -90)>=2) then
		Log(bot,state,'verified','visible_net_damage');state.logAt=now
	elseif state.productive and not productive then Log(bot,state,'lost','progress_stale') end
	state.productive=productive
	return state
end
function F.IsProductive(bot)
	local state=F.Update(bot)
	return state~=nil and state.productive==true
		and DotaTime()-(state.verifiedAt or -90)<=Config.NATIVE_PROGRESS_FRESH_SECONDS
end
function F.ShouldPreserve(bot)
	return Config.NATIVE_PROGRESS_AVOID_INTERRUPTS and F.IsProductive(bot)
end
function F.NoteOpportunity(bot,raw,adjusted,consumer)
	if not Config.DEBUG then return end
	local now=DotaTime()
	local old=audit[bot]
	if old and now-old<2 then return end
	audit[bot]=now
	print(string.format('[BOT][NativePushOpportunity] run=%s time=%.3f pid=%d consumer=%s raw=%.3f adjusted=%.3f',
		Config.RUN_ID,now,bot:GetPlayerID(),consumer or 'ordinary_task',raw,adjusted))
end
return F
