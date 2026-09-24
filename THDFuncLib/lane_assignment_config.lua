-- 分线专项测试只在 Bot Lua 侧读取，避免选人阶段访问或修改原生英雄能力。
-- 修改后需要重新载入 Bot 脚本或开始新对局。
return {
	-- 临时分线诊断：每个 Bot 自报引擎分路，与 [LaneAssign] 规划日志按 team/pid 对照。
	diagnostics = {
		enabled = true,
		interval = 15,
		endTime = 120,
	},
	testMode = {
		radiant = false,
		dire = false,
	},
}
