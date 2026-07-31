local Records = {}

Records.CATEGORY = {
	MOBILITY = 'MOBILITY',
	SURVIVAL = 'SURVIVAL',
	HARD_CONTROL = 'HARD_CONTROL',
	STRONG_SLOW = 'STRONG_SLOW',
	DISPLACEMENT = 'DISPLACEMENT',
	SOFT_CONTROL = 'SOFT_CONTROL',
	COUNTERPRESSURE = 'COUNTERPRESSURE',
	ALLY_SAVE = 'ALLY_SAVE',
	SETUP = 'SETUP',
	EXCLUDED = 'EXCLUDED',
}

Records.USE_STATUS = {
	CAST = 'CAST',
	ALLY_RETREAT_CAST = 'ALLY_RETREAT_CAST',
	SEQUENCE_COMPONENT = 'SEQUENCE_COMPONENT',
	SUPPRESSED = 'SUPPRESSED',
	COMMENTED_OUT = 'COMMENTED_OUT',
}

Records.CONTROL_STATUS = {
	ENABLED = 'ENABLED',
	CANDIDATE = 'CANDIDATE',
	CONDITIONAL = 'CONDITIONAL',
	REJECTED = 'REJECTED',
	NOT_CONTROL = 'NOT_CONTROL',
}

local C = Records.CATEGORY
local U = Records.USE_STATUS
local Q = Records.CONTROL_STATUS
local abilities = {}

local function Add(name, category, script, useStatus, controlStatus, note, options)
	options = options or {}
	local frameworkPolicy = options.frameworkPolicy
	if frameworkPolicy == nil then
		if useStatus == U.SEQUENCE_COMPONENT then
			frameworkPolicy = 'PARENT_SEQUENCE'
		elseif useStatus == U.SUPPRESSED then
			frameworkPolicy = 'SUPPRESS_ON_HIGH'
		elseif useStatus == U.COMMENTED_OUT then
			frameworkPolicy = 'NONE'
		else
			frameworkPolicy = 'CRITICAL_OR_LEGACY_EMERGENCY'
		end
	end
	abilities[name] = {
		name = name,
		category = category,
		script = script,
		functionName = options.functionName,
		useStatus = useStatus or U.CAST,
		controlStatus = controlStatus or Q.NOT_CONTROL,
		frameworkPolicy = frameworkPolicy,
		note = note,
		tags = options.tags,
		control = options.control,
	}
end

-- 这里记录“现有脚本在撤退条件下会做什么”，不代表技能已经获准降低撤退危险。
-- 控制登记还必须通过前摇、引导、命中延迟、组合条件和现有动作路径审查。

-- Ellen
Add('ability_thdots_ellen02', C.DISPLACEMENT, 'ability_item_usage_arc_warden.lua', U.CAST, Q.CONDITIONAL,
	'在自身周围生成推开敌人的光粒；需要敌人接近光粒才触发。')
Add('ability_thdots_ellen03', C.SOFT_CONTROL, 'ability_item_usage_arc_warden.lua', U.CAST, Q.CONDITIONAL,
	'第一段为沉默光波，击退依赖后续 Vacant Pulse，不能按一次施法直接计算硬控。')
Add('ability_thdots_ellen04', C.COUNTERPRESSURE, 'ability_item_usage_arc_warden.lua', U.CAST, Q.NOT_CONTROL,
	'直线伤害并延迟叠层爆发，不直接迟滞追兵。')

-- Cirno
Add('ability_thdots_cirno01', C.STRONG_SLOW, 'ability_item_usage_axe.lua', U.CAST, Q.ENABLED,
	'现有公共追兵选择已接入；50% 减速持续 3 秒，前摇 0.2 秒。', {
	control = { type = 'SLOW', slow = 0.50, duration = 3.0, range = 400, castPoint = 0.20, maxCommitTime = 0.35 },
})
Add('ability_thdots_cirno04', C.HARD_CONTROL, 'ability_item_usage_axe.lua', U.CAST, Q.REJECTED,
	'能眩晕敌人，但同时眩晕自身，不能视为保持撤退移动的安全迟滞。')

-- Seija / Momiji / Yugi
Add('ability_thdots_seija04', C.DISPLACEMENT, 'ability_item_usage_batrider.lua', U.CAST, Q.CONDITIONAL,
	'围绕中心对称旋转单位，结果依赖目标阵营、视角状态和几何位置。')
Add('ability_thdots_momiji03', C.HARD_CONTROL, 'ability_item_usage_bounty_hunter.lua', U.CAST, Q.CANDIDATE,
	'近身盾击眩晕，现有紧急撤退分支可施放。', {
	control = { type = 'HARD', duration = 2.0, range = 150, castPoint = 0.10, maxCommitTime = 0.35, minimumSeverity = 'CRITICAL' },
})
Add('ability_thdots_momiji04', C.MOBILITY, 'ability_item_usage_bounty_hunter.lua', U.CAST, Q.NOT_CONTROL,
	'万宝槌主动效果提高自身及队伍移动能力。')
Add('centaur_hoof_stomp', C.HARD_CONTROL, 'ability_item_usage_centaur.lua', U.CAST, Q.CANDIDATE,
	'勇仪二技能的近身范围眩晕；跳跃组合路径需与直接施法分开评估。', {
	control = { type = 'HARD', duration = 1.2, range = 315, castPoint = 0, maxCommitTime = 0.20 },
})
Add('ability_thdots_yugi04', C.COUNTERPRESSURE, 'ability_item_usage_centaur.lua', U.CAST, Q.CONDITIONAL,
	'三步必杀以移动触发斩杀或纯粹伤害，是移动威慑而非已生效定身。')

-- Mokou / Marisa
Add('ability_thdots_mokou03', C.SURVIVAL, 'ability_item_usage_chaos_knight.lua', U.CAST, Q.NOT_CONTROL,
	'低生命撤退时进入凤凰蛋式生存窗口。')
Add('ability_thdots_mokou04', C.SURVIVAL, 'ability_item_usage_chaos_knight.lua', U.CAST, Q.NOT_CONTROL,
	'提供持续恢复和移动速度。')
Add('ability_thdots_marisa01', C.MOBILITY, 'ability_item_usage_crystal_maiden.lua', U.CAST, Q.NOT_CONTROL,
	'向目标位置高速冲刺。')
Add('ability_thdots_marisa02', C.COUNTERPRESSURE, 'ability_item_usage_crystal_maiden.lua', U.CAST, Q.NOT_CONTROL,
	'扇形持续输出，存在持续施法时间且不提供迟滞。')
Add('ability_thdots_marisa03', C.COUNTERPRESSURE, 'ability_item_usage_crystal_maiden.lua', U.CAST, Q.NOT_CONTROL,
	'生成自动攻击附近目标的环绕光球。')
Add('ability_thdots_marisa04', C.COUNTERPRESSURE, 'ability_item_usage_crystal_maiden.lua', U.CAST, Q.NOT_CONTROL,
	'Master Spark 为长前摇/持续施法输出，撤退控制不得复用。')

-- Byakuren / Larva
Add('ability_thdots_byakuren01', C.HARD_CONTROL, 'ability_item_usage_dark_seer.lua', U.CAST, Q.CANDIDATE,
	'近身目标眩晕，现有撤退分支可施放。', {
	control = { type = 'HARD', duration = 1.2, range = 150, castPoint = 0.20, maxCommitTime = 0.35 },
})
Add('ability_thdots_byakuren02', C.COUNTERPRESSURE, 'ability_item_usage_dark_seer.lua', U.CAST, Q.NOT_CONTROL,
	'消耗当前法力造成伤害，不提供控制。')
Add('ability_thdots_byakuren03', C.ALLY_SAVE, 'ability_item_usage_dark_seer.lua', U.ALLY_RETREAT_CAST, Q.NOT_CONTROL,
	'把正在撤退的友方拉回白莲身边并驱散；当前分支不是白莲自身逃生。')
Add('ability_thdots_byakuren05', C.COUNTERPRESSURE, 'ability_item_usage_dark_seer.lua', U.CAST, Q.NOT_CONTROL,
	'脚本函数名为 Byakuren04，但实际施放的是削减魔抗的 ability_thdots_byakuren05。')
Add('ability_thdots_larva01_1', C.MOBILITY, 'ability_item_usage_dark_willow.lua', U.CAST, Q.NOT_CONTROL,
	'往返飞行技能；路径可能暂时远离追兵，但并非单向安全位移。')
Add('ability_thdots_larva02', C.STRONG_SLOW, 'ability_item_usage_dark_willow.lua', U.CAST, Q.CONDITIONAL,
	'范围减速仅在数值达到 30% 的等级才满足强减速门槛。')
Add('ability_thdots_larva04', C.HARD_CONTROL, 'ability_item_usage_dark_willow.lua', U.CAST, Q.CONDITIONAL,
	'梦境控制会受逃离距离、受伤唤醒等额外条件影响，需单独建模。')

-- Miko / Tojiko / Clown / Meirin
Add('ability_thdots_miko01', C.MOBILITY, 'ability_item_usage_dawnbreaker.lua', U.CAST, Q.CONDITIONAL,
	'消失一秒后落到目标点并范围眩晕；位移和短暂无敌有效，但控制生效有延迟。')
Add('ability_thdots_miko02', C.MOBILITY, 'ability_item_usage_dawnbreaker.lua', U.CAST, Q.NOT_CONTROL,
	'撤退时开启技能增强和移动速度光环。')
Add('ability_thdots_tojiko04', C.COUNTERPRESSURE, 'ability_item_usage_disruptor.lua', U.CAST, Q.NOT_CONTROL,
	'延迟落雷造成高额伤害，不提供迟滞。')
Add('ability_thdots_clown02', C.HARD_CONTROL, 'ability_item_usage_doom_bringer.lua', U.CAST, Q.CONDITIONAL,
	'只有敌方冲出火圈并满足位移距离条件才眩晕，不能预先当作确定硬控。')
Add('ability_thdots_meirin01', C.MOBILITY, 'ability_item_usage_dragon_knight.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时向安全方向移动。')
Add('ability_thdots_meirin02', C.SURVIVAL, 'ability_item_usage_dragon_knight.lua', U.CAST, Q.NOT_CONTROL,
	'持续驱散并提供 30% 减伤，低于高额减伤的 60% 门槛。')

-- Koishi / Tenshi / Merlin / Komachi
Add('phantom_assassin_blur', C.SURVIVAL, 'ability_item_usage_drow_ranger.lua', U.CAST, Q.NOT_CONTROL,
	'恋的 EX 隐匿/闪避生存技能。')
Add('ability_thdots_koishi04', C.MOBILITY, 'ability_item_usage_drow_ranger.lua', U.CAST, Q.NOT_CONTROL,
	'提高移动速度和战斗能力，但施法前摇约 1 秒，不适合作为紧急控制。')
Add('earthshaker_fissure', C.HARD_CONTROL, 'ability_item_usage_earthshaker.lua', U.CAST, Q.CANDIDATE,
	'天子一技能同时提供眩晕和地形阻挡；需要检查沟壑方向不会封住自身退路。', {
	control = { type = 'HARD', duration = 1.0, range = 1400, castPoint = 0.30, maxCommitTime = 0.45 },
})
Add('ability_thdots_Merlin01', C.HARD_CONTROL, 'ability_item_usage_earth_spirit.lua', U.CAST, Q.CANDIDATE,
	'嘲讽持续 1.5 至 3 秒；地图侧标识符含大写 M。', {
	control = { type = 'HARD', duration = 1.5, range = 250, castPoint = 0.20, maxCommitTime = 0.35 },
})
Add('ability_thdots_Merlin04', C.COUNTERPRESSURE, 'ability_item_usage_earth_spirit.lua', U.CAST, Q.NOT_CONTROL,
	'伤害反射/联结效果，不限制目标移动；地图侧标识符含大写 M。')
Add('ability_thdots_komachi01', C.MOBILITY, 'ability_item_usage_elder_titan.lua', U.CAST, Q.REJECTED,
	'向前瞬移并挥镰；附带 0.3 秒小控制低于 0.6 秒门槛。')
Add('ability_thdots_komachi03', C.COUNTERPRESSURE, 'ability_item_usage_elder_titan.lua', U.CAST, Q.NOT_CONTROL,
	'引爆已有恶灵造成伤害，不提供迟滞。')

-- Youmu2 / Seiga / Minoriko
Add('ability_thdots_youmu2_01', C.MOBILITY, 'ability_item_usage_enchantress.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时向安全方向突进。')
Add('ability_thdots_seigaEx', C.MOBILITY, 'ability_item_usage_grimstroke.lua', U.CAST, Q.NOT_CONTROL,
	'创建一对虫洞；真正脱离仍依赖 Bot 接近入口，不能按施法瞬间完成位移。')
Add('ability_thdots_minoriko02', C.SURVIVAL, 'ability_item_usage_huskar.lua', U.CAST, Q.NOT_CONTROL,
	'放置持续回复生命和法力的番薯车。')

-- Patchouli：合成技能本身与五个元素输入分别登记，避免把输入动作误算为控制。
Add('ability_thdots_patchouli_fire_fire', C.COUNTERPRESSURE, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'撤退单技能状态机可召唤火元素。')
Add('ability_thdots_patchouli_fire_water', C.COUNTERPRESSURE, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'目标持续伤害。')
Add('ability_thdots_patchouli_fire_wood', C.COUNTERPRESSURE, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'延迟范围伤害。')
Add('ability_thdots_patchouli_fire_metal', C.COUNTERPRESSURE, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'燃烧敌方法力并造成伤害。')
Add('ability_thdots_patchouli_fire_earth', C.SOFT_CONTROL, 'ability_item_usage_invoker.lua', U.CAST, Q.CONDITIONAL,
	'生成环状熔岩地形；需要验证落点不会同时困住撤退 Bot。')
Add('ability_thdots_patchouli_water_water', C.SOFT_CONTROL, 'ability_item_usage_invoker.lua', U.CAST, Q.CONDITIONAL,
	'范围沉默和减速；只有高水元素等级才达到 30% 强减速门槛。')
Add('ability_thdots_patchouli_water_metal', C.COUNTERPRESSURE, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'范围持续伤害和魔抗削减。')
Add('ability_thdots_patchouli_water_earth', C.DISPLACEMENT, 'ability_item_usage_invoker.lua', U.CAST, Q.CONDITIONAL,
	'大洪水击退并在击退期间缠绕、沉默和缴械；需按弹道命中时间评估。')
Add('ability_thdots_patchouli_wood_wood', C.MOBILITY, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时优先尝试的自身移动速度增益。')
Add('ability_thdots_patchouli_wood_metal', C.SURVIVAL, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'命中敌人或树木后按伤害回复生命，收益依赖弹道命中。')
Add('ability_thdots_patchouli_wood_earth', C.HARD_CONTROL, 'ability_item_usage_invoker.lua', U.CAST, Q.CONDITIONAL,
	'目标缠绕，基础 0.7 秒并随土元素等级增加。')
Add('ability_thdots_patchouli_metal_metal', C.COUNTERPRESSURE, 'ability_item_usage_invoker.lua', U.CAST, Q.NOT_CONTROL,
	'目标移动时减甲并受伤，是移动惩罚而非定身。')
Add('ability_thdots_patchouli_metal_earth', C.DISPLACEMENT, 'ability_item_usage_invoker.lua', U.CAST, Q.CONDITIONAL,
	'巨石持续吸引敌人，控制强度和到达时机依赖落点。')
Add('ability_thdots_patchouli_earth_earth', C.HARD_CONTROL, 'ability_item_usage_invoker.lua', U.CAST, Q.REJECTED,
	'一秒延迟后眩晕，紧急迟滞的生效延迟过长。')
for _, elementName in ipairs({
	'ability_thdots_patchouli_fire',
	'ability_thdots_patchouli_water',
	'ability_thdots_patchouli_wood',
	'ability_thdots_patchouli_metal',
	'ability_thdots_patchouli_earth',
}) do
	Add(elementName, C.SETUP, 'ability_item_usage_invoker.lua', U.SEQUENCE_COMPONENT, Q.NOT_CONTROL,
		'合成技能或严重撤退双土姿态的元素输入，不直接产生迟滞。')
end

-- Youmu / Rumia / Reimu
Add('ability_thdots_youmu01', C.MOBILITY, 'ability_item_usage_juggernaut.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时向安全方向高速移动。')
Add('ability_thdots_youmu04', C.COUNTERPRESSURE, 'ability_item_usage_juggernaut.lua', U.CAST, Q.NOT_CONTROL,
	'低生命时尝试高伤害斩击，属于反打而非逃生控制。')
Add('ability_thdots_rumia01', C.SURVIVAL, 'ability_item_usage_life_stealer.lua', U.CAST, Q.NOT_CONTROL,
	'获得黑暗隐匿、百分比回复和 25% 闪避。')
Add('ability_dota2x_reimu01', C.COUNTERPRESSURE, 'ability_item_usage_lina.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时向追击者位置输出。')
Add('ability_dota2x_reimu02', C.COUNTERPRESSURE, 'ability_item_usage_lina.lua', U.CAST, Q.NOT_CONTROL,
	'发射自动追踪灵弹，不直接迟滞。')
Add('ability_dota2x_reimu03', C.SURVIVAL, 'ability_item_usage_lina.lua', U.CAST, Q.NOT_CONTROL,
	'撤退分支优先给自身/友方施加物理免疫结界；敌方用法才是封锁施法。')
Add('ability_dota2x_reimu04', C.SURVIVAL, 'ability_item_usage_lina.lua', U.CAST, Q.NOT_CONTROL,
	'无目标防护/领域技能，包含魔法免疫窗口。')

-- Shizuha / Shou / Jyoon / Reisen
Add('ability_thdots_shizuha01', C.COUNTERPRESSURE, 'ability_item_usage_lone_druid.lua', U.CAST, Q.NOT_CONTROL,
	'对最近伤害来源施加伤害和恢复抑制，不限制移动。')
Add('ability_thdots_shizuhaEXNew', C.SOFT_CONTROL, 'ability_item_usage_lone_druid.lua', U.CAST, Q.CONDITIONAL,
	'万宝槌主动造树林阻挡道路并给自身加速；地形落点需验证。')
Add('ability_thdots_shizuha02', C.EXCLUDED, 'ability_item_usage_lone_druid.lua', U.SUPPRESSED, Q.NOT_CONTROL,
	'长时间引导回复；高欲望撤退分支明确返回 NONE，不会施放。')
Add('ability_thdots_shou01', C.SURVIVAL, 'ability_item_usage_mars.lua', U.CAST, Q.NOT_CONTROL,
	'先提高护甲和魔抗，首次攻击才可能按剩余时间附带眩晕。')
Add('ability_thdots_Jyoon_2', C.STRONG_SLOW,
	{'ability_item_usage_meepo.lua', 'ability_item_usage_tusk.lua'}, U.CAST, Q.CONDITIONAL,
	'必定减速并随机附加眩晕、沉默、缠绕、恐惧或缴械；减速需达到 30% 等级门槛。')
Add('ability_thdots_Jyoon_3', C.MOBILITY,
	{'ability_item_usage_meepo.lua', 'ability_item_usage_tusk.lua'}, U.CAST, Q.NOT_CONTROL,
	'标记附近敌人后提高移动速度和状态抗性。')
Add('ability_thdots_reisenOld04', C.SURVIVAL, 'ability_item_usage_mirana.lua', U.CAST, Q.NOT_CONTROL,
	'迅速隐身并获得相位移动，随后强化攻击。')

-- Flandre / Mystia / Daiyousei / Suwako
Add('naga_siren_mirror_image', C.SURVIVAL, 'ability_item_usage_naga_siren.lua', U.CAST, Q.NOT_CONTROL,
	'受击撤退时利用短暂无敌和分身混淆。')
Add('ability_thdots_flandre04', C.MOBILITY, 'ability_item_usage_naga_siren.lua', U.CAST, Q.NOT_CONTROL,
	'回收分身并获得随低生命增强的移速，兼有反打暴击。')
Add('ability_thdots_mystia04', C.STRONG_SLOW, 'ability_item_usage_night_stalker.lua', U.CAST, Q.CANDIDATE,
	'周围敌人受到显著移速/攻速降低；无需目标且不打断撤退方向。', {
	control = { type = 'SLOW', slow = 0.50, duration = 3.0, range = 800, castPoint = 0.30, maxCommitTime = 0.45 },
})
Add('ability_thdots_mystiaex', C.MOBILITY, 'ability_item_usage_night_stalker.lua', U.CAST, Q.NOT_CONTROL,
	'获得飞行移动能力；地图侧标识符为全小写 ex。')
Add('ability_thdots_daiyousei01', C.MOBILITY, 'ability_item_usage_nyx_assassin.lua', U.CAST, Q.NOT_CONTROL,
	'闪烁到更接近泉水的友军或树木并治疗。')
Add('ability_thdots_suwako01', C.HARD_CONTROL, 'ability_item_usage_ogre_magi.lua', U.CAST, Q.CANDIDATE,
	'近身范围缠绕并缴械，持续时间达到通用硬控门槛。', {
	control = { type = 'HARD', duration = 1.1, range = 450, castPoint = 0.25, maxCommitTime = 0.40 },
})
Add('ability_thdots_suwako02', C.SURVIVAL, 'ability_item_usage_ogre_magi.lua', U.CAST, Q.NOT_CONTROL,
	'钻地后不可被攻击并获得移速，代价是自身缴械、沉默和锁闭。')
Add('ability_thdots_suwako04new', C.HARD_CONTROL, 'ability_item_usage_ogre_magi.lua', U.CAST, Q.CANDIDATE,
	'对视野内敌人造成击飞和眩晕。', {
	control = { type = 'HARD', duration = 1.5, range = 800, castPoint = 0.30, maxCommitTime = 0.45 },
})

-- Kisume / Reisen2 / Sagume / Iku
Add('ability_thdots_kisume02', C.MOBILITY, 'ability_item_usage_omniknight.lua', U.CAST, Q.NOT_CONTROL,
	'低生命撤退时向安全地点降落，过程包含不可选/无敌状态。')
Add('ability_thdots_kisume04', C.COUNTERPRESSURE, 'ability_item_usage_omniknight.lua', U.CAST, Q.NOT_CONTROL,
	'极低生命时以生命上限代价发动范围爆发，不提供迟滞。')
Add('ability_thdots_reisen_2_01', C.MOBILITY, 'ability_item_usage_phantom_lancer.lua', U.CAST, Q.REJECTED,
	'撤退分支对自身施放取得冲锋速度；虽然攻击目标可被强减速，现有撤退路径没有选择敌人。')
Add('ability_thdots_sagume_2', C.MOBILITY, 'ability_item_usage_queenofpain.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时闪烁至安全方向。')
Add('ability_thdots_iku01', C.MOBILITY, 'ability_item_usage_razor.lua', U.CAST, Q.NOT_CONTROL,
	'撤退时按敌人距离切换持续耗蓝的移动速度状态。')
Add('ability_thdots_iku02', C.SURVIVAL, 'ability_item_usage_razor.lua', U.CAST, Q.CONDITIONAL,
	'提高护甲魔抗并击退靠近者，但基础移速被降至 220，需比较当前速度后使用。')
Add('ability_thdots_ikuEx', C.HARD_CONTROL, 'ability_item_usage_razor.lua', U.CAST, Q.REJECTED,
	'落雷有约 1.7 秒延迟，不能作为即时追兵迟滞。')

-- Aya / Shikieiki / Sakuya / Yumemi
Add('ability_thdots_aya01', C.MOBILITY, 'ability_item_usage_slark.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时向安全方向高速移动。')
Add('ability_thdots_aya04', C.MOBILITY, 'ability_item_usage_slark.lua', U.CAST, Q.NOT_CONTROL,
	'持续多段高速位移。')
Add('aya_fantasy', C.SURVIVAL, 'ability_item_usage_slark.lua', U.CAST, Q.NOT_CONTROL,
	'统一撤退框架请求的防御施法；100% 闪避、80% 伤害降低和移动窗口。')
Add('ability_thdots_shikieiki02', C.HARD_CONTROL, 'ability_item_usage_storm_spirit.lua', U.CAST, Q.CONDITIONAL,
	'延迟审判后眩晕，时长随罪名增加；需把 delay_action 纳入命中时间。')
Add('ability_thdots_shikieiki04', C.SOFT_CONTROL, 'ability_item_usage_storm_spirit.lua', U.CAST, Q.REJECTED,
	'禁用主动技能和物品但不限制移动，不能单独视为追兵迟滞。')
Add('ability_thdots_sakuya03', C.MOBILITY, 'ability_item_usage_templar_assassin.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时向安全方向突围并闪现。')
Add('ability_thdots_yumemi02', C.MOBILITY, 'ability_item_usage_tinker.lua', U.CAST, Q.NOT_CONTROL,
	'驾驶空间船飞向安全地点，飞行持续耗蓝。')
Add('ability_thdots_yumemi03', C.STRONG_SLOW, 'ability_item_usage_tinker.lua', U.CAST, Q.REJECTED,
	'分身一秒后才爆炸并施加 100% 减速，紧急迟滞的生效延迟过长。')
Add('ability_thdots_yumemi04', C.EXCLUDED, 'ability_item_usage_tinker.lua', U.COMMENTED_OUT, Q.NOT_CONTROL,
	'撤退判断位于块注释内，不属于当前运行路径。')

-- Nazrin / Hatate / Yuuka / Medicine / Lyrica
Add('ability_thdotsr_Nazrin01', C.SURVIVAL, 'ability_item_usage_ursa.lua', U.CAST, Q.CONDITIONAL,
	'获得恢复并推开近身单位；推开是近身触发，主要按生存技能记录。')
Add('ability_thdots_hatate01', C.MOBILITY, 'ability_item_usage_vengefulspirit.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时高速移动到安全点。')
Add('ability_thdots_hatateEx', C.SURVIVAL, 'ability_item_usage_vengefulspirit.lua', U.CAST, Q.NOT_CONTROL,
	'传送回家需要约 2 秒施法，必须保护完整施法阶段，不能当即时控制。')
Add('ability_thdots_YuukaEx2', C.MOBILITY, 'ability_item_usage_venomancer.lua', U.CAST, Q.NOT_CONTROL,
	'严重撤退时瞬移到更接近泉水的向日葵。')
Add('ability_thdots_medicine04', C.HARD_CONTROL, 'ability_item_usage_viper.lua', U.CAST, Q.CONDITIONAL,
	'使追兵转而攻击友军且暂时无法被我方攻击；万宝槌会额外延迟 2.5 秒，必须分支建模。')
Add('ability_thdots_lyrica01', C.MOBILITY, 'ability_item_usage_weaver.lua', U.CAST, Q.NOT_CONTROL,
	'浮现到安全目标点并治疗周围友军。')

function Records.Get(abilityName)
	return abilities[abilityName]
end

function Records.GetAll()
	return abilities
end

function Records.GetStatistics()
	local result = {
		total = 0,
		active = 0,
		excluded = 0,
		sequenceComponents = 0,
		byCategory = {},
		byControlStatus = {},
	}
	for _, record in pairs(abilities) do
		result.total = result.total + 1
		result.byCategory[record.category] = (result.byCategory[record.category] or 0) + 1
		result.byControlStatus[record.controlStatus] = (result.byControlStatus[record.controlStatus] or 0) + 1
		if record.useStatus == U.SUPPRESSED or record.useStatus == U.COMMENTED_OUT then
			result.excluded = result.excluded + 1
		elseif record.useStatus == U.SEQUENCE_COMPONENT then
			result.sequenceComponents = result.sequenceComponents + 1
		else
			result.active = result.active + 1
		end
	end
	return result
end

return Records
