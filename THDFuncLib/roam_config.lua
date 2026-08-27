local RoamConfig = {}

-- 新 gank 框架默认关闭；现有持续施法、连招和拾取逻辑不受此开关影响。
RoamConfig.ENABLED = true
RoamConfig.DEBUG = true
RoamConfig.ANNOUNCE_CHAT = true

RoamConfig.LANING_PHASE_END_TIME = 8 * 60
RoamConfig.APPROACH_TIMEOUT = 12.0
RoamConfig.ENGAGE_TIMEOUT = 12.0
RoamConfig.MISSION_TIMEOUT = 22.0
RoamConfig.ANNOUNCEMENT_WINDOW = 4.0
RoamConfig.ANNOUNCEMENT_TARGET_RADIUS = 900
RoamConfig.LOST_TARGET_GRACE = 2.5
-- 已发出 TP 的任务按通道生命周期暂停丢失计时，落地后再给一次短暂重获取窗口。
RoamConfig.TP_TARGET_REACQUIRE_GRACE = 2.0
RoamConfig.TEAM_COOLDOWN = 30.0
-- 任一 Bot 观察到肉山或团队推进后保留短时共享锁，避免刚发起 ROAM 就在下一帧释放。
RoamConfig.TEAM_OBJECTIVE_LOCK_DURATION = 4.0
RoamConfig.MAX_ROAMERS = 2
RoamConfig.PARTICIPANT_JOIN_TIMEOUT = 4.0
-- 跟随者观察到队长模式/目标短暂失配时先等待，持续超过该宽限才释放任务。
RoamConfig.LEADER_MISMATCH_GRACE = 2.0
RoamConfig.EARLY_ROAM_LEVEL = 5
RoamConfig.EARLY_ROAM_MAX_TRAVEL_TIME = 8.0
RoamConfig.EARLY_ROAM_TEAM_COOLDOWN = 45.0
RoamConfig.EARLY_ROAM_MAX_ROAMERS = 1
RoamConfig.EARLY_ROAM_OUTNUMBER_TARGET_HEALTH = 0.65
RoamConfig.EARLY_ROAM_KILL_CONFIRM_HEALTH = 0.30
RoamConfig.EARLY_ROAM_MIN_KILL_POWER_RATIO = 1.10

RoamConfig.LANE_DISTANCE = 900
RoamConfig.LOCAL_FIGHT_RADIUS = 1600
RoamConfig.TOWER_DANGER_RADIUS = 1200
RoamConfig.ENGAGE_DISTANCE = 900
RoamConfig.MIN_START_POWER_RATIO = 0.90
RoamConfig.MIN_CONTINUE_POWER_RATIO = 0.80
-- 先手移动和施法确认分开计时；近战控制不能在走进施法距离前耗尽整个起手窗口。
RoamConfig.INITIATION_APPROACH_TIMEOUT = 4.0
RoamConfig.INITIATION_CAST_TIMEOUT = 1.5
-- 兼容仍读取旧配置名的外部脚本；运行时起手状态机使用上面两个独立窗口。
RoamConfig.INITIATION_TIMEOUT = RoamConfig.INITIATION_CAST_TIMEOUT
RoamConfig.MIN_TARGET_SCORE = 0.35
RoamConfig.OUTNUMBER_TARGET_MIN_POWER_RATIO = 1.10
RoamConfig.OUTNUMBER_TARGET_SCORE_RELIEF = 0.10
RoamConfig.HIGH_HEALTH_TARGET_FRACTION = 0.90
RoamConfig.HIGH_HEALTH_MIN_PARTICIPANTS = 2
RoamConfig.TARGET_LOCAL_DAMAGE_FACTOR = 0.55
RoamConfig.TARGET_HEALTH_HISTORY_WINDOW = 2.0
RoamConfig.TARGET_HEALTH_HISTORY_MIN_DROP = 10.0
RoamConfig.TARGET_ARRIVAL_BUFFER = 0.75
RoamConfig.TARGET_TTK_BONUS_WINDOW = 6.0
RoamConfig.RALLY_UPDATE_LOG_DISTANCE = 300
RoamConfig.RALLY_UPDATE_LOG_INTERVAL = 1.0
-- idle 的低价值理由先稳定 2 秒再输出；同一理由保留低频心跳，避免模式抖动撑满 VConsole。
RoamConfig.DEBUG_STATUS_HEARTBEAT_INTERVAL = 15.0
RoamConfig.DEBUG_STATUS_DEBOUNCE_INTERVAL = 2.0
RoamConfig.PURSUIT_SAMPLE_INTERVAL = 0.5
RoamConfig.PURSUIT_ESCAPE_DISTANCE = 120
RoamConfig.PURSUIT_MIN_TARGET_DISTANCE = 650
RoamConfig.PURSUIT_SWITCH_DISTANCE = 1100
RoamConfig.PURSUIT_SWITCH_MARGIN = 0.10
RoamConfig.PURSUIT_RETREAT_POWER_RATIO = 0.75
RoamConfig.PURSUIT_RETREAT_HEALTH_FRACTION = 0.35
RoamConfig.PURSUIT_KEEP_TARGET_HEALTH_FRACTION = 0.28
RoamConfig.TP_MIN_WALK_DISTANCE = 4200
RoamConfig.TP_MAX_LANDING_DISTANCE = 2600
RoamConfig.TP_CHANNEL_TIME_ESTIMATE = 3.0
RoamConfig.TP_MIN_TIME_SAVING = 1.5
RoamConfig.TP_SAFE_RADIUS = 1200
RoamConfig.TP_CAST_START_GRACE = 1.0
RoamConfig.TP_LANDING_OBSERVED_RADIUS = 600
RoamConfig.TP_REPLAN_LOG_DISTANCE = 200
RoamConfig.COMBAT_LOG_INTERVAL = 1.0
RoamConfig.COMBAT_HEALTH_LOG_MIN_DELTA = 1.0

-- 十二分钟后启用严格的多打少抓单；普通线上 gank 仍沿用上面的旧参数。
RoamConfig.PICKOFF_START_TIME = 12 * 60
RoamConfig.PICKOFF_OBSERVATION_INTERVAL = 0.5
RoamConfig.PICKOFF_MAX_ENEMIES = 2
RoamConfig.PICKOFF_MAX_PARTICIPANTS = 3
RoamConfig.PICKOFF_GROUP_RADIUS = 1600
RoamConfig.PICKOFF_SINGLE_POWER_RATIO = 1.30
RoamConfig.PICKOFF_SINGLE_KILL_TIME = 6.0
RoamConfig.PICKOFF_PAIR_POWER_RATIO = 1.45
RoamConfig.PICKOFF_PAIR_FIRST_KILL_TIME = 4.5
RoamConfig.PICKOFF_UNKNOWN_POWER_BONUS = 0.20
RoamConfig.PICKOFF_UNKNOWN_KILL_TIME_PENALTY = 1.0
RoamConfig.PICKOFF_MAX_UNKNOWN_ENEMIES = 1
RoamConfig.PICKOFF_REINFORCEMENT_BUFFER = 3.0
RoamConfig.PICKOFF_CACHED_DAMAGE_MARGIN = 1.25
RoamConfig.PICKOFF_LAST_SEEN_MAX_AGE = 3.0
RoamConfig.PICKOFF_TOTAL_TIMEOUT = 30.0
RoamConfig.PICKOFF_ASSEMBLE_TIMEOUT = 8.0
-- 集合窗口按参与者到集合点的行程排期后，在预计到达时间上额外保留的缓冲。
RoamConfig.PICKOFF_ASSEMBLE_TRAVEL_BUFFER = 2.0
RoamConfig.PICKOFF_CONCEAL_TIMEOUT = 8.0
RoamConfig.PICKOFF_APPROACH_TIMEOUT = 12.0
RoamConfig.PICKOFF_AMBUSH_TIMEOUT = 6.0
RoamConfig.PICKOFF_ENGAGE_TIMEOUT = 6.0
RoamConfig.PICKOFF_ASSEMBLE_RADIUS = 750
RoamConfig.PICKOFF_STAGING_DISTANCE = 1600
RoamConfig.PICKOFF_REVALIDATE_RADIUS = 1600
RoamConfig.PICKOFF_SAFE_CORE_KILL_TIME = 3.0
RoamConfig.PICKOFF_SAFE_CORE_POWER_RATIO = 1.80
RoamConfig.PICKOFF_SAFE_CORE_MAX_TRAVEL_TIME = 4.0

-- 中后期局部战斗达到六名英雄且双方至少各两人时，交由团战模式而不是继续 ROAM。
RoamConfig.ROAM_TEAMFIGHT_START_TIME = RoamConfig.PICKOFF_START_TIME
RoamConfig.ROAM_TEAMFIGHT_RADIUS = 1600
RoamConfig.ROAM_TEAMFIGHT_MIN_ALLIES = 2
RoamConfig.ROAM_TEAMFIGHT_MIN_ENEMIES = 2
RoamConfig.ROAM_TEAMFIGHT_MIN_TOTAL_HEROES = 6

RoamConfig.SMOKE_PATROL_COOLDOWN = 90.0
RoamConfig.SMOKE_PATROL_MIN_EVIDENCE_AGE = 2.0
RoamConfig.SMOKE_PATROL_MAX_EVIDENCE_AGE = 25.0
RoamConfig.SMOKE_PATROL_PARTICIPANTS = 2
RoamConfig.SMOKE_APPLICATION_RADIUS = 900
RoamConfig.SMOKE_SAFE_ENEMY_RADIUS = 1200
RoamConfig.SMOKE_SAFE_TOWER_RADIUS = 1325
RoamConfig.SMOKE_PRECAST_STAGING_DISTANCE = 1800
RoamConfig.SMOKE_MIN_HEALTH = 0.70
RoamConfig.SMOKE_MIN_MANA = 0.60
-- 当前烟雾任务的实战利用率较低；关闭后同时禁止购买、提案和施放，但保留完整实现以便后续复评。
RoamConfig.SMOKE_ENABLED = false
-- 可见目标距离足够远且队伍已有烟时也先集合开雾，不再把烟限制在失踪目标巡逻。
RoamConfig.PICKOFF_VISIBLE_SMOKE_MIN_DISTANCE = 2000

-- 传送门和地图侧副包桥都先保留为默认关闭的实验开关。
RoamConfig.ENABLE_TWIN_GATE_ROUTE = false
RoamConfig.TWIN_GATE_SAFE_RADIUS = 1200
RoamConfig.TWIN_GATE_CAST_RANGE = 350
RoamConfig.TWIN_GATE_CHANNEL_TIME_ESTIMATE = 3.0
RoamConfig.TWIN_GATE_CAST_START_GRACE = 1.0
RoamConfig.BACKPACK_CAST_BRIDGE_ENABLED = false
RoamConfig.CONSUMABLE_PURCHASE_ENABLED = true

function RoamConfig.GetEnabledConsumablePurchaseItems(enemyNeedsDust)
	local items = {}
	if RoamConfig.SMOKE_ENABLED == true then table.insert(items, 'item_smoke_of_deceit') end
	if enemyNeedsDust == true then table.insert(items, 'item_dust') end
	return items
end

-- 仅登记已由 hero.txt 与游戏侧能力 Lua/KV 双重确认的隐身来源；购买与抓单共用同一份 ID 表。
RoamConfig.INVISIBILITY_HEROES = {
	npc_dota_hero_Rumia = true,
	npc_dota_hero_sunny = true,
	npc_dota_hero_wriggle = true,
	npc_dota_hero_kogasa = true,
	npc_dota_hero_parsee = true,
	npc_dota_hero_daiyousei = true,
	npc_dota_hero_eirin = true,
	npc_dota_hero_flandre = true,
	npc_dota_hero_Margatroid = true,
	npc_dota_hero_shion = true,
	npc_dota_hero_patchouli = true,
}

-- GetSelectedHeroName 在 override_hero 后可能返回基础槽位；以下映射逐项来自对应 hero.txt。
RoamConfig.INVISIBILITY_SELECTION_ALIASES = {
	npc_dota_hero_life_stealer = 'npc_dota_hero_Rumia',
	npc_dota_hero_rattletrap = 'npc_dota_hero_sunny',
	npc_dota_hero_clinkz = 'npc_dota_hero_wriggle',
	npc_dota_hero_riki = 'npc_dota_hero_kogasa',
	npc_dota_hero_pugna = 'npc_dota_hero_parsee',
	npc_dota_hero_nyx_assassin = 'npc_dota_hero_daiyousei',
	npc_dota_hero_silencer = 'npc_dota_hero_eirin',
	npc_dota_hero_naga_siren = 'npc_dota_hero_flandre',
	npc_dota_hero_visage = 'npc_dota_hero_Margatroid',
	npc_dota_hero_death_prophet = 'npc_dota_hero_shion',
	npc_dota_hero_invoker = 'npc_dota_hero_patchouli',
}

RoamConfig.POSITION_RULES = {
	mid = {
		minLevel = 6,
		minHealth = 0.70,
		minMana = 0.50,
		travelBias = 2.0,
	},
	soft_support = {
		minLevel = 4,
		minHealth = 0.60,
		minMana = 0.40,
		travelBias = 0.0,
	},
	hard_support = {
		minLevel = 5,
		minHealth = 0.60,
		minMana = 0.40,
		travelBias = 1.0,
	},
}

-- 新抓单候选允许五个位置参与；旧线上 gank 仍只读取 POSITION_RULES，不因此扩权。
RoamConfig.PICKOFF_POSITION_RULES = {
	mid = RoamConfig.POSITION_RULES.mid,
	soft_support = RoamConfig.POSITION_RULES.soft_support,
	hard_support = RoamConfig.POSITION_RULES.hard_support,
	off_core = {
		minLevel = 6,
		minHealth = 0.68,
		minMana = 0.45,
		travelBias = 0.5,
	},
	safe_core = {
		minLevel = 6,
		minHealth = 0.75,
		minMana = 0.55,
		travelBias = 3.0,
	},
}

local REQUIRED_POSITIVE_NUMBERS = {
	"LANING_PHASE_END_TIME",
	"APPROACH_TIMEOUT",
	"ENGAGE_TIMEOUT",
	"MISSION_TIMEOUT",
	"ANNOUNCEMENT_WINDOW",
	"ANNOUNCEMENT_TARGET_RADIUS",
	"LOST_TARGET_GRACE",
	"TP_TARGET_REACQUIRE_GRACE",
	"TEAM_COOLDOWN",
	"TEAM_OBJECTIVE_LOCK_DURATION",
	"MAX_ROAMERS",
	"PARTICIPANT_JOIN_TIMEOUT",
	"LEADER_MISMATCH_GRACE",
	"EARLY_ROAM_LEVEL",
	"EARLY_ROAM_MAX_TRAVEL_TIME",
	"EARLY_ROAM_TEAM_COOLDOWN",
	"EARLY_ROAM_MAX_ROAMERS",
	"EARLY_ROAM_OUTNUMBER_TARGET_HEALTH",
	"EARLY_ROAM_KILL_CONFIRM_HEALTH",
	"EARLY_ROAM_MIN_KILL_POWER_RATIO",
	"LANE_DISTANCE",
	"LOCAL_FIGHT_RADIUS",
	"TOWER_DANGER_RADIUS",
	"ENGAGE_DISTANCE",
	"MIN_START_POWER_RATIO",
	"MIN_CONTINUE_POWER_RATIO",
	"INITIATION_APPROACH_TIMEOUT",
	"INITIATION_CAST_TIMEOUT",
	"INITIATION_TIMEOUT",
	"MIN_TARGET_SCORE",
	"OUTNUMBER_TARGET_MIN_POWER_RATIO",
	"OUTNUMBER_TARGET_SCORE_RELIEF",
	"HIGH_HEALTH_TARGET_FRACTION",
	"HIGH_HEALTH_MIN_PARTICIPANTS",
	"TARGET_LOCAL_DAMAGE_FACTOR",
	"TARGET_HEALTH_HISTORY_WINDOW",
	"TARGET_HEALTH_HISTORY_MIN_DROP",
	"TARGET_ARRIVAL_BUFFER",
	"TARGET_TTK_BONUS_WINDOW",
	"RALLY_UPDATE_LOG_DISTANCE",
	"RALLY_UPDATE_LOG_INTERVAL",
	"DEBUG_STATUS_HEARTBEAT_INTERVAL",
	"DEBUG_STATUS_DEBOUNCE_INTERVAL",
	"PURSUIT_SAMPLE_INTERVAL",
	"PURSUIT_ESCAPE_DISTANCE",
	"PURSUIT_MIN_TARGET_DISTANCE",
	"PURSUIT_SWITCH_DISTANCE",
	"PURSUIT_SWITCH_MARGIN",
	"PURSUIT_RETREAT_POWER_RATIO",
	"PURSUIT_RETREAT_HEALTH_FRACTION",
	"PURSUIT_KEEP_TARGET_HEALTH_FRACTION",
	"TP_MIN_WALK_DISTANCE",
	"TP_MAX_LANDING_DISTANCE",
	"TP_CHANNEL_TIME_ESTIMATE",
	"TP_MIN_TIME_SAVING",
	"TP_SAFE_RADIUS",
	"TP_CAST_START_GRACE",
	"TP_LANDING_OBSERVED_RADIUS",
	"TP_REPLAN_LOG_DISTANCE",
	"COMBAT_LOG_INTERVAL",
	"COMBAT_HEALTH_LOG_MIN_DELTA",
	"PICKOFF_START_TIME",
	"PICKOFF_OBSERVATION_INTERVAL",
	"PICKOFF_MAX_ENEMIES",
	"PICKOFF_MAX_PARTICIPANTS",
	"PICKOFF_GROUP_RADIUS",
	"PICKOFF_SINGLE_POWER_RATIO",
	"PICKOFF_SINGLE_KILL_TIME",
	"PICKOFF_PAIR_POWER_RATIO",
	"PICKOFF_PAIR_FIRST_KILL_TIME",
	"PICKOFF_UNKNOWN_POWER_BONUS",
	"PICKOFF_UNKNOWN_KILL_TIME_PENALTY",
	"PICKOFF_MAX_UNKNOWN_ENEMIES",
	"PICKOFF_REINFORCEMENT_BUFFER",
	"PICKOFF_CACHED_DAMAGE_MARGIN",
	"PICKOFF_LAST_SEEN_MAX_AGE",
	"PICKOFF_TOTAL_TIMEOUT",
	"PICKOFF_ASSEMBLE_TIMEOUT",
	"PICKOFF_ASSEMBLE_TRAVEL_BUFFER",
	"PICKOFF_CONCEAL_TIMEOUT",
	"PICKOFF_APPROACH_TIMEOUT",
	"PICKOFF_AMBUSH_TIMEOUT",
	"PICKOFF_ENGAGE_TIMEOUT",
	"PICKOFF_ASSEMBLE_RADIUS",
	"PICKOFF_STAGING_DISTANCE",
	"PICKOFF_REVALIDATE_RADIUS",
	"PICKOFF_SAFE_CORE_KILL_TIME",
	"PICKOFF_SAFE_CORE_POWER_RATIO",
	"PICKOFF_SAFE_CORE_MAX_TRAVEL_TIME",
	"ROAM_TEAMFIGHT_START_TIME",
	"ROAM_TEAMFIGHT_RADIUS",
	"ROAM_TEAMFIGHT_MIN_ALLIES",
	"ROAM_TEAMFIGHT_MIN_ENEMIES",
	"ROAM_TEAMFIGHT_MIN_TOTAL_HEROES",
	"SMOKE_PATROL_COOLDOWN",
	"SMOKE_PATROL_MIN_EVIDENCE_AGE",
	"SMOKE_PATROL_MAX_EVIDENCE_AGE",
	"SMOKE_PATROL_PARTICIPANTS",
	"SMOKE_APPLICATION_RADIUS",
	"SMOKE_SAFE_ENEMY_RADIUS",
	"SMOKE_SAFE_TOWER_RADIUS",
	"SMOKE_PRECAST_STAGING_DISTANCE",
	"SMOKE_MIN_HEALTH",
	"SMOKE_MIN_MANA",
	"PICKOFF_VISIBLE_SMOKE_MIN_DISTANCE",
	"TWIN_GATE_SAFE_RADIUS",
	"TWIN_GATE_CAST_RANGE",
	"TWIN_GATE_CHANNEL_TIME_ESTIMATE",
	"TWIN_GATE_CAST_START_GRACE",
}

local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > 0
end

local function IsValidPositionRule(rule)
	return type(rule) == "table"
		and IsFiniteNumber(rule.minLevel)
		and IsFiniteNumber(rule.minHealth) and rule.minHealth <= 1
		and IsFiniteNumber(rule.minMana) and rule.minMana <= 1
		and type(rule.travelBias) == "number" and rule.travelBias == rule.travelBias
		and rule.travelBias >= 0
end

function RoamConfig.IsEnabled()
	if RoamConfig.ENABLED ~= true
		or type(RoamConfig.DEBUG) ~= "boolean"
		or type(RoamConfig.ANNOUNCE_CHAT) ~= "boolean"
		or type(RoamConfig.ENABLE_TWIN_GATE_ROUTE) ~= "boolean"
		or type(RoamConfig.BACKPACK_CAST_BRIDGE_ENABLED) ~= "boolean"
		or type(RoamConfig.SMOKE_ENABLED) ~= "boolean"
		or type(RoamConfig.CONSUMABLE_PURCHASE_ENABLED) ~= "boolean"
		or type(RoamConfig.INVISIBILITY_HEROES) ~= "table"
		or type(RoamConfig.INVISIBILITY_SELECTION_ALIASES) ~= "table"
		or type(RoamConfig.POSITION_RULES) ~= "table"
		or type(RoamConfig.PICKOFF_POSITION_RULES) ~= "table"
	then
		return false
	end
	for _, field in ipairs(REQUIRED_POSITIVE_NUMBERS) do
		if not IsFiniteNumber(RoamConfig[field]) then return false end
	end
	if RoamConfig.EARLY_ROAM_OUTNUMBER_TARGET_HEALTH > 1
		or RoamConfig.EARLY_ROAM_KILL_CONFIRM_HEALTH > RoamConfig.EARLY_ROAM_OUTNUMBER_TARGET_HEALTH
		or RoamConfig.EARLY_ROAM_MAX_ROAMERS > RoamConfig.MAX_ROAMERS
		or RoamConfig.OUTNUMBER_TARGET_SCORE_RELIEF >= RoamConfig.MIN_TARGET_SCORE
		or RoamConfig.HIGH_HEALTH_TARGET_FRACTION > 1
		or RoamConfig.HIGH_HEALTH_MIN_PARTICIPANTS > RoamConfig.MAX_ROAMERS
		or RoamConfig.ROAM_TEAMFIGHT_MIN_TOTAL_HEROES
			< RoamConfig.ROAM_TEAMFIGHT_MIN_ALLIES + RoamConfig.ROAM_TEAMFIGHT_MIN_ENEMIES
	then
		return false
	end
	return IsValidPositionRule(RoamConfig.POSITION_RULES.mid)
		and IsValidPositionRule(RoamConfig.POSITION_RULES.soft_support)
		and IsValidPositionRule(RoamConfig.POSITION_RULES.hard_support)
		and IsValidPositionRule(RoamConfig.PICKOFF_POSITION_RULES.mid)
		and IsValidPositionRule(RoamConfig.PICKOFF_POSITION_RULES.off_core)
		and IsValidPositionRule(RoamConfig.PICKOFF_POSITION_RULES.safe_core)
		and IsValidPositionRule(RoamConfig.PICKOFF_POSITION_RULES.soft_support)
		and IsValidPositionRule(RoamConfig.PICKOFF_POSITION_RULES.hard_support)
end

return RoamConfig
