local J = require( GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')
local Scheduler = require(GetScriptDirectory()..'/thd2_scheduler')


local Defend = {}
local currentTime = DotaTime()
local maxDesire = 0.98
local DEFEND_DESIRE_CACHE_INTERVAL = 1.5
local DEFEND_DESIRE_STAGGER_INTERVAL = 0.14
local DEFEND_LANE_STICKY_SECONDS = 3.0
local DEFEND_LANES = {LANE_TOP, LANE_MID, LANE_BOT}


local function GetLaneState(bot, lane)
	if bot.DefendLaneState == nil then bot.DefendLaneState = {} end
	if bot.DefendLaneState[lane] == nil then bot.DefendLaneState[lane] = {} end
	return bot.DefendLaneState[lane]
end

local function GetDefendActiveModeForLane(lane)
	if lane == LANE_TOP then return BOT_MODE_DEFEND_TOWER_TOP end
	if lane == LANE_MID then return BOT_MODE_DEFEND_TOWER_MID end
	if lane == LANE_BOT then return BOT_MODE_DEFEND_TOWER_BOT end
	return BOT_MODE_NONE
end

function Defend.GetStableDefendLane(bot, requestedLane)
	if bot == nil then return requestedLane end

	local now = GameTime()
	local activeMode = bot:GetActiveMode()
	for _, lane in pairs(DEFEND_LANES) do
		if activeMode == GetDefendActiveModeForLane(lane) then
			bot.StableDefendLane = lane
			bot.StableDefendLaneUntil = now + DEFEND_LANE_STICKY_SECONDS
			return lane
		end
	end

	local ancientDefenseState = J.GetAncientDefenseState(1500)
	if ancientDefenseState ~= nil and ancientDefenseState.enemyPressure > 0 then
		if bot.StableDefendLane == nil or bot.StableDefendLaneUntil == nil or now >= bot.StableDefendLaneUntil then
			bot.StableDefendLane = requestedLane
			bot.StableDefendLaneUntil = now + DEFEND_LANE_STICKY_SECONDS
		end
		return bot.StableDefendLane
	end

	if bot.StableDefendLane ~= nil
	and bot.StableDefendLaneUntil ~= nil
	and now < bot.StableDefendLaneUntil
	then
		return bot.StableDefendLane
	end

	local selectedLane = requestedLane
	local bestDesire = -1
	if bot.DefendLaneDesire ~= nil then
		for _, lane in pairs(DEFEND_LANES) do
			local desire = bot.DefendLaneDesire[lane] or 0
			if desire > bestDesire then
				bestDesire = desire
				selectedLane = lane
			end
		end
	end

	bot.StableDefendLane = selectedLane
	bot.StableDefendLaneUntil = now + DEFEND_LANE_STICKY_SECONDS
	return selectedLane
end

function Defend.GetDefendDesire(bot, lane)
	local stableLane = Defend.GetStableDefendLane(bot, lane)
	if stableLane ~= lane then
		return BOT_MODE_DESIRE_NONE
	end

	return Timer.GetOrComputeBotLane('DefendDesire', bot, lane, DEFEND_DESIRE_CACHE_INTERVAL, function()
		return Defend.ComputeDefendDesire(bot, lane)
	end, DEFEND_DESIRE_STAGGER_INTERVAL)
end

function Defend.ComputeDefendDesire(bot, lane)
	if bot:IsIllusion() then return BOT_MODE_DESIRE_NONE end
	if bot.laneToDefend == nil then bot.laneToDefend = lane end
	if bot.DefendLaneDesire == nil then bot.DefendLaneDesire = {0, 0, 0} end
	local state = GetLaneState(bot, lane)

	currentTime = DotaTime()

	state.weAreStronger = false
	local defendLoc = GetLaneFrontLocation( bot:GetTeam(), lane, 0 )
	state.defendLoc = defendLoc

	-- 如果己方没有兵线，防御点设为对方兵线
	if J.Utils.GetLocationToLocationDistance(J.Utils.GetTeamFountainTpPoint(), defendLoc) < 3000 then
		local enemyLaneFront = GetLaneFrontLocation(GetOpposingTeam(), lane, 0)
		local hEnemyNearEnemyLaneFront = J.GetLastSeenEnemiesNearLoc(enemyLaneFront, 1600)
		local hAllyNearEnemyLaneFront = J.GetAlliesNearLoc(enemyLaneFront, 1600)
		if GetUnitToLocationDistance(bot, enemyLaneFront) > bot:GetAttackRange()
		and #hEnemyNearEnemyLaneFront <= #hAllyNearEnemyLaneFront + 1 then
			defendLoc = enemyLaneFront
			state.defendLoc = defendLoc
		end
	end

	state.distanceToLane = GetUnitToLocationDistance(bot, defendLoc)
	state.nInRangeAlly = J.GetNearbyHeroes(bot,1600,false,BOT_MODE_NONE)
	state.nInRangeEnemy = J.GetLastSeenEnemiesNearLoc( bot:GetLocation(), 1600)

	bot.DefendLaneDesire[lane] = Defend.GetDefendDesireHelper(bot, lane, state)
	local defendDesire = bot.DefendLaneDesire[lane]
	if defendDesire > 0.9 then
		J.Utils.GameStates['recentDefendTime'] = DotaTime()
	end
	return defendDesire
end

function Defend.GetDefendDesireHelper(bot, lane, state)

	local nSearchRange = 2500
	local team = bot:GetTeam()
	local laneFront = GetLaneFrontLocation(team, lane, 0)
	local ancient = GetAncient(team)
	local attackRange = bot:GetAttackRange()
	local defendLoc = state.defendLoc or GetLaneFrontLocation(team, lane, 0)
	state.defendLoc = defendLoc
	state.botTarget = J.GetProperTarget(bot);
	state.weAreStronger = J.WeAreStronger(bot, nSearchRange)

	local ancientDefenseState = J.GetAncientDefenseState(1500)
	state.nEnemyUnitsAroundAncient = ancientDefenseState.enemyPressure

	local nDefendAllyHeroes = J.GetAlliesNearLoc(defendLoc, nSearchRange)
	state.nEffctiveAllyHeroesNearPingedDefendLoc = #nDefendAllyHeroes + #J.Utils.GetAllyIdsInTpToLocation(defendLoc, nSearchRange)
	state.lEnemyHeroesAroundLoc = J.GetLastSeenEnemiesNearLoc(defendLoc, nSearchRange)
	state.aliveAllyHeroes = J.GetNumOfAliveHeroes(false)

	-- 如果基地附近有敌人，则重点防御基地
	if state.nEnemyUnitsAroundAncient > 0
	then
		nSearchRange = 1800
		local ancientHp = J.GetHP(ancient)

		defendLoc = ancient:GetLocation()
		state.defendLoc = defendLoc
		nDefendAllyHeroes = J.GetAlliesNearLoc(defendLoc, nSearchRange)
		state.nEffctiveAllyHeroesNearPingedDefendLoc = #nDefendAllyHeroes + #J.Utils.GetAllyIdsInTpToLocation(defendLoc, nSearchRange)
		state.lEnemyHeroesAroundLoc = J.GetLastSeenEnemiesNearLoc(defendLoc, nSearchRange)
		state.distanceToLane = GetUnitToLocationDistance(bot, defendLoc)

		if #state.lEnemyHeroesAroundLoc == 0 and (J.IsAnyAllyDefending(bot, lane) or state.nEffctiveAllyHeroesNearPingedDefendLoc >= 1) then
			return BOT_MODE_DESIRE_NONE
		end
		if (#nDefendAllyHeroes < state.nEnemyUnitsAroundAncient + 1
		or ancientHp < 0.95
		or (state.nEffctiveAllyHeroesNearPingedDefendLoc < state.aliveAllyHeroes and state.nEffctiveAllyHeroesNearPingedDefendLoc <= #state.lEnemyHeroesAroundLoc + 1 )
		or (#state.lEnemyHeroesAroundLoc >= 3 and state.nEffctiveAllyHeroesNearPingedDefendLoc < state.aliveAllyHeroes))
		and J.GetLocationToLocationDistance(defendLoc, laneFront) < nSearchRange
		and #J.GetNearbyHeroes(bot, math.max(attackRange + 100, 1000), true, BOT_MODE_NONE) <= 0
		and ((#state.nInRangeEnemy <= 1 and not (J.IsValidHero(state.botTarget) and J.GetHP(state.botTarget) < 0.3)) or not bot:WasRecentlyDamagedByAnyHero(2)) then
			print("Ancient is in danger for team " .. team)
			local desire = RemapValClamped(J.GetHP(bot), 0.25, 0.5, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_ABSOLUTE)
			return desire
		end
	end

	local distanceToDefendLoc = GetUnitToLocationDistance(bot, defendLoc)
	state.distanceToLane = distanceToDefendLoc
	local tpScoll = J.Utils.GetItemFromFullInventory(bot, 'item_tpscroll')

	-- 避免特殊情况还坚持防守
	if #state.nInRangeEnemy > 0 and distanceToDefendLoc < 1200
	or bot:GetLevel() < 3
	or (bot:GetAssignedLane() == LANE_MID and bot:GetLevel() < 10)
	or (J.IsDoingRoshan(bot) and J.GetRoshanTeamState(2800).isDoingRoshanWithTeam)
	then
		return BOT_MODE_DESIRE_NONE
	end

	local furthestBuilding, urgentNum, nBuildingfTier = Defend.GetFurthestBuildingOnLane(lane)

	-- 如果防御塔快没了，则不防守
	if J.CanBeAttacked(furthestBuilding) and furthestBuilding ~= GetAncient(team)
	then
		if (nBuildingfTier == 1 and J.GetHP(furthestBuilding) <= 0.15)
			or (nBuildingfTier == 2 and J.GetHP(furthestBuilding) <= 0.1)
		then
			return BOT_MODE_DESIRE_NONE
		end
	end

	-- 非关键性建筑，没tp，不防守
	if (currentTime < 4 * 60 )
	and bot:GetAssignedLane() ~= lane
	and distanceToDefendLoc > nSearchRange * 2
	and nBuildingfTier < 2
	then
		if not J.CanCastAbility(tpScoll) then
			return BOT_MODE_DESIRE_NONE
		end
	end

	local nDefendDesire = 0

	-- 如果不在当前线上，且等级低，不防守
	local botLevel = bot:GetLevel()
	if bot:GetAssignedLane() ~= lane
	and distanceToDefendLoc > 3000 and botLevel < 5 then
	return BOT_MODE_DESIRE_NONE
	end

	-- 如果附近没有敌方英雄，同时队友去防守了，则不防守
	if #state.lEnemyHeroesAroundLoc == 0 and J.IsAnyAllyDefending(bot, lane) then
		return BOT_MODE_DESIRE_NONE
	end

	-- 如果附近有1个敌方英雄，同时队友去防守了，则不防守
	if #state.lEnemyHeroesAroundLoc == 1
	and (state.nEffctiveAllyHeroesNearPingedDefendLoc > #state.lEnemyHeroesAroundLoc
		or (J.IsAnyAllyDefending(bot, lane) and J.GetAverageLevel(false) >= J.GetAverageLevel(true)))
	then
		return BOT_MODE_DESIRE_NONE
	end

	bot.laneToDefend = lane
	local nUnitsAroundBuilding = J.GetEnemiesAroundLoc(furthestBuilding:GetLocation(), nSearchRange)
	local lCloseEnemyHeroesAroundLoc = J.GetLastSeenEnemiesNearLoc(furthestBuilding:GetLocation(), 1200)
	local urgentMultipler = RemapValClamped(nUnitsAroundBuilding * urgentNum, 1, 15, 0.6, 3)

	-- 如果建筑物优先级大于等于3，且我方英雄数量不少于敌方英雄数量，则提高欲望
	if nBuildingfTier >= 3 and state.nEffctiveAllyHeroesNearPingedDefendLoc >= #state.lEnemyHeroesAroundLoc then
		maxDesire = 1
	end
	-- 按照血量、建筑物优先级 和初始欲望来重新计算欲望
	nDefendDesire = RemapValClamped(J.GetHP(bot), 0.75, 0.2, RemapValClamped(GetDefendLaneDesire(lane) * urgentMultipler, 0, 1, BOT_ACTION_DESIRE_NONE, maxDesire), BOT_ACTION_DESIRE_LOW)

	-- 如果距离防御点小于1600，且敌方英雄数量大于我方英雄数量，且我方不强，则降低欲望
	if (distanceToDefendLoc and distanceToDefendLoc < 1600 and #state.nInRangeEnemy > #state.nInRangeAlly) and not state.weAreStronger then
		-- 1. if we are not stronger, most likely defend == feed
		-- 2. we dont want to get stuck in defend mode too much because other modes are also important after bots arrive the location.
		nDefendDesire = RemapValClamped(nDefendDesire, 0, 1, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH)
	end

	-- 如果敌方英雄血量低于我方英雄血量，且距离小于1500，则降低欲望
	if J.IsValidHero(state.botTarget) and J.GetHP(state.botTarget) < 0.6 and J.GetHP(bot) > J.GetHP(state.botTarget) and GetUnitToUnitDistance(bot, state.botTarget) < 1500 then
		nDefendDesire = nDefendDesire * 0.4
	end

	-- 如果没tp，且距离大于4000，且目标地点建筑物附近没有敌方英雄，则降低欲望
	if not J.CanCastAbility(tpScoll) and distanceToDefendLoc > 4000
	then
		if #lCloseEnemyHeroesAroundLoc == 0 or bot:WasRecentlyDamagedByAnyHero(2) then
			nDefendDesire = nDefendDesire * 0.5
		end
		nDefendDesire = RemapValClamped(distanceToDefendLoc/4000, 0, 2, nDefendDesire, BOT_ACTION_DESIRE_VERYLOW)
	end

	return nDefendDesire
end

function Defend.DefendThink(bot, lane)
    if J.CanNotUseAction(bot) then return end
	local state = GetLaneState(bot, lane)
	local nSearchRange = 1800

	local attackRange = bot:GetAttackRange()
	local defendLoc = state.defendLoc or GetLaneFrontLocation(GetTeam(), lane, 0)
	local distanceToDefendLoc = GetUnitToLocationDistance(bot, defendLoc)
	state.distanceToLane = distanceToDefendLoc
	local nInRangeAlly = state.nInRangeAlly or J.GetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)
	local weAreStronger = state.weAreStronger or false
	local nEnemyUnitsAroundAncient = state.nEnemyUnitsAroundAncient or 0
	local nAttackSearchRange = attackRange < 900 and 900 or math.min(attackRange, nSearchRange)

	local nEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	local nEnemyHeroes_real = J.GetEnemiesNearLoc(defendLoc, nSearchRange)

	if J.IsValidHero(nEnemyHeroes_real[1]) and J.IsInRange(bot, nEnemyHeroes_real[1], nAttackSearchRange)
	then
		local target = J.GetStickyTarget(bot, 'defend_real_enemy_'..tostring(lane), nEnemyHeroes_real[1], 1.2, nAttackSearchRange + 250)
		J.ActionAttackUnit(bot, 'defend_attack_real_enemy', target, true, 0.35)
		return
	elseif J.IsValidHero(nEnemyHeroes[1]) and J.IsInRange(bot, nEnemyHeroes[1], nAttackSearchRange)
	then
		local target = J.GetStickyTarget(bot, 'defend_near_enemy_'..tostring(lane), nEnemyHeroes[1], 1.2, nAttackSearchRange + 250)
		J.ActionAttackUnit(bot, 'defend_attack_near_enemy', target, true, 0.35)
		return
	end


	if nEnemyUnitsAroundAncient > 0 then
		local ancient = GetAncient(GetTeam())
		if GetUnitToLocationDistance(ancient, defendLoc) < 100 then
			if GetUnitToUnitDistance(bot, ancient) > 3000 then
				local moveLoc = J.GetStableFormationLocation(bot, 'defend_move_ancient_'..tostring(lane), defendLoc, 300, 30.0)
				J.ActionMoveToLocation(bot, 'defend_move_ancient', moveLoc, 0.5, 240)
				return
			end

		end
	end

	if distanceToDefendLoc > nSearchRange then
		local moveLoc = J.GetStableFormationLocation(bot, 'defend_move_location_'..tostring(lane), defendLoc, 300, 30.0)
		J.ActionMoveToLocation(bot, 'defend_move_location_'..tostring(lane), moveLoc, 0.5, 240)
		return
	end


	local nEnemyLaneCreeps = bot:GetNearbyCreeps(900, true)
	if (nEnemyHeroes_real == nil or #nEnemyHeroes_real <= 0)
	and nEnemyLaneCreeps ~= nil and #nEnemyLaneCreeps > 0
	then
		local targetCreep = nil
		local attackDMG = 0
		for _, creep in pairs(nEnemyLaneCreeps)
		do
			if J.IsValid(creep)
			and J.CanBeAttacked(creep)
			and creep:GetAttackDamage() > attackDMG
			then
				attackDMG = creep:GetAttackDamage()
				targetCreep = creep
			end
		end

		if targetCreep ~= nil
		then
			targetCreep = J.GetStickyTarget(bot, 'defend_creep_'..tostring(lane), targetCreep, 1.0, 1200)
			J.ActionAttackUnit(bot, 'defend_attack_creep', targetCreep, true, 0.35)
			return
		end
	end

	local actionLoc = J.GetStableFormationLocation(bot, 'defend_action_'..tostring(lane), defendLoc, 300, 30.0)
	if weAreStronger or #nInRangeAlly >= #nEnemyHeroes_real then
		J.ActionAttackMove(bot, 'defend_attack_move_'..tostring(lane), actionLoc, 0.5, 260)
	else
		J.ActionMoveToLocation(bot, 'defend_move_fallback_'..tostring(lane), actionLoc, 0.5, 260)
	end

end

function Defend.GetFurthestBuildingOnLane(lane)
	local bot = GetBot()
	local FurthestBuilding = nil

	if lane == LANE_TOP then
		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_TOP_1)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 0.5, 3)
			return FurthestBuilding, mul, 1
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_TOP_2)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 1, 2)
			return FurthestBuilding, mul, 2
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_TOP_3)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 1.5, 2)
			return FurthestBuilding, mul, 3
		end

		FurthestBuilding = GetBarracks(bot:GetTeam(), BARRACKS_TOP_MELEE)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return FurthestBuilding, 2.5, 3
		end

		FurthestBuilding = GetBarracks(bot:GetTeam(), BARRACKS_TOP_RANGED)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return FurthestBuilding, 2.5, 3
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BASE_1)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 2.5, 3
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BASE_2)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 2.5, 3
		end

		FurthestBuilding = GetAncient(bot:GetTeam())
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 3, 4
		end
	end

	if lane == LANE_MID then
		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_MID_1)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 0.5, 3)
			return FurthestBuilding, mul, 1
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_MID_2)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 1, 2)
			return FurthestBuilding, mul, 2
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_MID_3)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 1.5, 2)
			return FurthestBuilding, mul, 3
		end

		FurthestBuilding = GetBarracks(bot:GetTeam(), BARRACKS_MID_MELEE)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return FurthestBuilding, 2.5, 3
		end

		FurthestBuilding = GetBarracks(bot:GetTeam(), BARRACKS_MID_RANGED)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return FurthestBuilding, 2.5, 3
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BASE_1)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 2.5, 3
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BASE_2)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 2.5, 3
		end

		FurthestBuilding = GetAncient(bot:GetTeam())
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 3, 4
		end
	end

	if lane == LANE_BOT then
		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BOT_1)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 0.5, 3)
			return FurthestBuilding, mul, 1
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BOT_2)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 1, 2)
			return FurthestBuilding, mul, 2
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BOT_3)
		if Defend.IsValidBuildingTarget(FurthestBuilding)
		then
			local nHealth = FurthestBuilding:GetHealth() / FurthestBuilding:GetMaxHealth()
			local mul = RemapValClamped(nHealth, 0.25, 1, 1.5, 2)
			return FurthestBuilding, mul, 3
		end

		FurthestBuilding = GetBarracks(bot:GetTeam(), BARRACKS_BOT_MELEE)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return FurthestBuilding, 2.5, 3
		end

		FurthestBuilding = GetBarracks(bot:GetTeam(), BARRACKS_BOT_RANGED)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return FurthestBuilding, 2.5, 3
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BASE_1)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 2.5, 3
		end

		FurthestBuilding = GetTower(bot:GetTeam(), TOWER_BASE_2)
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 2.5, 3
		end

		FurthestBuilding = GetAncient(bot:GetTeam())
		if Defend.IsValidBuildingTarget(FurthestBuilding) then
			return GetAncient(bot:GetTeam()), 3, 4
		end
	end

	return nil, 1, 0
end

function Defend.IsValidBuildingTarget(unit)
	if unit == nil then return false end

	local ok, result = pcall(function()
		return unit.IsAlive ~= nil
		and unit.IsBuilding ~= nil
		and unit.CanBeSeen ~= nil
		and unit:IsAlive()
		and unit:IsBuilding()
		and unit:CanBeSeen()
	end)

	return ok and result == true
end

function Defend.OnEnd() end

return Defend
