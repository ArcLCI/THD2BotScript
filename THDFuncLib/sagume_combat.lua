local U = require(GetScriptDirectory()..'/THDFuncLib/sagume_util')
local C = require(GetScriptDirectory()..'/THDFuncLib/sagume_config')
local M = require(GetScriptDirectory()..'/THDFuncLib/sagume_model')
local Pool = require(GetScriptDirectory()..'/THDFuncLib/sagume_ultimate_pool')
local Tower = require(GetScriptDirectory()..'/THDFuncLib/tower_safety')
local J = require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local S = {}

local function Towards(origin,goal,distance)
	local length=U.Distance(origin,goal)
	if length<1 then return U.Copy(origin) end
	local f=math.min(1,distance/length)
	return Vector(origin.x+(goal.x-origin.x)*f,origin.y+(goal.y-origin.y)*f,origin.z)
end
local function Health(unit) return unit:GetHealth()/math.max(1,unit:GetMaxHealth()) end
local function Range(bot,target) return U.Valid(target) and GetUnitToUnitDistance(bot,target) or math.huge end
local function DisableRemaining(target)
	local result=0
	for _,name in ipairs({'modifier_stunsystem_pause','modifier_item_yukkuri_stick_debuff',
		'modifier_item_morenjingjuan_antiblink','modifier_item_tentacle_root'}) do
		result=math.max(result,U.Remaining(target,name))
	end
	return result
end

local function WorthQ(bot,target,action)
	if not U.Valid(target) then return false end
	-- 不能只看0.4秒内是否有弹道落地；较长共同窗口才能计入被推迟的普攻。
	local horizon=C.REFRESH_HORIZON
	local attacks=M.Attacks(bot,target,horizon,0,bot:GetMana())
	local after=M.Attacks(bot,target,horizon,action.cast,bot:GetMana()-action.mana)
	if attacks==nil or after==nil then return false end
	local beforeCast=M.Attacks(bot,target,action.cast,0,bot:GetMana(),false,nil,true)
	local health=target:GetHealth()+U.Safe(0,function() return target:GetHealthRegen() end)*action.cast
	if action.damage>=health*1.05 and beforeCast and beforeCast<health then return true end
	return action.damage+after>=attacks*C.OUTPUT_MARGIN
end

function S.Context(bot,escape)
	local ctx={bot=bot,enemies=U.Enemies(bot,1600),allies=U.Allies(bot,1600),escape=escape}
	ctx.target=U.Target(bot,ctx.enemies)
	ctx.retreat=escape~=nil or U.Safe(false,function() return IsSeriouslyRetreating(bot,C.W) end)
	ctx.danger=ctx.retreat or (Health(bot)<0.45 and bot:WasRecentlyDamagedByAnyHero(2))
	ctx.magicThreat=false
	for _,enemy in ipairs(ctx.enemies) do
		if Range(bot,enemy)<1000 and U.Safe(false,function() return enemy:IsCastingAbility() or enemy:IsChanneling() end) then ctx.magicThreat=true end
	end
	ctx.towers=escape and escape.zones or Tower.Observe(bot,'sagume').towers
	ctx.goal=escape and escape.anchor or U.Safe(nil,function() return GetAncient(bot:GetTeam()):GetLocation() end)
	return ctx
end

local function PointRisk(bot,p,ctx)
	if p==nil or not U.Safe(false,function() return IsLocationPassable(p) and IsLocationVisible(p) end) then return math.huge end
	for _,zone in ipairs(ctx.towers or {}) do
		if U.Distance(p,zone.center)<(zone.effectiveRadius or zone.radius or 900)+80 then return math.huge end
	end
	-- 正在修改的技能规避模块只消费其已有数值快照，不重新枚举单位或改动租约。
	local skill=bot.THD_SkillAvoidance
	for _,zone in ipairs(skill and skill.zones or {}) do
		if zone.center and (not zone.expiresAt or zone.expiresAt>U.Now())
		and U.Distance(p,zone.center)<(zone.radius or 0)+100 then return math.huge end
	end
	local risk=0
	for _,enemy in ipairs(ctx.enemies) do
		local distance=U.Distance(p,enemy:GetLocation())
		local reach=enemy:GetAttackRange()+150
		if distance<reach then risk=risk+1+(reach-distance)/math.max(1,reach) end
		if distance<300 then risk=risk+2 end
	end
	return risk
end

local function CanBlink(bot,w)
	local item=w and U.Safe(false,function() return w:IsItem() end)
	return U.Level(w)>0 and (item and not bot:IsMuted() or not item and not bot:IsSilenced()) and not bot:IsRooted()
		and not U.Safe(true,function() return IsYugi04NoDisplacementActive(bot) end)
end
local function JumpItem(bot)
	return U.Item(bot,'item_nb9ball') or U.Item(bot,'item_wanmeitiaoyuezhuangzhi')
end
local function BlinkRange(a)
	if a:GetName()=='item_nb9ball' then return 999 end
	if a:GetName()=='item_wanmeitiaoyuezhuangzhi' then return 499 end
	return U.Special(a,'cast_range',400+100*U.Level(a))
end
function S.EscapePoint(bot,ctx,ability)
	local w=ability or U.Ability(bot,C.W)
	if not CanBlink(bot,w) or not ctx.goal then return nil end
	local origin=bot:GetLocation()
	local range=BlinkRange(w)
	local base=math.atan2(ctx.goal.y-origin.y,ctx.goal.x-origin.x)
	local best,bestScore=nil,math.huge
	for _,offset in ipairs({0,0.4,-0.4,0.8,-0.8,1.2,-1.2}) do
		for _,scale in ipairs({1,0.75,0.5}) do
			local p=Vector(origin.x+math.cos(base+offset)*range*scale,origin.y+math.sin(base+offset)*range*scale,origin.z)
			local risk=PointRisk(bot,p,ctx)
			local progress=U.Distance(origin,ctx.goal)-U.Distance(p,ctx.goal)
			local score=risk*1000-progress
			if progress>150 and risk<=1 and score<bestScore then best,bestScore=p,score end
		end
	end
	return best
end

local function ReturnIntent(bot,ctx)
	local state,w=U.State(bot),U.Ability(bot,C.W)
	if not U.Has(bot,C.RETURN) or not state.returnOrigin or not U.Castable(w) or not CanBlink(bot,w) then return nil end
	local current,origin=bot:GetLocation(),state.returnOrigin
	local risk=PointRisk(bot,origin,ctx)
	local currentRisk=PointRisk(bot,current,ctx)
	local retreatGain=ctx.goal and U.Distance(current,ctx.goal)-U.Distance(origin,ctx.goal) or 0
	if U.Distance(current,origin)>150 and risk<math.huge
	and (ctx.danger and (risk<currentRisk or retreatGain>180)
		or not ctx.danger and ctx.target==nil and risk<currentRisk) then
		return {ability=w,back=true,reason='safe_return'}
	end
	return nil
end

local function OffensePoint(bot,ctx,ability)
	local w=ability or U.Ability(bot,C.W)
	if not CanBlink(bot,w) or ctx.danger or not ctx.target then return nil end
	local target=ctx.target
	local origin,targetLoc=bot:GetLocation(),target:GetLocation()
	local distance=U.Distance(origin,targetLoc)
	local range=BlinkRange(w)
	local desired=math.max(300,bot:GetAttackRange()-60)
	local point=Towards(targetLoc,origin,desired)
	if U.Distance(origin,point)>range then point=Towards(origin,point,range) end
	if U.Distance(origin,point)<160 or PointRisk(bot,point,ctx)>1 then return nil end
	if distance<=bot:GetAttackRange() and (ability~=nil or not U.Has(bot,C.SCEPTER)) then return nil end
	return point
end

local function Add(actions,bot,a,id,damage,utility,target,location,wait,reason)
	local cd=U.Cooldown(a)
	if a==nil or cd==nil or U.Level(a)==0 then return end
	actions[#actions+1]={id=id,ability=a,cooldown=cd,mana=U.Mana(a),cast=math.max(0.05,U.CastPoint(a)),
		damage=damage or 0,utility=utility or 0,target=target,location=location,wait=wait or 0,
		reason=reason or id,offensive=target and target:GetTeam()~=bot:GetTeam() or location~=nil}
end

function S.Actions(bot,ctx)
	local actions={}
	local target=ctx.target
	local q,w=U.Ability(bot,C.Q),U.Ability(bot,C.W)
	if target and U.Level(q)>0 and U.EntityAllowed(bot,target,q) then
		local damage=M.Damage(bot,target,M.QRaw(bot),DAMAGE_TYPE_MAGICAL)
		if damage then
			local interrupt=target:IsChanneling()
			local silence=U.Special(q,'stuntime',1.2)+M.Talent(bot,'special_bonus_unique_sagume_3')
			local utility=not target:IsSilenced() and (interrupt and 250 or ctx.retreat and 120 or 30*silence) or 0
			Add(actions,bot,q,C.Q,damage,utility,target,nil,0,interrupt and 'interrupt' or 'q_value')
		end
	end
	local p=OffensePoint(bot,ctx)
	if p and target then
		local damage,hits,orbAttacks=0,0,0
		if U.Has(bot,C.SCEPTER) then
			local radius=U.Special(w,'radius',600)
			for _,enemy in ipairs(ctx.enemies) do
				local e=U.Ability(bot,C.E)
				local hit=M.PerAttack(bot,enemy,U.Level(e)>0 and e:GetAutoCastState())
				if hit then
					local count=(Range(bot,enemy)<=radius and 1 or 0)+(U.Distance(p,enemy:GetLocation())<=radius and 1 or 0)
					damage,hits=damage+hit*count,hits+count
					orbAttacks=orbAttacks+count
				end
			end
			for _,creep in ipairs(U.Safe({},function() return bot:GetNearbyCreeps(1600,true) end)) do
				if U.Valid(creep) then
					orbAttacks=orbAttacks+(Range(bot,creep)<=radius and 1 or 0)+(U.Distance(p,creep:GetLocation())<=radius and 1 or 0)
				end
			end
		end
		if hits>=2 or Range(bot,target)>bot:GetAttackRange()+100 then
			Add(actions,bot,w,C.W,damage,Range(bot,target)>bot:GetAttackRange()+100 and 100 or 0,nil,p,0,'attack_blink')
			if actions[#actions] and actions[#actions].id==C.W then
				local action,e=actions[#actions],U.Ability(bot,C.E)
				action.returnReset=U.Has(bot,C.RETURN)
				if U.Level(e)>0 and e:GetAutoCastState() then
					-- W即时攻击是否进一步触发月兔尚未单独确认，耗蓝按最多三次预留，不额外计伤害。
					action.mana=action.mana+orbAttacks*U.Mana(e)*(U.Item(bot,'item_inaba_illusion_weapon') and 3 or 1)
				end
			end
		end
	end
	for _,name in ipairs({'item_tentacle','item_morenjingjuan','item_yukkuri_stick',
		'item_rocket_5','item_rocket_4','item_rocket_3','item_rocket_2','item_rocket'}) do
		local item=U.Item(bot,name)
		if item and target and U.EntityAllowed(bot,target,item) then
			local damage,utility,wait=0,0,DisableRemaining(target)
			if string.find(name,'item_rocket',1,true) then
				damage=M.Damage(bot,target,U.Special(item,'rocket_damage',300),DAMAGE_TYPE_MAGICAL) or 0
				utility=target:IsChanneling() and 220 or 0
			elseif name=='item_morenjingjuan' then
				local delta=bot:GetMaxMana()-target:GetMaxMana()
				if delta>0 or ctx.retreat then
					local attack=M.Attacks(bot,target,2,0,bot:GetMana()) or 0
					utility=(ctx.retreat and 180 or 60)+math.min(250,attack*math.max(0,delta)*0.003/2)
				else wait=math.huge end
			elseif name=='item_yukkuri_stick' then utility=target:IsChanneling() and 280 or ctx.retreat and 220 or 140
			else utility=ctx.retreat and 170 or 90 end
			Add(actions,bot,item,name,damage,utility,target,nil,math.max(0,wait-0.15),'control_item')
			local added=actions[#actions]
			if added and added.id==name and not string.find(name,'item_rocket',1,true) then
				added.control=name=='item_morenjingjuan' and 4 or name=='item_yukkuri_stick' and 2.5 or 2
			end
		end
	end
	local jump=JumpItem(bot)
	local jumpPoint=jump and OffensePoint(bot,ctx,jump)
	if jumpPoint then
		Add(actions,bot,jump,jump:GetName(),0,50,nil,jumpPoint,0,'item_reposition')
		local action=actions[#actions]
		if action and action.id==jump:GetName() then action.jump=true end
	end
	local trinity=U.Item(bot,'item_trinity')
	if trinity and (ctx.danger or Health(bot)<0.7 and bot:WasRecentlyDamagedByAnyHero(2)) then
		Add(actions,bot,trinity,'item_trinity',0,math.min(666,bot:GetMaxHealth()*0.35),nil,nil,
			U.Remaining(bot,'modifier_item_trinity_active_shield'),'trinity_protection')
	end
	local mirror=U.Item(bot,'item_green_dam')
	if mirror and ctx.magicThreat then
		local recipient=bot
		for _,ally in ipairs(ctx.allies) do
			if U.EntityAllowed(bot,ally,mirror) and Health(ally)<Health(recipient) then recipient=ally end
		end
		if Health(recipient)<0.65 and U.EntityAllowed(bot,recipient,mirror) then
			Add(actions,bot,mirror,'item_green_dam',0,math.min(350,recipient:GetMaxHealth()*0.2),recipient,nil,
				U.Remaining(recipient,'modifier_item_green_dam_barrier'),'magic_protection')
		end
	end
	local heal=U.Item(bot,'item_hakurei_ticket')
	if heal then
		local value=0
		for _,ally in ipairs(ctx.allies) do
			if Range(bot,ally)<=750 and not U.Has(ally,'modifier_item_hakurei_ticket_feast_buff') then
				value=value+math.min(ally:GetMaxHealth()-ally:GetHealth(),250+ally:GetMaxHealth()*0.1)
			end
		end
		if value>=250 then Add(actions,bot,heal,'item_hakurei_ticket',0,value,nil,nil,0,'effective_healing') end
	end
	return actions
end

local function RefreshPenalty(bot,ctx)
	local penalty=0
	local w=U.Ability(bot,C.W)
	if U.Cooldown(w)==0 and not U.Has(bot,C.RETURN) then
		if ctx.danger then return nil,'ready_escape' end
		penalty=penalty+100
	end
	-- 未建模装备不能产生虚构刷新收益；危险时不封锁任何未建模就绪主动装备。
	for slot=0,20 do
		local item=U.Safe(nil,function() return bot:GetItemInSlot(slot) end)
		if item then
			local cd=U.Cooldown(item)
			if cd==nil then return nil,'unknown_item_cooldown' end
			if cd==0 and not U.Safe(true,function() return item:IsPassive() end) then
				if ctx.danger and slot<=5 then return nil,'ready_defensive_item' end
				if slot<=5 then penalty=penalty+25 end
			end
		end
	end
	return penalty
end

local function SelfRefresh(bot,ctx,actions)
	local r=U.Ability(bot,C.R)
	if not U.Castable(r) or bot:IsSilenced() or U.Now()-U.State(bot).lastR<C.REFRESH_REUSE_DELAY then return nil end
	if ctx.target==nil and not ctx.danger then return nil end
	if U.Has(bot,C.RETURN) and S.EscapePoint(bot,ctx)==nil then return nil end
	local penalty,reason=RefreshPenalty(bot,ctx)
	if penalty==nil then U.Log(bot,'refresh_rejected',{reason=reason},2);return nil end
	local result=M.CompareRefresh(bot,ctx.target,actions,penalty)
	if not result then return nil end
	if U.Has(bot,C.RETURN) then
		local hasBlink=false
		for _,id in ipairs(result.steps) do if id==C.W then hasBlink=true end end
		if not hasBlink then result.steps[#result.steps+1]='sagume_disengage' end
	end
	local id=ctx.target and ctx.target:GetPlayerID() or nil
	return {ability=r,target=bot,reason='self_composite',followup=result.steps,targetId=id,
		priority=60+(U.Profile(bot)=='damage' and 10 or 0),gain=result.gain}
end

local function ManageOrb(bot,ctx)
	local e=U.Ability(bot,C.E)
	if U.Level(e)==0 or bot:IsSilenced() then return false end
	local state=U.State(bot)
	local reserve=190
	local r=U.Ability(bot,C.R)
	if U.Castable(r) and (#ctx.enemies>0 or state.combo) then reserve=reserve+U.Mana(r) end
	local on=e:GetAutoCastState()
	local target=ctx.target or U.Safe(nil,function() return bot:GetAttackTarget() end)
	local worthwhile=U.Valid(target) and target:GetTeam()~=bot:GetTeam() and not target:IsBuilding()
		and not target:IsMagicImmune() and not target:IsAttackImmune()
	if worthwhile and not target:IsHero() then
		worthwhile=not ctx.danger and (bot:GetActiveMode()==BOT_MODE_FARM or bot:GetActiveMode()==BOT_MODE_PUSH_TOWER_TOP
			or bot:GetActiveMode()==BOT_MODE_PUSH_TOWER_MID or bot:GetActiveMode()==BOT_MODE_PUSH_TOWER_BOT
			or target:GetHealth()<(M.PerAttack(bot,target,true) or 0))
	end
	local cycleCost=M.OrbCycleCost(bot,target)
	local desired=worthwhile and bot:GetMana()>=reserve+cycleCost*(on and 1 or 3)
	if desired~=on then
		e:ToggleAutoCast()
		bot.THD_SagumeActionUntil=U.Now()+0.05
		U.Log(bot,'orb',{reason=desired and 'on' or 'off',reserve=reserve},1)
		return true
	end
	return false
end

local function TryMaintenance(bot,ctx)
	local red=U.Item(bot,'item_horse_red')
	if U.Castable(red) and not U.Has(bot,'modifier_item_horse_red_active')
	and bot:GetMaxHealth()-bot:GetHealth()>=math.max(100,bot:GetMaxHealth()*0.12)
	and not bot:WasRecentlyDamagedByAnyHero(2) then
		-- 英雄伤害会取消扫把回血；拉开攻击距离后再开，避免在挨打时浪费冷却。
		local safe=true
		for _,enemy in ipairs(ctx.enemies) do
			if Range(bot,enemy)<=enemy:GetAttackRange()+100 then safe=false;break end
		end
		if safe then return U.Issue(bot,{ability=red,reason='health_sustain'}) end
	end
	local horse=U.Item(bot,'item_horse_king')
	if U.Castable(horse) then
		local on=horse:GetToggleState()
		local reserve=190+(U.Castable(U.Ability(bot,C.R)) and U.Mana(U.Ability(bot,C.R)) or 0)
		local wanted=(ctx.target~=nil or ctx.retreat) and bot:GetMana()>reserve+bot:GetMaxMana()*0.09+M.OrbCycleCost(bot,ctx.target)*2
		if wanted~=on then return U.Issue(bot,{ability=horse,toggle=true,reason=wanted and 'horse_on' or 'horse_off'}) end
	end
	return false
end

function S.ObserveOnly(bot)
	local state=U.State(bot)
	if U.Now()>=(state.nextObservation or 0) then Pool.Observe(bot,{enemies=U.Enemies(bot,1600)}) end
end

function S.TryEscape(bot,escape)
	if bot:GetUnitName()~='npc_dota_hero_queenofpain' then return false end
	if U.Update(bot) then return true end
	if U.Now() < (bot.THD_SagumeActionUntil or -90) then return true end
	if U.Busy(bot) or bot:NumQueuedActions()>0 then return false end
	local ctx=S.Context(bot,escape)
	if not ctx.danger then return false end
	local back=ReturnIntent(bot,ctx)
	if back and U.Issue(bot,back) then return true end
	local jump=JumpItem(bot)
	local jumpPoint=jump and U.Castable(jump) and S.EscapePoint(bot,ctx,jump)
	-- 有独立装备位移可用时先保留R；沉默下仍可使用未被禁用的位移装备。
	if jumpPoint and U.Issue(bot,{ability=jump,location=jumpPoint,jump=true,reason='item_escape'}) then return true end
	local w=U.Ability(bot,C.W)
	local point=S.EscapePoint(bot,ctx)
	if not point or not CanBlink(bot,w) then return false end
	if not U.Has(bot,C.RETURN) and U.Castable(w) then
		return U.Issue(bot,{ability=w,location=point,reason='escape_blink'})
	end
	local r=U.Ability(bot,C.R)
	-- 逃生例外仍比较实际落点收益，不在 W 就绪时用 R 把它封进冷却。
	local currentRisk=PointRisk(bot,bot:GetLocation(),ctx)
	if currentRisk<1 and not ctx.magicThreat and not (Health(bot)<0.35 and bot:WasRecentlyDamagedByAnyHero(1.5)) then return false end
	local refreshable=U.Has(bot,C.RETURN) or (U.Cooldown(w) or 0)>U.CastPoint(r)+0.2
	if refreshable and U.Castable(r) and U.Now()-U.State(bot).lastR>=C.REFRESH_REUSE_DELAY
	and bot:GetMana()>=U.Mana(r)+90 and U.Issue(bot,{ability=r,target=bot,reason='escape_reset',followup={C.W}}) then return true end
	return false
end

local function FollowCombo(bot,ctx,actions)
	local state=U.State(bot)
	local combo=state.combo
	if not combo then return false end
	if U.Now()>combo.expiresAt or (combo.targetId and (not ctx.target or ctx.target:GetPlayerID()~=combo.targetId)) then
		state.combo=nil
		return false
	end
	if ctx.danger then state.combo=nil;return false end
	local id=combo.steps[combo.cursor]
	if not id then state.combo=nil;return false end
	if id=='sagume_disengage' then
		local point=S.EscapePoint(bot,ctx)
		local w=U.Ability(bot,C.W)
		if point and not U.Has(bot,C.RETURN) and U.Issue(bot,{ability=w,location=point,reason='combo_disengage'}) then
			combo.cursor=combo.cursor+1
			return true
		end
		state.combo=nil
		return false
	end
	for _,a in ipairs(actions) do
		if a.id==id and a.cooldown<=0 and a.wait<=0.1 and not (id==C.W and U.Has(bot,C.RETURN))
		and bot:GetMana()>=a.mana+(a.offensive and 90 or 0) then
			if id==C.Q and a.utility<100 then
				if not WorthQ(bot,ctx.target,a) then combo.cursor=combo.cursor+1;return false end
			end
			if U.Issue(bot,a) then combo.cursor=combo.cursor+1;return true end
		end
	end
	return false
end

function S.Think(bot)
	-- 自己施法期间仍可被动观测可见敌人，避免每次Q/R都丢失连续观测历史。
	if U.Valid(bot) then S.ObserveOnly(bot) end
	if U.Update(bot) then return end
	if U.Now() < (bot.THD_SagumeActionUntil or -90) then return end
	if not U.Valid(bot) or bot:IsIllusion() or U.Busy(bot) or bot:NumQueuedActions()>0 then return end
	if J.IsTowerEscapeActive(bot) then return end
	local state,now=U.State(bot),U.Now()
	local interval=state.combo and C.ACTIVE_INTERVAL or C.THINK_INTERVAL
	if now<(state.nextThink or 0) then return end
	state.nextThink=now+interval
	ObserveAbilityUsageTask(bot,'sagume_combat',interval)
	local ctx=S.Context(bot)
	if state.combo and state.combo.targetId then
		ctx.target=nil
		for _,enemy in ipairs(ctx.enemies) do if enemy:GetPlayerID()==state.combo.targetId then ctx.target=enemy end end
	end
	if ctx.danger and S.TryEscape(bot,nil) then return end
	local back=ReturnIntent(bot,ctx)
	if back and U.Issue(bot,back) then return end
	-- 中断目标优先于普通攻击目标，但仍必须位于真实施法距离内。
	local q=U.Ability(bot,C.Q)
	for _,enemy in ipairs(ctx.enemies) do
		if U.Castable(q) and not bot:IsSilenced() and enemy:IsChanneling() and U.EntityAllowed(bot,enemy,q) then
			if U.Issue(bot,{ability=q,target=enemy,reason='interrupt'}) then return end
		end
	end
	if not ctx.target then
		for _,enemy in ipairs(ctx.enemies) do
			if ctx.retreat and bot:WasRecentlyDamagedByHero(enemy,2) then ctx.target=enemy;break end
		end
	end
	if not ctx.target and not state.combo and U.Castable(q) and bot:GetMana()>=U.Mana(q)+90 then
		for _,enemy in ipairs(ctx.enemies) do
			if U.EntityAllowed(bot,enemy,q) then
				local damage=M.Damage(bot,enemy,M.QRaw(bot),DAMAGE_TYPE_MAGICAL)
				local action={damage=damage or 0,cast=U.CastPoint(q),mana=U.Mana(q)}
				if damage and damage>=enemy:GetHealth()*1.05 and WorthQ(bot,enemy,action) then ctx.target=enemy;break end
			end
		end
	end
	-- 万宝槌即时攻击前先确认法球开关；避免模型计入实际未开启的法球。
	if ManageOrb(bot,ctx) then return end
	local actions=S.Actions(bot,ctx)
	for _,a in ipairs(actions) do
		if a.cooldown<=0 and a.wait<=0.1 and not a.offensive and a.utility>=250 then if U.Issue(bot,a) then return end end
	end
	local external=Pool.Consider(bot,ctx)
	-- 对外 R 同样会丢弃旧返回点；存在返回状态时必须先找到新的安全脱离落点。
	if external and U.Has(bot,C.RETURN) and S.EscapePoint(bot,ctx)==nil then external=nil end
	if external and U.Has(bot,C.RETURN) then external.followup={'sagume_disengage'} end
	if external and external.priority>=90 and U.Issue(bot,external) then return end
	if FollowCombo(bot,ctx,actions) then return end
	local selfR=not state.combo and SelfRefresh(bot,ctx,actions) or nil
	local selected=external
	if selfR and (not selected or selfR.priority>selected.priority) then selected=selfR end
	if selected and U.Issue(bot,selected) then return end
	-- 普通 Q 的法球机会成本不能被连段入口绕过；当前可用道具按实际作用排序。
	table.sort(actions,function(a,b) return a.utility+a.damage>b.utility+b.damage end)
	for _,a in ipairs(actions) do
		if a.cooldown<=0 and a.wait<=0.1 and U.Castable(a.ability)
		and not (a.id==C.W and U.Has(bot,C.RETURN))
		and (a.ability:IsItem() or not bot:IsSilenced()) then
			local worthwhile=true
			if a.id==C.Q then
				worthwhile=ctx.retreat or a.utility>=100 or WorthQ(bot,ctx.target,a)
				if not ctx.retreat and bot:GetMana()-a.mana<190 then worthwhile=false end
			elseif a.id==C.W and bot:GetMana()-a.mana<190 then worthwhile=false end
			if worthwhile and U.Issue(bot,a) then return end
		end
	end
	if TryMaintenance(bot,ctx) then return end
	local neutral=bot:GetItemInSlot(16)
	if not U.Busy(bot) and U.Castable(neutral) then
		ConsiderNeutralItems()
		-- 共享 neutral helper 不返回是否下单，保守预留本轮间隔给它完成动作。
		bot.THD_SagumeActionUntil=U.Now()+0.10
	end
end

return S
