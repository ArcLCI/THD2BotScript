-- 疗伤莲花系列：名称/恢复值来自7.38原生KV，实际决策读取当前物品特殊值。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Consumables=require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local M={}
local weights={item_famango=1,item_great_famango=3,item_greater_famango=6}
local REQUESTER='map_resource_lotus_use'
local nextUse=setmetatable({}, {__mode='k'})
local diagnostics=setmetatable({}, {__mode='k'})
function M.Count(bot)
	local count=0
	for slot=0,8 do
		local item=bot:GetItemInSlot(slot)
		if item and weights[item:GetName()] then count=count+weights[item:GetName()]*math.max(0,item:GetCurrentCharges()) end
	end
	return count
end
function M.CanCollect(bot)
	for slot=0,8 do
		local item=bot:GetItemInSlot(slot)
		if not item or (item:GetName()=='item_famango' and item:GetCurrentCharges()<3) then return true end
	end
	return false
end
local function Need(bot,item)
	local amount=item:GetSpecialValueInt('replenish_amount')
	if amount<=0 then return false,0,0,false end
	local hp=math.max(0,bot:GetMaxHealth()-bot:GetHealth())
	local mp=math.max(0,bot:GetMaxMana()-bot:GetMana())
	local heal,mana=math.min(hp,amount),math.min(mp,amount)
	local urgent=bot:GetHealth()/math.max(1,bot:GetMaxHealth())<0.4 and heal>=math.min(100,amount*0.5)
	local useful=urgent or heal>=amount*0.85 or (mana>=amount*0.85 and bot:GetMana()/math.max(1,bot:GetMaxMana())<0.6)
		or heal+mana>=amount*1.2
	return useful,amount,heal,urgent
end
local function Log(bot,event,name,reason)
	if Config.DEBUG then print(string.format('[BOT][LotusUse] run=%s time=%.3f pid=%s event=%s item=%s reason=%s',
		Config.RUN_ID,DotaTime(),bot:GetPlayerID(),event,tostring(name),reason)) end
end
-- 只读、每入口两秒一次；持有莲花时记录静默门，不能靠缺少requested猜测原因。
function M.Observe(bot,reason,stage)
	if not Config.DEBUG or not bot or bot:IsNull() then return end
	stage=stage or 'decision'
	local state=diagnostics[bot] or {};diagnostics[bot]=state
	local now=DotaTime()
	if now-(state[stage] or -90)<2 then return end
	state[stage]=now
	local owned=Consumables.GetState(bot)
	local items={}
	for slot=0,8 do
		local item=bot:GetItemInSlot(slot)
		if item and weights[item:GetName()] then
			local useful,amount=Need(bot,item)
			items[#items+1]=string.format('%s:%d:%s:%.2f:%s:%s:%s',item:GetName(),slot,tostring(item:GetCurrentCharges()),
				item:GetCooldownTimeRemaining(),tostring(item:IsFullyCastable()),tostring(amount),tostring(useful))
		end
	end
	local has=#items>0 or (owned and owned.requester==REQUESTER) or false
	if not has and state[stage..'HadItem']==false then return end
	state[stage..'HadItem']=has
	print(string.format('[BOT][LotusUseGate] run=%s time=%.3f pid=%s stage=%s reason=%s items=%s hp=%s max_hp=%s mana=%s max_mana=%s action=%s queued=%d owner=%s cast_pending=%s restore_pending=%s deadline=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),stage,reason,#items>0 and table.concat(items,'|') or 'none',
		tostring(bot:GetHealth()),tostring(bot:GetMaxHealth()),tostring(bot:GetMana()),tostring(bot:GetMaxMana()),tostring(bot:GetCurrentActionType()),bot:NumQueuedActions(),
		tostring(owned and owned.requester),tostring(owned and owned.castIssuedTime~=nil),tostring(owned and owned.restorePending),tostring(owned and owned.deadline)))
end
function M.Think(bot)
	local state=Consumables.GetState(bot)
	if state and state.requester~=REQUESTER then M.Observe(bot,'other_inventory_owner');return false end
	if not Config.MAP_RESOURCES_ENABLED then
		M.Observe(bot,'feature_disabled')
		if state then Consumables.Release(bot,REQUESTER,'feature_disabled') end
		return false
	end
	if not bot:IsAlive() then bot.THD_LotusCast=nil;M.Observe(bot,'dead');return state~=nil end
	local pending=state and Consumables.PollCastConfirmation(bot,REQUESTER)
	if pending=='cast_confirm_wait' then M.Observe(bot,'inventory_cast_confirm_wait');return true end
	if not pending and (J.CanNotUseAction(bot) or Actions.Protected(bot)) then M.Observe(bot,'action_protected');return state~=nil end
	if not pending and bot:NumQueuedActions()>0 then M.Observe(bot,'queued_action');return state~=nil end
	if state then
		local name=state.itemName
		local owned,status=true,pending
		if not pending then owned,status=Consumables.Think(bot) end
		M.Observe(bot,'inventory_'..tostring(status))
		if status=='cast_confirmed' then
			bot.THD_LotusCast=nil
			Log(bot,'consumption_confirmed',name,'charges_cooldown_or_item_changed')
			local before=state.lotusBefore
			if before and Config.DEBUG then
				print(string.format('[BOT][LotusUseRecovery] run=%s time=%.3f pid=%s item=%s hp_before=%.1f hp_after=%.1f mana_before=%.1f mana_after=%.1f elapsed=%.3f attribution=observed_delta_only',
					Config.RUN_ID,DotaTime(),bot:GetPlayerID(),name,before.hp,bot:GetHealth(),before.mana,bot:GetMana(),DotaTime()-before.at))
			end
			Consumables.Release(bot,REQUESTER,'cast_issued');nextUse[bot]=DotaTime()+0.5;return true
		elseif status=='cast_unconfirmed' then
			bot.THD_LotusCast=nil
			Log(bot,'released',name,'cast_unconfirmed');Consumables.Release(bot,REQUESTER,'cast_unconfirmed')
			nextUse[bot]=DotaTime()+2;return true
		end
		local item=Consumables.GetReadyItem(bot,name,REQUESTER)
		if item then
			if not Need(bot,item) then Log(bot,'released',name,'no_longer_needed');Consumables.Release(bot,REQUESTER,'no_longer_needed');return true end
			if bot:IsMuted() or bot:IsStunned() or bot:IsHexed() then return true end
			local marked,markReason,confirmUntil=Consumables.MarkCastIssued(bot,REQUESTER)
			if marked then
				state.lotusBefore={hp=bot:GetHealth(),mana=bot:GetMana(),at=DotaTime()}
				bot.THD_LotusCast={health=bot:GetHealth(),untilAt=confirmUntil}
				bot:Action_UseAbility(item);Actions.NoteIssued(bot,'item',item);Actions.Protect(bot,item,0.25)
				Log(bot,'issued',name,'self_restore')
			else Log(bot,'blocked',name,'mark_cast_'..tostring(markReason)) end
		end
		return owned
	end
	if DotaTime()<(nextUse[bot] or -90) or bot:IsMuted() or bot:IsStunned() or bot:IsHexed()
		or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility() then M.Observe(bot,'retry_or_cast_unavailable');return false end
	local chosen,chosenAmount,chosenHeal,emergency
	for slot=0,8 do
		local item=bot:GetItemInSlot(slot)
		if item and weights[item:GetName()] and item:GetCurrentCharges()>0 and item:GetCooldownTimeRemaining()<=0 then
			local useful,amount,heal,urgent=Need(bot,item)
			if useful and (slot>=6 or item:IsFullyCastable()) then
				-- 危急时优先有效回血量；平时优先小剂量，减少溢出。
				if not chosen or (urgent and not emergency) or (urgent==emergency and
					((urgent and heal>chosenHeal) or (heal==chosenHeal and amount<chosenAmount) or (not urgent and amount<chosenAmount))) then
					chosen,chosenAmount,chosenHeal,emergency=item,amount,heal,urgent
				end
			end
		end
	end
	if not chosen then M.Observe(bot,'no_eligible_item');return false end
	local accepted=Consumables.Request(bot,chosen:GetName(),REQUESTER,emergency and 45 or 25,DotaTime()+12,{kind='none'})
	if accepted then Log(bot,'requested',chosen:GetName(),emergency and 'low_health' or 'effective_restore')
	else M.Observe(bot,'inventory_request_rejected') end
	return accepted
end
-- 多个真实英雄入口共用同一帧决策，避免技能入口和中立物品入口重复交换/施放。
function M.SharedThink(bot)
	if not bot or bot~=GetBot() or not bot:IsAlive() or bot:IsIllusion() then return false end
	local now=DotaTime()
	if bot.THD_LotusSharedAt==now then return bot.THD_LotusSharedOwned==true end
	bot.THD_LotusSharedAt=now
	M.Observe(bot,'hero_shared_entered','dispatch')
	local owned=M.Think(bot)
	bot.THD_LotusSharedOwned=owned==true
	return owned
end
return M
