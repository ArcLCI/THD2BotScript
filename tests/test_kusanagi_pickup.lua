local BOT_ROOT = "D:/LAF Workspace/THD/THD2BotScript"
local GAME_ROOT = "D:/LAF Workspace/THD/THDAmethyst_Game"

BOT_MODE_DESIRE_NONE = 0
BOT_MODE_DESIRE_VERYHIGH = 0.9
BOT_MODE_DESIRE_ABSOLUTE = 1.0
BOT_MODE_NONE = 0
BOT_ACTION_TYPE_DELAY = 99
ITEM_SLOT_TYPE_MAIN = 0
ITEM_SLOT_TYPE_BACKPACK = 1

local now = 100
local droppedItems = {}
local itemCosts = {}
local bot

local function Assert(condition, message)
	if not condition then error(message, 2) end
end

local function AssertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "value mismatch") .. ": expected=" .. tostring(expected)
			.. ", actual=" .. tostring(actual), 2)
	end
end

local function NewItem(name, cost)
	itemCosts[name] = cost or 100
	local item = {name = name}
	function item:GetName() return self.name end
	return item
end

local function RemoveDroppedItem(item)
	for index, drop in ipairs(droppedItems) do
		if drop.item == item then
			table.remove(droppedItems, index)
			return
		end
	end
end

local function NewBot()
	local hero = {
		inventory = {},
		location = 0,
		actions = {},
	}
	function hero:GetUnitName() return "npc_dota_hero_axe" end
	function hero:IsAlive() return true end
	function hero:GetCurrentActionType() return 0 end
	function hero:GetNearbyHeroes() return {} end
	function hero:HasModifier() return false end
	function hero:GetItemInSlot(slot) return self.inventory[slot] end
	function hero:GetItemSlotType(slot)
		if slot >= 6 and slot <= 8 then return ITEM_SLOT_TYPE_BACKPACK end
		return ITEM_SLOT_TYPE_MAIN
	end
	function hero:FindItemSlot(name)
		for slot = 0, 14 do
			local item = self.inventory[slot]
			if item ~= nil and item:GetName() == name then return slot end
		end
		return -1
	end
	function hero:GetLocation() return self.location end
	function hero:GetAbilityByName() return nil end
	function hero:ActionImmediate_SwapItems(first, second)
		table.insert(self.actions, {kind = "swap", first = first, second = second})
		self.inventory[first], self.inventory[second] = self.inventory[second], self.inventory[first]
	end
	function hero:Action_DropItem(item, location)
		table.insert(self.actions, {kind = "drop", item = item})
		if self.failDrops then return end
		for slot = 0, 8 do
			if self.inventory[slot] == item then
				self.inventory[slot] = nil
				break
			end
		end
		table.insert(droppedItems, {item = item, location = location, owner = self})
	end
	function hero:Action_PickUpItem(item)
		table.insert(self.actions, {kind = "pickup", item = item})
		local lastSlot = item:GetName() == "item_kusanagi" and 5 or 8
		for slot = 0, lastSlot do
			if self.inventory[slot] == nil then
				self.inventory[slot] = item
				RemoveDroppedItem(item)
				return
			end
		end
	end
	return hero
end

function GetScriptDirectory() return BOT_ROOT end
function GetBot() return bot end
function DotaTime() return now end
function GetDroppedItemList() return droppedItems end
function GetItemCost(name) return itemCosts[name] or 0 end
function GetUnitToLocationDistance(unit, location) return math.abs(unit.location - location) end
function Clamp(value, low, high) return math.max(low, math.min(value, high)) end

local J = {
	Retreat = {
		HIGH = 2,
		ShouldYield = function() return false end,
	},
	Utils = {
		IsTeamPushingSecondTierOrHighGround = function() return false end,
	},
	IsDoingRoshan = function() return false end,
	CanNotUseAction = function() return false end,
	IsAbilityInChannelPhase = function() return false end,
	ActionMoveToLocation = function(unit, _, location)
		table.insert(unit.actions, {kind = "move", location = location})
		unit.location = location
	end,
}

local Utils = {
	AllowModeDesire = function() return true end,
	GetCachedModeDesire = function(_, _, compute) return compute() end,
	NoteModeStart = function() end,
}

local Timer = {ShouldRunBotTask = function() return true end}
local specialThinkShouldAct = false
local specialThinkCalls = 0
local modeController = {
	GetModeDesire = function() return BOT_MODE_DESIRE_NONE end,
	Think = function()
		specialThinkCalls = specialThinkCalls + 1
		return specialThinkShouldAct
	end,
	OnEnd = function() end,
}

package.preload[BOT_ROOT .. "/thd2_item_function"] = function()
	dofile(BOT_ROOT .. "/thd2_item_function.lua")
	return true
end
package.preload[BOT_ROOT .. "/THDFuncLib/thd_func"] = function() return J end
package.preload[BOT_ROOT .. "/THDFuncLib/utils"] = function() return Utils end
package.preload[BOT_ROOT .. "/thd2_timer"] = function() return Timer end
package.preload[BOT_ROOT .. "/THDFuncLib/flandre_ultimate"] = function() return modeController end
package.preload[BOT_ROOT .. "/THDFuncLib/sunny_ultimate"] = function() return modeController end
package.preload[BOT_ROOT .. "/THDFuncLib/yuuka_combo"] = function() return modeController end
package.preload[BOT_ROOT .. "/THDFuncLib/nitori_poke"] = function() return modeController end

local roamConfigModule = BOT_ROOT .. "/THDFuncLib/roam_config"
local roamGankModule = BOT_ROOT .. "/THDFuncLib/roam_gank"
local RoamConfig = dofile(BOT_ROOT .. "/THDFuncLib/roam_config.lua")
local gankLoadCount = 0
package.preload[roamConfigModule] = function() return RoamConfig end
package.preload[roamGankModule] = function()
	gankLoadCount = gankLoadCount + 1
	error("disabled roam gank must not be loaded")
end

bot = NewBot()
local roamAuxiliaryModule = BOT_ROOT .. "/THDFuncLib/roam_auxiliary"
local RoamAuxiliary = dofile(BOT_ROOT .. "/THDFuncLib/roam_auxiliary.lua")
package.preload[roamAuxiliaryModule] = function() return RoamAuxiliary end
dofile(BOT_ROOT .. "/mode_roam_generic.lua")
AssertEqual(RoamConfig.IsEnabled(), false, "new roam gank is disabled by default")
AssertEqual(gankLoadCount, 0, "disabled gank provider is not loaded during router initialization")

local function ResetScenario()
	now = now + 3
	droppedItems = {}
	itemCosts = {}
	bot.inventory = {}
	bot.actions = {}
	bot.location = 0
	bot.failDrops = false
	specialThinkShouldAct = false
	specialThinkCalls = 0
	OnEnd()
end

local function FillInventory(firstSlot, lastSlot, prefix, baseCost)
	for slot = firstSlot, lastSlot do
		bot.inventory[slot] = NewItem(prefix .. tostring(slot), baseCost + slot)
	end
end

local function DropKusanagi()
	local kusanagi = NewItem("item_kusanagi", 6999)
	table.insert(droppedItems, {item = kusanagi, location = 0})
	return kusanagi
end

-- 主栏已有空位时，背包全满也必须直接拾取。
ResetScenario()
FillInventory(0, 4, "item_main_", 100)
FillInventory(6, 8, "item_backpack_", 200)
local kusanagi = DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_VERYHIGH, "full backpack still targets Kusanagi when main slot is empty")
Think()
AssertEqual(bot.inventory[5], kusanagi, "Kusanagi enters the empty main slot")
AssertEqual(#bot.actions, 1, "empty main slot needs only one action")
AssertEqual(bot.actions[1].kind, "pickup", "empty main slot directly picks up")

-- 主栏全满但背包有空位时，保留原有换格后拾取行为。
ResetScenario()
FillInventory(0, 5, "item_main_", 100)
FillInventory(6, 7, "item_backpack_", 200)
kusanagi = DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_VERYHIGH, "free backpack slot permits Kusanagi target")
Think()
AssertEqual(bot.actions[1].kind, "swap", "main item moves into free backpack slot")
AssertEqual(bot.actions[2].kind, "pickup", "Kusanagi pickup follows immediate swap")
AssertEqual(bot.inventory[0], kusanagi, "Kusanagi occupies the freed main slot")

-- 九格全满时先丢最低价值物品，拾剑兑换后再捡回。
ResetScenario()
FillInventory(0, 5, "item_main_", 100)
FillInventory(6, 8, "item_backpack_", 200)
local recoverableItem = NewItem("item_cheap_backpack", 10)
bot.inventory[8] = recoverableItem
kusanagi = DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_VERYHIGH, "nine full slots still target Kusanagi")
Think()
AssertEqual(#bot.actions, 1, "full inventory first Think issues one action")
AssertEqual(bot.actions[1].kind, "drop", "full inventory first drops the cheapest recoverable item")
AssertEqual(bot.actions[1].item, recoverableItem, "the cheapest backpack item is displaced")
AssertEqual(bot:FindItemSlot("item_kusanagi"), -1, "drop and pickup are not issued in the same Think")

Think()
AssertEqual(bot.actions[2].kind, "swap", "second Think moves a main item into the freed backpack slot")
AssertEqual(bot.actions[3].kind, "pickup", "second Think picks Kusanagi")
Assert(bot:FindItemSlot("item_kusanagi") >= 0, "Kusanagi was picked after making a main slot")

-- 模拟游戏侧拾取事件完成即时兑换。
bot.inventory[bot:FindItemSlot("item_kusanagi")] = nil
OnEnd()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_ABSOLUTE * 0.98, "nearby displaced item gets bounded recovery priority")
specialThinkShouldAct = true
specialThinkCalls = 0
Think()
AssertEqual(bot.actions[#bot.actions].kind, "pickup", "displaced item is picked back up")
Assert(bot:FindItemSlot("item_cheap_backpack") >= 0, "displaced item returned to inventory")
AssertEqual(specialThinkCalls, 0, "displaced item recovery runs before hero-specific Think")

-- 丢弃动作失败时只做有界重试，不会永久锁死游走模式。
ResetScenario()
FillInventory(0, 5, "item_main_", 100)
FillInventory(6, 8, "item_backpack_", 200)
bot.inventory[8] = NewItem("item_failed_drop", 10)
bot.failDrops = true
DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_VERYHIGH, "failed-drop scenario still starts pickup")
Think()
now = now + 1.1
Think()
local failedDropActions = #bot.actions
now = now + 2.1
Think()
AssertEqual(#bot.actions, failedDropActions, "drop retries stop after the bounded timeout")
AssertEqual(bot:FindItemSlot("item_failed_drop"), 8, "failed drop keeps the original item in inventory")
AssertEqual(bot:FindItemSlot("item_kusanagi"), -1, "failed drop never issues an impossible pickup")
AssertEqual(GetDesire(), BOT_MODE_DESIRE_NONE, "failed Kusanagi target enters retry cooldown")
Think()
AssertEqual(#bot.actions, failedDropActions, "retry cooldown prevents a new drop cycle")

-- 两帧之间若外部系统重新填满九格，保持恢复租约并等待空位，不丢失原物品句柄。
ResetScenario()
FillInventory(0, 5, "item_main_", 100)
FillInventory(6, 8, "item_backpack_", 200)
local refillRecoverableItem = NewItem("item_refill_recoverable", 10)
bot.inventory[8] = refillRecoverableItem
DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_VERYHIGH, "refill race starts Kusanagi pickup")
Think()
bot.inventory[8] = NewItem("item_external_refill", 300)
Think()
local actionsBeforeRecoverySpace = #bot.actions
Think()
AssertEqual(#bot.actions, actionsBeforeRecoverySpace, "full inventory waits instead of issuing impossible recovery pickup")
bot.inventory[0] = nil
Think()
AssertEqual(bot.actions[#bot.actions].kind, "pickup", "recovery resumes when any inventory slot opens")
Assert(bot:FindItemSlot("item_refill_recoverable") >= 0, "refill race still recovers the displaced item")

-- 已锁定的剑被其他单位拿走时，当前掉落表刷新会安全取消目标。
ResetScenario()
FillInventory(0, 4, "item_main_", 100)
FillInventory(6, 8, "item_backpack_", 200)
DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_VERYHIGH, "stale target scenario locks Kusanagi")
droppedItems = {}
Think()
AssertEqual(#bot.actions, 0, "missing live dropped handle cancels without issuing an action")

-- 没有可安全换出的主栏物品时，不应牺牲受保护物品。
ResetScenario()
for slot = 0, 8 do bot.inventory[slot] = NewItem("item_aegis", 0) end
DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_NONE, "protected full inventory rejects Kusanagi target")
AssertEqual(#bot.actions, 0, "protected inventory issues no destructive action")

ResetScenario()
for slot = 0, 5 do bot.inventory[slot] = NewItem("item_jiduzhixinyan", 100) end
FillInventory(6, 7, "item_backpack_", 200)
DropKusanagi()
AssertEqual(GetDesire(), BOT_MODE_DESIRE_NONE, "non-backpack special item is never selected for Kusanagi swap")
AssertEqual(#bot.actions, 0, "protected non-backpack main inventory issues no swap")
AssertEqual(gankLoadCount, 0, "disabled gank provider is never loaded by auxiliary pickup flow")

local gameModeSource = assert(io.open(GAME_ROOT .. "/scripts/vscripts/addon_game_mode.lua", "rb")):read("*a")
Assert(gameModeSource:find('itemEntity:GetAbilityName%(%) == "item_kusanagi"') ~= nil,
	"game pickup event recognizes Kusanagi")
Assert(gameModeSource:find("botBuff:SellKusanagiItems%(%)") ~= nil,
	"game pickup event reuses Bot Buff conversion")
Assert(gameModeSource:find('modifier_bot_buff_radiant') ~= nil
	and gameModeSource:find('modifier_bot_buff_dire') ~= nil,
	"game pickup event resolves both team modifiers")
local hookPosition = assert(gameModeSource:find('itemEntity:GetAbilityName%(%) == "item_kusanagi"'))
local shareabilityPosition = assert(gameModeSource:find('itemEntity:GetShareability%(%) ~= 2', hookPosition))
Assert(hookPosition < shareabilityPosition, "Kusanagi hook runs before the shareability early return")

print("test_kusanagi_pickup: OK")
