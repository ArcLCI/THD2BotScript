-- 人工审核以“原版英雄槽位 + 实际 Bot profile”为一条独立定位记录。
-- 每条记录必须完整填写 14 项 0-3 整数；缺项或越界时整条记录不会参与分路。
-- 预置模板保持 enabled = false；填完该定位全部 14 项后再改为 true。
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
-- low_gold_value 低金钱价值 不补刀时是否仍有稳定作用？；
-- low_experience_value 低经验价值 少等级时是否仍有稳定作用？；
-- solo_experience_conversion 单人经验转化 独享经验能否迅速转化为压制、击杀或团队节奏？；
-- late_carry 后期承载 是否能够持续消化团队最高经济？。
return {
	schemaVersion = 1,
	heroes = {
		-- Momiji：damage / frontline
		["npc_dota_hero_bounty_hunter"] = {
			damage = {
				enabled = false, label = "Momiji 输出定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
			frontline = {
				enabled = false, label = "Momiji 前排定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
		},

		-- Sunny：frontline / support
		["npc_dota_hero_rattletrap"] = {
			frontline = {
				enabled = false, label = "Sunny 前排定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
			support = {
				enabled = false, label = "Sunny 辅助定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
		},

		-- Yuuka：damage / frontline
		["npc_dota_hero_venomancer"] = {
			damage = {
				enabled = false, label = "Yuuka 输出定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
			frontline = {
				enabled = false, label = "Yuuka 前排定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
		},

		-- Nitori：damage / support
		["npc_dota_hero_spectre"] = {
			damage = {
				enabled = false, label = "Nitori 近身输出定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
			support = {
				enabled = false, label = "Nitori 法系辅助定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
		},

		-- Patchouli 的四项最高 Role 同为 3，因此普通选人可落入三种定位池。
		["npc_dota_hero_invoker"] = {
			damage = {
				enabled = true, label = "Patchouli 输出定位",
				traits = {
					gold_scaling = 2, level_scaling = 3, lane_independence = 3,
					last_hit = 2, trading = 3, wave_control = 1,
					initiation = 1, follow_up = 3, protection = 1,
					roaming = 2, low_gold_value = 1, low_experience_value = 0,
					solo_experience_conversion = 3, late_carry = 2,
				},
				-- 输出定位保留强换血/跟进事实，但不让它被误作无经济辅助。
				position_caps = {off_core = 18, soft_support = 12, hard_support = 4},
			},
			frontline = {
				enabled = false, label = "Patchouli 前排定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
			support = {
				enabled = false, label = "Patchouli 辅助定位",
				traits = {
					gold_scaling = nil, level_scaling = nil, lane_independence = nil,
					last_hit = nil, trading = nil, wave_control = nil,
					initiation = nil, follow_up = nil, protection = nil,
					roaming = nil, low_gold_value = nil, low_experience_value = nil,
					solo_experience_conversion = nil, late_carry = nil,
				},
			},
		},
	},
}
