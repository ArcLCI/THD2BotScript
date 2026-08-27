local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local configLoaded, Config = pcall(require, GetScriptDirectory()..'/THDFuncLib/roam_config')
if not configLoaded or type(Config) ~= 'table' then Config = {} end
local Auxiliary = require(GetScriptDirectory()..'/THDFuncLib/roam_auxiliary')
local ModeDesireDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_desire_debug')
local RoamDebug = require(GetScriptDirectory()..'/THDFuncLib/roam_debug')

local bot = GetBot()
local activeProvider = nil
local pendingProvider = nil
local activeAuxiliarySource = 'none'
local pendingAuxiliarySource = 'none'
local Gank = nil
local routerDebugState = {}

local function RefreshBot()
	if type(GetBot) ~= 'function' then return nil end
	local ok, current = pcall(GetBot)
	if not ok or current == nil then return nil end
	bot = current
	return current
end

local function FormatDotaClock(value)
	if type(value) ~= 'number' then return 'unknown' end
	local sign = value < 0 and '-' or ''
	local tenths = math.floor(math.abs(value) * 10 + 0.5)
	local minutes = math.floor(tenths / 600)
	local seconds = (tenths % 600) / 10
	return string.format('%s%02d:%04.1f', sign, minutes, seconds)
end

local function IsGankEnabled()
	if type(Config.IsEnabled) ~= 'function' then return false end
	local ok, enabled = pcall(Config.IsEnabled)
	return ok and enabled == true
end

local function GetGankProvider()
	if Gank == nil then Gank = require(GetScriptDirectory()..'/THDFuncLib/roam_gank') end
	return Gank
end

local function RouterDebugStatus(message, force)
	if Config.DEBUG ~= true then return end
	local currentBot = RefreshBot()
	local now = -9999
	local timeOk, currentTime = pcall(DotaTime)
	if timeOk and type(currentTime) == 'number' then now = currentTime end
	local shouldLog, event = RoamDebug.ShouldLogStatus(routerDebugState, message, now,
		Config.DEBUG_STATUS_HEARTBEAT_INTERVAL, force)
	if not shouldLog then return end
	local playerID = -1
	local idOk, id = pcall(function() return currentBot:GetPlayerID() end)
	if idOk and id ~= nil then playerID = id end
	local gameOk, gameTime = pcall(GameTime)
	if not gameOk or type(gameTime) ~= 'number' then gameTime = currentTime end
	local dotaValue = timeOk and type(currentTime) == 'number'
		and string.format('%.1f', currentTime) or 'unknown'
	local gameValue = type(gameTime) == 'number' and string.format('%.1f', gameTime) or 'unknown'
	print('[BOT][Roam] schema=2 pid=' .. tostring(playerID) .. ' router event=' .. tostring(event)
		.. ' ' .. tostring(message)
		.. ' dota_time=' .. dotaValue
		.. ' game_time=' .. gameValue
		.. ' dota_clock=' .. (timeOk and FormatDotaClock(currentTime) or 'unknown'))
end

local function StopGank(reason, auxiliarySource, auxiliaryDesire)
	local currentBot = RefreshBot()
	if Gank ~= nil then
		Gank.Abort(currentBot, reason, {
			auxProvider = auxiliarySource or 'none',
			auxDesire = auxiliaryDesire,
		})
	end
end

-- DEBUG 开启后在加载阶段就给出存活信号，避免资格检查前的路由拦截成为日志盲区。
RouterDebugStatus('loaded enabled=' .. tostring(IsGankEnabled()), true)

function GetDesire()
	local currentBot = RefreshBot()
	if currentBot == nil then return BOT_MODE_DESIRE_NONE end
	-- 每个 Bot 各自输出当前实际模式倾向，供赛后合并为统一时间序列。
	ModeDesireDebug.Think(currentBot)
	-- 现有持续施法、英雄连招和拾取租约始终优先，不受新 gank 总开关影响。
	local auxiliaryDesire, auxiliarySource = Auxiliary.GetDesire(currentBot)
	if auxiliaryDesire ~= nil and auxiliaryDesire > BOT_MODE_DESIRE_NONE then
		auxiliarySource = auxiliarySource or 'unknown'
		RouterDebugStatus('reason=auxiliary_active provider=' .. tostring(auxiliarySource)
			.. ' desire=' .. tostring(auxiliaryDesire))
		pendingProvider = 'auxiliary'
		pendingAuxiliarySource = auxiliarySource
		if activeProvider == 'gank' then
			StopGank('auxiliary_preempted', auxiliarySource, auxiliaryDesire)
			activeProvider = 'auxiliary'
			activeAuxiliarySource = auxiliarySource
			Auxiliary.OnStart(currentBot)
		end
		return auxiliaryDesire
	end

	-- 辅助租约释放后先退出一次 ROAM，避免直接续接一份陈旧 gank 任务。
	if activeProvider == 'auxiliary' then
		RouterDebugStatus('reason=auxiliary_release_frame provider=' .. tostring(activeAuxiliarySource))
		pendingProvider = nil
		pendingAuxiliarySource = 'none'
		return BOT_MODE_DESIRE_NONE
	end
	if not Utils.AllowModeDesire(currentBot, 'roam') then
		RouterDebugStatus('reason=mode_switch_lock')
		if activeProvider == 'gank' then StopGank('mode_unavailable') end
		pendingProvider = nil
		return BOT_MODE_DESIRE_NONE
	end

	if not IsGankEnabled() then
		RouterDebugStatus('reason=disabled_or_invalid_config')
		if activeProvider == 'gank' then StopGank('disabled') end
		pendingProvider = nil
		return BOT_MODE_DESIRE_NONE
	end

	local desire = GetGankProvider().GetDesire(currentBot)
	if desire ~= nil and desire > BOT_MODE_DESIRE_NONE then
		pendingProvider = 'gank'
	else
		pendingProvider = nil
	end
	return desire or BOT_MODE_DESIRE_NONE
end

function OnStart()
	local currentBot = RefreshBot()
	if currentBot == nil then return end
	Utils.NoteModeStart(currentBot, 'roam')
	activeProvider = pendingProvider
	if activeProvider == 'auxiliary' then
		activeAuxiliarySource = pendingAuxiliarySource
		Auxiliary.OnStart(currentBot)
	elseif activeProvider == 'gank' then
		GetGankProvider().OnStart(currentBot)
	end
end

function OnEnd()
	local currentBot = RefreshBot()
	if currentBot == nil then return end
	if activeProvider == 'gank' and Gank ~= nil then Gank.OnEnd(currentBot, 'mode_end') end
	Auxiliary.OnEnd(currentBot)
	activeProvider = nil
	pendingProvider = nil
	activeAuxiliarySource = 'none'
	pendingAuxiliarySource = 'none'
end

function Think()
	local currentBot = RefreshBot()
	if currentBot == nil then return end
	-- Think 再检查一次独占辅助任务，确保技能前摇/引导不会被同模式的 gank 动作覆盖。
	local auxiliaryDesire, auxiliarySource = Auxiliary.GetDesire(currentBot)
	if auxiliaryDesire ~= nil and auxiliaryDesire > BOT_MODE_DESIRE_NONE then
		auxiliarySource = auxiliarySource or 'unknown'
		RouterDebugStatus('reason=auxiliary_active_think provider=' .. tostring(auxiliarySource)
			.. ' desire=' .. tostring(auxiliaryDesire))
		if activeProvider == 'gank' then StopGank('auxiliary_preempted', auxiliarySource, auxiliaryDesire) end
		if activeProvider ~= 'auxiliary' then Auxiliary.OnStart(currentBot) end
		activeProvider = 'auxiliary'
		pendingProvider = 'auxiliary'
		activeAuxiliarySource = auxiliarySource
		pendingAuxiliarySource = auxiliarySource
		Auxiliary.Think(currentBot)
		return
	end
	if activeProvider == 'auxiliary' then return end
	if not Utils.AllowModeDesire(currentBot, 'roam') then
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
			GetGankProvider().OnStart(currentBot)
		end
		GetGankProvider().Think(currentBot)
	end
end

-- 保留旧模式脚本暴露的全局物品查询，避免英雄技能脚本的加载顺序发生变化。
function IsItemAvailable(itemName)
	local currentBot = RefreshBot()
	if currentBot == nil then return nil end
	for slot = 0, 5 do
		local item = currentBot:GetItemInSlot(slot)
		if item ~= nil and item:GetName() == itemName then return item end
	end
	return nil
end
