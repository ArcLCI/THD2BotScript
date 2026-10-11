-- 后手核心的有界站位/跟进任务；原生动态系数仍只负责放行后的战斗积极性。
local Actions = require(GetScriptDirectory() .. '/THDFuncLib/action_intent')
local J = require(GetScriptDirectory() .. '/THDFuncLib/thd_func')
local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/modes/evasive/avoidance_geometry')
local Towers = require(GetScriptDirectory() .. '/THDFuncLib/modes/shared/tower_safety')
local Skill = require(GetScriptDirectory() .. '/THDFuncLib/modes/evasive/skill_avoidance')
local CombatPower = require(GetScriptDirectory() .. '/THDFuncLib/combat_power')
local Burst = require(GetScriptDirectory() .. '/THDFuncLib/heroes/tei/tei_burst')
local Coordinator = require(GetScriptDirectory() .. '/THDFuncLib/modes/roam/roam_coordinator')
local G = {}
local RUN = 'TEI-ENGAGE-R8-20261011'
local OWNER = 'tei_engagement'

local function Enemy(bot, unit)
	return Actions.ValidTarget(unit) and unit:IsHero() and unit:GetTeam() ~= bot:GetTeam()
		and not unit:IsInvulnerable() and not unit:IsAttackImmune() and not J.IsSuspiciousIllusion(unit)
end

local function Ally(bot, unit)
	return unit ~= bot and Actions.ValidTarget(unit) and unit:IsHero() and unit:GetTeam() == bot:GetTeam()
		and not J.IsSuspiciousIllusion(unit) and J.GetHP(unit) >= 0.4
end

local function Enemies(bot)
	local result = {}
	for _, unit in pairs(CachedGetNearbyHeroes(bot,1600,true,BOT_MODE_NONE)) do
		if Enemy(bot,unit) then table.insert(result,unit) end
	end
	return result
end

local function Item(bot, name)
	if bot:IsMuted() then return nil end
	for slot=0,5 do
		local item=bot:GetItemInSlot(slot)
		if item and item:GetName()==name and item:IsFullyCastable() then return item end
	end
	return nil
end

local function JumpItem(bot)
	if bot:IsRooted() then return nil end
	return Item(bot,'item_nb9ball') or Item(bot,'item_wanmeitiaoyuezhuangzhi')
end

local function Special(item,name,fallback)
	local value=item:GetSpecialValueFloat(name)
	return value>0 and value or fallback
end

local function Log(bot,state,event,reason)
	local distance=Enemy(bot,state.target) and GetUnitToUnitDistance(bot,state.target) or -1
	local frontDistance=Ally(bot,state.front) and Enemy(bot,state.target) and GetUnitToUnitDistance(state.front,state.target) or -1
	print(string.format('[BOT][TeiEngage] run=%s team=%d player=%d event=%s phase=%s reason=%s front=%s target=%s distance=%.1f front_distance=%.1f goal_x=%s goal_y=%s time=%.3f',
		RUN,bot:GetTeam(),bot:GetPlayerID(),event,state.phase,reason or 'none',
		state.front and not state.front:IsNull() and state.front:GetPlayerID() or -1,tostring(state.target),distance,frontDistance,
		tostring(state.point and state.point.x),tostring(state.point and state.point.y),DotaTime()))
end

-- 全部证据来自Bot可见目标和队友；先手任务只用来优先选人，不把issued当作命中。
function G.Opportunity(bot,target)
	if not Enemy(bot,target) then return {allowed=false,reason='target_invalid'} end
	local old=bot.THD_TeiOpportunity
	if old and old.target==target and DotaTime()-old.at<0.10 then return old end
	local result={at=DotaTime(),target=target,allowed=false,reason='no_front'}
	local enemies=Enemies(bot)
	local mission=Coordinator.GetMission(bot)
	local owner=mission and mission.target==target and mission.initiationOwnerID or nil
	local bestScore=-math.huge
	for _,ally in pairs(CachedGetNearbyHeroes(bot,1600,false,BOT_MODE_NONE)) do
		if Ally(bot,ally) then
			local distance=GetUnitToUnitDistance(ally,target)
			if distance<=1200 then
				local attacking=ally:GetAttackTarget()
				local contact=distance<=math.min(750,bot:GetAttackRange()+100)
				local engaged=contact and ((not ally:IsStunned() and not ally:IsDisarmed() and Enemy(bot,attacking)
					and GetUnitToUnitDistance(ally,attacking)<=ally:GetAttackRange()+100
					and GetUnitToUnitDistance(attacking,target)<=450)
					or target:GetAttackTarget()==ally or ally:WasRecentlyDamagedByHero(target,1.0)
					or target:IsStunned() or target:IsRooted())
				local score=-distance+(ally:GetAttackRange()<=350 and 150 or 0)
					+(ally:GetPlayerID()==owner and 200 or 0)+(engaged and 1000 or 0)
				if score>bestScore then
					bestScore=score;result.front=ally;result.allowed=engaged
					result.reason=engaged and 'front_contact' or 'waiting_front'
				end
			end
		end
	end
	-- 近处单个残血英雄存在保守普攻击杀机会时，不必为了等先手放掉击杀。
	if #enemies==1 and J.GetHP(target)<=0.30 and GetUnitToUnitDistance(bot,target)<=bot:GetAttackRange()+150 then
		local damage=CombatPower.EstimateAttackDamage(bot,target,2.0,1)
		if damage~=nil and damage>=target:GetHealth()*1.1 then
			result.allowed=true;result.solo=true;result.front=nil;result.reason='visible_solo_kill'
		end
	end
	bot.THD_TeiOpportunity=result
	return result
end

local function SafePoint(bot,point,enemies,waiting,front,target)
	local origin=bot:GetLocation()
	local observation=Towers.Observe(bot,'tei_engagement')
	if not point or not observation.available
	or not Geometry.ValidateMovementSegment(origin,point,observation.towers,96)
	or not Geometry.ValidateLocalTerrainSegment(origin,point,true) then return false end
	local hostile=0
	for _,enemy in ipairs(enemies) do
		local distance=Geometry.Distance(point,enemy:GetLocation())
		local minimum=waiting and math.max(800,enemy:GetAttackRange()+150) or 400
		if distance<minimum then return false end
		if distance<=1000 then hostile=hostile+1 end
	end
	if not waiting then
		local allies=1
		for _,unit in pairs(CachedGetNearbyHeroes(bot,1600,false,BOT_MODE_NONE)) do
			if Ally(bot,unit) and Geometry.Distance(point,unit:GetLocation())<=1000 then allies=allies+1 end
		end
		if hostile>allies then return false end
		-- 切入点仍在前排后侧，不能把跟进变成越过先手的贴脸跳跃。
		if Ally(bot,front) and Geometry.Distance(point,target:GetLocation())<GetUnitToUnitDistance(front,target)+75 then return false end
	end
	return true
end

local function Rotate(v,degrees)
	local a=math.rad(degrees)
	return Vector(v.x*math.cos(a)-v.y*math.sin(a),v.x*math.sin(a)+v.y*math.cos(a),0)
end

local function WaitPoint(bot,front,target,enemies)
	if not Ally(bot,front) then return nil end
	local away=(front:GetLocation()-target:GetLocation()):Normalized()
	local best,bestDistance=nil,math.huge
	for _,offset in ipairs({350,450,500}) do
		for _,angle in ipairs({0,30,-30}) do
			local point=front:GetLocation()+Rotate(away,angle)*offset
			local distance=Geometry.Distance(bot:GetLocation(),point)
			if distance<=900 and distance<bestDistance and SafePoint(bot,point,enemies,true,front,target) then best,bestDistance=point,distance end
		end
	end
	return best
end

local function Reachable(bot,target)
	local gap=math.max(0,GetUnitToUnitDistance(bot,target)-bot:GetAttackRange()+50)
	local item=JumpItem(bot)
	return gap<=500 or (item~=nil and gap<=Special(item,'AbilityCastRange',499)-30)
end

local function FollowPoint(bot,target,front,enemies)
	local outputRange=math.max(400,math.min(650,bot:GetAttackRange()-75))
	local away=(bot:GetLocation()-target:GetLocation()):Normalized()
	for _,angle in ipairs({0,25,-25}) do
		local point=target:GetLocation()+Rotate(away,angle)*outputRange
		if SafePoint(bot,point,enemies,false,front,target) then return point end
	end
	return nil
end

local function Stop(bot,state,success,reason)
	if not success and state.issuedMove and bot:GetActiveMode()==BOT_MODE_EVASIVE_MANEUVERS
	and not bot:IsCastingAbility() and not bot:IsUsingAbility() and not bot:IsChanneling() then
		bot:Action_ClearActions(true);Actions.Forget(bot)
	end
	Log(bot,state,success and 'output' or 'release',reason)
	bot.THD_TeiEngagement=nil
	bot.THD_TeiEngagementRetryAt=DotaTime()+(success and 1 or 3)
	if success then
		Burst.RefreshCombat(bot,state.target,true,false)
		bot.THD_TeiBurstReleasedAt=DotaTime()
	else
		bot.THD_TeiCombat,bot.THD_TeiBurstReady=nil,nil
	end
end

function G.Start(bot,target,validate,guaranteedMooncake)
	if bot.THD_TeiEngagement or Burst.IsActive(bot) or Burst.InCombat(bot)
	or DotaTime()<(bot.THD_TeiEngagementRetryAt or -90) or Actions.Protected(bot)
	or Skill.IsActive(bot) or J.IsTowerEscapeActive(bot) or not Enemy(bot,target) then return false end
	local opportunity=G.Opportunity(bot,target)
	if not opportunity.front and not opportunity.solo then return false end
	if not validate(bot,target) then return false end
	local point=WaitPoint(bot,opportunity.front,target,Enemies(bot))
	if not opportunity.allowed and point==nil then return false end
	local state={phase='wait',target=target,front=opportunity.front,point=point,
		validate=validate,guaranteedMooncake=guaranteedMooncake,expires=DotaTime()+2.0}
	bot.THD_TeiEngagement=state
	bot:Action_ClearActions(true);Actions.Forget(bot)
	Log(bot,state,'wait',opportunity.reason)
	return true
end

function G.IsActive(bot) return bot~=nil and bot.THD_TeiEngagement~=nil end

function G.Update(bot)
	local state=bot and bot.THD_TeiEngagement
	if not state then return false end
	if not bot:IsAlive() then Stop(bot,state,false,'dead');return true end
	if Burst.IsActive(bot) then return true end
	local now=DotaTime()
	local pending=state.pendingJump
	if pending then
		if pending.handle==nil or pending.handle:IsNull() then Stop(bot,state,false,'jump_item_lost');return true end
		if pending.handle:IsInAbilityPhase() or pending.handle:IsChanneling() or bot:IsCastingAbility() then return true end
		if pending.handle:GetCooldownTimeRemaining()>pending.cooldown and Geometry.Distance(bot:GetLocation(),pending.origin)>=64 then
			Log(bot,state,'jump_confirmed','position_and_cooldown');state.pendingJump=nil;state.phase='follow'
		elseif now>pending.expires then
			if bot:GetCurrentActiveAbility()==pending.handle then bot:Action_ClearActions(true) end
			Stop(bot,state,false,'jump_unconfirmed');return true
		else return true end
	end
	if now>state.expires then Stop(bot,state,false,state.phase..'_timeout');return true end
	if not Enemy(bot,state.target) or not state.validate(bot,state.target)
	or bot:IsStunned() or bot:IsHexed() or bot:IsDisarmed() or J.Retreat.ShouldYield(bot,J.Retreat.HIGH) then
		Stop(bot,state,false,'target_or_safety_changed');return true
	end
	if bot:GetActiveMode()~=BOT_MODE_EVASIVE_MANEUVERS then return true end
	local opportunity=G.Opportunity(bot,state.target)
	state.front=opportunity.front
	if state.phase=='wait' then
		local behindFront=opportunity.solo or not Ally(bot,state.front)
			or GetUnitToUnitDistance(bot,state.target)>=math.max(400,GetUnitToUnitDistance(state.front,state.target)+250)
		local hasFollowPoint=GetUnitToUnitDistance(bot,state.target)<=bot:GetAttackRange()
			or FollowPoint(bot,state.target,state.front,Enemies(bot))~=nil
		if opportunity.allowed and behindFront and hasFollowPoint and Reachable(bot,state.target) then
			local function ValidatePreparation(unit,target)
				local opening=G.Opportunity(unit,target)
				return state.validate(unit,target) and opening.allowed and Reachable(unit,target)
					and (GetUnitToUnitDistance(unit,target)<=unit:GetAttackRange()
						or FollowPoint(unit,target,opening.front,Enemies(unit))~=nil)
			end
			if Burst.Start(bot,state.target,ValidatePreparation,state.guaranteedMooncake,OWNER) then
				state.phase='prepare';state.expires=now+6.0;Log(bot,state,'prepare',opportunity.reason);return true
			elseif Burst.IsReady(bot) then
				state.phase='follow';state.expires=now+1.8
			else Stop(bot,state,false,'preparation_unavailable');return true end
		else
			local point=WaitPoint(bot,state.front,state.target,Enemies(bot))
			if point==nil then Stop(bot,state,false,'no_safe_backline');return true end
			state.point=point
			if GetUnitToLocationDistance(bot,point)>90 then
				local _,issued=Actions.Move(bot,point,80,'move',false,OWNER)
				state.issuedMove=state.issuedMove or issued
				state.holding=false
			elseif not state.holding then
				bot:Action_ClearActions(true);Actions.Forget(bot);state.holding=true
			end
			return true
		end
	end
	if state.phase=='prepare' then
		if not Burst.IsReady(bot) then Stop(bot,state,false,'preparation_aborted');return true end
		state.phase='follow';state.expires=now+1.8;Log(bot,state,'follow','burst_confirmed')
	end
	if not opportunity.allowed then Stop(bot,state,false,'front_contact_lost');return true end
	if state.phase=='attack_confirm' then
		if bot:GetAttackTarget()==state.target and bot:GetCurrentActionType()==BOT_ACTION_TYPE_ATTACK then
			Stop(bot,state,true,'attack_accepted')
		end
		return true
	end
	local distance=GetUnitToUnitDistance(bot,state.target)
	if distance<=bot:GetAttackRange() then
		local accepted,issued=Actions.Attack(bot,state.target,false,OWNER)
		if accepted then state.phase='attack_confirm';state.expires=now+0.35;Log(bot,state,'attack',issued and 'issued' or 'already_attacking') end
		return true
	end
	local item=JumpItem(bot)
	local enemies=Enemies(bot)
	local landing=FollowPoint(bot,state.target,state.front,enemies)
	if landing==nil then Stop(bot,state,false,'no_follow_landing');return true end
	state.point=landing
	local travel=GetUnitToLocationDistance(bot,landing)
	local window=Burst.TimeRemaining(bot)
	if item and travel>200 and travel<=Special(item,'AbilityCastRange',499)-30 and window>0.6+bot:GetAttackPoint() then
		state.pendingJump={handle=item,cooldown=item:GetCooldownTimeRemaining(),origin=bot:GetLocation(),expires=now+item:GetCastPoint()+0.8}
		state.phase='jump';state.expires=now+1.8
		bot:Action_UseAbilityOnLocation(item,landing);Actions.NoteIssued(bot,'tei_follow_jump',nil,landing)
		Log(bot,state,'jump','safe_landing');return true
	end
	local needed=math.max(0,distance-bot:GetAttackRange()+30)/math.max(1,bot:GetCurrentMovementSpeed())+bot:GetAttackPoint()+0.35
	if bot:IsRooted() or travel>500 or needed>=window or needed>state.expires-now then Stop(bot,state,false,'insufficient_follow_window');return true end
	local _,issued=Actions.Move(bot,landing,60,'move',false,OWNER)
	state.issuedMove=state.issuedMove or issued
	return true
end

function G.GetDesire(bot)
	local state=bot and bot.THD_TeiEngagement
	if not state then return BOT_MODE_DESIRE_NONE end
	if not bot:IsAlive() then Stop(bot,state,false,'dead');return BOT_MODE_DESIRE_NONE end
	if DotaTime()>state.expires and not state.pendingJump and not Burst.IsActive(bot) then
		Stop(bot,state,false,state.phase..'_timeout');return BOT_MODE_DESIRE_NONE
	end
	-- 仅为有目标且有安全站位/接敌动作的短任务保留余量，避免动态Attack抢回未完成步骤。
	return BOT_MODE_DESIRE_ABSOLUTE+0.01
end

function G.OnEnd(bot)
	local state=bot and bot.THD_TeiEngagement
	if not state then return false end
	if Burst.IsActive(bot) or state.pendingJump then return true end
	Stop(bot,state,false,'mode_lost');return true
end

return G
