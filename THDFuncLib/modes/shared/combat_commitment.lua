-- 只约束具体技能的落点与施法保护，不替代引擎Attack/Retreat仲裁。
local J=require(GetScriptDirectory()..'/THDFuncLib/thd_func')
local G=require(GetScriptDirectory()..'/THDFuncLib/modes/evasive/avoidance_geometry')
local Towers=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/tower_safety')
local Actions=require(GetScriptDirectory()..'/THDFuncLib/action_intent')
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Actor=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/actor_diagnostics')
local C={}
function C.Note(bot,reason,ability,point)
	if not Config.DEBUG then return end
	local now=DotaTime()
	if bot.THD_CombatNoteReason==reason and now-(bot.THD_CombatNoteAt or -90)<2 then return end
	bot.THD_CombatNoteReason,bot.THD_CombatNoteAt=reason,now
	print(string.format('[BOT][CombatDecision] run=%s time=%.3f pid=%s reason=%s ability=%s mode=%s desire=%.3f hp=%.0f max_hp=%.0f action=%s goal_x=%s goal_y=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),reason,tostring(ability and ability:GetName()),bot:GetActiveMode(),bot:GetActiveModeDesire(),
		bot:GetHealth(),bot:GetMaxHealth(),bot:GetCurrentActionType(),tostring(point and point.x),tostring(point and point.y))..Actor.Fields(bot))
end
function C.Observe(bot)
	if not Config.DEBUG or not bot or bot:IsNull() or bot:IsIllusion() then return end
	local now,deaths=DotaTime(),GetHeroDeaths(bot:GetPlayerID())
	local changed=bot.THD_CombatDeaths~=nil and deaths~=bot.THD_CombatDeaths
	if not changed and now-(bot.THD_CombatSampleAt or -90)<1 then return end
	local previous=bot.THD_CombatSampleAt
	bot.THD_CombatSampleAt,bot.THD_CombatDeaths=now,deaths
	local ability=bot:GetCurrentActiveAbility()
	print(string.format('[BOT][CombatState] run=%s time=%.3f pid=%s event=%s deaths=%s previous_at=%s mode=%s desire=%.3f hp=%.0f max_hp=%.0f mana=%.0f action=%s x=%.1f y=%.1f ability=%s recent_hero=%s recent_tower=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),changed and 'death_count_changed' or 'sample',deaths,tostring(previous),bot:GetActiveMode(),bot:GetActiveModeDesire(),
		bot:GetHealth(),bot:GetMaxHealth(),bot:GetMana(),bot:GetCurrentActionType(),bot:GetLocation().x,bot:GetLocation().y,
		tostring(ability and not ability:IsNull() and ability:GetName() or nil),tostring(bot:WasRecentlyDamagedByAnyHero(2)),tostring(bot:WasRecentlyDamagedByTower(2)))..Actor.Fields(bot))
end
function C.Issued(bot,ability,point,reason)
	Actions.NoteIssued(bot,'ability',ability,point)
	Actions.Protect(bot,ability,math.max(0.15,ability:GetCastPoint()+0.1))
	C.Note(bot,reason,ability,point)
end
function C.SafeLanding(bot,point,escape)
	if not point or not IsLocationVisible(point) or not IsLocationPassable(point) then return false,'landing_unseen_or_blocked' end
	local towers=Towers.Observe(bot,'hero_mobility')
	if not towers.available then return false,'tower_snapshot_unavailable' end
	local safe,why=G.ValidateMovementSegment(bot:GetLocation(),point,towers.towers,96,escape==true)
	if not safe then return false,'tower_'..tostring(why) end
	if not escape then
		if J.IsRetreating(bot) or J.GetHP(bot)<0.5 then return false,'offensive_dash_low_health_or_retreat' end
		local enemies=J.GetEnemiesNearLoc(point,1000)
		local allies=J.GetAlliesNearLoc(point,1000)
		if #enemies>#allies or (#enemies>0 and not J.WeAreStronger(bot,1000)) then return false,'offensive_dash_local_disadvantage' end
	end
	return true
end
function C.EscapePoint(bot,range)
	local origin,home=bot:GetLocation(),GetShopLocation(bot:GetTeam(),SHOP_HOME)
	local delta=home-origin
	if delta:Length2D()<120 then return nil end
	local enemies=J.GetNearbyHeroes(bot,1200,true,BOT_MODE_NONE)
	for _,length in ipairs({range,math.min(range,500),math.min(range,300)}) do
		for _,degrees in ipairs({0,30,-30}) do
			local angle=math.rad(degrees);local direction=delta:Normalized()
			local point=origin+Vector(direction.x*math.cos(angle)-direction.y*math.sin(angle),direction.x*math.sin(angle)+direction.y*math.cos(angle),0)*length
			local safe=G.Distance(point,home)<G.Distance(origin,home)-96 and C.SafeLanding(bot,point,true)
			for _,enemy in ipairs(enemies) do
				if Actions.ValidTarget(enemy) and G.Distance(point,enemy:GetLocation())<GetUnitToUnitDistance(bot,enemy)-32 then safe=false;break end
			end
			if safe then return point end
		end
	end
	return nil
end
return C
