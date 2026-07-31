local YuukaUnits = {}

local FLOWER_NAME = "ability_yuuka_flower"
local HERO_NAME = "npc_dota_hero_venomancer"
local FLOWER_MODIFIER = "modifier_thdots_yuukaex_flower"
local CACHE_INTERVAL = 0.25

local function IsNullUnit(unit)
	if unit == nil then return true end
	if unit.IsNull == nil then return false end
	local ok, result = pcall(function() return unit:IsNull() end)
	return not ok or result == true
end

local function IsAlive(unit)
	if IsNullUnit(unit) or unit.IsAlive == nil then return false end
	local ok, result = pcall(function() return unit:IsAlive() end)
	return ok and result == true
end

local function IsIllusion(unit)
	if IsNullUnit(unit) or unit.IsIllusion == nil then return false end
	local ok, result = pcall(function() return unit:IsIllusion() end)
	return ok and result == true
end

local function GetValidPlayerIDs(unit)
	local ids = {}
	local hasValidID = false
	for _, methodName in pairs({"GetPlayerID", "GetPlayerOwnerID"}) do
		if unit ~= nil and unit[methodName] ~= nil then
			local ok, id = pcall(function() return unit[methodName](unit) end)
			if ok and id ~= nil and id >= 0 then
				ids[id] = true
				hasValidID = true
			end
		end
	end
	return ids, hasValidID
end

local function IsOwnedByBot(bot, unit)
	if bot == nil or unit == nil then return true end
	if unit.GetOwner ~= nil then
		local ok, owner = pcall(function() return unit:GetOwner() end)
		if ok and owner ~= nil then return owner == bot end
	end
	local botIDs, hasBotID = GetValidPlayerIDs(bot)
	local unitIDs, hasUnitID = GetValidPlayerIDs(unit)
	if not hasBotID or not hasUnitID then return true end
	for id in pairs(unitIDs) do
		if botIDs[id] then return true end
	end
	return false
end

local function GetState(bot)
	if bot.thdYuukaUnitsState == nil then
		bot.thdYuukaUnitsState = {
			lastScanTime = -90,
			flowers = {},
			allies = {},
			illusion = nil,
		}
	end
	return bot.thdYuukaUnitsState
end

local function Refresh(bot, force)
	local state = GetState(bot)
	local now = DotaTime()
	if not force and now - state.lastScanTime < CACHE_INTERVAL then return state end

	state.lastScanTime = now
	state.flowers = {}
	state.allies = {}
	state.illusion = nil
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES)) do
		if IsAlive(unit) then
			table.insert(state.allies, unit)
			local unitName = unit:GetUnitName()
			if unitName == FLOWER_NAME and IsOwnedByBot(bot, unit) then
				table.insert(state.flowers, unit)
			elseif unit ~= bot and unitName == HERO_NAME and IsIllusion(unit) and IsOwnedByBot(bot, unit) then
				state.illusion = unit
			end
		end
	end
	return state
end

function YuukaUnits.Invalidate(bot)
	if bot == nil then return end
	GetState(bot).lastScanTime = -90
end

function YuukaUnits.GetState(bot)
	return GetState(bot)
end

function YuukaUnits.GetFlowers(bot, force)
	return Refresh(bot, force).flowers
end

function YuukaUnits.GetAllies(bot, force)
	return Refresh(bot, force).allies
end

function YuukaUnits.GetIllusion(bot, force)
	local illusion = Refresh(bot, force).illusion
	return IsAlive(illusion) and illusion or nil
end

function YuukaUnits.IsPermanentFlower(flower)
	if not IsAlive(flower) or flower:GetUnitName() ~= FLOWER_NAME
	or flower.GetModifierByName == nil or flower.GetModifierRemainingDuration == nil
	then
		return nil
	end
	local ok, index = pcall(function() return flower:GetModifierByName(FLOWER_MODIFIER) end)
	if not ok or index == nil or index < 0 then return nil end
	local durationOk, duration = pcall(function() return flower:GetModifierRemainingDuration(index) end)
	if not durationOk or duration == nil then return nil end
	return duration <= 0
end

function YuukaUnits.GetFlowerCount(bot)
	local permanent = 0
	local unknown = 0
	for _, flower in pairs(YuukaUnits.GetFlowers(bot)) do
		local isPermanent = YuukaUnits.IsPermanentFlower(flower)
		if isPermanent == true then permanent = permanent + 1
		elseif isPermanent == nil then unknown = unknown + 1 end
	end
	if permanent > 0 or unknown == 0 then return permanent end

	-- 旧版 Bot API 看不到隐藏持续时间时退回本体 stack；维护逻辑只在脱战时读取，临时花通常已消失。
	if bot.GetModifierByName ~= nil and bot.GetModifierStackCount ~= nil then
		local ok, index = pcall(function()
			return bot:GetModifierByName("modifier_thdots_yuukaex_bonus_damage")
		end)
		if ok and index ~= nil and index >= 0 then
			local stackOk, stack = pcall(function() return bot:GetModifierStackCount(index) end)
			if stackOk and stack ~= nil and stack >= 0 then return stack end
		end
	end
	return unknown
end

function YuukaUnits.GetMaxFlowerCount(bot, ability)
	if ability ~= nil and ability.GetSpecialValueInt ~= nil then
		local ok, value = pcall(function() return ability:GetSpecialValueInt("max_flower") end)
		if ok and value ~= nil and value > 0 then return value end
	end
	local result = 5
	if bot ~= nil and bot.GetAbilityByName ~= nil then
		local talent = bot:GetAbilityByName("special_bonus_unique_yuuka_3")
		if talent ~= nil and talent.GetLevel ~= nil and talent:GetLevel() > 0 then result = result + 15 end
	end
	return result
end

function YuukaUnits.CountFlowersNearLocation(bot, location, radius, permanentOnly)
	local count = 0
	for _, flower in pairs(YuukaUnits.GetFlowers(bot)) do
		if (not permanentOnly or YuukaUnits.IsPermanentFlower(flower) ~= false)
		and GetUnitToLocationDistance(flower, location) <= radius
		then
			count = count + 1
		end
	end
	return count
end

function YuukaUnits.GetNearestFlowerTo(bot, target, maximumBotRange)
	local bestFlower = nil
	local bestDistance = math.huge
	for _, flower in pairs(YuukaUnits.GetFlowers(bot)) do
		if (maximumBotRange == nil or GetUnitToUnitDistance(bot, flower) <= maximumBotRange) then
			local distance = GetUnitToUnitDistance(target, flower)
			if distance < bestDistance then
				bestFlower = flower
				bestDistance = distance
			end
		end
	end
	return bestFlower, bestDistance
end

local function GetNearestEnemyDistance(unit, enemies)
	local best = 1600
	for _, enemy in pairs(enemies or {}) do
		local distance = GetUnitToUnitDistance(unit, enemy)
		if distance < best then best = distance end
	end
	return best
end

local function IsLegalTeleportTarget(target)
	if not IsAlive(target) or (target.IsBuilding ~= nil and target:IsBuilding()) then return false end
	if target:GetUnitName() == FLOWER_NAME then return true end
	if target.IsHero ~= nil and target:IsHero() then return true end
	return target.IsCreep ~= nil and target:IsCreep()
end

local function IsNearEnemyBuilding(target, threats)
	for _, threat in pairs(threats or {}) do
		if threat.IsBuilding ~= nil and threat:IsBuilding()
		and GetUnitToUnitDistance(target, threat) <= 750
		then
			return true
		end
	end
	return false
end

function YuukaUnits.GetBestRetreatTarget(bot, castRange, allowAnyAlly, fountain, enemies)
	local state = Refresh(bot)
	local candidates = allowAnyAlly and state.allies or state.flowers
	local botFountainDistance = GetUnitToLocationDistance(bot, fountain)
	local botEnemyDistance = GetNearestEnemyDistance(bot, enemies)
	local bestTarget = nil
	local bestScore = -math.huge
	for _, target in pairs(candidates) do
		if target ~= bot and IsLegalTeleportTarget(target)
		and not IsNearEnemyBuilding(target, enemies)
		and GetUnitToUnitDistance(bot, target) <= castRange
		then
			local progress = botFountainDistance - GetUnitToLocationDistance(target, fountain)
			local clearanceGain = GetNearestEnemyDistance(target, enemies) - botEnemyDistance
			if progress >= 200 or clearanceGain >= 250 then
				local score = progress + clearanceGain * 0.45
				if target:GetUnitName() == FLOWER_NAME then score = score + 80 end
				if score > bestScore then
					bestTarget = target
					bestScore = score
				end
			end
		end
	end
	return bestTarget
end

function YuukaUnits.GetBestGardenLocation(bot, castRange, radius)
	local state = Refresh(bot)
	local candidates = {{location = bot:GetLocation()}}
	for _, flower in pairs(state.flowers) do table.insert(candidates, {location = flower:GetLocation()}) end
	if IsAlive(state.illusion) then table.insert(candidates, {location = state.illusion:GetLocation()}) end

	local bestLocation = nil
	local bestScore = 0
	for _, candidate in pairs(candidates) do
		local location = candidate.location
		if GetUnitToLocationDistance(bot, location) <= castRange then
			local score = GetUnitToLocationDistance(bot, location) <= radius and 2 or 0
			for _, flower in pairs(state.flowers) do
				if GetUnitToLocationDistance(flower, location) <= radius then score = score + 1 end
			end
			if IsAlive(state.illusion)
			and GetUnitToLocationDistance(state.illusion, location) <= radius
			then
				score = score + 2
			end
			if score > bestScore then
				bestLocation = location
				bestScore = score
			end
		end
	end
	return bestLocation, bestScore
end

function YuukaUnits.GetBestUltimateFlower(bot, castRange, focus)
	local bestFlower = nil
	local bestScore = -math.huge
	for _, flower in pairs(YuukaUnits.GetFlowers(bot)) do
		local botDistance = GetUnitToUnitDistance(bot, flower)
		if botDistance <= castRange then
			local score = -botDistance * 0.2
			if focus ~= nil then score = score - GetUnitToUnitDistance(flower, focus) end
			-- 临时花即将消失，优先用来支付大招，不破坏永久传送网络。
			if YuukaUnits.IsPermanentFlower(flower) == false then score = score + 500 end
			if score > bestScore then
				bestFlower = flower
				bestScore = score
			end
		end
	end
	return bestFlower
end

return YuukaUnits
