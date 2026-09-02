# THD Bot 危险区域避让：阶段化开发与验收计划

## 1. 文档状态

| 项目 | 当前值 |
| --- | --- |
| 文档用途 | 作为后续危险区域识别、原生路径验证、Bot 移动集成和实机验收的唯一阶段清单 |
| 目标环境 | Dota 2 7.38，本机安装目录 `D:\DOTA Latest\dota 2 beta` |
| 目标仓库 | `THD2BotScript` |
| 当前总体状态 | P0–P7 实机通过；P8-19AS 清线入口修复有效、局部交接补步守界，但仍有 1 次路径重入、5 条独立游戏侧 Lua 错误，部分保护/预算分支未覆盖；P8 实机未通过，不解锁 P9 |
| 当前运行与下一步 | `20260902-P8-01R-20TG-10B` 已静态通过并同步双镜像，待用户完全重启后的十 Bot 新局：30 秒塔几何记忆与 1 秒活动危险分离，完整集合构造/校验路径；另修游戏侧 GetCastRange 的 caster。详见 [20TG 部署说明](docs/P8_20TG_DEPLOYMENT.md) |
| 生产策略 | 永久禁止 `GetAvoidanceZones()`；由 Lua 自建危险区域注册表 |
| 原生路径策略 | `AddAvoidanceZone()`、`RemoveAvoidanceZone()`、`GeneratePath()`、`Action_MovePath()` 必须逐项验证后才能启用 |
| 回退策略 | 任一原生路径接口不稳定时，保留 Lua 危险注册表，退回 Lua 几何避让和普通移动 |

状态枚举统一使用：

- `未开始`：尚未修改或验证。
- `开发中`：已有实现，但当前阶段尚未完成全部静态门禁。
- `静态通过`：语法、引用扫描和 diff 已通过，但未完成 Dota 实机验证。
- `实机通过`：在完全重启的全新 Dota 对局中完成指定场景，且没有新 dump。
- `阻塞`：当前阶段失败或前置阶段未通过，后续阶段不得开始。
- `不适用`：上游原生能力已被明确禁用，该阶段由既定 Lua 降级路线取代。

任何后续开发都应先更新第 7 节进度总表，再开始下一阶段。

## 2. 结论和范围

### 2.1 已确认结论

不依赖 `GetAvoidanceZones()` 实现危险区域避让在架构上可行，但必须拆成两个独立系统：

1. Bot 脚本通过其他可见信息自行识别危险，维护自己的中心、半径、持续时间和危险等级。
2. 在原生路径 API 验证安全后，将脚本已知区域交给 `AddAvoidanceZone()` 和 `GeneratePath()`，最后通过 `Action_MovePath()` 执行。

完整数据流为：

```text
可见危险事件
    ↓
Lua 危险区域注册表（唯一事实来源）
    ├─→ 紧急直接逃生点
    └─→ AddAvoidanceZone / RemoveAvoidanceZone
              ↓
          GeneratePath
              ↓
        路径有效性和代数检查
              ↓
        Action_MovePath
```

`AddAvoidanceZone()` 只负责注册脚本已经知道的区域，不能发现引擎内部危险。因此，本项目不承诺完整复刻旧 `GetAvoidanceZones()` 的信息覆盖。

### 2.2 永久非目标

- 不再调用、包装或尝试容错 `GetAvoidanceZones()`。
- 不把 `pcall` 当作原生访问冲突的隔离手段。
- 不读取战争迷雾外、Bot API 没有暴露的危险信息。
- 不从 game-side 全局权限向 Bot 侧泄漏不可见敌人或区域信息。
- 不假定普通 `Action_MoveToLocation()` 会自动读取 `AddAvoidanceZone()` 注册的区域。
- 不在第一版使用 `AddConditionalAvoidanceZone()`；它属于可选扩展阶段。
- 不在原生 API 未逐项通过前将避让默认启用到所有 Bot。

## 3. 当前证据基线

### 3.1 已确认的 `GetAvoidanceZones()` 崩溃

基线 dump：

```text
D:\DOTA Latest\dota 2 beta\game\bin\win64\dota2_2026_0824_005652_0_accessviolation.mdmp
SHA-256: 95F29169FEAD8B8472F40D4A2F316BF116AD0311A4425CD8C2F51D2D3E75411B
```

已确认签名：

```text
Exception: 0xC0000005 READ
Module: server.dll+0x1A05516
Fault target: 0x5A8
Fault instruction: mov rax, qword ptr [rcx+5A8h]
Register: rcx=0
```

调用链证据表明，引擎在序列化 avoidance zone 的 `ability` 字段时：

1. 从当前区域对象的 `+0x6C` 读取 ability handle。
2. handle 为 `0xFFFFFFFF`，解析结果为 `NULL`。
3. 调用方没有判空，继续进入 ability 包装路径。
4. 最终读取 `[NULL+0x5A8]`，触发原生访问冲突。

该区域的 RTTI 为 `CDOTA_Modifier_BaseBlocker`。dump 内含 `stage=before-call`，不含 `stage=after-call`，且没有 Lua runtime error。

公开问题记录：

- <https://github.com/ValveSoftware/Dota2-Gameplay/issues/9742>
- <https://github.com/ValveSoftware/Dota2-Gameplay/issues/23152>

### 3.2 匹配的运行时二进制

```text
D:\DOTA Latest\dota 2 beta\game\dota\bin\win64\server.dll
SHA-256: 254BEE29E9D60998C66CC6700DCAFF0F0D4BE692F092C20B59A2AE19FA227058
```

该二进制分别注册了：

- `AddAvoidanceZone`
- `AddConditionalAvoidanceZone`
- `RemoveAvoidanceZone`
- `GeneratePath`
- `GetAvoidanceZones`

注册说明把 `AddAvoidanceZone` 的用途限定为供 `GeneratePath` 使用。接口存在只证明当前构建暴露了入口，不证明其运行稳定性。

### 3.3 当前代码和运行时状态

| 检查项 | 当前状态 | 说明 |
| --- | --- | --- |
| 旧 `THDFuncLib/avoidance_zones_probe.lua` | 已退役并删除 | 不再保留危险读取实现 |
| 仓库与活跃镜像 `GetAvoidanceZones` Lua 调用 | 精确扫描为 0 | 镜像同步后以完全重启的新对局继续验证 |
| `mode_evasive_maneuvers_generic.lua` | 已通过 P0E 与 P7 真塔所有权实机验证 | 当前由测试 player 门禁限制作用范围 |
| `AddAvoidanceZone` / `RemoveAvoidanceZone` | P1/P2 已实机通过 | P8-01 仅对首个 Radiant Bot 的真塔撤离路线动态启用 |
| `GeneratePath` / `Action_MovePath` | P3–P5 已实机通过 | P8-01 生产控制器中继续关闭，不与动态区域生命周期同时引入 |
| Lua 自定义 avoidance 注册表与几何回退 | P7-02 已实机通过 | 当前只服务敌方 T1–T4 防越塔撤离 |
| `mode_retreat_generic.lua` | 未修改 | Valve retreat 继续完整拥有默认撤退行为 |

## 4. 不可违反的安全约束

### 4.1 原生 API 约束

1. 任何生产文件和活跃运行时镜像都不得调用 `GetAvoidanceZones()`。
2. 每个新原生接口必须单独测试，禁止一次加入多个尚未验证的调用。
3. 每个原生调用前后都必须打印可唯一归因的日志。
4. `pcall` 只用于区分 Lua 参数错误，不能作为 C++ 崩溃保护。
5. 任一阶段出现新 dump，立即停止后续阶段，不得继续组合更多原生 API。
6. dump 分析前不得仅凭最后一条普通游戏日志推断根因。

### 4.2 Bot 信息边界

1. 危险检测只能使用当前 Bot API 可见的信息。
2. 不得使用 game-side 全局搜索结果作为 Bot 的实时感知输入。
3. 对敌方 unit/ability handle 只做同帧可见读取；跨帧保存稳定 ID、名称和数值快照。
4. 失去可见性后无法确认持续状态的区域，应按配置的保守 TTL 到期，而不是继续读取旧 handle。

### 4.3 开发和同步约束

1. 所有原生 avoidance API 开关和手动探针在仓库中必须保持 `false`；已经通过实机门禁的 Lua 生产策略才可设为 `true`，并必须配套独立 run ID。
2. 每次实机测试前记录仓库文件和运行时镜像的 SHA-256。
3. 只同步本阶段明确列出的 Bot 文件，不覆盖无关运行时文件。
4. 静态语法/控制流审阅、镜像哈希一致和全新 Dota 对局是三种不同证据，必须分别记录；按当前项目策略不创建、维护或运行自动化、单元、mock 或回归测试。
5. 必须完全退出并重新启动 Dota 后，才能把一次测试标记为“全新对局实机通过”。

## 5. 目标模块设计

以下模块边界已按防越塔第一版落地；Lua 生产控制器已启用，原生 avoidance API 与手动探针继续关闭。

### 5.1 `THDFuncLib/avoidance_zone_manager.lua`

职责：

- 维护 Lua 危险区域注册表，作为唯一事实来源。
- 生成稳定的 danger key 并去重。
- 管理中心、半径、有效期、危险等级和来源快照。
- P8-20TG 在同一注册表中区分 1 秒活动危险与 30 秒最后可见塔几何；后者仅约束已取得租约后的移动，不独立取得或延长租约。
- 保存 `AddAvoidanceZone()` 返回的整数句柄。
- 在区域提前结束时调用已验证的 `RemoveAvoidanceZone()`。
- 清理 Lua 侧已过期记录，不重新读取引擎区域。
- 对原生 API 失败提供降级标记。

建议区域结构：

```lua
{
    key = 'ability_name:caster_player_id:cast_sequence',
    center = Vector(0, 0, 0),
    radius = 450,
    effectiveRadius = 650,
    createdAt = DotaTime(),
    expiresAt = DotaTime() + 4.0,
    severity = 'persistent',
    sourceAbilityName = 'ability_name',
    sourcePlayerID = 7,
    nativeHandle = nil,
    generation = 1,
}
```

不得在该结构中跨帧保存敌方 ability handle。

### 5.2 `THDFuncLib/avoidance_path.lua`

职责：

- 提交 `GeneratePath()` 请求。
- 保存 request ID、目标位置和请求代数。
- 丢弃晚到的过期回调。
- 验证回调距离、waypoint 类型和数量。
- 验证每一段 waypoint 线段与危险圆的最小净空。
- P8-20TG 的请求与执行复核使用完整有效移动几何，日志记录实际请求集合和各塔最后可见年龄。
- 在路径失败时返回明确的 Lua 降级原因。

建议请求结构：

```lua
{
    generation = 12,
    requestID = 34,
    requestedAt = DotaTime(),
    start = startLocation,
    destination = destination,
    zoneKeys = { 'zone-a', 'zone-b' },
    status = 'pending',
}
```

### 5.3 `THDFuncLib/avoidance_geometry.lua`

职责：

- 点到圆、线段到圆和线段到点的距离计算。
- 判断当前位置、目标点或规划线段是否进入区域。
- 计算 Bot 位于圆内时的直接逃生点。
- 直接逃生点必须同时满足落点和整段安全；侧面塔只作为安全约束，不参与路线障碍的远离方向合成。
- 计算原生路径失败时的左右候选绕行点。
- 使用 `IsLocationPassable()` 对候选点做最低限度过滤。

该模块应为纯 Lua，并对关键边界场景完成静态控制流审阅，不调用任何 Dota 原生 avoidance API。

### 5.4 `mode_evasive_maneuvers_generic.lua` 与防越塔控制器

集成方式已经冻结为新的 `EVASIVE_MANEUVERS` generic mode。默认关闭时文件不注册任何回调；P0E 只验证该文件在 Dota 7.38 中能否实际出现 `loaded → selected → Think`。如果不能加载，主线停止并归因，不降级到共享调度或 `ROAM`。

控制器职责：

- 当前处于危险区时优先直接逃离。
- 计划路径穿越持久危险区时请求安全路径。
- 在路径等待、执行和离开区域期间维持控制权。
- 离开 `effectiveRadius + hysteresis` 后才释放。
- 正确处理施法前摇、持续施法、不可移动和死亡状态。
- 通过 `bot.THD_TowerEscapeActive` 阻止共享和旧英雄动作入口覆盖逃生。
- Objective 参与者在逃生期间保留预留身份，并只获得一次 2.5 秒接近进度宽限。

### 5.5 危险能力目录

建议后续按能力名称维护：

```lua
{
    shape = 'circle',
    radius = 450,
    margin = 150,
    delay = 0.6,
    duration = 4.0,
    response = 'persistent_path',
}
```

第一批目录只加入可以从 Bot 可见事件可靠重建圆心和持续时间的能力，不追求一次覆盖全部英雄。

## 6. 统一日志和证据格式

### 6.1 日志前缀

所有阶段统一使用：

```text
[BOT][AvoidanceDev]
```

必要字段：

```text
run=<测试运行编号>
phase=<P0-P9>
team=<队伍>
player=<PlayerID>
generation=<请求代数>
zone=<稳定 danger key>
api=<API 名称或 none>
stage=<before-call|after-call|callback|execute|complete|fallback>
result=<结果>
```

示例：

```text
[BOT][AvoidanceDev] run=20260827-P1 phase=P1 team=2 player=1 generation=0 zone=probe-1 api=AddAvoidanceZone stage=before-call center_x=-1200 center_y=300 radius=450 duration=0.75
[BOT][AvoidanceDev] run=20260824-A phase=P1 team=2 player=1 generation=0 zone=probe-1 api=AddAvoidanceZone stage=after-call result=returned handle_type=number handle=17
```

不得打印 userdata 的完整内容或跨帧解引用敌方 handle。

### 6.2 阶段证据等级

| 等级 | 含义 | 可证明 | 不可证明 |
| --- | --- | --- | --- |
| E0 源码检查 | 阅读接口和调用边界 | 设计和命名一致 | Lua 能运行 |
| E1 `luac -p` | Lua 语法通过 | 文件可被 Lua 解析 | Dota API 参数正确 |
| E2 静态逻辑审阅 | 纯 Lua 状态机、几何边界和失效分支经源码控制流检查 | 本地算法包含预期分支 | Dota 运行时行为或原生 API 稳定 |
| E3 diff/扫描 | diff、禁用开关、禁用 API 扫描通过 | 变更范围和静态约束正确 | 运行时镜像一致 |
| E4 镜像哈希 | 仓库和目标镜像 SHA-256 一致 | Dota 将读取预期文件 | 对局行为正确 |
| E5 全新对局 | 完全重启后的指定场景通过 | 当前构建中该场景可运行 | 未覆盖场景也安全 |
| E6 dump 对比 | 无新 dump 或新 dump 已归因 | 当前测试是否引入原生崩溃 | 永久不会再崩溃 |

阶段只有同时满足其列出的最高证据等级，才能更新为相应状态。

## 7. 阶段进度总表

| Phase | 目标 | 当前状态 | 最高已完成证据 | 下一门禁 |
| --- | --- | --- | --- | --- |
| P0 | 固化崩溃基线并恢复安全运行时 | 实机通过 | E0–E6 | P0E 加载与仲裁门禁 |
| P0E | 验证 EVASIVE generic 加载和模式仲裁 | 实机通过 | E0–E6 | P1 单次 Add 门禁 |
| P1 | 单独验证 `AddAvoidanceZone()` | 实机通过 | E0–E6 | P2 TTL 与 Remove 门禁 |
| P2 | 验证自然过期和 `RemoveAvoidanceZone()` | 实机通过 | E0–E6 | P3 空区域 GeneratePath 门禁 |
| P3 | 单独验证无区域 `GeneratePath()` 回调契约 | 实机通过 | E0–E6 | P4 Add＋GeneratePath 组合门禁 |
| P4 | 验证新增圆形区域会改变路径 | 实机通过 | E0–E6 | P5 单 Bot Action_MovePath 门禁 |
| P5 | 验证单 Bot `Action_MovePath()` 执行 | 实机通过 | E0–E6 | P7 Lua-only 单 Bot 真塔逃生门禁 |
| P6 | 实现 Lua 区域注册表和纯 Lua 几何回退 | 实机通过 | E0–E6（由 P7-02 真塔链路覆盖） | P8 动态原生区域接入 |
| P7 | 集成高优先级回避控制器 | 实机通过 | E0–E6 | P8 动态区域与多 Bot 门禁 |
| P8 | 动态区域、多 Bot、动作竞争和异常场景 | 静态通过（P8-20TG；P8 实机仍未通过） | 20TG 已补全短期几何集合、整段检查与集合日志，另修游戏侧 caster；33 对镜像哈希一致、66 份 Lua 静态解析通过 | 等待完全重启后的 20TG 人工十 Bot 新局；路径零重入、缓存边界、零错误及保护/预算覆盖分别验收，不解锁 P9 |
| P9 | 小范围能力目录、性能和生产验收 | 未开始 | 无 | P8 实机通过 |
| PX | 可选验证 `AddConditionalAvoidanceZone()` | 未开始 | 无 | P9 后单独立项，不影响主线完成 |

## 8. 分阶段开发与验收

### Phase 0：恢复安全基线

#### 目标

确保后续对局不会再次执行已确认崩溃的 `GetAvoidanceZones()`，并保留现有 dump 作为归因基线。

#### 操作

- [x] 保存 dump 路径、时间、大小和 SHA-256。
- [x] 保存匹配 `server.dll` 的 SHA-256。
- [x] 删除仓库和活跃镜像中的旧危险读取探针。
- [x] 所有新 avoidance 开关在仓库和镜像中默认关闭。
- [x] 对仓库生产 Lua 和活跃镜像执行 `GetAvoidanceZones` 精确扫描，Lua 调用为 0。
- [x] 完全退出 Dota，重新启动并创建全新测试对局。
- [x] 确认日志不存在新的 `api=GetAvoidanceZones stage=before-call`。
- [x] 确认没有新 access violation dump。

#### 通过条件

- 活跃镜像不再包含旧探针；本阶段同步文件与仓库 SHA-256 一致。
- 全新对局中未执行 `GetAvoidanceZones()`。
- 没有时间晚于基线的新 dump。

#### 失败处理

如果仍出现 `GetAvoidanceZones stage=before-call`，先查找其他运行时镜像、workshop 脚本或旧加载路径；不得开始 Phase 1。

#### 状态摘要

P0 已实机通过；详细运行证据按第 12 节的两条滚动记录策略保留，不在阶段定义中重复存档。

### Phase 0E：`EVASIVE_MANEUVERS` 加载与仲裁门禁

#### 目标

在不调用任何 avoidance 原生 API、不发出任何动作的前提下，确认 Dota 2 7.38 会加载 `mode_evasive_maneuvers_generic.lua`，并允许它以 `BOT_MODE_DESIRE_ABSOLUTE` 进入 `Think()`。

#### 操作

- [x] 新增默认关闭的 `PROBE_MODE_LOAD` 和 `PROBE_PHASE=0`。
- [x] 只选择第一个 Radiant Bot，并要求其处于泉水安全范围。
- [x] 文件加载、模式选择和 `Think()` 分别记录 `loaded`、`selected`、`think_entered`。
- [x] `Think()` 首次进入后无动作持有 ABSOLUTE 1 秒，覆盖至少一次 0.5 秒 ModeDesire 采样。
- [x] ModeDesire 只在 P0E 标记有效且实际模式为 EVASIVE 时允许负时间样本；其他赛前样本继续关闭。
- [x] 静态控制流审阅确认 P0E 不调用 Add/Remove/Generate/MovePath，也不发移动动作。
- [x] 在全部原生开关关闭时完全重启 Dota 并运行一次 P0E。
- [x] 同时确认 ModeDesire 记录实际模式名 `evasive_maneuvers`。

#### 通过条件

- 同一 run/player 日志按顺序出现 `loaded → selected → Think`。
- ModeDesire 同帧序列出现 `evasive_maneuvers`。
- 没有 avoidance 原生调用日志、移动动作或新 dump。

#### 失败处理

如果 7.38 未加载该 generic mode，停止 P1–P9 的模式集成实机验证并归因；不得改挂共享调度或 `ROAM`。

### Phase 1：隔离验证 `AddAvoidanceZone()`

#### 目标

只确认以下事实：当前构建调用 `AddAvoidanceZone()` 是否返回稳定的整数句柄，并且不会立刻产生 dump。

#### 测试约束

- 仅第一个实际 Bot 执行一次。
- 使用开阔、安全、不会影响正常路线的位置。
- duration 固定为生产短 TTL `0.75` 秒。
- 不调用 `RemoveAvoidanceZone()`。
- 不调用 `GeneratePath()`。
- 不调用 `Action_MovePath()`。
- 不调用 `GetAvoidanceZones()`。

#### 必需日志

- `api=AddAvoidanceZone stage=before-call`
- `api=AddAvoidanceZone stage=after-call result=returned`
- 返回值类型和句柄数值
- 测试中心、半径和 duration

#### 通过条件

- `after-call` 出现。
- 返回值为可保存的 number。
- 等待区域自然过期后游戏继续运行。
- 没有新 dump。

#### 失败分支

| 失败 | 决策 |
| --- | --- |
| before 有、after 无、新 dump | `AddAvoidanceZone` 原生路线永久禁用；主线转纯 Lua |
| 返回 Lua error | 先核对当前签名和 Vector 约定，修正后只重测 P1 |
| 返回 nil/非 number | 不进入 P2/P4，记录当前 API 不可用 |

如果 `AddAvoidanceZone` 被明确禁用，则 P2、P4、P5 标记为“不适用”，不再阻塞 Phase 6 的纯 Lua 路线。

#### 状态摘要

P1 已实机通过；详细运行证据按第 12 节的两条滚动记录策略保留，不在阶段定义中重复存档。

### Phase 2：验证自然过期和 `RemoveAvoidanceZone()`

#### 目标

确认 Lua 可以只依赖自己保存的句柄管理区域生命周期，不需要枚举引擎区域。

#### 子场景

1. 添加 0.75 秒区域，不手动移除，观察自然过期。
2. 添加 10 秒区域，1 秒后用保存句柄移除。
3. 不得对已自然过期句柄再次调用 Remove，除非单独增加专门测试。

#### 必需日志

- Add before/after。
- Remove before/after。
- Lua 注册表的 createdAt、expiresAt、清理时间。

#### 通过条件

- Add 和 Remove 均有 after-call。
- 自然过期与 Lua 本地清理一致。
- 不读取 `GetAvoidanceZones()`。
- 没有新 dump。

#### 失败分支

如果只有 Remove 不稳定：

- 禁用手动 Remove。
- 原生区域只允许短 TTL 自然过期。
- 移动区域不得通过“长区域反复移动”实现。
- 后续是否继续 P3/P4，由一次独立复核决定。

### Phase 3：隔离验证 `GeneratePath()` 回调契约

#### 目标

在没有任何自定义区域的情况下，确认当前构建的参数、返回 request ID、官网二参数 callback、7.38 三参数扩展和失败表示。

#### 测试约束

- 起点、终点均在开阔可通行区域。
- 第三个参数使用空表，不调用 `GetAvoidanceZones()`。
- 回调只打印，不执行移动。
- 首次测试只允许一个 pending 请求。
- 回调期限使用生产值 `0.25` 秒；超时后 fail closed，晚到回调只记录并丢弃。
- P3-03 使用两个严格串行请求确认当前 7.38 返回 number 与 callback 第二参数逐次匹配；该 token 是实测扩展且可复用，官网 `(distance, waypoints)` 二参数 callback 同样必须通过，晚到回调始终由 Lua generation 判定。

#### 必需日志

- GeneratePath before/after。
- 返回 request ID 类型和值。
- callback 的 distance 类型和值。
- waypoint 表类型、数量和每个点的数值字段。
- callback 契约类型，以及可选 request token 是否存在。
- 请求到回调的延迟。

#### 通过条件

- after-call 出现。
- callback 在限定超时时间内出现。
- 成功路径 distance 大于 0，waypoint 非空。
- 没有新 dump。

#### 失败分支

| 失败 | 决策 |
| --- | --- |
| GeneratePath before 后崩溃 | 原生路径规划禁用，转纯 Lua |
| after 出现但 callback 永不出现 | 当前 API 不可用于实时避让 |
| callback 参数契约不同 | 只更新探针和文档，不进入 P4，重新验证 |

如果 `GeneratePath` 被明确禁用，则 P4、P5 标记为“不适用”，不再阻塞 Phase 6。

### Phase 4：验证区域确实改变路径

#### 目标

证明 `AddAvoidanceZone()` 创建的区域会被 `GeneratePath()` 采用，而不是只证明两个函数分别能返回。

#### 固定场景

- P4 不移动 Bot；按顺序从三组固定中路线段中选择起点和终点均可通行的第一组。
- 基准路径不设置区域；基准回调成功后，沿其累计路径长度的中点放置圆心，避免几何直线中点落在实际导航路线外。
- 半径固定为 360；放置前必须证明基准路径穿过该圆且起终点均有足够余量。
- baseline 和 Add 后的第二次 GeneratePath 第三个参数都必须是 `{}`；Add 返回句柄只保存在 Lua 区域记录中供 Remove 使用。
- 区域 effective radius 包含最小安全余量。
- 只打印和绘制路径，不执行 Bot 移动。

#### 数学验收

不能只检查 waypoint 是否在圆外，必须检查每一段相邻 waypoint 线段到圆心的最小距离：

```text
minClearance(segment_i, center) >= effectiveRadius - tolerance
```

同时检查：

```text
avoidancePathDistance > baselinePathDistance
```

允许导航网格带来少量测量误差，tolerance 必须在测试前固定，不能看结果后调整。

#### 通过条件

- 基准路径和避让路径回调均成功。
- 避让路径所有线段满足净空要求。
- 避让路径相对基准发生可解释变化。
- 没有新 dump。

#### 失败分支

- 如果路径完全不受区域影响，不能继续 P5。
- 先确认日志中的 `explicit_zone_count=0`，再区分“全局区域未被采用”“圆的 z/radius 约定不对”和“导航空间不足”。
- 禁止通过调用 `GetAvoidanceZones()` 检查区域是否存在。

### Phase 5：单 Bot 执行 `Action_MovePath()`

#### 目标

证明有效 waypoint 表可以被 Bot 执行，且不会立即被其他模式覆盖。

#### 测试步骤

1. 在测试模式中暂时抑制其他移动入口。
2. 复用 P4 的 baseline → Add 全局区域 → 空显式区域 GeneratePath 验证链；为确保 Bot 从路径起点开始，执行场景使用泉水内当前位置到 Ancient 方向 1200 距离的安全线段。
3. 记录 execute 前后的当前动作类型。
4. 调用一次 `Action_MovePath()`。
5. 采样 Bot 位置，计算实际轨迹到圆心的最小距离。
6. 到达目标或超时后结束测试。

#### 通过条件

- Bot 沿 waypoint 方向移动。
- 实际轨迹没有进入 effective radius。
- 没有出现高频重复下单或动作抖动。
- 没有新 dump。

#### 失败分支

- 如果 Action_MovePath 不稳定但 waypoint 正确，可降级为逐 waypoint 的 `Action_MoveToLocation()`。
- 如果泉水安全场景的原生 avoidance path 无法绕开测试圆，P4 结论保持有效；P5 可改用通过同一净空校验且到达原终点的 Lua fallback waypoint，继续隔离 Action_MovePath。
- 如果动作被模式覆盖，保留原生路径结论，问题转入 Phase 7 的动作所有权设计，不把它误判为 GeneratePath 失败。

### Phase 6：Lua 注册表、几何判断和回退

#### 目标

建立与原生 API 解耦的危险区域事实源。即使 P1-P5 任一原生能力不可用，该阶段仍应完成。

#### 开发内容

- [x] 稳定 `tower:<实体 ID>` key 和去重。
- [x] TTL、提前结束、Lua 本地清理。
- [x] `attackRange + 200` effective radius 计算。
- [x] 点是否在圆内。
- [x] 线段是否穿越圆。
- [x] Bot 在一个或多个重叠圆内时的联合直接逃生点。
- [x] 目标在圆内时拒绝把不安全终点作为完整路径。
- [x] 左右候选绕行点和 `IsLocationPassable()` 过滤。
- [x] 多区域集合参与整段净空校验。
- [x] request generation、目标/区域签名变化和旧回调丢弃。
- [x] 原生功能矩阵和 Lua 降级选择。

#### 必需边界场景审阅

1. 目标点在圆外、直线不穿圆。
2. 目标点在圆外、直线穿圆。
3. Bot 起点在圆内。
4. 目标点在圆内。
5. 起点等于圆心。
6. 相切、几乎相切和带 margin 相交。
7. 两个重叠圆。
8. 区域自然过期。
9. 同一 danger key 更新但不重复添加。
10. 旧 generation 回调晚到。
11. 原生 Add 禁用时回退 Lua。
12. 原生 GeneratePath 超时时回退 Lua。

#### 静态通过条件

- 所有新增 Lua `luac -p` 通过。
- 重点边界场景的控制流和失效分支均已审阅。
- `git diff --check` 通过。
- 精确扫描无生产 `GetAvoidanceZones()`。
- 默认功能开关均为 false。

### Phase 7：高优先级控制器与动作竞争

#### 目标

让危险回避真正拥有完整动作生命周期，而不是生成路径后被普通模式下一帧覆盖。

#### 开发前调查

- [x] 已由 P0E 实机确认 `mode_evasive_maneuvers_generic.lua` 在当前 7.38 被加载、选中并进入 `Think()`。
- [x] 已冻结失败策略：如果不会加载就停止并归因，不选择共享调度或 `ROAM`。
- [x] 已审计共享 `IsBotAwake`、`J.CanNotUseAction`、通用 Ability/Item Think 和旧英雄入口。
- [x] 第一版只处理非幻象英雄 Bot，不处理召唤物。

#### 生命周期状态

建议使用：

```text
IDLE
  → ESCAPE_DIRECT
  → WAITING_PATH
  → FOLLOWING_PATH
  → CLEARANCE_HOLD
  → IDLE
```

必须定义：

- 每个状态的进入条件。
- 可以发出的动作。
- 超时时间。
- 退出和回退条件。
- 是否允许打断施法前摇或持续施法。
- 死亡、无法移动、传送、飞行和路径目标改变时如何清理。

#### 通过条件

- 单 Bot 能在普通模式持续运行时完成一次避让。
- `WAITING_PATH` 不频繁重复提交请求。
- `FOLLOWING_PATH` 不被普通移动覆盖。
- 离开危险区后释放租约，由 Valve 模式或原 Objective 重新验证和决策，不重放旧 unit handle。
- 不影响自己的关键持续施法，除非已明确标为紧急可中断。

### Phase 8：动态区域、多 Bot 和边界场景

#### 动态区域策略

移动危险区不得注册成长 TTL 静态圆。建议：

- TTL 0.25 至 0.5 秒。
- 圆心位移超过阈值后才更新。
- Remove 已验证安全时先移除旧句柄；否则等待短 TTL 自然过期。
- 限制同一危险每秒最大原生更新次数。

#### 多 Bot 策略

- 选择唯一团队协调者添加全局区域，或通过团队级稳定 key 去重。
- 实测一个 Bot 添加的区域是否影响同队其他 Bot 的 GeneratePath。
- 实测是否意外影响敌方脚本队伍。
- 协调者死亡、掉线或 hero replacement 后必须能转移所有权。

#### 必测边界

- [ ] Bot 在区域中心。
- [ ] 目标在区域中心。
- [ ] 区域覆盖狭窄坡道，导致无可行路径。
- [ ] 两个或三个区域重叠。
- [ ] 区域在等待路径时过期。
- [ ] 目标在等待路径时改变。
- [ ] Bot 在等待路径时死亡。
- [ ] Bot 被眩晕、缠绕或击退。
- [ ] Bot 正在施法前摇。
- [ ] Bot 正在持续施法。
- [ ] 路径执行中出现更高严重度危险。
- [ ] 五个 Bot 同时看到同一危险。
- [ ] 区域来源失去视野。

#### P8-01R-16PC-10B 结果与归因修正

- [x] 本轮 189 次租约、186 组 mode-start/end 和 180 个 handoff 终点均闭合；多高地塔 11 个 IDLE 样本均同帧取得租约，Ancient 锚点降级未自然覆盖。
- [ ] 路径仍有 2 次入圈；P8-17TL 的预锁改动已回滚，此门禁没有通过，不解锁 P9。
- [x] 长撤的直接动作来源已定位：team 2/player 3/generation 24、player 4/generation 39 在租约释放后继续进行 86/75 次交接移动，分别持续交接 72.500/63.667 秒，首尾位置已回到己方基地。活动避塔短锚点与交接 Ancient 方向短步是不同路径。
- [ ] attack 的 18 段 `desire=0.000 + attack_target=none` 只证明日志状态；完整候选 desire、GetTarget 和动作/位移原本未采集。ROAM 冷却/无提案的零分支已有日志，高地四人门槛与复活后 push 接管吻合，但不得直接归因 Valve 仲裁异常。
- [x] P8-17TL 的团战授权租约、首次近圈预锁和 attack 恢复模块全部按原补丁回滚，源码/镜像恢复 P8-16 哈希后才添加本轮诊断。
- 后续 17MD 已确认自定义候选全零的实际空窗；保留下节结论，过期诊断说明在 19AS 验收后已备份清理。

#### P8-01R-17MD-10B 诊断结果与下一步

- [x] 单一 run/logger 覆盖十 Bot；17,299 组仲裁快照，每组 14 个候选，所有候选都有实际值、calls>0，最新回调年龄不超过 0.400146 秒。
- [x] 10 个至少 2 秒的零 attack / 无攻击目标区间共 339 点，14 个自定义候选最新值全部为 0；最长 83.133 秒。原生非活跃候选仍未知，不能将结果扩大为引擎内部全部候选。
- [x] 高地四人门槛已直接命中；普通 laning 超过 15 级为零、farm/assemble 固定零、ROAM 冷却/角色资格/无提案共同造成任务空窗。0.001866 的 defend 与 0.02 的 push 均能自然接管，无需 0.97 恢复任务。
- [x] team 3/player 10/generation 30 的避塔租约只持续 2.100 秒；释放后继续 54 次 fallback_move，交接 46.333 秒、快照首尾位移约 13816，长撤动作来源再次确认。
- [x] 195 次租约、193 组 mode-start/end、175 组 handoff 闭合；3 个多高地塔 IDLE 起点均同帧取得租约。
- [ ] 仍有 1 次 path_reentry / inside_tower_zone（team 3/player 10/generation 15，1160.467）；路径门禁未通过，不解锁 P9。
- [ ] 589 条缓存理由缺失和 3 条未标注分支不在上述长 attack 主样本中。嵌套防守查询可能污染 ROAM 的 cache/evaluation 等附加字段；不能将子查询缓存解释为整段 ROAM 未重算。
- 本轮仅分析日志并更新文档，源码和镜像仍是原诊断部署版本。没有行为改动、没有新 run，也不要求再重复同一诊断局。
- D1 交接移动预算、D2 独立普通任务已于 18LW 实施；D3 的过宽互斥仍按证据分批，不能一并取消安全门。17MD 旧报告已备份清理，不再保留为待执行说明。

#### P8-01R-18LW-10B 实机结果与下一步

- [x] 用户确认实施 D1/D2。交接补步只保留距释放位置最多 900 的冻结终点；释放后 4 秒、累计采样位移 1200、抵达/无进度/安全或任务状态改变时停止续发，不清其他任务的队列。停止不等于强制取消最后一条移动，也不伪记模式已交接。
- [x] 普通清线/护送/有限集合由独立任务分支承载，desire 为 0.28/0.22/0.18；高地人数/等级拒绝不再自动抹去所有安全普通任务。只限具体局部目标、期限及进度，不给无目标空壳加分，不落入建筑/AttackMove 分支。
- [x] 保留 siege 四人门槛、Objective/建筑授权、正常战斗/撤退/施法保护、ROAM 角色规则及高等级团战避塔策略。源码/镜像无原生禁用接口调用，无高欲望 attack 恢复模块。
- [x] 8 个 Lua 文件部署完成；相关 32 对源码/镜像 SHA-256 一致，64 份 Lua 语法解析与 diff 静态核对通过。目标搜索限频、复用塔快照；没有运行自动化测试或启动 Dota，不声称性能实测完成。
- [x] 十 Bot 新 run/logger 覆盖完整：15,416 组仲裁、215,824 条候选，14 项齐全且最新回调年龄最多 0.400146 秒。135 租约、133 组模式、116 组交接均闭合。
- [x] 本局无交接长撤，最长交接 0.933 秒，fallback_move=0；114 个 clearance 交接终点均不超过 900。全部在补步起点前结束，4 秒/1200 距离等预算执行态仍未自然覆盖。
- [x] 145 个普通任务全部闭合；护送 60 次 started、46 次 arrived，集合 37 次 started、30 次 arrived，已经有真实局部移动。
- [ ] 清线未通过：41 个 clear_wave 全无 started，35 个任务关联到正欲望 push 样本；push_lane_work.lua:291 调用不存在的 bot:IsAttacking()，共 30 条 Script Runtime Error。不是自然仲裁不接管，不能靠抬分解决；控制器里同名调用被 pcall 转为 false 的保护也需核对。
- [ ] 仍有 1 次 path_reentry/inside_tower_zone：team 3/player 6/generation 23，2586.033，Radiant 上路 T2，distance=949.6/r950、actual=1/requested=1。本版未修改路径几何，不解锁 P9。
- 详细验收及当时修复方案见 [P8-18LW 实机结果](docs/P8_18LW_RUNTIME_REVIEW.md)；该方案已于 19AS 实施。过期部署说明已清理，当前完整哈希迁入 19AS 实机报告；第 12 节保留 18LW 与 19AS 两次完整对局记录。

#### P8-01R-19AS-10B 实机结果与下一步

- [x] 单一 run/logger 覆盖双方十 Bot，11,156 组仲裁与 156,184 条候选，每组 14 项完整，最新回调年龄最多 0.400146 秒。32 个相关源码/镜像文件保持部署哈希，禁止 API 调用为零。
- [x] 清线入口修复得到运行证据：10 个 clear_wave 全部 started，3 个任务记录同目标 ATTACK 保留；无 IsAttacking 错误、无 attack_state_unavailable。任务实际命中/伤害归属不能由 started 或 target_lost 单独证明。
- [x] 67 个普通任务全部闭合，10 次 average_level_below_23 入口自然覆盖；护送 25 创建/22 启动/15 抵达，集合 32/32/24。desire、高地许可和 ROAM 角色规则未改。
- [x] 139 组交接全部闭合；3 次交接共 5 条 fallback_move，目标冻结、下单均在 1≤held_for<4 且 travel<1200，停止后无续发。最长交接 4.967 秒，但 2.600 秒已因 arrived 停止补步，没有据此退回基地。
- [ ] ATTACK/ATTACKMOVE 保护、4 秒/1200 上限、无进度或动态安全停止仍无对应自然触发样本，不能因 5 次下单守界就标为全面通过。
- [ ] 146 acquire/145 release、145 mode-start/144 mode-end；唯一末尾未闭合为 team 2/player 3/generation 24，在 2940.434 对局结束时被截断，既不冒充闭合，也不直接认定泄漏。
- [ ] 路径重入 1 次：team 2/player 1/generation 49，1802.000，Dire 中路 T3，distance=673.9/r950、actual=1/requested=0。前序连续 escape_only 向该塔推进；应查清可见/缓存/授权过滤集合，不直接加大 margin。
- [x] 17 次 waypoint_rejected、53 次 repath invalidated 后无旧代执行；49 条高等级团战 bypass，4 个双高地塔 IDLE 起点同帧取得租约。Ancient 锚点降级仍未覆盖。
- [ ] 游戏侧 item_nb9ball.lua:5 有 5 条未定义 caster 的 Runtime Error；与 Bot 攻击状态修复分开处理。无新 dump 不等于零 Lua 错误。
- [ ] 仍有其他模式的零欲望静止等待，14 个自定义候选全零、普通任务最后拒绝为 beyond_local_range 等；本局唯一 ≥2 秒的零 attack 段正在使用技能并移动，不能按标签判挂机。
- 完整证据及后续范围见 [P8-19AS 实机报告](docs/P8_19AS_RUNTIME_REVIEW.md)。19AS 验收轮只分析并清理旧说明；随后用户授权实施以下 20TG，P8 仍未通过，不解锁 P9。

#### P8-01R-20TG-10B 已部署，待人工实机

- [x] 仅改 5 个 Bot Lua 文件：config、zone_manager、geometry、path、controller。活动危险 TTL 仍为 1 秒；可见塔数值几何保留 30 秒，正常交接不清短期几何，死亡/禁用/显式 Reset 清空。
- [x] 路径请求、Lua fallback、直接逃生和当前 waypoint 复核使用完整有效移动几何；侧面塔只参与约束。直接候选必须整段安全，无安全候选时不再向未经校验的锚点下单。
- [x] geometry-snapshot 区分活动/路线/完整集合，以及 visible/remembered、年龄和授权排除原因；路径请求记录实际集合与 game_time，保留 team + player + generation 归因。
- [x] 不扩大信息权限、不新增敌方查询，复用现有扫描。保留 desire、普通任务范围、高地门槛、ROAM 角色、前摇/持续施法保护及 4 秒/1200 交接预算；无 CPU/帧耗实测结论。
- [x] 游戏侧独立修复 `item_nb9ball:GetCastRange()` 的局部 caster 与有效性检查；服务端 99999 下单语义和 OnSpellStart 的 KV 999+加成距离截断不变，已同步 THI。
- [x] 32 对 Bot + 1 对游戏源码/镜像 SHA-256 一致；66 份 Lua 静态语法解析与双仓库 diff 核对通过，GetAvoidanceZones 调用为零。没有运行自动化测试或启动 Dota。
- [ ] 人工新局待执行。重点确认相邻塔不再漏入路径约束、记忆不过度避让且不延长租约、高等级团战优先、无 caster 错误，以及原有保护/预算未覆盖分支。无安全候选时不续发命令不等于取消旧命令，须观察是否滞留。
- 19AS 样本的具体可见性/授权变化不能由旧日志倒推；本版静态修复不等于证明所有实机根因已排除。完整参数、哈希、回滚备份与人工门禁见 [20TG 部署说明](docs/P8_20TG_DEPLOYMENT.md)。

### Phase 9：小范围生产验收

#### 第一批能力选择标准

只选择同时满足以下条件的能力：

- Bot 能可靠获得中心位置。
- 半径和持续时间能从 THD KV/Lua 确认。
- 危险为持续圆形区域，适合路径避让。
- 不是要求几十毫秒反应的高速线性技能。
- 不依赖战争迷雾外信息。

第一批建议只做 1 至 3 个能力，逐个加入目录和实机覆盖。

#### 性能门禁

- 不允许每帧全图扫描所有单位。
- 不允许每帧对每个 Bot 无条件调用 GeneratePath。
- 区域检测、路径生成和 DebugDraw 必须分别限频。
- release 构建关闭 DebugDraw 和详细日志。
- 记录每 Bot 每分钟 Add、Remove、GeneratePath 和动作下单次数。

#### 最终生产通过条件

- 所有默认开关设计明确，正式启用项才改为 true。
- 全部新增 Lua 语法通过。
- 全部重点边界场景的控制流和失效分支审阅完成。
- 禁止 API 精确扫描通过。
- 源码与运行时镜像哈希一致。
- 完全重启后的多场全新对局覆盖选定能力。
- 没有新 avoidance 原生崩溃 dump。
- 普通移动、撤退、推进、TP、持续施法和死亡重生没有明显回归。

### Phase X：可选 `AddConditionalAvoidanceZone()`

该阶段不属于第一版完成条件。

只有在 P9 完成后，且确有固定位置动态启用区域需求时才考虑。测试必须与 Add、Remove 和 GeneratePath 主线分开，条件回调只能读取稳定数值状态，不得捕获长期敌方 unit/ability handle。

## 9. 原生能力矩阵和降级决策

每完成一个原生阶段，更新下表：

| 能力 | 未测试 | 可用 | 不可用 | 降级方案 |
| --- | --- | --- | --- | --- |
| `AddAvoidanceZone` | 否 | P1 单次调用返回 number 句柄且无新 dump |  | Lua 注册表，不向引擎注册 |
| 自然 TTL | 否 | P2 等待短 TTL 后游戏继续运行；实际路径影响仍由 P4 间接验证 |  | Lua 自行过期 |
| `RemoveAvoidanceZone` | 否 | P2 保存句柄后单次 Remove before/after 完整且无新 dump |  | 只使用短 TTL，不手动移除 |
| `GeneratePath` 空区域 | 否 | P3 两个串行请求均在 0.033 秒回调并得到有效 waypoint；token 0 可复用 |  | Lua 候选绕行点 |
| `GeneratePath` 自定义区域 | 否 | P4 开阔场景中全局 Add 圆区令路径增长约 6.75%；泉水窄路无替代路线时可返回原路径 |  | Lua 线段/圆净空复核；不合格时使用切线 waypoint |
| `Action_MovePath` | 否 | P5-02 单次执行 2 个 Lua 安全 waypoint，21 个轨迹样本后到达，最小净空 254.25 |  | 逐 waypoint `Action_MoveToLocation` |
| `AddConditionalAvoidanceZone` | 是 |  |  | 短 TTL 普通区域 |

降级后不得保留不可用原生接口的“偶尔尝试”路径。

## 10. Dump 归因流程

每次实机测试前：

1. 记录测试开始时间和 run ID。
2. 列出当前最新三个 `.mdmp` 的文件名、时间、大小和 SHA-256。
3. 确认本阶段只新增一个尚未验证的原生调用。
4. 保存源码和运行时镜像哈希。

发生崩溃后：

1. 找到时间晚于测试开始的新 dump。
2. 计算 SHA-256，禁止用文件名代替唯一标识。
3. 读取 exception code、thread、RIP、fault address 和寄存器。
4. 映射到匹配模块和模块偏移。
5. 比较 `server.dll+0x1A05516` 的已知 Get 崩溃签名。
6. 搜索 dump 内的 `[BOT][AvoidanceDev]` 日志副本。
7. 找到最后一个 before/after/callback/execute 阶段。
8. 没有匹配 PDB 时，只报告机器码、模块偏移、寄存器和可验证 RTTI，不发明内部函数名。

归因规则：

| 最后日志 | 初步范围 |
| --- | --- |
| Add before，无 Add after | `AddAvoidanceZone` 调用内部 |
| Add after，Remove before，无 Remove after | `RemoveAvoidanceZone` 调用内部 |
| GeneratePath before，无 after | `GeneratePath` 同步入口 |
| GeneratePath after，无 callback | 异步路径任务或无回调，需结合栈判断 |
| callback 完成，execute before，无 execute after | `Action_MovePath` 调用入口 |
| execute after，稍后崩溃 | 不能仅凭最后日志归因，必须看 dump 栈和偏移 |

## 11. 功能开关和回滚点

建议每一层使用独立开关，禁止只有一个总开关：

```lua
Avoidance.ENABLED = false
Avoidance.TOWER_ESCAPE_ENABLED = false
Avoidance.PROBE_MODE_LOAD = false
Avoidance.PROBE_PHASE = 0
Avoidance.USE_NATIVE_ZONES = false
Avoidance.USE_NATIVE_REMOVE = false
Avoidance.USE_NATIVE_PATH = false
Avoidance.EXECUTE_NATIVE_PATH = false
Avoidance.DEBUG_LOG = false
Avoidance.DEBUG_DRAW = false
```

阶段启用顺序：

```text
DEBUG_LOG
  → PROBE_MODE_LOAD（P0E，所有原生 API 仍关闭）
  → PROBE_PHASE=1 / USE_NATIVE_ZONES
  → USE_NATIVE_REMOVE
  → USE_NATIVE_PATH
  → EXECUTE_NATIVE_PATH
  → TOWER_ESCAPE_ENABLED
  → ENABLED
```

任一阶段失败，只关闭当前层和其后所有层。不得用删除 Lua 注册表的方式回滚，因为注册表是后续纯 Lua 回退的基础。

P8-18LW 的独立关闭点：`avoidance_config.lua` 的 `HANDOFF_FALLBACK_ENABLED` 只控制释放后补步；`push_lane_work.lua` 的 `Work.ENABLED` 只控制新增普通兵线任务；`DEBUG_CANDIDATE_DESIRE` 只控制候选观测。关闭这些开关不等于重现某个历史版本，不得同时清除避塔注册表或放宽 siege 许可。

## 12. 每阶段交接模板

后续开发完成一个阶段后，滚动更新本节的“本次”和“上次”两条完整手动实机记录：

```text
### YYYY-MM-DD / Phase N / run=<ID>

状态：静态通过 | 实机通过 | 阻塞

变更文件：
- path/to/file.lua

静态证据：
- luac -p：
- 控制流与边界场景审阅：
- git diff --check：
- 禁止 API 扫描：

运行时证据：
- Dota 是否完全重启：
- 是否为全新对局：
- 源码 SHA-256：
- 镜像 SHA-256：
- 关键日志：
- 测试前最新 dump：
- 测试后最新 dump：

结论：

下一阶段是否解锁：是 | 否
```

### 测试记录保留策略

从本次更新起，本计划只保留最近两次**完整手动实机**测试例：本次与紧前一次。更早 run 的详细日志、部署和准备记录不再在本文累积；其已确认阶段结论只保留在第 1 节和第 7 节的摘要状态中。静态检查、镜像一致性和人工实机观察仍需分开判断，但不以历史流水形式长期保留。

依用户要求，每次完成验收后同步清理失效的部署/待验收说明；当前已完成版的必要参数、哈希和验收结论迁入实机报告。独立实机报告也只保留本次与上次两份。删除前保留可恢复备份，修正计划和保留报告中的链接；原始日志、dump 和行为源码不随文档清理删除。


### 上次完整实机测试例 / 2026-09-02 / P8-01R-18LW-10B Local Lane Work / run=20260902-P8-01R-18LW-10B

状态：实机未通过。清线动作入口 nil-call，交接预算未自然触发，仍有路径重入；护送/集合部分有效。完整证据见 [P8-18LW 实机报告](docs/P8_18LW_RUNTIME_REVIEW.md)。

- 日志 138,383,178 bytes、330,887 行，修改时间 2026-09-02 13:59:18，SHA-256 `96647FF03DDC3AFC6D2698B591AA1A55660AD1034352E0786A2ABADF43E68D2D`；单一 run/logger_instance=26533-1，十 Bot 仲裁覆盖约 DotaTime 0–3366.733。
- 15,416 组 ModeArbitration、215,824 条 ModeCandidate、53,693 条 ModeDesire、4,121 条 AvoidanceDev、388 条 LaneWork；14 项候选齐全，全部值可用/calls>0，最新回调年龄最多 0.400146 秒。
- 135 次租约（team 2=77、team 3=58）、133 组 mode-start/end、116 组 handoff 闭合，无重叠/孤立/结束悬空。交接 completed=114、reacquired=2，最长 0.933 秒；114 个 clearance 交接终点距释放点 ≤900，fallback_move/target/retarget/stale 均为 0。预算执行态及攻击保护未自然覆盖。
- 145 个普通任务全部创建/释放配平，全部命中 eligible_below_4，覆盖 9 个 Bot；escort_wave 66 创建/60 启动/46 抵达，stage_lane 38/37/30；clear_wave 41 创建/0 启动，35 个任务已关联正欲望 push 样本。任务生命周期闭合不等于动作成功。
- Script Runtime Error=30，均为 push_lane_work.lua:291 的 `attempt to call method 'IsAttacking' (a nil value)`，发生在清线攻击下单前。team 2/player 2/generation 9 于 2300.633 已以 push_mid≈0.28 被选中，随后报错；没有必要提高 desire。controller 里同名调用虽被 pcall 吞掉，也不能视为有效攻击保护。
- 3 段 ≥2 秒的活体零 attack/无攻击目标样本共 42 点，14 项最新值全零，首尾差为 14.000/8.133/2.733 秒；部分仍在移动。另有正欲望 push 清线无动作及 35.067 秒 push=0 静止等待，不能把 attack 标签样本减少当作挂机修复比例。
- path_reentry/inside_tower_zone 各 1：team 3/player 6/generation 23，于 2586.033 进入 Radiant 上路 T2，distance=949.6/r950、actual=1/requested=1。4 次 waypoint rejection、14 次 repath invalidation 后未见旧 generation 执行。6 条团战 bypass，多高地塔重叠/Ancient 降级未自然覆盖。
- 8 个本版源码与镜像文件均保持部署哈希，禁止 API 调用为零；logger_error=0、无新 dump，但 Lua 错误门禁失败。最新 dump 仍为 2026-08-24 00:56:52，SHA-256 `95F29169FEAD8B8472F40D4A2F316BF116AD0311A4425CD8C2F51D2D3E75411B`。
- 本轮只分析与更新文档，没有行为修改或自动化测试。234 条缓存理由缺失及原有嵌套辅助字段污染仍保留为诊断限制，没有独立 CPU/帧耗结论。

当时结论：先修清线与交接攻击保护中的错误成员调用，保持 desire、siege 门槛及角色规则不变；该小修已于 19AS 实施，结果见下。路径重入独立继续 P8，不解锁 P9。

### 本次完整实机测试例 / 2026-09-02 / P8-01R-19AS-10B Attack State / run=20260902-P8-01R-19AS-10B

状态：本版清线攻击状态入口修复有效，交接有限补步有部分自然覆盖；路径及零错误门禁仍失败，P8 未通过。完整证据与 32 文件哈希见 [P8-19AS 实机报告](docs/P8_19AS_RUNTIME_REVIEW.md)。

- 日志 112,623,547 bytes、266,594 行，修改时间 2026-09-02 16:46:26，SHA-256 `77824E2ABDB2049EFD649BEDD77ACB8F0B0BA9C5547EB06C30CB9888388B179C`；单一 run/logger_instance=67467-1，十 Bot 仲裁覆盖约 DotaTime 0–2940.300，2940.434 Ancient 被摧毁后进入 POST_GAME。
- 11,156 组 ModeArbitration、156,184 条 ModeCandidate、47,010 条 ModeDesire、4,900 条 AvoidanceDev、202 条 LaneWork；14 项候选齐全、有值且 calls>0，最大回调年龄 0.400146 秒。原生非活跃候选仍不可见。
- 67 个普通任务覆盖 8 Bot、全部闭合；clear_wave 10 创建/10 started/3 attack_preserved，escort_wave 25/22/15 arrived，stage_lane 32/32/24 arrived。创建原因 eligible_below_4=57、average_level_below_23=10。清线入口不再报错，但目标丢失不是命中或击杀归因。
- 146 次 acquire（team 2=117、team 3=29）/145 release；145 mode-start/144 mode-end。team 2/player 3/generation 24 在 2939.067 取得、2940.400 开始净空确认，随后对局结束截断；其余没有重叠/孤立终点。
- 139 组 handoff 闭合（138 completed、1 reacquired）；129 个允许补步的冻结终点距离≤900。5 次 fallback_move 来自 3 组交接，全部目标固定、下单在 1≤held_for<4 和 travel<1200，停止后无续发，无 fallback_target/retarget。
- 最长交接 team 3/player 8/generation 4，held_for=4.967；实际仅 2 次补步，2.600 秒 arrived 停止、travel=794.6，之后才由 defend_top=0.98 接管。不能把整个交接时长当作持续撤退或预算超发；攻击保护和上限停止仍未自然覆盖。
- path_reentry/inside_tower_zone 各 1：team 2/player 1/generation 49，1802.000，Dire 中路 T3，distance=673.9/r950、actual=1/requested=0；前序连续 escape_only，随后 generation 50 同帧失效并直接退出。17 次 waypoint rejection、53 次 repath invalidation 后无旧代执行。
- 49 条团战 bypass（计数 0/1 分别 30/19），8 条双高地塔退出策略，4 个 IDLE 起点同帧 acquire；Ancient 锚点降级未覆盖。
- 唯一 ≥2 秒的零 attack/无攻击目标段为 team 2/player 5 的 2498.967–2503.634，8 点、4.667 秒，全部 using_ability=true 且位移约 2169，不是静止挂机。另有 push_mid/item/roshan 零欲望静止段，其 14 项候选全零，不能宣布全局挂机已解决。
- 5 条 Script Runtime Error 全为游戏侧 item_nb9ball.lua:5 的未定义 caster；Bot 的 IsAttacking 错误、attack_state_unavailable 与 logger_error 均为零。无新 dump，最新仍为 2026-08-24 00:56:52，SHA-256 `95F29169FEAD8B8472F40D4A2F316BF116AD0311A4425CD8C2F51D2D3E75411B`。
- 当前 32 文件源码/镜像保持部署哈希、禁止 API 调用为零。228 条缓存理由缺失及原有嵌套附加字段限制保留；未测独立 CPU/帧耗。本轮只分析、更新计划、备份清理 4 份旧说明，没有行为改动或自动化测试。

当次验收结论：优先处理 escape_only 路径塔集合遗漏/可见性/授权变化；游戏侧 caster 错误单独修复。随后用户已授权 20TG 并完成部署，见第 8 节；本条保留 19AS 的历史实机结论，不解锁 P9。

## 13. 完成定义

本项目只有同时达到以下条件才算完成：

- `GetAvoidanceZones()` 在生产源码和运行时镜像中保持零调用。
- Lua 区域注册表是危险状态的唯一事实来源。
- 当前构建下可用的原生能力已经逐项验证并记录；不可用能力有明确、已测试的降级路线。
- Bot 能在至少一个真实 THD 持续圆形危险中识别区域、取得动作所有权、绕行并恢复原行为。
- 起点在区域内、目标在区域内、重叠区域、路径失败、区域过期和旧回调均有测试覆盖。
- 单 Bot、五 Radiant 和双方十 Bot 场景均无明显动作抖动或区域重复泄漏。
- 静态验证、镜像一致性、全新对局和 dump 结果分别记录。
- 所有适用且已解锁阶段均达到“实机通过”；被禁用的原生分支明确标记为“不适用”，没有通过跳过失败门禁完成后续阶段。
