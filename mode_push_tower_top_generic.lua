-- 原生推进常驻，仅在THD建筑保护条件成立时短时否决评分；不注册Think。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
GetDesire,Think,OnStart,OnEnd=nil,nil,nil,nil
if Config.NATIVE_PUSH_THD_PROTECTION then
    local Guard=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/native_push_guard')
    function GetDesire() return Guard.Desire(GetBot(),LANE_TOP) end
end
local bot=GetBot()
if bot and bot:IsHero() and not bot:IsIllusion() then
    print('[BOT][NativePush] run='..Config.RUN_ID..' lane=top pid='..bot:GetPlayerID()
        ..' callbacks='..(GetDesire and 'desire_guard_only' or 'absent')..' think=absent')
end
