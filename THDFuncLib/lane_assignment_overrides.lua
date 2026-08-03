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
return {}
