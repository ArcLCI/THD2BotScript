# THD Bot 危险区域避让：阶段化开发与验收计划

## 1. 文档状态

| 项目 | 当前值 |
| --- | --- |
| 文档用途 | 作为后续危险区域识别、原生路径验证、Bot 移动集成和实机验收的唯一阶段清单 |
| 目标环境 | Dota 2 7.38，本机安装目录 `D:\DOTA Latest\dota 2 beta` |
| 目标仓库 | `THD2BotScript` |
| 当前总体状态 | Phase 0 部分完成；活跃运行时探针尚未关闭，后续实机阶段阻塞 |
| 生产策略 | 永久禁止 `GetAvoidanceZones()`；由 Lua 自建危险区域注册表 |
| 原生路径策略 | `AddAvoidanceZone()`、`RemoveAvoidanceZone()`、`GeneratePath()`、`Action_MovePath()` 必须逐项验证后才能启用 |
| 回退策略 | 任一原生路径接口不稳定时，保留 Lua 危险注册表，退回 Lua 几何避让和普通移动 |

状态枚举统一使用：

- `未开始`：尚未修改或验证。
- `开发中`：已有实现，但当前阶段尚未完成全部静态门禁。
- `静态通过`：语法、mock、扫描和 diff 已通过，但未完成 Dota 实机验证。
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
| 仓库 `THDFuncLib/avoidance_zones_probe.lua` | `Probe.ENABLED = false` | 仓库默认安全 |
| 活跃 Dota 镜像同名文件 | `Probe.ENABLED = true` | **阻塞后续实机测试；启动新比赛前必须关闭** |
| 生产 Lua 中 `GetAvoidanceZones` | 仅诊断探针 | 后续应保持精确扫描零生产调用 |
| 生产 Lua 中 `AddAvoidanceZone` | 0 处 | 尚未开发 |
| 生产 Lua 中 `GeneratePath` | 0 处 | 尚未开发 |
| 生产 Lua 中 `Action_MovePath` | 0 处 | 尚未开发 |
| `Action_MoveToLocation` | 19 处 | 现有移动不会自动变成避让路径 |
| Lua 自定义 avoidance 注册表 | 已有未使用雏形 | `THDFuncLib/utils.lua` 中标记为 TODO |

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

1. 所有功能开关在仓库中默认必须为 `false`。
2. 每次实机测试前记录仓库文件和运行时镜像的 SHA-256。
3. 只同步本阶段明确列出的 Bot 文件，不覆盖无关运行时文件。
4. 静态测试、mock、镜像哈希一致和全新 Dota 对局是四种不同证据，必须分别记录。
5. 必须完全退出并重新启动 Dota 后，才能把一次测试标记为“全新对局实机通过”。

## 5. 目标模块设计

以下为建议的最终模块边界。具体文件只有在相应阶段开始时才创建。

### 5.1 `THDFuncLib/avoidance_zone_manager.lua`

职责：

- 维护 Lua 危险区域注册表，作为唯一事实来源。
- 生成稳定的 danger key 并去重。
- 管理中心、半径、有效期、危险等级和来源快照。
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
- 计算原生路径失败时的左右候选绕行点。
- 使用 `IsLocationPassable()` 对候选点做最低限度过滤。

该模块应为纯 Lua，并具有完整 mock 覆盖，不调用任何 Dota 原生 avoidance API。

### 5.4 危险回避控制器

候选集成方式：

- 新建与 `BOT_MODE_EVASIVE_MANEUVERS` 对应的高优先级 generic mode；或
- 在现有共享调度入口中增加独立控制器，并确保它能阻止普通模式覆盖移动命令。

在 Phase 7 前不得提前确定文件名；必须先确认 Dota 7.38 对自定义 evasive mode 文件的加载行为。

控制器职责：

- 当前处于危险区时优先直接逃离。
- 计划路径穿越持久危险区时请求安全路径。
- 在路径等待、执行和离开区域期间维持控制权。
- 离开 `effectiveRadius + hysteresis` 后才释放。
- 正确处理施法前摇、持续施法、不可移动和死亡状态。

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
[BOT][AvoidanceDev] run=20260824-A phase=P1 team=2 player=1 generation=0 zone=probe-1 api=AddAvoidanceZone stage=before-call center_x=-1200 center_y=300 radius=450 duration=10.00
[BOT][AvoidanceDev] run=20260824-A phase=P1 team=2 player=1 generation=0 zone=probe-1 api=AddAvoidanceZone stage=after-call result=returned handle_type=number handle=17
```

不得打印 userdata 的完整内容或跨帧解引用敌方 handle。

### 6.2 阶段证据等级

| 等级 | 含义 | 可证明 | 不可证明 |
| --- | --- | --- | --- |
| E0 源码检查 | 阅读接口和调用边界 | 设计和命名一致 | Lua 能运行 |
| E1 `luac -p` | Lua 语法通过 | 文件可被 Lua 解析 | Dota API 参数正确 |
| E2 mock | 纯 Lua 状态机和几何测试通过 | 本地算法满足测试场景 | 原生 API 稳定 |
| E3 diff/扫描 | diff、禁用开关、禁用 API 扫描通过 | 变更范围和静态约束正确 | 运行时镜像一致 |
| E4 镜像哈希 | 仓库和目标镜像 SHA-256 一致 | Dota 将读取预期文件 | 对局行为正确 |
| E5 全新对局 | 完全重启后的指定场景通过 | 当前构建中该场景可运行 | 未覆盖场景也安全 |
| E6 dump 对比 | 无新 dump 或新 dump 已归因 | 当前测试是否引入原生崩溃 | 永久不会再崩溃 |

阶段只有同时满足其列出的最高证据等级，才能更新为相应状态。

## 7. 阶段进度总表

| Phase | 目标 | 当前状态 | 最高已完成证据 | 下一门禁 |
| --- | --- | --- | --- | --- |
| P0 | 固化崩溃基线并恢复安全运行时 | 阻塞 | E0、E6 | 活跃镜像探针改回 `false`，全新对局确认不再调用 Get |
| P1 | 单独验证 `AddAvoidanceZone()` | 未开始 | 无 | P0 实机通过 |
| P2 | 验证自然过期和 `RemoveAvoidanceZone()` | 未开始 | 无 | P1 实机通过 |
| P3 | 单独验证无区域 `GeneratePath()` 回调契约 | 未开始 | 无 | P1 实机通过；P2 可并行设计但不可混测 |
| P4 | 验证新增圆形区域会改变路径 | 未开始 | 无 | P2、P3 实机通过 |
| P5 | 验证单 Bot `Action_MovePath()` 执行 | 未开始 | 无 | P4 实机通过 |
| P6 | 实现 Lua 区域注册表和纯 Lua 几何回退 | 未开始 | 无 | 原生能力矩阵已确定为通过、禁用或不适用 |
| P7 | 集成高优先级回避控制器 | 未开始 | 无 | P6 静态通过和重点 mock 通过 |
| P8 | 动态区域、多 Bot、动作竞争和异常场景 | 未开始 | 无 | P7 单 Bot 实机通过 |
| P9 | 小范围能力目录、性能和生产验收 | 未开始 | 无 | P8 实机通过 |
| PX | 可选验证 `AddConditionalAvoidanceZone()` | 未开始 | 无 | P9 后单独立项，不影响主线完成 |

## 8. 分阶段开发与验收

### Phase 0：恢复安全基线

#### 目标

确保后续对局不会再次执行已确认崩溃的 `GetAvoidanceZones()`，并保留现有 dump 作为归因基线。

#### 操作

- [x] 保存 dump 路径、时间、大小和 SHA-256。
- [x] 保存匹配 `server.dll` 的 SHA-256。
- [x] 仓库探针默认为 `Probe.ENABLED = false`。
- [ ] 将活跃 Dota Bot 镜像的探针恢复为 `false`。
- [ ] 对仓库生产 Lua 和活跃镜像执行 `GetAvoidanceZones` 精确扫描。
- [ ] 完全退出 Dota，重新启动并创建全新测试对局。
- [ ] 确认日志不存在新的 `api=GetAvoidanceZones stage=before-call`。
- [ ] 确认没有新 access violation dump。

#### 通过条件

- 活跃镜像和仓库探针文件 SHA-256 一致。
- 全新对局中未执行 `GetAvoidanceZones()`。
- 没有时间晚于基线的新 dump。

#### 失败处理

如果仍出现 `GetAvoidanceZones stage=before-call`，先查找其他运行时镜像、workshop 脚本或旧加载路径；不得开始 Phase 1。

#### 阶段记录

```text
状态：阻塞
测试时间：
运行编号：
源码哈希：
镜像哈希：
最新 dump：
结论：活跃镜像仍为 Probe.ENABLED=true
```

### Phase 1：隔离验证 `AddAvoidanceZone()`

#### 目标

只确认以下事实：当前构建调用 `AddAvoidanceZone()` 是否返回稳定的整数句柄，并且不会立刻产生 dump。

#### 测试约束

- 仅第一个实际 Bot 执行一次。
- 使用开阔、安全、不会影响正常路线的位置。
- duration 固定为 10 秒。
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

#### 阶段记录

```text
状态：未开始
测试时间：
运行编号：
返回句柄：
新增 dump：
结论：
```

### Phase 2：验证自然过期和 `RemoveAvoidanceZone()`

#### 目标

确认 Lua 可以只依赖自己保存的句柄管理区域生命周期，不需要枚举引擎区域。

#### 子场景

1. 添加 2 秒区域，不手动移除，观察自然过期。
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

在没有任何自定义区域的情况下，确认当前构建的参数、返回 request ID、回调参数和失败表示。

#### 测试约束

- 起点、终点均在开阔可通行区域。
- 第三个参数使用空表，不调用 `GetAvoidanceZones()`。
- 回调只打印，不执行移动。
- 首次测试只允许一个 pending 请求。

#### 必需日志

- GeneratePath before/after。
- 返回 request ID 类型和值。
- callback 的 distance 类型和值。
- waypoint 表类型、数量和每个点的数值字段。
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

- 在开阔地形选择起点 A 和终点 B。
- 基准路径不设置区域。
- 在 A-B 中点设置圆形区域，半径足以阻挡直线路径但仍可从两侧绕行。
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
- 先区分“句柄列表格式不对”“全局区域未被采用”“圆的 z/radius 约定不对”。
- 禁止通过调用 `GetAvoidanceZones()` 检查区域是否存在。

### Phase 5：单 Bot 执行 `Action_MovePath()`

#### 目标

证明有效 waypoint 表可以被 Bot 执行，且不会立即被其他模式覆盖。

#### 测试步骤

1. 在测试模式中暂时抑制其他移动入口。
2. 复用 P4 的固定开阔场景。
3. 记录 execute 前的当前动作类型。
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
- 如果动作被模式覆盖，保留原生路径结论，问题转入 Phase 7 的动作所有权设计，不把它误判为 GeneratePath 失败。

### Phase 6：Lua 注册表、几何判断和回退

#### 目标

建立与原生 API 解耦的危险区域事实源。即使 P1-P5 任一原生能力不可用，该阶段仍应完成。

#### 开发内容

- [ ] 稳定 danger key 和去重。
- [ ] TTL、提前结束、Lua 本地清理。
- [ ] effective radius 计算。
- [ ] 点是否在圆内。
- [ ] 线段是否穿越圆。
- [ ] Bot 在圆内时的直接逃生点。
- [ ] 目标在圆内时的安全投影或拒绝策略。
- [ ] 左右候选绕行点。
- [ ] 多区域下的下一碰撞区域选择。
- [ ] request generation 和旧回调丢弃。
- [ ] 原生功能矩阵和降级选择。

#### 必需 mock

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
- 重点 mock 全部通过。
- `git diff --check` 通过。
- 精确扫描无生产 `GetAvoidanceZones()`。
- 默认功能开关均为 false。

### Phase 7：高优先级控制器与动作竞争

#### 目标

让危险回避真正拥有完整动作生命周期，而不是生成路径后被普通模式下一帧覆盖。

#### 开发前调查

- [ ] 确认 `mode_evasive_maneuvers_generic.lua` 在当前 7.38 是否会被加载。
- [ ] 如果不会加载，选定现有共享调度入口。
- [ ] 列出所有独立移动入口和共享 action wrapper。
- [ ] 确认幻象、召唤物是否在第一版范围内；默认只处理英雄 Bot。

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
- 离开危险区后能恢复先前目标或正常模式。
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
- 全部重点 mock 通过。
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
| `AddAvoidanceZone` | 是 |  |  | Lua 注册表，不向引擎注册 |
| 自然 TTL | 是 |  |  | Lua 自行过期 |
| `RemoveAvoidanceZone` | 是 |  |  | 只使用短 TTL，不手动移除 |
| `GeneratePath` 空区域 | 是 |  |  | Lua 候选绕行点 |
| `GeneratePath` 自定义区域 | 是 |  |  | Lua 线段/圆几何避让 |
| `Action_MovePath` | 是 |  |  | 逐 waypoint `Action_MoveToLocation` |
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
Avoidance.DETECT_DANGERS = false
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
  → USE_NATIVE_ZONES
  → USE_NATIVE_REMOVE
  → USE_NATIVE_PATH
  → EXECUTE_NATIVE_PATH
  → DETECT_DANGERS
  → ENABLED
```

任一阶段失败，只关闭当前层和其后所有层。不得用删除 Lua 注册表的方式回滚，因为注册表是后续纯 Lua 回退的基础。

## 12. 每阶段交接模板

后续开发完成一个阶段后，在本节末尾追加一条记录：

```text
### YYYY-MM-DD / Phase N / run=<ID>

状态：静态通过 | 实机通过 | 阻塞

变更文件：
- path/to/file.lua

静态证据：
- luac -p：
- mocks：
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

## 13. 完成定义

本项目只有同时达到以下条件才算完成：

- `GetAvoidanceZones()` 在生产源码和运行时镜像中保持零调用。
- Lua 区域注册表是危险状态的唯一事实来源。
- 当前构建下可用的原生能力已经逐项验证并记录；不可用能力有明确、已测试的降级路线。
- Bot 能在至少一个真实 THD 持续圆形危险中识别区域、取得动作所有权、绕行并恢复原行为。
- 起点在区域内、目标在区域内、重叠区域、路径失败、区域过期和旧回调均有测试覆盖。
- 单 Bot 和五 Bot 场景均无明显动作抖动或区域重复泄漏。
- 静态验证、镜像一致性、全新对局和 dump 结果分别记录。
- 所有适用且已解锁阶段均达到“实机通过”；被禁用的原生分支明确标记为“不适用”，没有通过跳过失败门禁完成后续阶段。
