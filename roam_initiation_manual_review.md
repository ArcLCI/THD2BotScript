# Roam 先手控制人工审核清单

状态：待人工审核。本文件中的技能只记录候选控制效果，不参与 `THDFuncLib/roam_initiation.lua` 的运行时登记。

## 本次已登记

当前先手登记已经覆盖以下七种动作：

- `npc_dota_hero_yuuka` / `ability_thdots_yuuka02`：敌方单位目标眩晕。
- `npc_dota_hero_kisume` / `ability_thdots_kisume01`：点目标投射物范围眩晕。
- `npc_dota_hero_sunny` / `ability_thdots_sunny02`：无目标近身范围眩晕。
- `npc_dota_hero_Byakuren` / `ability_thdots_byakuren01`：敌方单位目标硬控制。
- `npc_dota_hero_merlin` / `ability_thdots_Merlin01`：敌方单位目标硬控制。
- `npc_dota_hero_Yugi` / `centaur_hoof_stomp`：无目标近身眩晕，支持跳刀接踩和移动接近后直接踩。
- `npc_dota_hero_suwako` / `ability_thdots_suwako01`：无目标范围 Root/Disarm。

天子和秋穰子的既有登记不在本清单中重复记录。

## 暂不直接登记的控制效果

| 英雄 | 技能 | 控制效果 / 形态 | 暂缓原因 | 人工审核重点 |
| --- | --- | --- | --- | --- |
| Tojiko | `ability_thdots_tojiko01` | 直线范围眩晕 | 当前 Bot 有技能 03 可用时的组合门控；需要方向和终点计算 | 是否允许先手覆盖技能 03 组合顺序 |
| Shikieiki | `ability_thdots_shikieiki02` | 单位目标基础眩晕，可由控罪层数增强 | 当前决策依赖控罪层数、伤害和击杀条件 | 是否允许无控罪层数时作为稳定先手 |
| Cirno | `ability_thdots_cirno01` | 50% 强减速，持续约 3 秒 | 属于软控制，不属于当前硬控登记口径；还与二技能队列有组合关系 | 是否建立独立的 soft opener 登记 |
| Sanae | `ability_thdots_sanae01` | 40% 减速，持续约 1 秒 | 控制强度较低，先手收益不稳定 | 是否把短减速视为有效先手 |
| Mystia | `ability_thdots_mystia04` | 范围强减速 | 大招、范围控制，普通 gank 中资源成本较高 | 是否允许消耗大招启动普通游走 |
| Hina | `ability_thdots_hina04` | 持续施法 / 拉扯 / 终止眩晕 | 需要完整 channel 生命周期保护，不能只登记一次施法 | 是否单独建立 channel initiation 模式 |
| Suwako | `ability_thdots_suwako04new` | 范围眩晕 / 击退大招 | 高冷却大招，不适合作为普通 gank 默认起手 | 是否只允许团队战或明确击杀任务使用 |
| Larva | `ability_thdots_larva04` | 条件性范围控制 | 控制触发依赖额外状态和距离模型，不能保证第一次接触就控住 | 是否补充状态机和逃生距离模型 |
| Clown | `ability_thdots_clown02` | 单位目标控制 | 目标队伍为 BOTH，存在误选友军或非任务目标风险 | 是否补充敌我目标过滤 |
| Kagerou | `ability_thdots_kagerou03` | 概率性控制 | 控制触发概率低，不适合作为确定性的先手信号 | 是否接受概率控制作为先手 |
| Yasaka | `ability_thdots_yasaka01` | 点目标范围眩晕 | 当前没有可靠的对应 Bot 技能决策入口 | 先补 Bot 入口，再评估登记 |
| Yukari | `ability_thdots_yukari01` | 点目标范围眩晕 | 当前没有可靠的对应 Bot 技能决策入口 | 先补 Bot 入口，再评估登记 |
| Chen | `ability_thdots_chen01` | 点目标范围眩晕 | 当前没有对应的主动 Bot 施法路径 | 确认 Terrorblade 槽位映射后的脚本归属 |
| Kasen | `ability_thdots_kasen02` | 单位目标击退 / 眩晕 / 减速 | 当前没有对应的主动 Bot 施法路径 | 确认 Bristleback 槽位映射后的脚本归属 |
| Kokoro | `ability_thdots_kokoro03` | 单位目标击退 / 眩晕 | 当前没有对应的主动 Bot 施法路径，且技能不是一技能 | 是否允许非一技能承担通用先手 |
| Toyohime | `ability_thdots_toyohime02` | 点目标范围眩晕 | 当前 Oracle 槽位脚本没有命中 Toyohime 技能 ID | 先修复 Bot 技能 ID 映射 |
| Minamitsu | `ability_thdots_minamitsu01` | 点目标范围控制 | 目标队伍为 BOTH，且当前没有对应的 Bot 施法路径 | 补敌我过滤和主动施法入口 |

## 人工审核通过后的接入条件

将候选移入运行时登记前，至少确认以下事项：

1. 技能能在普通 gank 中稳定完成第一次控制，而不是依赖大招、随机概率或额外层数。
2. Bot 脚本能锁定 roam mission 的指定目标，不会从附近单位重新挑选目标。
3. 点目标、单位目标和无目标技能分别有正确的动作提交方式。
4. 施法队列、持续施法、组合技能和主动道具不会覆盖先手动作。
5. 技能不可用、目标消失或超时后，roam 能安全回退到默认集火逻辑。
