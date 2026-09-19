require(GetScriptDirectory() .. '/thd2_item_usage')
local J = require(GetScriptDirectory() .. '/THDFuncLib/thd_func')
local Geometry = require(GetScriptDirectory() .. '/THDFuncLib/avoidance_geometry')
local TowerSafety = require(GetScriptDirectory() .. '/THDFuncLib/tower_safety')
local Consumables = require(GetScriptDirectory() .. '/THDFuncLib/consumable_inventory')
local CombatPower = require(GetScriptDirectory() .. '/THDFuncLib/combat_power')
local Backstep = require(GetScriptDirectory() .. '/THDFuncLib/tei_backstep')

local E_BUFF = 'modifier_ability_thdots_tei03'
local R_BUFF = 'modifier_ability_thdots_tei04'
local HORSE_BUFF = 'modifier_item_horse_king_open'
local RUN_ID = 'TEI-R3-20260919'

local function Special(ability, name, fallback)
	if ability == nil then return fallback end
	local value = ability:GetSpecialValueFloat(name)
	return value ~= nil and value > 0 and value or fallback
end

local function Ready(ability)
	return ability ~= nil and ability:GetLevel() > 0 and ability:IsFullyCastable()
end

local function ValidEnemy(bot, unit)
	return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
		and unit:GetTeam() ~= bot:GetTeam() and not unit:IsInvulnerable()
end

local function Enemies(bot)
	local result = {}
	for _, enemy in pairs(CachedGetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)) do
		if ValidEnemy(bot, enemy) and not J.IsSuspiciousIllusion(enemy) then
			table.insert(result, enemy)
		end
	end
	return result
end

local function NearestDistance(location, enemies)
	local distance = math.huge
	for _, enemy in ipairs(enemies) do
		distance = math.min(distance, Geometry.Distance(location, enemy:GetLocation()))
	end
	return distance
end

local function Issue(bot, ability, location)
	-- 每次仅下一条命令，短窗口覆盖尚未进入原生前摇的发单间隙。
	local margin = ability:GetName() == 'ability_thdots_tei02' and 0.35 or 0.15
	bot.THD_TeiActionUntil = DotaTime() + math.max(0, ability:GetCastPoint()) + margin
	if location ~= nil then bot:Action_UseAbilityOnLocation(ability, location)
	else bot:Action_UseAbility(ability) end
	print(string.format('[BOT][Tei] run=%s team=%d player=%d event=order ability=%s game_time=%.2f',
		RUN_ID, bot:GetTeam(), bot:GetPlayerID(), ability:GetName(), DotaTime()))
	return true
end

local function Item(bot, name)
	-- 背包、储藏处的装备不参与决策。
	if bot:IsMuted() then return nil end
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and item:GetName() == name and Ready(item) then return item end
	end
	return nil
end

local function SafeLocation(bot, location, enemies, retreat)
	local origin = bot:GetLocation()
	if location == nil or not IsLocationPassable(location) then return false end
	local observation = TowerSafety.Observe(bot, 'tei_movement')
	if observation.available ~= true then return false end
	if not Geometry.ValidateMovementSegment(origin, location, observation.towers, 96) then return false end
	-- 后跳和闪烁均采用保守可见地形路径，避免未知落点及穿入高地。
	if not Geometry.ValidateLocalTerrainSegment(origin, location, true) then return false end
	local before = NearestDistance(origin, enemies)
	local after = NearestDistance(location, enemies)
	if after < 400 then return false end
	return not retreat or after > before + 100
end

local function TryJump(bot, enemies, retreat, target)
	if bot:IsRooted() then return false end
	local item = Item(bot, 'item_nb9ball') or Item(bot, 'item_wanmeitiaoyuezhuangzhi')
	if item == nil then return false end
	-- 牛逼跳跃的服务端 GetCastRange 可返回99999，必须读取实际位移特殊值。
	local range = Special(item, 'AbilityCastRange', 499)
	local origin = bot:GetLocation()
	local destination
	if retreat then
		local ancient = GetAncient(bot:GetTeam())
		if ancient == nil then return false end
		destination = ancient:GetLocation()
	else
		if not ValidEnemy(bot, target) then return false end
		local distance = GetUnitToUnitDistance(bot, target)
		if distance <= bot:GetAttackRange() + 200 or distance > range + bot:GetAttackRange() then return false end
		destination = origin + (target:GetLocation() - origin):Normalized() * (distance - 500)
	end
	local delta = destination - origin
	if delta:Length2D() < 200 then return false end
	destination = origin + delta:Normalized() * math.min(range - 30, delta:Length2D())
	if not SafeLocation(bot, destination, enemies, retreat) then return false end
	return Issue(bot, item, destination)
end

local function SafeCombat(bot, enemies, forBuff)
	if J.GetHP(bot) < 0.4 or bot:WasRecentlyDamagedByTower(2.0) then return false end
	local nearby = 0
	local incoming = 0
	for _, enemy in ipairs(enemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		if distance <= 1000 then
			nearby = nearby + 1
			-- 原地开增益不等同于跳进人群；远处未攻击自己的单位仅计人数，不虚算满两秒普攻。
			local threatening = not forBuff or distance <= enemy:GetAttackRange() + 150
				or enemy:GetAttackTarget() == bot or bot:WasRecentlyDamagedByHero(enemy, 2.0)
			if threatening then
				local damage = CombatPower.EstimateAttackDamage(enemy, bot, 2.0, 1)
				if damage == nil then return false end
				incoming = incoming + damage
			end
		end
	end
	local defense = CombatPower.GetDefenseSnapshot(bot)
	if defense == nil or incoming >= defense.health * 0.8 then return false end
	local allies = CachedGetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE)
	local allyCount = 1
	for _, ally in pairs(allies) do
		if ally ~= bot and ally:IsAlive() and not J.IsSuspiciousIllusion(ally) then allyCount = allyCount + 1 end
	end
	if nearby > allyCount + 1 then return false end
	local towerDanger = TowerSafety.Scan(bot)
	if towerDanger.unseenIncoming or towerDanger.incomingCount > 0 then return false end
	local observation = TowerSafety.Observe(bot, 'tei_combat')
	return observation.available == true
		and Geometry.ValidateMovementSegment(bot:GetLocation(), bot:GetLocation(), observation.towers, 96)
end

local function GuaranteedMooncake(bot)
	if bot:HasModifier('modifier_item_wanbaochui') and J.GetHP(bot) <= 0.30 then return false end
	if bot:HasModifier(R_BUFF) then return true end
	-- Bot侧修饰器接口使用索引，不复用游戏侧 name/caster 参数签名。
	for index = 0, bot:NumModifiers() - 1 do
		if bot:GetModifierName(index) == 'modifier_ability_thdots_tei01_count' then
			return bot:GetModifierStackCount(index) >= 2
		end
	end
	return false
end

function AbilityUsageThink()
	local bot = GetBot()
	-- 转身和后跳由高优先级规避模式推进，本入口不能被自己的保护锁卡住后另发动作。
	if Backstep.IsActive(bot) then return end
	if bot == nil or not bot:IsAlive() or bot:IsIllusion() or bot:IsHexed() or J.CanNotUseAction(bot) then return end
	if Consumables.IsCastConfirmationPending(bot) then return end
	-- 目标与塔危险评估有界限频，动作保护本身仍在每次入口检查。
	local now = DotaTime()
	if now - (bot.THD_TeiLastThink or -90) < 0.10 then return end
	bot.THD_TeiLastThink = now
	if not bot.THD_TeiLoaded then
		bot.THD_TeiLoaded = true
		print(string.format('[BOT][Tei] run=%s team=%d player=%d event=loaded profile=damage', RUN_ID, bot:GetTeam(), bot:GetPlayerID()))
	end
	ObserveAbilityUsageTask(bot, 'tei_ability_usage', 0.10)
	local q = bot:GetAbilityByName('ability_thdots_tei01')
	local w = bot:GetAbilityByName('ability_thdots_tei02')
	local e = bot:GetAbilityByName('ability_thdots_tei03')
	local r = bot:GetAbilityByName('ability_thdots_tei04')
	local enemies = Enemies(bot)
	local nearby = NearestDistance(bot:GetLocation(), enemies)
	local pressure = #enemies > 0 and bot:WasRecentlyDamagedByAnyHero(2.5)
	local retreat = J.IsRetreating(bot) or (pressure and J.GetHP(bot) < 0.4)
	local canCast = not bot:IsSilenced()
	local reserve = w ~= nil and w:GetLevel() > 0 and w:GetManaCost() or 50
	local target = J.GetProperTarget(bot)
	local committed = not retreat and (J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200))
		and ValidEnemy(bot, target) and target:IsHero() and not J.IsSuspiciousIllusion(target)
		and SafeCombat(bot, enemies)

	if retreat and #enemies > 0 then
		if Backstep.Start(bot, w, 'escape', nil) or TryJump(bot, enemies, true) then return end
	end
	local dragon = Item(bot, 'item_dragon_star')
	if dragon ~= nil and not bot:HasModifier('modifier_item_dragon_star_buff')
	and nearby <= 1000 and (retreat or committed or (pressure and J.GetHP(bot) < 0.75)) then
		Issue(bot, dragon); return
	end
	if retreat and nearby <= 1000 and canCast then
		if Ready(r) and not bot:HasModifier(R_BUFF) then Issue(bot, r); return end
		for _, enemy in ipairs(enemies) do
			-- Bot接口没有游戏侧 IsRangedAttacker，以可见攻击距离保守判断远程压力。
			if enemy:GetAttackRange() > 310 and GetUnitToUnitDistance(bot, enemy) < 800
			and Ready(e) and not bot:HasModifier(E_BUFF) then Issue(bot, e); return end
		end
	end
	-- 被贴脸时侧后跳拉开，原地替身用于减速追兵；保留落地后的普攻接触范围。
	if not retreat and pressure and nearby <= 450 and not bot:IsDisarmed()
	and SafeCombat(bot, enemies, true) and Backstep.Start(bot, w, 'kite', target) then return end

	local horse = Item(bot, 'item_horse_king')
	if horse ~= nil then
		local active = bot:HasModifier(HORSE_BUFF)
		local wanted = (committed or (retreat and #enemies > 0)) and bot:GetMana() > reserve + 100
		if wanted ~= active then Issue(bot, horse); return end
	end
	if committed then
		local followupMana = (Ready(e) and e:GetManaCost() or 0) + (Ready(r) and r:GetManaCost() or 0)
		-- 追击需要先背对目标；转身任务验证目标、人数和落点，失败才交给跳跃装置。
		if Backstep.Start(bot, w, 'chase', target, followupMana) or TryJump(bot, enemies, false, target) then return end
	end
	local attackTarget = bot:GetAttackTarget()
	local eRadius = Special(e, 'radius', 800)
	local rangeTalent = bot:GetAbilityByName('special_bonus_unique_tei_5')
	if rangeTalent ~= nil and rangeTalent:GetLevel() > 0 then eRadius = eRadius + Special(rangeTalent, 'value', 200) end
	-- 可以用当前可攻击的小兵作起点覆盖远处英雄，但不主动换目标或追入危险区。
	local anchorAttack = ValidEnemy(bot, attackTarget) and not attackTarget:IsAttackImmune()
		and GetUnitToUnitDistance(bot, attackTarget) <= bot:GetAttackRange() + 50
	local attackingHero = committed and not bot:IsDisarmed() and not target:IsAttackImmune()
		and (GetUnitToUnitDistance(bot, target) <= bot:GetAttackRange() + 75
			or (anchorAttack and GetUnitToUnitDistance(bot, target) <= eRadius))
	-- 增益可在接敌时提前开启，也覆盖对线普攻/受压；不借此放宽进攻闪烁。
	local attackingEnemyHero = anchorAttack and attackTarget:IsHero() and not J.IsSuspiciousIllusion(attackTarget)
	local buffContext = J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1200) or pressure or attackingEnemyHero
	local buffEnemyInRange = false
	local buffEnemyDistance = math.huge
	local buffRange = math.min(eRadius, bot:GetAttackRange() + 250)
	for _, enemy in ipairs(enemies) do
		local distance = GetUnitToUnitDistance(bot, enemy)
		if not enemy:IsAttackImmune()
		and ((buffContext and distance <= buffRange) or (anchorAttack and distance <= eRadius)) then
			buffEnemyInRange = true
			buffEnemyDistance = math.min(buffEnemyDistance, distance)
		end
	end
	local buffCombat = not retreat and canCast and not bot:IsDisarmed()
		and buffEnemyInRange and SafeCombat(bot, enemies, true)
	if buffCombat then
		local eReserve = Ready(e) and not bot:HasModifier(E_BUFF) and e:GetManaCost() or 0
		-- 远处英雄只能借枪斗术触及时，须已有枪斗术或本轮有法力紧接开启，避免空开大招。
		local canDeliverR = buffEnemyDistance <= bot:GetAttackRange() + 250 or bot:HasModifier(E_BUFF) or Ready(e)
		if canDeliverR and Ready(r) and not bot:HasModifier(R_BUFF)
		and bot:GetMana() >= r:GetManaCost() + reserve + eReserve then
			Issue(bot, r); return
		end
		-- 先把枪斗术攻速/多目标窗口开出来，月饼的随机正面效果放到后面。
		if Ready(e) and not bot:HasModifier(E_BUFF) and bot:GetMana() >= e:GetManaCost() + reserve then
			Issue(bot, e); return
		end
	end
	if attackingHero and canCast and Ready(q) and GuaranteedMooncake(bot) then
		local eReserve = Ready(e) and not bot:HasModifier(E_BUFF) and e:GetManaCost() or 0
		if bot:GetMana() >= q:GetManaCost() + reserve + eReserve then Issue(bot, q); return end
	end
	-- 安全刷兵只取枪斗术攻速，不虚构对小兵的分裂伤害。
	local farmTarget = bot:GetAttackTarget()
	if not retreat and not bot:IsDisarmed() and #enemies == 0 and ValidEnemy(bot, farmTarget) and not farmTarget:IsHero()
	and not farmTarget:IsBuilding() and GetUnitToUnitDistance(bot, farmTarget) <= bot:GetAttackRange() + 50 then
		if canCast and Ready(e) and not bot:HasModifier(E_BUFF)
		and bot:GetMana() >= e:GetManaCost() + reserve + 100 then Issue(bot, e); return end
		if canCast and Ready(q) and GuaranteedMooncake(bot)
		and bot:GetMana() >= q:GetManaCost() + reserve then Issue(bot, q); return end
	end
	local redHorse = Item(bot, 'item_horse_red')
	if redHorse ~= nil and #enemies == 0 and not retreat and J.GetHP(bot) < 0.75 then
		Issue(bot, redHorse); return
	end
	if ConsiderNeutralItems ~= nil then ConsiderNeutralItems() end
end
