-- 分线专项测试只在 Bot Lua 侧读取，避免选人阶段访问或修改原生英雄能力。
-- 修改后需要重新载入 Bot 脚本或开始新对局。
return {
	testMode = {
		radiant = false,
		dire = false,
	},
}
