-- 只拾取战旗和本图神奇芒果；不丢现有装备腾格，不承担购买/合成事务。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Tasks=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_task')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Consumables=require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')
local Towers=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/tower_safety')
local Geometry=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Strategy=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/base_threat')
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local NativeProgress=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/native_push_progress')
local P={}
local allowed={item_roshans_banner=true,item_magic_mushroom=true}
local states=setmetatable({}, {__mode='k'})
local function State(bot)
	states[bot]=states[bot] or {nextSearch=-90,serial=0}
	return states[bot]
end
local function Count(bot,name)
	local n=0
	for slot=0,8 do local item=bot:GetItemInSlot(slot);if item and item:GetName()==name then n=n+math.max(1,item:GetCurrentCharges()) end end
	return n
end
local function Room(bot)
	for slot=0,8 do if not bot:GetItemInSlot(slot) then return true end end
	return false
end
local function Safe(bot,point)
	local tower=Towers.Observe(bot,'resource_pickup')
	if not tower.available then return false end
	return Geometry.ValidateMovementSegment(bot:GetLocation(),point,tower.towers,96)
		and Geometry.ValidateLocalTerrainSegment(bot:GetLocation(),point,true)
end
local function Eligible(bot)
	if not Config.MAP_RESOURCES_ENABLED or not bot:IsAlive() or Actions.Protected(bot) or J.CanNotUseAction(bot) or Consumables.GetState(bot) then return false end
	if J.Retreat.ShouldYield(bot,J.Retreat.HIGH) or J.IsRoshanCommitmentActive(bot) or bot:WasRecentlyDamagedByAnyHero(2) then return false end
	local base=Strategy.GetBaseThreatSnapshot(nil,bot)
	return not (base and base.hardEmergency) and #(J.GetNearbyHeroes(bot,1200,true,BOT_MODE_NONE) or {})==0
end
local function Find(handle)
	for _,drop in pairs(GetDroppedItemList()) do if drop.item==handle then return drop end end
end
local function Log(bot,task,event,reason)
	if Config.DEBUG then print(string.format('[BOT][ResourcePickup] run=%s time=%.3f pid=%s event=%s item=%s key=%s reason=%s deadline=%.3f',
		Config.RUN_ID,DotaTime(),bot:GetPlayerID(),event,task.itemName,task.key,reason,task.deadline)) end
end
function P.Prepare(bot)
	local state,now=State(bot),DotaTime()
	if not Eligible(bot) or Tasks.HasOtherExecution(bot,'roam') then return nil end
	-- 推进小组仍在取得实际进展时不为普通掉落离队，已发拾取只完成短确认。
	if NativeProgress.ShouldPreserve(bot) and not (state.task and state.task.pickupAt) then return nil end
	if state.task and now<state.task.deadline then
		local task={};for k,v in pairs(state.task) do task[k]=v end
		task.preparedAt,task.validUntil=now,math.min(now+Config.CANDIDATE_TTL,task.deadline)
		return task,task.pickupAt and 0.96 or 0.5
	end
	if now<state.nextSearch or not Room(bot) then return nil end
	state.nextSearch=now+1
	local best,range
	for _,drop in pairs(GetDroppedItemList()) do
		local item=drop.item
		if item and not item:IsNull() and allowed[item:GetName()] and drop.location and IsLocationVisible(drop.location)
			and (not drop.owner or drop.owner==bot) then
			local distance=GetUnitToLocationDistance(bot,drop.location)
			if distance<=1000 and (not range or distance<range) and Safe(bot,drop.location) then best,range=drop,distance end
		end
	end
	if not best then return nil end
	state.serial=state.serial+1
	local task={executionVersion=2,key='resource_pickup:'..state.serial,provider='resource_pickup',intent='move',
		item=best.item,itemName=best.item:GetName(),location=best.location,before=Count(bot,best.item:GetName()),
		preparedAt=now,validUntil=now+Config.CANDIDATE_TTL,deadline=now+8,stallSeconds=3,tolerance=48,reason='resource_pickup',mode=BOT_MODE_ROAM}
	state.task=task;Log(bot,task,'prepared','visible_safe_drop');return task,0.5
end
function P.Execute(bot,task)
	State(bot).task=task
	if Count(bot,task.itemName)>task.before then Log(bot,task,'confirmed','inventory_increased');return {status='COMPLETE',reason='resource_inventory_increased'} end
	if Actions.Protected(bot) then return {status='PROTECTED',reason='protected_lifecycle'} end
	if not Eligible(bot) then return {status='INVALID',reason='resource_pickup_unsafe'} end
	local drop=Find(task.item)
	if not drop then return {status='COMPLETE',reason='resource_drop_gone_unattributed'} end
	if not Room(bot) then return {status='INVALID',reason='resource_inventory_full'} end
	if task.pickupAt then
		if DotaTime()>=task.deadline then return {status='INVALID',reason='resource_pickup_unconfirmed'} end
		return {status='WAITING',reason='resource_pickup_confirmation',deadline=task.deadline}
	end
	if NativeProgress.ShouldPreserve(bot) then return {status='INVALID',reason='productive_push_assignment'} end
	if not Safe(bot,drop.location) then return {status='BLOCKED',reason='resource_pickup_path'} end
	if GetUnitToLocationDistance(bot,drop.location)>150 then
		task.location=drop.location;local before=Tasks.Capture(bot)
		J.ActionMoveToLocation(bot,'resource_pickup',task.location,0.4,48,function(point) return Safe(bot,point) end)
		return Tasks.ResultAfter(bot,task,before)
	end
	bot:Action_PickUpItem(task.item);Actions.NoteIssued(bot,'inventory',task.item)
	task.pickupAt=DotaTime();task.intent='wait';task.deadline=math.min(task.deadline,task.pickupAt+1.5)
	Log(bot,task,'issued','await_inventory');return {status='WAITING',reason='resource_pickup_confirmation',deadline=task.deadline}
end
function P.End(bot,task,reason)
	if task then Log(bot,task,'released',reason or 'mode_end') end
	local state=State(bot);state.task=nil;state.nextSearch=DotaTime()+3
end
return P
