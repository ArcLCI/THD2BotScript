-- 仅采样自身状态；不发单、不扫描敌人，也不把游戏侧信息回传决策。
local O = { ENABLED = true }
local Build = require(GetScriptDirectory()..'/THDFuncLib/acceptance_build')
local Config = require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local function Token(value) return tostring(value):gsub('%s','_') end
local function Sample(bot,source)
	if not bot or bot~=GetBot() or bot:IsNull() or not bot:IsHero() or bot:IsIllusion() then return end
	local now=DotaTime()
	local state=bot.THD_AcceptanceObservation
	if not state then
		state={at=-1000,sequence=0,instance=Token(bot)};bot.THD_AcceptanceObservation=state
		print(string.format('[BOT][BuildLoaded] schema=2 producer=thd_acceptance_v2 component=bot build_id=%s run_id=%s pid=%d team=%d time=%.3f revision=%s scope=observer_and_manifest',
			Build.BUILD_ID,Build.RUN_ID,bot:GetPlayerID(),bot:GetTeam(),now,Config.RUN_ID))
	end
	if now>=state.at and now-state.at<1 then return end
	state.at=now;state.sequence=state.sequence+1
	local point=bot:GetLocation()
	local active=bot:GetCurrentActiveAbility()
	local phase=active and active:IsInAbilityPhase() or false
	local channel=bot:IsChanneling() or (active and active:IsChanneling()) or false
	local protection=bot.THD_ActionProtection
	local protected=phase or channel or bot:IsCastingAbility() or bot:IsUsingAbility()
		or (protection and now<(protection.untilTime or -90)) or false
	print(string.format('[BOT][AcceptanceSample] schema=2 producer=thd_acceptance_v2 build_id=%s run_id=%s time=%.3f pid=%d team=%d logger_instance=%s sample=%d alive=%s bot_x=%.1f bot_y=%.1f mode=%d desire=%.3f action=%d attack_target=%s protected=%s channeling=%s ability_phase=%s sample_source=%s',
		Build.BUILD_ID,Build.RUN_ID,now,bot:GetPlayerID(),bot:GetTeam(),state.instance,state.sequence,
		tostring(bot:IsAlive()),point.x,point.y,bot:GetActiveMode(),bot:GetActiveModeDesire(),bot:GetCurrentActionType(),
		bot:GetAttackTarget() and 'present' or 'none',tostring(protected),tostring(channel),tostring(phase),Token(source or 'ability_or_item')))
end
function O.Pump(bot,source)
	if not O.ENABLED then return end
	-- 诊断失败只关闭观察器，不能阻断技能/物品入口。
	local ok,err=pcall(Sample,bot,source)
	if not ok then O.ENABLED=false;print('[BOT][AcceptanceError] producer=thd_acceptance_v2 error='..Token(err)) end
end
function O.ResourceStage(bot,event,itemName,state)
	if not O.ENABLED then return end
	local ok,err=pcall(function()
		O.Pump(bot)
		if state and not state.acceptanceRequest then
			bot.THD_AcceptanceRequestSerial=(bot.THD_AcceptanceRequestSerial or 0)+1
			state.acceptanceRequest=Token(bot)..'_'..bot.THD_AcceptanceRequestSerial
		end
		print(string.format('[BOT][ResourceStage] schema=2 producer=thd_acceptance_v2 run_id=%s build_id=%s time=%.3f pid=%d team=%d event=%s item=%s request_id=%s evidence=bot_stage',
			Build.RUN_ID,Build.BUILD_ID,DotaTime(),bot:GetPlayerID(),bot:GetTeam(),Token(event),Token(itemName),Token(state and state.acceptanceRequest)))
	end)
	if not ok then O.ENABLED=false;print('[BOT][AcceptanceError] producer=thd_acceptance_v2 error='..Token(err)) end
end
return O
