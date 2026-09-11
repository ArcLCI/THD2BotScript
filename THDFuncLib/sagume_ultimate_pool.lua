local U = require(GetScriptDirectory()..'/THDFuncLib/sagume_util')
local C = require(GetScriptDirectory()..'/THDFuncLib/sagume_config')
local P = {}

-- 用长冷却与战术作用人工入池；不是 AbilityType=ULTIMATE 的自动扫描。
P.Entries = {
	{hero='npc_dota_hero_lion',id='ability_thdots_sanae04',kind='protect',priority=90,range=600,
		active='modifier_thdots_sanae04_caster',effect='modifier_thdots_sanae04_target',upper=150,duration=5},
	{hero='npc_dota_hero_silencer',id='ability_thdots_eirin04',kind='rescue',priority=95,range=800,
		effect='modifier_ability_thdots_eirin04_effect',upper=150,duration=9},
	{hero='npc_dota_hero_lina',id='ability_dota2x_reimu04',kind='zone',priority=75,range=600,
		effect='modifier_ability_dota2x_reimu04_immue',upper=180,duration=20},
	{hero='npc_dota_hero_tidehunter',id='ability_thdots_suika04',kind='transform',priority=65,range=650,
		active='modifier_thdots_Suika_04',upper=180,duration=30},
	{hero='npc_dota_hero_crystal_maiden',id='ability_thdots_marisa04',kind='beam',priority=75,range=1200,
		active='modifier_thdots_marisa04_think_interval',upper=240,duration=8},
	{hero='npc_dota_hero_necrolyte',id='ability_thdots_yuyuko04',kind='execute',priority=80,range=650,
		active='modifier_thdots_yuyuko04_think_interval',upper=180,duration=4},
	{hero='npc_dota_hero_sniper',id='ability_thdots_Utsuho04',kind='aoe',priority=75,range=1200,
		active='modifier_thdots_Utsuho04_think_interval',upper=240,duration=6.5,cleanup=1.1},
	{hero='npc_dota_hero_bane',id='ability_thdots_shinki_02',kind='transform',priority=70,range=700,
		active='modifiery_thdots_shinki_02_buff',upper=150,duration=55},
}
local byHero = {}
for _,entry in ipairs(P.Entries) do byHero[entry.hero] = entry end

local function Entry(unit)
	return U.Valid(unit) and byHero[unit:GetUnitName()] or nil
end
local function Nearby(unit,ctx,enemyTeam,radius)
	local result = {}
	local units = enemyTeam and ctx.enemies or ctx.allies
	for _,other in ipairs(units) do
		if U.Valid(other) and GetUnitToUnitDistance(unit,other) <= radius then result[#result+1]=other end
	end
	return result
end
local function Threatened(unit)
	return U.Valid(unit) and U.Safe(false,function()
		return unit:WasRecentlyDamagedByAnyHero(2) and unit:GetHealth()/unit:GetMaxHealth() < 0.55
	end)
end

function P.Opportunity(unit,a,e,ctx,enemy)
	if U.Has(unit,e.active or '') or U.Busy(unit) then return false end
	local victims = Nearby(unit,ctx,not enemy,e.range)
	local friends = Nearby(unit,ctx,enemy,e.range)
	if e.kind == 'rescue' then
		for _,friend in ipairs(friends) do
			if Threatened(friend) and not U.Has(friend,e.effect) then return true end
		end
	elseif e.kind == 'protect' then
		for _,friend in ipairs(friends) do
			if Threatened(friend) and not U.Has(friend,e.effect) then return true end
		end
	elseif e.kind == 'transform' then
		return #victims >= 1 and (Threatened(unit) or U.Safe(false,function() return unit:GetAttackTarget() ~= nil end))
	elseif e.kind == 'execute' then
		local hurt=0
		for _,victim in ipairs(victims) do if victim:GetHealth()/victim:GetMaxHealth() < 0.55 then hurt=hurt+1 end end
		return hurt >= 2
	elseif e.kind == 'beam' then
		local width=U.Special(a,'damage_width',200)
		for _,victim in ipairs(victims) do
			local source,p=unit:GetLocation(),victim:GetLocation()
			local dx,dy=p.x-source.x,p.y-source.y
			local length=math.max(1,math.sqrt(dx*dx+dy*dy))
			local hits=0
			for _,other in ipairs(victims) do
				local q=other:GetLocation()
				local along=((q.x-source.x)*dx+(q.y-source.y)*dy)/length
				local across=math.abs((q.x-source.x)*dy-(q.y-source.y)*dx)/length
				if along >= 0 and along <= e.range and across <= width*0.5 then hits=hits+1 end
			end
			if hits >= 2 then return true end
		end
	elseif e.kind == 'zone' then
		if U.Has(unit,e.effect) then return false end
		return #victims >= 2 or (#victims > 0 and Threatened(unit))
	elseif e.kind == 'aoe' then
		for _,victim in ipairs(victims) do
			local hits=0
			for _,other in ipairs(victims) do if GetUnitToUnitDistance(victim,other) <= 450 then hits=hits+1 end end
			if hits >= 2 then return true end
		end
	end
	return false
end

-- 不读取敌方冷却、IsCooldownReady 或技能充能；只保留可见状态的数值历史。
function P.Observe(bot,ctx)
	local state,now=U.State(bot),U.Now()
	if now < (state.nextObservation or 0) then return end
	state.nextObservation=now+C.OBSERVE_INTERVAL
	local touched={}
	for _,enemy in ipairs(ctx.enemies) do
		local e=Entry(enemy)
		if e then
			local id=enemy:GetPlayerID()
			local record=state.observations[id]
			if not record or record.hero~=e.hero or now-(record.lastSeen or -90)>0.35 then
				record={hero=e.hero,since=now,possibleCast=now,status='unknown'}
				state.observations[id]=record
			end
			touched[id]=true
			record.lastSeen=now
			local active=U.Safe(nil,function() return enemy:GetCurrentActiveAbility() end)
			local name=active and U.Safe('',function() return active:GetName() end) or ''
			if name~='' and name~=e.id then record.otherCast=now end
			if name==e.id or U.Has(enemy,e.active or '') then
				record.possibleCast=now
				record.status='observed_cast_or_effect'
			elseif now-math.max(record.since,record.possibleCast)>e.upper+1 then
				record.status='inferred_ready'
			else record.status='unknown_or_cooling' end
			U.Log(bot,'enemy_observation',{reason=e.id,target=id,state=record.status,continuous=math.floor(now-record.since)},5)
		end
	end
	for id,record in pairs(state.observations) do
		if not touched[id] and now-(record.lastSeen or -90)>0.35 then record.status='unknown';record.since=now end
	end
end

local function AllySideEffects(unit,key,ctx)
	-- 自身特殊能力与充能技能不能被通用刷新器假设为普通技能。
	for slot=0,23 do
		local a=U.Safe(nil,function() return unit:GetAbilityInSlot(slot) end)
		if a and a~=key and U.Level(a)>0 then
			local name=a:GetName()
			if name=='ability_thdots_sanae_lyz' or name=='ability_thdots_sakuya04'
			or U.Special(a,'AbilityCharges',0)>0 then return false end
			local cd=U.Cooldown(a)
			if cd==nil then return false end
			local protected = name=='ability_thdots_suika03' or name=='ability_thdots_marisa02'
				or name=='ability_thdots_eirin03' or name=='ability_thdots_yuyuko02'
			if cd<=0 and protected and Threatened(unit) and U.Mana(a)<=unit:GetMana() then return false end
		end
	end
	for slot=0,5 do
		local item=unit:GetItemInSlot(slot)
		if item and U.Cooldown(item)==0 and not U.Safe(true,function() return item:IsPassive() end)
		and Threatened(unit) then return false end
	end
	return true
end

function P.Consider(bot,ctx)
	local r=U.Ability(bot,C.R)
	if not U.Castable(r) or bot:IsSilenced() or U.Now()-U.State(bot).lastR<C.REFRESH_REUSE_DELAY then return nil end
	local best,now=nil,U.Now()
	local state=U.State(bot)
	state.allyEffects=state.allyEffects or {}
	for _,ally in ipairs(ctx.allies) do
		local e=ally~=bot and Entry(ally) or nil
		local a=e and U.Ability(ally,e.id) or nil
		if a and U.Level(a)>0 then
			local id=ally:GetPlayerID()
			local effect=state.allyEffects[id] or {untilAt=now+(e.cleanup or 0)+0.2,wasActive=false}
			state.allyEffects[id]=effect
			local active=U.Has(ally,e.active or '') or U.Safe(false,function() return a:IsInAbilityPhase() or a:IsChanneling() end)
			if active then effect.untilAt=now+(e.cleanup or 0)+0.2;effect.wasActive=true
			elseif effect.wasActive then effect.untilAt=now+(e.cleanup or 0)+0.2;effect.wasActive=false end
			local cd=U.Cooldown(a)
			local urgent=e.kind=='rescue' or e.kind=='protect'
			if cd and cd>(urgent and U.CastPoint(r)+0.2 or 8) and now>=effect.untilAt
			and ally:GetMana()>=U.Mana(a) and bot:GetMana()>=U.Mana(r)+90
			and U.EntityAllowed(bot,ally,r) and P.Opportunity(ally,a,e,ctx,false)
			and AllySideEffects(ally,a,ctx) then
				local score=e.priority+(U.Profile(bot)=='support' and 5 or 0)
				if not best or score>best.priority then best={ability=r,target=ally,reason='ally_refresh:'..e.id,
					priority=score,key=e.id} end
			end
		end
	end
	for _,enemy in ipairs(ctx.enemies) do
		local e=Entry(enemy)
		local record=state.observations[enemy:GetPlayerID()]
		local a=e and U.Ability(enemy,e.id) or nil
		if e and a and U.Level(a)>0 and record and record.status=='inferred_ready'
		and now-(record.otherCast or -90)>8
		and U.EntityAllowed(bot,enemy,r) and P.Opportunity(enemy,a,e,ctx,true)
		and bot:GetMana()>=U.Mana(r)+90 then
			U.Log(bot,'enemy_candidate',{reason=e.id,target=enemy:GetPlayerID(),enabled=C.ENEMY_LOCK_ENABLED},2)
			if C.ENEMY_LOCK_ENABLED and not ctx.retreat and (not best or e.priority>best.priority) then
				best={ability=r,target=enemy,reason='enemy_lock:'..e.id,priority=e.priority,key=e.id}
			end
		end
	end
	return best
end

return P
