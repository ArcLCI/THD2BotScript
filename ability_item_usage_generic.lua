require(GetScriptDirectory() ..  "/thd2_item_usage")
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')

local X = {}
local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then return end
if not bot.frameProcessTime then bot.frameProcessTime = 0.1 end

local nCourierLastActionTime = -90
local nCourierState = -1
local nCourierReturnTime = -90
local nCourierDeliverTime = -90
local function CourierUsageComplement()

	if GetGameMode() == 23
		or DotaTime() < -56
		or nCourierReturnTime + 5.0 > DotaTime()
	then
		return
	end

	if bot.theCourier == nil
	then
		bot.theCourier = GetBotCourier( bot )
		return
	end

	--------* * * * * * * ----------------* * * * * * * ----------------* * * * * * * --------
	local npcCourier = bot.theCourier
	nCourierState = GetCourierState( npcCourier )
	local courierHP = npcCourier:GetHealth() / npcCourier:GetMaxHealth()
	local currentTime = DotaTime()
	local bAliveBot = bot:IsAlive()
	local botLV = bot:GetLevel()
	local useCourierCD = 2.3
	local protectCourierCD = 5.0
	--------* * * * * * * ----------------* * * * * * * ----------------* * * * * * * --------

	if nCourierState == COURIER_STATE_DEAD then return end

	if IsCourierTargetedByUnit( npcCourier )
	then
		if currentTime > nCourierReturnTime + protectCourierCD
		then
			nCourierReturnTime = currentTime

			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_RETURN_STASH_ITEMS )

			local abilityBurst = npcCourier:GetAbilityByName( 'courier_burst' )
			if botLV >= 4 and abilityBurst:IsFullyCastable()
			then
				bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_BURST )
			end

			return
		end
	end

	if ( nCourierState == COURIER_STATE_RETURNING_TO_BASE
		or nCourierState == COURIER_STATE_AT_BASE
		or nCourierState == COURIER_STATE_IDLE )
		and currentTime > nCourierReturnTime + protectCourierCD
	then

		if nCourierState == COURIER_STATE_AT_BASE and courierHP < 0.8
		then return	end

		if nCourierState == COURIER_STATE_IDLE and npcCourier:DistanceFromFountain() > 800
		then
			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_RETURN_STASH_ITEMS )
			return
		end

		if bAliveBot
			and ( not IsInvFull( bot )
					or currentTime <= 5 * 60
					or ( bot.currBuyingBasicItemList ~= nil and #bot.currBuyingBasicItemList == 0 ) )
			and ( nCourierState == COURIER_STATE_AT_BASE
					or ( nCourierState == COURIER_STATE_IDLE and npcCourier:DistanceFromFountain() < 800 ) )
		then
			local nMSlot = GetNumStashItem( bot )
			if nMSlot > 0
			-- and Utils.CountBackpackEmptySpace(bot) >= 1
			then
				if ( bot.currBuyingBasicItemList ~= nil and #bot.currBuyingBasicItemList == 0 )
					or ( bot.currBuyingBasicItem ~= nil and ( GetNumStashItem( bot ) == 6
					or bot:GetGold() + 80 < GetItemCost( bot.currBuyingBasicItem ) ) )
				then
					bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_TAKE_STASH_ITEMS )
					nCourierLastActionTime = currentTime

					if currentTime > nCourierDeliverTime + protectCourierCD
					then
						nCourierDeliverTime = currentTime
						local abilityBurst = npcCourier:GetAbilityByName( 'courier_burst' )
						if botLV >= 4 and abilityBurst:IsFullyCastable()
						then
							bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_BURST )
						end
					end
				end
			end
		end

		if bAliveBot
			and bot:GetCourierValue() > 0
			and bot:GetStashValue() < 100
			and ( not IsInvFull( bot ) or ( GetNumStashItem( bot ) == 0 and bot.currBuyingBasicItemList ~= nil and #bot.currBuyingBasicItemList == 0 ) )
			and ( npcCourier:DistanceFromFountain() < 4000 + botLV * 200 or GetUnitToUnitDistance( bot, npcCourier ) < 1800 )
			and currentTime > nCourierLastActionTime + useCourierCD
			-- and Utils.CountBackpackEmptySpace(bot) >= 1
		then
			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_TRANSFER_ITEMS )
			nCourierLastActionTime = currentTime
			return
		end


	end

end


function GetBotCourier( bot )

	local nPlayerID = bot:GetPlayerID()

	for nCourierID = 0, 11
	do
		local courier = GetCourier( nCourierID )
		if courier:GetPlayerID() == nPlayerID
		then
			return courier
		end
	end

end


function GetNumStashItem( unit )

	local amount = 0
	for i = 9, 14
	do
		if unit:GetItemInSlot( i ) ~= nil
		then
			amount = amount + 1
		end
	end

	return amount

end

function IsThereRecipeInStash( unit )
	local amount = 0

	for i = 9, 14
	do
		local item = unit:GetItemInSlot(i)
		if item ~= nil
		then
			if string.find(item:GetName(), "item_recipe_")
			then
				amount = amount + 1
			end
		end
	end

	return amount > 0
end


function IsCourierTargetedByUnit( courier )

	local botLV = bot:GetLevel()

	if GetHP( courier ) < 0.9
	then
		return true
	end

	if courier:DistanceFromFountain() < 900 then return false end

	for i = 0, 10
	do
		local tower = GetTower( GetOpposingTeam(), i )
		if tower ~= nil and tower:CanBeSeen()
		then
			local towerTarget = tower:GetAttackTarget()

			if towerTarget == courier
			then
				return true
			end

			if towerTarget == nil
				and GetUnitToUnitDistance( courier, tower ) < 999
			then
				return true
			end
		end
	end

	for _, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
	do
		if IsHeroAlive( id )
		then
			local info = GetHeroLastSeenInfo( id )
			if info ~= nil
			then
				local dInfo = info[1]
				if dInfo ~= nil
					and GetUnitToLocationDistance( courier, dInfo.location ) <= 800
					and dInfo.time_since_seen < 1.8
				then
					return true
				end
			end
		end
	end

	local nEnemysHeroesCanSeen = GetUnitList( UNIT_LIST_ENEMY_HEROES )
	for _, enemy in pairs( nEnemysHeroesCanSeen )
	do
		if GetUnitToUnitDistance( enemy, courier ) <= 700 + botLV * 15
		then
			local nNearCourierAllyList = GetAlliesNearLoc( enemy:GetLocation(), 600 )
			if #nNearCourierAllyList == 0
				or enemy:GetAttackTarget() == courier
			then
				return true
			end
		end

		if GetUnitToUnitDistance( enemy, courier ) <= enemy:GetAttackRange() + 88
		then
			return true
		end
	end

	local nEnemysHeroes = CachedGetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
	for _, enemy in pairs( nEnemysHeroes )
	do
		if enemy ~= nil and J.Utils.IsValidHero( enemy ) and GetUnitToUnitDistance( enemy, courier ) <= 700 + botLV * 15
		then
			local nNearCourierAllyList = GetAlliesNearLoc( enemy:GetLocation(), 800 )
			if #nNearCourierAllyList == 0
				or enemy:GetAttackTarget() == courier
			then
				return true
			end
		end

		if enemy ~= nil and J.Utils.IsValidHero( enemy ) and GetUnitToUnitDistance( enemy, courier ) <= enemy:GetAttackRange() + 100
		then
			return true
		end
	end

	local nAllEnemyCreeps = GetUnitList( UNIT_LIST_ENEMY_CREEPS )
	local nNearCourierAllyList = GetAlliesNearLoc( courier:GetLocation(), 1500 )
	local nNearCourierAllyCount = #nNearCourierAllyList
	for _, creep in pairs( nAllEnemyCreeps )
	do
		if GetUnitToUnitDistance( courier, creep ) <= 800
			and ( creep:GetAttackTarget() == courier or botLV > 4 )
			and ( nNearCourierAllyCount == 0 or creep:GetAttackTarget() == courier )
		then
			return true
		end
	end
	return false
end


function IsInvFull( bot )
	for i = 0, 8
	do
		if bot:GetItemInSlot(i) == nil
		then
			return false
		end
	end
	return true
end

function GetAlliesNearLoc( vLoc, nRadius )
	local allies = {}
	local cacheKey = 'GetAlliesNearLoc'..tostring(nRadius) ..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	if cache ~= nil then return cache end

	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember( i )
		if member ~= nil
			and member:IsAlive()
			and GetUnitToLocationDistance( member, vLoc ) <= nRadius
		then
			table.insert( allies, member )
		end
	end

	J.Utils.SetCachedVars(cacheKey, allies)

	return allies
end

function GetHP( unit )
	local nCurHealth = unit:GetHealth()
    local nMaxHealth = unit:GetMaxHealth()
	if nCurHealth <= 0 then return 0 end
	return nCurHealth / nMaxHealth
end

function CourierUsageThink()
	if bot.lastCourierFrameProcessTime == nil then bot.lastCourierFrameProcessTime = DotaTime() end
	if DotaTime() - bot.lastCourierFrameProcessTime < bot.frameProcessTime then return end
	bot.lastCourierFrameProcessTime = DotaTime()
	if not bot:IsIllusion() then CourierUsageComplement() end
end

local function ItemUsageComplement()

	X.SetStashItemTimeUpdate()

	if not bot:IsAlive()
		or bot:IsMuted()
		or bot:IsHexed()
		or bot:IsStunned()
		or bot:IsChanneling()
		or bot:IsInvulnerable()
		or bot:IsUsingAbility()
		or bot:IsCastingAbility()
		or bot:NumQueuedActions() > 0
		or bot:HasModifier( 'modifier_teleporting' )
	then return	BOT_ACTION_DESIRE_NONE end

	hNearbyEnemyHeroList = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE )
	hNearbyEnemyTowerList = bot:GetNearbyTowers( 888, true )
	botTarget = J.GetProperTarget( bot )
	nMode = bot:GetActiveMode()

	local aether = J.IsItemAvailable( "item_aether_lens" )
	if aether ~= nil then aetherRange = 250 else aetherRange = 0 end

	local nItemSlot = { 5, 4, 3, 2, 1, 0, 15, 16 }

	for _, nSlot in pairs( nItemSlot )
	do
		local hItem = bot:GetItemInSlot( nSlot )
		if J.CanCastAbility(hItem)
		then
			local sItemName = hItem:GetName()
			if	X.ConsiderItemDesire[sItemName] ~= nil
				and not X.IsItemInStash( sItemName )
			then
				local nItemDesire, hItemTarget, sCastType, sMotive = X.ConsiderItemDesire[sItemName]( hItem )

				if nItemDesire > 0
				then
					if bDebugMode
						and sMotive ~= nil
					--	and J.Item.IsDebugItem( sItemName )
						and J.Item.IsSpecifiedItem( sItemName )
					then
						-- local sReportItemName = J.Chat.GetItemCnName( sItemName )
						J.SetReportMotive( bDebugMode, sItemName..'→'..sMotive )
					end

					X.SetUseItem( hItem, hItemTarget, sCastType )

					return nSlot + 1
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--TP

X.ConsiderItemDesire["item_tpscroll"] = function( hItem )

	if bot:GetActiveMode() == BOT_MODE_RUNE
		or ( bot:IsRooted() )
		or ( bot:HasModifier( "modifier_teleporting" ) )
		or (J.IsDoingRoshan(bot) and GetUnitToLocationDistance(bot, J.GetCurrentRoshanLocation()) <= 2800)
	then return BOT_ACTION_DESIRE_NONE end

	if bot:GetHealth() < 240
	then
		local nProDamage = J.GetAttackProjectileDamageByRange( bot, 1600 ) * 2
		if bot:GetHealth() < bot:GetActualIncomingDamage( nProDamage, DAMAGE_TYPE_PHYSICAL )
		then return BOT_ACTION_DESIRE_NONE end
	end

	if bot.healInBase then return BOT_ACTION_DESIRE_NONE end

	local nNearbyEnemyTowers = bot:GetNearbyTowers( 888, true )
	if #nNearbyEnemyTowers > 0 then return BOT_ACTION_DESIRE_NONE end

	local tpLoc = nil
	local sCastType = 'ground'
	local hEffectTarget = nil
	local sCastMotive = nil
	local botTarget = nil
	local team = GetTeam()

	local nMinTPDistance = 5500
	local nMode = bot:GetActiveMode()
	local nModeDesire = bot:GetActiveModeDesire()
	local botLocation = bot:GetLocation()
	local botHP = J.GetHP( bot )
	local botMP = J.GetMP( bot )
	local nEnemyCount = X.GetNumHeroWithinRange( 1600 )
	local nAllyCount = J.GetAllyCount( bot, 1600 )

	if bot:GetLevel() > 12 and bot:DistanceFromFountain() < 600 then nMinTPDistance = nMinTPDistance + 600 end

	if nMode == BOT_MODE_LANING
	then
		hEffectTarget, shouldTp = X.GetLaningTPLocation(bot, nMinTPDistance, botLocation)
		sCastMotive = '出去发育'
		if shouldTp then return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	--守塔
	if J.IsDefending( bot )
		and nModeDesire > BOT_MODE_DESIRE_MODERATE
		and nEnemyCount == 0
	then
		local nDefendLane, sLane = LANE_MID, 'tower_mid'
		if nMode == BOT_MODE_DEFEND_TOWER_TOP then nDefendLane, sLane = LANE_TOP, 'tower_top' end
		if nMode == BOT_MODE_DEFEND_TOWER_BOT then nDefendLane, sLane = LANE_BOT, 'tower_bot' end

		local botAmount = GetAmountAlongLane( nDefendLane, botLocation )
		local laneFront = GetLaneFrontAmount( team, nDefendLane, false )
		if botAmount.distance > nMinTPDistance
			or botAmount.amount < laneFront / 5
		then
			tpLoc = X.GetDefendTPLocation( nDefendLane )
		end

		if tpLoc ~= nil
			and GetUnitToLocationDistance( bot, tpLoc ) > nMinTPDistance - 500
		then
			hEffectTarget = tpLoc
			sCastMotive = '前往守塔:'..sLane
			return BOT_ACTION_DESIRE_ABSOLUTE, hEffectTarget, sCastType, sCastMotive
		end
	end


	--推塔
	if J.IsPushing( bot )
		and nModeDesire >= BOT_MODE_DESIRE_MODERATE
		and nEnemyCount == 0
	then
		local nPushLane, sLane = LANE_MID, 'tower_mid'
		if nMode == BOT_MODE_PUSH_TOWER_TOP then nPushLane, sLane = LANE_TOP, 'tower_top' end
		if nMode == BOT_MODE_PUSH_TOWER_BOT then nPushLane, sLane = LANE_BOT, 'tower_bot' end

		local botAmount = GetAmountAlongLane( nPushLane, botLocation )
		local laneFront = GetLaneFrontAmount( team, nPushLane, false )
		if botAmount.distance > nMinTPDistance
			or botAmount.amount < laneFront / 5
		then
			tpLoc = X.GetPushTPLocation( nPushLane )
		end

		if tpLoc ~= nil
			and GetUnitToLocationDistance( bot, tpLoc ) > nMinTPDistance - 600
		then
			hEffectTarget = tpLoc
			sCastMotive = '前往推塔:'..sLane

			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	--撤退
	if nMode == BOT_MODE_RETREAT
		and nModeDesire >= BOT_MODE_DESIRE_MODERATE
		and bot:GetLevel() >= 3
	then

		--第一种情况:无敌人无大药回家恢复
		if botHP < 0.16
			and ( bot:WasRecentlyDamagedByAnyHero( 8.0 ) or botHP < 0.12 )
			and nEnemyCount == 0
			and bot:DistanceFromFountain() > nMinTPDistance
		then
			tpLoc = J.GetTeamFountain()
			sCastMotive = '撤退:1'

			return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
		end


		--第二种情况:有多个敌人但可以卡视野TP
		local nAttackAllyList = J.GetNearbyHeroes(bot, 1500, false, BOT_MODE_ATTACK )
		if botHP < ( 0.15 + 0.24 * nEnemyCount )
			and #nAttackAllyList == 0
			and bot:WasRecentlyDamagedByAnyHero( 6.0 )
			and X.CanJuke()
			and nEnemyCount <= ( botHP < 0.4 and 2 or 3 )
			and nAllyCount <= 2
			and bot:DistanceFromFountain() > nMinTPDistance - 600
		then
			tpLoc = J.GetTeamFountain()
			sCastMotive = '撤退:2'

			return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
		end

	end

	--支援团战和守家
	if bot:GetLevel() > 10
		and nMode ~= BOT_MODE_ROSHAN
		and nMode ~= BOT_MODE_ATTACK
		and ( botTarget == nil or not botTarget:IsHero() )
	then
		local nNearEnemyList = J.GetNearbyHeroes(bot, 1400, true, BOT_MODE_NONE )
		local nTeamFightLocation = J.GetTeamFightLocation( bot )
		local isTravelBootsAvailable = false
		if J.IsItemAvailable( "item_gap_creator" )
		then
			isTravelBootsAvailable = true
		end

		if #nNearEnemyList == 0
			and nTeamFightLocation ~= nil
			and GetUnitToLocationDistance( bot, nTeamFightLocation ) > nMinTPDistance - 1200
		then

			if isTravelBootsAvailable
			then
				sCastMotive = '飞鞋支援团战距离:'..GetUnitToLocationDistance( bot, nTeamFightLocation )
				return BOT_ACTION_DESIRE_HIGH, nTeamFightLocation, sCastType, sCastMotive
			end

			local bestTpLoc = J.GetNearbyLocationToTp( nTeamFightLocation )
			if bestTpLoc ~= nil
				and J.GetLocationToLocationDistance( bestTpLoc, nTeamFightLocation ) < 1800
				and GetUnitToLocationDistance( bot, bestTpLoc ) > nMinTPDistance - 1200
			then
				sCastMotive = '支援团战:'..GetUnitToLocationDistance( bot, nTeamFightLocation )
				return BOT_ACTION_DESIRE_HIGH, bestTpLoc, sCastType, sCastMotive
			end
		end

		--守护遗迹
		local nAncient = GetAncient( team )
		if bot:GetLevel() >= 15
			and #nNearEnemyList == 0
			and bot:DistanceFromFountain() > 2000
			and GetUnitToUnitDistance( bot, nAncient ) > nMinTPDistance - 200
			and J.GetAroundTargetAllyHeroCount( nAncient, 1400 ) == 0
		then
			local nEnemyLaneFront = J.GetNearestLaneFrontLocation( nAncient:GetLocation(), true, 400 )
			if nEnemyLaneFront ~= nil
				and GetUnitToLocationDistance( nAncient, nEnemyLaneFront ) <= 1600
			then sCastMotive = '守护遗迹'
				return BOT_ACTION_DESIRE_HIGH, nAncient:GetLocation(), sCastType, sCastMotive
			end

			local ancientTower1 = GetTower(team, 9)
			local ancientTower2 = GetTower(team, 10)
			if ancientTower1 == nil and ancientTower2 == nil
--				and nAncient:WasRecentlyDamagedByCreep( 5.0 )
			then
				local nAllEnemyCreeps = GetUnitList( UNIT_LIST_ENEMY_CREEPS )
				for _, creep in pairs( nAllEnemyCreeps )
				do
					if J.IsValid(creep)
					and GetUnitToUnitDistance( nAncient, creep ) <= 800
					and ( creep:GetAttackTarget() == nAncient or bot:GetLevel() >= 15 )
					then sCastMotive = '保护遗迹'
						return BOT_ACTION_DESIRE_HIGH, nAncient:GetLocation(), sCastType, sCastMotive
					end
				end
			end
		end
	end


	return BOT_ACTION_DESIRE_NONE

end

function X.GetNumHeroWithinRange( nRange )

	local enemyPids = GetTeamPlayers( GetOpposingTeam() )

	local cHeroes = 0
	for i = 1, #enemyPids
	do
		local info = GetHeroLastSeenInfo( enemyPids[i] )
		if info ~= nil then
			local dInfo = info[1]
			if dInfo ~= nil and dInfo.time_since_seen < 2.0
				and GetUnitToLocationDistance( bot, dInfo.location ) < nRange
			then
				cHeroes = cHeroes + 1
			end
		end
	end

	return cHeroes

end

function X.GetLaningTPLocation( bot, nMinTPDistance, botLocation )

	local laneToTP
	local tp = false
	local position = J.GetPosition(bot)
	local team = GetTeam()

	if team == TEAM_RADIANT then
		if position == 1 then
			laneToTP = LANE_BOT
		elseif position == 2 then
			laneToTP = LANE_MID
		elseif position == 3 or position == 4 then
			laneToTP = LANE_TOP
		elseif position == 5 then
			laneToTP = LANE_BOT
		end
	elseif team == TEAM_DIRE then
		if position == 1 then
			laneToTP = LANE_TOP
		elseif position == 2 then
			laneToTP = LANE_MID
		elseif position == 3 or position == 4 then
			laneToTP = LANE_BOT
		elseif position == 5 then
			laneToTP = LANE_TOP
		end
	end

	local botAmount = GetAmountAlongLane(laneToTP, botLocation)
	local laneFront = GetLaneFrontAmount(team, laneToTP, false)
	if botAmount.distance > nMinTPDistance
	or botAmount.amount < laneFront / 5
	then
		tp = true
	end

	return GetLaneFrontLocation(team, laneToTP, 100), tp
end

function X.GetDefendTPLocation( nLane )
	local team = GetTeam()
	return GetLaneFrontLocation( team, nLane, -950 )

end

function X.GetPushTPLocation( nLane )
	local team = GetTeam()
	local laneFront = GetLaneFrontLocation( team, nLane, 0 )
	local bestTpLoc = J.GetNearbyLocationToTp( laneFront )
	if J.GetLocationToLocationDistance( laneFront, bestTpLoc ) < 2000
	then
		return bestTpLoc
	end

end

function X.CanJuke()

	local allyTowers = bot:GetNearbyTowers( 350, false )

	if allyTowers[1] ~= nil
		and allyTowers[1]:DistanceFromFountain() > bot:DistanceFromFountain() + 100
		and J.GetEnemyCount( bot, 700 ) == 0
	then return true end

	local enemyPids = GetTeamPlayers( GetOpposingTeam() )

	local heroHG = GetHeightLevel( bot:GetLocation() )
	for i = 1, #enemyPids
	do
		local info = GetHeroLastSeenInfo( enemyPids[i] )
		if info ~= nil then
			local dInfo = info[1]
			if dInfo ~= nil
				and dInfo.time_since_seen < 2.0
			then
				if GetUnitToLocationDistance( bot, dInfo.location ) < 1300
					and GetHeightLevel( dInfo.location ) < heroHG
				then
					return false
				end

				if GetUnitToLocationDistance( bot, dInfo.location ) < 600
				then
					local hNearbyEnemyHeroList = J.GetNearbyHeroes(bot, 600, true, BOT_MODE_NONE )
					if #hNearbyEnemyHeroList == 0
					then
						return false
					end
				end
			end
		end
	end

	local totalDamage = 0
	local nEnemies = J.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE )
	for _, enemy in pairs( nEnemies )
	do
		local enemyDamage = enemy:GetEstimatedDamageToTarget( true, bot, 4.0, DAMAGE_TYPE_ALL )
		totalDamage = totalDamage + enemyDamage
		if bot:OriginalGetHealth() <= totalDamage
		then
			return false
		end
	end

	return true

end

function ItemUsageThink()
	if RefreshBotHandle() then return end
	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
	if bot.lastItemFrameProcessTime == nil then bot.lastItemFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastItemFrameProcessTime < (bot.frameProcessTime * (1 + Customize.ThinkLess))) then return end
	bot.lastItemFrameProcessTime = DotaTime()
	if not J.IsNoItemIllution(bot) then ItemUsageComplement() end
end

function AbilityUsageThink()
	if RefreshBotHandle() then return end
	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
	if bot.lastAbilityFrameProcessTime == nil then bot.lastAbilityFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastAbilityFrameProcessTime < (bot.frameProcessTime * (1 + Customize.ThinkLess))) and bot.isBear == nil then return end
	bot.lastAbilityFrameProcessTime = DotaTime()
	if BotBuild ~= nil and not J.IsNoAbilityIllution(bot) then BotBuild.SkillsComplement() end
end

X.AbilityUsageThink = AbilityUsageThink
X.ItemUsageThink = ItemUsageThink

return X