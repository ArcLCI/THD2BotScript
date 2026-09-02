local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local Utils = require( GetScriptDirectory()..'/THDFuncLib/utils')
local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local local_mode_laning_generic = nil
local nAllyCreeps = nil
local nEnemyCreeps = nil
local nFurthestEnemyAttackRange = 0
local nInRangeEnemy = nil
local botAssignedLane = nil
local botAttackRange = bot:GetAttackRange()
local attackDamage = bot:GetAttackDamage()

local skipLaningState = {
	count = 0,
	lastCheckTime = 0,
	checkGap = 3,
}

local function ComputeDesire()
	if not Utils.AllowModeDesire(bot, 'laning') then CandidateDebug.Note('mode_switch_lock'); return BOT_MODE_DESIRE_NONE end
	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then CandidateDebug.Note('invalid_or_unavailable_bot'); return BOT_MODE_DESIRE_NONE end
	local botLV = bot:GetLevel()
	local currentTime = DotaTime()

	botAttackRange = bot:GetAttackRange()
	nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	nEnemyCreeps = bot:GetNearbyLaneCreeps(800, true)
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(nInRangeEnemy)
	if local_mode_laning_generic then
		botAssignedLane = local_mode_laning_generic.GetBotTargetLane()
	else
		botAssignedLane = bot:GetAssignedLane()
	end
	attackDamage = bot:GetAttackDamage()
	if bot:GetItemSlotType(bot:FindItemSlot("item_quelling_blade")) == ITEM_SLOT_TYPE_MAIN then
		if bot:GetAttackRange() > 310 then
			attackDamage = attackDamage + 7
		else
			attackDamage = attackDamage + 12
		end
	end

	if bot:GetItemSlotType(bot:FindItemSlot("item_wind_gun")) == ITEM_SLOT_TYPE_MAIN then
		attackDamage = attackDamage + 30
	end

	if currentTime < 0 then CandidateDebug.Note('pregame'); return BOT_ACTION_DESIRE_NONE end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		CandidateDebug.Note('ancient_pressure')
		return BOT_MODE_DESIRE_NONE
	end

	if bot:WasRecentlyDamagedByAnyHero(5)
	and #J.Utils.GetLastSeenEnemyIdsNearLocation(bot:GetLocation(), 800) > 0 then
		local nLaneFrontLocation = GetLaneFrontLocation(GetTeam(), bot:GetAssignedLane(), 0)
		local nDistFromLane = GetUnitToLocationDistance(bot, nLaneFrontLocation)
		if not J.WeAreStronger(bot, 1200) or (nDistFromLane > 700 and J.GetHP(bot) < 0.7) then
			CandidateDebug.Note('recent_hero_danger')
			return BOT_MODE_DESIRE_NONE
		end
	end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		CandidateDebug.Note('team_push_proximity')
		return BOT_MODE_DESIRE_NONE
	end
	if local_mode_laning_generic then
		-- last hit
		if J.IsInLaningPhase() then
			local hitCreep, _ = GetBestLastHitCreep(nEnemyCreeps)
			if J.IsValid(hitCreep) then
				CandidateDebug.Note('last_hit')
				return 0.9
			end
		end
	end
	if local_mode_laning_generic and local_mode_laning_generic.GetDesire ~= nil then return local_mode_laning_generic.GetDesire() end

	if currentTime <= 10 then CandidateDebug.Note('opening_lane'); return 0.268 end
	if currentTime <= 9 * 60 and botLV <= 7 then CandidateDebug.Note('early_low_level'); return 0.446 end
	if currentTime <= 12 * 60 and botLV <= 11 then CandidateDebug.Note('mid_low_level'); return 0.369 end
	if botLV <= 15 then CandidateDebug.Note('level_at_most_15'); return 0.228 end

	J.Utils.GameStates.passiveLaningTime = true
	CandidateDebug.Note('level_above_15')
	return BOT_MODE_DESIRE_NONE
end

function GetDesire()
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then CandidateDebug.Note('high_retreat'); return BOT_MODE_DESIRE_NONE end
	return Utils.GetCachedModeDesire(bot, 'laning', ComputeDesire)
end

function OnStart()
	Utils.NoteModeStart(bot, 'laning')
	skipLaningState.count = skipLaningState.count + 1
end

function GetFurthestEnemyAttackRange(enemyList)
	local attackRange = 0
	for _, enemy in pairs(enemyList) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then
			local enemyAttackRange = enemy:GetAttackRange()
			if enemyAttackRange > attackRange then
				attackRange = enemyAttackRange
			end
		end
	end

	return attackRange
end

function GetBestLastHitCreep(hCreepList)
	local dmgDelta = attackDamage * 0.7

	local moveToCreep = nil
	for _, creep in pairs(hCreepList) do
		if J.IsValid(creep) and J.CanBeAttacked(creep) then
			local nDelay = J.GetAttackProDelayTime(bot, creep)
			if J.WillKillTarget(creep, attackDamage, DAMAGE_TYPE_PHYSICAL, nDelay) then
				return creep, false
			end
			if J.WillKillTarget(creep, attackDamage + dmgDelta, DAMAGE_TYPE_PHYSICAL, nDelay) then
				moveToCreep = creep
			end
		end
	end
	if moveToCreep then
		return moveToCreep, true
	end

	return nil
end

function GetBestDenyCreep(hCreepList)
	for _, creep in pairs(hCreepList)
	do
		local currentHealth, maxHealth = J.Utils.GetVisibleHealth(creep)
		if J.IsValid(creep)
		and currentHealth ~= nil
		and maxHealth > 0
		and currentHealth / maxHealth < 0.49
		and J.CanBeAttacked(creep)
		and currentHealth <= attackDamage
		then
			return creep
		end
	end

	return nil
end

if local_mode_laning_generic then
	function Think()
		if not Timer.ShouldRunBotTask(bot, 'laning_think', 0.15, 0.02) then return end
		if J.CanNotUseAction(bot) then return end
		if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then return end
		local hitCreep, moveToCreep = GetBestLastHitCreep(nEnemyCreeps)
		if J.IsValid(hitCreep) then
			J.SetTargetIfChanged(bot, hitCreep, 0.3)
			J.ActionAttackUnit(bot, 'laning_last_hit', hitCreep, true, 0.25)
			return
		end

		local denyCreep = GetBestDenyCreep(nAllyCreeps)
		if J.IsValid(denyCreep) then
			J.SetTargetIfChanged(bot, denyCreep, 0.3)
			J.ActionAttackUnit(bot, 'laning_deny', denyCreep, true, 0.25)
			return
		end

		if local_mode_laning_generic then
			local_mode_laning_generic.Think()
		end

		local fLaneFrontAmount = GetLaneFrontAmount(GetTeam(), botAssignedLane, false)
		local fLaneFrontAmount_enemy = GetLaneFrontAmount(GetOpposingTeam(), botAssignedLane, false)

		local nLongestAttackRange = math.max(botAttackRange, 250, nFurthestEnemyAttackRange)

		local target_loc = GetLaneFrontLocation(GetTeam(), botAssignedLane, -nLongestAttackRange)
		if fLaneFrontAmount_enemy < fLaneFrontAmount then
			target_loc = GetLaneFrontLocation(GetOpposingTeam(), botAssignedLane, -nLongestAttackRange)
		end

		J.ActionMoveToLocation(bot, 'laning_move_front', J.GetStableFormationLocation(bot, 'laning_move_front', target_loc, 80, 10.0), 0.5, 180)
	end
end

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('laning', GetDesire)
