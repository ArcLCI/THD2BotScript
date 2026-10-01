-- 建筑攻击距离包含碰撞边界；候选仅提供位置，调用方负责权限和逐段安全复核。
local Geometry=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/push/push_escort_config')
local B={}
function B.Reach(bot,target)
	if not target or target:IsNull() or not target:CanBeSeen() or not target:IsAlive() then return 0 end
	return bot:GetAttackRange()+math.max(0,bot:GetBoundingRadius())+math.max(0,target:GetBoundingRadius())
end
function B.Candidates(bot,target)
	local reach=B.Reach(bot,target)
	if reach<=0 then return {} end
	local center,origin=target:GetLocation(),bot:GetLocation()
	local delta=origin-center
	local length=math.max(1,Geometry.Distance(origin,center))
	local x,y=delta.x/length,delta.y/length
	if length<=1 then x,y=1,0 end
	local points={}
	-- 外圈优先，避免短射程英雄的目标落入建筑占地；最多18个候选。
	for _,inset in ipairs({32,72}) do
		local radius=math.max(target:GetBoundingRadius()+bot:GetBoundingRadius()+24,reach-inset)
		if radius<reach then
			for _,degrees in ipairs({0,25,-25,50,-50,75,-75,100,-100}) do
				local angle=math.rad(degrees)
				local goal=Vector(center.x+(x*math.cos(angle)-y*math.sin(angle))*radius,
					center.y+(x*math.sin(angle)+y*math.cos(angle))*radius,origin.z)
				local distance=Geometry.Distance(origin,goal)
				if distance>750 then goal=origin+(goal-origin):Normalized()*750 end
				points[#points+1]=goal
			end
		end
	end
	return points
end
-- 攻击命令负责最后一段寻路；该点只用于路径风险检查，不作为必须到达的站位。
function B.AttackApproach(bot,target)
	local reach=B.Reach(bot,target)
	if reach<=0 then return nil end
	local distance=GetUnitToUnitDistance(bot,target)
	if distance>math.min(1600,reach+400) then return nil end
	if distance<=reach then return bot:GetLocation() end
	return target:GetLocation()+(bot:GetLocation()-target:GetLocation()):Normalized()*math.max(1,reach-16)
end
function B.PathBudget(bot,point,towers,threat)
	if not threat or threat.unseenIncoming or (threat.unavoidableDamage or 0)>=bot:GetHealth() then return false,'unknown_or_lethal_incoming' end
	local origin=bot:GetLocation()
	local horizon=math.max(3,Geometry.Distance(origin,point)/math.max(100,bot:GetCurrentMovementSpeed())+1)
	local predicted,count=0,0
	for _,zone in ipairs(towers or {}) do
		if Geometry.SegmentDistanceToPoint(origin,point,zone.center)<=zone.radius+96 then
			local unit=zone.unit
			if not unit or unit:IsNull() or not unit:CanBeSeen() or not unit:IsAlive()
			or not zone.attackDamage or not zone.secondsPerAttack or zone.secondsPerAttack<=0 then return false,'unconfirmed_path_tower' end
			-- 汇总目标塔与邻塔，不能逐塔单独允许后遗漏总伤害。
			predicted=predicted+bot:GetActualIncomingDamage(zone.attackDamage,DAMAGE_TYPE_PHYSICAL)*math.ceil(horizon/math.max(0.3,zone.secondsPerAttack))
			count=count+1
		end
	end
	if count==0 then return false,'no_confirmed_path_tower' end
	predicted=math.max(predicted,threat.predictedDamage or 0)+(threat.unavoidableDamage or 0)
	local regen=math.min(math.max(0,bot:GetHealthRegen())*horizon,predicted*0.2)
	return bot:GetHealth()-predicted+regen>=bot:GetMaxHealth()*Config.PERSONAL_TOWER_RESERVE,'path_tower_budget'
end
return B
