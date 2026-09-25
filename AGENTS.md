# Bannerlord Mod 工程记忆

这是 Chronicle Framework 的本体与开发工作区。

## 必须遵守

- 遇到问题先检查工具、启动器、版本、模块清单、测试器和证据链，再修改 Mod 功能代码。
- 工具本应避免但仍发生的问题，要修工具并加入回归验证，不能只给功能代码打补丁。
- 用户提出的技术路径、平台类比或实现假设都只能视为待验证输入；不得因为用户这样描述就直接把它写成架构结论。
- 技术方案、可行性、成本、依赖和替代路径由 AI 独立论证并负责把关；若用户的技术假设不成立，必须明确纠正，不以服从性替代理性。
- 用户的设计目标和体验标准具有优先权，但不等于用户对实现机制的判断具有真理地位。
- [ResearchFirstGate] 新阶段/新能力在方案或代码前，必须先在现有 MAINLINE 记录：用户目标与验收、完整行为/观察面清单及分母、当前实现覆盖、当下主源与版本/日期、参考项目的类型/成熟度/适用与不适用处、替代方案和未知项、通用复用价值、可重复测试。只记起几个熟悉案例不算全景；分母未知时标 BLOCKED/盘点中，不选实现路线。Research gate 非 READY 不得写新游戏功能；验证目标不能变成交付指标，不为通过它堆一次性能力。
- [DecisionGate] 重大方案/工程判断按序检查：先问最可能改变答案的问题；界定真实问题；预演三种失败原因；列出标准答案及其缺陷；反查能推翻当前判断的变量；分开事实、推断、未知并说明改判证据；最后只给一个按目标/限制/代价选出的结论。无需把七项机械打印，但问题若真的会改变决策，先向用户确认，不用猜测填空。
- [MechanicGate] 实现任何原版玩家动作前，必须先在现有 `Focus/MAINLINE.md` 的“原版机制契约”记录：玩家实际入口/按键修饰、原版自然状态变化、Campaign 时间模式如何流动、直接 API 与 UI handler 的差别、当前证据和未知项。不得从 API 名称、其他游戏经验或想当然推导玩家体验。
- [ClockPolicy] 时间流动与地图/菜单动作分开建模：若原版时间模式正在运行，世界会自然推进；仅在明确的时间控制/固定步进或 Harness 需要确定性时调用时钟控制。移动、追近、进入定居点等动作不得为了让测试快结束而暗中强制快进或暂停；任何宏动作都须显式标记为 Harness/Agent Host 策略，不得冒充原版玩家动作。
- [ProgressMetrics] GitHub Project是唯一工作项状态源；领域/行为分母与可重复验收定义在 `Focus/MAINLINE.md`，单次运行结果和可计算的通过/失败数在本地 `TestResults`。不能把命令次数或验证夹具通过率当作Agent自主能力。
- [ProductTaskScope] GitHub Project只列直接形成Chronicle项目内容/成果的事项：Bannerlord系统研究、玩法设计、Mod能力与面向玩家的验收。Agent/Harness/文档/流程的内部结构维护不是产品任务，必要时直接维护、测试并提交，不创建路线图Issue或用其充当阶段产出；仅在用户明确要求把基础设施本身作为交付物时例外。
- [HarnessBoundary] GitHub Issues/Projects只管任务、依赖和协作状态；Git只管代码历史；本地Harness只管游戏/工具环境、可重复测试和原始运行收据；Agent负责研究、判断、目标分解和异常后的下一步。Harness不读取或镜像项目板，也不需登录GitHub即可测试。不得在Markdown复制动态任务状态。
- 静态源码无法判明交互链时，先追到 UI 入口、输入修饰与副作用；仍无法验证且会改变实现的玩家体验事实时，向用户提出一个具体、最小的问题，不得先选架构再补解释。
- 不把“能启动”“能进主菜单”“加载 DLL”“进入战役”“行为已触发”当成同一个结论。
- 所有功能变更必须经过 `Dev/ChronicleFramework/Run-Harness.ps1` 对应阶段；没有自动证据就标记为未验证。
- 不修改正式存档进行测试；使用 disposable save 和带时间戳的证据目录。
- Computer Use 只作为 UI 适配层，不能替代日志、遥测、存档和结构化断言。
- 当前优先做原版增强/优化；任何新系统都必须先证明原版接口无法满足目标。
- [ValidationTargetPolicy] P 阶段中的存档目标/验收场景是验证 Agent 通用能力的夹具，不是产品目的或必须达成的交付承诺。不得为通过单一目标临时堆叠一次性功能；只有能沉淀为通用感知、决策、动作或恢复能力且符合产品主线的改动才实施。若当前能力不足，保留失败证据并标明缺口，不为“过关”改目标或强行绕过原版流程。
- [PlainLanguageHandoff] 每次完成一项工作后，用用户无需编程背景也能理解的大白话说明改了什么、对项目/用户有什么影响、如何验证、什么还没做；主动解释容易误读的术语和状态（例如Blocked表示等待前置事项，不等于程序出错）。不要用命令和工程行话代替结果汇报，也不要默认用户与Agent工程认知对等。
- 文档过时视为工程缺陷；每次任务开始先运行 `Run-Harness.ps1 -Phase Docs`。
- 修改 harness、工具链或验收规则时，必须同步更新对应文档并提升 harness contract version。
- 文档必须按 ContextState 分层：当前主线只读 `Focus/MAINLINE.md`，稳定事实按标签读取，Archive 默认不读。
- 主线改变时先更新 `ContextState.json` 和 `Focus/MAINLINE.md`，再处理旧材料；不能让旧主线继续留在默认上下文。
- 主线完成或切换使用 `Complete-ContextFocus.ps1`，默认删除旧主线，只有明确需要追溯时才归档。
- 禁止用新增 Markdown 代替维护现有事实源；`Check-Docs.ps1` 强制唯一主线、复核期限、hash、文档路由和默认读取层级，文档字节数只作诊断而非硬上限。

## 每次任务启动

- 读取 `ContextState.json` 与 `Get-ContextPack.ps1` 输出；默认只加载工程契约和当前技术焦点。
- 从GitHub Project检查当前 `In Progress` 工作项、原生依赖及验收；不要假定上次会话的活动事项仍然有效。一次最多启动一个工作项；若没有活动事项，选择一个已解除依赖且符合当前焦点的事项后再开始。
- 项目卡状态按统一约定使用：Todo=未开始（阻塞看原生依赖），In Progress=唯一当前工作，Done=验收达成且有commit/结果摘要。父项维护共用验收，子项只维护独有范围。
- GitHub任务卡是执行清单和状态；不再把活动Issue、已完成域数或阶段状态抄入 `ContextState.json`、`MAINLINE.md` 或 Harness结果。

## 按任务读取

- `DEVELOPMENT.md` 与 `Focus/MAINLINE.md` 是默认上下文；详细机制事实通过 `SYSTEM_INVENTORY.md` 路由到对应Research文档。
- 只有设计/方案任务才读取 `DESIGN.md`；只有系统盘点任务才读取 `SYSTEM_INVENTORY.md` 和对应Research文件；普通代码/Harness任务不加载整份系统清单或无关Research。
- 只读取 `SYSTEM_INVENTORY.md` 路由到的目标系统研究文件；不要为普通任务加载全部 `Research/`。
- Research 文档按清晰的系统/主题维护；主题自然分化时允许拆分多份，不得为满足任意字数上限而极端压缩。每份文档必须在 `ContextState.json` 中分层路由，并由 `SYSTEM_INVENTORY.md` 指向；过时材料应更新、删除或移入默认不读取的 Archive。
- Agent Bridge任务以 `Dev/ChronicleFramework/Focus/MAINLINE.md` 为技术事实源。
- 关系/身份任务读取 `Dev/ChronicleFramework/Research/B/WorldEntitiesIdentity.md`，跨系统时再读取 C、F、J 对应文件。

当前已验证的默认入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Dev\ChronicleFramework\Run-Harness.ps1 -Phase All
```

任务状态只看GitHub Project；源码差异只看Git；当前单次测试收据看 `Dev/ChronicleFramework/TestResults/latest.json`；长期机制事实和验收定义看 `Focus/MAINLINE.md`。GitHub Project只在Agent开始/结束工作项时读取或更新，Harness运行阶段完全本地化。
