-- 此表只保存 THD 特例；未列出的分数继续使用 hero.txt 自动生成值。
-- scores 在通用 profile 增量之后覆盖，profiles 则在英雄 scores 之后按实际 profile 覆盖。
--[[
return {
	["npc_dota_hero_lina"] = {
		scores = {mid = 20},
		profiles = {
			support = {hard_support = 24},
		},
	},
}
]]
return {
	["npc_dota_hero_queenofpain"] = {
		-- 只覆盖探女的先验，最终分路仍由团队分配器决定。
		profiles = {
			damage = {mid=22, safe_core=20, off_core=6, soft_support=4, hard_support=1},
			support = {mid=3, safe_core=2, off_core=2, soft_support=22, hard_support=18},
		},
	},
	["npc_dota_hero_bristleback"] = {
		-- 华扇单一前排先验；不强行覆盖团队最终分路。
		profiles = {
			frontline = {off_core=22, safe_core=8, soft_support=6, mid=3, hard_support=1},
		},
	},
}
