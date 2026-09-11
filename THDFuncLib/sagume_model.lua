local U = require(GetScriptDirectory()..'/THDFuncLib/sagume_util')
local C = require(GetScriptDirectory()..'/THDFuncLib/sagume_config')
local Combat = require(GetScriptDirectory()..'/THDFuncLib/combat_power')
local M = {}

function M.ManaBudget(bot,horizon)
	local drain=U.Has(bot,'modifier_item_horse_king_open') and bot:GetMaxMana()*0.03*horizon or 0
	return math.max(0,bot:GetMana()-drain)
end

function M.Amplification(bot)
	local value = U.Safe(0,function() return bot:GetSpellAmp() end)
	return 1 + math.max(0,value > 3 and value/100 or value)
end
function M.Talent(bot,name)
	local a = U.Ability(bot,name)
	return U.Level(a) > 0 and U.Special(a,'value',0) or 0
end
function M.QRaw(bot)
	local q = U.Ability(bot,C.Q)
	return U.Level(q) > 0 and U.Special(q,'damage',80*U.Level(q)) + M.Talent(bot,'special_bonus_unique_sagume_6') or 0
end
function M.OrbRaw(bot)
	local e = U.Ability(bot,C.E)
	if U.Level(e) == 0 then return 0 end
	local intellect = U.Safe(0,function() return bot:GetAttributeValue(ATTRIBUTE_INTELLECT) end)
	return math.max(0,intellect)*(U.Special(e,'intellect_bonus',0.2+0.2*U.Level(e))+M.Talent(bot,'special_bonus_unique_sagume_4'))
end
function M.Damage(bot,target,raw,kind,skipAttackProcs)
	if not U.Valid(target) then return nil end
	if kind == DAMAGE_TYPE_MAGICAL and U.Safe(true,function() return target:IsMagicImmune() end) then return 0 end
	if U.Safe(true,function() return target:IsInvulnerable() end) then return 0 end
	local damage = Combat.EstimateIncomingDamage(target,raw*(kind == DAMAGE_TYPE_MAGICAL and M.Amplification(bot) or 1),kind)
	if damage and not skipAttackProcs and U.Item(bot,'item_ganggenier') then damage = damage*1.1 end
	return damage
end
function M.PerAttack(bot,target,orb,neverMiss,skipAttackProcs)
	if not U.Valid(target) or U.Safe(true,function() return target:IsAttackImmune() end) then return 0 end
	local physical = M.Damage(bot,target,bot:GetAttackDamage(),DAMAGE_TYPE_PHYSICAL,skipAttackProcs)
	local magical = M.Damage(bot,target,orb and M.OrbRaw(bot) or 0,DAMAGE_TYPE_MAGICAL,skipAttackProcs)
	if physical == nil or magical == nil then return nil end
	local hitChance=(neverMiss or U.Item(bot,'item_ganggenier')) and 1 or (1-U.Safe(1,function() return target:GetEvasion() end))
	return (physical+magical)*hitChance
end

function M.SplitTargets(bot,target,origin)
	if not U.Item(bot,'item_inaba_illusion_weapon') then return {},0 end
	-- 月兔也可能选中可见幻象，不能沿用主动技能的疑似幻象过滤后少算耗蓝。
	local candidates=U.Safe({},function() return bot:GetNearbyHeroes(1600,true,BOT_MODE_NONE) end)
	for _,creep in ipairs(U.Safe({},function() return bot:GetNearbyCreeps(1600,true) end)) do candidates[#candidates+1]=creep end
	local result,seen,eligible={}, {},0
	for _,unit in ipairs(candidates) do
		local key=tostring(unit)
		if unit~=target and not seen[key] and U.Valid(unit) and not unit:IsBuilding() and not unit:IsInvulnerable() and not unit:IsAttackImmune()
		and U.Distance(origin or bot:GetLocation(),unit:GetLocation())<=bot:GetAttackRange() then
			seen[key]=true
			if not unit:IsMagicImmune() then eligible=eligible+1 end
			-- 仅法球继承已确认；不顺带把冈格尼尔等攻击特效算到月兔副目标上。
			local plain,orb=M.PerAttack(bot,unit,false,true,true),M.PerAttack(bot,unit,true,true,true)
			if plain and orb then result[#result+1]={plain=plain,orb=orb,
				orbEligible=not unit:IsMagicImmune() and not unit:IsAttackImmune(),distance=U.Distance(origin or bot:GetLocation(),unit:GetLocation())} end
		end
	end
	-- 实际按 FIND_ANY_ORDER 选目标，不假定两发都命中高价值英雄；采用可见候选的保守值。
	table.sort(result,function(a,b) return a.orb<b.orb end)
	while #result>2 do result[#result]=nil end
	return result,math.min(2,eligible)
end

function M.OrbCycleCost(bot,target)
	local e=U.Ability(bot,C.E)
	if U.Level(e)==0 then return 0 end
	local _,extra=M.SplitTargets(bot,target)
	return U.Mana(e)*(1+extra)
end

local function AttackSnapshot(bot,target)
	if target==nil then return nil end
	local state,now=U.State(bot),U.Now()
	if state.attackModelAt~=now then state.attackModels={};state.attackModelAt=now end
	local key=tostring(target)
	if state.attackModels[key] then return state.attackModels[key] end
	if not U.Valid(target) then return nil end
	local distance = GetUnitToUnitDistance(bot,target)
	local period = U.Safe(nil,function() return bot:GetSecondsPerAttack() end)
	local point = U.Safe(nil,function() return bot:GetAttackPoint() end)
	local speed = U.Safe(nil,function() return bot:GetAttackProjectileSpeed() end)
	if not U.Finite(period) or period <= 0 or not U.Finite(point) or not U.Finite(speed) or speed <= 0 then return nil end
	local attackAge = U.Safe(nil,function() return GameTime()-bot:GetLastAttackTime() end)
	local untilAttack = U.Finite(attackAge) and math.max(point,period-math.max(0,attackAge)) or point
	local e=U.Ability(bot,C.E)
	local plain,orb=M.PerAttack(bot,target,false),M.PerAttack(bot,target,true)
	if plain==nil or orb==nil then return nil end
	local trident=U.Item(bot,'item_nuetrident')
	local cd=U.Cooldown(trident)
	local dot=M.Damage(bot,target,bot:GetMaxMana()*0.06,DAMAGE_TYPE_MAGICAL)
	if trident and (cd==nil or dot==nil) then return nil end
	-- 组合搜索仅复用当前时刻的数值快照，不在每个搜索分支反复调用原生单位API。
	local snapshot={inRange=distance<=bot:GetAttackRange()+35,period=period,point=point,
		untilAttack=untilAttack,travel=distance/speed,plain=plain,orb=orb,
		orbEnabled=U.Level(e)>0 and e:GetAutoCastState(),orbMana=U.Mana(e),
		trident=trident~=nil,tridentCD=cd,dotActive=U.Has(target,'modifier_item_nuetrident_damage_debuff'),
		dot=dot or 0,rTime=U.CastPoint(U.Ability(bot,C.R))}
	local extraOrbs
	snapshot.split,extraOrbs=M.SplitTargets(bot,target)
	snapshot.cycleOrbs=1+extraOrbs
	snapshot.hasSplit=U.Item(bot,'item_inaba_illusion_weapon')~=nil
	snapshot.speed=speed
	snapshot.attackRange=bot:GetAttackRange()
	snapshot.targetPosition=U.Copy(target:GetLocation())
	local hitChance=U.Item(bot,'item_ganggenier') and 1 or (1-U.Safe(1,function() return target:GetEvasion() end))
	snapshot.heal=U.Item(bot,'item_trinity') and not target:IsBuilding() and not target:IsAttackImmune() and target:GetMaxHealth()*0.033*hitChance or 0
	snapshot.healthMissing=bot:GetMaxHealth()-bot:GetHealth()
	snapshot.bounceUntil=U.Remaining(bot,C.BOUNCE)
	snapshot.bouncePlain,snapshot.bounceOrb=0,0
	if snapshot.bounceUntil>0 then
		local bounces=math.max(0,1+M.Talent(bot,'special_bonus_unique_sagume_5')-(U.Has(bot,C.SCEPTER) and 1 or 0))
		local candidates=U.Enemies(bot,1600)
		for _,creep in ipairs(U.Safe({},function() return bot:GetNearbyCreeps(1600,true) end)) do candidates[#candidates+1]=creep end
		local seen=0
		for _,other in ipairs(candidates) do
			if bounces>0 and other~=target and U.Valid(other) and GetUnitToUnitDistance(target,other)<=300 then
				seen=seen+1
				local physical=M.Damage(bot,other,bot:GetAttackDamage()*0.6,DAMAGE_TYPE_PHYSICAL)
				local magical=M.Damage(bot,other,M.OrbRaw(bot),DAMAGE_TYPE_MAGICAL)
				if physical and magical then
					-- 随机弹射按可见候选上界计算放弃普攻的代价，不把它当可靠击杀伤害。
					snapshot.bouncePlain=math.max(snapshot.bouncePlain,physical*bounces)
					snapshot.bounceOrb=math.max(snapshot.bounceOrb,(physical+magical)*bounces)
				end
				if seen>=16 then break end
			end
		end
		local hitChance=U.Item(bot,'item_ganggenier') and 1 or (1-U.Safe(1,function() return target:GetEvasion() end))
		snapshot.bouncePlain,snapshot.bounceOrb=snapshot.bouncePlain*hitChance,snapshot.bounceOrb*hitChance
	end
	state.attackModels[key]=snapshot
	return snapshot
end

-- 同一时间窗口内只统计能命中的攻击；使用 GameTime 与 GetLastAttackTime 的同一时基。
function M.Attacks(bot,target,horizon,blocked,mana,refreshed,position,primaryOnly)
	local s=AttackSnapshot(bot,target)
	if s==nil then return nil end
	local projected=position and U.Distance(position,s.targetPosition) or nil
	if projected and projected>s.attackRange+35 or not projected and not s.inRange then return 0 end
	local travel=projected and projected/s.speed or s.travel
	local first=math.max(s.untilAttack,(blocked or 0)+s.point)+travel
	local damage,hits=0,0
	local availableMana = math.max(0,mana or bot:GetMana())
	local t = first
	while t <= horizon and hits < 20 do
		local cycleCost=s.orbMana*(position and s.hasSplit and 3 or s.cycleOrbs)
		local orb = s.orbEnabled and availableMana >= cycleCost
		damage, hits = damage+(orb and s.orb or s.plain), hits+1
		if not primaryOnly and not position then
			if t<=s.bounceUntil then damage=damage+(orb and s.bounceOrb or s.bouncePlain) end
			for _,other in ipairs(s.split) do
				if t-travel+other.distance/s.speed<=horizon then damage=damage+(orb and other.orbEligible and other.orb or other.plain) end
			end
		end
		-- 法球继承已由用户确认；不足整轮蓝量时不猜攻击事件先后，只扣可能消耗而不虚报法球伤害。
		if s.orbEnabled then availableMana=math.max(0,availableMana-cycleCost) end
		t = t+s.period
	end
	-- 三叉戟是带内置冷却的被动物品；原 DoT 仍在时不把刷新计作第二份 DoT。
	local cd=s.tridentCD
	if hits > 0 and s.trident and cd ~= nil and not s.dotActive then
		if refreshed then
			cd=cd>s.rTime and s.rTime or s.rTime+7
		end
		local procAt = first
		if cd > procAt then procAt = first+math.ceil((cd-first)/s.period)*s.period end
		local ticks = math.max(0,math.min(5,math.floor(horizon-procAt)))
		damage = damage+s.dot*ticks
	end
	return damage, hits, math.min(s.healthMissing,hits*s.heal)
end

-- 三个方案共用候选和动作预算；刷新并不创造额外行动时间，也不重复计算已打出的伤害。
function M.Simulate(bot,target,actions,horizon,refresh)
	local r = U.Ability(bot,C.R)
	local initial = refresh and U.CastPoint(r) or 0
	local budget = M.ManaBudget(bot,horizon)-(refresh and U.Mana(r) or 0)
	if budget < 0 then return nil end
	local chosen, best = {}, nil
	local function visit(time,mana,damage,utility,steps,controlUntil,position)
		local attacks,_,healing=0,0,0
		if target then attacks,_,healing=M.Attacks(bot,target,horizon,time,mana,refresh,position) end
		if attacks == nil then return end
		local candidate = {damage=damage+attacks,utility=utility+(healing or 0),value=damage+attacks+utility+(healing or 0),
			steps={},mana=bot:GetMana()-mana,castTime=time}
		for _,step in ipairs(steps) do candidate.steps[#candidate.steps+1] = step end
		if best == nil or candidate.value > best.value then best = candidate end
		if #steps >= 3 then return end
		for i,a in ipairs(actions) do
			-- R 会封锁原本就绪的能力；W 返回标记的特殊重置由候选显式声明。
			local available = refresh and (a.cooldown > initial+0.1 or a.returnReset) or not refresh and not a.returnReset
			local readyAt = refresh and initial or a.cooldown
			local start = math.max(time,readyAt,a.wait or 0)
			if a.control then start=math.max(start,controlUntil-0.15) end
			local finish = start+a.cast
			if not chosen[i] and available and finish+(a.travel or 0) <= horizon
			and mana >= a.mana and not (a.offensive and mana-a.mana < 90) then
				chosen[i] = true
				steps[#steps+1] = a.id
				visit(finish,mana-a.mana,damage+(a.damage or 0),utility+(a.utility or 0),steps,
					a.control and finish+a.control or controlUntil,a.location or position)
				steps[#steps] = nil
				chosen[i] = nil
			end
		end
	end
	visit(initial,budget,0,0,{},0)
	return best
end

function M.CompareRefresh(bot,target,actions,penalty)
	local horizon = C.REFRESH_HORIZON
	local current = M.Simulate(bot,target,actions,horizon,false)
	local refreshed = M.Simulate(bot,target,actions,horizon,true)
	local attacks = target and M.Attacks(bot,target,horizon,0,M.ManaBudget(bot,horizon),false) or 0
	if not current or not refreshed or attacks == nil then
		U.Log(bot,'refresh_rejected',{reason='unknown_attack_or_resource_snapshot'},2)
		return nil
	end
	if #refreshed.steps == 0 then return nil end
	local baseline = math.max(attacks,current.value)
	refreshed.value = refreshed.value-(penalty or 0)
	local gain = refreshed.value-baseline
	U.Log(bot,'refresh_model',{reason='self',attacks=math.floor(attacks),current=math.floor(current.value),
		refresh=math.floor(refreshed.value),gain=math.floor(gain),cast=refreshed.castTime,
		steps=table.concat(refreshed.steps,','),mana=refreshed.mana},2)
	if refreshed.value < baseline*C.OUTPUT_MARGIN or gain < C.MIN_REFRESH_GAIN then return nil end
	refreshed.gain = gain
	return refreshed
end

return M
