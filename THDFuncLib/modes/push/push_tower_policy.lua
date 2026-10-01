-- 推进中的个人承伤门：不分配坦克，不替其他成员关闭任务，也不发布动作。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/push/push_escort_config')
local P={}
function P.Evaluate(bot,target,threat,enemyCount)
	local now,hp,maximum=DotaTime(),bot:GetHealth(),math.max(1,bot:GetMaxHealth())
	local incoming=threat.unavoidableDamage or 0
	local predicted=math.max(incoming,threat.predictedDamage or 0)
	local function Result(allowed,reason)
		local state=bot.THD_PushTowerLog or {}
		if Config.DEBUG and (state.reason~=reason or now-(state.at or -90)>=Config.LOG_INTERVAL) then
			print(string.format('[BOT][PushTower] run=%s time=%.3f pid=%s allowed=%s reason=%s hp=%.1f max_hp=%.1f predicted=%.1f incoming=%.1f locked=%s retry_at=%s',
				Config.RUN_ID,now,bot:GetPlayerID(),tostring(allowed),reason,hp,maximum,predicted,incoming,
				tostring(threat.locked==true),tostring(bot.THD_PushTowerRetryAt)))
			bot.THD_PushTowerLog={reason=reason,at=now}
		end
		return allowed,reason
	end
	local function Remember(reason)
		local tower=threat.escapeTower and threat.escapeTower.tower or target
		local old=bot.THD_PushTowerRecovery
		bot.THD_PushTowerRecovery={tower=tower,reason=reason,startedAt=old and old.startedAt or now}
		bot.THD_PushTowerRetryAt=now+Config.PERSONAL_TOWER_RETRY
	end
	if threat.unseenIncoming or incoming>=hp then
		Remember('unavoidable_tower_danger')
		return Result(false,'unavoidable_tower_danger')
	end
	local covered=false
	-- 没被锁定不代表进圈后安全：预估目标塔转火后的三秒普通攻击。
	if target and not target:IsNull() and target:CanBeSeen() and target:IsAlive()
	and GetUnitToUnitDistance(bot,target)<=1400 and target:GetAttackDamage()>0 then
		local victim=target:GetAttackTarget()
		covered=victim and not victim:IsNull() and victim:CanBeSeen() and victim:IsAlive()
			and victim~=bot and victim:GetTeam()==bot:GetTeam()
		if not covered and not threat.locked then
			local interval=math.max(0.3,target:GetSecondsPerAttack())
			predicted=math.max(predicted,bot:GetActualIncomingDamage(target:GetAttackDamage(),DAMAGE_TYPE_PHYSICAL)*math.ceil(3/interval))
		end
	end
	local regen=math.min(math.max(0,bot:GetHealthRegen())*3,predicted*0.2)
	local reserve=maximum*Config.PERSONAL_TOWER_RESERVE
	local safe=hp-predicted+regen>=reserve
	if not safe then
		-- 仅真实承伤建立退让迟滞；远处不适合进入的候选不能封锁其他安全目标。
		if threat.active then Remember('personal_tower_budget') end
		return Result(false,'personal_tower_budget')
	end
	if now<(bot.THD_PushTowerRetryAt or -90) then return Result(false,'personal_tower_recovery') end
	local recovery=bot.THD_PushTowerRecovery
	if recovery and (recovery.tower==target or threat.active or recovery.tower==nil) then
		-- 因承伤退出后，不能仅因Retreat分数下降立即返回；先确认弹道/锁定已解除。
		if incoming>0 or threat.locked then recovery.clearSince=nil;return Result(false,'await_tower_transfer') end
		local transfer=false
		local tower=recovery.tower
		if tower and not tower:IsNull() and tower:CanBeSeen() and tower:IsAlive() then
			local victim=tower:GetAttackTarget()
			transfer=victim and victim~=bot and not victim:IsNull() and victim:CanBeSeen() and victim:IsAlive() and victim:GetTeam()==bot:GetTeam()
		end
		if hp/maximum<Config.PERSONAL_TOWER_REJOIN and not transfer then recovery.clearSince=nil;return Result(false,'tower_recovery_health') end
		recovery.clearSince=recovery.clearSince or now
		if now-recovery.clearSince<Config.PERSONAL_TOWER_CLEAR_STABLE then return Result(false,'tower_reentry_settling') end
		bot.THD_PushTowerRecovery=nil;bot.THD_PushTowerRetryAt=nil
	elseif not recovery then
		bot.THD_PushTowerRetryAt=nil
	end
	return Result(true,covered and not threat.locked and enemyCount==0 and not bot:WasRecentlyDamagedByAnyHero(3)
		and 'covered_tower_window' or 'personal_tower_budget_ok')
end
return P
