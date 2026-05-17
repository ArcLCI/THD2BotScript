local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local OUTPOST_DESIRE_INTERVAL = 1.8
local OUTPOST_DESIRE_LATE_INTERVAL = 5.0
local OUTPOST_DESIRE_STAGGER = 0.13
local OUTPOST_LATE_GAME_TIME = 25 * 60
local OUTPOST_LATE_MAX_DISTANCE = 1800

local Outposts = {}
local DidWeGetOutpost = false
local ClosestOutpost = nil
local ClosestOutpostDist = 10000

local IsEnemyTier2Down = false
local hAbilityCapture = bot:GetAbilityByName('ability_capture')

local function ComputeDesire()

	if not Utils.AllowModeDesire(bot, 'outpost') then return BOT_MODE_DESIRE_NONE end
	if not IsEnemyTier2Down
	then
		if GetTower(GetOpposingTeam(), TOWER_TOP_2) == nil
		or GetTower(GetOpposingTeam(), TOWER_MID_2) == nil
		or GetTower(GetOpposingTeam(), TOWER_BOT_2) == nil
		then
			IsEnemyTier2Down = true
		end
	end

	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE;
	end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		return BOT_MODE_DESIRE_NONE
	end

	----------
	-- Outpost
	----------

	if not IsEnemyTier2Down then return BOT_ACTION_DESIRE_NONE end

	local outpostDesireInterval = OUTPOST_DESIRE_INTERVAL
	if DotaTime() > OUTPOST_LATE_GAME_TIME then
		outpostDesireInterval = OUTPOST_DESIRE_LATE_INTERVAL
	end

	if not Timer.ShouldRunBotTask(bot, 'outpost_desire', outpostDesireInterval, OUTPOST_DESIRE_STAGGER) then
		return BOT_MODE_DESIRE_NONE
	end

	if not DidWeGetOutpost
	then
		for _, unit in pairs(GetUnitList(UNIT_LIST_ALL))
		do
			if unit:GetUnitName() == '#DOTA_OutpostName_North'
			or unit:GetUnitName() == '#DOTA_OutpostName_South'
			then
				table.insert(Outposts, unit)
			end
		end

		DidWeGetOutpost = true
	end

	ClosestOutpost, ClosestOutpostDist = GetClosestOutpost()
	if DotaTime() > OUTPOST_LATE_GAME_TIME and ClosestOutpostDist > OUTPOST_LATE_MAX_DISTANCE then
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() > 30 * 60 and #bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) > 0 then
		return BOT_MODE_DESIRE_NONE
	end

	if ClosestOutpost ~= nil and ClosestOutpostDist < 3000
	and not IsEnemyCloserToOutpostLoc(ClosestOutpost:GetLocation(), ClosestOutpostDist)
	and IsSuitableToCaptureOutpost()
	then
		if GetUnitToUnitDistance(bot, ClosestOutpost) < 600
		then
			local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), bot:GetCurrentVisionRange())
			if nInRangeEnemy ~= nil and #nInRangeEnemy >= 1
			then
				return BOT_ACTION_DESIRE_NONE
			end
		end

		return RemapValClamped(GetUnitToUnitDistance(bot, ClosestOutpost), 3000, 0, BOT_ACTION_DESIRE_VERYLOW, BOT_ACTION_DESIRE_HIGH )
	end

	return BOT_ACTION_DESIRE_NONE
end

function GetDesire()
	return Utils.GetCachedModeDesire(bot, 'outpost', ComputeDesire)
end

function OnStart()
	Utils.NoteModeStart(bot, 'outpost')
end

function OnEnd()
	ClosestOutpost = nil
	ClosestOutpostDist = 10000
	ShouldWaitInBaseToHeal = false
end

function Think()
	if not Timer.ShouldRunBotTask(bot, 'outpost_think', 0.50, 0.05) then return end
	if J.CanNotUseAction(bot) then return end

	if ClosestOutpost ~= nil
	then
		if GetUnitToUnitDistance(bot, ClosestOutpost) > 300
		then
			J.ActionMoveToLocation(bot, 'outpost_move', ClosestOutpost:GetLocation(), 0.5, 180)
			return
		else
			if hAbilityCapture then
				bot:Action_UseAbilityOnEntity(hAbilityCapture, ClosestOutpost)
			else
				J.ActionAttackUnit(bot, 'outpost_attack', ClosestOutpost, false, 0.5)
			end
			return
		end
	end
end

function GetClosestOutpost()
	local closest = nil
	local dist = 10000

	for i = 1, 2
	do
		if Outposts[i] ~= nil
		and Outposts[i]:GetTeam() ~= GetTeam()
		and GetUnitToUnitDistance(bot, Outposts[i]) < dist
		and not Outposts[i]:IsNull()
		and not Outposts[i]:IsInvulnerable()
		then
			closest = Outposts[i]
			dist = GetUnitToUnitDistance(bot, Outposts[i])
		end
	end

	return closest, dist
end

function IsEnemyCloserToOutpostLoc(opLoc, botDist)
	for _, id in pairs(GetTeamPlayers(GetOpposingTeam()))
	do
		local info = GetHeroLastSeenInfo(id)

		if info ~= nil
		then
			local dInfo = info[1]
			if dInfo ~= nil
			then
				if dInfo ~= nil
				and dInfo.time_since_seen < 5
				and J.GetDistance(dInfo.location, opLoc) < botDist
				then
					return true
				end
			end
		end
	end

	return false
end

function IsSuitableToCaptureOutpost()
	local botTarget = J.GetProperTarget(bot)

	if (J.IsGoingOnSomeone(bot) and J.IsValidTarget(botTarget) and GetUnitToUnitDistance(bot, botTarget) < 700)
	or J.IsDefending(bot)
	or (J.IsDoingRoshan(bot) and J.IsRoshan(botTarget) and J.IsAttacking(bot))
	or (J.IsRetreating(bot) and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_HIGH)
	or bot:WasRecentlyDamagedByAnyHero(5)
	or bot:GetActiveMode() == BOT_MODE_DEFEND_ALLY
	or J.GetNumOfAliveHeroes( false ) < J.GetNumOfAliveHeroes( true )
	then
		return false
	end

	return true
end
