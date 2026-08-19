
local Illusion = dofile(GetScriptDirectory()..'/thd2_illusion')
local Scheduler = require(GetScriptDirectory()..'/thd2_scheduler')
local npcBot = GetBot()

local MINION_THINK_INTERVAL = 0.3
local MINION_THINK_STAGGER = 0.03

local function GetMinionTaskName(hMinionUnit)
	if hMinionUnit == nil then return 'minion_think_nil' end
	if hMinionUnit.entindex ~= nil then
		local ok, result = pcall(function() return hMinionUnit:entindex() end)
		if ok and result ~= nil then return 'minion_think_ent_' .. tostring(result) end
	end
	if hMinionUnit.GetUnitName ~= nil then
		local ok, result = pcall(function() return hMinionUnit:GetUnitName() end)
		if ok and result ~= nil then return 'minion_think_name_' .. tostring(result) end
	end
	return 'minion_think_' .. tostring(hMinionUnit)
end

local function IsNullMinion(hMinionUnit)
	if hMinionUnit == nil then return true end
	if hMinionUnit.IsNull == nil then return false end
	local ok, result = pcall(function() return hMinionUnit:IsNull() end)
	return ok and result == true
end

local function ShouldRunMinionThink(hMinionUnit)
	if IsNullMinion(hMinionUnit) then return false end
	if hMinionUnit.IsAlive ~= nil then
		local ok, alive = pcall(function() return hMinionUnit:IsAlive() end)
		if not ok or alive ~= true then return false end
	end
	local taskName = GetMinionTaskName(hMinionUnit)
	local phaseInterval = MINION_THINK_STAGGER
	return Scheduler.ShouldRunBotTask(hMinionUnit, taskName, MINION_THINK_INTERVAL, phaseInterval)
end

function THD2MinionThink( hMinionUnit )
	if not ShouldRunMinionThink(hMinionUnit) then return end
	Illusion.IllusionThink(npcBot, hMinionUnit)
	Illusion.DemonThink(npcBot, hMinionUnit)
end

function THD2DemonThink( hMinionUnit )
	if not ShouldRunMinionThink(hMinionUnit) then return end
	Illusion.DemonThink(npcBot, hMinionUnit)
end
