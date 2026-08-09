local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local configLoaded, Config = pcall(require, GetScriptDirectory()..'/THDFuncLib/roam_config')
if not configLoaded or type(Config) ~= 'table' then Config = {} end
local Auxiliary = require(GetScriptDirectory()..'/THDFuncLib/roam_auxiliary')

local bot = GetBot()
local activeProvider = nil
local pendingProvider = nil
local Gank = nil

local function IsGankEnabled()
	if type(Config.IsEnabled) ~= 'function' then return false end
	local ok, enabled = pcall(Config.IsEnabled)
	return ok and enabled == true
end

local function GetGankProvider()
	if Gank == nil then Gank = require(GetScriptDirectory()..'/THDFuncLib/roam_gank') end
	return Gank
end

local function StopGank(reason)
	if Gank ~= nil then Gank.Abort(bot, reason) end
end

function GetDesire()
	-- 现有持续施法、英雄连招和拾取租约始终优先，不受新 gank 总开关影响。
	local auxiliaryDesire = Auxiliary.GetDesire(bot)
	if auxiliaryDesire ~= nil and auxiliaryDesire > BOT_MODE_DESIRE_NONE then
		pendingProvider = 'auxiliary'
		if activeProvider == 'gank' then
			StopGank('auxiliary_preempted')
			activeProvider = 'auxiliary'
			Auxiliary.OnStart(bot)
		end
		return auxiliaryDesire
	end

	-- 辅助租约释放后先退出一次 ROAM，避免直接续接一份陈旧 gank 任务。
	if activeProvider == 'auxiliary' then
		pendingProvider = nil
		return BOT_MODE_DESIRE_NONE
	end
	if not Utils.AllowModeDesire(bot, 'roam') then
		if activeProvider == 'gank' then StopGank('mode_unavailable') end
		pendingProvider = nil
		return BOT_MODE_DESIRE_NONE
	end

	if not IsGankEnabled() then
		if activeProvider == 'gank' then StopGank('disabled') end
		pendingProvider = nil
		return BOT_MODE_DESIRE_NONE
	end

	local desire = GetGankProvider().GetDesire(bot)
	if desire ~= nil and desire > BOT_MODE_DESIRE_NONE then
		pendingProvider = 'gank'
	else
		pendingProvider = nil
	end
	return desire or BOT_MODE_DESIRE_NONE
end

function OnStart()
	Utils.NoteModeStart(bot, 'roam')
	activeProvider = pendingProvider
	if activeProvider == 'auxiliary' then
		Auxiliary.OnStart(bot)
	elseif activeProvider == 'gank' then
		GetGankProvider().OnStart(bot)
	end
end

function OnEnd()
	if activeProvider == 'gank' and Gank ~= nil then Gank.OnEnd(bot, 'mode_end') end
	Auxiliary.OnEnd(bot)
	activeProvider = nil
	pendingProvider = nil
end

function Think()
	-- Think 再检查一次独占辅助任务，确保技能前摇/引导不会被同模式的 gank 动作覆盖。
	local auxiliaryDesire = Auxiliary.GetDesire(bot)
	if auxiliaryDesire ~= nil and auxiliaryDesire > BOT_MODE_DESIRE_NONE then
		if activeProvider == 'gank' then StopGank('auxiliary_preempted') end
		if activeProvider ~= 'auxiliary' then Auxiliary.OnStart(bot) end
		activeProvider = 'auxiliary'
		pendingProvider = 'auxiliary'
		Auxiliary.Think(bot)
		return
	end
	if activeProvider == 'auxiliary' then return end
	if not Utils.AllowModeDesire(bot, 'roam') then
		if activeProvider == 'gank' then StopGank('mode_unavailable') end
		return
	end

	if not IsGankEnabled() then
		if activeProvider == 'gank' then StopGank('disabled') end
		return
	end

	local provider = activeProvider or pendingProvider
	if provider == 'gank' then
		if activeProvider == nil then
			activeProvider = 'gank'
			GetGankProvider().OnStart(bot)
		end
		GetGankProvider().Think(bot)
	end
end

-- 保留旧模式脚本暴露的全局物品查询，避免英雄技能脚本的加载顺序发生变化。
function IsItemAvailable(itemName)
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and item:GetName() == itemName then return item end
	end
	return nil
end
