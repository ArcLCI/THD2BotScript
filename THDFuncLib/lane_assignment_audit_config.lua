-- 人工审核以“原版英雄槽位 + 实际 Bot profile”为一条独立定位记录。
-- 每条记录必须完整填写 12 项 0-3 整数；缺项或越界时整条记录不会参与分路。
-- 定位键使用 damage、damage_spell、frontline、support；base 只用于标记暂不可读的情况。
-- 指标含义：
-- gold_scaling 金钱成长 多拿 3000–6000 经济后，战斗力提升是否显著？；
-- level_scaling 等级成长 单独获得 3、5、6、7 级是否产生关键质变？；
-- lane_independence 独立生存 没有辅助时能否留在经验区？；
-- last_hit 补刀 基础攻击和技能能否稳定取得兵线经济？；
-- trading 换血 一级至三级能否有效消耗敌人？；
-- wave_control 兵线控制 能否清线、控线或抢远程兵？是否会失控推线？；
-- initiation 先手 能否可靠开启战斗？需要多少等级和装备？；
-- follow_up 跟进 队友先手后能否稳定提供伤害或控制？；
-- protection 保护 能否治疗、救援、驱散、减伤或阻止突进？；
-- roaming 游走 离开兵线后是否有移动、控制和击杀能力？；
-- low_economy 低经济价值 不补刀、少等级时是否仍有稳定作用？；
-- late_carry 后期承载 是否能够持续消化团队最高经济？。
return {
	schemaVersion = 1,
	heroes = {
		--[[
		["npc_dota_hero_venomancer"] = {
			damage = {
				label = "输出定位",
				traits = {
					gold_scaling = 0,
					level_scaling = 0,
					lane_independence = 0,
					last_hit = 0,
					trading = 0,
					wave_control = 0,
					initiation = 0,
					follow_up = 0,
					protection = 0,
					roaming = 0,
					low_economy = 0,
					late_carry = 0,
				},
			},
			frontline = {
				label = "前排定位",
				traits = {
					gold_scaling = 0,
					level_scaling = 0,
					lane_independence = 0,
					last_hit = 0,
					trading = 0,
					wave_control = 0,
					initiation = 0,
					follow_up = 0,
					protection = 0,
					roaming = 0,
					low_economy = 0,
					late_carry = 0,
				},
			},
		},
		]]
	},
}
