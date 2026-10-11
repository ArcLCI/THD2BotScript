-- 基地压力事实独立于推进控制，供防守/资源/游走读取。
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Buildings=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/building_rules')
local ExecutionConfig=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Strategy={ENABLED=true,BASE_PRESSURE_LAST_SEEN_AGE=5,BASE_PRESSURE_RADIUS=4500,
    BASE_TOWER_CRITICAL_RADIUS=700,BASE_ANCIENT_CRITICAL_RADIUS=1200}
local BUILDING_DESCRIPTORS=Buildings.DESCRIPTORS
local ResolveDescriptorBuilding=Buildings.ResolveDescriptorBuilding
local baseThreatEvidence,lastBaseThreatSnapshots={},{}
local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function GetTeamKey()
	return Safe(nil, function() return GetTeam() end)
end

local function GetNow()
	return Safe(0, function() return DotaTime() end) or 0
end

local function GetLocationDistance(first, second)
	if first == nil or second == nil then return math.huge end
	local dx = (first.x or 0) - (second.x or 0)
	local dy = (first.y or 0) - (second.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function IsOwnBaseBuildingUnderAttack(team)
	if team == nil or J.Utils == nil or J.Utils.IsBuildingAttackedByEnemy == nil then return false end
	for _, descriptor in ipairs(BUILDING_DESCRIPTORS) do
		if descriptor.tier >= 3 then
			local building = ResolveDescriptorBuilding(team, descriptor)
			if building ~= nil
			and Safe(false, function() return J.Utils.IsBuildingAttackedByEnemy(building) ~= nil end)
			then
				return true, descriptor.kind, building
			end
		end
	end
	local ancient = Safe(nil, function() return GetAncient(team) end)
	if ancient ~= nil
	and Safe(false, function() return J.Utils.IsBuildingAttackedByEnemy(ancient) ~= nil end)
	then
		return true, 'ancient', ancient
	end
	return false, nil
end

local function HasCriticalBaseIntrusion(team, ancient)
	if team == nil or ancient == nil then return true, 'ancient_unknown' end
	for _, towerID in ipairs({TOWER_BASE_1, TOWER_BASE_2}) do
		local tower = towerID ~= nil and Safe(nil, function() return GetTower(team, towerID) end) or nil
		if tower ~= nil
		and (tonumber(Safe(0, function()
			return J.CountLastSeenEnemiesNearLoc(
				tower:GetLocation(), Strategy.BASE_TOWER_CRITICAL_RADIUS,
				Strategy.BASE_PRESSURE_LAST_SEEN_AGE)
		end)) or 0) > 0
		then
			return true, 'base_t4'
		end
	end
	if (tonumber(Safe(0, function()
		return J.CountLastSeenEnemiesNearLoc(
			ancient:GetLocation(), Strategy.BASE_ANCIENT_CRITICAL_RADIUS,
			Strategy.BASE_PRESSURE_LAST_SEEN_AGE)
	end)) or 0) > 0
	then
		return true, 'ancient'
	end
	return false, nil
end

local function BuildBaseThreatSnapshot(now, bot)
	local team = GetTeamKey()
	if team == nil then
		return {
			hardEmergency = true,
			coveredPressure = false,
			status = 'hard',
			reason = 'team_unknown',
			enemyCount = 0,
			effectiveAllyCount = 0,
		}
	end
	local cached = lastBaseThreatSnapshots[team]
	if cached ~= nil and cached.sampledAt == now then return cached end

	local ancient = Safe(nil, function() return GetAncient(team) end)
	if ancient == nil then
		cached = {
			sampledAt = now,
			hardEmergency = true,
			coveredPressure = false,
			status = 'hard',
			reason = 'ancient_unknown',
			enemyCount = 0,
			effectiveAllyCount = 0,
		}
		lastBaseThreatSnapshots[team] = cached
		return cached
	end

	local ancientLocation = Safe(nil, function() return ancient:GetLocation() end)
	if ancientLocation == nil then
		cached = {
			sampledAt = now,
			hardEmergency = true,
			coveredPressure = false,
			status = 'hard',
			reason = 'ancient_location_unknown',
			enemyCount = 0,
			effectiveAllyCount = 0,
		}
		lastBaseThreatSnapshots[team] = cached
		return cached
	end
	local enemyHeroCount = tonumber(Safe(0, function()
		return J.CountLastSeenEnemiesNearLoc(
			ancientLocation, Strategy.BASE_PRESSURE_RADIUS, Strategy.BASE_PRESSURE_LAST_SEEN_AGE)
	end)) or 0
	local enemyTpCount = #(Safe({}, function()
		return J.Utils.GetEnemyIdsInTpToLocation(ancientLocation, Strategy.BASE_PRESSURE_RADIUS)
	end) or {})
	local allyHeroCount = #(Safe({}, function()
		return J.GetAlliesNearLoc(ancientLocation, Strategy.BASE_PRESSURE_RADIUS)
	end) or {})
	local allyTpCount = #(Safe({}, function()
		return J.Utils.GetAllyIdsInTpToLocation(ancientLocation, Strategy.BASE_PRESSURE_RADIUS)
	end) or {})
	local enemyCount = enemyHeroCount + enemyTpCount
	local effectiveAllyCount = allyHeroCount + allyTpCount
	local criticalIntrusion, intrusionReason = HasCriticalBaseIntrusion(team, ancient)
	local buildingUnderAttack, attackedKind, attackedBuilding = IsOwnBaseBuildingUnderAttack(team)
	local hardEmergency = buildingUnderAttack
		or criticalIntrusion
	-- 外围无人覆盖不等于基地遭攻击；不能因此撤销全队正在执行的推进。
	local peripheralPressure = enemyCount > effectiveAllyCount and not hardEmergency
	local coveredPressure = enemyCount > 0 and not hardEmergency and not peripheralPressure
	local reason = 'none'
	if buildingUnderAttack then
		reason = 'building_attacked_' .. tostring(attackedKind or 'unknown')
	elseif criticalIntrusion then
		reason = 'critical_intrusion_' .. tostring(intrusionReason or 'unknown')
	elseif enemyCount > effectiveAllyCount then
		reason = 'uncovered_' .. tostring(enemyCount) .. '_vs_' .. tostring(effectiveAllyCount)
	elseif coveredPressure then
		reason = 'covered_' .. tostring(enemyCount) .. '_vs_' .. tostring(effectiveAllyCount)
	end

	cached = {
		sampledAt = now,
		enemyHeroCount = enemyHeroCount,
		enemyTpCount = enemyTpCount,
		enemyCount = enemyCount,
		allyHeroCount = allyHeroCount,
		allyTpCount = allyTpCount,
		effectiveAllyCount = effectiveAllyCount,
		criticalIntrusion = criticalIntrusion,
		buildingUnderAttack = buildingUnderAttack,
		hardEmergency = hardEmergency,
		coveredPressure = coveredPressure,
		peripheralPressure = peripheralPressure,
		status = hardEmergency and 'hard' or (peripheralPressure and 'peripheral' or (coveredPressure and 'covered' or 'none')),
		reason = reason,
	}
	lastBaseThreatSnapshots[team] = cached
	-- 与旧Strategy.DEBUG分离；R系列验收需要知道具体触发依据，不能只看到hard标签。
	local previous=baseThreatEvidence[team]
	if ExecutionConfig.DEBUG and (not previous or previous.reason~=reason
		or ((hardEmergency or enemyCount>0) and now-previous.at>=2)) then
		baseThreatEvidence[team]={reason=reason,at=now}
		local seen={}
		for _,id in ipairs(GetTeamPlayers(GetOpposingTeam()) or {}) do
			local info=Safe(nil,function() return GetHeroLastSeenInfo(id) end)
			info=info and info[1]
			if info and info.location and IsHeroAlive(id) and info.time_since_seen<=Strategy.BASE_PRESSURE_LAST_SEEN_AGE
			and GetLocationDistance(info.location,ancientLocation)<=Strategy.BASE_PRESSURE_RADIUS then
				seen[#seen+1]=string.format('%s@%.0f,%.0f:age%.1f:dist%.0f',id,info.location.x,info.location.y,info.time_since_seen,GetLocationDistance(info.location,ancientLocation))
			end
		end
		print(string.format('[BOT][BaseThreat] run=%s time=%.3f team=%s status=%s reason=%s enemy=%d enemy_tp=%d allies=%d ally_tp=%d building=%s building_hp=%s intrusion=%s ancient_x=%.0f ancient_y=%.0f radius=%d last_seen_age=%.1f seen=%s',
			ExecutionConfig.RUN_ID,now,team,cached.status,reason,enemyHeroCount,enemyTpCount,allyHeroCount,allyTpCount,
			tostring(attackedKind),tostring(attackedBuilding and Safe(-1,function() return attackedBuilding:GetHealth() end)),tostring(intrusionReason),
			ancientLocation.x,ancientLocation.y,Strategy.BASE_PRESSURE_RADIUS,Strategy.BASE_PRESSURE_LAST_SEEN_AGE,table.concat(seen,'|')))
	end
	return cached
end


function Strategy.IsEnabled() return Strategy.ENABLED end
function Strategy.GetBaseThreatSnapshot(state, bot)
	if not Strategy.IsEnabled() then return nil end
	if type(state) == 'table' and type(state.baseThreat) == 'table' then return state.baseThreat end
	if type(state) == 'table' then
		local hardEmergency = state.baseDefenseRequired == true
		local coveredPressure = state.basePressureCovered == true and not hardEmergency
		return {
			hardEmergency = hardEmergency,
			coveredPressure = coveredPressure,
			status = hardEmergency and 'hard' or (coveredPressure and 'covered' or 'none'),
			reason = 'caller_state',
			enemyCount = tonumber(state.baseEnemyCount) or 0,
			effectiveAllyCount = tonumber(state.effectiveBaseAllies) or 0,
		}
	end
	return BuildBaseThreatSnapshot(GetNow(), bot)
end

return Strategy
