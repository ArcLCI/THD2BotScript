-- 可复用的收益观察/个人风险常量，不含推进任务或执行开关。
local Execution=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
return {
	DEBUG = true,
	LOG_INTERVAL = 2.0,
	MAX_TOWER_DAMAGE_RATIO = 0.35,
	NET_MIN_FRACTION = 0.005,
	NET_MIN_HEALTH = 16,
	NET_MIN_SPAN = 2.0,
	NET_SAMPLE_GAP = 1.5,
	NET_WINDOW = 3.0,
	PERSONAL_TOWER_CLEAR_STABLE = 0.75,
	PERSONAL_TOWER_REJOIN = 0.60,
	PERSONAL_TOWER_RESERVE = 0.45,
	PERSONAL_TOWER_RETRY = 2.0,
	RUN_ID = Execution.RUN_ID,
	SAMPLE_INTERVAL = 0.75,
	SIEGE_SHADOW_DEBUG = true,
}
