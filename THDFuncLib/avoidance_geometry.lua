-- 纯 Lua 几何层不接触原生 avoidance 状态，便于崩溃路径关闭时独立回退。
local Geometry = {}

local EPSILON = 0.001

local function MakeVector(x, y, z)
	if type(Vector) == 'function' then return Vector(x, y, z or 0) end
	return {x = x, y = y, z = z or 0}
end

local function GetXY(value)
	if value == nil then return 0, 0 end
	return tonumber(value.x) or 0, tonumber(value.y) or 0
end

local function DistanceSquared(first, second)
	local firstX, firstY = GetXY(first)
	local secondX, secondY = GetXY(second)
	local dx, dy = firstX - secondX, firstY - secondY
	return dx * dx + dy * dy
end

local function Distance(first, second)
	return math.sqrt(DistanceSquared(first, second))
end

local function Normalize(x, y)
	local length = math.sqrt(x * x + y * y)
	if length <= EPSILON then return 0, 0, 0 end
	return x / length, y / length, length
end

local function GetRadius(zone, margin)
	return math.max(0, tonumber(zone and (zone.effectiveRadius or zone.radius)) or 0)
		+ (tonumber(margin) or 0)
end

function Geometry.MakeVector(x, y, z)
	return MakeVector(x, y, z)
end

function Geometry.Distance(first, second)
	return Distance(first, second)
end

function Geometry.PointInCircle(point, zone, margin)
	if point == nil or zone == nil or zone.center == nil then return false end
	local radius = GetRadius(zone, margin)
	return DistanceSquared(point, zone.center) <= radius * radius
end

function Geometry.SegmentDistanceToPoint(startLocation, endLocation, point)
	if startLocation == nil or endLocation == nil or point == nil then return math.huge end
	local startX, startY = GetXY(startLocation)
	local endX, endY = GetXY(endLocation)
	local pointX, pointY = GetXY(point)
	local segmentX, segmentY = endX - startX, endY - startY
	local lengthSquared = segmentX * segmentX + segmentY * segmentY
	if lengthSquared <= EPSILON then return Distance(startLocation, point) end
	local projection = ((pointX - startX) * segmentX + (pointY - startY) * segmentY) / lengthSquared
	projection = math.max(0, math.min(1, projection))
	local closestX = startX + segmentX * projection
	local closestY = startY + segmentY * projection
	local dx, dy = pointX - closestX, pointY - closestY
	return math.sqrt(dx * dx + dy * dy)
end

function Geometry.SegmentIntersectsCircle(startLocation, endLocation, zone, margin)
	if zone == nil or zone.center == nil then return false end
	return Geometry.SegmentDistanceToPoint(startLocation, endLocation, zone.center)
		<= GetRadius(zone, margin)
end

function Geometry.ValidateMovementSegment(startLocation, endLocation, zones, margin, partialExit)
	if startLocation == nil or endLocation == nil then return false, 'missing_location', nil end
	local startX, startY = GetXY(startLocation)
	local endX, endY = GetXY(endLocation)
	for _, zone in ipairs(zones or {}) do
		if zone.center ~= nil then
			local radius = GetRadius(zone, margin)
			local startDistance = Distance(startLocation, zone.center)
			local endDistance = Distance(endLocation, zone.center)
			if startDistance <= radius + EPSILON then
				local centerX, centerY = GetXY(zone.center)
				local outwardDot = (startX - centerX) * (endX - startX)
					+ (startY - centerY) * (endY - startY)
				-- 已在联合净空内时只允许单调向外且终点跨出净空，保留 escape_only 的合法出口。
				if endDistance <= startDistance + EPSILON then
					return false, 'no_outward_progress', zone
				end
				if outwardDot < -EPSILON then
					return false, 'initially_inward', zone
				end
				if not partialExit and endDistance <= radius + EPSILON then
					return false, 'target_inside_margin', zone
				end
			elseif Geometry.SegmentIntersectsCircle(startLocation, endLocation, zone, margin) then
				return false, 'segment_intersection', zone
			end
		end
	end
	return true, nil, nil
end

-- 恢复专用短步只放开“本段必须到圆外”，仍要求每个起点圆单调向外、不得进入其他圆。
function Geometry.ValidateRecoverySegment(origin, target, zones, margin)
	if origin == nil or target == nil or Distance(origin, target) > 480.1 then
		return false, 'recovery_step_range'
	end
	return Geometry.ValidateMovementSegment(origin, target, zones, margin, true)
end

function Geometry.FilterIntersectingZones(startLocation, endLocation, zones, margin)
	local result = {}
	for _, zone in ipairs(zones or {}) do
		if Geometry.SegmentIntersectsCircle(startLocation, endLocation, zone, margin) then
			table.insert(result, zone)
		end
	end
	return result
end

local function IsPassable(location)
	if type(IsLocationPassable) ~= 'function' then return true end
	local ok, passable = pcall(IsLocationPassable, location)
	return ok and passable == true
end

local function IsOutsideAll(location, zones, margin)
	for _, zone in ipairs(zones or {}) do
		if Geometry.PointInCircle(location, zone, margin) then return false end
	end
	return true
end

local function BuildDirection(origin, preferredDestination, zones, margin, forceAway)
	local originX, originY = GetXY(origin)
	local preferredX, preferredY = GetXY(preferredDestination)
	local directionX, directionY = Normalize(preferredX - originX, preferredY - originY)
	for _, zone in ipairs(zones or {}) do
		if forceAway or Geometry.PointInCircle(origin, zone, margin or 0) then
			local centerX, centerY = GetXY(zone.center)
			local awayX, awayY = Normalize(originX - centerX, originY - centerY)
			directionX = directionX + awayX * 2
			directionY = directionY + awayY * 2
		end
	end
	directionX, directionY = Normalize(directionX, directionY)
	if directionX == 0 and directionY == 0 then directionX = 1 end
	return directionX, directionY
end

local function RequiredExitDistance(origin, directionX, directionY, zones, margin)
	local originX, originY = GetXY(origin)
	local required = 0
	for _, zone in ipairs(zones or {}) do
		local radius = GetRadius(zone, margin)
		local centerX, centerY = GetXY(zone.center)
		local relX, relY = originX - centerX, originY - centerY
		local distanceSquared = relX * relX + relY * relY
		if distanceSquared < radius * radius then
			local projection = relX * directionX + relY * directionY
			local discriminant = projection * projection + radius * radius - distanceSquared
			local needed = -projection + math.sqrt(math.max(0, discriminant))
			required = math.max(required, needed)
		end
	end
	return required
end

local function Rotate(x, y, radians)
	local cosine, sine = math.cos(radians), math.sin(radians)
	return x * cosine - y * sine, x * sine + y * cosine
end

function Geometry.FindDirectEscapePoint(origin, preferredDestination, zones, margin, directionZones)
	if origin == nil then return nil end
	local originX, originY = GetXY(origin)
	local originZ = tonumber(origin.z) or 0
	-- directionZones 表示本次必须远离的圆；约束检查仍使用完整 zones，避免逃入相邻塔圆。
	local baseX, baseY = BuildDirection(origin, preferredDestination or origin,
		directionZones or zones, margin, directionZones ~= nil)
	local angles = {0, math.pi / 6, -math.pi / 6, math.pi / 3, -math.pi / 3, math.pi / 2, -math.pi / 2, math.pi}
	local best, bestDistance = nil, math.huge
	for _, angle in ipairs(angles) do
		local directionX, directionY = Rotate(baseX, baseY, angle)
		local distance = math.max(220, RequiredExitDistance(origin, directionX, directionY, zones, margin) + 64)
		local candidate = MakeVector(originX + directionX * distance, originY + directionY * distance, originZ)
		-- 落点在圈外仍可能穿过另一座塔；直接逃生与 escape_only 都必须整段安全。
		if IsPassable(candidate) and IsOutsideAll(candidate, zones, margin)
		and Geometry.ValidateMovementSegment(origin, candidate, zones, margin)
		and distance < bestDistance then
			best, bestDistance = candidate, distance
		end
	end
	return best
end

function Geometry.ValidateLocalTerrainSegment(origin, target, requireVisible)
	if origin == nil or target == nil then return false, 'missing_location' end
	if type(IsLocationPassable) ~= 'function'
	or (requireVisible and type(IsLocationVisible) ~= 'function') then
		return false, 'terrain_api_unavailable'
	end
	local steps = math.max(1, math.ceil(Distance(origin, target) / 96))
	if steps > 64 then return false, 'segment_too_long' end
	-- 恢复不能只看终点；采样有硬上限，API 缺失时不把未知地形当可走。
	for index = 1, steps do
		local point = MakeVector(origin.x + (target.x - origin.x) * index / steps,
			origin.y + (target.y - origin.y) * index / steps, target.z)
		local ok, passable = pcall(IsLocationPassable, point)
		if not ok or passable ~= true then return false, ok and 'impassable_segment' or 'terrain_query_error', {point = point, index = index, steps = steps} end
		if requireVisible then
			local visibleOK, visible = pcall(IsLocationVisible, point)
			if not visibleOK or visible ~= true then return false, 'unseen_segment', {point = point, index = index, steps = steps} end
		end
	end
	return true
end

function Geometry.FindRecoveryPoint(origin, preferred, zones, margin, maxDistance, rejected)
	local stats = {candidates = 0, geometry = 0, terrain = 0, recent = 0, range = 0, terrainSamples = {}}
	if origin == nil or preferred == nil then return nil, stats end
	local baseX, baseY = BuildDirection(origin, preferred, zones, margin, false)
	local best, bestScore = nil, math.huge
	-- 最多 16 方向 x 3 距离；联合圆只做约束，不删除侧面塔，也不缩小半径。
	for index = 0, 15 do
		local dx, dy = Rotate(baseX, baseY, index * math.pi / 8)
		local exitDistance = RequiredExitDistance(origin, dx, dy, zones, margin) + 96
		local previousDistance = -1
		for _, step in ipairs({220, 480, 960}) do
			local distance = math.max(step, exitDistance)
			if distance ~= previousDistance then
				previousDistance = distance
				stats.candidates = stats.candidates + 1
				local candidate = MakeVector(origin.x + dx * distance, origin.y + dy * distance, origin.z)
				local recentlyFailed = false
				for _, point in ipairs(rejected or {}) do
					if Distance(candidate, point) < 240 then recentlyFailed = true; break end
				end
				if distance > maxDistance then
					stats.range = stats.range + 1
				elseif recentlyFailed then
					stats.recent = stats.recent + 1
				elseif not Geometry.ValidateMovementSegment(origin, candidate, zones, margin) then
					stats.geometry = stats.geometry + 1
				else
					local passable, reason, detail = Geometry.ValidateLocalTerrainSegment(origin, candidate, false)
					if not passable then
						stats.terrain = stats.terrain + 1
						if #stats.terrainSamples < 4 then
							table.insert(stats.terrainSamples, {reason = reason, detail = detail, target = candidate})
						end
					else
						local score = Distance(candidate, preferred) + distance * 0.25
						if score < bestScore then best, bestScore = candidate, score end
					end
				end
			end
		end
	end
	return best, stats
end

-- 完整直线出口无解时，额外最多 48 个短步候选；真实进度后才允许下一批搜索。
function Geometry.FindRecoveryStep(origin, preferred, zones, margin, rejected, compact)
	local stats = {candidates = 0, geometry = 0, terrain = 0, recent = 0, range = 0, terrainSamples = {}}
	if origin == nil or preferred == nil then return nil, stats end
	local baseX, baseY = BuildDirection(origin, preferred, zones, margin, false)
	local best, bestScore = nil, math.huge
	for index = 0, 15 do
		local dx, dy = Rotate(baseX, baseY, index * math.pi / 8)
		-- 细步仅缩短长度，不改变任何塔圆/向外推进/地形约束。
		for _, distance in ipairs(compact and {64, 96, 128} or {160, 320, 480}) do
			stats.candidates = stats.candidates + 1
			local candidate = MakeVector(origin.x + dx * distance, origin.y + dy * distance, origin.z)
			local recent = false
			for _, point in ipairs(rejected or {}) do
				if Distance(candidate, point) < 120 then recent = true; break end
			end
			if recent then
				stats.recent = stats.recent + 1
			elseif not Geometry.ValidateRecoverySegment(origin, candidate, zones, margin) then
				stats.geometry = stats.geometry + 1
			else
				local passable, reason, detail = Geometry.ValidateLocalTerrainSegment(origin, candidate, false)
				if not passable then
					stats.terrain = stats.terrain + 1
					if #stats.terrainSamples < 4 then
						table.insert(stats.terrainSamples, {reason = reason, detail = detail, target = candidate})
					end
				else
					local deficit = 0
					for _, zone in ipairs(zones or {}) do
						deficit = deficit + math.max(0, GetRadius(zone, margin) - Distance(candidate, zone.center))
					end
					local score = deficit * 4 + Distance(candidate, preferred) + distance * 0.25
					if score < bestScore then best, bestScore = candidate, score end
				end
			end
		end
	end
	return best, stats
end

local function CandidateIsSafe(startLocation, candidate, destination, zones, margin)
	if not IsPassable(candidate) or not IsOutsideAll(candidate, zones, margin) then return false end
	for _, zone in ipairs(zones or {}) do
		if Geometry.SegmentIntersectsCircle(startLocation, candidate, zone, margin)
		or Geometry.SegmentIntersectsCircle(candidate, destination, zone, margin)
		then
			return false
		end
	end
	return true
end

local function WaypointPathIsSafe(startLocation, waypoints, zones, margin)
	local previous = startLocation
	for _, waypoint in ipairs(waypoints or {}) do
		if not IsPassable(waypoint) or not IsOutsideAll(waypoint, zones, margin) then return false end
		for _, zone in ipairs(zones or {}) do
			if Geometry.SegmentIntersectsCircle(previous, waypoint, zone, margin) then return false end
		end
		previous = waypoint
	end
	return true
end

function Geometry.BuildFallbackWaypoints(startLocation, destination, zones, margin)
	if startLocation == nil or destination == nil then return nil, 'missing_location' end
	zones = zones or {}
	local routeZones = Geometry.FilterIntersectingZones(startLocation, destination, zones, margin)
	if #routeZones == 0 then
		return {destination}, 'direct'
	end

	local firstZone = routeZones[1]
	local startX, startY = GetXY(startLocation)
	local destinationX, destinationY = GetXY(destination)
	local centerX, centerY = GetXY(firstZone.center)
	local directionX, directionY = Normalize(destinationX - startX, destinationY - startY)
	if directionX == 0 and directionY == 0 then return nil, 'zero_length' end
	local bypassRadius = GetRadius(firstZone, margin) + 128
	local perpendicularX, perpendicularY = -directionY, directionX
	local bypasses = {
		{
			MakeVector(centerX - directionX * bypassRadius + perpendicularX * bypassRadius,
				centerY - directionY * bypassRadius + perpendicularY * bypassRadius, tonumber(startLocation.z) or 0),
			MakeVector(centerX + directionX * bypassRadius + perpendicularX * bypassRadius,
				centerY + directionY * bypassRadius + perpendicularY * bypassRadius, tonumber(startLocation.z) or 0),
			destination,
		},
		{
			MakeVector(centerX - directionX * bypassRadius - perpendicularX * bypassRadius,
				centerY - directionY * bypassRadius - perpendicularY * bypassRadius, tonumber(startLocation.z) or 0),
			MakeVector(centerX + directionX * bypassRadius - perpendicularX * bypassRadius,
				centerY + directionY * bypassRadius - perpendicularY * bypassRadius, tonumber(startLocation.z) or 0),
			destination,
		},
	}
	local bestBypass, bestBypassLength = nil, math.huge
	for _, waypoints in ipairs(bypasses) do
		if WaypointPathIsSafe(startLocation, waypoints, zones, margin) then
			local length = Distance(startLocation, waypoints[1])
				+ Distance(waypoints[1], waypoints[2]) + Distance(waypoints[2], destination)
			if length < bestBypassLength then bestBypass, bestBypassLength = waypoints, length end
		end
	end
	if bestBypass ~= nil then return bestBypass, 'bypass_pair' end

	local radius = GetRadius(firstZone, margin) + 96
	local candidates = {
		MakeVector(centerX - directionY * radius, centerY + directionX * radius, tonumber(startLocation.z) or 0),
		MakeVector(centerX + directionY * radius, centerY - directionX * radius, tonumber(startLocation.z) or 0),
	}
	local best, bestLength = nil, math.huge
	for _, candidate in ipairs(candidates) do
		if CandidateIsSafe(startLocation, candidate, destination, zones, margin) then
			local length = Distance(startLocation, candidate) + Distance(candidate, destination)
			if length < bestLength then best, bestLength = candidate, length end
		end
	end
	if best ~= nil then return {best, destination}, 'tangent' end
	-- 侧面塔只约束路径安全，不参与本次路线障碍的远离方向合成。
	local escape = Geometry.FindDirectEscapePoint(startLocation, destination, zones, margin, routeZones)
	if escape ~= nil then return {escape}, 'escape_only' end
	return nil, 'no_passable_waypoint'
end

function Geometry.ValidatePath(startLocation, waypoints, zones, tolerance)
	if startLocation == nil or type(waypoints) ~= 'table' or #waypoints == 0 then
		return false, 'empty_path'
	end
	local previous = startLocation
	for index, rawWaypoint in ipairs(waypoints) do
		local waypoint = type(rawWaypoint) == 'table' and (rawWaypoint.location or rawWaypoint) or rawWaypoint
		if waypoint == nil or waypoint.x == nil or waypoint.y == nil then
			return false, 'invalid_waypoint_' .. tostring(index)
		end
		for _, zone in ipairs(zones or {}) do
			local clearance = Geometry.SegmentDistanceToPoint(previous, waypoint, zone.center)
			if clearance < GetRadius(zone, 0) - (tonumber(tolerance) or 0) then
				return false, 'zone_intersection_' .. tostring(zone.key or index)
			end
		end
		previous = waypoint
	end
	return true, nil
end

return Geometry
