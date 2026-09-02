local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local Geometry = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')

local TowerSafety = {}

-- 敌塔 handle 只在本次扫描内读取；跨帧只向控制器返回位置、半径和锁定状态快照。

local function IsAuthorizedHighGroundTower(snapshot, options)
	local authorization = options ~= nil and options.highGroundAssaultAuthorization or nil
	if type(authorization) ~= 'table' or snapshot == nil or snapshot.highGround ~= true then return false end
	local targetLocation = authorization.targetLocation
	local bypassRadius = tonumber(authorization.towerBypassRadius) or 0
	return targetLocation ~= nil and bypassRadius > 0
		and Geometry.Distance(snapshot.center, targetLocation) <= bypassRadius
end

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if not ok or value == nil then return defaultValue end
	return value
end

local function IsValidUnit(unit)
	if unit == nil then return false end
	if unit.IsNull ~= nil and Safe(true, function() return unit:IsNull() end) then return false end
	if unit.IsAlive ~= nil and not Safe(false, function() return unit:IsAlive() end) then return false end
	return true
end

local function CanInspectUnit(unit)
	return IsValidUnit(unit)
		and unit.CanBeSeen ~= nil
		and Safe(false, function() return unit:CanBeSeen() end)
end

local function GetUnitKey(unit)
	local entityIndex = Safe(nil, function()
		if unit.GetEntityIndex ~= nil then return unit:GetEntityIndex() end
		if unit.entindex ~= nil then return unit:entindex() end
		return nil
	end)
	if type(entityIndex) == 'number' and entityIndex >= 0 then
		return 'tower:' .. tostring(entityIndex)
	end
	local name = Safe('unknown_tower', function() return unit:GetUnitName() end)
	local location = Safe(nil, function() return unit:GetLocation() end)
	if location ~= nil then
		return string.format('tower:%s:%d:%d', tostring(name),
			math.floor((location.x or 0) / 64), math.floor((location.y or 0) / 64))
	end
	return 'tower:' .. tostring(name)
end

local function IsTower(unit)
	return CanInspectUnit(unit)
		and unit.IsTower ~= nil
		and Safe(false, function() return unit:IsTower() end)
end

local function IsSupportedTowerName(name)
	if type(name) ~= 'string' then return false end
	return string.find(name, 'tower1', 1, true) ~= nil
		or string.find(name, 'tower2', 1, true) ~= nil
		or string.find(name, 'tower3', 1, true) ~= nil
		or string.find(name, 'tower4', 1, true) ~= nil
end

local function GetTowerSnapshots(bot)
	local snapshots = {}
	local botLocation = bot:GetLocation()
	local buildings = Safe({}, function() return GetUnitList(UNIT_LIST_ENEMY_BUILDINGS) end) or {}
	for _, tower in pairs(buildings) do
		if IsTower(tower) then
			local center = Safe(nil, function() return tower:GetLocation() end)
			local name = Safe('unknown_tower', function() return tower:GetUnitName() end)
			if IsSupportedTowerName(name)
			and center ~= nil and Geometry.Distance(botLocation, center) <= Config.TOWER_SCAN_RANGE
			then
				local attackRange = math.max(1, tonumber(Safe(900, function() return tower:GetAttackRange() end)) or 900)
				local attackTarget = Safe(nil, function() return tower:GetAttackTarget() end)
				local key = GetUnitKey(tower)
				table.insert(snapshots, {
					key = key,
					center = Geometry.MakeVector(center.x or 0, center.y or 0, center.z or 0),
					radius = attackRange,
					effectiveRadius = attackRange + Config.TOWER_EXIT_BUFFER,
					attackRange = attackRange,
					attackPoint = math.max(0, tonumber(Safe(0, function() return tower:GetAttackPoint() end)) or 0),
					secondsPerAttack = math.max(0, tonumber(Safe(0, function() return tower:GetSecondsPerAttack() end)) or 0),
					locked = attackTarget == bot,
					source = 'visible_enemy_tower',
					highGround = string.find(name, 'tower3', 1, true) ~= nil
						or string.find(name, 'tower4', 1, true) ~= nil,
					name = name,
				})
			end
		end
	end
	return snapshots
end

local function CountHighGroundAttackRanges(location, snapshots)
	local count = 0
	for _, snapshot in ipairs(snapshots or {}) do
		if snapshot.highGround == true
		and Geometry.Distance(location, snapshot.center) <= (tonumber(snapshot.attackRange) or 0)
		then
			count = count + 1
		end
	end
	return count
end

local function GetOwnAncientLocation(bot)
	local ancient = Safe(nil, function() return GetAncient(bot:GetTeam()) end)
	return ancient ~= nil and Safe(nil, function() return ancient:GetLocation() end) or nil
end

local function GetIncomingTowerAttacks(bot)
	local countByKey = {}
	local projectiles = Safe({}, function() return bot:GetIncomingTrackingProjectiles() end) or {}
	for _, projectile in pairs(projectiles) do
		local caster = projectile ~= nil and projectile.caster or nil
		if projectile ~= nil and projectile.is_attack and CanInspectUnit(caster)
		and caster.IsTower ~= nil and Safe(false, function() return caster:IsTower() end)
		then
			local key = GetUnitKey(caster)
			countByKey[key] = (countByKey[key] or 0) + 1
		end
	end
	-- 无法同帧确认 caster 为可见敌塔的普通攻击弹道必须失败关闭，不能误升级为塔危险。
	return countByKey, false
end

local function IsDiveMode(mode)
	local candidates = {
		rawget(_G, 'BOT_MODE_ATTACK'), rawget(_G, 'BOT_MODE_GANK'), rawget(_G, 'BOT_MODE_ROAM'),
		rawget(_G, 'BOT_MODE_TEAM_ROAM'), rawget(_G, 'BOT_MODE_PUSH_TOWER_TOP'),
		rawget(_G, 'BOT_MODE_PUSH_TOWER_MID'), rawget(_G, 'BOT_MODE_PUSH_TOWER_BOT'),
	}
	for _, candidate in pairs(candidates) do
		if type(candidate) == 'number' and mode == candidate then return true end
	end
	return false
end

local function IsVisibleEnemyHero(bot, target)
	return CanInspectUnit(target)
		and target.IsHero ~= nil
		and Safe(false, function() return target:IsHero() end)
		and Safe(bot:GetTeam(), function() return target:GetTeam() end) ~= bot:GetTeam()
end

local function IsOutsideTowerSnapshots(location, snapshots)
	for _, snapshot in ipairs(snapshots or {}) do
		if Geometry.PointInCircle(location, snapshot, 0) then return false end
	end
	return true
end

local function BuildAnchor(bot, snapshots)
	local botLocation = bot:GetLocation()
	local ancientLocation = GetOwnAncientLocation(bot)
	if ancientLocation == nil then return nil, false end
	local dx = (ancientLocation.x or 0) - (botLocation.x or 0)
	local dy = (ancientLocation.y or 0) - (botLocation.y or 0)
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 1 then return ancientLocation, false end
	local distance = math.min(Config.ESCAPE_ANCHOR_DISTANCE, length)
	local directionX, directionY = dx / length, dy / length
	local sideX, sideY = -directionY, directionX
	local forwardDistances = {distance}
	local extendedDistance = distance
	local changed = true
	while changed do
		changed = false
		for _, snapshot in ipairs(snapshots or {}) do
			local center = snapshot.center or {}
			local relX = (center.x or 0) - (botLocation.x or 0)
			local relY = (center.y or 0) - (botLocation.y or 0)
			local projection = relX * directionX + relY * directionY
			local perpendicularSquared = math.max(0, relX * relX + relY * relY - projection * projection)
			local radius = snapshot.effectiveRadius or snapshot.radius or 0
			if projection > 0 and perpendicularSquared <= radius * radius then
				local halfChord = math.sqrt(math.max(0, radius * radius - perpendicularSquared))
				local nearDistance, farDistance = projection - halfChord, projection + halfChord
				if extendedDistance >= nearDistance and extendedDistance <= farDistance then
					local nextDistance = math.min(length, farDistance + 64)
					if nextDistance > extendedDistance + 1 then
						extendedDistance = nextDistance
						changed = true
					end
				end
			end
		end
	end
	if extendedDistance > distance + 1 then table.insert(forwardDistances, extendedDistance) end
	for _, forwardDistance in ipairs(forwardDistances) do
		for _, sideOffset in ipairs({0, 160, -160, 320, -320}) do
			local candidate = Geometry.MakeVector(
				(botLocation.x or 0) + directionX * forwardDistance + sideX * sideOffset,
				(botLocation.y or 0) + directionY * forwardDistance + sideY * sideOffset,
				botLocation.z or ancientLocation.z or 0)
			if type(IsLocationPassable) ~= 'function'
			or Safe(false, function() return IsLocationPassable(candidate) end)
			then
				if IsOutsideTowerSnapshots(candidate, snapshots) then
					return candidate, forwardDistance > distance + 1
				end
			end
		end
	end
	-- 扩展锚点没有可通行落点时，保留较短的安全侧向候选作为最终降级。
	for _, scale in ipairs({0.75, 0.50, 0.25}) do
		for _, sideOffset in ipairs({0, 160, -160, 320, -320}) do
			local candidate = Geometry.MakeVector(
				(botLocation.x or 0) + directionX * distance * scale + sideX * sideOffset,
				(botLocation.y or 0) + directionY * distance * scale + sideY * sideOffset,
				botLocation.z or ancientLocation.z or 0)
			if (type(IsLocationPassable) ~= 'function'
			or Safe(false, function() return IsLocationPassable(candidate) end))
			and IsOutsideTowerSnapshots(candidate, snapshots)
			then
				return candidate, false
			end
		end
	end
	return nil, false
end

function TowerSafety.Scan(bot, options)
	options = options or {}
	local result = {
		triggered = false,
		reasons = {},
		allZones = {},
		containingZones = {},
		routeZones = {},
		anchor = nil,
		anchorExtended = false,
		anchorDistance = 0,
		incomingCount = 0,
		unseenIncoming = false,
		recentTowerDamage = false,
		highGroundAssaultBypassCount = 0,
		teamfightPriorityBypassCount = 0,
		highGroundAttackRangeCount = 0,
		multipleHighGroundAnchorFallback = false,
	}
	if not IsValidUnit(bot) then return result end

	local botLocation = bot:GetLocation()
	local snapshots = GetTowerSnapshots(bot)
	-- 复用本次可见塔快照；普通兵线任务不能继承团战/围攻的塔圈绕过授权。
	result.visibleTowers = snapshots
	local highLevelTeamfight = type(options.highLevelTeamfight) == 'table'
	local highGroundAttackRangeCount = highLevelTeamfight
		and CountHighGroundAttackRanges(botLocation, snapshots) or 0
	local maxHighGroundTowers = math.max(0,
		tonumber(Config.HIGH_LEVEL_TEAMFIGHT_MAX_HIGH_GROUND_TOWERS) or 1)
	local teamfightPriorityActive = highLevelTeamfight
		and highGroundAttackRangeCount <= maxHighGroundTowers
	local forceMultipleHighGroundEscape = highLevelTeamfight
		and highGroundAttackRangeCount > maxHighGroundTowers
	result.highGroundAttackRangeCount = highGroundAttackRangeCount
	local incomingByKey, unseenIncoming = GetIncomingTowerAttacks(bot)
	local recentTowerDamage = Safe(false, function()
		return bot:WasRecentlyDamagedByTower(Config.RECENT_TOWER_DAMAGE_TIME)
	end)
	local navigationSnapshots = {}
	for _, snapshot in ipairs(snapshots) do
		if teamfightPriorityActive then
			-- 高等级团战只在多座高地塔重叠时恢复规避；普通塔和单座高地塔不抢占团战。
		elseif not forceMultipleHighGroundEscape and IsAuthorizedHighGroundTower(snapshot, options) then
			result.highGroundAssaultBypassCount = result.highGroundAssaultBypassCount + 1
		else
			table.insert(navigationSnapshots, snapshot)
		end
	end
	local anchor, anchorExtended = BuildAnchor(bot, navigationSnapshots)
	if forceMultipleHighGroundEscape and anchor == nil then
		-- 多高地塔重叠时不能因短距离候选全部落在塔圈内而放弃租约；己方 Ancient 是保守外撤方向。
		anchor = GetOwnAncientLocation(bot)
		result.multipleHighGroundAnchorFallback = anchor ~= nil
	end
	local activeMode = Safe(BOT_MODE_NONE, function() return bot:GetActiveMode() end)
	local attackTarget = Safe(nil, function() return bot:GetAttackTarget() end)
	local chasingHero = IsDiveMode(activeMode) and IsVisibleEnemyHero(bot, attackTarget)
	local attackTargetLocation = chasingHero
		and Safe(nil, function() return attackTarget:GetLocation() end) or nil

	for _, snapshot in ipairs(snapshots) do
		local bypassedForTeamfight = teamfightPriorityActive
		local bypassedForAssault = not forceMultipleHighGroundEscape
			and IsAuthorizedHighGroundTower(snapshot, options)
		snapshot.incomingCount = incomingByKey[snapshot.key] or 0
		snapshot.inside = Geometry.PointInCircle(botLocation, snapshot, 0)
		snapshot.routeIntersects = anchor ~= nil
			and Geometry.SegmentIntersectsCircle(botLocation, anchor, snapshot, 0)
		snapshot.recentlyDamaged = recentTowerDamage
			and Geometry.Distance(botLocation, snapshot.center) <= snapshot.effectiveRadius + 350
		snapshot.chasingHero = attackTargetLocation ~= nil
			and Geometry.PointInCircle(attackTargetLocation, snapshot, 0)
			and (snapshot.inside or snapshot.routeIntersects)
		local relevantForTeamfightBypass = snapshot.locked
			or snapshot.incomingCount > 0
			or snapshot.recentlyDamaged
			or snapshot.chasingHero
			or snapshot.inside
			or snapshot.routeIntersects
		if bypassedForTeamfight then
			if relevantForTeamfightBypass then
				result.teamfightPriorityBypassCount = result.teamfightPriorityBypassCount + 1
			end
		elseif not bypassedForAssault then
			if snapshot.locked then table.insert(result.reasons, 'tower_locked:' .. snapshot.key) end
			if snapshot.incomingCount > 0 then table.insert(result.reasons, 'tower_projectile:' .. snapshot.key) end
			if snapshot.recentlyDamaged then table.insert(result.reasons, 'recent_tower_damage:' .. snapshot.key) end
			if snapshot.chasingHero then table.insert(result.reasons, 'hero_dive:' .. snapshot.key) end
			if snapshot.locked or snapshot.incomingCount > 0
			or snapshot.recentlyDamaged or snapshot.chasingHero
			then
				result.triggered = true
			end
			if snapshot.inside then table.insert(result.containingZones, snapshot) end
			if snapshot.routeIntersects then table.insert(result.routeZones, snapshot) end
			result.incomingCount = result.incomingCount + snapshot.incomingCount
			if snapshot.recentlyDamaged then result.recentTowerDamage = true end
			table.insert(result.allZones, snapshot)
		end
	end
	if forceMultipleHighGroundEscape then
		result.triggered = true
		table.insert(result.reasons,
			'multiple_high_ground_towers:' .. tostring(highGroundAttackRangeCount))
	end

	result.anchor = anchor
	result.anchorExtended = anchorExtended == true
	result.anchorDistance = anchor ~= nil and Geometry.Distance(botLocation, anchor) or 0
	result.unseenIncoming = unseenIncoming
	if result.highGroundAssaultBypassCount == 0
	and result.teamfightPriorityBypassCount == 0
	then
		-- 默认路径继续保留“塔暂时不可见但刚受到塔伤”时的失败关闭语义。
		result.recentTowerDamage = recentTowerDamage
	end
	if unseenIncoming then
		result.triggered = true
		table.insert(result.reasons, 'unseen_tower_projectile')
	end
	return result
end

return TowerSafety
