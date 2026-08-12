local M = {}

-- deadline 使用绝对 DotaTime；Think 首返回值表示该 Bot 的背包生命周期仍由本模块持有。
-- 调用方取得 GetReadyItem 后发单，再用 MarkCastIssued 等待实际消耗/冷却确认，确认后才 Release。

local MAIN_SLOT_MIN = 0
local MAIN_SLOT_MAX = 5
local BACKPACK_SLOT_MIN = 6
local BACKPACK_SLOT_MAX = 8
local ENEMY_SAFE_RADIUS = 1200
local RECENT_DAMAGE_TIME = 2.0
local READY_TIMEOUT = 8.0
local BRIDGE_TIMEOUT = 1.0
local RESTORE_TIMEOUT = 8.0
local ACTION_RETRY_INTERVAL = 0.5
local CAST_ISSUED_SETTLE_TIME = 0.5
local CAST_CONFIRM_TIMEOUT = 1.25

-- kind 只描述 Bot API 的施法入口；具体使用时机仍由请求方决定。
local REGISTRY = {
	item_clarity = {kind = 'entity', keepPriority = 10},
	item_flask = {kind = 'entity', keepPriority = 10},
	item_smoke_of_deceit = {kind = 'none', keepPriority = 30},
	item_dust = {kind = 'none', keepPriority = 30},
	item_ward_observer = {kind = 'location', keepPriority = 20},
	item_ward_sentry = {kind = 'location', keepPriority = 20},
	item_ward_dispenser = {kind = 'location', keepPriority = 20},
	item_cheese = {kind = 'none', keepPriority = 40},
	item_jinkela = {kind = 'none', keepPriority = 40},
	item_magic_mushroom = {kind = 'none', keepPriority = 10},
	item_card_good_man = {kind = 'entity', keepPriority = 10},
	item_card_bad_man = {kind = 'none', keepPriority = 10},
	item_card_love_man = {kind = 'entity', keepPriority = 10},
	item_card_worse_man = {kind = 'entity', keepPriority = 10},
	item_card_kid_man = {kind = 'none', keepPriority = 10},
	item_card_eat_man = {kind = 'entity', keepPriority = 10},
	item_card_moon_man = {kind = 'none', keepPriority = 10},
	item_card_super_man = {kind = 'none', keepPriority = 10},
}

local PROTECTED_ITEMS = {
	item_aegis = true,
	item_gem = true,
	item_kusanagi = true,
	item_tpscroll = true,
	item_travel_boots = true,
	item_travel_boots_2 = true,
	item_mushroom_kebab_immediate = true,
	item_mushroom_pie_immediate = true,
	item_mushroom_soup_immediate = true,
}

-- Bot 句柄是 userdata，不能可靠地直接增加 Lua 字段；弱键表仍将状态绑定到对应 Bot 生命周期。
local STATES = setmetatable({}, {__mode = 'k'})
local backpackBridgeEnabled = false

local function Now()
	if type(DotaTime) == 'function' then
		local ok, value = pcall(DotaTime)
		if ok and type(value) == 'number' then return value end
	end
	if type(GameTime) == 'function' then
		local ok, value = pcall(GameTime)
		if ok and type(value) == 'number' then return value end
	end
	return 0
end

local function CallMethod(object, methodName, defaultValue, ...)
	if object == nil then return defaultValue, false end
	local okMethod, method = pcall(function() return object[methodName] end)
	if not okMethod or type(method) ~= 'function' then return defaultValue, false end
	local arguments = {...}
	local ok, value = pcall(function() return method(object, unpack(arguments)) end)
	if not ok then return defaultValue, false end
	return value, true
end

local function GetItemName(item)
	local name, ok = CallMethod(item, 'GetName', nil)
	if not ok or type(name) ~= 'string' then return nil end
	return name
end

local function GetItemAt(bot, slot)
	local item, ok = CallMethod(bot, 'GetItemInSlot', nil, slot)
	if not ok then return nil, false end
	return item, true
end

local function FindHandle(bot, handle)
	if handle == nil then return nil, -1 end
	for slot = MAIN_SLOT_MIN, BACKPACK_SLOT_MAX do
		local item, ok = GetItemAt(bot, slot)
		if not ok then return nil, -1 end
		if item == handle then return item, slot end
	end
	return nil, -1
end

function M.FindItem(bot, itemName)
	if bot == nil or type(itemName) ~= 'string' then return nil, -1 end
	for slot = MAIN_SLOT_MIN, BACKPACK_SLOT_MAX do
		local item, ok = GetItemAt(bot, slot)
		if not ok then return nil, -1 end
		if item ~= nil and GetItemName(item) == itemName then return item, slot end
	end
	return nil, -1
end

local function FindLeasedItem(bot, state)
	if state.leasedItemHandle ~= nil then return FindHandle(bot, state.leasedItemHandle) end
	local item, slot = M.FindItem(bot, state.itemName)
	if item ~= nil then state.leasedItemHandle = item end
	return item, slot
end

function M.IsConsumable(itemName)
	return type(itemName) == 'string' and REGISTRY[itemName] ~= nil
end

function M.GetRegistry()
	local result = {}
	for itemName, entry in pairs(REGISTRY) do
		result[itemName] = {kind = entry.kind, keepPriority = entry.keepPriority}
	end
	return result
end

function M.GetState(bot)
	return STATES[bot]
end

function M.SetBackpackBridgeEnabled(enabled)
	backpackBridgeEnabled = enabled == true
end

local function IsListed(list, itemName)
	if type(list) ~= 'table' then return false end
	if list[itemName] == true then return true end
	for _, name in pairs(list) do
		if name == itemName then return true end
	end
	return false
end

local function GetItemCostSafe(itemName)
	if type(GetItemCost) ~= 'function' then return math.huge end
	local ok, cost = pcall(GetItemCost, itemName)
	if not ok or type(cost) ~= 'number' then return math.huge end
	return math.max(0, cost)
end

local function GetVictimPriority(itemName)
	local entry = REGISTRY[itemName]
	if entry ~= nil then return entry.keepPriority or 10 end
	return 100
end

local function IsProtectedItem(state, itemName)
	return PROTECTED_ITEMS[itemName] == true
		or IsListed(state.castSpec and state.castSpec.protectedItems, itemName)
end

local function FindMainSlotForLease(bot, state)
	local victimSlot = -1
	local victimPriority = math.huge
	local victimCost = math.huge
	for slot = MAIN_SLOT_MIN, MAIN_SLOT_MAX do
		local item, ok = GetItemAt(bot, slot)
		if not ok then return -1 end
		if item == nil then return slot end
		local itemName = GetItemName(item)
		if itemName ~= nil and not IsProtectedItem(state, itemName) then
			local priority = GetVictimPriority(itemName)
			local cost = GetItemCostSafe(itemName)
			if priority < victimPriority
				or (priority == victimPriority and cost < victimCost)
				or (priority == victimPriority and cost == victimCost and slot > victimSlot)
			then
				victimSlot = slot
				victimPriority = priority
				victimCost = cost
			end
		end
	end
	return victimSlot
end

local function ReadRequiredBoolean(bot, methodName, ...)
	local value, ok = CallMethod(bot, methodName, false, ...)
	if not ok or type(value) ~= 'boolean' then return nil end
	return value
end

local function IsOrderProtected(bot)
	local methodNames = {
		'IsCastingAbility',
		'IsUsingAbility',
		'IsChanneling',
	}
	for _, methodName in ipairs(methodNames) do
		local value = ReadRequiredBoolean(bot, methodName)
		if value == nil or value then return true end
	end

	local teleporting = ReadRequiredBoolean(bot, 'HasModifier', 'modifier_teleporting')
	if teleporting == nil or teleporting then return true end

	local actionType, ok = CallMethod(bot, 'GetCurrentActionType', nil)
	if not ok then return true end
	if (BOT_ACTION_TYPE_USE_ABILITY ~= nil and actionType == BOT_ACTION_TYPE_USE_ABILITY)
		or (BOT_ACTION_TYPE_PICK_UP_ITEM ~= nil and actionType == BOT_ACTION_TYPE_PICK_UP_ITEM)
		or (BOT_ACTION_TYPE_DROP_ITEM ~= nil and actionType == BOT_ACTION_TYPE_DROP_ITEM)
	then
		return true
	end
	return false
end

local function IsSafeToStart(bot)
	local alive = ReadRequiredBoolean(bot, 'IsAlive')
	if alive ~= true or IsOrderProtected(bot) then return false end

	local blockedMethods = {
		'IsSilenced',
		'IsStunned',
		'IsHexed',
		'IsNightmared',
		'IsRooted',
	}
	for _, methodName in ipairs(blockedMethods) do
		local value = ReadRequiredBoolean(bot, methodName)
		if value == nil or value then return false end
	end

	local mode, modeOK = CallMethod(bot, 'GetActiveMode', nil)
	if not modeOK then return false end
	if BOT_MODE_RETREAT ~= nil and mode == BOT_MODE_RETREAT then return false end

	local damaged, damagedOK = CallMethod(bot, 'WasRecentlyDamagedByAnyHero', false, RECENT_DAMAGE_TIME)
	if not damagedOK or damaged == true then return false end
	local modeNone = BOT_MODE_NONE or 0
	local enemies, enemiesOK = CallMethod(bot, 'GetNearbyHeroes', nil, ENEMY_SAFE_RADIUS, true, modeNone)
	if not enemiesOK or type(enemies) ~= 'table' or #enemies > 0 then return false end
	return true
end

local function NormalizeRequest(itemName, requester, priority, deadline, castSpec)
	if not M.IsConsumable(itemName) or requester == nil then return nil, 'invalid_request' end
	if castSpec ~= nil and type(castSpec) ~= 'table' then return nil, 'invalid_cast_spec' end
	castSpec = castSpec or {}
	local kind = castSpec.kind or REGISTRY[itemName].kind
	if kind ~= 'none' and kind ~= 'entity' and kind ~= 'location' then return nil, 'invalid_cast_kind' end
	local now = Now()
	deadline = tonumber(deadline) or (now + READY_TIMEOUT)
	if deadline <= now then return nil, 'expired' end
	local normalizedCastSpec = {}
	for key, value in pairs(castSpec) do normalizedCastSpec[key] = value end
	normalizedCastSpec.kind = kind
	return {
		itemName = itemName,
		requester = requester,
		priority = tonumber(priority) or 0,
		deadline = deadline,
		castSpec = normalizedCastSpec,
	}, nil
end

local function ActivateRequest(bot, request)
	local state = {
		requester = request.requester,
		itemName = request.itemName,
		priority = request.priority,
		deadline = request.deadline,
		castSpec = request.castSpec,
		requestStartTime = Now(),
		originalBackpackSlot = nil,
		displacedName = nil,
		displacedHandle = nil,
		mainSlot = nil,
		swapTime = nil,
		ready = false,
		restorePending = false,
		bridgeAttemptTime = nil,
	}
	STATES[bot] = state
	return state
end

local function PromotePending(bot, state)
	local pending = state and state.pendingRequest or nil
	STATES[bot] = nil
	if pending ~= nil and pending.deadline > Now() then return ActivateRequest(bot, pending) end
	return nil
end

local function BeginRestore(state, reason)
	if state.restorePending ~= true then
		state.restorePending = true
		state.restoreStartedTime = Now()
	end
	state.releaseReason = reason or state.releaseReason or 'released'
	state.ready = false
	state.castIssuedTime = nil
	state.castConfirmed = nil
end

local function RestoreFinished(bot, state)
	local displaced, displacedSlot = FindHandle(bot, state.displacedHandle)
	if displaced ~= nil and displacedSlot >= MAIN_SLOT_MIN and displacedSlot <= MAIN_SLOT_MAX then return true end
	if state.displacedHandle ~= nil then return false end

	if state.originalBackpackSlot == nil then return true end
	local leased, leasedSlot = FindLeasedItem(bot, state)
	if leased == nil then return true end
	return leasedSlot == state.originalBackpackSlot
end

local function TryRestore(bot, state)
	if RestoreFinished(bot, state) then
		local promoted = PromotePending(bot, state)
		return promoted ~= nil, promoted ~= nil and 'promoted' or 'restored'
	end

	local now = Now()
	if state.restoreNotBefore ~= nil and now < state.restoreNotBefore then
		return true, 'cast_settle_wait'
	end
	state.restoreStartedTime = state.restoreStartedTime or now
	if now >= state.restoreStartedTime + RESTORE_TIMEOUT then
		local promoted = PromotePending(bot, state)
		return promoted ~= nil, promoted ~= nil and 'promoted_after_restore_timeout' or 'restore_timeout'
	end
	if state.lastRestoreAttempt ~= nil and now < state.lastRestoreAttempt + ACTION_RETRY_INTERVAL then
		return true, 'restore_wait'
	end
	if IsOrderProtected(bot) then return true, 'restore_action_blocked' end

	local displaced, displacedSlot = FindHandle(bot, state.displacedHandle)
	local leased, leasedSlot = FindLeasedItem(bot, state)
	local sourceSlot = displacedSlot
	local targetSlot = -1

	if displaced ~= nil and displacedSlot >= BACKPACK_SLOT_MIN and displacedSlot <= BACKPACK_SLOT_MAX then
		if leased ~= nil and leasedSlot >= MAIN_SLOT_MIN and leasedSlot <= MAIN_SLOT_MAX then
			targetSlot = leasedSlot
		else
			local originalMainItem = state.mainSlot ~= nil and GetItemAt(bot, state.mainSlot) or nil
			if originalMainItem == nil then targetSlot = state.mainSlot or -1 end
		end
	elseif state.displacedHandle == nil
		and leased ~= nil
		and leasedSlot >= MAIN_SLOT_MIN and leasedSlot <= MAIN_SLOT_MAX
		and state.originalBackpackSlot ~= nil
	then
		local originalItem = GetItemAt(bot, state.originalBackpackSlot)
		if originalItem == nil then
			sourceSlot = leasedSlot
			targetSlot = state.originalBackpackSlot
		end
	end

	if sourceSlot == nil or sourceSlot < MAIN_SLOT_MIN or targetSlot < MAIN_SLOT_MIN then
		if displaced == nil then
			local promoted = PromotePending(bot, state)
			return promoted ~= nil, promoted ~= nil and 'promoted_after_item_missing' or 'restore_item_missing'
		end
		return true, 'restore_slot_blocked'
	end

	local _, actionOK = CallMethod(bot, 'ActionImmediate_SwapItems', nil, sourceSlot, targetSlot)
	if not actionOK then return true, 'restore_action_failed' end
	state.lastRestoreAttempt = now
	state.restoreAttempts = (state.restoreAttempts or 0) + 1
	return true, 'restore_swap'
end

function M.Request(bot, itemName, requester, priority, deadline, castSpec)
	if bot == nil then return false, 'invalid_bot' end
	local request, reason = NormalizeRequest(itemName, requester, priority, deadline, castSpec)
	if request == nil then return false, reason end

	local state = STATES[bot]
	if state == nil then
		ActivateRequest(bot, request)
		return true, 'accepted'
	end
	if state.requester == requester and state.itemName == itemName then
		state.priority = math.max(state.priority or 0, request.priority)
		state.deadline = request.deadline
		state.castSpec = request.castSpec
		return true, 'updated'
	end
	if request.priority <= (state.priority or 0) then return false, 'busy' end
	if state.pendingRequest == nil or request.priority > state.pendingRequest.priority then
		state.pendingRequest = request
	end
	BeginRestore(state, 'preempted')
	return true, 'queued'
end

function M.Release(bot, requester, reason)
	local state = STATES[bot]
	if state == nil then return false, 'idle' end
	if requester ~= nil and state.requester ~= requester then return false, 'not_owner' end
	if reason == 'cast_issued' then
		state.restoreNotBefore = math.max(state.restoreNotBefore or 0, Now() + CAST_ISSUED_SETTLE_TIME)
	end
	BeginRestore(state, reason)
	return true, 'releasing'
end

local function GetCharges(item)
	local charges, ok = CallMethod(item, 'GetCurrentCharges', nil)
	if not ok or type(charges) ~= 'number' then return nil end
	return charges
end

local function GetCooldown(item)
	local cooldown, ok = CallMethod(item, 'GetCooldownTimeRemaining', nil)
	if not ok or type(cooldown) ~= 'number' then return nil end
	return cooldown
end

function M.MarkCastIssued(bot, requester)
	local state = STATES[bot]
	if state == nil or state.restorePending == true then return false, 'idle' end
	if requester ~= nil and state.requester ~= requester then return false, 'not_owner' end
	local item, slot = FindLeasedItem(bot, state)
	if item == nil or slot < MAIN_SLOT_MIN or slot > MAIN_SLOT_MAX then return false, 'item_not_ready' end
	state.castIssuedTime = Now()
	state.castIssuedCharges = GetCharges(item)
	state.castIssuedCooldown = GetCooldown(item)
	state.castConfirmed = false
	state.ready = false
	return true, 'cast_pending'
end

function M.IsCastConfirmationPending(bot, requester)
	local state = STATES[bot]
	if state == nil or state.restorePending == true then return false end
	if requester ~= nil and state.requester ~= requester then return false end
	return state.castIssuedTime ~= nil or state.castConfirmed == true
end

local function GetCastConfirmationStatus(bot, state)
	if state.castConfirmed == true then return 'cast_confirmed' end
	if state.castIssuedTime == nil then return nil end
	local item = FindLeasedItem(bot, state)
	if item == nil then
		state.castConfirmed = true
		return 'cast_confirmed'
	end
	local charges = GetCharges(item)
	if charges ~= nil and state.castIssuedCharges ~= nil and charges < state.castIssuedCharges then
		state.castConfirmed = true
		return 'cast_confirmed'
	end
	local cooldown = GetCooldown(item)
	if cooldown ~= nil and state.castIssuedCooldown ~= nil
		and cooldown > state.castIssuedCooldown + 0.05
	then
		state.castConfirmed = true
		return 'cast_confirmed'
	end
	if Now() < state.castIssuedTime + CAST_CONFIRM_TIMEOUT then return 'cast_confirm_wait' end
	state.castIssuedTime = nil
	state.castIssuedCharges = nil
	state.castIssuedCooldown = nil
	state.castConfirmed = false
	state.readyDeadline = math.min(state.deadline, Now() + READY_TIMEOUT)
	return 'cast_unconfirmed'
end

local function DidBridgeSucceed(bot, state)
	local item, slot = FindLeasedItem(bot, state)
	if item == nil then return true end
	local charges = GetCharges(item)
	if charges ~= nil and state.bridgeCharges ~= nil and charges < state.bridgeCharges then return true end
	local cooldown = GetCooldown(item)
	if cooldown ~= nil and state.bridgeCooldown ~= nil and cooldown > state.bridgeCooldown + 0.05 then return true end
	return slot < BACKPACK_SLOT_MIN
end

local function TryBridge(bot, state, item)
	local kind = state.castSpec.kind
	local methodName = nil
	local argument = nil
	if kind == 'none' then
		methodName = 'Action_UseAbility'
	elseif kind == 'entity' then
		methodName = 'Action_UseAbilityOnEntity'
		argument = state.castSpec.target
	elseif kind == 'location' then
		methodName = 'Action_UseAbilityOnLocation'
		argument = state.castSpec.location
	end
	if methodName == nil or (kind ~= 'none' and argument == nil) then
		state.bridgeFailed = true
		return false, 'bridge_invalid_target'
	end

	local cooldown = GetCooldown(item)
	local charges = GetCharges(item)
	if cooldown ~= nil and cooldown > 0 then
		state.bridgeFailed = true
		return false, 'bridge_on_cooldown'
	end
	if charges ~= nil and charges <= 0 then
		state.bridgeFailed = true
		return false, 'bridge_no_charges'
	end

	local _, actionOK
	if kind == 'none' then
		_, actionOK = CallMethod(bot, methodName, nil, item)
	else
		_, actionOK = CallMethod(bot, methodName, nil, item, argument)
	end
	if not actionOK then
		state.bridgeFailed = true
		return false, 'bridge_action_failed'
	end
	state.bridgeAttemptTime = Now()
	state.bridgeCharges = charges
	state.bridgeCooldown = cooldown
	return true, 'bridge_attempt'
end

function M.GetReadyItem(bot, itemName, requester)
	local state = STATES[bot]
	if state == nil or state.restorePending == true then return nil end
	if state.castIssuedTime ~= nil or state.castConfirmed == true then return nil end
	if state.itemName ~= itemName or state.requester ~= requester then return nil end
	local item, slot = FindLeasedItem(bot, state)
	if item == nil or slot < MAIN_SLOT_MIN or slot > MAIN_SLOT_MAX then return nil end
	local castable, ok = CallMethod(item, 'IsFullyCastable', false)
	if not ok or castable ~= true then return nil end
	state.ready = true
	state.mainSlot = slot
	return item
end

function M.Think(bot)
	local state = STATES[bot]
	if state == nil then return false, 'idle' end
	local now = Now()

	if state.restorePending == true then return TryRestore(bot, state) end
	if now >= state.deadline then
		BeginRestore(state, 'deadline')
		return TryRestore(bot, state)
	end

	local alive = ReadRequiredBoolean(bot, 'IsAlive')
	if alive ~= true then
		BeginRestore(state, alive == false and 'dead' or 'receiver_unavailable')
		return TryRestore(bot, state)
	end

	local castStatus = GetCastConfirmationStatus(bot, state)
	if castStatus ~= nil then return true, castStatus end

	if state.bridgeAttemptTime ~= nil then
		if DidBridgeSucceed(bot, state) then
			local promoted = PromotePending(bot, state)
			return promoted ~= nil, promoted ~= nil and 'promoted_after_bridge' or 'bridge_succeeded'
		end
		if now < state.bridgeAttemptTime + BRIDGE_TIMEOUT then return true, 'bridge_wait' end
		state.bridgeFailed = true
		state.bridgeAttemptTime = nil
		state.bridgeCharges = nil
		state.bridgeCooldown = nil
	end

	local item, slot = FindLeasedItem(bot, state)
	if item == nil then
		BeginRestore(state, 'item_missing')
		return TryRestore(bot, state)
	end

	if slot >= MAIN_SLOT_MIN and slot <= MAIN_SLOT_MAX then
		state.mainSlot = slot
		state.readyDeadline = state.readyDeadline or math.min(state.deadline, now + READY_TIMEOUT)
		if now >= state.readyDeadline then
			BeginRestore(state, 'ready_timeout')
			return TryRestore(bot, state)
		end
		local castable, castableOK = CallMethod(item, 'IsFullyCastable', false)
		state.ready = castableOK and castable == true
		return true, state.ready and 'ready' or 'cooldown_wait'
	end

	if slot < BACKPACK_SLOT_MIN or slot > BACKPACK_SLOT_MAX then
		BeginRestore(state, 'unsupported_slot')
		return TryRestore(bot, state)
	end

	if state.swapTime ~= nil then
		if now < state.swapTime + ACTION_RETRY_INTERVAL then return true, 'swap_wait' end
		-- 原生命令没有改变槽位时清理快照后有界重试，避免把未发生的交换当成成功。
		state.swapAttempts = (state.swapAttempts or 0) + 1
		if state.swapAttempts >= 3 then
			BeginRestore(state, 'swap_failed')
			return TryRestore(bot, state)
		end
		state.originalBackpackSlot = nil
		state.displacedName = nil
		state.displacedHandle = nil
		state.mainSlot = nil
		state.swapTime = nil
		state.leasedItemHandle = item
	end

	if not IsSafeToStart(bot) then return true, 'unsafe_wait' end
	if backpackBridgeEnabled and state.bridgeAttemptTime == nil and state.bridgeFailed ~= true then
		local issued, reason = TryBridge(bot, state, item)
		if issued then return true, reason end
	end

	local mainSlot = FindMainSlotForLease(bot, state)
	if mainSlot < MAIN_SLOT_MIN then return true, 'no_switchable_slot' end
	local displaced = GetItemAt(bot, mainSlot)
	state.originalBackpackSlot = slot
	state.displacedHandle = displaced
	state.displacedName = GetItemName(displaced)
	state.mainSlot = mainSlot
	state.swapTime = now
	state.readyDeadline = math.min(state.deadline, now + READY_TIMEOUT)
	state.ready = false
	state.leasedItemHandle = item
	local _, actionOK = CallMethod(bot, 'ActionImmediate_SwapItems', nil, mainSlot, slot)
	if not actionOK then
		state.originalBackpackSlot = nil
		state.displacedHandle = nil
		state.displacedName = nil
		state.mainSlot = nil
		state.swapTime = nil
		return true, 'swap_action_failed'
	end
	return true, 'swap_issued'
end

return M
