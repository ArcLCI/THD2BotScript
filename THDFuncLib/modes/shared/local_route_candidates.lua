-- 只生成有界几何候选；调用方必须逐段检查地形、视野和塔区后才能执行。
local R={}
function R.Build(origin,goal,shortFirst)
	local result,seen,direct={},{},0
	if not origin or not goal then return result end
	local dx,dy=goal.x-origin.x,goal.y-origin.y
	local distance=math.sqrt(dx*dx+dy*dy)
	if distance<=120 then return result end
	-- 接兵/归位先找视野内短步；避塔保持原来的长步顺序。
	for _,length in ipairs(shortFirst and {200,240,450,750} or {750,450,240}) do
		local step=math.min(length,distance)
		for _,degrees in ipairs({0,35,-35,70,-70}) do
			local angle=math.rad(degrees)
			local x=origin.x+(dx*math.cos(angle)-dy*math.sin(angle))/distance*step
			local y=origin.y+(dx*math.sin(angle)+dy*math.cos(angle))/distance*step
			local remaining=math.sqrt((x-goal.x)^2+(y-goal.y)^2)
			local key=string.format('%.0f:%.0f',x/32,y/32)
			if remaining<=distance-24 and not seen[key] then
				seen[key]=true
				if shortFirst and degrees==0 then
					direct=direct+1;table.insert(result,direct,Vector(x,y,origin.z))
				else result[#result+1]=Vector(x,y,origin.z) end
			end
		end
	end
	if shortFirst then
		-- 首轮预算中保留左右两侧，不让多个同向长度用尽连接机会。
		local ordered,used={},{}
		local function Add(index)
			if result[index] and not used[index] then ordered[#ordered+1]=result[index];used[index]=true end
		end
		for _,index in ipairs({1,direct+1,direct+2,2,3,4}) do Add(index) end
		for index=1,#result do Add(index) end
		return ordered
	end
	return result
end
-- 基地连接允许先侧向绕开阻挡；只给出200距离局部点，不表示路径已安全。
function R.BaseConnections(origin,goal)
	local result={}
	local delta=goal-origin
	local length=math.max(1,delta:Length2D())
	local x,y=delta.x/length,delta.y/length
	if length<=1 then x,y=1,0 end
	for _,degrees in ipairs({0,30,-30,60,-60,90,-90,120,-120,150,-150,180}) do
		local angle=math.rad(degrees)
		result[#result+1]=Vector(origin.x+(x*math.cos(angle)-y*math.sin(angle))*200,
			origin.y+(x*math.sin(angle)+y*math.cos(angle))*200,origin.z)
	end
	return result
end
return R
