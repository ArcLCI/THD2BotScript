# Bot 库目录

这里按职责组织共享 Lua 库。Dota 要求的 `mode_*_generic.lua`、`ability_item_usage_*.lua` 等入口仍放在脚本根目录。

```text
THDFuncLib/
├── modes/
│   ├── push/       推线、护线、建筑接近与塔伤策略
│   ├── defend/     守线与回防
│   ├── roam/       游走、Gank、辅助任务路由
│   ├── retreat/    撤退判断与逃生能力资料
│   ├── laning/     分路分配、基础兵线与局部后备任务
│   ├── evasive/    技能避让、路径几何、高地退出与诊断
│   └── shared/     执行契约、战略、模式诊断与共享塔区观察
├── heroes/
│   ├── flandre/
│   ├── kasen/
│   ├── nitori/
│   ├── sagume/
│   ├── sunny/
│   ├── tei/
│   ├── yumemi/
│   └── yuuka/
└── 通用基础库
```

## 通用基础库

根目录保留 `thd_func.lua`、`utils.lua`、`action_intent.lua`、`combat_power.lua`、`consumable_inventory.lua`、`bot_profile.lua`、`bot_diagnostics_config.lua`、`aba_site.lua` 和 `thd_ward_util.lua`。这些库提供多个模式和英雄共用的基础能力，不归属于单个模式或英雄。

`modes/shared` 也是公共依赖，但其职责是模式执行与策略。英雄脚本可以引用它，不需要复制一份到英雄目录。

## 英雄归属

英雄目录采用游戏侧 `scripts/npc/heroes/<名称>/` 的标识。原版英雄槽位只用于查找 Bot 入口，不决定库的行为归属。

| 目录 | 游戏英雄标识 | Bot 槽位 |
|---|---|---|
| `flandre` | `npc_dota_hero_flandre` | `naga_siren` |
| `kasen` | `npc_dota_hero_kasen` | `bristleback` |
| `nitori` | `npc_dota_hero_nitori` | `spectre` |
| `sagume` | `npc_dota_hero_sagume` | `queenofpain` |
| `sunny` | `npc_dota_hero_sunny` | `rattletrap` |
| `tei` | `npc_dota_hero_tei` | `gyrocopter` |
| `yumemi` | `npc_dota_hero_yumemi` | `tinker` |
| `yuuka` | `npc_dota_hero_yuuka` | `venomancer` |

## 引用约定

保留原文件名与导出接口，只更新目录路径。例如：

```lua
local Tasks = require(GetScriptDirectory() .. '/THDFuncLib/modes/shared/mode_task')
local Push = require(GetScriptDirectory() .. '/THDFuncLib/modes/push/aba_push')
local Kasen = require(GetScriptDirectory() .. '/THDFuncLib/heroes/kasen/kasen_state')
```

新增模式专属实现放入对应模式目录；新增英雄专属实现放入游戏英雄标识对应的目录。不要把同一个有状态模块同时保留在新旧路径，以免产生两份模块状态。

历史验收文档中的旧路径代表当时的代码位置。项目不维护或运行自动化测试；历史测试文件未随本次目录迁移改写。
