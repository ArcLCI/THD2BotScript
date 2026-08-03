local BOT_ROOT = "D:/LAF Workspace/THD/THD2BotScript"
local GAME_ROOT = "D:/LAF Workspace/THD/THDAmethyst_Game"

BOT_ACTION_DESIRE_NONE = 0
BOT_ACTION_DESIRE_HIGH = 0.8
BOT_MODE_DESIRE_HIGH = 0.75
BOT_MODE_DESIRE_VERYHIGH = 0.9
BOT_MODE_NONE = 0
BOT_MODE_ATTACK = 1
BOT_MODE_RETREAT = 2
BOT_MODE_LANING = 3
BOT_MODE_PUSH_TOWER_MID = 4
BOT_ACTION_TYPE_USE_ABILITY = 5
DAMAGE_TYPE_MAGICAL = 2
DAMAGE_TYPE_PHYSICAL = 1
UNIT_LIST_ENEMY_BUILDINGS = 2
SHOP_HOME = 1
TOWER_TOP_3 = 2
TOWER_MID_3 = 5
TOWER_BOT_3 = 8
TOWER_BASE_1 = 9
TOWER_BASE_2 = 10

local now = 100
local bot = nil
local enemies = {}
local buildings = {}
local items = {}
local purchasedLists = {}
local towers = {}

local function Assert(condition, message)
	if not condition then error(message, 2) end
end

local function AssertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "value mismatch") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2)
	end
end

function Vector(x, y, z) return {x = x, y = y, z = z or 0} end
local function DistanceLocations(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end
function GetScriptDirectory() return BOT_ROOT end
function DotaTime() return now end
function GetBot() return bot end
function GetTeam() return bot and bot.team or 1 end
function GetOpposingTeam() return GetTeam() == 1 and 2 or 1 end
function GetTower(team, towerId) return towers[tostring(team) .. ":" .. tostring(towerId)] end
function GetShopLocation() return Vector(-6000, -6000, 0) end
function IsLocationPassable(location) return location.passable ~= false end
function GetUnitToUnitDistance(a, b) return DistanceLocations(a.location, b.location) end
function GetUnitToLocationDistance(unit, location) return DistanceLocations(unit.location, location) end
function GetUnitList(kind) return kind == UNIT_LIST_ENEMY_BUILDINGS and buildings or {} end
function CachedGetNearbyHeroes(unit, range)
	local result = {}
	for _, enemy in ipairs(enemies) do
		if enemy.alive and GetUnitToUnitDistance(unit, enemy) <= range then table.insert(result, enemy) end
	end
	return result
end
function IsTeleporting(target) return target.teleporting == true end
function IsItemAvailable(name) return items[name] end
function ConsiderNeutralItems() bot.neutralCalls = (bot.neutralCalls or 0) + 1 end
function RandomInt(low) return low end
function GetEquipmentMaxNum(list) return #list end
function ConsiderItemPurchase(list)
	local copy = {}
	for _, name in ipairs(list) do table.insert(copy, name) end
	table.insert(purchasedLists, copy)
	return 99
end

local function NewAbility(name, options)
	options = options or {}
	local ability = {
		name = name,
		castable = options.castable == true,
		trained = options.trained ~= false,
		level = options.level or 1,
		range = options.range or 800,
		specials = options.specials or {},
	}
	function ability:GetName() return self.name end
	function ability:IsFullyCastable() return self.castable end
	function ability:IsTrained() return self.trained end
	function ability:GetLevel() return self.level end
	function ability:GetCastRange() return self.range end
	function ability:GetSpecialValueInt(key) return self.specials[key] end
	function ability:GetSpecialValueFloat(key) return self.specials[key] end
	function ability:IsInAbilityPhase() return self.phase == true end
	function ability:IsChanneling() return self.channeling == true end
	return ability
end

local function NewHero(name, team, x, y)
	local hero = {
		name = name,
		team = team,
		location = Vector(x or 0, y or 0, 0),
		alive = true,
		visible = true,
		health = 1000,
		maxHealth = 1000,
		mana = 1000,
		maxMana = 1000,
		intellect = 100,
		attackDamage = 200,
		attackRange = 150,
		abilities = {},
		modifiers = {},
		modifierDurations = {},
		actions = {},
		laneCreeps = {},
		neutralCreeps = {},
	}
	function hero:IsNull() return false end
	function hero:IsAlive() return self.alive end
	function hero:CanBeSeen() return self.visible end
	function hero:IsHero() return true end
	function hero:IsBuilding() return false end
	function hero:IsTower() return false end
	function hero:GetTeam() return self.team end
	function hero:GetUnitName() return self.name end
	function hero:GetLocation() return self.location end
	function hero:GetExtrapolatedLocation() return self.predicted or self.location end
	function hero:GetHealth() return self.health end
	function hero:GetMaxHealth() return self.maxHealth end
	function hero:GetMana() return self.mana end
	function hero:GetMaxMana() return self.maxMana end
	function hero:GetIntellect() return self.intellect end
	function hero:GetAttackDamage() return self.attackDamage end
	function hero:GetAttackRange() return self.attackRange end
	function hero:GetActualIncomingDamage(damage) return damage end
	function hero:IsMagicImmune() return self.magicImmune == true end
	function hero:IsInvulnerable() return self.invulnerable == true end
	function hero:IsStunned() return self.stunned == true end
	function hero:IsHexed() return self.hexed == true end
	function hero:IsChanneling() return self.channeling == true end
	function hero:IsRooted() return self.rooted == true end
	function hero:GetAttackTarget() return self.attackTarget end
	function hero:HasScepter() return self.scepter == true end
	function hero:HasModifier(modifier) return self.modifiers[modifier] == true end
	function hero:GetModifierByName(modifier) return self.modifiers[modifier] and modifier or -1 end
	function hero:GetModifierRemainingDuration(index) return self.modifierDurations[index] end
	function hero:GetAbilityByName(abilityName) return self.abilities[abilityName] end
	function hero:GetActiveMode()
		if self.retreat then return BOT_MODE_RETREAT end
		if self.pushing then return BOT_MODE_PUSH_TOWER_MID end
		return self.laning and BOT_MODE_LANING or BOT_MODE_ATTACK
	end
	function hero:GetActiveModeDesire() return self.modeDesire or BOT_MODE_DESIRE_HIGH end
	function hero:GetCurrentActionType() return self.currentActionType or 0 end
	function hero:IsFacingLocation() return self.facing ~= false end
	function hero:WasRecentlyDamagedByAnyHero() return self.recentDamage == true end
	function hero:WasRecentlyDamagedByTower() return self.towerDamage == true end
	function hero:GetNearbyLaneCreeps() return self.laneCreeps end
	function hero:GetNearbyNeutralCreeps() return self.neutralCreeps end
	function hero:GetNearbyTowers() return self.nearbyTowers or (self.enemyTower and {true} or {}) end
	function hero:Action_UseAbility(ability) table.insert(self.actions, {kind = "ability", name = ability.name}) end
	function hero:Action_UseAbilityOnEntity(ability, target)
		table.insert(self.actions, {kind = "target", name = ability.name, target = target})
	end
	function hero:Action_UseAbilityOnLocation(ability, location)
		table.insert(self.actions, {kind = "location", name = ability.name, location = location})
	end
	function hero:Action_AttackUnit(target)
		table.insert(self.actions, {kind = "attack", target = target})
	end
	function hero:Action_MoveToLocation(location)
		table.insert(self.actions, {kind = "move", location = location})
	end
	return hero
end

local function NewItem(name, range)
	local item = NewAbility(name, {castable = true, range = range or 600})
	return item
end

local BotProfile = dofile(BOT_ROOT .. "/THDFuncLib/bot_profile.lua")
local NitoriCombat = dofile(BOT_ROOT .. "/THDFuncLib/nitori_combat.lua")
local J = {}
function J.CanNotUseAction(unit) return unit.blocked == true end
function J.IsSuspiciousIllusion(unit) return unit.suspicious == true end
function J.IsSeriouslyRetreating(unit) return unit.retreat == true end
function J.IsRetreating(unit) return unit.retreat == true end
function J.IsGoingOnSomeone(unit) return unit.going == true end
function J.IsInTeamFight(unit) return unit.teamfight == true end
function J.IsPushing(unit) return unit.pushing == true end
function J.IsInLaningPhase() return now < 8 * 60 end
function J.GetProperTarget(unit) return unit.properTarget end
function J.GetAllyCount(unit) return unit.allyCount or 2 end
function J.GetEnemyCount(unit, radius)
	if unit.enemyCount ~= nil then return unit.enemyCount end
	local count = 0
	for _, enemy in ipairs(enemies) do
		if radius == nil or GetUnitToUnitDistance(unit, enemy) <= radius then count = count + 1 end
	end
	return count
end
function J.CanKillTarget(target, damage) return damage >= target.health end
function J.ActionMoveToLocation(unit, actionName, location)
	unit:Action_MoveToLocation(location)
	return true
end
function J.GetTeamFountain() return Vector(-6600, -6300, 0) end
J.Retreat = {
	HIGH = 2,
	ShouldYield = function(unit) return unit.retreat == true end,
}

package.loaded[BOT_ROOT .. "/THDFuncLib/bot_profile"] = BotProfile
package.loaded[BOT_ROOT .. "/THDFuncLib/nitori_combat"] = NitoriCombat
package.loaded[BOT_ROOT .. "/THDFuncLib/thd_func"] = J
package.loaded[BOT_ROOT .. "/thd2_item_purchase"] = true
package.loaded[BOT_ROOT .. "/thd2_item_usage"] = true

local function SetMarker(hero, level)
	if level == nil then
		hero.abilities.ability_thd2_bot_profile = nil
	else
		hero.abilities.ability_thd2_bot_profile = NewAbility("ability_thd2_bot_profile", {level = level})
	end
end

local function InstallNitoriAbilities(hero)
	hero.abilities.ability_thdots_nitori01 = NewAbility("ability_thdots_nitori01")
	hero.abilities.ability_thdots_nitori02 = NewAbility("ability_thdots_nitori02", {specials = {damage = 90}})
	hero.abilities.ability_thdots_nitori03 = NewAbility("ability_thdots_nitori03", {
		specials = {magical_bonus = 60, outdamage_bonus = 20},
	})
	hero.abilities.ability_thdots_nitori04 = NewAbility("ability_thdots_nitori04")
	SetMarker(hero, 1)
end

-- 游戏侧 Profile 与30级加点。
local config = dofile(GAME_ROOT .. "/scripts/vscripts/util/bot_profile_config.lua")
local nitoriConfig = config.npc_dota_hero_spectre
Assert(nitoriConfig ~= nil, "spectre profile config missing")
AssertEqual(nitoriConfig.defaultProfile, "damage", "default profile")
AssertEqual(nitoriConfig.rolePools[1], "damage", "damage role pool")
AssertEqual(nitoriConfig.rolePools[2], "damage_spell", "spell damage role pool")
AssertEqual(#nitoriConfig.abilityPlans.damage, 30, "damage plan length")
local expectedDamagePlan =
	{3,2,3,1,3, 6,3,1,1,10, 1,6,2,2,12, 2,0,6,0,15, 0,0,0,0,16, 0,11,13,14,17}
local expectedSpellDamagePlan =
	{2,3,2,1,2, 6,2,3,3,11, 3,6,1,1,13, 1,0,6,0,14, 0,0,0,0,17, 0,10,12,15,16}
for level = 1, 30 do
	AssertEqual(nitoriConfig.abilityPlans.damage[level], expectedDamagePlan[level],
		"damage plan level " .. level)
	AssertEqual(nitoriConfig.abilityPlans.damage_spell[level], expectedSpellDamagePlan[level],
		"spell damage plan level " .. level)
end
local function CountPlanValue(plan, value)
	local count = 0
	for _, entry in ipairs(plan) do if entry == value then count = count + 1 end end
	return count
end
AssertEqual(CountPlanValue(nitoriConfig.abilityPlans.damage, 4), 0, "damage excludes innate slot 4")
AssertEqual(CountPlanValue(nitoriConfig.abilityPlans.damage_spell, 4), 0, "spell damage excludes innate slot 4")
for _, plan in ipairs({nitoriConfig.abilityPlans.damage, nitoriConfig.abilityPlans.damage_spell}) do
	AssertEqual(CountPlanValue(plan, 1), 4, "ability 1 learns exactly four times")
	AssertEqual(CountPlanValue(plan, 2), 4, "ability 2 learns exactly four times")
	AssertEqual(CountPlanValue(plan, 3), 4, "ability 3 learns exactly four times")
	AssertEqual(CountPlanValue(plan, 6), 3, "ultimate learns exactly three times")
end
local function AssertLevelRequirements(plan, profile)
	local basicRanks = {0, 0, 0}
	local ultimateRank = 0
	local talentMinimumLevel = {[10] = 10, [11] = 10, [12] = 15, [13] = 15,
		[14] = 20, [15] = 20, [16] = 25, [17] = 25}
	for heroLevel, slot in ipairs(plan) do
		if slot >= 1 and slot <= 3 then
			basicRanks[slot] = basicRanks[slot] + 1
			local requiredLevel = basicRanks[slot] * 2 - 1
			Assert(heroLevel >= requiredLevel, profile .. " ability " .. slot
				.. " rank " .. basicRanks[slot] .. " requires hero level " .. requiredLevel)
		elseif slot == 6 then
			ultimateRank = ultimateRank + 1
			Assert(heroLevel >= ultimateRank * 6, profile .. " ultimate rank requirement")
		elseif talentMinimumLevel[slot] ~= nil then
			Assert(heroLevel >= talentMinimumLevel[slot], profile .. " talent level requirement")
		end
	end
end
AssertLevelRequirements(nitoriConfig.abilityPlans.damage, "damage")
AssertLevelRequirements(nitoriConfig.abilityPlans.damage_spell, "damage_spell")
AssertEqual(nitoriConfig.abilityPlans.damage[25], 16, "damage level 25 talent")
AssertEqual(nitoriConfig.abilityPlans.damage[30], 17, "damage level 30 talent")
AssertEqual(nitoriConfig.abilityPlans.damage[2], 2, "damage early ability 2 lane pressure")
AssertEqual(nitoriConfig.abilityPlans.damage[7], 3, "damage ability 3 maxed first")
AssertEqual(nitoriConfig.abilityPlans.damage[11], 1, "damage ability 1 maxed second")
local earlyAbility2Ranks = 0
for level = 1, 12 do
	if nitoriConfig.abilityPlans.damage[level] == 2 then earlyAbility2Ranks = earlyAbility2Ranks + 1 end
end
AssertEqual(earlyAbility2Ranks, 1, "damage keeps only one early ability 2 rank")
AssertEqual(nitoriConfig.abilityPlans.damage[15], 12, "damage level 15 agility talent")
AssertEqual(nitoriConfig.abilityPlans.damage[20], 15, "damage level 20 booster duration talent")
AssertEqual(nitoriConfig.abilityPlans.damage_spell[7], 2, "spell damage maxes ability 2 first")
AssertEqual(nitoriConfig.abilityPlans.damage_spell[11], 3, "spell damage maxes ability 3 second")
AssertEqual(nitoriConfig.abilityPlans.damage_spell[15], 13, "spell damage no-decay talent")
AssertEqual(nitoriConfig.abilityPlans.damage_spell[20], 14, "spell damage attack-to-amp talent")
AssertEqual(nitoriConfig.abilityPlans.damage_spell[25], 17, "spell damage funnel talent")

local GameBotProfile = dofile(GAME_ROOT .. "/scripts/vscripts/util/bot_profile.lua")
GameBotProfile.RegisterHeroes(config)
local spellRolePools = GameBotProfile.GetRolePools("npc_dota_hero_spectre")
AssertEqual(#spellRolePools, 1, "both nitori builds share one damage role pool")
AssertEqual(spellRolePools[1], "damage", "spell build canonical damage role")
local validSpellProfile = GameBotProfile.ValidateProfile("npc_dota_hero_spectre", "damage_spell")
Assert(validSpellProfile, "forced damage_spell profile is valid")
local invalidForeignSpellProfile = GameBotProfile.ValidateProfile("npc_dota_hero_axe", "damage_spell")
Assert(not invalidForeignSpellProfile, "damage_spell alias is restricted to configured heroes")
local savedRandomInt = RandomInt
RandomInt = function(_, high) return high end
AssertEqual(GameBotProfile.ResolveProfileForRole("npc_dota_hero_spectre", "damage"), "damage_spell",
	"damage role can select the alternate spell build")
RandomInt = savedRandomInt

local specialmode = assert(io.open(GAME_ROOT .. "/scripts/vscripts/util/specialmode.lua", "rb")):read("*a")
local function ExtractTable(text, name)
	local startIndex = assert(text:find(name, 1, true), "missing table " .. name)
	local openIndex = assert(text:find("{", startIndex, true), "missing table open " .. name)
	local depth = 0
	for index = openIndex, #text do
		local char = text:sub(index, index)
		if char == "{" then depth = depth + 1 end
		if char == "}" then
			depth = depth - 1
			if depth == 0 then return text:sub(openIndex + 1, index - 1) end
		end
	end
	error("unterminated table " .. name)
end
local function CountPattern(text, pattern)
	local count = 0
	for _ in text:gmatch(pattern) do count = count + 1 end
	return count
end
Assert(specialmode:find("cur_bot_heros_size = 49", 1, true) ~= nil, "current hero count")
Assert(specialmode:find("tot_bot_heros_size = 69", 1, true) ~= nil, "total hero count")
Assert(specialmode:find('"npc_dota_hero_spectre"', 1, true) ~= nil, "spectre candidate")
Assert(specialmode:find('"nitori"', 1, true) ~= nil, "nitori folder")
Assert(specialmode:find("{3,2,3,1,3,  6,3,1,1,10", 1, true) ~= nil,
	"ordinary default plan excludes innate slot 4")
local usedBody = ExtractTable(specialmode, "G_BOT_USED =")
local heroBody = ExtractTable(specialmode, "G_Bot_Random_Hero =")
local folderBody = ExtractTable(specialmode, "G_Bot_Hero_Folder =")
local planBody = ExtractTable(specialmode, "G_Bots_Ability_Add =")
AssertEqual(CountPattern(usedBody, "%f[%a]true%f[%A]") + CountPattern(usedBody, "%f[%a]false%f[%A]"), 69,
	"used table alignment")
AssertEqual(CountPattern(heroBody, '"npc_dota_hero_[^"]+"'), 69, "hero table alignment")
AssertEqual(CountPattern(folderBody, '"[a-z0-9]+"'), 69, "folder table alignment")
AssertEqual(CountPattern(planBody, "{[^{}]*}"), 69, "ability-plan table alignment")
local itemAbilitySource = assert(io.open(
	GAME_ROOT .. "/scripts/vscripts/abilities/abilityitem.lua", "rb")):read("*a")
local nitoriAbilitySource = assert(io.open(
	GAME_ROOT .. "/scripts/vscripts/abilities/abilitynitori.lua", "rb")):read("*a")
local trinityItemSource = assert(io.open(
	GAME_ROOT .. "/scripts/npc/items/upgrade/item_trinity.txt", "rb")):read("*a")
local gameModeSource = assert(io.open(
	GAME_ROOT .. "/scripts/vscripts/addon_game_mode.lua", "rb")):read("*a")
local roamModeSource = assert(io.open(BOT_ROOT .. "/mode_roam_generic.lua", "rb")):read("*a")
local innateStart = assert(gameModeSource:find(
	'abilityEx = hero:FindAbilityByName("ability_thdots_nitoriEx")', 1, true),
	"nitori innate initialization branch")
Assert(gameModeSource:find("abilityEx:SetLevel(1)", innateStart, true) ~= nil,
	"nitori innate is initialized to level 1")
Assert(itemAbilitySource:find("Caster:Purge(false, true, false, true, false)", 1, true) ~= nil,
	"dragon star must continuously remove the flight-end stun")
Assert(nitoriAbilitySource:find("UtilStun:UnitStunTarget(caster,caster,duration)", 1, true) ~= nil,
	"permanent wanbao flight-end stun source")
Assert(trinityItemSource:find('"02" "item_sss"', 1, true) ~= nil,
	"trinity must accept sss as a direct upgrade base")
Assert(roamModeSource:find("THDFuncLib/nitori_poke", 1, true) ~= nil,
	"roam mode must load the nitori poke controller")

-- 双购买路线、缺失标记回退和临时食物副本。
bot = NewHero("npc_dota_hero_spectre", 1)
SetMarker(bot, nil)
dofile(BOT_ROOT .. "/item_purchase_spectre.lua")
ItemPurchaseThink()
local damageRoute = purchasedLists[#purchasedLists]
AssertEqual(damageRoute[1], "item_horse_red", "damage first item")
AssertEqual(damageRoute[2], "item_quant", "damage early crit transition")
AssertEqual(damageRoute[3], "item_bloodthirstiest", "damage early lifesteal transition")
AssertEqual(damageRoute[6], "item_wrench", "damage sampan damage component")
AssertEqual(damageRoute[7], "item_recipe_sampan", "damage sampan completion")
AssertEqual(damageRoute[8], "item_tengu_fan", "damage early laevateinn agility component")
AssertEqual(damageRoute[9], "item_ice_block", "damage early laevateinn stats component")
AssertEqual(damageRoute[10], "item_recipe_laevateinn", "damage early laevateinn completion")
AssertEqual(damageRoute[13], "item_ganggenier", "missing marker damage fallback")
AssertEqual(damageRoute[14], "item_recipe_wanbaochui2", "damage delayed permanent wanbao")
AssertEqual(damageRoute[15], "item_cirno_claymore", "damage ertianyiliu second component")
AssertEqual(damageRoute[16], "item_recipe_ertianyiliu", "damage ertianyiliu completion")
AssertEqual(damageRoute[18], "item_recipe_trinity", "damage final recipe")
SetMarker(bot, 2)
dofile(BOT_ROOT .. "/item_purchase_spectre.lua")
ItemPurchaseThink()
local spellDamageRoute = purchasedLists[#purchasedLists]
AssertEqual(spellDamageRoute[1], "item_horse_red", "spell damage opens with mobility")
AssertEqual(spellDamageRoute[2], "item_cht", "spell damage early sss component")
AssertEqual(spellDamageRoute[3], "item_naginata", "spell damage completes sss smoothly")
AssertEqual(spellDamageRoute[4], "item_pomojinlingli", "spell damage early silence amplifier")
AssertEqual(spellDamageRoute[5], "item_nuclear_stick", "spell damage early cooldown reduction")
AssertEqual(spellDamageRoute[6], "item_horse_king_compressor", "spell damage mobility compression")
AssertEqual(spellDamageRoute[7], "item_recipe_horse_king", "spell damage completes horse king")
AssertEqual(spellDamageRoute[8], "item_bagua", "spell damage amplifier")
AssertEqual(spellDamageRoute[9], "item_yukkuri_stick", "spell damage control and intellect")
AssertEqual(spellDamageRoute[10], "item_recipe_trinity", "spell damage upgrades sss in place")
SetMarker(bot, 1)
ItemPurchaseThink()
AssertEqual(#purchasedLists[#purchasedLists], 19, "optional edible copy")
AssertEqual(purchasedLists[#purchasedLists][13], "item_ganggenier", "forced damage route")
ItemPurchaseThink()
AssertEqual(#purchasedLists[#purchasedLists], 19, "canonical route remains immutable")
SetMarker(bot, 3)
dofile(BOT_ROOT .. "/item_purchase_spectre.lua")
ItemPurchaseThink()
AssertEqual(purchasedLists[#purchasedLists][13], "item_ganggenier", "illegal support purchase fallback")

-- 按实际配方表展开，确认路线没有把最终升级重新展开为重复组件。
dofile(BOT_ROOT .. "/thd2_item_recipe_list.lua")
AssertEqual(#GetFullPurchaseList(damageRoute), 38, "damage recipe expansion")
Assert(#GetFullPurchaseList(spellDamageRoute) > #spellDamageRoute, "spell damage recipe expansion")
local function CountValue(list, expected)
	local count = 0
	for _, value in ipairs(list) do if value == expected then count = count + 1 end end
	return count
end
AssertEqual(CountValue(GetFullPurchaseList(damageRoute), "item_recipe_trinity"), 1,
	"damage single trinity recipe")
AssertEqual(CountValue(damageRoute, "item_quant"), 1,
	"damage single quant transition")
AssertEqual(CountValue(GetFullPurchaseList(damageRoute), "item_recipe_sampan"), 1,
	"damage single sampan recipe")
AssertEqual(CountValue(damageRoute, "item_bloodthirstiest"), 1,
	"damage single early bloodthirstiest")
AssertEqual(CountValue(GetFullPurchaseList(damageRoute), "item_recipe_laevateinn"), 1,
	"damage single laevateinn recipe")
AssertEqual(CountValue(damageRoute, "item_laevateinn"), 0,
	"damage does not duplicate early laevateinn components")
AssertEqual(CountValue(damageRoute, "item_wanbaochui"), 1,
	"damage keeps one ordinary wanbao")
AssertEqual(CountValue(damageRoute, "item_wanbaochui2"), 0,
	"damage does not expand permanent wanbao early")
AssertEqual(CountValue(GetFullPurchaseList(damageRoute), "item_recipe_wanbaochui2"), 1,
	"damage single delayed permanent-wanbao recipe")
AssertEqual(CountValue(GetFullPurchaseList(damageRoute), "item_recipe_ertianyiliu"), 1,
	"damage single ertianyiliu recipe")
AssertEqual(CountValue(GetFullPurchaseList(damageRoute), "item_camera"), 0,
	"damage excludes camera")
AssertEqual(CountValue(spellDamageRoute, "item_cht"), 1, "spell damage single early cht")
AssertEqual(CountValue(spellDamageRoute, "item_naginata"), 1, "spell damage single sss component")
AssertEqual(CountValue(GetFullPurchaseList(spellDamageRoute), "item_recipe_cht"), 2,
	"spell damage buys one cht for sss and one for pomojinlingli")
AssertEqual(CountValue(GetFullPurchaseList(spellDamageRoute), "item_recipe_naginata"), 1,
	"spell damage uses only the sss naginata")
AssertEqual(CountValue(spellDamageRoute, "item_glutton_spork"), 0,
	"spell damage does not duplicate the trinity base")
AssertEqual(CountValue(spellDamageRoute, "item_horse_red"), 1,
	"spell damage buys one early mobility broom")
AssertEqual(CountValue(GetFullPurchaseList(spellDamageRoute), "item_recipe_horse_king"), 1,
	"spell damage compresses the broom once")
AssertEqual(CountValue(spellDamageRoute, "item_wanbaochui"), 0, "spell damage excludes wanbao")
AssertEqual(CountValue(spellDamageRoute, "item_dragon_star"), 0, "spell damage excludes dragon star")
AssertEqual(CountValue(spellDamageRoute, "item_yueyaomishi"), 0, "spell damage excludes redundant moon stone")
AssertEqual(CountValue(GetFullPurchaseList(spellDamageRoute), "item_recipe_pomojinlingli"), 1,
	"spell damage single pomojinlingli recipe")
AssertEqual(CountValue(GetFullPurchaseList(spellDamageRoute), "item_recipe_trinity"), 1,
	"spell damage single trinity recipe")

-- 按成装阶段模拟主物品栏：六格后永久化万宝槌，再压缩楼观剑与白楼剑，最终回到六格。
local function CountEquipment(equipment)
	local count = 0
	for _, amount in pairs(equipment) do count = count + amount end
	return count
end
local function AddEquipment(equipment, itemName)
	equipment[itemName] = (equipment[itemName] or 0) + 1
end
local function ConsumeEquipment(equipment, itemName)
	Assert((equipment[itemName] or 0) > 0, "missing equipment component " .. itemName)
	equipment[itemName] = equipment[itemName] - 1
end
local function SimulateSixSlotRoute(route, profile)
	local equipment = {}
	for _, itemName in ipairs(route) do
		if itemName == "item_naginata" and (equipment.item_cht or 0) > 0 then
			ConsumeEquipment(equipment, "item_cht")
			AddEquipment(equipment, "item_sss")
		elseif itemName == "item_recipe_sampan" then
			ConsumeEquipment(equipment, "item_quant")
			ConsumeEquipment(equipment, "item_wrench")
			AddEquipment(equipment, "item_sampan")
		elseif itemName == "item_recipe_laevateinn" then
			-- 第三个组件临时进入背包；配方随即把三个组件压成莱瓦汀并回到五格。
			AssertEqual(CountEquipment(equipment), 7, profile .. " laevateinn uses one backpack component")
			ConsumeEquipment(equipment, "item_bloodthirstiest")
			ConsumeEquipment(equipment, "item_tengu_fan")
			ConsumeEquipment(equipment, "item_ice_block")
			AddEquipment(equipment, "item_laevateinn")
		elseif itemName == "item_recipe_horse_king" then
			ConsumeEquipment(equipment, "item_horse_red")
			ConsumeEquipment(equipment, "item_horse_king_compressor")
			AddEquipment(equipment, "item_horse_king")
		elseif itemName == "item_recipe_wanbaochui2" then
			AssertEqual(CountEquipment(equipment), 6, profile .. " wanbao upgrades at six slots")
			ConsumeEquipment(equipment, "item_wanbaochui")
			-- 永久万宝槌完成后自消耗，只留下永久加持并腾出一个格子。
		elseif itemName == "item_recipe_ertianyiliu" then
			AssertEqual(CountEquipment(equipment), 6, profile .. " ertianyiliu compresses at six slots")
			ConsumeEquipment(equipment, "item_sampan")
			ConsumeEquipment(equipment, "item_cirno_claymore")
			AddEquipment(equipment, "item_ertianyiliu")
		elseif itemName == "item_recipe_trinity" then
			AssertEqual(CountEquipment(equipment), 6, profile .. " trinity upgrades in place")
			if (equipment.item_sss or 0) > 0 then
				ConsumeEquipment(equipment, "item_sss")
			else
				ConsumeEquipment(equipment, "item_glutton_spork")
			end
			AddEquipment(equipment, "item_trinity")
		else
			AddEquipment(equipment, itemName)
		end
	end
	AssertEqual(CountEquipment(equipment), 6, profile .. " final six slots")
	return equipment
end
local damageEquipment = SimulateSixSlotRoute(damageRoute, "damage")
AssertEqual(damageEquipment.item_ertianyiliu, 1, "damage final ertianyiliu")
AssertEqual(damageEquipment.item_laevateinn, 1, "damage final laevateinn")
AssertEqual(damageEquipment.item_trinity, 1, "damage final trinity")
local spellDamageEquipment = SimulateSixSlotRoute(spellDamageRoute, "damage_spell")
AssertEqual(spellDamageEquipment.item_sss, 0, "spell damage consumes sss for trinity")
AssertEqual(spellDamageEquipment.item_horse_king, 1, "spell damage final horse king")
AssertEqual(spellDamageEquipment.item_pomojinlingli, 1, "spell damage final pomojinlingli")
AssertEqual(spellDamageEquipment.item_nuclear_stick, 1, "spell damage final nuclear stick")
AssertEqual(spellDamageEquipment.item_bagua, 1, "spell damage final bagua")
AssertEqual(spellDamageEquipment.item_yukkuri_stick, 1, "spell damage final yukkuri")
AssertEqual(spellDamageEquipment.item_trinity, 1, "spell damage final trinity")

NITORI_BOT_TEST_EXPORTS = true
dofile(BOT_ROOT .. "/ability_item_usage_spectre.lua")

local function ResetScenario(marker)
	now = now + 1
	items = {}
	enemies = {}
	buildings = {}
	towers = {}
	bot = NewHero("npc_dota_hero_spectre", 1)
	InstallNitoriAbilities(bot)
	SetMarker(bot, marker)
	return bot
end

AssertEqual(NitoriBotTest.GetProfile(ResetScenario(nil)), BotProfile.DAMAGE, "ability missing marker fallback")
AssertEqual(NitoriBotTest.GetProfile(ResetScenario(2)), BotProfile.DAMAGE_SPELL, "forced spell-damage marker")
AssertEqual(NitoriBotTest.GetProfile(ResetScenario(3)), BotProfile.DAMAGE, "illegal support marker fallback")

-- 炮击前摇/蓄力期间无替换动作。
ResetScenario(1)
bot.abilities.ability_thdots_nitori02.phase = true
bot.abilities.ability_thdots_nitori01.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "ability phase protection")
bot.abilities.ability_thdots_nitori02.phase = false
bot.modifiers.modifier_ability_thdots_nitori02 = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "charge modifier protection")

-- 飞行窗口禁止2；没有待消耗充能时优先大招，其次3。
ResetScenario(1)
local center = NewHero("enemy_center", 2, 180, 0)
local side = NewHero("enemy_side", 2, 220, 0)
enemies = {center, side}
bot.modifiers.modifier_ability_thdots_nitori01 = true
bot.abilities.ability_thdots_nitori02.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
bot.abilities.ability_thdots_nitori04.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori04", "flight ultimate priority")
bot.actions = {}
bot.abilities.ability_thdots_nitori04.castable = false
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori03", "flight melee reaction priority")

-- 推进器追击过程中已有光束剑充能时，先完成普攻，不被大招或3技能刷新掉。
ResetScenario(1)
local flightAttackTarget = NewHero("flight_attack_target", 2, 100, 0)
enemies = {flightAttackTarget}
bot.properTarget = flightAttackTarget
bot.going = true
bot.modifiers.modifier_ability_thdots_nitori01 = true
bot.modifiers.modifier_ability_thdots_nitori03_passive = true
bot.abilities.ability_thdots_nitori03.castable = true
bot.abilities.ability_thdots_nitori04.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].kind, "attack", "flight empowered attack before refresh")

-- 输出追击从基础被动开始就先消耗强化普攻，不等到25级才保护充能。
ResetScenario(1)
local attackTarget = NewHero("enemy_attack", 2, 100, 0)
enemies = {attackTarget}
bot.properTarget = attackTarget
bot.going = true
bot.modifiers.modifier_ability_thdots_nitori03_passive = true
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].kind, "attack", "empowered attack follow-up")

-- 法术输出不为强化普攻延误阳电子炮，并在单目标追击时也主动炮击。
ResetScenario(2)
local spellTarget = NewHero("enemy_spell_target", 2, 750, 0)
enemies = {spellTarget}
bot.properTarget = spellTarget
bot.going = true
bot.modifiers.modifier_ability_thdots_nitori03_passive = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori02", "spell damage prioritizes single-target cannon")
AssertEqual(bot.actions[1].kind, "location", "spell damage cannon point cast")

-- 炮击智力伤害只按前置命中数衰减。
ResetScenario(1)
local damage = NitoriBotTest.GetNitori02Damage(bot, bot.abilities.ability_thdots_nitori02, 2)
AssertEqual(damage, 250, "line prior-hit intellect decay")
bot.abilities.special_bonus_unique_nitori_2 = NewAbility("special_bonus_unique_nitori_2", {level = 1})
AssertEqual(NitoriBotTest.GetNitori02Damage(bot, bot.abilities.ability_thdots_nitori02, 8), 290,
	"no-decay talent")

-- 输出25-29级仍是基础浮游炮数量，30级补槽位17后才增加3个。
bot.abilities.ability_thdots_nitori04.level = 3
bot.abilities.ability_thdots_nitori04.specials.number = 5
AssertEqual(NitoriBotTest.GetExpectedFunnelCount(bot, bot.abilities.ability_thdots_nitori04), 5,
	"level 29 funnel count")
bot.abilities.special_bonus_unique_nitori_5 = NewAbility("special_bonus_unique_nitori_5", {level = 1})
AssertEqual(NitoriBotTest.GetExpectedFunnelCount(bot, bot.abilities.ability_thdots_nitori04), 8,
	"level 30 funnel count")

-- 四个兵在同一直线上时按预测射线清线；近身撤退时拒绝用一秒自晕换减速。
ResetScenario(1)
for index = 1, 4 do
	local creep = NewHero("lane_creep_" .. index, 2, 220 + index * 100, 0)
	creep.IsHero = function() return false end
	table.insert(bot.laneCreeps, creep)
end
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori02", "predicted line clear")
AssertEqual(bot.actions[1].kind, "location", "line uses point cast")

ResetScenario(2)
for index = 1, 3 do
	local creep = NewHero("spell_lane_creep_" .. index, 2, 250 + index * 120, 0)
	creep.IsHero = function() return false end
	table.insert(bot.laneCreeps, creep)
end
bot.mana = 450
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori02", "spell damage clears three-unit line at lower mana")

ResetScenario(1)
local closePursuer = NewHero("close_pursuer", 2, 300, 0)
enemies = {closePursuer}
bot.retreat = true
bot.recentDamage = true
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "dangerous retreat does not self-stun")

-- 对线期远距离炮击压制，并在低蓝、近期受击或敌塔范围内保持克制。
ResetScenario(1)
local laneTarget = NewHero("lane_target", 2, 800, 0)
enemies = {laneTarget}
bot.laning = true
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori02", "laning ranged pressure")

ResetScenario(1)
laneTarget = NewHero("lane_target_low_mana", 2, 800, 0)
enemies = {laneTarget}
bot.laning = true
bot.mana = 600
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "laning pressure preserves low mana")

ResetScenario(1)
laneTarget = NewHero("lane_target_under_tower", 2, 800, 0)
enemies = {laneTarget}
bot.laning = true
bot.enemyTower = true
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "laning pressure avoids enemy tower")

-- 敌人贴近250范围时改用3技能，不用带自晕的炮击硬换血。
ResetScenario(2)
local closeLaneTarget = NewHero("close_lane_target", 2, 200, 0)
enemies = {closeLaneTarget}
bot.laning = true
bot.abilities.ability_thdots_nitori02.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori03", "laning close pressure")

-- 前排油库里优先打断，且同帧技能入口不会覆盖物品动作。
ResetScenario(2)
local channeler = NewHero("enemy_channel", 2, 300, 0)
channeler.channeling = true
enemies = {channeler}
items.item_yukkuri_stick = NewItem("item_yukkuri_stick", 600)
bot.abilities.ability_thdots_nitori03.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 1, "single action per frame")
AssertEqual(bot.actions[1].name, "item_yukkuri_stick", "yukkuri interrupt")

ResetScenario(2)
local spellEngageTarget = NewHero("spell_engage_target", 2, 650, 0)
enemies = {spellEngageTarget}
bot.properTarget = spellEngageTarget
bot.going = true
items.item_pomojinlingli = NewItem("item_pomojinlingli", 750)
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 1, "pomojinlingli single action")
AssertEqual(bot.actions[1].name, "item_pomojinlingli", "spell damage silences before cannon")

ResetScenario(2)
local teleportTarget = NewHero("teleport_target", 2, 500, 0)
teleportTarget.channeling = true
teleportTarget.teleporting = true
enemies = {teleportTarget}
bot.properTarget = teleportTarget
bot.going = true
items.item_pomojinlingli = NewItem("item_pomojinlingli", 750)
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "pomojinlingli does not try to interrupt teleport")

ResetScenario(2)
local pushTower = NewHero("push_tower", 2, 900, 0)
pushTower.IsHero = function() return false end
pushTower.IsBuilding = function() return true end
pushTower.IsTower = function() return true end
buildings = {pushTower}
bot.pushing = true
bot.mana = 400
bot.abilities.ability_thdots_nitori02.castable = true
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori02", "spell damage cannon pushes building")
AssertEqual(bot.actions[1].kind, "location", "building cannon uses point cast")

-- 三位一体在多人团战前预盾；炽热彗星能在脱战时主动关闭。
ResetScenario(1)
enemies = {NewHero("enemy_a", 2, 400, 0), NewHero("enemy_b", 2, 450, 50)}
bot.teamfight = true
items.item_trinity = NewItem("item_trinity")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "item_trinity", "trinity pre-shield")

ResetScenario(1)
bot.modifiers.modifier_item_horse_king_open = true
items.item_horse_king = NewItem("item_horse_king")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "item_horse_king", "horse king idle disable")

ResetScenario(2)
enemies = {NewHero("spell_chase_target", 2, 650, 0)}
bot.going = true
bot.mana = 400
items.item_horse_king = NewItem("item_horse_king")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "item_horse_king", "spell damage horse king chase enable")

-- 高欲望突进先开龙星，下一帧才允许推进器。
ResetScenario(1)
local engageTarget = NewHero("enemy_engage", 2, 700, 0)
enemies = {engageTarget}
bot.properTarget = engageTarget
bot.going = true
bot.abilities.ability_thdots_nitori01.castable = true
items.item_dragon_star = NewItem("item_dragon_star")
AbilityUsageThink()
AssertEqual(#bot.actions, 1, "dragon-star action lock")
AssertEqual(bot.actions[1].name, "item_dragon_star", "dragon-star pre-engage")

-- 万宝槌配合20级持续时间天赋时先突进，飞行剩余约5.25秒再开龙星覆盖结束自晕。
ResetScenario(1)
engageTarget = NewHero("enemy_extended_engage", 2, 700, 0)
enemies = {engageTarget}
bot.properTarget = engageTarget
bot.going = true
bot.scepter = true
bot.abilities.special_bonus_unique_nitori_3 = NewAbility("special_bonus_unique_nitori_3", {level = 1})
bot.abilities.ability_thdots_nitori01.castable = true
items.item_dragon_star = NewItem("item_dragon_star")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori01", "extended flight starts before dragon-star")

bot.actions = {}
bot.abilities.ability_thdots_nitori01.castable = false
bot.modifiers.modifier_ability_thdots_nitori01 = true
bot.modifierDurations.modifier_ability_thdots_nitori01 = 5.8
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "extended flight waits before dragon-star")
bot.modifierDurations.modifier_ability_thdots_nitori01 = 5.2
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "item_dragon_star", "delayed dragon-star covers flight-end stun")

-- 法术定位的 Poke 模式覆盖 Valve 贴脸进攻，并在施法生命周期内保持静默。
local NitoriPoke = dofile(BOT_ROOT .. "/THDFuncLib/nitori_poke.lua")
ResetScenario(2)
enemies = {NewHero("lane_poke_enemy", 2, 800, 0)}
bot.laning = true
bot.teamfight = true
bot.going = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori02.castable = true
AssertEqual(NitoriPoke.GetModeDesire(bot), BOT_MODE_DESIRE_NONE,
	"laning does not enable custom poke spacing")
AssertEqual(bot.thdNitoriPokeActive, false, "laning leaves movement to the normal lane mode")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori02",
	"spell profile still uses ranged lane pressure without dashing")

ResetScenario(2)
enemies = {NewHero("lane_no_cannon_enemy", 2, 800, 0)}
bot.laning = true
bot.going = true
bot.abilities.ability_thdots_nitori01.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0,
	"spell profile does not replace an unavailable lane cannon with nitori01")

ResetScenario(2)
enemies = {NewHero("poke_enemy", 2, 500, 0)}
bot.teamfight = true
Assert(NitoriPoke.GetModeDesire(bot) > BOT_MODE_DESIRE_VERYHIGH,
	"spell damage poke overrides base attack desire")
AssertEqual(bot.thdNitoriPokeActive, true, "spell damage poke state")
AssertEqual(NitoriPoke.Think(bot), true, "spell damage poke owns movement")
AssertEqual(bot.actions[1].kind, "move", "spell damage poke issues movement")
Assert(GetUnitToLocationDistance(enemies[1], bot.actions[1].location) >= 1000,
	"close enemy forces the pressured poke range")
Assert(DistanceLocations(bot.actions[1].location, J.GetTeamFountain())
	< DistanceLocations(enemies[1].location, J.GetTeamFountain()),
	"poke destination stays on the allied fountain side")

ResetScenario(2)
bot.location = Vector(900, 200, 0)
enemies = {NewHero("rear_side_enemy", 2, 0, 0)}
bot.teamfight = true
AssertEqual(NitoriPoke.Think(bot), true, "poke corrects an enemy-rear starting position")
AssertEqual(bot.actions[1].kind, "move", "rear-side correction issues movement")
Assert(DistanceLocations(bot.actions[1].location, J.GetTeamFountain())
	< DistanceLocations(enemies[1].location, J.GetTeamFountain()),
	"poke never selects another destination behind the enemy")

ResetScenario(2)
enemies = {NewHero("tower_poke_enemy", 2, 500, 0)}
local pokeTower = NewHero("poke_tower", 2, -550, 0)
pokeTower.IsHero = function() return false end
pokeTower.IsBuilding = function() return true end
pokeTower.IsTower = function() return true end
buildings = {pokeTower}
bot.teamfight = true
AssertEqual(NitoriPoke.Think(bot), true, "poke keeps control near enemy tower")
AssertEqual(bot.actions[1].kind, "move", "poke finds an alternate ring point")
Assert(GetUnitToLocationDistance(pokeTower, bot.actions[1].location) >= 900,
	"poke ring rejects visible enemy tower danger")
Assert(DistanceLocations(bot.actions[1].location, J.GetTeamFountain())
	< DistanceLocations(enemies[1].location, J.GetTeamFountain()),
	"tower avoidance still keeps the alternate point on the allied side")

ResetScenario(2)
enemies = {NewHero("queued_attack_enemy", 2, 700, 0)}
bot.teamfight = true
bot.blocked = true
AssertEqual(NitoriPoke.Think(bot), true, "poke owns a queued base-attack frame")
AssertEqual(bot.actions[1].kind, "move", "poke replaces the old Valve attack queue")

ResetScenario(2)
enemies = {NewHero("poke_cast_enemy", 2, 900, 0)}
bot.teamfight = true
bot.abilities.ability_thdots_nitori02.phase = true
Assert(NitoriPoke.GetModeDesire(bot) > BOT_MODE_DESIRE_VERYHIGH, "poke remains selected during cannon phase")
AssertEqual(NitoriPoke.Think(bot), true, "poke protects cannon phase")
AssertEqual(#bot.actions, 0, "poke does not replace cannon phase")

ResetScenario(2)
enemies = {NewHero("poke_locked_enemy", 2, 900, 0)}
bot.teamfight = true
bot.nitoriLastCombatActionTime = now
AssertEqual(NitoriPoke.Think(bot), true, "poke retains mode during action lock")
AssertEqual(#bot.actions, 0, "poke does not replace a same-frame combat action")

ResetScenario(1)
enemies = {NewHero("physical_enemy", 2, 500, 0)}
bot.teamfight = true
AssertEqual(NitoriPoke.GetModeDesire(bot), BOT_MODE_DESIRE_NONE, "physical damage does not use spell poke")

ResetScenario(2)
enemies = {NewHero("retreat_enemy", 2, 500, 0)}
bot.teamfight = true
bot.retreat = true
AssertEqual(NitoriPoke.GetModeDesire(bot), BOT_MODE_DESIRE_NONE, "retreat overrides spell poke")

ResetScenario(2)
enemies = {NewHero("poke_dash_enemy", 2, 700, 0)}
bot.going = true
bot.thdNitoriPokeActive = true
bot.abilities.ability_thdots_nitori01.castable = true
AbilityUsageThink()
AssertEqual(#bot.actions, 0, "spell poke suppresses offensive nitori01 dash")

-- 目标进入保守斩杀线后锁定收割：1 技能突进，飞行中先打强化攻击再接 3。
ResetScenario(2)
local harvestTarget = NewHero("harvest_target", 2, 800, 0)
harvestTarget.health = 330
enemies = {harvestTarget}
bot.teamfight = true
bot.facing = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
bot.modifiers.modifier_ability_thdots_nitori03_passive = true
AssertEqual(NitoriCombat.GetNitori03RawDamage(bot, bot.abilities.ability_thdots_nitori03), 180,
	"nitori03 uses magical_bonus plus attack and intellect")
AssertEqual(NitoriCombat.GetHarvestActualDamage(bot, harvestTarget, bot.abilities.ability_thdots_nitori03), 420,
	"harvest combines conservative empowered attack and nitori03")
Assert(NitoriPoke.GetModeDesire(bot) > BOT_MODE_DESIRE_VERYHIGH, "harvest keeps poke mode ownership")
AssertEqual(bot.thdNitoriHarvestState.target, harvestTarget, "harvest locks one target")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori01", "harvest starts with nitori01")
AssertEqual(bot.thdNitoriHarvestState.launched, true, "harvest records launch lifecycle")

now = now + 1
bot.actions = {}
bot.location = Vector(700, 0, 0)
bot.abilities.ability_thdots_nitori01.castable = false
bot.modifiers.modifier_ability_thdots_nitori01 = true
bot.modifiers.modifier_ability_thdots_nitori03_passive = true
AbilityUsageThink()
AssertEqual(bot.actions[1].kind, "attack", "harvest consumes empowered attack in flight")
AssertEqual(bot.actions[1].target, harvestTarget, "harvest attack keeps locked target")

now = now + 1
bot.actions = {}
bot.modifiers.modifier_ability_thdots_nitori03_passive = false
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori03", "harvest follows with nitori03")

ResetScenario(2)
local healthyPokeTarget = NewHero("healthy_poke_target", 2, 800, 0)
healthyPokeTarget.health = 400
enemies = {healthyPokeTarget}
bot.teamfight = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState, nil, "healthy target remains in poke mode")

ResetScenario(2)
harvestTarget = NewHero("equal_fight_harvest_target", 2, 800, 0)
harvestTarget.health = 330
local equalFightEnemy = NewHero("equal_fight_enemy", 2, 850, 100)
enemies = {harvestTarget, equalFightEnemy}
bot.teamfight = true
bot.allyCount = 1
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState, nil,
	"an even teamfight keeps poke distance instead of harvesting")

ResetScenario(2)
harvestTarget = NewHero("lost_advantage_harvest_target", 2, 800, 0)
harvestTarget.health = 330
enemies = {harvestTarget}
bot.teamfight = true
bot.allyCount = 2
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
Assert(bot.thdNitoriHarvestState ~= nil, "advantaged teamfight may lock a lethal harvest")
bot.allyCount = 0
AbilityUsageThink()
AssertEqual(#bot.actions, 0,
	"harvest rechecks team advantage before nitori01 launch")

ResetScenario(2)
harvestTarget = NewHero("outer_tower_harvest_target", 2, 800, 0)
harvestTarget.health = 300
enemies = {harvestTarget}
local harvestTower = NewHero("outer_tower", 2, 800, 0)
harvestTower.IsHero = function() return false end
harvestTower.IsBuilding = function() return true end
harvestTower.IsTower = function() return true end
buildings = {harvestTower}
bot.teamfight = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
Assert(bot.thdNitoriHarvestState ~= nil, "healthy supported harvest may dive an outer tower")

ResetScenario(2)
harvestTarget = NewHero("recent_tower_damage_target", 2, 800, 0)
harvestTarget.health = 300
enemies = {harvestTarget}
harvestTower = NewHero("recent_outer_tower", 2, 800, 0)
harvestTower.IsHero = function() return false end
harvestTower.IsBuilding = function() return true end
harvestTower.IsTower = function() return true end
buildings = {harvestTower}
bot.teamfight = true
bot.towerDamage = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState, nil, "recent tower damage blocks an outer-tower harvest")

ResetScenario(2)
harvestTarget = NewHero("unshared_high_ground_target", 2, 800, 0)
harvestTarget.health = 280
enemies = {harvestTarget}
local highGroundTower = NewHero("mid_tier_three", 2, 800, 0)
highGroundTower.IsHero = function() return false end
highGroundTower.IsBuilding = function() return true end
highGroundTower.IsTower = function() return true end
buildings = {highGroundTower}
towers["2:" .. tostring(TOWER_MID_3)] = highGroundTower
bot.teamfight = true
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState, nil, "unshared tier-three tower blocks harvest")

ResetScenario(2)
harvestTarget = NewHero("shared_high_ground_target", 2, 800, 0)
harvestTarget.health = 280
enemies = {harvestTarget}
local towerTank = NewHero("tower_tank", 1, 600, 0)
highGroundTower = NewHero("shared_mid_tier_three", 2, 800, 0)
highGroundTower.IsHero = function() return false end
highGroundTower.IsBuilding = function() return true end
highGroundTower.IsTower = function() return true end
highGroundTower.attackTarget = towerTank
buildings = {highGroundTower}
towers["2:" .. tostring(TOWER_MID_3)] = highGroundTower
bot.teamfight = true
bot.allyCount = 2
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState.allowHighGroundHarvest, true,
	"shared tier-three tower permits conservative harvest")
AbilityUsageThink()
AssertEqual(bot.actions[1].name, "ability_thdots_nitori01",
	"shared tier-three harvest may launch nitori01")

ResetScenario(2)
harvestTarget = NewHero("double_tier_four_target", 2, 800, 0)
harvestTarget.health = 280
enemies = {harvestTarget}
towerTank = NewHero("base_tower_tank", 1, 600, 0)
local baseTowerOne = NewHero("base_tower_one", 2, 800, 0)
local baseTowerTwo = NewHero("base_tower_two", 2, 820, 0)
for _, tower in ipairs({baseTowerOne, baseTowerTwo}) do
	tower.IsHero = function() return false end
	tower.IsBuilding = function() return true end
	tower.IsTower = function() return true end
end
baseTowerOne.attackTarget = towerTank
baseTowerTwo.attackTarget = nil
buildings = {baseTowerOne, baseTowerTwo}
towers["2:" .. tostring(TOWER_BASE_1)] = baseTowerOne
towers["2:" .. tostring(TOWER_BASE_2)] = baseTowerTwo
bot.teamfight = true
bot.allyCount = 3
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState, nil, "every covering tier-four tower needs another tank")

ResetScenario(2)
harvestTarget = NewHero("shared_double_tier_four_target", 2, 800, 0)
harvestTarget.health = 280
enemies = {harvestTarget}
local baseTowerTankOne = NewHero("base_tower_tank_one", 1, 600, 0)
local baseTowerTankTwo = NewHero("base_tower_tank_two", 1, 620, 0)
baseTowerOne = NewHero("shared_base_tower_one", 2, 800, 0)
baseTowerTwo = NewHero("shared_base_tower_two", 2, 820, 0)
for _, tower in ipairs({baseTowerOne, baseTowerTwo}) do
	tower.IsHero = function() return false end
	tower.IsBuilding = function() return true end
	tower.IsTower = function() return true end
end
baseTowerOne.attackTarget = baseTowerTankOne
baseTowerTwo.attackTarget = baseTowerTankTwo
buildings = {baseTowerOne, baseTowerTwo}
towers["2:" .. tostring(TOWER_BASE_1)] = baseTowerOne
towers["2:" .. tostring(TOWER_BASE_2)] = baseTowerTwo
bot.teamfight = true
bot.allyCount = 3
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState.allowHighGroundHarvest, true,
	"both shared tier-four towers permit conservative harvest")

ResetScenario(2)
harvestTarget = NewHero("unsupported_harvest_target", 2, 800, 0)
harvestTarget.health = 300
enemies = {harvestTarget}
bot.teamfight = true
bot.allyCount = 0
bot.abilities.ability_thdots_nitori01.castable = true
bot.abilities.ability_thdots_nitori03.castable = true
NitoriPoke.GetModeDesire(bot)
AssertEqual(bot.thdNitoriHarvestState, nil, "unsupported spell core does not harvest")

print("test_nitori_bot.lua: PASS")
