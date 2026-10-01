-- ROAM 的低优先级局部后备；不攻击建筑、不追英雄、不借用共享推进授权。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Tasks=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/mode_task')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Strategy=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/wasteland_strategy')
local Towers=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/tower_safety')
local Geometry=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Consumables=require(GetScriptDirectory()..'/THDFuncLib/consumable_inventory')
local LocalRoutes=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/local_route_candidates')
local F={}
local function State(bot,basicLane)
	if basicLane then
		bot.THD_BasicLaneStates=bot.THD_BasicLaneStates or {}
		bot.THD_BasicLaneStates[basicLane]=bot.THD_BasicLaneStates[basicLane] or {nextSearch=-90,generation=0}
		return bot.THD_BasicLaneStates[basicLane]
	end
	bot.THD_LocalLaneFallback=bot.THD_LocalLaneFallback or {nextSearch=-90,generation=0}
	return bot.THD_LocalLaneFallback
end
local function Copy(p) return Vector(p.x,p.y,p.z) end
local function LogJourney(bot,task,event)
	if not Config.DEBUG or not task or not task.finalGoal then return end
	local state,now=State(bot,task.basicLane),DotaTime()
	if event=='advance' and state.journeyLogKey==task.key and now-(state.journeyLogAt or -90)<2 then return end
	state.journeyLogKey,state.journeyLogAt=task.key,now
	print(string.format('[BOT][LocalJourney] run=%s time=%.3f pid=%s key=%s event=%s lane=%s reason=%s x=%.1f y=%.1f waypoint_x=%.1f waypoint_y=%.1f final_x=%.1f final_y=%.1f remaining=%.1f deadline=%.3f',
		Config.RUN_ID,now,bot:GetPlayerID(),tostring(task.key),event,tostring(task.lane),task.reason,
		bot:GetLocation().x,bot:GetLocation().y,task.location.x,task.location.y,task.finalGoal.x,task.finalGoal.y,
		GetUnitToLocationDistance(bot,task.finalGoal),task.deadline))
end
local function IsEgress(reason) return reason=='egress_from_excluded_base' or reason=='egress_from_tower_zone' or reason=='local_recovery_connector' end
local function IsConnector(reason) return reason=='base_lane_connector' or reason=='base_return_connector' or reason=='safe_return_connector' or reason=='local_recovery_connector' end
local function IsBaseReturn(reason) return reason=='base_return' or reason=='base_return_connector' or reason=='safe_return' or reason=='safe_return_connector' or reason=='safe_regroup' end
local function NearOwnBase(bot)
	local ancient=GetAncient(GetTeam())
	return ancient and not ancient:IsNull() and GetUnitToUnitDistance(bot,ancient)<=3200
end
function F.NeedsExitPlan(bot)
	local ancient=GetAncient(GetOpposingTeam())
	return ancient and not ancient:IsNull() and GetUnitToUnitDistance(bot,ancient)<3600
end
function F.Desire(task)
	if not task then return 0 end
	return (task.reason=='safe_return' or task.reason=='safe_return_connector' or task.reason=='safe_regroup')
		and Config.SAFE_RETURN_DESIRE or Config.FALLBACK_DESIRE
end
function F.RecentRouteFailure(bot,point)
	if not point then return false end
	for _,failed in ipairs(bot.THD_LocalFailedRoutes or {}) do
		if DotaTime()<failed.untilAt and Geometry.Distance(bot:GetLocation(),failed.origin)<128
		and Geometry.Distance(point,failed.goal)<96 then return true,failed.reason end
	end
	return false
end
local function Eligible(bot,basicLane)
	if not (basicLane and Config.BasicLaneEnabled() or not basicLane and Config.FallbackEnabled())
	or not bot:IsAlive() or bot:IsIllusion() then return false,'disabled_or_invalid' end
	if Actions.Protected(bot) or J.CanNotUseAction(bot) or Consumables.GetState(bot)~=nil then return false,'protected_or_inventory' end
	if J.Retreat.ShouldYield(bot,J.Retreat.HIGH) or J.IsRoshanCommitmentActive(bot) then return false,'retreat_or_roshan' end
	if bot:WasRecentlyDamagedByAnyHero(2) then return false,'recent_danger' end
	local egressOnly=J.GetHP(bot)<0.55 or bot:WasRecentlyDamagedByTower(2)
	if Tasks.HasOtherExecution(bot,basicLane and 'push_'..basicLane or 'roam') then return false,'other_execution' end
	local mode=bot:GetActiveMode()
	if bot:GetActiveModeDesire()>0 and (mode==BOT_MODE_ATTACK or mode==BOT_MODE_RETREAT
		or mode==BOT_MODE_EVASIVE_MANEUVERS or mode==BOT_MODE_TEAM_ROAM
		or mode==BOT_MODE_DEFEND_TOWER_TOP or mode==BOT_MODE_DEFEND_TOWER_MID or mode==BOT_MODE_DEFEND_TOWER_BOT
		or mode==BOT_MODE_RUNE or mode==BOT_MODE_OUTPOST) then return false,'other_active_mode' end
	local base=Strategy.GetBaseThreatSnapshot(nil,bot)
	-- 告急只允许回防移动；真正已有控制权的防守/战斗在前面的模式门让行。
	if base and base.hardEmergency then
		if basicLane then return false,'base_emergency' end
		return true,'base_return_only'
	end
	return true,egressOnly and 'egress_only' or nil
end
local function InLane(unit,lane)
	if not Actions.ValidTarget(unit) then return false end
	local name=unit:GetUnitName()
	if not (string.find(name,'^npc_dota_creep_') or string.find(name,'^npc_dota_.*siege')
		or string.find(name,'^npc_thd_goodguys_') or string.find(name,'^npc_thd_badguys_')) then return false end
	local location=unit:GetLocation()
	local along=GetAmountAlongLane(lane,location)
	if along.distance>900 then return false end
	for _,other in ipairs({LANE_TOP,LANE_MID,LANE_BOT}) do
		if other~=lane and GetAmountAlongLane(other,location).distance+50<along.distance then return false end
	end
	return true
end
local function Safe(bot,location,egress,connector,basicLane,task,from)
	if not location or GetUnitToLocationDistance(bot,location)>1000 then return false,'beyond_local_range' end
	local observation=Towers.Observe(bot,'local_lane_fallback')
	if not observation.available then return false,'tower_snapshot_unavailable' end
	local origin=from or bot:GetLocation()
	-- 禁止进入基地，但允许已在圈内的无任务英雄单调向外归位；不给攻击授权。
	local ancient=GetAncient(GetOpposingTeam())
	if ancient and not ancient:IsNull() and Geometry.SegmentDistanceToPoint(origin,location,ancient:GetLocation())<3600 then
		local center=ancient:GetLocation()
		local delta=location-origin
		local away=origin-center
		-- 48距离是整步准入进展；执行末段用原起点核验，仍要求当前余段单调向外。
		local progressOrigin=origin
		if task and not task.target and task.startLocation and DotaTime()<task.deadline
		and Geometry.Distance(location,task.location)<1
		and Geometry.SegmentDistanceToPoint(task.startLocation,location,origin)<=64
		and Geometry.Distance(origin,location)<=Geometry.Distance(task.startLocation,location)+32 then
			progressOrigin=task.startLocation
		end
		if not egress or Geometry.Distance(origin,center)>=3600
		or away.x*delta.x+away.y*delta.y<0
		or Geometry.Distance(location,center)<Geometry.Distance(progressOrigin,center)+48 then
			return false,'enemy_base_excluded'
		end
	end
	local allowed,reason
	-- 已在危险圈内可以分段向外，不要求750内一步跨出整个联合塔区。
	if egress then allowed,reason=Geometry.ValidateRecoverySegment(origin,location,observation.towers,96)
	else allowed,reason=Geometry.ValidateMovementSegment(origin,location,observation.towers,96) end
	if not allowed then return false,'tower_'..tostring(reason) end
	local state=State(bot,basicLane)
	for _,point in ipairs(state.enemies or {}) do
		if Geometry.SegmentDistanceToPoint(origin,location,point)<1200 then return false,'enemy_near_segment' end
	end
	local distance=Geometry.Distance(origin,location)
	local originPassable=IsLocationPassable(origin)
	local recoverOrigin=connector and distance<=240 and not originPassable
	local count=math.max(1,math.ceil(distance/(connector and 32 or 180)))
	local reachedPassable=originPassable
	-- 英雄可能已站在阻挡边缘；退出仍检查后续线段，不因起点不可通行锁死。
	for index=egress and 1 or 0,count do
		local point=origin+(location-origin)*(index/count)
		local detail={point=Copy(point),index=index,count=count,originPassable=originPassable}
		if not IsLocationVisible(point) then return false,'unseen_segment',detail end
		local passable=IsLocationPassable(point)
		-- 有界连接可离开最多96距离的连续起点阻挡边缘；进入可行区后禁止再穿阻挡。
		if not passable and not (recoverOrigin and not reachedPassable and distance*index/count<=96 and index<count) then
			return false,'impassable_segment',detail
		end
		if passable then reachedPassable=true end
	end
	return true
end
local Snapshot
local function Validate(bot,task,selecting)
	if task.basicLane and not selecting and task.basicLane~=F.GetLane(bot) then return false,'basic_lane_changed' end
	local eligible,reason=Eligible(bot,task.basicLane)
	if not eligible then return false,reason end
	if task.intent=='wait' and (reason~=nil or not NearOwnBase(bot)
		or GetUnitToLocationDistance(bot,task.location)>48) then return false,'regroup_conditions_changed' end
	if reason=='egress_only' and not IsEgress(task.reason) then return false,'recent_danger' end
	if reason=='base_return_only' and not IsBaseReturn(task.reason)
	and not (F.NeedsExitPlan(bot) and IsEgress(task.reason)) then return false,'base_emergency_replan' end
	if DotaTime()>=task.deadline then return false,'deadline' end
	if task.waveTarget and not Actions.ValidTarget(task.waveTarget) then return false,'wave_target_lost' end
	if task.target and (not InLane(task.target,task.lane) or not J.CanBeAttacked(task.target)) then return false,'target_lost' end
	State(bot,task.basicLane).enemies=Snapshot(bot).enemies
	return Safe(bot,task.target and task.target:GetLocation() or task.location,IsEgress(task.reason) and not task.target,IsConnector(task.reason),task.basicLane,task)
end
function F.GetLane(bot)
	local choice=bot.THD_BasicLaneChoice
	return choice and choice.lane
end
Snapshot=function(bot)
	local sample=bot.THD_LocalLanePerception
	if sample and DotaTime()-sample.at<Config.FALLBACK_INTERVAL then return sample end
	sample={at=DotaTime(),enemies={},enemyCreeps=bot:GetNearbyLaneCreeps(1000,true),alliedCreeps=bot:GetNearbyLaneCreeps(1000,false)}
	for _,id in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local seen=GetHeroLastSeenInfo(id);seen=seen and seen[1]
			if seen and seen.time_since_seen<5 then sample.enemies[#sample.enemies+1]=seen.location end
		end
	end
	bot.THD_LocalLanePerception=sample
	return sample
end
local function PrepareScope(bot,basicLane,limit)
	local state,now=State(bot,basicLane),DotaTime()
	local eligible,reason=Eligible(bot,basicLane)
	if not eligible then
		if reason=='other_execution' or reason=='other_active_mode' then state.noLaneSince=nil end
		return nil,reason,state.nextSearch
	end
	if not basicLane and F.FinishRecoveryStep(bot) then
		-- 先复核已提交的安全恢复步，再考虑新推进候选；只刷新候选副本的新鲜度。
		local running=Tasks.Active(bot,'roam')
		local plan={};for key,value in pairs(running) do plan[key]=value end
		plan.preparedAt,plan.validUntil=now,math.min(now+Config.CANDIDATE_TTL,plan.deadline)
		return plan
	end
	local egressOnly=reason=='egress_only'
	local baseReturnOnly=reason=='base_return_only'
	local enemyAncient=GetAncient(GetOpposingTeam())
	local insideEnemyBase=enemyAncient and not enemyAncient:IsNull() and GetUnitToUnitDistance(bot,enemyAncient)<3600
	local observed=Towers.Observe(bot,'local_lane_fallback')
	local insideTower=false
	for _,zone in ipairs(observed.towers or {}) do if Geometry.PointInCircle(bot:GetLocation(),zone,96) then insideTower=true;break end end
	-- 同一兵线任务只有一个模式持有；Roam仅保留回防、退让和基地脱困。
	local recoveryNeeded=baseReturnOnly or egressOnly or insideEnemyBase or insideTower
		or not IsLocationPassable(bot:GetLocation())
		or (not basicLane and state.task
			and now<state.task.deadline and GetUnitToLocationDistance(bot,state.task.location)>(state.task.tolerance or 120)
			and IsConnector(state.task.reason))
	if not recoveryNeeded then state.recovery=nil end
	local safeReturnOnly=false
	-- 最终目标尚未完成时沿用同一行程，不因一个路点到位重新决定进兵还是回家。
	if state.task and state.task.finalGoal and now<state.task.deadline
	and GetUnitToLocationDistance(bot,state.task.finalGoal)>120 then
		local valid=Validate(bot,state.task,basicLane~=nil)
		if valid then
			local task={};for k,v in pairs(state.task) do task[k]=v end
			task.preparedAt,task.validUntil=now,math.min(now+Config.CANDIDATE_TTL,task.deadline)
			return task
		end
	end
	if Config.BasicLaneEnabled() then
		if basicLane and recoveryNeeded then return nil,'recovery_required',now+Config.FALLBACK_INTERVAL end
		if not basicLane and not recoveryNeeded then
			local choice=F.Select(bot)
			if choice.plan then state.noLaneSince=nil;return nil,'basic_lane_admissible',choice.untilAt end
			state.noLaneSince=state.noLaneSince or now
			if now-state.noLaneSince<Config.SAFE_RETURN_CONFIRM_SECONDS then
				return nil,'await_lane_recheck',math.min(choice.untilAt,now+Config.FALLBACK_INTERVAL)
			end
			-- 基础推进确无方案才接管安全归位，不替它清兵或授予进攻权限。
			safeReturnOnly=true;baseReturnOnly=true
		end
	end
	if state.task and now<state.task.deadline then
		local valid=Validate(bot,state.task,basicLane~=nil)
		if safeReturnOnly and not IsBaseReturn(state.task.reason) then valid=false end
		if valid and (state.task.intent=='wait' or state.task.target or GetUnitToLocationDistance(bot,state.task.location)>(state.task.tolerance or 120)) then
			local task={};for k,v in pairs(state.task) do task[k]=v end
			task.preparedAt,task.validUntil=now,math.min(now+Config.CANDIDATE_TTL,task.deadline)
			return task
		end
	end
	state.task=nil
	if now<state.nextSearch then return nil,state.reason or 'search_throttled',state.nextSearch end
	state.nextSearch=now+Config.FALLBACK_INTERVAL
	local sample=Snapshot(bot)
	state.enemies=sample.enemies
	local objective=Strategy.GetPushObjective(true)
	local lane=basicLane or (objective and objective.lane or bot:GetAssignedLane())
	if lane~=LANE_TOP and lane~=LANE_MID and lane~=LANE_BOT then return nil,'invalid_lane',state.nextSearch end
	local candidate,checks=nil,0
	-- 恢复周期不因最后拒绝原因变化而重建；固定出口方向、截止时间与已拒绝局部点。
	if not basicLane and recoveryNeeded and (not baseReturnOnly or insideEnemyBase) then
		if state.recovery and now>=state.recovery.untilAt then
			state.recovery=nil;state.nextSearch=now+Config.FALLBACK_INTERVAL
			return nil,'recovery_cycle_expired',state.nextSearch
		end
		if not state.recovery then
			local goal=GetLaneFrontLocation(GetTeam(),lane,-1800)
			if insideEnemyBase then goal=bot:GetLocation()+(bot:GetLocation()-enemyAncient:GetLocation()) end
			state.recovery={goal=Copy(goal),untilAt=now+Config.FALLBACK_DURATION,rejected={},cursor=1,rejectCounts={}}
		end
	end
	local recovery=not basicLane and (not baseReturnOnly or insideEnemyBase) and state.recovery or nil
	local function Choose(location,target,kind,exact,waveTarget)
		if candidate or not location then return end
		if not target and GetUnitToLocationDistance(bot,location)<=120 then state.reason='already_in_position';return end
		-- 先裁出局部步再校验；远处战略终点不直接参与1000距离的局部安全门。
		local routeGoal=location
		if IsEgress(kind) and GetUnitToLocationDistance(bot,routeGoal)>450 then
			-- 与480恢复验证门一致，不能把750候选消耗在必然失败的长度检查上。
			routeGoal=bot:GetLocation()+(routeGoal-bot:GetLocation()):Normalized()*450
		end
		local points=(target or exact) and {routeGoal} or LocalRoutes.Build(bot:GetLocation(),routeGoal,true)
		if (basicLane or safeReturnOnly) and not target and not exact and GetUnitToLocationDistance(bot,location)>120 then
			-- 常规点不可见时再尝试96距离短步，仍检查每段视野和地形。
			table.insert(points,math.min(5,#points+1),bot:GetLocation()+(location-bot:GetLocation()):Normalized()*96)
		end
		for index,step in ipairs(points) do
			-- 给后续分路/归位目标保留预算，避免一个不可达点耗尽所有尝试。
			if index>6 then break end
			if checks>=(limit or Config.LOCAL_ROUTE_MAX_CHECKS) then return end
			checks=checks+1
			local safe,why,detail
			local rejectionKey=string.format('%.0f:%.0f:%.0f:%.0f',bot:GetLocation().x/128,bot:GetLocation().y/128,step.x/64,step.y/64)
			local failed,failedReason=F.RecentRouteFailure(bot,step)
			if recovery and recovery.rejected[rejectionKey] then safe,why=false,recovery.rejected[rejectionKey]
			elseif failed then safe,why=false,'recent_route_'..tostring(failedReason)
			elseif state.rejected and now<(state.rejectedUntil or -90) and Geometry.Distance(step,state.rejected)<128 then
				safe,why=false,'recent_failed_or_completed'
			elseif IsConnector(kind) and state.connectorOrigin and now<(state.connectorUntil or -90)
			and Geometry.Distance(step,state.connectorOrigin)<128 then safe,why=false,'recent_connector_origin'
			else safe,why,detail=Safe(bot,step,IsEgress(kind) and not target,IsConnector(kind),basicLane) end
			local continuation
			if safe and recovery and insideEnemyBase then
				-- 高地接管至少确认下一连接；只在现有可见范围内检查，计入同一搜索预算。
				if enemyAncient and Geometry.Distance(step,enemyAncient:GetLocation())<3600 then
					for nextIndex,nextPoint in ipairs(LocalRoutes.BaseConnections(step,recovery.goal)) do
						if nextIndex>3 or checks>=(limit or Config.LOCAL_ROUTE_MAX_CHECKS) then break end
						checks=checks+1
						if Safe(bot,nextPoint,true,true,nil,nil,step) then continuation=Copy(nextPoint);break end
					end
					if not continuation then safe,why=false,'no_safe_continuation' end
				end
			end
			if safe then
				candidate={provider=basicLane and 'basic_lane' or 'local_fallback',basicLane=basicLane,intent=target and 'attack_unit' or 'move',target=target,
					location=Copy(step),continuation=continuation,lane=lane,reason=kind,progressPolicy=target and 'clear_wave' or 'movement',
					finalGoal=not target and not IsEgress(kind) and Copy(location) or nil,waveTarget=waveTarget,
					preparedAt=now,validUntil=now+Config.CANDIDATE_TTL,deadline=recovery and recovery.untilAt or now+Config.FALLBACK_DURATION,
					stallSeconds=target and 6 or 3,validate=Validate,mode=basicLane and ({[LANE_TOP]=BOT_MODE_PUSH_TOWER_TOP,[LANE_MID]=BOT_MODE_PUSH_TOWER_MID,[LANE_BOT]=BOT_MODE_PUSH_TOWER_BOT})[basicLane] or BOT_MODE_ROAM,startLocation=Copy(bot:GetLocation()),
					tolerance=(basicLane or safeReturnOnly or IsConnector(kind)) and 24 or 120}
				return
			end
			state.reason=why
			if recovery then
				local label=why or 'recovery_rejected'
				recovery.rejected[rejectionKey]=label
				recovery.rejectCounts[label]=(recovery.rejectCounts[label] or 0)+1
			end
			Tasks.NoteRejection(bot,basicLane and 'push_'..basicLane or 'roam',why,step,kind..'_'..index,detail)
		end
	end
	local baseGoal
	if recovery then
		if recovery.nextPoint then Choose(recovery.nextPoint,nil,'local_recovery_connector',true);recovery.nextPoint=nil end
		local points=LocalRoutes.BaseConnections(bot:GetLocation(),recovery.goal)
		-- 每轮轮转六个方向，给其他出口候选保留原18次总预算。
		for offset=0,5 do
			Choose(points[(recovery.cursor+offset-1)%#points+1],nil,'local_recovery_connector',true)
		end
		recovery.cursor=(recovery.cursor+5)%#points+1
	end
	if baseReturnOnly then
		local home=GetShopLocation(GetTeam(),SHOP_HOME)
		local own=GetAncient(GetTeam())
		if own and not own:IsNull() and home then
			local delta=home-own:GetLocation()
			baseGoal=delta:Length2D()>1 and own:GetLocation()+delta:Normalized()*600 or home
			Choose(baseGoal,nil,safeReturnOnly and 'safe_return' or 'base_return')
		end
	end
	local terrainFailed=state.reason and string.find(state.reason,'impassable',1,true)~=nil
	if not candidate and not egressOnly and NearOwnBase(bot)
	and (not baseReturnOnly or (baseGoal and GetUnitToLocationDistance(bot,baseGoal)>120))
	and (baseReturnOnly or terrainFailed or not IsLocationPassable(bot:GetLocation())) then
		local goal=baseGoal or GetLaneFrontLocation(GetTeam(),lane,-1800)
		for _,point in ipairs(LocalRoutes.BaseConnections(bot:GetLocation(),goal)) do
			Choose(point,nil,baseReturnOnly and (safeReturnOnly and 'safe_return_connector' or 'base_return_connector') or 'base_lane_connector',true)
		end
	end
	local ancient=GetAncient(GetOpposingTeam())
	local inBase=ancient and not ancient:IsNull() and GetUnitToUnitDistance(bot,ancient)<3600
	local observation=Towers.Observe(bot,'local_lane_fallback')
	local inTower=false
	for _,zone in ipairs(not baseReturnOnly and observation.towers or {}) do
		if Geometry.PointInCircle(bot:GetLocation(),zone,96) then
			inTower=true
			local away=bot:GetLocation()-zone.center
			if away:Length2D()>1 then Choose(bot:GetLocation()+away:Normalized()*450,nil,'egress_from_tower_zone') end
		end
	end
	if inBase and not baseReturnOnly then
		local origin=bot:GetLocation()
		local away=origin-ancient:GetLocation()
		if away:Length2D()>1 then Choose(origin+away:Normalized()*750,nil,'egress_from_excluded_base') end
		Choose(GetLaneFrontLocation(bot:GetTeam(),lane,-1800),nil,'egress_from_excluded_base')
	end
	local ordinaryAllowed=basicLane~=nil or not Config.BasicLaneEnabled()
	for _,creep in ipairs(ordinaryAllowed and not baseReturnOnly and not inBase and not inTower and not egressOnly and sample.enemyCreeps or {}) do
		if InLane(creep,lane) and J.CanBeAttacked(creep) then Choose(creep:GetLocation(),creep,'clear_wave') end
	end
	if not candidate and ordinaryAllowed and not baseReturnOnly and not inBase and not inTower and not egressOnly then
		local homeward=GetLaneFrontLocation(bot:GetTeam(),lane,-1800)
		for _,creep in ipairs(sample.alliedCreeps) do
			if InLane(creep,lane) then
				local point=creep:GetLocation()
				if Geometry.Distance(point,homeward)>1 then point=point+(homeward-point):Normalized()*240 end
				Choose(point,nil,'meet_wave',false,creep)
			end
		end
	end
	if not candidate and not baseReturnOnly then
		for _,offset in ipairs({-1200,-1800,-2400}) do Choose(GetLaneFrontLocation(bot:GetTeam(),lane,offset),nil,inBase and 'egress_from_excluded_base' or ((inTower or egressOnly) and 'egress_from_tower_zone' or 'stage_lane')) end
	end
	-- 安全归位后只提供一次两秒重评窗口，不重复创建原地移动或无限等待。
	if state.regroupAnchor and Geometry.Distance(bot:GetLocation(),state.regroupAnchor)>128 then state.regroupAnchor=nil end
	if not candidate and safeReturnOnly and not egressOnly and NearOwnBase(bot) and state.reason=='already_in_position' then
		local safe,why=Safe(bot,bot:GetLocation(),false,false,nil)
		if safe and not state.regroupAnchor then
			state.regroupAnchor=Copy(bot:GetLocation())
			candidate={provider='local_fallback',intent='wait',location=Copy(bot:GetLocation()),lane=lane,
				reason='safe_regroup',progressPolicy='bounded_wait',preparedAt=now,validUntil=now+Config.CANDIDATE_TTL,
				deadline=now+2,mode=BOT_MODE_ROAM,tolerance=48,validate=Validate}
		else state.reason=safe and 'safe_regroup_consumed' or why end
	end
	if not candidate then
		-- 周期内汇总全部拒绝门，避免最后一次失败掩盖其他出口为何不可用。
		if recovery and Config.DEBUG and now-(state.recoveryLogAt or -90)>=2 then
			state.recoveryLogAt=now
			local labels={};for label,count in pairs(recovery.rejectCounts) do labels[#labels+1]=label..':'..count end
			table.sort(labels)
			print(string.format('[BOT][RecoverySearch] run=%s time=%.3f pid=%s x=%.1f y=%.1f goal_x=%.1f goal_y=%.1f until_at=%.3f checks=%d towers=%d rejects=%s',
				Config.RUN_ID,now,bot:GetPlayerID(),bot:GetLocation().x,bot:GetLocation().y,recovery.goal.x,recovery.goal.y,
				recovery.untilAt,checks,#(observed.towers or {}),table.concat(labels,'|')))
		end
		return nil,state.reason or 'no_local_safe_candidate',state.nextSearch
	end
	state.generation=state.generation+1
	candidate.key=(basicLane and 'basic:'..basicLane..':' or 'local:')..state.generation;candidate.executionVersion=2
	state.task=candidate
	return candidate
end
local function LogChoice(bot,choice)
	if not Config.DEBUG or DotaTime()-(bot.THD_BasicChoiceLogAt or -90)<Config.LOG_INTERVAL then return end
	bot.THD_BasicChoiceLogAt=DotaTime()
	print(string.format('[BOT][BasicChoice] run=%s time=%.3f pid=%s preferred_lane=%s prepared_lane=%s selected_lane=%s key=%s admissible=%s reason=%s rejections=%s until_at=%s',
		Config.RUN_ID,DotaTime(),bot:GetPlayerID(),tostring(choice.preferredLane),tostring(choice.preparedLane),tostring(choice.lane),
		tostring(choice.plan and choice.plan.key),tostring(choice.plan~=nil),tostring(choice.reason or 'admissible'),
		table.concat(choice.rejections or {},'|'),tostring(choice.untilAt)))
end
function F.Select(bot)
	local now=DotaTime()
	local cached=bot.THD_BasicLaneChoice
	if cached and now<cached.untilAt then
		if not cached.plan or Tasks.CanOfferExecutable(bot,'push_'..cached.lane,Config.BASIC_LANE_DESIRE,cached.plan) then return cached end
		-- 准备后可能进入重试冷却，旧的“已准备”不能阻止其他安全任务接手。
	end
	local choice={at=now,untilAt=now+Config.FALLBACK_INTERVAL,rejections={}}
	bot.THD_BasicLaneChoice=choice
	local objective=Strategy.GetPushObjective(true)
	local preferred=objective and objective.lane or bot:GetAssignedLane()
	for _,lane in ipairs({LANE_TOP,LANE_MID,LANE_BOT}) do
		local active=Tasks.Active(bot,'push_'..lane)
		if active and active.provider=='basic_lane' and active.finalGoal and now<active.deadline
		and Tasks.ProgressScore(bot,'push_'..lane,Config.BASIC_LANE_DESIRE,true)>Config.BASIC_LANE_DESIRE then preferred=lane;break end
	end
	choice.preferredLane=preferred
	local lanes={}
	if preferred==LANE_TOP or preferred==LANE_MID or preferred==LANE_BOT then lanes[1]=preferred end
	for _,lane in ipairs({LANE_TOP,LANE_MID,LANE_BOT}) do
		if lane~=preferred and GetAmountAlongLane(lane,bot:GetLocation()).distance<=1000 then lanes[#lanes+1]=lane end
	end
	-- 最多三路共享18次安全检查预算，不因三次GetDesire重复扫描或发布多个候选。
	local quota=math.floor(Config.LOCAL_ROUTE_MAX_CHECKS/math.max(1,#lanes))
	for _,lane in ipairs(lanes) do
		local plan,reason=PrepareScope(bot,lane,quota)
		if plan then
			choice.preparedLane=lane
			local admissible,why=Tasks.CanOfferExecutable(bot,'push_'..lane,Config.BASIC_LANE_DESIRE,plan)
			if admissible then
				choice.lane,choice.plan=lane,plan
				choice.untilAt=math.min(choice.untilAt,plan.validUntil)
				LogChoice(bot,choice)
				return choice
			end
			reason='admission_'..tostring(why)
		end
		choice.rejections[#choice.rejections+1]=tostring(lane)..':'..tostring(reason)
	end
	choice.reason='no_feasible_basic_lane:'..table.concat(choice.rejections,'|')
	LogChoice(bot,choice)
	return choice
end
function F.Prepare(bot,basicLane)
	if not basicLane then return PrepareScope(bot,nil) end
	local choice=F.Select(bot)
	if choice.lane~=basicLane then return nil,choice.reason or 'different_basic_lane',choice.untilAt end
	return choice.plan,nil,choice.untilAt
end
function F.Execute(bot,task)
	if Actions.Protected(bot) then return {status='PROTECTED',reason='protected_lifecycle'} end
	if task.intent=='wait' then
		if DotaTime()>=task.deadline then return {status='COMPLETE',reason='regroup_finished'} end
		local valid,reason=Validate(bot,task)
		if not valid then return {status='INVALID',reason=reason} end
		local action=bot:GetCurrentActionType()
		if action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE then return {status='INVALID',reason='regroup_action_changed'} end
		return {status='WAITING',reason='safe_regroup',deadline=task.deadline}
	end
	if task.target and not task.target:IsNull() and task.target:CanBeSeen() and not task.target:IsAlive() then
		return {status='COMPLETE',reason='creep_dead'}
	end
	if not task.target and GetUnitToLocationDistance(bot,task.location)<=(task.tolerance or 120) then
		if not task.finalGoal or GetUnitToLocationDistance(bot,task.finalGoal)<=120 then LogJourney(bot,task,'complete');return {status='COMPLETE',reason='arrived'} end
		local valid,why=Validate(bot,task)
		if not valid then return {status='INVALID',reason=why} end
		local state=State(bot,task.basicLane)
		local nextPoint
		for index,point in ipairs(LocalRoutes.Build(bot:GetLocation(),task.finalGoal,true)) do
			if index>6 then break end
			if GetUnitToLocationDistance(bot,point)>24 and not F.RecentRouteFailure(bot,point)
			and Safe(bot,point,false,IsConnector(task.reason),task.basicLane) then nextPoint=point;break end
		end
		if not nextPoint then return {status='BLOCKED',reason='journey_no_safe_step'} end
		-- 同任务换路点：保留最终目标、身份和绝对期限，只重置本段物理进度。
		task.location=Copy(nextPoint);task.startLocation=Copy(bot:GetLocation())
		task.bestDistance,task.arrivedAt,task.actionIntent=nil,nil,nil
		task.preparedAt,task.validUntil=DotaTime(),math.min(DotaTime()+Config.CANDIDATE_TTL,task.deadline)
		state.task=task
		local choice=bot.THD_BasicLaneChoice
		if task.basicLane and choice and choice.lane==task.basicLane then choice.plan=task;choice.untilAt=task.validUntil end
	end
	local valid,reason,detail=Validate(bot,task)
	if not valid then
		Tasks.NoteRejection(bot,task.basicLane and 'push_'..task.basicLane or 'roam',reason,task.target and Actions.ValidTarget(task.target) and task.target:GetLocation() or task.location,'fallback_execute',detail)
		return {status='INVALID',reason=reason}
	end
	local before=Tasks.Capture(bot)
	if task.target then J.ActionAttackUnit(bot,'local_fallback_clear',task.target,true,0.25)
	else J.ActionMoveToLocation(bot,'lane_work_local_fallback',task.location,0.25,task.tolerance or 120,function(point) return Safe(bot,point,IsEgress(task.reason),IsConnector(task.reason),task.basicLane,task) end) end
	local result=Tasks.ResultAfter(bot,task,before)
	if result.status=='ISSUED' or result.status=='CONTINUING' then LogJourney(bot,task,'advance') end
	return result
end
function F.End(bot,task,reason)
	local state=State(bot,task and task.basicLane)
	LogJourney(bot,task,'end_'..tostring(reason))
	if task and reason=='complete' and task.continuation and state.recovery and DotaTime()<state.recovery.untilAt then
		state.recovery.nextPoint=Copy(task.continuation)
	elseif task and reason=='arrived' and task.continuation and state.recovery and DotaTime()<state.recovery.untilAt then
		state.recovery.nextPoint=Copy(task.continuation)
	end
	if task and reason~='preempted' then
		state.rejected=Copy(task.location);state.rejectedUntil=DotaTime()+Config.FALLBACK_DURATION
		if IsConnector(task.reason) then state.connectorOrigin=task.startLocation;state.connectorUntil=DotaTime()+Config.FALLBACK_DURATION end
		if reason=='no_progress' or reason=='physical_stall' or (reason and string.find(reason,'impassable',1,true)) then
			-- 只记实际失败，不把正常抢占/完成或短暂视野变化当失败区域。
			bot.THD_LocalFailedRoutes=bot.THD_LocalFailedRoutes or {}
			local failed=bot.THD_LocalFailedRoutes
			if #failed>=8 then table.remove(failed,1) end
			failed[#failed+1]={origin=Copy(bot:GetLocation()),goal=Copy(task.location),reason=reason,untilAt=DotaTime()+6}
		end
	end
	state.task=nil;state.nextSearch=DotaTime()+Config.FALLBACK_INTERVAL
	local choice=bot.THD_BasicLaneChoice
	if task and task.basicLane and choice and choice.plan and choice.plan.key==task.key then bot.THD_BasicLaneChoice=nil end
end
function F.FinishRecoveryStep(bot)
	local task=Tasks.Active(bot,'roam')
	if not task or task.provider~='local_fallback' or task.intent~='move' or bot:GetActiveMode()~=BOT_MODE_ROAM then return false end
	local now=DotaTime()
	if now>=math.min(task.deadline or now,(task.startedAt or task.preparedAt)+Config.RECOVERY_STEP_FINISH_SECONDS)
	or not Tasks.IsExecutionActive(bot,'roam') or now-(task.progressAt or task.preparedAt)>=3
	or GetUnitToLocationDistance(bot,task.location)<=(task.tolerance or 120) then return false end
	if not Tasks.MatchingAction(bot,task) then return false end
	-- 只让正在安全前进的一小步完成；危险/保护变化立即解除，不锁Attack/Retreat。
	return Validate(bot,task)==true
end
return F
