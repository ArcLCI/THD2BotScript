require(GetScriptDirectory() .. "/bot_generic")

local Scheduler = require(GetScriptDirectory() .. "/thd2_scheduler")
local bot = GetBot()

local SUIKA_MINION_NAME = "npc_dota_suika_03_smallsuika"
local SUIKA_MINION_RANGE = 500
local SUIKA_MINION_INTERVAL = 0.3
local SUIKA_MINION_STAGGER = 0.03

local function SafeCall(defaultValue, fn)
	local ok, result = pcall(fn)
	if ok and result ~= nil then return result end
	return defaultValue
end

local function IsValidUnit(unit)
	return unit ~= nil
		and not SafeCall(false, function() return unit:IsNull() end)
		and SafeCall(false, function() return unit:IsAlive() end)
end

local function GetVisibleUnitDistance(unit, target)
	if not IsValidUnit(unit) or not IsValidUnit(target) then return math.huge end
	if not SafeCall(false, function() return target:CanBeSeen() end) then return math.huge end
	local ok, distance = pcall(function()
		if not target:CanBeSeen() then return nil end
		return GetUnitToUnitDistance(unit, target)
	end)
	return ok and type(distance) == "number" and distance or math.huge
end

local function IsVisibleAttackTarget(unit, target)
	if not IsValidUnit(unit) or not IsValidUnit(target) then return false end
	if SafeCall(unit:GetTeam(), function() return target:GetTeam() end) == unit:GetTeam() then return false end
	if not SafeCall(false, function() return target:CanBeSeen() end) then return false end
	if SafeCall(false, function() return target:IsInvulnerable() end) then return false end
	if SafeCall(false, function() return target:IsAttackImmune() end) then return false end
	return GetVisibleUnitDistance(unit, target) <= SUIKA_MINION_RANGE
end

local function FindClosestTarget(unit, targets)
	local closest = nil
	local closestDistance = math.huge
	for _, target in pairs(targets or {}) do
		if IsVisibleAttackTarget(unit, target) then
			local distance = GetVisibleUnitDistance(unit, target)
			if distance < closestDistance then
				closest = target
				closestDistance = distance
			end
		end
	end
	return closest
end

local function IsSuikaMinion(unit)
	if not IsValidUnit(unit) then return false end
	return SafeCall("", function() return unit:GetUnitName() end) == SUIKA_MINION_NAME
end

local function IsControlledSuikaMinion(unit)
	if not IsSuikaMinion(unit) then return false end
	-- auto 模式没有玩家控制权；只接管控制模式，避免与游戏侧 Think 双重发单。
	return SafeCall(-1, function() return unit:GetPlayerID() end)
		== SafeCall(-2, function() return bot:GetPlayerID() end)
end

local function GetTaskName(unit)
	return "suika_minion_" .. tostring(SafeCall(unit, function() return unit:entindex() end))
end

local function SuikaMinionThink(unit)
	if not Scheduler.ShouldRunBotTask(unit, GetTaskName(unit), SUIKA_MINION_INTERVAL, SUIKA_MINION_STAGGER) then return end

	local currentTarget = SafeCall(nil, function() return unit:GetAttackTarget() end)
	if IsVisibleAttackTarget(unit, currentTarget)
	and SafeCall(false, function() return currentTarget:IsHero() end)
	then
		return
	end

	-- 与游戏侧 auto 模式一致：英雄优先，附近没有英雄时才攻击基础单位。
	local target = FindClosestTarget(unit, unit:GetNearbyHeroes(SUIKA_MINION_RANGE, true, BOT_MODE_NONE))
	if target == nil and IsVisibleAttackTarget(unit, currentTarget) then target = currentTarget end
	if target == nil then target = FindClosestTarget(unit, unit:GetNearbyCreeps(SUIKA_MINION_RANGE, true)) end

	if target ~= nil then
		if target ~= currentTarget then unit:Action_AttackUnit(target, true) end
	elseif currentTarget ~= nil then
		unit:Action_ClearActions(false)
	end
end

function MinionThink(hMinionUnit)
	if IsSuikaMinion(hMinionUnit) then
		if IsControlledSuikaMinion(hMinionUnit) then SuikaMinionThink(hMinionUnit) end
		-- auto 模式已由游戏侧 ContextThink 控制，不能再交给通用召唤物逻辑发单。
		return
	end
	THD2MinionThink(hMinionUnit)
end
