local Tasks = require(GetScriptDirectory()..'/THDFuncLib/mode_task')
local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
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

	if not Utils.AllowModeDesire(bot, 'outpost') then CandidateDebug.Note('mode_switch_lock'); return BOT_MODE_DESIRE_NONE end
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
		CandidateDebug.Note('team_push_proximity')
		return BOT_MODE_DESIRE_NONE;
	end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		CandidateDebug.Note('ancient_pressure')
		return BOT_MODE_DESIRE_NONE
	end

	----------
	-- Outpost
	----------

	if not IsEnemyTier2Down then CandidateDebug.Note('tier2_not_unlocked'); return BOT_ACTION_DESIRE_NONE end

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
		CandidateDebug.Note('late_outpost_too_far')
		return BOT_MODE_DESIRE_NONE
	end

	if DotaTime() > 30 * 60 and #bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) > 0 then
		CandidateDebug.Note('late_enemy_nearby')
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
				CandidateDebug.Note('enemy_near_outpost')
				return BOT_ACTION_DESIRE_NONE
			end
		end

		CandidateDebug.Note('capture_candidate')
		return RemapValClamped(GetUnitToUnitDistance(bot, ClosestOutpost), 3000, 0, BOT_ACTION_DESIRE_VERYLOW, BOT_ACTION_DESIRE_HIGH )
	end

	CandidateDebug.Note('no_suitable_outpost')
	return BOT_ACTION_DESIRE_NONE
end

local function OutpostSafe(target)
	return Actions.ValidTarget(target) and target:GetTeam() ~= bot:GetTeam()
		and not target:IsInvulnerable() and IsSuitableToCaptureOutpost()
		and not J.Retreat.ShouldYield(bot,J.Retreat.HIGH)
		and not IsEnemyCloserToOutpostLoc(target:GetLocation(),GetUnitToUnitDistance(bot,target))
		and #bot:GetNearbyHeroes(1600,true,BOT_MODE_NONE)==0
end

function GetDesire()
	local active=Tasks.Active(bot,'outpost')
	if active ~= nil and Actions.Protected(bot) then return active.score end
	if active ~= nil and not Tasks.Check(bot,'outpost',OutpostSafe(active.target)) then return 0 end
	local score=Utils.GetCachedModeDesire(bot,'outpost',ComputeDesire,
		DotaTime()>OUTPOST_LATE_GAME_TIME and OUTPOST_DESIRE_LATE_INTERVAL or OUTPOST_DESIRE_INTERVAL)
	if score<=0 or not OutpostSafe(ClosestOutpost) then Tasks.Release(bot,'outpost','unsafe_or_complete');return 0 end
	return Tasks.Offer(bot,'outpost',score,{target=ClosestOutpost,reason='capture',stallSeconds=8})
end

function OnStart()
	Utils.NoteModeStart(bot,'outpost')
	Tasks.Start(bot,'outpost')
end

function OnEnd()
	Tasks.Release(bot,'outpost','mode_end')
	ClosestOutpost=nil
	ClosestOutpostDist=10000
end

function Think()
	Tasks.Commit(bot,'outpost')
	-- 保护先于所有任务清理，模式丢失不撤销已经提交的占领引导。
	if Actions.Protected(bot) or J.CanNotUseAction(bot) then return end
	local task=Tasks.Active(bot,'outpost')
	if not Tasks.Check(bot,'outpost',task~=nil and OutpostSafe(task.target)) then return end
	if not Timer.ShouldRunBotTask(bot,'outpost_think',0.5,0.05) then return end
	local target=task.target
	if GetUnitToUnitDistance(bot,target)>300 then
		J.ActionMoveToLocation(bot,'outpost_move',target:GetLocation(),0.5,100)
	elseif hAbilityCapture~=nil and not hAbilityCapture:IsNull() and hAbilityCapture:IsFullyCastable() then
		Actions.Protect(bot,hAbilityCapture,0.35)
		bot:Action_UseAbilityOnEntity(hAbilityCapture,target)
	elseif hAbilityCapture==nil then
		J.ActionAttackUnit(bot,'outpost_attack',target,false,0.5)
	end
end

function GetClosestOutpost()
	local closest = nil
	local dist = 10000

	for i = 1, 2
	do
		if Actions.ValidTarget(Outposts[i])
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

GetDesire = Actions.GuardDesire(bot,BOT_MODE_OUTPOST,GetDesire)

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('outpost', GetDesire)
