local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")

local X = {}

local HERO_NAME = "npc_dota_hero_rattletrap"
local ULTIMATE_MODIFIER = "modifier_ability_thdots_sunny04"
local TARGET_RANGE = 1600
local RELEASE_HEALTH_RATIO = 0.35
local THINK_INTERVAL = 0.10

local function NewState()
	return {
		phase = "idle",
		lastThinkTime = -90,
		lastTargetSeenTime = -90,
	}
end

local function GetState(bot)
	if bot.sunnyUltimateState == nil then
		bot.sunnyUltimateState = NewState()
	end
	return bot.sunnyUltimateState
end

local function ResetState(bot)
	bot.sunnyUltimateState = NewState()
	return bot.sunnyUltimateState
end

local function IsHighPriorityRetreat(bot)
	return J.Retreat ~= nil
		and J.Retreat.ShouldYield ~= nil
		and J.Retreat.ShouldYield(bot, J.Retreat.HIGH)
end

local function IsVisibleRealHero(bot, target)
	return target ~= nil
		and not target:IsNull()
		and target:CanBeSeen()
		and target:IsAlive()
		and target:IsHero()
		and target:GetTeam() ~= bot:GetTeam()
		and not target:IsInvulnerable()
		and not target:IsMagicImmune()
		and not J.IsSuspiciousIllusion(target)
end

local function RememberTarget(state, target)
	if target == nil or target:IsNull() or not target:CanBeSeen() then return end
	state.lastKnownTargetLocation = target:GetLocation()
	state.lastTargetSeenTime = DotaTime()
end

local function IsBetterTarget(bot, state, candidate, best)
	if best == nil then return true end
	local properTarget = J.GetProperTarget(bot)
	local candidatePreferred = candidate == state.preferredTarget or candidate == properTarget
	local bestPreferred = best == state.preferredTarget or best == properTarget
	if candidatePreferred ~= bestPreferred then return candidatePreferred end
	if candidate:GetHealth() ~= best:GetHealth() then
		return candidate:GetHealth() < best:GetHealth()
	end
	return GetUnitToUnitDistance(bot, candidate) < GetUnitToUnitDistance(bot, best)
end

local function FindBestTarget(bot, state)
	local best = nil
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if IsVisibleRealHero(bot, enemy)
		and GetUnitToUnitDistance(bot, enemy) <= TARGET_RANGE
		and IsBetterTarget(bot, state, enemy, best)
		then
			best = enemy
		end
	end
	return best
end

local function ShouldReleaseActiveControl(bot, state)
	if state.phase ~= "active" then return false end
	if J.GetHP(bot) <= RELEASE_HEALTH_RATIO then return true end
	-- Bot 只能依据可见信息判断；范围内没有有效英雄时立即让其他模式接管，不追缓存坐标。
	return FindBestTarget(bot, state) == nil
end

local function Update(bot)
	local state = GetState(bot)
	if bot:GetUnitName() ~= HERO_NAME or not bot:IsAlive() then return ResetState(bot) end

	if bot:HasModifier(ULTIMATE_MODIFIER) then
		state.phase = "active"
		return state
	end
	if state.phase == "pending" and DotaTime() <= (state.pendingUntil or -90) then return state end
	if state.phase ~= "idle" then return ResetState(bot) end
	return state
end

function X.BeginCast(bot, target, reason)
	local now = DotaTime()
	bot.sunnyUltimateState = {
		phase = "pending",
		pendingUntil = now + 1.0,
		preferredTarget = target,
		lockedTarget = target,
		castReason = reason or "unknown",
		lastThinkTime = -90,
		lastTargetSeenTime = -90,
	}
	RememberTarget(bot.sunnyUltimateState, target)
end

function X.IsActive(bot)
	local phase = Update(bot).phase
	return phase == "pending" or phase == "active"
end

function X.GetModeDesire(bot)
	if bot:GetUnitName() ~= HERO_NAME or IsHighPriorityRetreat(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	local state = Update(bot)
	if ShouldReleaseActiveControl(bot, state) then return BOT_MODE_DESIRE_NONE end
	if state.phase == "pending" or state.phase == "active" then return BOT_MODE_DESIRE_ABSOLUTE end
	return BOT_MODE_DESIRE_NONE
end

function X.Think(bot)
	if bot:GetUnitName() ~= HERO_NAME then return false end
	local state = Update(bot)
	if IsHighPriorityRetreat(bot) then return false end
	if state.phase ~= "active" then return state.phase == "pending" end
	if ShouldReleaseActiveControl(bot, state) then return false end
	if J.CanNotUseAction(bot) then return true end

	local now = DotaTime()
	if now - (state.lastThinkTime or -90) < THINK_INTERVAL then return true end
	state.lastThinkTime = now

	local target = state.lockedTarget
	if not IsVisibleRealHero(bot, target) or GetUnitToUnitDistance(bot, target) > TARGET_RANGE then
		target = FindBestTarget(bot, state)
		state.lockedTarget = target
	end

	if target ~= nil then
		RememberTarget(state, target)
		J.SetTargetIfChanged(bot, target, 0.15)
		J.ActionAttackUnit(bot, "sunny_ultimate_face_target", target, false, 0.20)
		return true
	end
	return false
end

return X
