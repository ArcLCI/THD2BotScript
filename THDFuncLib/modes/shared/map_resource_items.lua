-- 疗伤莲花系列：名称/恢复值来自7.38原生KV，实际决策读取当前物品特殊值。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Consumables=require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Actor=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/actor_diagnostics')
local M={}
local weights={item_famango=1,item_great_famango=3,item_greater_famango=6}
local usable={item_famango='lotus',item_great_famango='lotus',item_greater_famango='lotus',
	item_cheese='cheese',item_magic_mushroom='mango',item_roshans_banner='banner'}
local REQUESTER='map_resource_lotus_use'
local nextUse=setmetatable({}, {__mode='k'})
local failedUses=setmetatable({}, {__mode='k'})
local diagnostics=setmetatable({}, {__mode='k'})
local pendingReceipts=setmetatable({}, {__mode='k'})
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
local function BannerPoint(bot,item)
	local mode=bot:GetActiveMode()
	if mode~=BOT_MODE_PUSH_TOWER_TOP and mode~=BOT_MODE_PUSH_TOWER_MID and mode~=BOT_MODE_PUSH_TOWER_BOT then return nil end
	if DotaTime()<(bot.THD_BannerUntil or -90) or bot:WasRecentlyDamagedByAnyHero(2)
		or #J.GetNearbyHeroes(bot,1200,true,BOT_MODE_NONE)>0 then return nil end
	local creeps=bot:GetNearbyLaneCreeps(900,false)
	local count,point=0,nil
	for _,creep in ipairs(creeps) do
		if creep and not creep:IsNull() and creep:CanBeSeen() and creep:IsAlive() and not creep:HasModifier('modifier_roshans_banner_effect') then
			local location=creep:GetLocation()
			if not point then point=location end
			if J.GetDistance(point,location)<=400 then count=count+1 end
		end
	end
	if count<2 or not point or not IsLocationVisible(point) or not IsLocationPassable(point)
		or GetUnitToLocationDistance(bot,point)>item:GetCastRange() then return nil end
	return point
end
local function Need(bot,item)
	local kind=usable[item:GetName()]
	if kind=='banner' then local point=BannerPoint(bot,item);return point~=nil,0,0,false,point end
	local hp=math.max(0,bot:GetMaxHealth()-bot:GetHealth())
	local mp=math.max(0,bot:GetMaxMana()-bot:GetMana())
	if kind=='mango' then
		local mana=item:GetSpecialValueInt('regen_mana')
		return mana>0 and mp>=mana*0.8 and bot:GetMana()/math.max(1,bot:GetMaxMana())<0.8,mana,0,false
	end
	if kind=='cheese' then
		local h,m=item:GetSpecialValueInt('health_restore'),item:GetSpecialValueInt('mana_restore')
		local heal,mana=math.min(hp,h),math.min(mp,m)
		local urgent=J.GetHP(bot)<0.4 and heal>=math.min(500,h*0.35)
		return h>0 and (urgent or heal>=h*0.65 or heal/math.max(1,h)+mana/math.max(1,m)>=1),h+m,heal,urgent
	end
	local amount=item:GetSpecialValueInt('replenish_amount')
	if amount<=0 then return false,0,0,false end
	local heal,mana=math.min(hp,amount),math.min(mp,amount)
	local urgent=bot:GetHealth()/math.max(1,bot:GetMaxHealth())<0.4 and heal>=math.min(100,amount*0.5)
	local useful=urgent or heal>=amount*0.85 or (mana>=amount*0.85 and bot:GetMana()/math.max(1,bot:GetMaxMana())<0.6)
		or heal+mana>=amount*1.2
	return useful,amount,heal,urgent
end
local Acceptance=require(GetScriptDirectory()..'/THDFuncLib/acceptance_observer')
local function Log(bot,event,name,reason)
	Acceptance.ResourceStage(bot,event,name,Consumables.GetState(bot)) -- 仅串联诊断阶段，不参与决策。
	if Config.DEBUG then print(string.format('[BOT][%s] run=%s time=%.3f pid=%s event=%s item=%s reason=%s',
		weights[name] and 'LotusUse' or 'ResourceUse',Config.RUN_ID,DotaTime(),bot:GetPlayerID(),event,tostring(name),reason)..Actor.Fields(bot)) end
end
local function ForgetReceipt(bot,state)
	local records=pendingReceipts[bot] or {}
	for i=#records,1,-1 do if records[i].state==state then table.remove(records,i) end end
end
local function TrackReceipt(bot,state,item)
	ForgetReceipt(bot,state)
	local records=pendingReceipts[bot] or {};pendingReceipts[bot]=records
	if #records>=8 then table.remove(records,1) end
	records[#records+1]={state=state,item=item,name=state.itemName,charges=state.castIssuedCharges,
		cooldown=state.castIssuedCooldown,untilAt=DotaTime()+3}
end
local function PollReleasedReceipts(bot,state)
	local records=pendingReceipts[bot] or {}
	for i=#records,1,-1 do
		local record=records[i]
		if state~=record.state or record.state.restorePending then
			-- 原租约先结束也不能丢弃已发单快照；仅核对原物品，不以同名另一个堆叠替代。
			local consumed=record.item:IsNull()
			if not consumed then
				local owned=false
				for slot=0,8 do if bot:GetItemInSlot(slot)==record.item then owned=true;break end end
				consumed=owned and ((record.charges and record.item:GetCurrentCharges()<record.charges)
					or (record.cooldown and record.item:GetCooldownTimeRemaining()>record.cooldown+0.05))
			end
			if DotaTime()<=record.untilAt and consumed then
				Log(bot,'consumption_confirmed',record.name,'late_inventory_after_lifecycle_end')
				if failedUses[bot] then failedUses[bot][record.name]=nil end
				table.remove(records,i)
			elseif DotaTime()>=record.untilAt then
				Log(bot,'confirmation_expired',record.name,'lifecycle_ended_without_receipt');table.remove(records,i)
			end
		elseif DotaTime()>record.untilAt then table.remove(records,i) end
	end
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
		if item and usable[item:GetName()] then
			local useful,amount=Need(bot,item)
			items[#items+1]=string.format('%s:%d:%s:%.2f:%s:%s:%s',item:GetName(),slot,tostring(item:GetCurrentCharges()),
				item:GetCooldownTimeRemaining(),tostring(item:IsFullyCastable()),tostring(amount),tostring(useful))
		end
	end
	local has=#items>0 or (owned and owned.requester==REQUESTER) or false
	if not has and state[stage..'HadItem']==false then return end
	state[stage..'HadItem']=has
	print(string.format('[BOT][LotusUseGate] run=%s time=%.3f pid=%s stage=%s reason=%s items=%s hp=%s max_hp=%s mana=%s max_mana=%s action=%s queued=%d owner=%s cast_pending=%s restore_pending=%s deadline=%s backpack_ready_at=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),stage,reason,#items>0 and table.concat(items,'|') or 'none',
		tostring(bot:GetHealth()),tostring(bot:GetMaxHealth()),tostring(bot:GetMana()),tostring(bot:GetMaxMana()),tostring(bot:GetCurrentActionType()),bot:NumQueuedActions(),
		tostring(owned and owned.requester),tostring(owned and owned.castIssuedTime~=nil),tostring(owned and owned.restorePending),tostring(owned and owned.deadline),tostring(owned and owned.backpackReadyAt)))
end
function M.Think(bot)
	Consumables.ObserveInventory(bot)
	local state=Consumables.GetState(bot)
	PollReleasedReceipts(bot,state)
	if state and state.requester~=REQUESTER then M.Observe(bot,'other_inventory_owner');return false end
	if not Config.MAP_RESOURCES_ENABLED then
		M.Observe(bot,'feature_disabled')
		if state then Consumables.Release(bot,REQUESTER,'feature_disabled') end
		return false
	end
	-- 发单后的库存证据优先于死亡归类；死亡不代表此前瞬发消耗品没有生效。
	local pending=state and Consumables.PollCastConfirmation(bot,REQUESTER)
	if not bot:IsAlive() and pending~='cast_confirmed' then
		bot.THD_LotusCast=nil;if state then Consumables.Release(bot,REQUESTER,'dead') end
		M.Observe(bot,'dead');return state~=nil
	end
	-- 死亡期间可能没有物品回调；用自身死亡计数识别复活后的旧请求，避免误记施放失败。
	if state and pending~='cast_confirmed' and not state.restorePending and state.resourceDeaths and GetHeroDeaths(bot:GetPlayerID())~=state.resourceDeaths then
		bot.THD_LotusCast=nil;Log(bot,'released',state.itemName,'death_interrupted')
		Consumables.Release(bot,REQUESTER,'dead');return true
	end
	if pending=='cast_confirm_wait' then M.Observe(bot,'inventory_cast_confirm_wait');return true end
	if not pending and (J.CanNotUseAction(bot) or Actions.Protected(bot)) then M.Observe(bot,'action_protected');return state~=nil end
	if not pending and bot:NumQueuedActions()>0 then M.Observe(bot,'queued_action');return state~=nil end
	if state then
		local name=state.itemName
		local owned,status=true,pending
		if not pending then owned,status=Consumables.Think(bot) end
		M.Observe(bot,'inventory_'..tostring(status))
		if status=='cast_confirmed' then
			ForgetReceipt(bot,state)
			if failedUses[bot] then failedUses[bot][name]=nil end
			bot.THD_LotusCast=nil
			Log(bot,'consumption_confirmed',name,'charges_cooldown_or_item_changed')
			if usable[name]=='banner' then bot.THD_BannerUntil=DotaTime()+(state.bannerDuration or 120) end
			local before=state.lotusBefore
			if before and Config.DEBUG and usable[name]~='banner' then
				print(string.format('[BOT][%s] run=%s time=%.3f pid=%s item=%s hp_before=%.1f hp_after=%.1f mana_before=%.1f mana_after=%.1f elapsed=%.3f attribution=observed_delta_only',
					weights[name] and 'LotusUseRecovery' or 'ResourceUseRecovery',Config.RUN_ID,DotaTime(),bot:GetPlayerID(),name,before.hp,bot:GetHealth(),before.mana,bot:GetMana(),DotaTime()-before.at))
			end
			Consumables.Release(bot,REQUESTER,'cast_issued');nextUse[bot]=DotaTime()+0.5;return true
		elseif status=='cast_unconfirmed' then
			bot.THD_LotusCast=nil
			local retryItem=Consumables.GetReadyItem(bot,name,REQUESTER)
			-- 恢复品/战旗仅在原租约内补发一次，不恢复槽位再重建换入循环。
			if usable[name] and not state.resourceRetried and DotaTime()<state.deadline-1.5
			and retryItem and Need(bot,retryItem) and not J.CanNotUseAction(bot)
			and not Actions.Protected(bot) and bot:NumQueuedActions()==0 then
				state.resourceRetried=true;state.resourceRetryAt=DotaTime()+0.25
				Log(bot,'retry_scheduled',name,'same_lease_once')
			else
				failedUses[bot]=failedUses[bot] or {}
				local previous=failedUses[bot][name]
				local count=math.min(4,(previous and previous.count or 0)+1)
				failedUses[bot][name]={count=count,untilAt=DotaTime()+math.min(32,8*count)}
				Log(bot,'released',name,'cast_unconfirmed');Consumables.Release(bot,REQUESTER,'cast_unconfirmed')
				nextUse[bot]=DotaTime()+2;return true
			end
		end
		local item=Consumables.GetReadyItem(bot,name,REQUESTER)
		if item then
			if DotaTime()<(state.resourceRetryAt or -90) then return true end
			local useful,_,_,_,point=Need(bot,item)
			if not useful then Log(bot,'released',name,'no_longer_needed');Consumables.Release(bot,REQUESTER,'no_longer_needed');return true end
			if bot:IsMuted() or bot:IsStunned() or bot:IsHexed() or Actions.Protected(bot) or J.CanNotUseAction(bot) or bot:NumQueuedActions()>0 then return true end
			local marked,markReason,confirmUntil=Consumables.MarkCastIssued(bot,REQUESTER)
			if marked then
				state.lotusBefore={hp=bot:GetHealth(),mana=bot:GetMana(),at=DotaTime()}
				TrackReceipt(bot,state,item)
				bot.THD_LotusCast={health=bot:GetHealth(),untilAt=confirmUntil}
				if usable[name]=='banner' then
					state.bannerDuration=item:GetSpecialValueInt('duration');bot:Action_UseAbilityOnLocation(item,point)
				else bot:Action_UseAbility(item) end
				Actions.NoteIssued(bot,'item',item,point);Actions.Protect(bot,item,0.25)
				Log(bot,'issued',name,point and 'support_push_wave' or 'self_restore')
				if Config.DEBUG then
					print(string.format('[BOT][ResourceCast] run=%s time=%.3f pid=%s item=%s retry=%s charges=%s action=%s queued=%s ready_at=%s deadline=%s',
						Config.RUN_ID,DotaTime(),bot:GetPlayerID(),name,tostring(state.resourceRetried==true),tostring(state.castIssuedCharges),
						bot:GetCurrentActionType(),bot:NumQueuedActions(),tostring(state.backpackReadyAt),tostring(state.deadline)))
				end
			else Log(bot,'blocked',name,'mark_cast_'..tostring(markReason)) end
		end
		return owned
	end
	if DotaTime()<(nextUse[bot] or -90) or bot:IsMuted() or bot:IsStunned() or bot:IsHexed()
		or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility() then M.Observe(bot,'retry_or_cast_unavailable');return false end
	local chosen,chosenAmount,chosenHeal,emergency,chosenPoint
	for slot=0,8 do
		local item=bot:GetItemInSlot(slot)
		local failed=item and failedUses[bot] and failedUses[bot][item:GetName()]
		if item and usable[item:GetName()] and (not failed or DotaTime()>=failed.untilAt)
		and (usable[item:GetName()]=='banner' or item:GetCurrentCharges()>0) and item:GetCooldownTimeRemaining()<=0 then
			local useful,amount,heal,urgent,point=Need(bot,item)
			if useful and (slot>=6 or item:IsFullyCastable()) then
				-- 危急时优先有效回血量；平时优先小剂量，减少溢出。
				if not chosen or (urgent and not emergency) or (urgent==emergency and
					((urgent and heal>chosenHeal) or (heal==chosenHeal and amount<chosenAmount) or (not urgent and amount<chosenAmount))) then
					chosen,chosenAmount,chosenHeal,emergency,chosenPoint=item,amount,heal,urgent,point
				end
			end
		end
	end
	if not chosen then M.Observe(bot,'no_eligible_item');return false end
	local accepted=Consumables.Request(bot,chosen:GetName(),REQUESTER,emergency and 45 or 25,DotaTime()+15,chosenPoint and {kind='location',location=chosenPoint} or {kind='none'})
	if accepted then
		local owned=Consumables.GetState(bot)
		if owned and owned.requester==REQUESTER then owned.resourceDeaths=GetHeroDeaths(bot:GetPlayerID()) end
		Log(bot,'requested',chosen:GetName(),emergency and 'low_health' or 'effective_restore')
	else M.Observe(bot,'inventory_request_rejected') end
	return accepted
end
-- 多个真实英雄入口共用同一帧决策，避免技能入口和中立物品入口重复交换/施放。
function M.SharedThink(bot)
	if not bot or bot~=GetBot() or bot:IsIllusion() then return false end
	if not bot:IsAlive() then
		local state=Consumables.GetState(bot)
		if state and state.requester==REQUESTER then
			return M.Think(bot)
		end
		return false
	end
	local now=DotaTime()
	if bot.THD_LotusSharedAt==now then return bot.THD_LotusSharedOwned==true end
	bot.THD_LotusSharedAt=now
	M.Observe(bot,'hero_shared_entered','dispatch')
	local owned=M.Think(bot)
	bot.THD_LotusSharedOwned=owned==true
	return owned
end
return M
