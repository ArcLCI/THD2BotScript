local Actions = require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Tasks = require(GetScriptDirectory()..'/THDFuncLib/mode_task')
local CandidateDebug = require(GetScriptDirectory()..'/THDFuncLib/mode_candidate_debug')
local bot = GetBot()
local botName = bot:GetUnitName()
local Utils = require(GetScriptDirectory()..'/THDFuncLib/utils')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local Timer = require(GetScriptDirectory()..'/thd2_timer')

local IsAvoidingAbilityZone = false
local IsAvoidingAbilityProjectile = false
local IsAttackingSpecialUnit = false
local IsYugi04 = false

local nNextActionTime= 0

local immediateSpecialUnits = {
	['npc_dota_phoenix_sun'] = {
		radius = 1400,
		desire = BOT_ACTION_DESIRE_VERYHIGH,
	},
}

local MINORIKO_BOX_NAME = 'npc_thdots_unit_minoriko02_box'
local MINORIKO_BOX_NORMAL_MAX_HEALTH = 4
local MINORIKO_BOX_EMPOWERED_AURA_RADIUS = 700
local MINORIKO_BOX_ATTACK_RANGE_MARGIN = 100

local specialTarget
local yugi04Target

local TEAM_ROAM_DESIRE_INTERVAL = 0.45
local TEAM_ROAM_DESIRE_STAGGER = 0.07

local function ComputeDesire()
	if not Utils.AllowModeDesire(bot, 'team_roam') then CandidateDebug.Note('mode_switch_lock'); return BOT_MODE_DESIRE_NONE end

    IsAvoidingAbilityZone = false
	IsAvoidingAbilityProjectile = false
	IsAttackingSpecialUnit = false
	IsYugi04 = false
	specialTarget = nil

	local botMode = bot:GetActiveMode()

	-- 即时危险区规避高于普通撤退；其余特殊攻击在高风险撤退时全部让出。
	if HasModifierThatNeedToAvoidEffects() then
		IsAvoidingAbilityZone = true
		print("bot to avoid some abilities: " .. botName)
		CandidateDebug.Note('danger_modifier')
		return BOT_MODE_DESIRE_ABSOLUTE + 0.1
	end

	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then
		CandidateDebug.Note('high_retreat')
		return BOT_MODE_DESIRE_NONE
	end

	local specialUnitPlan = GetSpecialUnitAttackPlan(botMode)
	local isSeriouslyRetreating = J.IsSeriouslyRetreating(bot)
	if specialUnitPlan ~= nil and specialUnitPlan.immediate and not isSeriouslyRetreating then
		IsAttackingSpecialUnit = true
		specialTarget = specialUnitPlan.target
		print("bot to attack some special unit: " .. botName)
		CandidateDebug.Note('immediate_special_unit')
		return specialUnitPlan.desire
	end

	if SpecialYugi04() and not isSeriouslyRetreating then
		IsYugi04 = true
		CandidateDebug.Note('yugi_special')
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end

	if specialUnitPlan ~= nil and not isSeriouslyRetreating then
		IsAttackingSpecialUnit = true
		specialTarget = specialUnitPlan.target
		CandidateDebug.Note('special_unit')
		return specialUnitPlan.desire
	end

	--[[if HasProjectileThatNeedToAvoid(GetLinearProjectiles()) then
		IsAvoidingAbilityProjectile = true
		print("bot to avoid some projectiles: " .. botName)
		return BOT_ACTION_DESIRE_VERYHIGH + 0.1
	end]]

	CandidateDebug.Note('no_special_task')
	return BOT_MODE_DESIRE_NONE
end

function HasModifierThatNeedToAvoidEffects()
	-- 危险 modifier 直接检查，避免普通模式缓存延迟即时规避。
	local res = bot:HasModifier('modifier_thdots_clown04_debuff') -- 可能无视魔免的技能
	or bot:HasModifier('modifier_ability_thdots_tojiko05_debuff')
	or bot:HasModifier('modifier_ability_thdots_child02_debuff')
	return res
end

function HasProjectileThatNeedToAvoid(nProjectiles)
	for _, p in pairs(nProjectiles)
	do
		if p ~= nil
		and p.caster ~= nil
		and p.ability ~= nil
		and p.caster:GetTeam() ~= bot:GetTeam()
		and (p.ability:GetName() == "ability_thdots_ellen03"
		or p.ability:GetName() == "ability_thdots_ellen04")
        then
			if GetUnitToLocationDistance(bot, p.location) <= 2000 then
				return true
			end
		end
	end
	return false
end

local function IsBetterSpecialUnitPlan(candidate, current)
	return current == nil
		or candidate.desire > current.desire
		or (candidate.desire == current.desire and candidate.distance < current.distance)
end

local function CountEnemyHeroesSupportedByBox(box)
	local count = 0
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and enemyHero:GetTeam() == box:GetTeam()
		and not J.IsSuspiciousIllusion(enemyHero)
		and GetUnitToUnitDistance(box, enemyHero) <= MINORIKO_BOX_EMPOWERED_AURA_RADIUS
		then
			count = count + 1
		end
	end
	return count
end

local function IsHeroEngagementMode(botMode)
	return botMode == BOT_MODE_ROAM
		or botMode == BOT_MODE_GANK
		or botMode == BOT_MODE_ATTACK
		or botMode == BOT_MODE_DEFEND_ALLY
end

local function GetMinorikoBoxAttackPlan(box, botMode)
	if botMode == BOT_MODE_RETREAT then return nil end

	local distance = GetUnitToUnitDistance(bot, box)
	local attackDistance = bot:GetAttackRange() + MINORIKO_BOX_ATTACK_RANGE_MARGIN
	if distance > attackDistance then return nil end

	-- 普通箱子是一次性的对线补给，避免为 80 金经验打断补刀或英雄交战。
	if botMode == BOT_MODE_LANING then
		return {
			target = box,
			desire = BOT_MODE_DESIRE_LOW,
			distance = distance,
		}
	end

	-- 强化箱子有 700 范围攻速光环，但需要 8 次攻击；仅多人受益且已经在攻击范围内时中等处理。
	local isEmpowered = box:GetMaxHealth() > MINORIKO_BOX_NORMAL_MAX_HEALTH
	if isEmpowered and CountEnemyHeroesSupportedByBox(box) >= 2 then
		return {
			target = box,
			desire = BOT_MODE_DESIRE_MODERATE,
			distance = distance,
		}
	end

	if IsHeroEngagementMode(botMode) then return nil end

	return {
		target = box,
		desire = BOT_MODE_DESIRE_LOW,
		distance = distance,
	}
end

function GetSpecialUnitAttackPlan(botMode)
	local cachedPlan = Timer.GetOrCompute('TeamRoamSpecialUnit-'..tostring(bot:GetPlayerID()), 0.4, function()
		local bestPlan
		for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMIES))
		do
			if J.CanBeAttacked(enemy) and enemy:GetTeam() ~= bot:GetTeam() then
				local enemyName = enemy:GetUnitName()
				local distance = GetUnitToUnitDistance(bot, enemy)
				local rule = immediateSpecialUnits[enemyName]
				local candidate

				if rule ~= nil and distance <= rule.radius then
					candidate = {
						target = enemy,
						desire = rule.desire,
						distance = distance,
						immediate = true,
					}
				elseif enemyName == MINORIKO_BOX_NAME then
					candidate = GetMinorikoBoxAttackPlan(enemy, botMode)
				end

				if candidate ~= nil and IsBetterSpecialUnitPlan(candidate, bestPlan) then
					bestPlan = candidate
				end
			end
		end
		return bestPlan or false
	end)

	if cachedPlan == false or cachedPlan == nil or not Tasks.Valid(bot,{target=cachedPlan.target}) then return nil end
	return cachedPlan
end

function SpecialYugi04()
	if bot:GetUnitName() == "npc_dota_hero_centaur" then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( bot, 500, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( J.IsValidHero(npcEnemy) and npcEnemy:CanBeSeen()
			and SafeHasModifier(npcEnemy, "modifier_thdots_yugi04_think_interval" ))
			then
				yugi04Target = npcEnemy
				return true
			end
		end
	end
	return false
end

local function TaskSafe(task)
	if task == nil then return false end
	if task.kind == 'avoid' then return HasModifierThatNeedToAvoidEffects() end
	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) or J.IsSeriouslyRetreating(bot) then return false end
	if not Actions.ValidTarget(task.target) or not J.CanBeAttacked(task.target) then return false end
	if task.kind == 'yugi' then
		return GetUnitToUnitDistance(bot,task.target)<=500 and SafeHasModifier(task.target, 'modifier_thdots_yugi04_think_interval')
	end
	local name=task.target:GetUnitName()
	if name==MINORIKO_BOX_NAME then return GetMinorikoBoxAttackPlan(task.target,bot:GetActiveMode())~=nil end
	local rule=immediateSpecialUnits[name]
	return rule~=nil and GetUnitToUnitDistance(bot,task.target)<=rule.radius
end

function GetDesire()
	local active=Tasks.Active(bot,'team_roam')
	if active ~= nil and not HasModifierThatNeedToAvoidEffects() and (not Tasks.Check(bot,'team_roam',TaskSafe(active))) then return 0 end
	-- 危险modifier即时处理；普通候选允许短缓存，但缓存命中也重新验证句柄和安全。
	local score
	if HasModifierThatNeedToAvoidEffects() then score=ComputeDesire()
	else score=Utils.GetCachedModeDesire(bot,'team_roam',ComputeDesire,TEAM_ROAM_DESIRE_INTERVAL) end
	-- 空候选直接返回，避免高频缓存命中时仍构造候选表。
	if score<=0 then Tasks.Release(bot,'team_roam','no_candidate');return 0 end
	local candidate={kind=IsAvoidingAbilityZone and 'avoid' or IsYugi04 and 'yugi' or 'special',
		target=IsYugi04 and yugi04Target or specialTarget, stallSeconds=4}
	if candidate.kind=='avoid' then candidate.target=nil;candidate.location=J.GetTeamFountain();candidate.arrivalRadius=0;candidate.stallSeconds=2 end
	candidate.reason=candidate.kind
	if score <= 0 or not TaskSafe(candidate) then Tasks.Release(bot,'team_roam','candidate_invalid'); return 0 end
	-- 只对仍安全的同类收益竞争保留旧目标，紧急规避不走滞回。
	if active ~= nil and candidate.kind ~= 'avoid' and active.kind == candidate.kind
	and candidate.target ~= active.target and score < active.score+0.05 then candidate=active;score=active.score end
	return Tasks.Offer(bot,'team_roam',score,candidate)
end

function OnStart()
	Utils.NoteModeStart(bot,'team_roam')
	Tasks.Start(bot,'team_roam')
end
function OnEnd() Tasks.Release(bot,'team_roam','mode_end') end

function Think()
	Tasks.Commit(bot,'team_roam')
	local task=Tasks.Active(bot,'team_roam')
	if not Tasks.Check(bot,'team_roam',TaskSafe(task)) then return end
	local IsAvoidingAbilityZone=task.kind=='avoid'
	local IsAttackingSpecialUnit=task.kind=='special'
	local IsYugi04=task.kind=='yugi'
	local specialTarget,yugi04Target=task.target,task.target
    if not Timer.ShouldRunBotTask(bot, 'team_roam_think', 0.20, 0.03) then return end
    if J.CanNotUseAction(bot) then return end

	if IsAvoidingAbilityZone then
		local avoidLoc = J.GetStableRandomLocation(bot, 'team_roam_avoid_zone', Utils.GetOffsetLocationTowardsTargetLocation(bot:GetLocation(), J.GetTeamFountain(), 600), 160, 240, 0.8)
		J.ActionMoveToLocation(bot, 'team_roam_avoid_zone', avoidLoc, 0.4, 220)
		return
	end

	if J.Retreat.ShouldYield(bot, J.Retreat.HIGH) then return end

	if IsAttackingSpecialUnit and J.CanBeAttacked(specialTarget) and DotaTime() > nNextActionTime then
		J.ActionAttackUnit(bot, 'team_roam_special_attack', specialTarget, false, 0.7)
		nNextActionTime = DotaTime() + 0.7
	end

	if IsYugi04 and DotaTime() > nNextActionTime then
		J.ActionAttackUnit(bot, 'team_roam_yugi_attack', yugi04Target, false, 0.7)
		nNextActionTime = DotaTime() + 0.7
	end

	local nProjectiles = IsAvoidingAbilityProjectile and GetLinearProjectiles() or nil
	if IsAvoidingAbilityProjectile and nProjectiles ~= nil then
		for _, p in pairs(nProjectiles)
		do
			if p ~= nil
			and p.ability ~= nil
			and (p.ability:GetName() == "ability_thdots_ellen03"
			or p.ability:GetName() == "ability_thdots_ellen04"
		)
        	then
				if GetUnitToLocationDistance(bot, p.location) <= 1400 then
					local avoidLoc = J.GetStableRandomLocation(bot, 'team_roam_avoid_projectile', Utils.GetAvoidTargetLocation(bot:GetLocation(), p.location, 600), 160, 240, 0.7)
					J.ActionMoveToLocation(bot, 'team_roam_avoid_projectile', avoidLoc, 0.35, 220)
					return
				end
			end
		end
	end
end

GetDesire = Actions.GuardDesire(bot,BOT_MODE_TEAM_ROAM,GetDesire)

-- 仅观察本模式自然返回值，不参与模式选择。
GetDesire = CandidateDebug.Wrap('team_roam', GetDesire)
