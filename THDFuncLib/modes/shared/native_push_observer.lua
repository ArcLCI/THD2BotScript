-- 原生推线只读观察：不注册推进回调、不写目标、不发动作，每个Bot最多一秒一条。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local Progress=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/native_push_progress')
local M={}
local nextAt=setmetatable({}, {__mode='k'})
function M.Observe(bot)
	if not bot or bot~=GetBot() or not bot:IsAlive() or bot:IsIllusion() then return end
	Progress.Update(bot)
	local mode=bot:GetActiveMode()
	if mode~=BOT_MODE_PUSH_TOWER_TOP and mode~=BOT_MODE_PUSH_TOWER_MID and mode~=BOT_MODE_PUSH_TOWER_BOT then return end
	local now=DotaTime()
	if now<(nextAt[bot] or -90) then return end
	nextAt[bot]=now+1
	local target=bot:GetAttackTarget()
	local name,hp='none','unknown'
	if target and not target:IsNull() and target:CanBeSeen() then name=target:GetUnitName();hp=tostring(target:GetHealth()) end
	local buildings={}
	for _,unit in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS) or {}) do
		if #buildings>=8 then break end
		if unit and not unit:IsNull() and unit:CanBeSeen() and GetUnitToUnitDistance(bot,unit)<=2200 then
			local point=unit:GetLocation()
			buildings[#buildings+1]=string.format('%s@%.0f:%.0f:%.0f:g%s:b%s:c%s',unit:GetUnitName(),point.x,point.y,unit:GetHealth(),
				tostring(unit:HasModifier('modifier_fountain_glyph')),tostring(unit:HasModifier('modifier_backdoor_protection_active')),
				tostring(unit:HasModifier('modifier_thdots_anti_bd_stop')))
		end
	end
	local point=bot:GetLocation()
	print(string.format('[BOT][NativePushSample] run=%s time=%.3f pid=%d team=%d mode=%d action=%d x=%.1f y=%.1f hp=%.0f target=%s target_hp=%s buildings=%s',
		Config.RUN_ID,now,bot:GetPlayerID(),bot:GetTeam(),mode,bot:GetCurrentActionType(),point.x,point.y,bot:GetHealth(),name,hp,
		#buildings>0 and table.concat(buildings,'|') or 'none'))
end
return M
