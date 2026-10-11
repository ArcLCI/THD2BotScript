-- THD保护的薄适配：不选路线/建筑，不提供推进Think，只短暂停止确认无效的建筑攻击。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local G={}
local states=setmetatable({}, {__mode='k'})
local function Lane(mode)
	if mode==BOT_MODE_PUSH_TOWER_TOP then return LANE_TOP end
	if mode==BOT_MODE_PUSH_TOWER_MID then return LANE_MID end
	if mode==BOT_MODE_PUSH_TOWER_BOT then return LANE_BOT end
end
local function Blocked(bot,target)
	if not target or target:IsNull() or not target:CanBeSeen() or not target:IsAlive() or target:GetTeam()==bot:GetTeam() then return false end
	local name=target:GetUnitName()
	if not (string.find(name,'^npc_dota_.*tower[234]') or string.find(name,'^npc_dota_.*fort$')) then return false end
	-- 护符和原生反偷塔由引擎处理；这里只识别本图KV确认的自定义保护缺口。
	return not target:HasModifier('modifier_fountain_glyph') and not target:HasModifier('modifier_backdoor_protection_active')
		and not target:HasModifier('modifier_thdots_anti_bd_stop')
end
local function Log(bot,state,event)
	print(string.format('[BOT][NativeBuildingGuard] run=%s time=%.3f pid=%d lane=%d event=%s target=%s until_at=%.3f',
		Config.RUN_ID,DotaTime(),bot:GetPlayerID(),state.lane,event,state.name,state.untilAt))
end
local function Refresh(bot)
	if not Config.NATIVE_PUSH_THD_PROTECTION or not bot or not bot:IsAlive() or bot:IsIllusion() then return nil end
	local now=DotaTime()
	local state=states[bot]
	local currentTarget=bot:GetAttackTarget()
	if state and (now>=state.untilAt or not Blocked(bot,state.target) or (currentTarget and currentTarget~=state.target)) then
		Log(bot,state,'released');states[bot]=nil;state=nil
	end
	local lane=Lane(bot:GetActiveMode())
	local target=bot:GetAttackTarget()
	if not state and lane and bot:GetCurrentActionType()==BOT_ACTION_TYPE_ATTACK and Blocked(bot,target) then
		state={target=target,name=target:GetUnitName(),lane=lane,seenAt=now,untilAt=now+2}
		states[bot]=state
	end
	return state
end
function G.Desire(bot,lane)
	local state=Refresh(bot)
	if state and state.lane==lane and DotaTime()-state.seenAt>=0.3 and not Actions.Protected(bot,nil,true) then
		if not state.logged then Log(bot,state,'veto');state.logged=true end
		return 0
	end
	-- 7.38已确认负值进入原生GetDesire，内部建筑候选仍由引擎准备。
	return -1
end
function G.StopDesire(bot)
	local state=Refresh(bot)
	if not state or state.stopped or DotaTime()-state.seenAt<0.3 or Actions.Protected(bot,nil,true) then return 0 end
	if bot:GetCurrentActionType()~=BOT_ACTION_TYPE_ATTACK or bot:GetAttackTarget()~=state.target then return 0 end
	return 0.99 -- 严重原生撤退1.0仍可优先接管。
end
function G.Think(bot)
	local state=Refresh(bot)
	if not state or state.stopped or Actions.Protected(bot,nil,true) then return end
	-- 只清理仍指向原保护目标的普攻；不能清除新移动、技能、物品或排队动作。
	if bot:GetCurrentActionType()==BOT_ACTION_TYPE_ATTACK and bot:GetAttackTarget()==state.target and bot:NumQueuedActions()==0 then
		bot:Action_ClearActions(false);Actions.Forget(bot);Log(bot,state,'stopped')
	else Log(bot,state,'action_changed') end
	state.stopped=true
end
return G
