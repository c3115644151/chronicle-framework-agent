# Chronicle Framework 开发与 Harness 契约

Contract version: 4.84

## 目标与边界

Chronicle 当前服务两个目标：

1. 建立可无人值守验证 Bannerlord Mod 的本地 Harness；
2. 在充分拆解原版系统后实施原版增强/优化。

Campaign Agent Bridge 是验证基础设施，不是新玩法。它负责把战役层变成可观察、可控制、可恢复和可评测的环境；关系、长期目标和叙事优化仍必须先进入 `SYSTEM_INVENTORY.md` 对应研究，再由双方确认后写入 `DESIGN.md`。

## 单一事实来源

工程只维护三份根级人工文档：

| 文件 | 唯一职责 |
| --- | --- |
| `DEVELOPMENT.md` | 工程事实、Harness 契约、工具链、验收与维护规则 |
| `DESIGN.md` | 双方确认、准备实施的功能清单 |
| `SYSTEM_INVENTORY.md` | 原版系统总清单与研究路由 |

GitHub Project 是工作项、原生依赖、状态的唯一事实源，最多一个 `In Progress` 卡片。Git是代码及其历史的唯一事实源。`Focus/MAINLINE.md` 保存长期有效的工程目标、机制契约、技术事实、未知项、覆盖分母和验收定义，不保存活动Issue、完成数或单次测试快照。`ContextState.json` 是上下文路由器，只保存当前技术焦点路径、hash/复核元数据、默认读取层和按需Research路由；项目目标、当前阶段和Issue状态不在其中重复。`TestResults/latest.json` 仅代表本机最近一次Harness运行及其commit/脏树信息。每个 `Research/<类别>/` 只维护一份权威文档并按需加载，由`ContextState.json`和`SYSTEM_INVENTORY.md`路由；某类首次进入W1研究且无文档时，创建并路由有实际内容的类别文档属于该域研究交付，不预建空文档或流程任务，拆分已有类别文档才需用户确认。`Archive/`默认不读。

GitHub 与 Harness 不互相替代：GitHub Issues/Projects 管理工作项、原生依赖、评审和协作状态；Git记录可审查的源代码历史；本机Harness探测安装的游戏版本/模组、编译并启动游戏、操作disposable fixture、采集崩溃与结构化断言；Agent负责解释目标、研究机制、选择下一步和处理未覆盖异常。这四者之间不复制状态。Harness只输出本次运行的commit、工作树状态和测试收据，不查询或更改GitHub，也不因GitHub未登录/离线而失效。运行收据以run ID保存在本地`TestResults/<run-id>`并由`latest.json`指向最近一次；Agent在工作项达到验收时，将相关commit与简洁测试结论回填到GitHub Issue。大型日志、存档与视频不自动上传或塞进Issue。

Project采用最少任务状态：`Todo`表示尚未开始（是否被阻塞看Issue原生dependency关系），`In Progress`表示唯一当前工作（最多一项），`Done`表示验收标准已满足且Issue附有commit/结果摘要。任务清单只记录本项目内容工作（原版系统研究、玩法设计、Mod能力和面向玩家的验收）；纯Agent/Harness/文档/流程重构是内部维护，不作为产品里程碑或任务卡计数。W1用一个父Issue持有跨域审计和退出标准，子Issue只写独有的系统范围；W2-W8由原生Issue dependencies排序，标题前缀提供阶段标识，不再维护重复的自定义Phase/Gate字段。

任务工作流由Agent在明确边界点同步，而非由Harness轮询：开始前从Project确认唯一活动Issue、依赖及验收；仅执行该Issue范围；本地Harness验证并记录commit/测试证据；只有验收条件满足时，Agent才更新Issue为Done并附上commit与结果摘要。暂缓、阻塞或范围变化直接更新对应Issue/依赖，不另开状态文档。没有活动Issue时，Agent选择可执行且依赖已解除的下一项后再开始。

源码仓库位于 Bannerlord 安装目录之外；游戏目录只作为 Harness 的运行时目标。被Git忽略的 `harness.local.json` 仅保存本机仓库与游戏路径；GitHub任务板位置只在 `ContextState.json` 记录一次。新工作区用 `Initialize-ChronicleWorkspace.ps1` 生成本地路径设置。源码、模块清单、Harness和工程规则均由同一Git提交追踪；构建将版本化模块清单与DLL部署到本机 `Modules/ChronicleFramework`。大型`TestResults`不提交Git，证据仍按运行号保留在本地。

文档管理优先保证可读性和信息层级，不以总字数或文件总数强迫压缩。`Check-Docs.ps1` 强制的是文档均有明确路由、引用目标存在、主线唯一且复核/hash有效；总文档字节数和默认读取集合的大小只作诊断数据。主题过长时先按概念边界拆分并调整路由；过时内容应修订、删除或移入默认不读取的 Archive，不得为了塞进一个任意容量而写成密文。

禁止新增 README、Harness 说明、工具链说明、验证报告、状态记录或索引 Markdown。当前项目完成或主线改变时，默认删除旧 `MAINLINE.md` 内容；只有仍具长期追溯价值时才移入 `Archive/`。Archive 不得进入默认上下文。

## 原版机制假设门禁 / Original Mechanic Assumption Gate

任何会模拟玩家输入、改变 Campaign 状态或推进时间的实现，先在唯一 `Focus/MAINLINE.md` 的“原版机制契约”补一行，再写代码。每行必须分清：

1. 玩家实际入口和输入修饰（普通点击、按住某键、菜单项、TAB 屏幕等）；
2. 原版命令造成的自然世界状态变化；
3. 当前 Campaign 时间档位与动作的关系；
4. UI/input handler 相比直接调用原版 API 额外做了什么；
5. 事实来源、运行证据和未知项。

实现前追当前版本玩家入口；反编译出 setter 不等于复现操作。Campaign 时间运行时自然推进，原版地图点击可调档；移动不得暗藏快进/暂停。仅对影响实现且源码未知的玩法事实询问用户。

这不是新增文档：在既有 MAINLINE 契约表中维护事实。`Check-Docs.ps1` 检查契约表、必需字段和当前实现动作是否都有记录；实现范围改变时同步维护该表与 Harness contract version。PowerShell 读取 AGENTS/Markdown/JSON 权威文件时必须显式 UTF-8，中文规则门禁不得依赖系统默认代码页。MAINLINE维护分母定义与验收规则，GitHub维护任务状态，`TestResults`维护单次运行结果；不以动作数量替代自主决策闭环进度。

## 研究就绪门槛

`Focus/MAINLINE.md` 的 Research Gate 未就绪时，不实现新的游戏能力。就绪依据是玩家真实入口与相关观察/行为范围已研究到足以界定覆盖分母，而不是列出多少熟悉案例。纯Harness诊断维护不等于新游戏能力；若修改受精确hash保护的诊断代码，只限已审阅的 `SubModule.cs` 异常清理/存档调度实验，不得改变原版玩法。

## 当前版本事实

- 当前可见客户端为 `v1.4.8.119303`。
- 先前 `v1.5.3` 结论来自不同本体状态，不能直接作为当前 API 契约。
- 根目录 `package_info.txt` 不是可靠运行版本来源；以当前官方模块、运行日志和本机 DLL 为准。
- 当前阶段必须重新运行 API Probe、Build、Smoke 和干净战役夹具，旧 PID、旧日志和旧存档只算历史证据。
- 正式整合包模块集、Chronicle 最小模块集和官方基线必须分别记录，不能互相替代。

## 开发入口

默认入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Dev\ChronicleFramework\Run-Harness.ps1 -Phase All
```

按需阶段以同一命令加单个 `-Phase` 运行；可选 Docs、Preflight、Api、Build、Smoke、Campaign、FreshCampaign、FreshCampaignProgression、Protocol、AgentLoop、BattleFixture、PostBattle、Observation、Movement、Recruitment、Rest、Pursuit、VisualCapture、All。

`Run-Harness.ps1` 顺序执行阶段、首错停止、把原始输出和 JSON 写入 `TestResults/<run-id>`，并更新 `TestResults/latest.json`。

Provider loop 输入观察及上一动作原始回执，再执行 allowlist 动作并复观察；`advance` 仅 Harness 可用。Test provider 不代表 LLM。CLI 需 state 握手；stop 清理进程树/队列。对话与战斗控制分开。

每次 Harness 将 MSBuild/`Add-Type` 临时文件定向到 `TestResults/<run-id>/Temp`；项目排除 `TestResults/**/*.cs`，防止反编译研究源码污染 Mod Build。

## Harness 架构

职责按事实来源划分，不复制状态：GitHub 项目板回答“做什么/顺序/当前工作项/是否被依赖阻塞”；Git回答“代码变成了什么”；Harness回答“本机游戏与工具实际上发生了什么”；Agent决策层回答“基于证据下一步做什么”。Harness输出不能覆盖GitHub卡片状态，也不能把测试指标当作产品自主能力；Harness不调用GitHub API/CLI。

```text
CLI / Computer Use 启动适配
            ↓
进程、模块集与 disposable save
            ↓
Mod 内状态、命令与事件遥测
            ↓
结构化断言、日志、检查点和 A/B
```

适配器优先级：

1. 原生 CLI/API；
2. 进程、日志和存档；
3. Mod 内遥测与白名单命令；
4. Computer Use 回退。

Computer Use 可创建一次性夹具、处理菜单和已分类弹窗，但不能作为功能真值。截图只能做诊断附件。

## 统一状态与动作

状态至少包含：

```json
{
  "contractVersion": "...",
  "runId": "...",
  "processId": 0,
  "gameVersion": "...",
  "moduleSet": [],
  "screen": "title|campaign|map|menu|error|unknown",
  "campaignTime": null,
  "saveName": null,
  "lastCommand": null,
  "lastEvent": null,
  "lastError": null,
  "timestampUtc": "..."
}
```

环境动作目标为：

```text
start(modules, launcher)
load(save)
observe()
advance(hours|days)
pause()/resume()
save(name)
stop()
```

每个动作必须有命令 ID、前置条件、完成证据、超时、中断、失败分类和幂等边界。命令送达不等于动作成功，动作后必须重新观察。

时间模式运行时世界自然推进；移动不补发 `advance`。地图点击副作用和 WaitMenu 自管时钟按原版复现。`advance/pause/resume` 仅显式 Harness 时钟工具，不嵌入普通动作。

## 验收阶梯

| 层级 | 必须证明 | 自动证据 |
| --- | --- | --- |
| Docs | 文档路由、主线层级、引用/hash/复核和契约一致 | `Check-Docs.ps1`；Harness收据另记Git commit/脏树 |
| Preflight | 本体、项目、清单和工具存在 | JSON 清单 |
| Api | 当前 DLL 存在目标签名 | API Probe 输出 |
| Build | 项目针对当前 DLL 编译 | 构建退出码和 DLL |
| Smoke | 清单、DLL、`OnSubModuleLoad`、`Finished All` | 同 PID 日志 |
| Campaign/FreshCampaign | 旧档；FreshCampaign新Sandbox原生创建、跳intro、选+20；Progression用临时存档重载再move/arrival/recruit | 同PID renown20/MapState、非激活840x472；仅对未进游戏的Crash Report启动失败重试一次；临时存档精确清理、非模型Provider |
| Protocol | CLI 启动/重载、状态、暂停/恢复、独立推进时钟、保存、停止；推进到目标时间或遭遇边界即返回 | 每命令不可变回执、JSONL 轨迹与存档回读；时间步进不得隐式塞入地图移动/追近命令 |
| AgentLoop | 外部提供者接收真实观察，选择 allowlisted 原子动作并重观察 | 测试输入/决策/回执、时钟转换、拒绝越权动作、fixture 哈希、退出；不计作模型能力 |
| BattleFixture | disposable save 内造 hostile looter；用原版 pursue 点击语义接敌 | hostile/party ID、自然时间/encounter 回执、fixture 哈希、进程退出；造敌非 Agent 行为 |
| BattleSimulation | 原版 `Send troops` 启动；pause/skip/finish/retreat；Mission TAB retreat | 模拟状态、结算/loot、Mission end、fixture hash；不等同即时战斗 |
| PostBattle | Simulation skip/finish→encounter leave→PartyState transfers→conditional InventoryState loot/Done→MapState | troop/item counts, state timeline screenshots, fixture hash, process cleanup |
| VisualCapture | 引擎单帧参考图 + 按 Bannerlord HWND 连续采集 30fps；只验证采集链，不是玩法真值 | MP4/contact sheet、帧覆盖率、fixture hash、进程清理；不录全桌面，不进默认 All |
| Conversation | 观察原版句/选项；`DoOption/ContinueConversation` 需满足原生条件 | 选项/回执/菜单迁移；不预测未开放选项 |
| Observation | 玩家身份、队伍、资源、坐标、移动模式/目标、上下文、附近实体与其移动/定居状态、任务与危险；记录数据来源、原版可见/侦察标记和所采用的情报策略 | 两次暂停快照、稳定 ID/位置、字段新鲜度和 fixture 哈希 |
| Movement | 依据目标聚落 ID 下达原版路径目标，并复现普通地图单击的时间档位规则；Harness 独立步进时间至目标聚落 | 目标/菜单/离开状态、MapScreen 等价时间模式、每步时间证据、失败输入拒绝、fixture 哈希 |
| Recruitment | 调用本体招募 ViewModel，按指定 owner/troop/slot 招募；用原版 InventoryLogic 完成买入、卖出和食品补给往返 | 实际 roster、双方库存与金币差额；无效报价不改状态；fixture 哈希 |
| Rest | 通过原版 `town_wait` 进入 native Wait menu（`StartWait` 自行启动时间），观察指定时长后由原版 `wait_leave/EndWait` 退出 | Wait menu/time mode、native 持续时长、离开后 Stop、非法/中断路径和 fixture 哈希 |
| Pursuit | 在大地图给当前可见且可导航的移动队伍下达原版 `EngageParty` 目标，并复现普通地图单击时间档位规则；`hold` 复现点击玩家队伍 | 正确 TargetParty/DefaultBehavior、native click time mode、自然前进到遭遇或目标丢失 Hold、无效目标不改状态、fixture 哈希 |
| Event | 事件按预期且不重复 | 带时间和 PID 的遥测 |
| Save | 自定义状态保存并恢复 | 保存前后结构化快照 |
| World | 原版行为只发生目标变化 | 同夹具 A/B 对照 |

“启动”“主菜单”“加载 DLL”“进入战役”“事件触发”“存档恢复”是不同命题。没有对应层证据只能标记为未验证。

## 原版增强测试

```text
同一 disposable save + 基线模块集
        ↓
记录行为与状态
        ↓
同一存档副本 + Chronicle
        ↓
记录候选结果
        ↓
断言只有目标语义变化
```

一次变更只推进一个验收层或一个消费者。新 API 先 Probe；行为代码先只读；写入原版状态前必须有基线、回滚和回归测试。

## 长时间运行与恢复

- 使用检查点推进，不进行一次性盲等；
- 每个检查点保存状态、最后命令、事件计数、进程健康和 disposable save；
- 异常立即保存最后证据并停止；
- 最多进行一次自动恢复，重复确定性故障转入模块二分或代码定位；
- 测试器主动结束进程不算崩溃；
- 任何正式存档都不得被测试器覆盖。
- Smoke 必须按本次启动新增的诊断行和实际 Bannerlord 子进程 PID 归因；不得用启动器返回 PID 或旧日志推断模块生命周期。
- Campaign 阶段必须使用版本化 disposable fixture；第一轮通过必须包含 `campaign-sync mode=save`、每日事件、另存文件、第二进程 `campaign-sync mode=load` 和未改动 fixture 哈希。
- ButterLib DLL 报告含托管栈/模块及可选 MiniDump；Harness 在报告 UI 阻塞前复制异常栈与 MBMusicManager/CampaignMusic 状态。FreshCampaign 等 native music 初始化后再开档；progression skip flag 到 MapState 后不再调用 Issue probe。保留fault-IP映射/关键帧，不点报告窗。
- ButterLib 当前回退到 1.4.7 implementation；同样回退见通过的 `Fresh 215022`，是兼容风险但不是本次根因证据。
- Progression `045339` deterministic provider 验证 Fresh→CampaignTick SaveAs/CLI load→移动→招募1人；保留回执与费用前后值，并确认临时存档清理、原存档哈希未变。
- FreshCampaign日志尾投影DTO，禁直序列化Get-Content。
- P2 原子 JSON；`captureFrame` 仅 visual Harness 可用且输出 BMP。FFmpeg `gfxcapture(hwnd=...)` 只采游戏窗；校验覆盖率并生成状态/动作 JSONL、缩略图和关键帧。成功删 MP4，失败留片；Agent 按索引看图。Loot All/Done 限原生 InventoryState，seedVisualLoot 不代表自然掉落。
- Progression证据保留初始Renown、招募回执/净变化、存档周期验证；清理后存档哈希不变。
- Protocol 若暂时无法读取 `.processing` 命令，保留 claim 并延迟重试，不删失/丢弃命令；Docs 检查此恢复契约。
- 自动启动用本体 `DisplayMode_0`，840×472 无抢焦点置左上；结构化断言坐标/尺寸，禁止把 `DisplayMode_2` 当窗口模式。
- P3 快照来自 Campaign API；schema 8 含战后 InventoryState、双方 item 数量及遭遇待领取 item 数。回执按 UTF-8 读写。
- P3 分开记录 `IsVisible`/`IsInspected`，不从属性名推断玩家认知。情报策略由产品设计确定；静态面板按需读取。
- P4 `move/pursue/hold` 复现原版目标 setter 与 MapScreen 点击时钟副作用；运行时间自然推进。无效聚落拒绝，抵达以 `CurrentSettlement` 为准；`rest` 只观察原版 WaitMenu 的 `StartWait/EndWait` 时钟。
- 聚落移动的标准夹具还要验证抵达后状态切到目标聚落及原版 `town` 菜单；结构化菜单选项按当前 `GameMenuOption.GetConditionsHold` 计算可用性，选择时重验菜单 ID、选项 ID 与 enabled 条件。离开选项作为菜单原语验收；失败夹具对无效 settlement ID 返回结构化拒绝，且世界位置不变。
- 招募必须复用本体 `RecruitmentVM` 的志愿者列表、队伍上限和金钱条件；命令显式指定可用 owner、troop 与 volunteer slot，每次只招募一个。完成以兵力 `+1`、金币按本体价格扣除且来源 volunteer 槽清空为准。
- 食物补给必须经城镇 `InventoryLogic` 交易和 `InventoryListener` 提交市场库存与金币变化；不直接改 roster。动作前检查食品类别、市场库存、交易价格、金币和载重，动作后验证食品库存增长与金币差额。
- 普通交易要分别测试买入与卖出：按原版市场价格执行 `OtherInventory ↔ PlayerInventory` 交易；验收双方库存变化、金币净差和失败无状态变更。仅读市场报价时不应 Push 可视 `InventoryState`；实际购买也应避免无目的地短暂弹出全屏界面。
- 定居点等待通过原版城镇菜单进入 Wait menu；`GameMenu.SwitchToMenu` 调 `StartWait` 原生启动时间，`wait_leave` 的 `EndWait` 原生停止。`rest(days)` 只观察原版等待时钟达到目标，不能写 `TimeControlMode`；离开等待菜单后的 rest 请求必须拒绝且不改世界状态；`Agent-Cli.ps1 -ReturnWhenAccepted` 用于串行发出后续中断动作。
- 休整验收以 `town_wait_menus → town` 菜单迁移为离开依据。当前 v1.4.8 运行中，返回 `town` 后 `Campaign.IsMainPartyWaiting` 仍为 true；记录此事实并单独核对 API 语义/生命周期，不将属性名直觉作为对功能成功与否的推断。
- UI/VM 验证必须区分“从玩家界面入口走通”和“直接调用相同 VM/逻辑事务”。二者都是真实本体行为，但报告不能互相替代。
- 启动游戏前先告知本轮测试目的、预期界面、是否会打开可视菜单/交易屏幕及主要断言；结束后列出实际执行的入口、结果、证据文件和未覆盖部分。避免 UI 一闪而过却没有可解释的上下文。

## 工具链

| 工具 | 用途 | 采用边界 |
| --- | --- | --- |
| .NET SDK | 编译、探针和辅助工具 | 以本机 DLL 和项目锁定配置为准 |
| PowerShell | 编排、日志、进程和证据 | 不承担游戏状态真值 |
| ILSpy CLI | 只读调用链分析 | 反编译实现不是稳定 API |
| BLSE Standalone | disposable save 自动读档 | 不接管正式存档和模块排序 |
| Bannerlord.Templates | 新模块结构对照 | 当前项目不因模板存在而迁移 |
| Computer Use | UI 回退与一次性初始化 | 不替代遥测、日志和断言 |

不让中文站管理器、官方启动器和 BLSE 同时修改同一模块排序；不直接改官方 DLL；Harmony 只有在公开接口不足且已有 A/B 证据时才进入方案。

## 问题归因顺序

先查 Harness，再查启动器/版本/模块集与生命周期，最后核实战役行为；只有故障证据落在功能层才改功能代码。

工具本应避免却仍然发生的问题必须修工具并增加回归，不能只为功能代码加延时、try/catch 或补丁。

## 技术决策权

产品体验是需求；机制判断和技术建议待验证。用当前源码/运行证据核实，并据此比较成本、风险、替代方案；证据冲突时直说。

## 文档维护契约

- 始终只有一个 `Focus/MAINLINE.md`；它维护技术焦点，不记录当前Issue、域完成数或项目阶段状态。工作项状态仅由GitHub Project声明。
- `ContextState.json` 只路由当前MAINLINE、文档默认层、按需Research和复核/hash元数据；不得加入任务ID、活动Issue、阶段或完成百分比。
- MAINLINE焦点改变时直接维护该文件，再运行 `Set-ContextFocus.ps1 -Review` 更新review日期和hash；它不接受或存储任务目标/阶段参数。
- 主线完成或主题切换必须使用 `Complete-ContextFocus.ps1` 原子执行“删除/归档旧MAINLINE + 写入新技术焦点 + 更新路由元数据”；任务Issue另在GitHub关闭或更新，两边不互相复制状态。
- `Get-ContextPack.ps1` 默认只返回Development Contract + Active Focus；`DESIGN.md`仅设计任务读取，`SYSTEM_INVENTORY.md`与Research仅盘点任务按路由加载，Archive只有显式请求才返回。
- `Check-Docs.ps1` 检查层级、唯一主线、hash、复核期限、Reference 单文件规则以及 Archive 不进入默认读取列表。
- 文档内容过时直接修改权威段落，不新增“新版”“补充”文件。
- 删除、移动或归档文档时同步修正 `ContextState.json`、根 `AGENTS.md` 和 Docs 检查。
- Harness、验收、工具链或文档拓扑变化时提升 contract version。
- 启动重试只认明确崩溃；RGL存在不等于崩溃。Progression留故障摘要；PostBattle夹具读取并校验奖励遥测，不改结算。
- Harness入口只接收本地游戏路径和仓库路径；不需要GitHub授权、配置、网络或Project字段。
- 每次修改后运行相关Harness阶段；Docs检查文档路由/技术门禁，`TestResults/latest.json`只表示最新本地收据。项目板状态只在Agent开始/结束工作项时更新。

## 当前执行焦点

`ContextState.json.current.path`只定位当前技术焦点；GitHub Project及活动Issue决定工作项和执行次序；`Focus/MAINLINE.md`保存跨任务有效的技术约束、机制事实和研究门槛。不得从单个来源推导另外两个来源的动态状态。
