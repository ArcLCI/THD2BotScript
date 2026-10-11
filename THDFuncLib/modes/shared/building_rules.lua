-- 共享建筑规则与只读风险基础数据；不分配成员、不维护推进目标或租约。
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local B={HIGH_GROUND_MAX_TOWER_DAMAGE_RATIO=0.35}
local infoCache=setmetatable({}, {__mode='k'})
local BUILDING_DESCRIPTORS = {
	{kind = 'top_t1', tier = 1, lane = LANE_TOP, buildingType = 'tower', id = TOWER_TOP_1},
	{kind = 'top_t2', tier = 2, lane = LANE_TOP, buildingType = 'tower', id = TOWER_TOP_2},
	{kind = 'top_t3', tier = 3, lane = LANE_TOP, buildingType = 'tower', id = TOWER_TOP_3},
	{kind = 'mid_t1', tier = 1, lane = LANE_MID, buildingType = 'tower', id = TOWER_MID_1},
	{kind = 'mid_t2', tier = 2, lane = LANE_MID, buildingType = 'tower', id = TOWER_MID_2},
	{kind = 'mid_t3', tier = 3, lane = LANE_MID, buildingType = 'tower', id = TOWER_MID_3},
	{kind = 'bot_t1', tier = 1, lane = LANE_BOT, buildingType = 'tower', id = TOWER_BOT_1},
	{kind = 'bot_t2', tier = 2, lane = LANE_BOT, buildingType = 'tower', id = TOWER_BOT_2},
	{kind = 'bot_t3', tier = 3, lane = LANE_BOT, buildingType = 'tower', id = TOWER_BOT_3},
	{kind = 'top_melee_rax', tier = 3, lane = LANE_TOP, buildingType = 'barracks', id = BARRACKS_TOP_MELEE},
	{kind = 'top_ranged_rax', tier = 3, lane = LANE_TOP, buildingType = 'barracks', id = BARRACKS_TOP_RANGED},
	{kind = 'mid_melee_rax', tier = 3, lane = LANE_MID, buildingType = 'barracks', id = BARRACKS_MID_MELEE},
	{kind = 'mid_ranged_rax', tier = 3, lane = LANE_MID, buildingType = 'barracks', id = BARRACKS_MID_RANGED},
	{kind = 'bot_melee_rax', tier = 3, lane = LANE_BOT, buildingType = 'barracks', id = BARRACKS_BOT_MELEE},
	{kind = 'bot_ranged_rax', tier = 3, lane = LANE_BOT, buildingType = 'barracks', id = BARRACKS_BOT_RANGED},
	{kind = 'base_t4_1', tier = 4, buildingType = 'tower', id = TOWER_BASE_1},
	{kind = 'base_t4_2', tier = 4, buildingType = 'tower', id = TOWER_BASE_2},
}

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function CanInspectUnit(unit)
	if unit == nil then return false end
	local ok, visible = pcall(function()
		if unit.IsNull ~= nil and unit:IsNull() then return false end
		if unit.CanBeSeen == nil or not unit:CanBeSeen() then return false end
		return unit.IsAlive == nil or unit:IsAlive()
	end)
	return ok and visible == true
end

local function ResolveDescriptorBuilding(team, descriptor)
	if team == nil or descriptor == nil or descriptor.id == nil then return nil end
	if descriptor.buildingType == 'tower' then
		return Safe(nil, function() return GetTower(team, descriptor.id) end)
	end
	if descriptor.buildingType == 'barracks' then
		return Safe(nil, function() return GetBarracks(team, descriptor.id) end)
	end
	return nil
end

local function GetManagedBuildingInfo(target, team)
	if target == nil then return nil end
	if infoCache[target] then return infoCache[target] end
	team = team or Safe(nil, function() return GetOpposingTeam() end)
	for _, descriptor in ipairs(BUILDING_DESCRIPTORS) do
		if ResolveDescriptorBuilding(team, descriptor) == target then infoCache[target]=descriptor;return descriptor end
	end
	local ancient = team ~= nil and Safe(nil, function() return GetAncient(team) end) or nil
	if ancient == target then
		infoCache[target]={kind='ancient',tier=4,buildingType='ancient'};return infoCache[target]
	end
	return nil
end

local function HasManagedBackdoorProtection(target)
	-- Bot API 不允许读取不可见建筑的 modifier；不可读时按仍受保护处理。
	if not CanInspectUnit(target) then return true end
	for _, modifierName in ipairs({
		'modifier_fountain_glyph',
		'modifier_backdoor_protection',
		'modifier_backdoor_protection_in_base',
		'modifier_backdoor_protection_active',
	}) do
		if Safe(false, function() return target:HasModifier(modifierName) end) then return true end
	end
	local info = GetManagedBuildingInfo(target)
	if info ~= nil and info.tier >= 2 then
		local antiBackdoorStopped = Safe(nil, function()
			return target:HasModifier('modifier_thdots_anti_bd_stop')
		end)
		return antiBackdoorStopped ~= true
	end
	return false
end

local function GetActualBotAverageLevel(team, includeHumans)
	local players = Safe({}, function() return GetTeamPlayers(team) end) or {}
	local total = 0
	local botCount = 0
	local heroCount = 0
	for _, playerID in ipairs(players) do
		local isBot = Safe(nil, function() return IsPlayerBot(playerID) end)
		if type(isBot) ~= 'boolean' then return nil, nil end
		if isBot then botCount=botCount+1 end
		if isBot or includeHumans then
			local level = Safe(nil, function() return GetHeroLevel(playerID) end)
			if type(level) ~= 'number' or level < 1 then return nil, nil end
			total = total + level
			heroCount = heroCount + 1
		end
	end
	-- 己方上高等级仍按Bot阵容；敌方比较必须含真人，否则纯真人队永远返回未知。
	if heroCount == 0 then return nil, botCount end
	return total / heroCount, botCount
end


B.DESCRIPTORS=BUILDING_DESCRIPTORS
B.ResolveDescriptorBuilding=ResolveDescriptorBuilding
B.GetManagedBuildingInfo=GetManagedBuildingInfo
B.HasManagedBackdoorProtection=HasManagedBackdoorProtection
function B.CanControlledUnitAttackBuilding(owner,target)
    return target~=nil and CanInspectUnit(target) and J.CanBeAttacked(target)
        and not HasManagedBackdoorProtection(target),'map_building_rules'
end
function B.GetStrictTeamAverageLevel()
    return GetActualBotAverageLevel(GetTeam())
end
return B
