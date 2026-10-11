# Chronicle Framework 开发与 Harness 契约
- `settlementOverlayCharacters`是schema 21中的有限视图，只在Settlement Characters overlay当前可见时按本体`MenuLocations + HeroAgentLocationModel.WillBeListedInOverlay`生成，并携带玩家Overlay显示的Issue/Quest标记。用户确认聚落人物与地图贵族领主名旁都有蓝色委托标记；W2-AU将Native Party Nameplate的类别补到`mapPartyTargets`，不暴露全局Issue/Quest清单，并由临时Native Issue与引擎帧验证`AvailableIssue`。`talkToSettlementHero(HeroId)`经QuickTalkPermission和CampaignMapConversation作地图快速“交谈”；`visitSettlementHero(HeroId)`经Visit permission进入NPC的Location Mission。W2-D运行`TestResults/20261001-101331`验证QuickTalk返回原Village菜单/MapState，`20261001-095934`验证Visit进入目标Mission；二者不可混称。两者都只接受本轮可见overlay名单，不用Harness全场景Notable诊断里的隐藏ID。
Contract version: 7.127

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

源码仓库位于 Bannerlord 安装目录之外；游戏目录只作为 Harness 的运行时目标。被Git忽略的 `harness.local.json` 仅保存本机仓库与游戏路径；GitHub任务板位置只在 `ContextState.json` 记录一次。新工作区用 `Initialize-ChronicleWorkspace.ps1` 生成本地路径设置。源码、模块清单、Harness和工程规则均由同一Git提交追踪；构建将版本化模块清单与DLL部署到本机 `Modules/ChronicleFramework`。Build阶段部署前检查`Bannerlord*`进程；若用户游戏已运行则明确拒绝，Harness不终止该进程也不覆盖正在加载的DLL。大型`TestResults`不提交Git，证据仍按运行号保留在本地。

文档管理优先保证可读性和信息层级，不以总字数或文件总数强迫压缩。`Check-Docs.ps1` 强制内容文档明确路由、引用目标存在、主线唯一且复核/hash有效；根目录`AGENTS.md`是直接生效的工作规则，不属于内容文档路由，也不应加入`ContextState.json`或`SYSTEM_INVENTORY.md`。检查器会验证 SYSTEM_INVENTORY 的126个A-L系统各自至少落到一个显式OBS/ACT/N/A目录行、每条目录记录在来源列引用有效A-L系统编号且全体覆盖126个编号、观察/行为/N/A目录ID唯一且所有交叉引用都有定义；同时按目录中显式标注的特权ACT分类，核对Mainline声明的ACT总量/核心分母，避免目录增删后分母脱节。Docs收据记录当前目录行结构计数，供同一分母口径下比较版本变化；这些计数不代表已核实的玩家行为最终分母。系统本身不是行为分母；有真实原因无玩家入口的引擎项必须用带研究来源的N/A行表示。总文档字节数和默认读取集合的大小只作诊断数据。主题过长时先按概念边界拆分并调整路由；过时内容应修订、删除或移入默认不读取的 Archive，不得为了塞进一个任意容量而写成密文。

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

`MissionLeave`验收使用一次性Campaign夹具经Town菜单进入真实Location Mission，先保存引擎帧，再用一个限时Mission专属`IInputContext`让本场景的`Mission.Tick`读到Leave Area game key处于按住状态；它继续走原版`Mission.OnEndMissionRequest`、MissionLogic veto/Inquiry与Mission计时，不直接调用`Mission.EndMission`，也不发送OS全局键鼠事件。测试等待真实Mission→Campaign MapState和原Settlement菜单，并保留前后引擎帧/时钟/存档哈希/清理收据。该测试已加入`All`：当前实测证明了Sargot TownCenter路径，不等于所有Town/Village/Tavern和其他Mission条件都已覆盖。用户当前键鼠实测长按Tab约两秒，但产品代码虚拟的是Native Leave Area game action，不硬编码物理键位。

Harness启动Native游戏客户端前先确认Steam Client和Steam WebHelper都稳定运行；若Steam未运行，仅从本机安装目录用`-silent`启动，不发送账号凭据/全局键鼠，并等待WebHelper进程集合稳定5秒后才启动Bannerlord。这样避免只看到`steam.exe`进程就过早启动游戏。若启动需要登录，或Bannerlord仍弹`Unable to initialize Steam API`警告，则失败收据保留目标窗口控件内容，不自动点确认、不伪装为Mod/存档兼容故障。启动还会把`engine_config.txt`里的`max_framerate`临时限制为30，并使用已核验的840×472非激活窗口布局；该配置快照放在Agent运行目录，Stop后恢复；在 visual-capture 模式下，1.4.8 `MapScreen.OnGameWindowFocusChange`会在非激活窗口自动打开Escape菜单，Harness通过Harness-only Harmony前缀抑制该自动Overlay并在地图操作前断言Map/Escape菜单未挡输入；普通游戏行为与Agent白名单不变。（保留`safely_exited=1`安全退出标志）。若测试中异常退出，后续安全启动会先恢复遗留快照；无Bannerlord进程时也可显式运行`Agent-Cli.ps1 recoverTestConfig`恢复一次性快照；游戏进程仍在时绝不覆盖配置。这样减少测试渲染负载但不把低画质设置留给玩家日常游戏。启动等待只读取Chronicle日志新追加的字节，不再每250毫秒重复解析整份日志；若协议未就绪，`startup-timeout-<pid>.json`记录Window Title、Steam状态、增量Chronicle遥测、RGL/watchdog末尾和弹窗快照。UI Automation返回的窗口/控件代理必须先投影为纯文本/数值字段再写收据，避免序列化卡住；未知警告不被假定为崩溃，也不自动确认。

若Bannerlord已加载模块但未达到Campaign协议就超时，Agent-Cli会在清理进程前保留`startup-timeout-<pid>.json`：窗口标题/句柄、进程是否仍在及CPU秒数、当次Chronicle启动遥测、RGL错误日志/watchdog尾部、已确认的启动弹窗回执和待恢复配置标志。该失败只能判作“协议未就绪”；若日志没有故障信号，不宣称崩溃或兼容性根因。下次安全启动恢复未完成的配置快照。

`VillageToolsDelivery`是W2-AI单项端到端Harness阶段：至多320轮内由确定性Provider只看本轮Native `state`、当前Settlement overlay人物与Issue marker、QuickConversation当前选项、公开QuestJournal任务文本及Trade VM报价；通用Agent循环的硬上限为400轮。这个路线需要真实跨城购买、返回委托人并交付。玩家可见交谈使用`talkToSettlementHero` QuickConversation；Visit使用分离的`visitSettlementHero`，不混入W2-AI的快速交谈闭环。任务提示结束后，Provider继续推进原版QuickConversation，验收回到同一村庄Settlement菜单且conversation为空，不把尚未关掉的提示面板当作闭环。该环节暴露并修复了Agent JSON跨Windows PowerShell进程的中文乱码、单个对话选项被误当成数组、空对话节点未继续、Trade模式从错误字段读取、空市场重复访问、原版`hero_task_given`分层交付入口未继续，以及Provider变量名`$home`碰撞PowerShell只读变量的问题；AgentLoop回归现用真实Campaign中的中文主角名验证完整往返。每个市场只查一次、无合适商品才转到下一个已观察市场；移动订单完成后，Provider另发显式Native `fastForward`以缩短自然行程，不把时间控制藏入`move`动作。为避免让只有主角一人的测试队伍陷入无法使用Native Send Troops的遭遇，Provider在委托村庄尝试用当前Native志愿兵报价组成最多5人的护卫，同时至少保留450第纳尔；遇到主动劫匪先选择当前可见的和平方案，战斗菜单仅在原版Send Troops可用时使用BattleSimulation及Native战后界面；若Send Troops不可用则保留遭遇并停止，不进入实时战场或擅自投降。Captivity界面只继续单一可见的`mno_continue`阶段；到达赎金/逃脱等有后果选项时保留状态等待用户的玩家策略事实，不快进、不猜着选择。以上是该测试Provider的有界策略，不表示产品Agent已实现完整战斗/战后AI。完成判定基于Native任务从活动Quest列表移除、Turn-in前原生市场可见的工具数量，以及Turn-in后经玩家原生MainHero Inventory VM按需读取的精确Tools/奖励物品ID与数量；先前的Roster总物品数变化只作交叉检查，不冒充物品类型明细。由于Native TradeVM的可出售Flax数量可能小于MainParty完整Roster数量，不为二次确认而冒险再次穿越战区。测试还核验QuickConversation返回同一Settlement菜单、源存档哈希和进程清理；Provider的`done`只结束循环，不代表成功。不注入任务/物品/库存，不读取私有Quest字段。此专项阶段通过前不加入`All`。

`SettlementOverlayQuickTalk`对已确认存在自然Issue marker的可见Settlement运行Native QuickConversation专项回归：通过QuickTalk权限事件与CampaignMapConversation进入地图对话，按当前可见原版选项结束，并验证回到同一Settlement菜单、任务/存档/时间证据和进程清理。测试目标Settlement是已验证的一次性Campaign夹具参数，不是Provider得到的隐藏Quest字段，也不代表全地图自主Issue发现能力。`SettlementOverlayConversation`继续验证不同的Visit/Location Mission路线。

Agent decision provider may terminate a bounded loop with an explicit `{done: true, reason: ...}` response; the loop records this as `provider-stop` and issues no further game action. This only means the provider claims its objective is met, not that the game objective is verified; the owning Harness test must assert the actual native postconditions separately. Reaching the decision budget is recorded as `decision-budget-exhausted`, never as success.

默认入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Dev\ChronicleFramework\Run-Harness.ps1 -Phase All
```

AgentLoop 的 `observeAgain` 是循环调度控制，不属于游戏动作：只允许在 Native `move` 已完成、Campaign Map仍在自然运行、主队仍移动且目标尚未抵达时，请求 1–10 秒的宿主侧等待；允许的Native时间档是 `StoppablePlay` 或 `UnstoppableFastForward`。遭遇、菜单、弹窗或停止时间都不能靠宿主等待解决，执行器会拒绝该等待、刷新Native观察并把 `control-unavailable` 反馈给模型，不发送暂停/快进/时间步进命令，也不重复下达移动。若模型推理期间主队已自然抵达目标，同样将过期等待作为无副作用拒绝反馈；没有匹配的已完成Move回执则失败关闭。Native拒绝一个动作后，循环把失败动作和原因放在本步回执/反馈中，但保留上一个已完成的Native回执供重规划使用，不能把失败提案当成最后一次成功游戏状态。执行器会检查条件，Native `currentSettlementId` 与移动回执的目标一致时，只有“移动到达”这一窄目标会把 `nativeMoveArrival` 送给模型；循环另可设墙钟总时限，超限失败并留收据。为了避免无关背包/技能内容和上一回执的完整状态副本挤占短上下文，地图旅行白名单严格为 `mapSettlementTargets,move` 时，模型输入使用 `campaign-map-travel` 字段视图；地图旅行+招募白名单时使用 `campaign-settlement-recruitment`，只传相关位置、队伍/金币、时间、危险和当前招募菜单入口。两种视图都将模型侧上一回执压为有限的 `stateSummary`，聚落目标/招募报价也各自摘要；原生观察/回执、执行器校验和游戏状态不被裁剪。Provider将UTF-8 JSON作为字节发送；面对模型输出的 positional array，只在元素数精确等于当前动作参数列表长度时按列表顺序映射，最终仍由执行器检查参数名/值。缺少模型 rationale 时会明确标为 `rationaleSource=provider-fallback`，不会伪称为模型理由。`LiveModelArrival`、`LiveModelRecruitment` 与 `LiveModelSafePassageRecruitment` 是显式、耗时的选择性阶段（不进入 `All`），使用真实配置Provider和disposable战役。`LiveModelSafePassageRecruitment`用视觉Harness专用的Native Bandit fixture，在一次Move后创建当前可观察的hostile party，等待原版`encounter_meeting`真实出现，再让模型通过`dialogueSelect`与Native BarterVM完成和平通行并继续招募；夹具详情只进Harness收据，不进入模型观察。`recruitOptions/recruit` 不打开Gauntlet招募窗口、不模拟焦点，因此不能声称已经验证玩家可视招募弹窗路径。各阶段均验证Campaign自然时间、窗口视频关键帧、源存档hash及进程清理。LiveModel Harness优先从进程环境读取服务配置，缺项时才继承已有的用户级环境值；阶段内的超时/输出Token覆盖只作用于测试子进程并在结束恢复。

对于`ollama-native`本地模型，LiveModel在启动Campaign前先访问本机`/api/tags`并确认配置模型已安装；服务未运行、模型名不匹配或端口不可达时，在打开游戏/复制测试存档前即失败，避免把服务离线误判为模型决策失败。

如果模型已选择Native `rest(Days)`且游戏确认请求被接受，AgentLoop按接受回执中的`dailyTickCount + Days`计算目标日结算数。随后Harness每5秒仅读取一次Native状态；仅当原版仍处于活动的Town Wait且Campaign时钟由原版自然运行时继续等待。达到目标日结算、原版等待结束/时钟停止或全局墙钟超时即退出监测，再把最新状态交回模型；这段确定性观察不调用模型、不发出游戏动作，也不调用暂停/快进/时间步进。收据注明目标tick、实际tick、轮询次数、耗时和退出原因，明确`nativeClockControlSent=false`；这样模型不必为每个无变化的五秒窗口重复付费推理。

Campaign Agent checkpoint schema v2把目标、最后一个**已确认**的Native动作回执、完成契约和预算累计快照交给现有`ChronicleCampaignBehavior.SyncData(IDataStore)`随Native Campaign存档保存；只允许v1/v2，旧v1继续用于没有预算状态的任务，付费预算续跑遇到缺少累计状态的v1则拒绝重置。checkpoint本体另保存Campaign实例ID，防止错配到不同存档。`agentCheckpointGet/Set`仅在Campaign Map读写且限定checkpoint最大65,536字节；Checkpoint只表示游戏存档状态，不替代当前观察。费用账本另写到Agent Host本地`LocalAppData/ChronicleFramework/ProviderBudgetLedger/<taskId>.json`（Harness以临时TestResults目录覆盖）：内容仅含任务/战役ID、预算profile hash、预留与usage计数/估算金额、请求次数审计状态和待确认调用标记，不存提示词、模型回复或密钥。账本比恢复的旧存档更先进时，合并保留较大的已消费计数，避免回滚游戏存档复活已花掉的模型额度；费率/预算profile变化、损坏账本或身份不符均失败关闭。请求发出前先原子持久化完整预留；若恢复时发现请求状态未知，则把整次预留保留、将usage与HTTP attempt次数标记为未知，绝不当成零或退回额度。`-PersistCheckpoint`将预算与已完成Native回执同步保存；`-ResumeCheckpoint`先获取新的Native `state`、校验Campaign ID和预算指纹，再从同一任务账本/存档快照恢复累计额度。没有Native完成契约时，Provider的`done`或无参数`action=done`只表示停机提案，不是Evaluator证明成功；有契约时必须经过本地Native verifier，只有条件满足才记作`verified-complete`，未满足则继续回到模型，不发送游戏动作。已确认receipt用于避免重放Move/Recruit；真正的“游戏或Agent在Native副作用提交中途崩溃”尚无Exactly-once保证，本阶段不覆盖。`CheckpointPersistence`确定性阶段核验Native Save/Load的预算快照；`AgentLoop`回归核验同一任务恢复后调用额度不会从零开始。账本可以跨旧存档回退保存预留，但若用户删除对应本地账本文件，本地软件无法约束外部服务账单；该路径不是服务商账户级硬限额。

Agent决策循环可选接收schema v1的Native完成契约（JSON经Base64参数传入，作为结构化对象交给Provider）。契约限24条条件，只允许当前Native观察中的有限字段与`eq`/`gte`比较，不执行脚本或游戏动作。带契约时，Provider的`done`先由本地Verifier核对：满足才把checkpoint标成`verified-complete`；未满足/字段未知则把逐项条件和当前Native值作为反馈交回同一循环，checkpoint保持`active`，不得声称成功。恢复时从Campaign checkpoint读回原契约并重看Native状态；目标已满足则记录已验证完成，未满足则先反馈缺项。

真实模型Provider返回的用量只记录计数元数据：请求/响应ID、模型、输入/输出/总token、缓存命中/未命中、重试和HTTP body字节；不保存提示词、回复正文或鉴权头。用量缺失标为`unavailable`，不当成0。预算门限制最多20次请求、每次body≤10,000字节、每次输入保守额度10,128 token、累计输入202,560 token、每次输出≤256 token、累计输出≤5,120 token。付费模式关闭自动重试；loopback本地模式只对尚未得到HTTP响应的连接失败重试一次。

Provider默认使用OpenAI-compatible协议；仅支持Ollama原生`/api/chat`的本地服务可显式设置`CHRONICLE_LLM_PROTOCOL=ollama-native`。适配器把Ollama的`prompt_eval_count/eval_count`转换成相同用量收据，并在loopback token/body预算下运行，不套用远程服务价格。一次真实供给切片发现，10KB请求上限会挡在“读取食品报价”之后：模型拿到完整食品报价后，通用系统提示加后续请求超限；预算门确实阻止了下一次HTTP请求和Native动作。原始Native观察/回执仍完整保存给执行器和验收层，但模型侧使用`campaign-multiday-supply`专用提示与结构化观察/回执视图。食品报价保留当前物品ViewModel ID、物品/修饰符ID、名称、库存、Native报价、交易逻辑单价及食品/可交易标记，去掉不影响选择与动作参数的提示类型、重量等字段；作用域明确，未传字段视为未知。这样不放宽请求/费用上限，也不裁掉`provision`验证必需数据；其它任务继续使用通用提示和各自视图。

官方DeepSeek `deepseek-flash`（官方文档当前对应V4.1-Flash）使用有日期/来源的峰值安全费率；汇率暂按8 CNY/USD，输入预留按body字节数加128个消息封装token且一律按缓存未命中计，输出按256 token/次预留。当前配置20次请求的预留上界约¥0.535296，单次任务上限¥0.65；三轮评测预留上界约¥1.605888，三轮总限额¥1.95。响应超出单次或累计Token边界时立即停止，不再执行Native动作或发出后续模型请求。此估算依赖当前费率、服务端遵守输出上限及保守输入换算；它不是DeepSeek账户级消费限额。代理/自托管服务没有经核实的价格时只报告token/body，不借用DeepSeek费率。Harness收据不得包含密钥或完整提示词/回复。

按需阶段以同一命令加单个 `-Phase` 运行；可选 Docs、Preflight、Api、Build、Smoke、Campaign、FreshCampaign、FreshCampaignProgression、Protocol、AgentHostProvider、AgentHostSupplyEvaluation、AgentLoop、LiveModel、LiveModelArrival、LiveModelRecruitment、CheckpointPersistence、LiveModelResume、BattleFixture、PostBattle、Observation、MapNotifications、QuickInformation、SceneNotification、MainHeroSkills、CharacterDevelopment、SpendSkillFocus、QuestJournal、PartyRoster、PartyUpgrade、PartyPrisonerRecruitment、MissionInteraction、MissionSceneNavigation、AlleyVolunteerBranches、AlleyAttackYield、AlleyAttackFightMission、PersuasionDetails、CompanionHiring、MapPartyTargets、MapPartyQuestMarkers、MapPartyQuestAcceptance、MapEscapeMenu、MapInquiry、AlleyLeaderInquiry、AlleyRosterManagement、AlleyAbandonment、AlleyEntryMenu、MapPartyComposition、MapArmyComposition、MapPartyBehavior、MapSettlementTargets、Movement、MoveToPoint、Recruitment、Rest、Pursuit、EngageVisibility、Conversation、QuestAcceptance、EscortVisibility、TavernMission、TownCenterMission、SettlementOverlayConversation、SettlementOverlayQuestAcceptance、SettlementOverlayQuestGate、BarterTransactions、BarterContexts、BarterFightRoute、BarterSafePassage、VisualCapture、All。`AlleyAttackFightMission`从Native攻击回应对话选择迎战进入专用Mission，再用现有`missionRetreat`撤退action核验失败结果/返回地图；最新实现改为请求Native `Mission.OnEndMissionRequest()`，在MissionState中暴露当前Inquiry，并由Agent通过`respondInquiry`明确取消或确认；它不发OS/桌面输入。`TestResults/20261006-184320`通过并留存“放弃战斗？”与“好/取消”的引擎帧：取消保持Mission和战斗状态，affirmative按原版结果处理。具体物理按键/TAB完整HUD仍待玩家观察核实。由于原版撤退会失去Alley且主角降至1HP，只用disposable Campaign并留存引擎帧；这项不代表实时战斗自主能力或守住巷子。`MapNotifications`在disposable Campaign中添加一个Harness专用的有效Native `InformationData`及无效/未注册负向项，产品观察器按原版`MapNotificationVM`注册表生成可见数据并确认无副作用；全为临时内存信息，不保存。`QuickInformation`清空一次性测试客户端原有提示，再经Native `MBInformationManager.AddQuickInformation`提交当前与排队提示，核对AI只看到当前Native UI提示而不泄漏未显示队列。`SceneNotification`用Native非执行型HeroExecution信息弹窗建立一个真实Native SceneNotification画面，检查按钮/文本VM并保留引擎帧；不点击、不执行、不改正式存档。三类Notice观察均不模拟Windows键鼠，也不声称覆盖所有类型/实际鼠标焦点。`EngageVisibility`在临时运行中通过Native `BanditPartyComponent.CreateLooterParty`生成一个弱劫匪Party，并仅为测试强弱差异临时加入普通兵；要求它先自然出现在`mapPartyTargets`后才执行Engage。之后目标移动、原版IsVisible、AI选择、遭遇与时钟都由引擎自然运行；不直接修改可见标志/移动位置，也不在追击中脚本推进/暂停。关键状态变化时保存游戏引擎截图，并把“探测成功”与“是否复现目标丢失行为”分开记录。该阶段为慢速1.4.8启动客户端使用240秒启动超时，并将子测试原始stderr/stdout写入失败收据。临时Party/士兵不写入源存档。`BarterFightRoute`单独复跑Safe Passage Fight路线；`BarterSafePassage`单独复跑接受路径并显式跨过非攻击时限。32小时自然期间可能有其他NPC劫匪触发Encounter，故该长程模拟与不依赖长时间推进的完整`BarterContexts`阶段分开运行；如果被其他队伍打断，收据应保留实际打断实体，不得把它误报为目标冷却到期。Settlement overlay阶段可选`-TargetSettlementId`与`-ApproachSettlementId`：两者必须来自当前`mapSettlementTargets`；Harness若先到Approach聚落，则通过原生Leave返回地图并重新观察后再选目标，不读取隐藏全局ID。若路线失败，收据会保留结构化观察和MapState游戏引擎截图。`MapSettlementTargets`负向回归使用一个visual-capture专用全Settlement显隐诊断找测试样本，仅Harness可调用，不在普通Agent观察或决策白名单中。

`PersuasionDetails`用独立窄Harness阶段验证按需观察及原版答复入口。`TestResults/20261006-204936`证明Native PersuasionVM即使在AnswerList为空时也能显示0/2与两个空圈，但隐藏CurOptions候选不输出且误选被拒。之后的`TestResults/20261007-033330`等待真实Native AnswerList显示当前回答，再由Harness仅向现有可见行注入临时PersuasionTask、argument和原版OptionVM；Agent读回success/fail/critical chances并通过原有`dialogueSelect`提交。该次Native随机结果为成功，答复文本及进度圆圈更新为1/2，源存档未改变且进程退出。这验证Native VM/机会模型/option提交链，不声称已走通Quest、求偶或政治场景中的自然Persuasion触发与宿主后果。

`MapNotifications`还在同一disposable Campaign放入`IsValid=false`和未被Native UI注册的负向`InformationData`，确认这些没有进入AI观察；只有原生能够显示的测试通知回传。观察适配器重建的VM是原版类型映射，不等同窗口当前的鼠标焦点或人工视觉操作。

`CaptivityObservation`可单独以`Run-Harness.ps1 -Phase CaptivityObservation`运行，作为额外Harness阶段且不加入All：它用临时Native bandit captor和`TakePrisonerAction`建立只存在于本次进程内的PlayerCaptivity，再打开原版Wilderness Ransom GameMenu；为核对报价字段只在应显示的页面可见，Harness再经受限Fixture切到原版Wilderness Escape Continue GameMenu，不按任何选项。Agent仅读取新增的条件性`context.captivity`、当前菜单选项和两张游戏引擎帧，不选择接受/拒绝/逃脱。测试同时确认非俘虏state中字段为null、Captive赎金报价来自`PlayerCaptivity.CurrentRansomAmount`且与菜单可见金额一致、离开报价页后金额隐藏；重复读取不改Gold/时间/存档。Harness通过Native`TakePrisonerAction`和GameMenu阶段切换制作观察Fixture，不伪称覆盖自然战斗失败/定时检查进入这些菜单，也不决定捕俘后的Agent策略。

`MapEscapeMenu`可单独运行，不加入`All`：它用原生`MapScreen.OpenEscapeMenu()`在一次性Campaign中打开地图Escape overlay，核对Observer报告仍是MapState且`escapeMenuOpen=true`，验证被挡住的地图操作在写入前失败，再由产品`closeEscapeMenu`调用原版`MapScreen.CloseEscapeMenu()`恢复地图。关菜单不切换时间档位；测试会在显式暂停后比较CampaignDay、raw时钟档、waiting、金钱/影响力、目标和任务数，保留overlay打开/关闭引擎帧及存档哈希/进程清理回执。此动作只针对Campaign地图顶层Escape overlay，不负责Options、读档/存档、退出、Mission菜单或任意键鼠输入。

`MapInquiry`可单独运行，不加入`All`：在一次性Campaign中通过Native `InformationManager.ShowInquiry`实际生成SingleQueryPopup VM，普通`state`通过1.4.8 `GauntletQueryManager`的当前活动数据映射显示当前 Yes/No 文案、可用性、生命周期token及`pauseGameActiveState`，不把排队项当成可见询问。Agent必须提供最新token与明确的affirmative/negative choice；`respondInquiry`调用Native `SingleQueryPopUpVM.Execute*Action`以保留原版“业务回调后关闭/切到下一条”顺序。测试分别验证两个Native回调、重复/过期token拒绝、弹窗打开时阻止地图移动、时钟/世界/存档不变和前后引擎帧。额外用Sargot村镇当前Native `recruit_volunteers`入口准备1.4.8 `RecruitmentVM`，在主队恰好满员时调用Native `ExecuteDone`打开本体“Over Limit/超过上限”询问，按当前本体VM分别否定和肯定：拒绝无Roster/Gold变化，接受实际加入1人并扣原价；原始存档哈希不变。引擎帧中可以看到聚落菜单下方的原生对话框。这里调用的是Native VM的玩家按钮处理器，不是桌面鼠标点击，也未覆盖其他业务Inquiry；任意Yes/No都不代表安全或应接受。

`CaptivityOutcome`是独立可选阶段，不加入`All`：分别在两次隔离游戏进程中从同一个不变的disposable Campaign存档加载，以Native `TakePrisonerAction`建立临时捕获；测试只从当前赎金菜单观察到的启用选项中选择Accept或Reject，并记录前后引擎截图、MainHero金币/囚禁状态、主队成员、Captor囚犯名册、菜单与Campaign时间。Accept须扣除本轮原生报价并让MainHero回归MainParty、从Captor名册移除；Reject须不扣钱/不解囚，且返回`prisoner_wait`。它验证原版当前菜单结算，不代表Chronicle已选择何时赎人、拒绝或尝试逃跑；也不模拟自然战败、关押、绑架或AI政策。

`PrisonCaptivityOutcome`为`CaptivityOutcome`的独立SettlementCaptor分支，只验证`settlement_wait`→`menu_captivity_end_propose_ransom_in_prison`上下文，不加入`All`。Harness以Native `TakePrisonerAction`把MainHero置入真实Settlement Party PrisonRoster，再由`PlayerCaptivity.CaptorParty`使用当前Settlement对象进入Native `settlement_wait`；为使原版Captivity检查不会因双方和平而立即释放主角，夹具仅在disposable Campaign内通过Native `DeclareWarAction`建立临时敌对。测试金币不足报价上限时用Native Gold Action补足到测试下限，金额仅用于确保Accept分支可用，不当作玩家经济事实。Accept/Reject仍通过当前观察到的Native菜单选项，核验解囚/支付及返回Settlement等待流，并记录自然时钟前后值/完整引擎帧。此夹具不复现MobileParty押送进城或原版定时检查自然触发赎金Offer。

`EncounterSurrender`是独立可选阶段，不加入`All`：Harness建立当前Native hostility bandit后，通过原版地图导航自然触发Bandit会面，再选择当前可见的Native Fight对话选项进入真正的`encounter`菜单；只在当前MapEvent存在之后，测试夹具才用`Hero.MakeWounded()`和`RecentEventsMorale=-100`满足该版本投降条件。Harness复读当前菜单，只有Native `surrender`确实available/enabled才选择。测试验证`PlayerEncounter.PlayerSurrender`/MapEvent结算到Captor Captivity等待菜单，并截图保留Bandit会面/遭遇/投降后原生画面；不直接设置Surrender flag、MapEvent胜负或Captivity结果。测试性伤病/士气和Bandit均只存在当前Campaign内存。若真实入口或菜单条件未满足则阶段失败留证据，不把API存在当作玩家可用入口。

`EncounterEscape`是独立可选阶段，不加入`All`：Harness在两个独立disposable Campaign进程中，把MainParty填入Native文化新兵/Grain，再以原版Fight会面路径进入MapEvent，观察Native `leave_soldiers_behind`并打开Try-to-get-away warning。Reject进程只能选择Native Think again，并核验回原Encounter且资源/时间不变；Accept进程只能选择Go ahead，核验Native `TroopSacrificeModel`显示的损失、实际伤兵/货物损失、escape debrief及Continue返回流程。测试诊断仅Visual Harness允许读取当前TroopSacrificeModel结果、Roster和Inventory；不会修改BattleEvent胜负或接受后结果。

`JoinEncounterDefenders`是独立可选阶段，不加入`All`。为提供可重复的NPC对NPC在途战斗，Harness-only fixture调用Native `StartBattleAction.Apply`建立一个BattleEvent，并确保MainParty未加入；玩家自身仍经Native地图点移动接近，再由原版Join Encounter菜单决定是否可参与。接着仅选择当前可见的Help Defenders option，并核验MainParty加入同一 MapEvent 的Defender side及后续Encounter菜单；不调用PlayerEncounter.JoinBattle，不攻击或坐镇结算。若NPC battle在玩家抵达前自然结束、join选项因原版过滤被禁或MapEvent ID变化，则记录失败原因而不是改为直接注入玩家入场。

`JoinEncounterEligibility`是独立可选阶段，不加入`All`，作为`JoinEncounterDefenders`的关系筛选补充。fixture只在disposable Campaign用Native战争/和平动作设置玩家关系，分别测“只可帮助攻击方”及“双侧中立不可加入”。攻击方正向必须经过本轮可见`join_encounter`的唯一Help Attackers选项并确认MainParty进入同一MapEvent的AttackerSide；双中立分支绝不提交Help选择，只记录原版到达状态、当前可用选项与Native `CanPartyJoinBattle`结果。如果自然NPC战斗先结束，或测试需要直接构造玩家Encounter才能显示菜单，则作为失败收据保留，不伪造UI路径。

`JoinEncounterAbandonArmy`是独立可选阶段，不加入`All`。玩家先用本轮可见地图目标与原版`pursue`进入真实`join_encounter`；为隔离弃军菜单条件，visual Harness随后在当前活动事件中用Native `Kingdom.CreateArmy`将MainParty准备成非Leader Army成员，再重新激活同一注册菜单让原版条件重算。只提交当前页面Native `join_encounter_abandon`菜单项。收据必须显式说明成员是Harness准备而非玩家点击Army Management界面建立；验收核对MapEvent/PlayerEncounter、Army内部成员/附属Party、主队Hold、资源/关系/影响力、Campaign时间和退出界面；不得用直接清除`Army`引用替代玩家菜单回调。

`MovingArmyJoin`是独立可选阶段，不加入`All`。它仅测试没有MapEvent/SiegeEvent的Campaign行军Army；先由本轮可见目标创建Native Army，disposable fixture内通过Native ChangeKingdomAction让MainParty和Army处于同Faction，再以原版地图目标交互接近。仅在当前Native `army_encounter`菜单确实开放`army_join_army`时提交；不手动触发Army encounter或直接把MainParty写进Army。Army战斗援助/中立离开走G01，围城加入是另一个上下文，均不混进本阶段。政治Faction切换仅为测试前置，收据必须将其与菜单结果/原版副作用分开。

`JoinSiegeEvent`是独立可选阶段，不加入`All`。Harness在disposable Campaign以Native `SiegeEventManager.StartSiegeEvent`和BesiegerCamp/AI目标路径建立当前可见Fortification SiegeEvent；玩家用地图Settlement目标和原版导航进入`join_siege_event`，只提交实际Enabled的“Join the continuing siege”。结果需区分Native `PlayerSiege`/Siege preparation、Active MapEvent分支和之后Mission；围城WaitMenu造成的Campaign自然时钟推进需单独记录，不作为Join命令隐藏快进。Army行军成员加入、Battle help/leave和Siege join保持独立能力/验收。

`TimeControlLoop` 是独立可选阶段，专门验证测试Provider通过Agent循环选择原版时间档；通用 `AgentLoop` 保持只读观察循环，避免Encounter随机状态污染时间控件断言。

`Hold` 是独立可选阶段（`Run-Harness.ps1 -Phase Hold`），验证先执行原版聚落导航、再调用玩家主队停步动作后，目标确实清除，并在没有显式时钟命令的自然观察窗口记录Campaign是否有效暂停。

`Run-Harness.ps1` 顺序执行阶段、首错停止、把原始输出和 JSON 写入 `TestResults/<run-id>`，并更新 `TestResults/latest.json`。

Inventory/market专项阶段：`InventoryNavigation`验证玩家Map Inventory入口与Trade之外的原生InventoryState；`EquipmentTransactions`验证MainHero Native SPInventoryVM装备事务；`TradeTransactions`验证Town菜单Trade入口、市场买卖/食物筛选、按当前ItemViewModelId读取异地贸易传闻及Native `ItemMenuVM`提示一致性；`BarterTransactions`走真实Lord对话入口，验证原生BarterVM普通物品/金币谈判草稿、Native Auto Balance、Offer/Cancel结果。Trade rumor测试传闻仅注入到disposable Campaign内存，比较商品市场/玩家两侧原生tooltip文本，不模拟Windows鼠标；真实物理悬停视觉仍未覆盖。Town菜单不允许原版显式时钟控件时，测试不调用pause/resume，而是记录当前档并确认Trade查询/事务不改写它。Barter的普通、Peace/SafePassage/Defection/Marriage UI共用VM适配层，但各Context的初始Barterable与最终世界效果不可混为一谈；Diplomatic/Ransom的AI Barter不属于玩家UI接口。

`BarterContexts` 用独立的visual-capture Harness进程验证Bandit Safe Passage。夹具通过本机1.4.8 `BanditPartyComponent.CreateLooterParty`建立临时BanditFaction party，按原版遭遇半径/关系计入附近可加入玩家侧的队伍与`CustomStrength`；逐步增加劫匪编制，直到其强度至少为玩家侧的1.56倍，再调用原生`SetMoveEngageParty(MainParty)`。生成位置须先通过原版导航检查，且`SettlementHelper.FindNearestSettlementToMobileParty`须找到Town/Village，避免无效夹具位置触发原版条件中的空引用。

测试不手动创建Encounter，也不强制`UnstoppablePlay`；玩家经有效地图点使用原生`moveToPoint`，使地图点击按普通规则进入`StoppablePlay`，由主动追击的劫匪自然触发遭遇。默认分支走Native BarterVM、Auto Balance、Offer和接受后结算；Offer后记录原生32小时`DoNotAttackMainPartyUntil`与Hold模式，再使用独立Harness `advance 1.35 days`越过时限并复读队伍。该快进是显式测试动作，不属于普通玩家/Agent移动。第二个`-CancelOnly`临时进程验证Cancel不产生世界效果、Continue回到Encounter菜单；第三个`-FightOnly`进程从威胁选项验证Attack/Send Troops入口，但不启动或结算战斗。`BarterFightRoute`允许只复跑Fight分支，不重跑其他路线。

遭遇等待中单次状态请求限8秒，连续3次超时即失败并进入截图/清理流程；同时保留ButterLib原生崩溃异常，区分游戏崩溃与协议/UI不响应。fixture仅在visual-capture Harness模式可调用，不加入Agent决策工具。运行记录队伍/潜在加入者、有效生成点/最近定居点、地图移动回执、原始存档hash；断言先于stop执行，失败可取游戏引擎末帧，成功则停止进程并核对源存档hash。

UI Harness失败证据：游戏内Agent协议遇到非`InvalidOperationException`异常时，在当前Harness temp里保留首张引擎末帧`protocol-unexpected-failure-frame.bmp`和配套JSON（动作、错误、游戏状态/菜单/时钟）；业务拒绝类`InvalidOperationException`不触发自动截图。带UI转换的测试脚本若在其自身断言失败，则在`finally`清理进程前调用`Capture-HarnessFailureFrame`，该助手只允许对`session.json`中仍存活的Harness进程调用游戏内`captureFrame`，写入`harness-failure-frame.bmp/.json`；若Agent命令通道已卡住，失败收据会回指协议层刚保存的末帧，而不再盲等或伪报“没有截图”。不截Windows桌面、不抢焦点；成功运行不留失败图，失败收据和末帧保留在同一个TestResults run目录供Agent与用户对齐事实。

`tradeOptions`/`foodOptions`只在当前Native Trade InventoryState读取SPItemVM候选；`tradeRumors(ItemViewModelId, InventorySide)`进一步限定到这次候选，读取Native Goods tooltip实际会显示的异地价格线索，不枚举Campaign全局rumor表。买卖动作引用最新观察中的`ItemViewModelId + InventorySide + Amount`，以区分同一基础Item在市场侧与玩家侧的重名实例。`tradeConfirm`通过Native Gauntlet Done提交；若原生报价高于MainHero当前金币或Native VM拒绝完成，适配器会通过原版Cancel Inquiry清理刚建立的草稿并拒绝该动作，避免挂住不可提交事务。`tradeCancel`关空白交易页，`tradeCancelChanges`仅在Agent明确选择丢弃草稿时接受原版Inquiry。食品`provision`是买入方向的食品筛选别名，不另建地图态市场交易旁路。`TradeTransactions`已用一次性买卖记录同时比对市场侧/玩家侧返回提示和Native `ItemMenuVM`文本，并确认查询不改金币、Roster与时钟。该证据是原生ViewModel/结构化候选的一致性，不代表真实鼠标悬停的焦点动画或全部语言/Mod覆盖。

Campaign Map普通`state`保持轻量，不默认携带全部可见聚落列表；Agent可按需调用只读`mapSettlementTargets`查询当前本体`IsVisible`的Settlement地图标记，该查询只在MapState有效，不改变游戏状态或Campaign时间。隐藏目标真值仅由visual-capture Harness诊断取得，用于负向安全测试，不送入决策Provider。

地图聚落列表通过只读CLI/Agent工具 `mapSettlementTargets`按需查询，而不重复塞进每次`state`快照；只有Campaign Map状态可以调用。数据只含本体`IsVisible`的活动聚落，并附`IsInspected`以区分地图图标与近距离调查。Harness-only的`harnessMapDiagnostics`可用于正/负向测试，但禁止进入Agent决策白名单。

`Agent-Cli.ps1 load`从存档头部读取该存档创建时的有序模块ID，验证这些模块仍安装后再用同一模块集加载；不向旧/不同模组集存档擅自附加当前默认模块。元数据解析在Preflight使用合成存档头回归。v1.4.8 的“Mod change detected”原版窗口是着色器缓存提示，不足以证明存档模组不兼容。启动Harness会读取目标游戏进程窗口的UI Automation树；仅当窗口标题、着色器/缓存正文和唯一明确肯定控件都匹配时，才调用该控件的UIA `InvokePattern`/`LegacyIAccessiblePattern`，或对可验证归属进程的Win32 Button发送`BM_CLICK`一次，并记录处理回执。它不发送全局键鼠、不激活窗口；内容/控件不匹配、无法安全调用或一次确认后窗口仍在时快速失败，绝不盲目重试。Docs用正向和三种负向样例锁定这个范围。实测发现RGL提示里的“确定”是Win32 `Button`，但UIA把它标为`Pane`且不提供InvokePattern；改为校验按钮类、控件名、窗口正文和所属PID后发送单控件`BM_CLICK`。随后`InventoryNavigation`实机阶段通过，临时存档hash前后不变、游戏进程正常退出；测试结果现会保留启动弹窗处理回执，供后续回归核验。

Provider loop 输入观察及上一动作原始回执，再执行 allowlist 动作并复观察；`advance` 仅 Harness 可用。Test provider 不代表 LLM。CLI 需 state 握手；stop 清理进程树/队列。对话与战斗控制分开。

每次 Harness 将 MSBuild/`Add-Type` 临时文件定向到 `TestResults/<run-id>/Temp`；项目排除 `TestResults/**/*.cs`，防止反编译研究源码污染 Mod Build。

`mainHeroSkills`是固定体量的玩家自我状态，随常规快照读取：只枚举当前Campaign的SkillObject并调用MainHero原生`GetSkillValue`；不混入XP、Focus或Perk预览值。`MainHeroSkills` Harness阶段将对照独立Native读取，证明快照没有写入角色成长状态。用于测试的`harnessPlayerSkillsDiagnostics`仅在visual-capture模式可调用，且不进入Agent动作白名单。

`characterDevelopment`是只在Campaign Map显式请求的只读查询，不扩大常规`state`快照。它向Agent返回MainHero属性、技能进度/Focus/学习率、点数余额与当前等级可见Perk状态；CharacterDeveloperHarness用原生`CharacterDeveloperHeroItemVM`逐项对照，QA诊断仅在visual-capture模式可调用，不进入Agent决策白名单。它不提交成长草稿；Focus/Attribute/Perk投入以及Done/Cancel/Reset须另立产品任务，并先补MAINLINE行为契约。

`spendSkillFocus(SkillId, Count)`只允许Campaign Map调用，要求目标来自最新`characterDevelopment`观察。调用在单个命令内验证技能身份、原生可加点状态、余额与Focus上限；然后用原版`SkillVM.ExecuteAddFocus`建立临时草稿并通过`SkillVM.ApplyChanges`提交，不开角色界面、不保留跨回合草稿、不改时钟。事务测试验证可用Focus实际写入与超额请求的整体拒绝；QA诊断只在visual-capture模式可用，决策环可调用的仅为正式白名单动作。

Campaign `state` schema21把活动Quest期限字段限制为原版QuestsVM显示的整日剩余时间；若Quest声明期限隐藏，返回`null`。Agent可用观察到的QuestId显式查询`questDetails`，取得Quest Journal显示的阶段文本/任务名与进度，不读取内部QuestTask列表、已完成历史或未观察任务。此查询只读，在Campaign Map/Mission均可用；QA用新接受的原版Quest与`QuestItemVM`逐项对照。

`partyRoster`是Campaign Map上的按需只读查询，只列MainParty成员与俘虏的兵种ID/名称、人数、伤员和Hero标志；常规`state.party`继续保持汇总。它不枚举其他阵营Party，不给升级/招募建议或费用，也不改Roster。Harness专用诊断从同一原生TroopRoster但用独立`GetTroopRoster()`枚举路径交叉核对；测试诊断不进决策白名单。

`partyUpgradeOptions`/`upgradeTroop`从MainParty Normal PartyScreen的原生PartyVM读取并提交一个普通兵种升级。`prisonerRecruitmentOptions`/`recruitPrisoner`读Native PartyVM当前可招募的MainParty普通俘虏并提交一个；超PartySize时，选项同时返回完整原版Done确认文案，Agent必须显式传`ConfirmPartySizeWarning`同意超限后果才会调用原生affirmative callback，否则动作拒绝并撤销草稿。两项动作都使用共享MainParty PartyScreen生命周期，临时PartyVM需按原生要求初始化按键回调并调用`OnFinalize`。Harness disposable fixture仅在visual-capture模式下能注入兵种、XP或填满队伍；不会保存这些改动。`PartyUpgrade`/`PartyPrisonerRecruitment`阶段分别核验native结果、拒绝、Campaign时钟和清理。

`missionSceneAgents`只在友好Town/Tavern/Village Location Mission且Campaign Stop时按需列出当前Mission已生成的活动人类Agent及其位置；它不是相机可见列表，也不查询Campaign全局或其他聚落。该信息不进入常规`state`快照。`missionNavigateToAgent(AgentIndex, DurationSeconds)`在12单位内仍接受当前局部Agent；远目标必须先来自同一Mission、最近60秒内的`missionSceneAgents`观察。导航读取目标的当前位置，经Native `SandBox.AgentNavigator`和Scene NavMesh实际移动，非传送；NPC移动后需重查询/重选目标。导航租约默认8秒、显式限1–20秒，结束恢复MainAgent Player控制权；有Agent不保证存在可达路径。`missionInteract(AgentIndex)`仍只接受当前局部`nearbySceneAgents`里的有效人类Agent；它先验证原生`MissionConversationLogic.IsThereAgentAction`与`Agent.CanInteractWithAgent`，再调用目标的Native `Agent.OnUse`→`Mission.OnAgentInteraction`链，而不直接启动ConversationManager。对话启动后由既有`dialogue`观察及`dialogueSelect`/`dialogueContinue`处理。`MissionSceneNavigation`以Assigned Alley Leader为远距目标，先证实无场景观察的远距导航被拒，再查询当前Mission、经有界NavMesh走近、进入局部范围后由现有原生交谈动作开对话；不选对话选项。

`CompanionHiring`是一项端到端Tavern原版对话验收：Test-only fixture可把玩家Gold精确设到Native报价或报价+1，用于测试严格`Gold > price`门槛；它不进入Agent决策白名单、不保存存档。该阶段要验证按本次Conversation选项启动雇佣、报价实值、Clan/MainParty结果与不足报价时不发生扣款/加入，不直接调用原版Hire动作API。

## Harness 架构

职责按事实来源划分，不复制状态：GitHub 项目板回答“做什么/顺序/当前工作项/是否被依赖阻塞”；Git回答“代码变成了什么”；Harness回答“本机游戏与工具实际上发生了什么”；Agent决策层回答“基于证据下一步做什么”。Harness输出不能覆盖GitHub卡片状态，也不能把测试指标当作产品自主能力；Harness不调用GitHub API/CLI。

```text
CLI 启动适配
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
4. 只读窗口截图，仅在不激活/不前置游戏窗口且确有视觉诊断需要时使用。

不使用 Windows Computer Use 向游戏窗口发送鼠标或键盘输入：当前 `@oai/sky` 的窗口定向输入会自动激活目标窗口，不能保证不抢占用户前台或物理键鼠。游戏操作一律走 Mod 内版本化协议和 Harness 白名单动作；截图不是功能真值。若未来要恢复窗口输入，必须先证明后台窗口输入不会激活窗口、移动/占用用户鼠标或截获键盘，并以隔离测试验证，不能只因 API 接收了 window 参数就视为隔离。

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

Agent决策循环的Harness原型使用请求schema v3：每轮把明确Goal、由执行器同一白名单生成的可用动作/参数名、当前结构化观察、上一Native action receipt，以及最多8条只含“模型所选动作/参数与原版执行结果”的近期决策历史发送给Provider。历史不携带过去完整观察或自由文本理由；当前Native观察和最新receipt始终是游戏状态真值。它用于帮助模型跟踪已完成的目标步骤，而不能扩大动作白名单。每步记录Provider响应、原版动作和后验观察的UTC时点与耗时，供真实游戏窗体视频按同一时间轴抽取关键帧。`AllowedActionNames`可选地同时缩窄模型可见目录与执行端许可；W3-A首个真实模型尝试只开放只读`mapSettlementTargets`和原版移动`move`。决定仍在Provider返回后由本地白名单/参数校验，模型不直接调用游戏API；Harness确定性Provider只验证上下文契约，不算模型自主能力，也不是玩家交付运行时。

Agent决策循环的 `allowedControls` 与游戏动作目录分离，但同样按当前Native状态动态生成。只有执行器确认上一条成功移动仍在地图上自然推进、主队仍在移动且目标未到达时，才向模型暴露宿主侧 `observeAgain`；遭遇、对话/菜单、询问弹窗、暂停时间或无有效移动回执时，控制目录为空。执行器仍会在模型返回后重新核验，因此目录是决策约束和清晰反馈，不是安全边界本身。每轮收据同时记录交给模型的动作与控制目录，便于判断模型是选择了错误动作，还是当时根本没有看到可用操作。

移动中的新鲜观察不要求模型专门发起等待：若模型在下一轮直接调用一个允许的只读原版观察动作，且该轮输入明确看到主队仍在目标路上、Campaign时间自然推进，则这是有效的旅途观察；它和宿主侧 `observeAgain` 一样，只读状态、不改变游戏时钟。若短途移动在下一次决策前已到达，则目标Settlement的Native菜单观察与移动期间Campaign时间增量共同构成有效后验观察，不要求再发起多余等待。

在劫匪无选项对话阶段，执行器按状态区分两种转换：当前BarterVM尚未建立时先检查一次原生报价；该检查被Native拒绝后开放 `dialogueContinue`，让原版对话继续建立谈判界面。当前Native BarterOffer已接受后若对话仍暂时没有选项，则直接开放Continue并隐藏过期报价查询，避免在交易已完成后重新探测失效BarterVM。

Provider发现模型选择了当前合法动作、但参数名超出该动作当轮的白名单时，不得静默删掉额外参数，也不应把它伪装成游戏内动作失败。它返回带当前动作目录、合法参数名、非法参数名且明确标注“未发送给Native”的结构化拒绝；循环重新读取原版状态，把拒绝原因交还模型，并限制连续重试次数。其它参数形状错误或缺少必填参数继续失败关闭，直到建立对应的可验证恢复契约。

真实Provider只对尚未收到HTTP响应的TCP连接/名称解析失败自动重试一次，随后停止并记录安全的HTTP状态、主机和内层异常类型；不重试超时或已收到的HTTP错误响应，以免结果不确定时重复生成并产生重复费用。外部服务响应正文、Authorization头和密钥不进入失败日志。`CHRONICLE_LLM_THINKING_MODE`可选地把OpenAI-compatible `thinking.type`设为`enabled`或`disabled`；未配置时不改Provider原来的默认值。DeepSeek Flash默认为Thinking模式，这个选项用于针对结构化动作评测控制推理模式，不更换模型或改游戏动作。

Native Barter目录按当前VM会话和成功回执逐阶段开放：没有当前BarterVM时只允许读取选项；读到当前Safe Passage报价后开放自动平衡，暂不允许提交；自动平衡成功后在同一会话中隐藏重复读取/重复平衡，开放当前可用的Offer。报价编辑、重置、取消或提交会使已平衡标记失效；Offer成功则清除会话标记并转回原版谈话阶段。这样模型仍决定是否调整/提交，但不会被反复可用的“读取/自动平衡”按钮困在无进展循环。

真实模型验收收据记录配置中的模型标识、Git源码提交、被跟踪文件是否干净、Campaign日区间与运行UTC区间；不记录API密钥或服务端点。用于结束产品Issue的真实模型结果应在已提交源码上复跑，使收据提交号就是实际被测试的代码版本。

时间模式运行时世界自然推进；移动不补发 `advance`。地图点击副作用和 WaitMenu 自管时钟按原版复现。`advance/pause/resume` 仅显式 Harness 时钟工具，不嵌入普通动作。

## 验收阶梯

| 层级 | 必须证明 | 自动证据 |
| --- | --- | --- |
| Docs | 文档路由、主线层级、引用/hash/复核和契约一致 | `Check-Docs.ps1`；Harness收据另记Git commit/脏树 |
| Preflight | 本体、项目、清单和工具存在；存档头模块列表的解析、顺序保留、损坏拒绝 | JSON 清单与合成存档元数据回归 |
| Api | 当前 DLL 存在目标签名 | API Probe 输出 |
| Build | 游戏内Mod针对当前DLL编译；外置本地Agent Host单独构建为.NET 8进程 | Build收据分别保留Mod与Host构建输出/退出码；Bannerlord运行时不编译或覆盖已加载DLL |
| Smoke | 清单、DLL、`OnSubModuleLoad`、`Finished All`与MCM已注册的Chronicle Provider设置定义（两个文本字段+本地配置验证按钮）；只对严格匹配的着色器缓存弹窗执行一次进程内原生确认，对未知 Warning 只读采集、不乱点 | 同 PID RGL/错误/Watchdog日志副本、结构化Smoke结果及MCM属性ID/按钮类型；Harness模式从游戏启动/主界面阶段显式传入并在MCM Provider就绪后核验；安全识别的UIA弹窗信息，失败时保留子测试输出，超时与实际崩溃分开 |
| Campaign/FreshCampaign | 旧档；FreshCampaign新Sandbox原生创建、跳intro、选+20；Progression用临时存档重载再move/arrival/recruit | 同PID renown20/MapState、非激活840x472；Crash Report仅按明确信号有界重试；已知`Mod change detected`着色器缓存提示仅可经精确匹配的目标进程UIA按钮确认一次，不用全局输入；临时存档精确清理、非模型Provider |
| Protocol | CLI 启动/重载、状态、Native Pause/Play/FastForward、Harness-only独立推进时钟、Campaign保存/跨进程读档、外置Host只读Native状态握手与Native拒绝回执、停止 | Native时间选择对照`Campaign.SetTimeSpeed(0/1/2)`，检查raw/effective模式和waiting状态；固定advance仅用于Harness测试并按日目标或Encounter返回；存档往返使用唯一测试名，比较Save前与新进程读档后的结构化Campaign指纹及Chronicle SyncData计数、源夹具哈希后删除；外置Host三次读状态须与同一PID/MainHero/Clan/MainParty回执一致，且前后Campaign指纹不变；假邮箱覆盖繁忙/错关联ID/超时；一次故意无效的Native Menu option必须获得严格JSON可读的拒绝回执且不改变Campaign。`AgentProtocol.Escape`转义所有JSON控制字符，避免异常堆栈的CR/LF破坏IPC响应。时间步进不得隐式塞入地图移动/追近命令 |
| AgentHostProvider | 本地Host的IPC邮箱回归、MCM Global Provider profile校验与Ollama结构化决策Provider | 可单独 opt-in；假Mailbox测繁忙/关联ID/超时，假HTTP Handler覆盖请求schema、格式/解析错误、截断、越权动作、HTTP失败及超时；Mod设置按钮与外部Host共用同一地址/模型校验器，profile回归核对Global JSON字段、loopback URL、凭据/查询参数/损坏文件及模型标识拒绝路径，并验证Host只读取授权的Harness临时配置；确定性Provider分别用地图目标查询与补给报价验证Campaign/补给策略调用同一个Host决策循环；真实Qwen Smoke是单独的本地模型请求，无Bannerlord/Native状态副作用、不访问付费API，且不记录模型提示词/原始回复/凭证；不加入`All` |
| AgentHostPackage | 为Windows x64用户打包可在未安装.NET时运行的本地Host | 单独opt-in；从源码发布self-contained win-x64目录到D盘仓库外的暂存目录，避免运行时DLL进入源码树影响Mod编译；NuGet包走7890代理且缓存放D盘；在与publish目录不同的工作目录直接启动Host `--package-health`/`--version`及无模型`--provider-self-test`，核对内嵌运行库、协议/架构、决策循环安全回归、文件SHA256清单、不含用户配置及进程退出；不启动Bannerlord、不修改正式模块、不加入`All` |
| AgentHostSupplyEvaluation | C# Agent Host 使用本地Qwen循环控制当前MainHero/MainParty完成固定三日补给切片 | 独立opt-in，复用W5 Native起点/完成门槛；3次同存档起点记录Host决策、Native动作、每日Tick/资源结果、录像覆盖与清理。测试前Prelude只负责建立六人起点；模型决策不得由Harness替代。Harness视觉阶段显式注入用户已有Provider环境配置；产品运行路径改读MCM Global `FormatType=json`本地profile。Native `rest` accepted后Host用只读轮询等待三个自然Campaign Tick，并在当前`wait_leave`可用时提交一次原版菜单选择；不调用显式时钟API，不逐次调用LLM，且超时仅在安全入口可用时尝试停止原版Wait。若等待被中断则基于新Native状态安全返回/停止；若冻结完成条件未满足，Host停止且不重复交易。此阶段不覆盖全Campaign和其他182项行为，不加入`All` |
| AgentHostCampaignLoopEvaluation | C# Agent Host 的通用决策通道与有界地图到达闭环 | 独立opt-in，真实本地模型从原生观察中选取安全可见聚落、经Native `move`前往、移动中只被动重新观察，且只在Native当前位置确认抵达后结束；必须证明Campaign时间由游戏自然推进、不发送时钟动作、行动白名单、录像覆盖及源存档/进程清理。另有无模型单元回归覆盖初始只读观察、目标风险筛选、移动期间唯一观察控制、抵达门槛、陌生ID/显式时钟拒绝，并用地图查询与补给报价两种不同动作目录核验共享决策循环。属于有限地图切片，不代表182个Campaign行动完整支持，也不加入`All`或替代Epic的最终玩家验收 |
| AgentLoop | 外部Provider进程接收版本化决策请求，选择白名单动作并重观察 | 请求schema v2含显式测试Goal、由同一执行白名单导出的动作/参数目录、当前观察与上一Native receipt；可选动作子集须同时缩窄模型可见目录与执行端许可；每步记录provider/action/observation的UTC时点和耗时；确定性Provider回归核对上下文续传/动作集合；OpenAI-compatible Provider把配置的`/v1`基础URL解析为`/chat/completions`请求路径，云端默认使用`max_completion_tokens`、`store=false`及JSON response mode（兼容端可显式切换token字段）；可选`CHRONICLE_LLM_REASONING_EFFORT`与`CHRONICLE_LLM_TEMPERATURE`仅在显式配置时转发，供Ollama等思考模型关闭推理并稳定结构化决策；有序目标步骤必须以完成的前序Native receipt为门槛，不能因后续动作看似可行而跳过；大型`mapSettlementTargets`回执仅在模型输入视图中压缩为最近安全候选与少量风险候选，并显式携带总数/省略数，原生回执和Harness追踪不变；本地Ollama兼容Stub核对`max_tokens`别名、推理/温度设置、大型回执压缩、loopback无密钥请求与JSON响应；通用HTTP stub核对鉴权头、结构化输出、越权动作/401/超时失败关闭及secret不回显；随后AgentLoop回归核验时序字段、前序回执、中文主角名往返、超时/无效动作拒绝、fixture哈希与进程退出。所有stub/确定性Provider只验证协议，绝不作为真实模型能力证据。 |
| LiveModel | 显式进行一次真实Provider与Campaign闭环验证，不包含在`All`中 | 要求当前没有已运行的Bannerlord客户端，且本地Provider URL/model已配置；只允许`mapSettlementTargets`和`move`，要求模型先查当前可见的安全聚落，再对本轮观察到的目标发出一次Native移动并主动停止；同一轮记录Provider/动作/后验观察UTC时点，对指定Bannerlord HWND连续录制并按事件抽取真实窗口关键帧，同时保留引擎截图前后对照；验证视频覆盖、目标匹配、测试存档哈希及进程清理。成功仅保留关键帧/联系表并删除原视频；失败保留部分视频、失败引擎帧及事件轨迹。该阶段会向配置服务发送当前Campaign观察并可能产生模型费用；HTTP stub不能替代它。 |
| MapPartyQuestMarkers | Campaign Map当前`mapPartyTargets`观察；visual Harness只在disposable Campaign用Native `IssueManager.CheckForIssues/CreateNewIssue`创建一个合法Issue候选 | 创建前目标无AvailableIssue、创建后AvailableIssue、另一Party空标记负向、未名牌资格目标null；重复读取稳定、无Quest文本、原生前后帧、源档hash和进程清理。Issue fixture不加入产品，也不接取任务 |
| MapPartyQuestAcceptance | 从`mapPartyTargets`可见且有AvailableIssue的Lord Party开始，原生map/Escape菜单未遮挡后，通过Native `pursue`进入`encounter_meeting`；只沿本轮Conversation合法选项启动一条Issue Quest | `TestResults/20261003-110250/Temp/MapPartyQuestAcceptanceResult.json`通过：临时Native TheSpyPartyIssue有效候选进入同一Lord地图会面，动态问候/hero_give_issue/issue说明桥接，最终仅提交Enabled Quest接受选项；`issue_153_quest`为该Hero QuestGiver、活动Quest数0→1/期限16天。Day 91077.378→91077.397为地图行程自然推进，接受时Stop/金币1000不变。原生三帧、源档hash和进程清理通过；Harness初试105312/110002的回执断言缺陷已修复，并保留失败证据 |
| TimeControlLoop | 确定性测试Provider在真实Agent循环内依次选择原生Play、Fast Forward、Pause，再用第二个临时进程验证Hold→Play | 验证动作经CLI/协议调用Native `Campaign.SetTimeSpeed(1/2/0)`、raw/effective档回执；比较各时钟档间的自然CampaignDay推进与Pause稳定性；Hold使主队等待后，显式Play应恢复`UnstoppablePlay`并自然推进而保持waiting；Harness advance隔离、fixture哈希和所有进程清理；与只读AgentLoop分离，避免遭遇状态污染 |
| BattleFixture | disposable save 内造 hostile looter；用原版 pursue 点击语义接敌 | hostile/party ID、自然时间/encounter 回执、fixture 哈希、进程退出；造敌非 Agent 行为 |
| BattleSimulation | 原版 `Send troops` 启动；pause/skip/finish/retreat；Mission TAB retreat | 模拟状态、结算/loot、Mission end、fixture hash；不等同即时战斗 |
| PostBattle | Simulation skip/finish→encounter leave→PartyState transfers→conditional InventoryState loot/Done→MapState | troop/item counts, state timeline screenshots, fixture hash, process cleanup |
| VisualCapture | 引擎单帧参考图 + 按 Bannerlord HWND 连续采集 30fps；只验证采集链，不是玩法真值 | MP4/contact sheet、帧覆盖率、fixture hash、进程清理；事件帧时间戳夹到最后一个实际视频帧，JPEG编码强制full-range像素格式；成功后只留关键帧/索引并清除源MP4，失败保留片段；不录全桌面，不进默认 All |
| Conversation | 观察原版句/选项；`DoOption/ContinueConversation` 需满足原生条件 | 选项/回执/菜单迁移；不预测未开放选项 |
| Observation | 玩家身份、队伍、资源、坐标、移动模式/目标、上下文、附近实体与其移动/定居状态、任务与危险；记录数据来源、原版可见/侦察标记和所采用的情报策略 | 两次暂停快照、稳定 ID/位置、字段新鲜度和 fixture 哈希 |
| CaptivityObservation | Harness-only Native `TakePrisonerAction`置入MainHero Captivity；打开原版Wilderness ransom菜单并将当前Menu切到Native Wilderness Escape Continue屏，两个阶段都只读、不点击选择 | `TestResults/20261002-051747/Temp/CaptivityObservationResult.json`通过：`context.captivity`在Captive为真/非Captive为null；菜单报价188与Native `CurrentRansomAmount`一致、Accept/Decline Option ID匹配；Escape Continue阶段报价为null且唯一`mno_continue`可见；重复读数稳定、菜单切换不改CampaignDay/Gold/Roster，双引擎截图、源存档hash和清理收据；不声称复现自然战败或逃脱概率/结果 |
| CaptivityOutcome | 两个新Campaign进程加载同一个不变fixture；各自先验证无效菜单项被安全拒绝，再从当前Native赎金菜单提交可见的Accept/Reject；核对Gold、MainHero囚禁/主队/Captor roster、菜单与原生时间档、前后引擎截图和清理 | 共用参数化后回归`TestResults/20261002-062355/Temp/CaptivityOutcomeResult.json`通过：两个无效Option均拒绝且菜单/金币/时间未变；Accept报价331使Gold 1000→669、MainHero恢复并回主队/Captor roster归零、日期不变；Reject报价305、Gold不变且仍被Captor拘押，返回`prisoner_wait`后时钟Stop→UnstoppableFastForward并自然推进0.102737日；四张Native引擎帧、原Campaign fixture hash不变、两次进程清理。结果不覆盖自然战败/入狱过程与后续Captor政策 |
| CaptivityOutcome | 两个新Campaign进程加载同一个不变fixture；各自先验证无效菜单项被安全拒绝，再从当前Native赎金菜单提交可见的Accept/Reject；核对Gold、MainHero囚禁/主队/Captor roster、菜单与原生时间档、前后引擎截图和清理 | `TestResults/20261002-055501/Temp/CaptivityOutcomeResult.json`通过：两个无效Option均拒绝且菜单/金币/时间未变；Accept 244报价使Gold 1000→756，MainHero恢复并回主队、Captor roster归零，日期不变；Reject报价244，Gold不变且仍被Captor拘押，回到`prisoner_wait`后时钟Stop→UnstoppableFastForward并自然推进0.104924日；四张Native引擎帧、原Campaign fixture hash不变、两次进程清理。结果不覆盖自然战败/入狱过程与后续Captor政策 |
| PrisonCaptivityOutcome | 同一disposable Campaign源分别启动Accept/Reject两个进程；Native MainHero captive归属Town settlement roster并进入实际Native Prison ransom菜单，当前有效/无效选项、报价、金钱、Party/Captor、Settlement等待时钟、前后引擎截图和清理 | `TestResults/20261002-061905/Temp/PrisonCaptivityOutcomeResult.json`通过：报价菜单原生报价可见，黑暗地牢截图与两条可用选项一致；Accept 2689使fixture Gold 10000→7311并解囚回MainParty；Reject报价2236、不扣钱仍Captive、返回`settlement_wait`，Native时钟Stop→UnstoppableFastForward、日期自然+0.106295。临时战争仅用于使源版captivity检查保持Captor敌对，金币补足仅用于Accept可用；无效Option被拒、4帧、源存档hash不变、进程清理。初试失败已保留在`20261002-061453`，原因是测试Captor与玩家和平导致原版合法释放；自然押送/触发流程未覆盖 |
| EncounterSurrender | Native hostile Bandit meeting→当前可见Fight选项→MapEvent/Encounter菜单→Native条件启用的Surrender；核验前后Party/Captor/Captivity/时间与引擎帧；不调用私有后果或伪造MapEvent结果 | `TestResults/20261002-064814/Temp/EncounterSurrenderResult.json`通过：复用Native Bandit meeting/Fight到`encounter`；在该活动Encounter里Native Hero伤病+Morale=0门槛成立后，真实菜单显示Fight/逃跑/投降并由当前`surrender` option结算；Captured状态结构字段确认MainHero加入Bandit PrisonRoster、主队inactive、Gold未变，屏幕后帧为原生`prisoner_wait`且没有Continue选项；Stop→UnstoppableFastForward为等待阶段自然推进，三张引擎帧（Bandit meeting/Encounter前/ Captivity后）、源存档hash不变、进程退出。测试只覆盖一种原版可用条件/野外Bandit遭遇；没有捕捉瞬态`taken_prisoner`菜单、没有模拟其他条件/围城或逃离失败 |
| EncounterEscape | 两个独立Campaign进程通过Native Bandit fight进入Defender Encounter；从当前`leave_soldiers_behind`和warning屏可用选项分别走Reject/Accept，核验Native TroopSacrificeModel/兵员/商品/时钟/debrief/清理 | `TestResults/20261002-071124/Temp/EncounterEscapeResult.json`通过：原生警告模型预测失去7人；Reject回到当前Encounter且Party 13人/grain20/Gold1000/时钟/日期全无变化；Accept后Native party 13→6、商品grain20→17（15%向下取整为3），debrief画面显示原版脱离说明，按Native Continue后Encounter关闭。风险说明/选项/脱离结果共8引擎帧，两分支均源存档hash不变、进程清理；CampaignDay=91077.378787、TimeControlMode=Stop保持不变。Troop/Grain仅在disposable进程中用Native roster写入，测试未预置loss结果 |
| JoinEncounterDefenders | Harness Native `StartBattleAction`只构造NPC-vs-NPC持续MapEvent；MainParty未加入时以可见Party目标执行原版pursue，选择当前菜单唯一可用Help Defender后核验同一Event的DefenderSide与Encounter菜单，不开始战斗 | `TestResults/20261002-074242/Temp/JoinEncounterDefendersResult.json`通过：当前玩家对Bandit攻击方敌对、对Lord防守方中立；引擎帧显示“帮助防守方/不参与”，无双侧选择。通过原生可见 Party target + `pursue`抵达`join_encounter`；Native `menuSelect`后仍为EventID0，MainParty只在DefenderSide、`IsJoinedBattle=true`，当前回到`encounter`选择Fight/坐镇，未启动BattleSimulation。Gold/成员/日期91077.402347/时钟Stop不变；前后截图、源存档hash、进程清理。NPC对NPC MapEvent只由Harness Native `StartBattleAction`准备，玩家Join本人完整走菜单；第一轮Event因攻守强弱悬殊在到达前自然结束，第二轮将测试双方力量调至接近后通过。中立双方“不可加入”尚只由用户事实与Native CanPartyJoinBattle条件推导，未实跑 |
| JoinEncounterEligibility | 独立disposable进程分别测试Help Attackers与双方Neutral；Native事件和NPC faction关系由Harness fixture准备，玩家以当前可见地图目标和原版pursue接近；仅攻击方正向提交实际可用Help，双中立只观察 | `TestResults/20261002-081603/Temp/JoinEncounterEligibility-HelpAttackers.json`与`...-Neutral.json`通过：攻击方正向UI只开放Help Attackers/Leave，选择后MainParty在同一MapEvent AttackerSide并回通用Encounter菜单；双中立页面只开放Leave，双方Native `CanPartyJoinBattle=false`且MainParty未入场。三张原生游戏帧保留；Campaign时间只在途中自然推进，选项前后Day/Stop不变。两轮源档hash不变、Agent停止且无Bannerlord残留进程 |
| JoinEncounterAbandonArmy | 玩家先经可见地图目标与原版pursue进入JoinEncounter；visual Harness在该原生页面通过Native Kingdom.CreateArmy准备MainParty非Leader成员并刷新同一注册菜单，再提交实际Abandon Army选项 | `TestResults/20261002-090646/Temp/JoinEncounterAbandonArmyResult.json`通过：Army成员页面仅显示Help Defender和Abandon Army、普通Leave被过滤；选择弃军后MainParty从Army成员移除/AttachedTo清空，PlayerEncounter关闭回MapState等待，NPC MapEvent EventID0仍未决且无胜者、主队Hold。Day91077.402299/Stop、Gold与双方Influence/战争关系不变；前后Native帧，存档hash不变且进程退出。成员准备是Harness Native `Kingdom.CreateArmy`，非Army Management视觉流程；先入Army再自然追近未复现，属于未覆盖路径 |
| MovingArmyJoin | 针对用户确认的未交战地图行军Army：Harness用Native ChangeKingdomAction/Kingdom.CreateArmy准备Disposable同Faction Army，玩家经当前可见marker与原版pursue进入`army_encounter`，再提交原版Join Army | `TestResults/20261002-165845/Temp/MovingArmyJoinResult.json`通过：Native Army leader处于GoToPoint行军、无MapEvent/SiegeEvent；`army_encounter`显示Talk/Join Army/Leave，加入后MainParty成为Army member且AttachedTo Leader、PlayerEncounter关闭，回`army_wait`。Join命令即时回执为Stop/Day91077.405；后续原版WaitMenu切`UnstoppableFastForward`，世界日期自然推进至约91077.516。Gold/玩家及Army Leader Influence不变；前后引擎帧、源档hash与进程清理通过。政治加入/Army Management视觉流程和围城Join未覆盖 |
| JoinSiegeEvent | 在disposable Campaign中准备当前可见Town/Castle的Native SiegeEvent；通过`move`到原版`join_siege_event`，只选择当前可用的“Join the continuing siege”；核验PlayerSiege、BesiegerCamp、菜单、资源、时钟、存档hash与清理 | `TestResults/20261003-091025/Temp/JoinSiegeEventResult.json`通过：旧`move`安全策略拒绝所有敌对Settlement，导致第一次尝试在测试夹具的萨哥特原生攻城事件处被拦，失败留据`20261003-090333`；修正为仅当非Blockade、无Settlement MapEvent且Native `CanPartyJoinSide(Attacker)`为真才允许地图导航后，菜单截图显示“加入继续围城/不参与”，选择前状态为SiegeEvent active、双方MapEvent空、MainParty尚未加入；Native选择后进入`menu_siege_strategies`，`PlayerSiege.PlayerSide=Attacker`、主队在BesiegerCamp、PlayerEncounter结束、没有自动启动Mission。途中地图导航将时间档自然变为StoppablePlay；Native围城准备将档置`UnstoppablePlay`，CampaignDay 91077.400375→91077.431638；Gold 1000不变、fixture前后Influence -1不变（入场时政治转换为Battania仅为Harness夹具）。保存before/after游戏引擎帧；源档hash一致、测试进程已停止。加强资源断言后`20261003-091720`第二轮在地图接近中进入`join_encounter`而不是围城页；失败帧显示Native“帮助作战军团/不参与”选项，未提交选择；具体关系/MapEvent细节未单独记录，因此作为可能遭遇分流而非本验收成功。已通过的结果可计算资源不变断言为真。未覆盖已存在Settlement MapEvent的战斗加入、守方Break in、攻营、Blockade、海战及之后围城战斗/Mission |
| Movement | 从原版可见聚落marker观察选择Settlement ID，下达原版路径目标并复现普通地图单击时间档位；Harness独立显式步进至抵达，并复用抵达回执中的原生菜单观察 | 目标/菜单/时钟轨迹、失败拒绝、fixture hash；子测试stdout/stderr原文保存在父Harness阶段失败收据，若游戏仍响应则捕获引擎末帧 |
| Hold | 按原版Map点击语义从正在移动主队切到Hold；动作后不发Pause/Resume/advance，观察Native waiting与CampaignDay | 当前目标清除、defaultBehavior、raw时间档/isWaiting和短自然窗口的日期差；disposable fixture hash、进程清理；失败尽可能留游戏引擎末帧 |
| MoveToPoint | W2-B仅在陆地用Campaign世界坐标请求有效自由地形点导航；适配层验证CampaignVec2/Face与原版导航模型，通过MapState.ProcessTravel而非直接写位置；Harness可显式步进至目的地 | GoToPoint与location.targetPosition对齐、初末坐标变化/到达、无效Face拒绝且不移主队/切时钟、原版点击时钟模式、fixture hash/进程清理；海上/港口另行验收 |
| Recruitment | 仅当当前Settlement菜单有`recruit_volunteers`可用项时，读取/招入指定Native RecruitmentVM offer；通过显式 `ConfirmPartySizeWarning` 选择是否接受原版超限Inquiry；Detached VM按原生Gauntlet hotkey/GetKeyText绑定初始化并在每次查询/事务后Finalize；同一运行复验Town Trade买卖/食物补给 | menu ID/option/Native VM offer、Roster/Gold、原版Over Limit提示及affirmative回调、off-menu/invalid报价无副作用、容量边界的raw time/date、受限Harness fixture/hash/进程清理；不模拟点击焦点；失败收据保留子测试原始stdout/stderr |
| Rest | 通过原版 `town_wait` 进入 native Wait menu（`StartWait` 自行启动时间），观察指定时长后由原版 `wait_leave/EndWait` 退出 | Wait menu/time mode、native 持续时长、离开后 Stop、非法/中断路径和 fixture 哈希 |
| Pursuit | 在大地图对当前可见且可导航Party分别下达原版 `EngageParty`/`EscortParty`；`hold` 复现点击玩家队伍。Escort等价于按住`MapFollowModifier`点击Party；所有有效点击复现同一原版点击时间档位规则 | 正确TargetParty/DefaultBehavior、native click time mode、Escort目标/无效目标和无副作用拒绝、Engage自然前进到遭遇或目标丢失Hold、fixture哈希 |
| EngageVisibility | 在一次性运行中显式暂停Campaign以稳定准备场景；用Native `BanditPartyComponent`生成初始位置有效、原版`IsVisible`自然判定的弱劫匪目标，只为场景测试临时增加主队普通兵力差。确认目标可见并截图后由产品`pursue`发出Engage，观察自然移动、主队Hold及`Campaign.IsMainPartyWaiting`；Hold后再观察稳定窗口，区分原始TimeControlMode与引擎有效暂停 | 目标原生可见性消失前后快照、`isWaiting`、原始时钟档/日期、Hold稳定窗口、前后引擎关键帧和源fixture hash/进程清理；初始位置和兵力差属于明确标注的测试夹具，不在追击中传送/改AI/改`IsVisible`/脚本推进或暂停时钟 |
| Conversation | 从Campaign Map用原版Party追近抵达Lord会面；观察实际开放Sentence/Option并选择一个低副作用自我介绍；invalid option必须拒绝，Continue仅在CurOptions为空时允许 | native Conversation/参与对象/option ID前后状态、时间/遭遇迁移、无效选项无副作用、存档hash/进程退出；不代表Quest、Barter或Persuasion支持 |
| QuestAcceptance | 在真实Lord会面里选当前有效的`hero_give_issue`入口，沿Issue brief/解决方案分支只接受原生开放的Quest解法；不调用IssueManager创建任务API | `issue_offer_player_accept_quest`后的active Quest/Issue状态、Quest ID/标题、费用/关系/时间副作用与失败存活分支；不包含Alternative/Lord Solution和Story/Notable任务 |
| EscortVisibility | 一次性存档选择当前可见范围内最远的活动移动Party，按Follow修饰键语义设置Escort；只观察自然时间窗口，不显式advance/pause；记录目标是否离开Chronicle附近队伍观察集以及原生Escort/时钟终态。离开观察集不等于证明引擎`IsVisible=false` | `AgentPursuitVisibilityResult.json`、目标ID/初末观察/模式、自然时间变化、fixture哈希、进程退出；未触发目标离开时如实记录窗口结果，不伪造目标失明 |
| TavernMission | 从Campaign Map自然抵达城镇，沿`town_backstreet → town_tavern`进入酒馆；确定性Provider根据本地Agent位置和主角朝向计算一次短时移动，并在有候选时试用Sandbox AgentNavigator | 验证实际位移、目标距离缩短、MovementInput lease清零、AgentNavigator的NavMesh路径/Player Controller限时切换与归还、Campaign时钟保持Stop；截图、源存档hash及进程清理。样本不是Notable/委托接取，不代表W2-D完成 |
| TownCenterMission | 从Campaign Map自然抵达城镇，选择`town_streets`进入`center` Location Mission；确定性Provider短步探索，在当前局部Agent出现后尝试复用原版`SandBox.AgentNavigator`路径到该Agent，再试相机指向与Focus | 结构化前后位置、NavMesh路径是否生成/脚本移动是否实际产生位移、当前12单位内Scene Agent清单/Notable标记、相机bearing、原生Focus AgentIndex、Campaign时钟、引擎截图、fixture hash及进程退出；baseline成功不保证已到Notable或Focus命中，不能声称Quest/对话可用，也不扫描整场景给决策器、不传送、不接受Quest |
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
- Smoke 必须按本次启动新增的诊断行和实际 Bannerlord 子进程 PID 归因；不得用启动器返回 PID 或旧日志推断模块生命周期。失败时持久化`SmokeResult.json`及同PID日志；已知着色器弹窗只允许使用经UIA识别的进程所有控件确认一次，其他警告只读取证据、不通过全局键鼠输入。
- Campaign 阶段必须使用版本化 disposable fixture；第一轮通过必须包含 `campaign-sync mode=save`、每日事件、另存文件、第二进程 `campaign-sync mode=load` 和未改动 fixture 哈希。
- ButterLib DLL 报告含托管栈/模块及可选 MiniDump；Harness 在报告 UI 阻塞前复制异常栈与 MBMusicManager/CampaignMusic 状态。FreshCampaign 等 native music 初始化后再开档；progression skip flag 到 MapState 后不再调用 Issue probe。保留fault-IP映射/关键帧，不点报告窗。
- ButterLib 当前回退到 1.4.7 implementation；同样回退见通过的 `Fresh 215022`，是兼容风险但不是本次根因证据。
- Progression `045339` deterministic provider 验证 Fresh→CampaignTick SaveAs/CLI load→移动→招募1人；保留回执与费用前后值，并确认临时存档清理、原存档哈希未变。
- FreshCampaign日志尾投影DTO，禁直序列化Get-Content。
- P2 原子 JSON；`captureFrame` 仅 visual Harness 可用且输出 BMP。FFmpeg `gfxcapture(hwnd=...)` 只采游戏窗；校验覆盖率并生成状态/动作 JSONL、缩略图和关键帧。成功删 MP4，失败留片；Agent 按索引看图。Loot All/Done 限原生 InventoryState，seedVisualLoot 不代表自然掉落。
- Progression证据保留初始Renown、招募回执/净变化、存档周期验证；清理后存档哈希不变。
- Protocol 若暂时无法读取 `.processing` 命令，保留 claim 并延迟重试，不删失/丢弃命令；Docs 检查此恢复契约。
- W7-B 的 `AgentHost/` 是目标玩家产品的本地 .NET 8 Host，不属于游戏线程，也不是Harness决策器。当前只提供一次只读 `state` 握手：写入独立关联ID，拒绝覆盖已有`command.json`，只接受关联ID/动作/状态都匹配的Native响应；超时仅删除仍能证明归属自身的未领取命令。它只返回PID、Hero/Clan/MainParty摘要，不输出整份快照、不发送世界动作。Protocol Harness先用假桥验证邮箱繁忙、旧/错响应与超时清理，再在一次性Campaign里连续调用三次Host，并与同一PID的原生CLI只读状态、前后Campaign指纹比较；这证明通信和零世界副作用，不代表模型循环已迁移或玩家入口已交付。
- 自动启动用本体 `DisplayMode_0`，840×472 无抢焦点置左上；结构化断言坐标/尺寸，禁止把 `DisplayMode_2` 当窗口模式。
- P3快照来自Campaign API；schema 9含战后InventoryState、双方item数量、遭遇待领取item数和仅在主队GoToPoint时提供的`location.targetPosition{x,y,isOnLand}`。该目标坐标用于恢复Agent移动意图，不是对其他Party/全图隐匿坐标的授权；回执按UTF-8读写。
- W2-B陆地自由地点移动使用`moveToPoint(X,Y,Surface=land)`世界坐标意图，不发送桌面像素。原生`MapState.ProcessTravel`/CampaignVec2校验为准；写入GoToPoint后回执给出实际原生目标，位置自然变化，不传送。Naval/海上过渡是独立未测边界，不由本动作宣称支持。
- P3 分开记录 `IsVisible`/`IsInspected`，不从属性名推断玩家认知。情报策略由产品设计确定；静态面板按需读取。
- P4 `move/pursue/hold` 复现原版目标 setter 与 MapScreen 点击时钟副作用；运行时间自然推进。W2-A进一步接入`follow/escort`并与普通`pursue`分开验收。无效聚落拒绝，抵达以 `CurrentSettlement` 为准；`rest` 只观察原版 WaitMenu 的 `StartWait/EndWait` 时钟。
- Pursuit 夹具在 `hold` 后另取一次稳定观察作为无效追击的前置快照，避免把原版命令刚接受时的瞬时移动模式与下一次观察混比；每次结果写入当前运行 `Temp/AgentPursuitResult.json`，即使阶段失败也可核查每项断言。
- `EscortVisibility`是Pursuit的专项自然观察阶段：只验证Agent附近观察集中的目标离开与Campaign状态联动，不注入隐身、不改变目标位置、不显式步进时钟；它不会把离开观察集等同于原版`IsVisible=false`。
- `TavernMission`保留为酒馆场景的通用移动输入回归；W2-D实际Notable验证只以当前产品工作项指定的Town Center `center` Location Mission为准。
- W2-D的Location观察schema 21会把原版`GameMenuOption.OptionQuestData`作为菜单`questMarkerFlags/questMarkerNames`返回；`GameMenuItemVM`用同一标记生成原版`QuestMarkerVM`。`nearbySceneAgents`仅为主角周围12场景单位内的Agent，不等于视线可见列表；原生`CurrentFocusedObject`同时用`Agent.CanInteractWithAgent`提供原版Focus/交谈可用判定；`settlementOverlayCharacters`复用可见CharacterList和QuestMarkers。`missionNavigateToAgent`在发令时取NPC位置快照，NPC移动后必须重新观察并下达新路径，不能以对旧坐标到达判作追上。
- `harnessMissionDiagnostics`只在Harness `visual-capture`模式与临时run目录同时有效时返回当前Town/Tavern Mission里已激活的Notable Agent、场景里全部已生成的Hero Agent census及当前`CampaignMission.Location`登记的Issue所有者；新增的`activeHeroAgents`只用来核对NPC是否已经生成及其Location/距离，目的是验证测试场景前提，不进入常规观察快照，也不在`Agent-DecisionLoop.ps1`的模型动作白名单中。当任务主人超出主角当前本地观察半径时，Town Center Harness立即保存诊断并清理，不继续跑固定移动步骤；后续应核实原版造访入口。禁止用诊断遥测代替AI玩家的局部观察。
- `MissionSceneNavigation`使用真实`town_streets`入口与内存PlayerAlley fixture；Harness-only `activeHeroAgents`只核NPC确已生成，产品动作必须先请求受支持的当前Mission `missionSceneAgents`观察，再在新鲜同Mission清单中选目标。`missionNavigateToAgent`经Native NavMesh、非传送，限1–20秒lease；抵达附近后只有普通局部观察的Agent才能传给`missionInteract`。`TestResults/20261006-021538`通过：未查询前的远距index导航被拒；当前`vlandia_town_e`场景返回144个活动人类Agent；为Assigned Hero实际执行4段NavMesh lease，249.312→187.746→140.980→60.329→1.417米，每段恢复Player控制；随后Native交谈身份匹配并看到“询问志愿者”选项，但Harness不选项/不提交兵员。CampaignDay/raw Stop/Alley与MainParty roster/Gold/Influence、源存档hash保持，进程正常退出。`TestResults/20261006-021951`Tavern RansomBroker近距移动/对话回归通过。未验证敌对/战斗Mission、相机可视遮挡、所有场景代理及Alley招募结果。
- `AlleyVolunteerBranches`是后续W2-BC分支验收，不在`All`中自动长跑：每次单独启动disposable Campaign，`noVolunteers`以LastRecruitTime=Now保证Native周内暂无分支；`availableVolunteers`只在Harness夹具中挑选一个当前Native seed确实会产生非空志愿Roster的Alley。两个值只供Harness造场景与核断言，不进入Agent输入/决策；产品Agent仍只能基于屏幕实际Native Conversation句子/点击项作选择。前者不得显示招募确认或改变Roster/计时，后者先走“No need”证明无写入、再选择当前可见“Yes”以验证原版提交。
- `AlleyAttackYield`是W2-BE和平交出分支专项：`noAttack`和`peacefulYield`分别用隔离Campaign运行；UnderAttack与攻击方由Harness临时写入原版Alley对象，产品Agent只读真实`manage_alley`选项/Native对话，不调用夹具。正向路径不会选择“Bring it on”，只选择当前可见和平选项并核验Owner/PlayerAlleyData/普通守军返还/关系/Gold/Influence/时钟。专用`AlleyFight` Mission另属后续工作，不纳入该阶段。
- Native Mission `nativeFocus`是玩家当前视线准星的一项结果：本机`MissionMainAgentInteractionComponent.FocusTick`从`MissionScreen.CombatCamera`做约10单位射线并返回当前Focus对象；它不是场景人物枚举。`nearbySceneAgents`则是距离12单位的局部集合。现有`missionAimAt`也仅接受该局部集合里的目标；不要把前两者包装成远处NPC定位能力。
- `settlementOverlayCharacters`是schema 21中的有限视图，只在Settlement Characters overlay当前可见时按本体`MenuLocations + HeroAgentLocationModel.WillBeListedInOverlay`生成，并携带玩家Overlay显示的Issue/Quest标记。用户确认聚落右上人物列表的蓝色感叹号及地图贵族名字蓝标语义；当前Observer只覆盖聚落人物，`mapPartyTargets`的贵族Leader任务标记尚未暴露。`talkToSettlementHero(HeroId)`校验QuickTalkPermission并通过CampaignMapConversation原生QuickConversation在地图上快速交谈；`visitSettlementHero(HeroId)`校验Visit权限并进入NPC Location Mission，不能混称。两者都只接受当前可见overlay名单，不使用Harness全场景Notable诊断里的隐藏ID。
- `SettlementOverlayQuestGate`只验证测试fixture中确实被原版前置拒绝、且Quest/存档不变；该阶段纳入`All`用于回归保护。`SettlementOverlayQuestAcceptance`是另一个正向阶段，必须看到一个新Ongoing Quest及对应原版状态变化才通过；前置拒绝、没有offer、对话返回均为失败，不可用负向结果替代。Harness可跟随原版提供的Alternative方案说明对话节点，但不能点击最终Alternative/Lord接受选项。它要求自然满足条件的disposable Issue fixture，故不纳入通用`All`，直到该fixture稳定存在。
- 聚落移动的标准夹具还要验证抵达后状态切到目标聚落及原版 `town` 菜单；结构化菜单选项按当前 `GameMenuOption.GetConditionsHold` 计算可用性，选择时重验菜单 ID、选项 ID 与 enabled 条件。离开选项作为菜单原语验收；失败夹具对无效 settlement ID 返回结构化拒绝，且世界位置不变。
- 招募必须复用本体 `RecruitmentVM` 的志愿者列表、队伍上限和金钱条件；命令显式指定可用 owner、troop 与 volunteer slot，每次只招募一个。完成以兵力 `+1`、金币按本体价格扣除且来源 volunteer 槽清空为准。
- 食物补给必须经城镇 `InventoryLogic` 交易和 `InventoryListener` 提交市场库存与金币变化；不直接改 roster。动作前检查食品类别、市场库存、交易价格、金币和载重，动作后验证食品库存增长与金币差额。
- 普通交易要分别测试买入与卖出：按原版市场价格执行 `OtherInventory ↔ PlayerInventory` 交易；验收双方库存变化、金币净差和失败无状态变更。仅读市场报价时不应 Push 可视 `InventoryState`；实际购买也应避免无目的地短暂弹出全屏界面。
- W2-U `EquipmentTransactions`用原生SPInventoryVM验证单件equip/unequip、Done/Cancel、occupied-slot交换、旧候选和无效ID/不兼容槽拒绝。非空modifier场景只由`HarnessEquipmentModifierFixture`在visual-capture运行中临时塞入1把Native masterwork sword；测试同时验证同一ItemObject的普通/非空modifier候选具有不同VM ID。测试后先用原生事务将主角装备恢复，再精确移除这件QA物品，最后比较完整Equipment slot fingerprint、主队/经济/位置/时钟与存档hash。夹具seed/clear不进入Agent决策白名单，也不保存测试进度。
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
| Computer Use | 不用于本项目的游戏验证 | 用户要求避免Windows桌面操作；游戏截图和状态只由游戏引擎/Harness采集，不向窗口发键鼠输入 |

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

`AlleyLeaderInquiry`是独立可选阶段，不加入`All`：在Sargot原版`town→manage_alley→change_leader_of_alley`菜单链，以内存内Native Alley/Clan Hero夹具补齐玩家巷道数据，然后由Native菜单选项生成正式`MultiSelectionInquiryData`。夹具调用`AlleyCampaignBehavior.AddPlayerAlleyCharacters`建立旧负责人`LocationCharacter`，因为原版确认回调会将旧负责人移至酒馆；缺少该对象会令真实Native handler抛出NullReference，不能用直接写AssignedHero/Roster绕过。测试从Native ViewModel观察候选、启用提示、数量、Done/X与pause标志，保留Town菜单、弹窗、取消、确认四张引擎帧；非法候选与过期令牌拒绝，退出不改变负责人/Roster/Owner/Gold/Influence，确认则由原版回调更换负责人和驻守Roster。基线Campaign为Stop，运行内日期/档位稳定，源存档哈希不变。它验证原版菜单与回调集成，不是自然Alley存档或真实鼠标操作；本阶段启动互斥和清理检查覆盖`Bannerlord*`进程族。

`AlleyRosterManagement`是独立可选阶段，不加入`All`：在一次性Campaign中走Sargot原版`manage_alley→manage_alley_troops`菜单入口，打开真实`PartyState/TroopsManage`。Native fixture提供玩家Alley负责人、普通兵和当前MainParty；Agent只读当前PartyScreen可见左右Roster与 transferability，并通过Native `PartyCharacterVM.ExecuteTransferSingle`逐名转移。测试先暂存再Native Cancel，确认完全回滚；然后在Alley `AlleyModel`下限/上限两侧试探Done禁用，恢复边界后用Native `PartyVM.ExecuteDone`提交，检查双方Native roster实际结果。保留四张引擎帧、Campaign day/raw mode/waiting、源存档hash和游戏进程清理证据。它不覆盖负责人对话入口或已有Alley Mission中的刷新，不用直接Roster写入冒充玩家事务。

`AlleyAbandonment`是独立可选阶段，不加入`All`：因Native Yes会不可逆移除当前玩家Alley，同一Harness任务分别从相同且不变的disposable Campaign独立加载，测试原版No取消和Yes确认，不能先Yes再通过Fixture假装回滚状态来测取消。仅使用非UnderAttack玩家Alley；记录`manage_alley→manage_alley_abandon_are_you_sure`及两分支引擎帧。Cancel后原Native Ally数据/Owner/负责人/守军/主队不变；源码Yes handler请求`town_outside`，运行观察却显示`town`菜单及放弃通知；与此同时Native数据不存在、owner清空、普通守军回主队。不得把源码菜单ID当成运行后画面证据。同时保存金钱/Influence/CampaignDay/raw mode/waiting、两次源存档hash与进程清理。被袭转交、对话/Clan screen分支不包含在本专项中。

`AlleyEntryMenu`是独立可选阶段，不加入`All`：从到达Town后的Native当前`town`菜单观察启用的`manage_alley`（显示“进入巷子”），通过产品`menuSelect`走真实`GameMenuOption`后果进入`manage_alley`；再观察当前菜单并选择Native `back`返回Town。`20261004-052453`的Native帧与state均显示进入后仍是MapState且没有Mission，背景是Campaign地图上的Alley菜单/图板，不是可走动3D巷道场景；返回时menuId是`town`。两次菜单转换前后`PlayerAlleyData`、Owner/负责人/左右Roster、Gold/Influence、CampaignDay=91077.400065/raw Stop/`isWaiting=true`和存档hash不变；三张引擎帧及进程退出保留。此菜单注册的`MenuLocations`不能代替对Assigned Leader人物对话Scene入口的实测。

`LiveModelRuntimeResume` 是可选的 `Run-Harness.ps1 -Phase LiveModelRuntimeResume` 阶段：它验证Agent决策循环/Provider进程重启时，Bannerlord Campaign仍维持同一PID和Native内存checkpoint；与 `LiveModelResume` 的Native存档重新加载分开记录。两者均不加入 `All`。

`LiveModelActionRecovery`（`Run-Harness.ps1 -Phase LiveModelActionRecovery`）是独立 opt-in 阶段，用一个仅Harness可启用的故障注入点，在Native recruit已提交且CLI回执返回、但DecisionLoop尚未把动作结果写回Campaign checkpoint时终止该loop进程。Campaign保持运行；恢复时只在新Native状态精确满足本次招募人数+1及按Native成本扣金后，才把pending action标为已恢复，否则拒绝重放并保留失败证据。此逻辑目前只实现RecruitmentVM这一已知非幂等动作，不是所有游戏动作的通用事务协议；阶段不进入 `All`。

`CheckpointValidation` 是 opt-in 的 checkpoint输入安全回归：对一个接入于disposable Campaign存档的损坏JSON、未知schema版本和错Campaign身份逐个尝试Resume；每类都应在Provider启动或任何Native写动作前失败，且当前地图/队伍/金币/日期/时间档保持不变。专用seed action只在visual Harness模式可用，不能进入产品白名单。

`RecruitmentBaseline` 是W5的确定性原版对照阶段：它从同一个未修改的Campaign模板分别重载5个Runtime，完成地图移动与招募一人，按Native receipt/Party/Gold/Volunteer slot验证成功，同时记录CampaignDay、raw time mode与墙钟成本。它明确只有同一Campaign起点重复，不是5个独立随机seed，也不测试真实LLM；结果用于冻结后续候选模型评测的重复数和阈值，阶段不进入 `All`。

`MultiDaySupplyBaseline` 是W5-H的确定性Native配对基线，显式opt-in且不进入 `All`：从同一个disposable Campaign模板建立固定MainParty，分别执行无补给/原生市场补给两条支路，在Town Wait Menu通过原版等待跨过至少三个日周期。它记录Food/FoodInventory/FoodChange、日工资字段、Gold、daily tick与原始时间档，判断是否存在可观察的资源压力及Native补给是否缓解；移动只使用当前可见安全Town并让Campaign时间自然推进，等待只调用原版Town Wait/`rest`，不发Harness `advance`。该Native对照先用于校准变量/方差和真实模型阈值，不代表LLM已会规划补给。

`LiveModelSupplyEvaluation` 是W5-I的opt-in真实本地模型测试，默认同一disposable模板重复3次，不加入 `All`：Harness先用原版移动/招募将场景准备到萨哥特的6人主队状态，再把决策交给模型；预处理不计入模型成绩，且必须用Native收据确认固定起点。模型需依当前TradeVM报价补给、使用Town Wait/`rest`自然跨过3个daily tick、再次观察并离开等待菜单。门槛固定为每轮最多24次模型决策/300秒、模型3/3完成、结束Food≥1且Gold>0/队伍6人、录像≥90%并在关键帧/时间线生成后删除成功原片；每轮记录Native交易、等待、资源/时间后果、源档hash和清理。三次运行只是一个相同Campaign模板上的模型重复性，不是跨Seed泛化或完整生涯能力。

`menuSelect` 的模型参数必须引用当前Native观察中启用选项的精确 `id`，不能把参数名或显示文本当作ID。`provision` 则须把最新报价里的 `viewModelItemId` 映射到 `ItemViewModelId`，并提供该报价允许的整数数量；它只创建TradeVM草稿，须再用当前提供的 `tradeConfirm` 提交，才能退出交易并进入后续等待流程。TradeVM取到有效食物报价后，会隐藏重复报价读取，只保留基于该报价的有效交易动作，直至Native事务成功、取消或拒绝。未提交交易期间的 `observeAgain` 会被安全拒绝并反馈，让模型根据当前仅开放的确认/取消动作重新决策。决策或 `observeAgain` 在Native调用/宿主等待前校验失败时，失败收据保留归一化后的模型决策、当时的原版观察以及“未发送Native动作/未开始宿主等待”证明，便于区分模型选值错误与游戏执行错误。

`FreshCampaignBaselineMatrix` 是单独opt-in的多新档Native基线：5次分别走本机1.4.8原版New Campaign/角色创建入口，在相同模块/难度/背景条件下创建全新Campaign；每次记录初始Native状态、可见安全Settlement、RecruitmentVM结果、Campaign实例标识、耗时和清理。`ChronicleCampaignInstanceId` 是Mod Campaign实例身份，不等同Native随机Seed；若本体没有可验证Seed，结果明示Seed未知。每个新进程遇到已识别的“Mod change detected”着色器缓存提示时，FreshCampaign调用同一精确UIA/所属进程按钮处理器并保留回执；不使用全局键鼠，也不把弹窗误认成存档模组不兼容。该基线衡量新档起点和机会变化，不含真实模型通过率，也不能用“5次新档”冒充5个已验证Seed；它不进入 `All`。

`FreshCampaignSupplyBaseline` 是后续单独opt-in的W5-J原版对照矩阵，不进入 `All`：每轮从原版New Campaign创建并验证一个独立Campaign，再仅保留一份由该Campaign实际生成的disposable临时存档。它从两个新加载副本分别执行无补给/一单位当轮最低价可购食物的Native分支，均用原版城镇等待自然推进三个Daily tick；每个分支记录当轮Native报价/资源后果及Campaign运行时ID。运行时ID可能在跨进程重载时重建，所以配对必须核对同一源存档SHA-256和对齐起始资源/日期/tick，不得把ID当作Seed。实际游戏窗口录像保留连续视频用于回看，并由契约工具生成约每4秒一帧的总览联系表和动作边界前/中/后关键帧索引；成功提取后删除MP4，完整覆盖以解码帧数/期望帧数计算。临时存档由外层统一清理并复核既有保存清单；创建、加载、录像或清理任何一步失败均留下分类收据，不代表真实模型自主能力，也不重用W5-I固定模板成功门槛。

`FreshCampaignRecruitmentFallback` 是W5-K的selective Native评测（不进入 `All`）：最多十次原版New Campaign尝试；从每个新档先在玩家当前Native可见的最近安全城镇检查实际RecruitmentVM名额，若当前槽位耗尽，只查询当轮 `mapSettlementTargets` 返回的可见、安全、未围城聚落，通过普通原版Move与本地RecruitmentVM逐处观察/招募。它不快进刷新offer，不使用全世界Notable诊断，不修改Party/Roster。若Native路线达到六人，则必须准确到达安全Town菜单；之后退出Town回到Campaign MapState再保存一份disposable prepared Campaign，防止把聚落菜单的运行态误当成地图存档。其两份独立加载副本从原版地图移动到可见安全Town后运行三日无补给/Native补给配对；已经六人的队伍不要求存在可招募菜单。运行时Campaign ID只作记录，pair以保存SHA及起点状态判断。若候选耗尽、路上遭遇或十次未复现名额短缺，都输出明确结果，不以未证明说成全局无路；每次都保留菜单/offer/行动/日期/资源和窗口关键帧、自动清理临时保存与游戏/session。若收据的`PreparedMarketTownId`存在，则它来自到Town时验证过的当前settlement id，不能从返回地图后的空`currentSettlementId`反推。

`FreshCampaignLiveModelEvaluation` 是#101 Native基线后的opt-in候选评测：每轮新建Campaign并由真实本地模型从该新档第一条决策观察开始，自行选择当前可见安全Settlement、移动、读取当前RecruitmentVM报价、招募并核验停止。固定5轮实例，阈值为完整新档到目标≤180秒、自然Campaign推进≤0.1日、每轮恰好一次Native Move/Recruit、无被Native拒绝的动作、录像覆盖≥90%、临时保存与进程清理；动作未列入当轮目录时可被Native前安全拦截并重新观察，该拦截不计作Native拒绝，但必须记录且不得造成世界副作用。途中可以是显式有限 `observeAgain`，也可以是安全拦截后的新Native观察；到达时延迟模型给出的过期等待请求应被反馈处理，不能让已完成的成长路径假阴性。候选五轮启动前生成当前Tracked/非忽略Harness源文件和本地Harness设置的SHA-256清单；每轮前后复核，若清单变化就停止/判失败，避免把不同代码版本的运行合并成同一个矩阵。模型/服务器/模块/源码提交与源清单状态随结果记录。首轮目标结束后清除测试保存，不改已有正式存档。该阶段不加入 `All`，结果只证明这一成长切片的五实例重复性。

`LiveModelRecruitmentEvaluation` 是基于该Native基线的真实本地模型opt-in阶段：固定同一seed、真实Provider、五次独立Runtime运行，预先要求5/5成功、每次墙钟≤180秒/CampaignDay≤0.1、一次move与一次recruit、无重复或越权副作用、Visual覆盖≥90%、模板hash不变且进程清理；候选模型结果不得反向改阈值。它只评估当前地图→志愿兵目标，不代表跨seed或整个产品成熟度。

DecisionLoop 的动作白名单仍是产品能力上限，但模型每轮看到的是当前Native观察决定的有效动作目录。地图状态/无可用Settlement菜单时不暴露 `recruitOptions`/`recruit`；当前Settlement菜单启用原版 `recruit_volunteers` 后才开放报价读取；仅上一回执属于同一Settlement的Native报价、且当前主队有容量和可支付选项时才开放 `recruit`。对话层只在当前Native Conversation有可点击选项时开放 `dialogueSelect`，没有选项时才开放 `dialogueContinue`；Barter修改/平衡/提交只在最近的`barterOptions`/更新回执对应有效Native VM会话时开放。提交参数还会与当前菜单、最新报价、Gold及队伍容量二次比对。模型选了未开放动作时，执行器不把它发给Native，会刷新观察、提供明确反馈并允许有限重规划；Provider将目录外动作转换成带动作名和目录的结构化拒绝回执，DecisionLoop保留上一条已确认Native回执并安全重规划；Native自身拒绝同样会记录回执、重新观察再决定，重复拒绝有上限并安全停止。AgentLoop确定性回归不仅在地图上故意提出不可用招募，也在报价环节故意提交不存在的offer ID；另在 `StoppablePlay` 的原版地图移动中故意提出目录外 `resume`，确认没有Native时钟命令、Move重复或Campaign时钟档修改，收到拒绝反馈后仅用有限 `observeAgain`继续。还会在主队已自然抵达目标时故意提出一次过期 `observeAgain`，确认它被安全拒绝、没有宿主等待/Native动作，并将当前抵达状态反馈给Provider。该目录用于精确表达动作前置条件，不替代Native最终校验。

`LiveModelSafePassageRecruitment` 是独立 opt-in 的真实模型分支评测，不进入 `All`：从一次实际 Native Move 后由 Harness 在视觉测试客户端内创建敌对Looters并等待原版`encounter_meeting`；夹具回执单独存于Harness trace，不进入模型prompt。模型仅按当前Conversation选非战斗谈判，通过Native Safe Passage BarterVM当前报价、Auto Balance与Offer流程清除拦截，重新观察地图、继续移动并完成一名志愿兵招募。遇到没有可点击对话选项的Bandit会面时，先用只读`barterOptions`探测Safe Passage BarterVM；仅当该VM尚未就绪且Native会话仍处于无选项阶段时才继续一次对话，然后重新探测。此顺序避免把BarterVM动作误当成Conversation选项或在停止时钟下重复等待。测试核对敌对强度/本地joiner、选项、Barter金额、移动恢复、Party/Gold变化、Campaign时间、连续视觉关键帧与清理；这一切不授权Agent在正式游戏创建敌队，也不代表实时战斗能力。

`LiveModelSafePassageRecruitment` 也是一个耗时、需显式指定的独立阶段，不进入 `All`；它验证上述原版劫匪拦截恢复路线。

动作目录会镜像Native入口的前置条件：`move`/`pursue`/`follow`/`hold`/`moveToPoint`只在无Encounter、无当前GameMenu、Escape或Inquiry的Campaign Map出现；Native遭遇期间隐藏`mapSettlementTargets`以避免把地图导航误作当前交互。当前对话没有可点击选项时不暴露`dialogueSelect`。在Bandit无选项过渡句中先探测`barterOptions`；仅当Native表明Safe Passage BarterVM尚未就绪且会话仍无可点击选项时，才放开一次`dialogueContinue`，随后重新探测Barter。Barter修改/自动平衡/Offer只在同一Native BarterVM最近的查询或草稿回执存在时开放；每次Native handler仍复核自己的上下文条件。

遇到遭遇阻塞时，`control-unavailable`反馈另保留上一条`native-action-rejected`的原因；这样模型在同一轮重规划中不会丢失“Barter探测尚未就绪，需要按当前无选项Conversation继续”的信息。

真实模型的三日补给试跑显示：即便 Native 会安全拒绝过期的 foodOptions/menuSelect，静态允许列表仍会反复把模型送进失效上下文。因此决策目录现进一步随当前状态分阶段：menuSelect只让模型传当前 enabled 的OptionId，执行器从同一观察绑定Native context.menuId；食品/交易工具只在Trade InventoryState开放，provision须有当前foodOptions回执，提交后只开放确认/取消；rest只在实际Town Wait菜单与等待状态开放。它们仅缩小Agent可调用工具/参数，并在原生 handler 前核对，不替代、改写或绕开本体菜单、交易或时间后果。相关确定性门禁在AgentLoop阶段验证，真实模型三日目标仍以独立W5-I收据验收。

rest通过Native返回accepted后，AgentLoop不阻塞等待三天，而是以有界observeAgain继续读当前Campaign状态；只有上一条rest已接受、Native Wait菜单仍打开且原版时间正在推进时，才开放此宿主侧短暂等待。rest在同一Wait菜单内只允许提交一次，接受/完成后隐藏重复rest，直到离开Wait菜单。该观察和等待不调用游戏时钟开关；未接受rest、等待菜单已退出或原版游戏时间停止时不开放。

Supply循环的本地Qwen3.5 4B校准在输出上限768和1536时均收到finish_reason=length、未得到完整第二步决策；本轮将上限提高到Provider允许的4096并写入每轮收据。目标文本已缩短以减少不必要推理，但模型仍受决策/墙钟硬预算约束；这只说明该模型/任务目前需要更高输出上限，不能据此推断其他模型都需相同配置或把截断记成Agent失败结果。

本地模型还曾把一个结构化动作的arguments包成JSON字符串或单项嵌套数组，并把单参数rest压成数字；Provider现只解包有限层数的单项string/array包装，且仅在动作 schema 确有一个字段时接受标量作为该字段，之后仍逐字段执行当前工具参数白名单。多字段动作的标量/数组、未知字段和无效JSON仍拒绝，并有本地HTTP回归测试。

campaign-multiday-supply只将当前菜单OptionId、主队人数/粮食/日工资、Gold、当前Settlement/菜单/Inventory模式、Campaign日与tick，以及当前Trade/Wait选项传给模型；不重复放入NPC、邻近队伍、任务标记或角色技能。Native完整状态仍保留在Harness轨迹中，供开发者诊断；模型看到的窄视图是场景所需事实的呈现方式，不代表隐藏的Native状态被改写。

## 当前执行焦点

`ContextState.json.current.path`只定位当前技术焦点；GitHub Project及活动Issue决定工作项和执行次序；`Focus/MAINLINE.md`保存跨任务有效的技术约束、机制事实和研究门槛。不得从单个来源推导另外两个来源的动态状态。
