-- 人数预算按实际队伍与存活人数缩放；敌方真实人数/战力安全门由各模式保留。
local T={}
local cache={}
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
function T.Snapshot()
	local team,now=GetTeam(),DotaTime()
	local old=cache[team]
	if old and now-old.at<0.75 then return old end
	local s={at=now,total=0,alive=0,available=0,bots=0,aliveBots=0,enemyTotal=0,enemyAlive=0}
	for index,id in ipairs(GetTeamPlayers(team) or {}) do
		s.total=s.total+1
		local alive=IsHeroAlive(id)
		if alive then s.alive=s.alive+1 end
		if IsPlayerBot(id) then
			s.bots=s.bots+1;if alive then s.aliveBots=s.aliveBots+1;s.available=s.available+1 end
		elseif alive then
			local member=GetTeamMember(index)
			-- 泉水内无敌的观测真人不增加Bot任务人数要求；正常离泉队友仍计入。
			if member and not member:IsNull() and not (member:IsInvulnerable()
				and GetUnitToLocationDistance(member,GetShopLocation(team,SHOP_HOME))<1200) then s.available=s.available+1 end
		end
	end
	for _,id in ipairs(GetTeamPlayers(GetOpposingTeam()) or {}) do
		s.enemyTotal=s.enemyTotal+1;if IsHeroAlive(id) then s.enemyAlive=s.enemyAlive+1 end
	end
	if Config.DEBUG and (not old or old.total~=s.total or old.available~=s.available or old.enemyAlive~=s.enemyAlive) then
		print(string.format('[BOT][TeamBudget] run=%s time=%.3f team=%s total=%d alive=%d available=%d bots=%d alive_bots=%d enemy_total=%d enemy_alive=%d',
			Config.RUN_ID,now,team,s.total,s.alive,s.available,s.bots,s.aliveBots,s.enemyTotal,s.enemyAlive))
	end
	cache[team]=s;return s
end
function T.Group(fivePlayerCount)
	local s=T.Snapshot()
	return math.max(1,math.min(math.max(1,s.aliveBots),math.floor(fivePlayerCount*math.max(1,s.available)/5+0.5)))
end
function T.LeaveProgressCost(base)
	return math.min(0.30,base*5/math.max(1,T.Snapshot().available))
end
function T.EnemyGroup(fivePlayerCount)
	return math.max(1,math.floor(fivePlayerCount*math.max(1,T.Snapshot().enemyAlive)/5+0.5))
end
return T
