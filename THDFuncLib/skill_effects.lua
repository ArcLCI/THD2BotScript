-- 技能机制来自Game KV/Lua；等级/增伤未知时使用显式目录参考值，不当作实际施法数据。
local E = {}
E.sources = {
	{id='ability_thdots_sanae01',prefix='sanae01',modifier='modifier_thd_sanae01_observation',kind='periodic',
		rawLow=40,rawHigh=300,interval=1,slow=0.40,slowModifier='modifier_thdots_sanae01_slow',
		baseWeight=1.0,control=0,confidence='catalog_unattributed',scope='periodic_circle'},
	{id='ability_thdots_tojiko04',prefix='tojiko04',modifier='modifier_thd_tojiko04_observation',kind='delayed_burst',
		rawLow=200,rawHigh=450,armorFactor=40,markerTail=0.35,timeSlack=0.20,slow=0,
		baseWeight=1.0,control=0,confidence='catalog_unattributed',scope='primary_and_echo_burst'},
}
local byId={};for _,profile in ipairs(E.sources) do byId[profile.id]=profile end
function E.Get(id) return byId[id] end
-- 只计算沿已知直线计划的占用窗口；无目的地时按留在当前位置处理，不猜测Valve路径。
function E.BurstExposure(a,b,zone,speed,now,elapsed,margin,holdGoal)
	local profile=E.Get(zone.abilityId)
	if not profile or profile.kind~='delayed_burst' or not zone.impactAt then return nil end
	local radius=zone.radius+(margin or 0)
	local dx,dy=b.x-a.x,b.y-a.y
	local length=math.sqrt(dx*dx+dy*dy)
	local x,y=a.x-zone.center.x,a.y-zone.center.y
	local enter,leave=0,math.huge
	if length<1 then
		if x*x+y*y>radius*radius then return false,'outside_at_impact',0,0 end
		if not holdGoal then leave=0 end
	else
		local projection=(x*dx+y*dy)/length
		local disc=projection*projection-(x*x+y*y-radius*radius)
		if disc<0 then return false,'path_misses',0,0 end
		local root=math.sqrt(disc)
		local first,last=math.max(0,-projection-root),math.min(length,-projection+root)
		if last<first then return false,'path_misses',0,0 end
		enter,leave=first/math.max(1,speed),last/math.max(1,speed)
		local gx,gy=b.x-zone.center.x,b.y-zone.center.y
		if holdGoal and gx*gx+gy*gy<=radius*radius then leave=math.huge end
	end
	local low=zone.impactAt-now-profile.timeSlack
	local high=zone.impactAt-now+profile.timeSlack
	enter,leave=enter+(elapsed or 0),leave+(elapsed or 0)
	if high<0 then return false,'impact_window_finished',enter,leave end
	if leave<low then return false,'clear_before_impact',enter,leave end
	if enter>high then return false,'arrive_after_impact',enter,leave end
	return true,'occupies_impact_window',enter,leave
end
return E
