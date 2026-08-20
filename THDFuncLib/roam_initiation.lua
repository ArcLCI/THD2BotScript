local Config = require(GetScriptDirectory() .. '/THDFuncLib/roam_config')
local GeneratedHeroes = require(GetScriptDirectory() .. '/THDFuncLib/lane_assignment_generated')

local Initiation = {}
local states = {}
local CAST_START_GRACE = 0.35

-- 这里只登记“能够作为 gank 开场控制”的英雄与技能；实际目标选择和施法仍由英雄脚本负责。
local HERO_INITIATION = {
	 npc_dota_hero_Tensi = {
		abilityName = 'earthshaker_fissure',
		castMode = 'location',
		fallbackCastRange = 1200,
	},
	 npc_dota_hero_Minoriko = {
		abilityName = 'ability_thdots_minoriko01',
		castMode = 'entity',
		fallbackCastRange = 600,
	},
	npc_dota_hero_yuuka = {
		abilityName = 'ability_thdots_yuuka02',
		castMode = 'entity',
		fallbackCastRange = 600,
	},
	npc_dota_hero_kisume = {
		abilityName = 'ability_thdots_kisume01',
		castMode = 'location',
		fallbackCastRange = 900,
	},
	npc_dota_hero_sunny = {
		abilityName = 'ability_thdots_sunny02',
		castMode = 'no_target',
		fallbackCastRange = 300,
	},
	npc_dota_hero_Byakuren = {
		abilityName = 'ability_thdots_byakuren01',
		castMode = 'entity',
		fallbackCastRange = 150,
	},
	npc_dota_hero_merlin = {
		abilityName = 'ability_thdots_Merlin01',
		castMode = 'entity',
		fallbackCastRange = 250,
	},
	npc_dota_hero_Yugi = {
		abilityName = 'centaur_hoof_stomp',
		castMode = 'no_target',
		fallbackCastRange = 315,
	},
	npc_dota_hero_suwako = {
		abilityName = 'ability_thdots_suwako01',
		castMode = 'no_target',
		fallbackCastRange = 450,
	},
}

local function Safe(defaultValue, callback)
	local ok, value = pcall(callback)
	if ok then return value end
	return defaultValue
end

local function GetPlayerID(bot)
	if bot == nil or bot.GetPlayerID == nil then return -1 end
	return Safe(-1, function() return bot:GetPlayerID() end) or -1
end

local function GetNow()
	return Safe(0, function() return DotaTime() end) or 0
end

local function GetState(bot)
	local playerID = GetPlayerID(bot)
	if states[playerID] == nil then
		states[playerID] = {
			mission = nil,
			info = nil,
			status = 'idle',
			lastStatus = nil,
			event = nil,
			issuedAbilityName = nil,
			issuedTime = nil,
		}
	end
	return states[playerID]
end

local function GetHeroName(bot)
	if bot == nil or bot.GetUnitName == nil then return nil end
	local slotName = Safe(nil, function() return bot:GetUnitName() end)
	local entry = slotName ~= nil and GeneratedHeroes.heroes ~= nil
		and GeneratedHeroes.heroes[slotName]
		or nil
	-- Bot API 返回基础槽位；统一映射回 customHero 后再查询先手注册表。
	return entry ~= nil and entry.customHero or slotName
end

function Initiation.ResolveHeroName(bot)
	return GetHeroName(bot)
end

local function GetAbility(bot, info)
	if bot == nil or info == nil or bot.GetAbilityByName == nil then return nil end
	return Safe(nil, function() return bot:GetAbilityByName(info.abilityName) end)
end

local function IsAbilityReady(ability)
	if ability == nil then return false end
	if ability.IsFullyCastable == nil then return true end
	return Safe(false, function() return ability:IsFullyCastable() end) == true
end

local function IsAbilityInProgress(bot, ability)
	if ability ~= nil then
		if ability.IsInAbilityPhase ~= nil
			and Safe(false, function() return ability:IsInAbilityPhase() end)
		then return true end
		if ability.IsChanneling ~= nil
			and Safe(false, function() return ability:IsChanneling() end)
		then return true end
	end
	return (bot.IsCastingAbility ~= nil and Safe(false, function() return bot:IsCastingAbility() end))
		or (bot.IsUsingAbility ~= nil and Safe(false, function() return bot:IsUsingAbility() end))
		or (bot.IsChanneling ~= nil and Safe(false, function() return bot:IsChanneling() end))
end

local function GetDistance(first, second)
	if first == nil or second == nil then return math.huge end
	if GetUnitToUnitDistance ~= nil then
		local distance = Safe(nil, function() return GetUnitToUnitDistance(first, second) end)
		if type(distance) == 'number' then return distance end
	end
	local firstLocation = Safe(nil, function() return first:GetLocation() end)
	local secondLocation = Safe(nil, function() return second:GetLocation() end)
	if firstLocation == nil or secondLocation == nil then return math.huge end
	local dx = (firstLocation.x or 0) - (secondLocation.x or 0)
	local dy = (firstLocation.y or 0) - (secondLocation.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function IsValidTarget(target)
	if target == nil then return false end
	if target.CanBeSeen ~= nil and not Safe(false, function() return target:CanBeSeen() end) then return false end
	if target.IsAlive ~= nil and not Safe(false, function() return target:IsAlive() end) then return false end
	return true
end

local function GetCastRange(bot, info, ability)
	if ability ~= nil and ability.GetCastRange ~= nil then
		local range = Safe(nil, function() return ability:GetCastRange() end)
		if type(range) == 'number' and range > 0 then return range end
	end
	return info.fallbackCastRange or 0
end

local function SetEvent(state, event)
	if state.lastStatus ~= event then
		state.lastStatus = event
		state.event = event
	end
end

local function ConsumeEvent(state)
	local event = state.event
	state.event = nil
	return event
end

function Initiation.GetHeroInfo(bot)
	local heroName = GetHeroName(bot)
	if heroName == nil then return nil end
	return HERO_INITIATION[heroName]
end

function Initiation.GetAbility(bot)
	local info = Initiation.GetHeroInfo(bot)
	return GetAbility(bot, info), info
end

function Initiation.SelectOwner(mission, members)
	if mission == nil then return nil end
	local firstRegisteredID = nil
	for _, participantID in ipairs(mission.participantIDs or {}) do
		for _, member in ipairs(members or {}) do
			if GetPlayerID(member) == participantID then
				local info = Initiation.GetHeroInfo(member)
				if info ~= nil then
					if firstRegisteredID == nil then firstRegisteredID = participantID end
					if IsAbilityReady(GetAbility(member, info)) then return participantID end
				end
				break
			end
		end
	end
	return firstRegisteredID
end

-- 为日志保留完整的先手候选快照，区分英雄未登记、技能不存在和技能未就绪。
function Initiation.DescribeMission(mission, members)
	local result = {
		selectedID = nil,
		candidateCount = 0,
		registeredCount = 0,
		readyCount = 0,
		candidates = {},
	}
	if mission == nil then return result end

	for _, participantID in ipairs(mission.participantIDs or {}) do
		for _, member in ipairs(members or {}) do
			if GetPlayerID(member) == participantID then
				local heroName = GetHeroName(member)
				local info = Initiation.GetHeroInfo(member)
				local ability = GetAbility(member, info)
				local mapped = info ~= nil
				local ready = mapped and IsAbilityReady(ability) or false
				result.candidateCount = result.candidateCount + 1
				if mapped then result.registeredCount = result.registeredCount + 1 end
				if ready then result.readyCount = result.readyCount + 1 end
				table.insert(result.candidates, {
					playerID = participantID,
					heroName = heroName,
					abilityName = info ~= nil and info.abilityName or nil,
					mapped = mapped,
					ready = ready,
				})
				break
			end
		end
	end
	result.selectedID = Initiation.SelectOwner(mission, members)
	return result
end

function Initiation.Begin(bot, mission)
	local state = GetState(bot)
	if state.mission == mission then return state end
	state.mission = mission
	state.info = Initiation.GetHeroInfo(bot)
	state.status = 'pending'
	state.lastStatus = nil
	state.event = nil
	state.issuedAbilityName = nil
	state.issuedTime = nil
	return state
end

local function EnsureState(bot, mission)
	local state = GetState(bot)
	if state.mission ~= mission then return Initiation.Begin(bot, mission) end
	return state
end

local function IsOwner(bot, mission)
	if mission.initiationOwnerID == nil then return true end
	return GetPlayerID(bot) == mission.initiationOwnerID
end

local function MakeResult(state, status, hold, reason, target, castRange, needMove)
	return {
		status = status,
		hold = hold == true,
		reason = reason,
		target = target,
		castRange = castRange,
		needMove = needMove == true,
		event = ConsumeEvent(state),
	}
end

function Initiation.GetStatus(bot, mission)
	if mission == nil or mission.phase ~= 'engage' then return nil end
	local state = EnsureState(bot, mission)
	if state.info == nil then
		return MakeResult(state, 'unavailable', false, 'hero_not_registered')
	end
	if not IsOwner(bot, mission) then
		return MakeResult(state, 'non_owner', false, 'another_opener_selected')
	end
	local now = GetNow()
	if state.status == 'completed' then
		return MakeResult(state, 'completed', false, 'cast_finished')
	end
	if state.status == 'issued' then
		local ability = GetAbility(bot, state.info)
		local issuedElapsed = now - (state.issuedTime or now)
		if issuedElapsed < CAST_START_GRACE or IsAbilityInProgress(bot, ability) then
			return MakeResult(state, 'issued', true, nil, mission.target, nil, false)
		end
		-- 发令后只保护起手和真实施法过程；技能结束后必须恢复追击，不能锁到整次 gank 超时。
		state.status = 'completed'
		SetEvent(state, 'complete')
		return MakeResult(state, 'completed', false, 'cast_finished')
	end

	local engageStart = mission.engageStartTime or now
	if now - engageStart >= Config.INITIATION_TIMEOUT then
		state.status = 'fallback'
		SetEvent(state, 'fallback')
		return MakeResult(state, 'fallback', false, 'initiation_timeout')
	end

	local ability = GetAbility(bot, state.info)
	if not IsAbilityReady(ability) then
		state.status = 'fallback'
		SetEvent(state, 'fallback')
		return MakeResult(state, 'fallback', false, 'ability_unavailable')
	end

	local target = mission.target
	if not IsValidTarget(target) then
		state.status = 'fallback'
		SetEvent(state, 'fallback')
		return MakeResult(state, 'fallback', false, 'target_invalid')
	end

	local castRange = GetCastRange(bot, state.info, ability)
	local needMove = GetDistance(bot, target) > castRange
	local status = needMove and 'pending_move' or 'pending'
	state.status = 'pending'
	SetEvent(state, status)
	return MakeResult(state, status, true, nil, target, castRange, needMove)
end

function Initiation.GetIntent(bot)
	local state = GetState(bot)
	if state.mission == nil then return nil end
	local result = Initiation.GetStatus(bot, state.mission)
	if result == nil or not result.hold then return nil end
	return {
		target = result.target or state.mission.target,
		abilityName = state.info ~= nil and state.info.abilityName or nil,
		castMode = state.info ~= nil and state.info.castMode or nil,
		status = result.status,
		hold = true,
		castRange = result.castRange,
	}
end

function Initiation.ShouldHoldGenericAction(bot)
	local state = GetState(bot)
	if state.mission == nil then return false end
	local result = Initiation.GetStatus(bot, state.mission)
	return result ~= nil and result.hold == true
end

function Initiation.MarkIssued(bot, abilityName, target)
	local state = GetState(bot)
	if state.mission == nil or state.info == nil then return false end
	if state.mission.phase ~= 'engage' or not IsOwner(bot, state.mission) then return false end
	if abilityName ~= state.info.abilityName or target ~= state.mission.target then return false end
	state.status = 'issued'
	state.issuedAbilityName = abilityName
	state.issuedTime = GetNow()
	state.event = 'cast'
	return true
end

function Initiation.Clear(bot, mission)
	local state = GetState(bot)
	if mission ~= nil and state.mission ~= nil and state.mission ~= mission then return end
	states[GetPlayerID(bot)] = nil
end

function Initiation.ResetForTests()
	states = {}
end

return Initiation
