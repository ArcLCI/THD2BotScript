-- 同pid可有本体与分身；统一与Execution使用同一句柄token，禁止跨实体拼接验收。
local A={}
function A.Fields(bot)
	-- 诊断也遵守Bot可见信息边界：敌方幻象身份未知，不发起非法查询。
	local illusion='unknown'
	if bot:GetTeam()==GetTeam() then illusion=tostring(bot:IsIllusion()) end
	return string.format(' actor_token=%s actor_name=%s actor_is_current=%s actor_alive=%s actor_illusion=%s',
		tostring(bot):gsub('%s','_'),tostring(bot:GetUnitName()),tostring(bot==GetBot()),
		tostring(bot:IsAlive()),illusion)
end
return A
