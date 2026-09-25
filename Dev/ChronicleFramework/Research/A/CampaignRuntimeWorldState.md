# A 类：战役运行与世界状态

状态：机制拆解，未进行方案评审

本文只描述 Bannerlord 原版机制、状态、输入、输出和玩家可见入口，不评价设计质量，不提出优化方案。

## A01 战役生命周期

玩家入口：初始菜单中的“新战役”“沙盒”“继续战役”“已存档游戏”。`Modules/Native/GUI/Prefabs/InitialScreen.xml` 将菜单按钮点击绑定到 `ExecuteAction`；`InitialMenuVM.RefreshMenuOptions` 从 `Module.GetInitialStateOptions()` 生成选项行，`InitialMenuOptionVM.ExecuteAction` 先通知 `InitialState`，再运行该选项注册的动作。

菜单选项由不同游戏视图模块注册：`StoryModeViewSubModule.OnSubModuleLoad` 注册 `StoryModeNewGame`（显示“新战役”，顺序2）；`SandBoxViewSubModule.OnSubModuleLoad` 注册 `CampaignResumeGame`（“已存档游戏”，顺序0）、`ContinueCampaign`（“继续战役”，顺序1）和 `SandBoxNewGame`（“沙盒”，顺序3）。因此“新战役”与“沙盒”虽然共享后续沙盒加载器，创建的 Campaign 类型不同。故事模式创建 `CampaignStoryMode`，并在 `_startedStoryMode` 标记本次开局；`OnBeforeGameStart` 会据该标记或存档元数据决定是否保留 StoryMode 模块。沙盒新战役创建普通 `Campaign`。这些菜单项会受仅核心内容模式禁用；继续战役还要求配置的最新存档存在且可用；“已存档游戏”打开列表，不依赖“继续战役”所指的最新存档。

新战役路径：点击故事模式或沙盒选项 → `MBGameManager.StartNewGame` 建立 `GameLoadingState` → `SandBoxGameManager` 使用对应的 `CampaignCreatorDelegate` 创建 Campaign 并标记 `NewCampaign` → Campaign 初始化创建 `CampaignGameStarter`，先由 `SandBoxManager.Initialize` 和已启用模块的 `InitializeGameStarter` 注册行为/模型，再完成 Campaign 初始化与行为事件订阅。新战役 Campaign 初始化完成后，分发 `OnNewGameCreated`，随后分发 `OnSessionStart` 和 `OnAfterSessionStart`。`SandBoxGameManager.OnLoadFinished` 对非 Development Mode 的新战役先推入开场 `VideoPlaybackState`，视频结束委托进入 `CharacterCreationState`；Development Mode 跳过视频并直接进入该状态。角色创建最后由 `CharacterCreationState.FinalizeCharacterCreationState` 清理当前状态并推入 `MapState`，再触发 `OnCharacterCreationIsOver`。用户已确认开场动画可用 ESC 跳过；该输入修饰尚未在当前 1.4.8 反编译链中定位。

读档路径：点击“已存档游戏”打开 `SaveLoadScreen`；`SaveLoadVM.InitializeAsync` 异步枚举存档，分组显示可用档并单列损坏档。选择存档后 `SavedGameVM.ExecuteSaveLoad` 调用 `SandBoxSaveHelper.TryLoadSave`；成功回调先结束当前 Game/Screen 状态，再经 `MBSaveLoad.OnStartGame` 和 `MBGameManager.StartNewGame` 建立 `SandBoxGameManager(LoadResult)`。此分支加载已保存 Campaign、调用行为 `SyncData` 并重建事件订阅，不进入新建角色流程。`ContinueCampaign` 则以 `BannerlordConfig.LatestSaveGameName` 建立 `PreloadState` 后读取该存档；启动参数要求继续游戏时，`SandBoxViewSubModule.OnInitialState` 也会尝试自动加载最新可用存档。读档完成后 `SandBoxGameManager.OnLoadFinished` 调用 `OnSavedGameLoadFinished`，清理状态栈并进入 `MapState`；恢复存档中的地图菜单，完成地图加载回调，最终将 Campaign 时间模式设为 Stop。

事件和界面边界：`CampaignEvents` 的创建/加载/会话事件是 Campaign 生命周期通知，不表示初始菜单或角色创建界面已完成。玩家角色创建界面是 `CharacterCreationState`（由 `CharacterCreationManager` 管理阶段）；新战役的 Campaign 初始化和 `OnNewGameCreated` 发生在该状态之前。新档到地图需同时跨过 Campaign 初始化、开场视频/跳过、角色创建完成三段状态；读档则不经角色创建。Campaign 注册的 `CampaignBehavior` 在新档初始化时注册事件，在读档时先恢复 `SyncData` 再重建事件订阅。

Chronicle 当前覆盖：`ChronicleCampaignBehavior` 在 `OnGameStart` 加入 `CampaignGameStarter` 并于 `RegisterEvents` 注册自身事件；现有 FreshCampaign 自动夹具曾实际到达全部7个角色创建阶段、触发创建完成并取得 `MapState` 快照（`TestResults/20260925-044807/FreshCampaignProgression.log` 与 `Temp/FreshCampaignProgressionAttempt1/FreshCampaign.initial-state.json`）。该夹具启动测试战役、自动选择角色创建内容并跳过开场，不从初始菜单点击选项；它证明测试进程内原生新战役到创建完成的路径，不证明玩家菜单点击链的端到端运行。角色创建后快照包含初始身份、声望、队伍、资源、地图位置和时间模式；其测试角色数据由 Harness 自动选择，不代表模型自主完成角色创建。

证据来源：当前安装 v1.4.8.119303 的 `Modules/Native/GUI/Prefabs/InitialScreen.xml`、`TaleWorlds.MountAndBlade.ViewModelCollection.dll`（`InitialMenuVM`/`InitialMenuOptionVM`）、`TaleWorlds.MountAndBlade.dll`（`Module`/`MBGameManager`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`SandBoxViewSubModule`）、`SandBox.ViewModelCollection.dll`（`SaveLoadVM`/`SavedGameVM`）、`SandBox.dll`（`SandBoxGameManager`）、`TaleWorlds.CampaignSystem.dll`（`Campaign`/`CharacterCreationState`），以及上述 Harness 运行证据。源码路径以本机 DLL 反编译类型/方法为证；当前没有单独执行“初始菜单→点击新战役/沙盒或存档→完整 Campaign”的 UI 运行测试。

未知项：以鼠标点击以外的键盘/手柄触发绑定与具体焦点规则；无存档、损坏存档、无 StoryMode 模块、存档所需模块缺失时各菜单按钮的运行时表现；故事模式与沙盒模式在角色创建阶段及首次落图后的完整差异；开场视频 ESC 跳过所调用的具体 handler；自动继续模式下存档加载失败后的完整 UI 恢复链。Harness 中的 MapState 夹具未覆盖这些条件组合。

## A02 战役时间与时间控制

玩家入口：地图栏三个按钮分别绑定 `MapTimeControlVM.ExecuteTimeControlChange`，点击参数为0（暂停）、1（正常）、2（快进）；当前按键/手柄提示由 VM 的快捷键集合提供，Prefab另给三个按钮排列导航序号。聚落等待菜单另行开始/结束等待；移动的自然时钟副作用见 MAINLINE 机制契约，不等价于玩家每次都要另按时间按钮。

`ExecuteTimeControlChange` 在没有普通聚落菜单，或正在运行可解锁时间的等待菜单且时间控制未锁定时响应。它以请求档位调用 `Campaign.SetTimeSpeed`；此 API 并不总把档位一一映射到同名模式：正常/快进会检查主队是否等待、是否处于 Hold、是否是军团成员但非领袖，并在需要时进入不可暂停的 Unstoppable 模式；暂停时若正处于快进会进入 `FastForwardStop`，否则进入 `Stop`。等待期间，简化显示会把部分可暂停状态显示为暂停。地图栏在遭遇模拟、招募、百科、城镇/军团管理、战役选项、事件弹窗等状态下会禁用中心时间控制。

`Campaign.TickMapTime` 根据 Campaign 时间模式决定自然推进量：Stop/FastForwardStop 不推进；StoppablePlay 与 UnstoppablePlay 使用 `0.25 × realDt`；快进模式再乘 `SpeedUpMultiplier`（当前默认值4）。Stoppable 模式在主队等待时不推进，Unstoppable 模式仍推进。推进后的 `_dt` 被 Campaign 实体、事件和周期系统使用；小时、日、周等计时不是每个Agent动作附带的单独开关。周期的分发粒度见 A03。

Agent 覆盖：快照给出 `campaignDay`、`timeControlMode`；`pause`/`resume` 直接赋模式，`advance` 是 Harness 固定步进，不是玩家动作。源码：当前安装 v1.4.8 `Modules/SandBox/GUI/Prefabs/Map/MapBar.xml`、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`MapTimeControlVM`）与 `TaleWorlds.CampaignSystem.dll`（`Campaign.TickMapTime`、`SetTimeSpeed`）；运行证据见 MAINLINE 机制契约所列 Movement、Rest、Protocol 阶段。自动状态证据已覆盖；本节未验证键鼠物理绑定、等待期间不同锁定状态的画面反馈以及各禁用状态恢复后的UI焦点。

## A03 周期事件与调度粒度

没有独立玩家按钮；周期事件依 A02 的 Campaign 时钟运行。1.4.8 `Campaign.CreateCampaignEvents` 建立每日(1日)、每小时(1小时)、每15分钟(0.25小时)三个全局周期事件，并以当前战役时间计算各自首次触发延迟；处理器转发给 `CampaignEventDispatcher`。每日分发完成后，若从战役起始日经过的整日数可被7整除，则分发 WeeklyTick（按 Campaign 起点计周，不直接按现实星期）。

`CampaignPeriodicEventManager.InitializeTickers` 还按对象类别建立分散的定期处理：MobileParty 的小时/日处理、Party/Town/Settlement/Hero/Clan 事件，以及 Caravan、Garrison、Militia、Villager、Custom、Patrol、Bandit、Lord 等队伍的部分小时级 AI 事件。对象级 ticker 和全局小时/日/周事件是不同入口；订阅者决定收到哪些回调。全局 Campaign 运行路径受当前 GameState 限制：`MapState.OnMapModeTick` 只有在 MapState 为活动 State 时才调用 `Campaign.RealTick` 和 `Campaign.Tick`；Campaign 时间暂停期间，`_dt` 为0，周期 ticker 不推进。3D Mission 使用另一条 `CampaignMissionComponent.OnMissionTick` → `CampaignEventDispatcher.MissionTick(dt)` 实时回调，这不是 CampaignTime 的小时/日事件。地图内坐镇战斗模拟保持 MapState 的具体时间模式效果未在此处判定，见相应机制契约。

影响包括队伍与 AI、食物工资、市场、聚落、英雄、任务、战争外交等；每种 CampaignBehavior 可订阅不同事件，加载组合决定实际消费者，行为总数尚未盘点。AgentObserver 是轮询快照：给出日期、玩家队资源/移动、可见聚落/队伍、进行中任务期限；不订阅 CampaignEvents，不输出通用事件增量/日志历史。证据：当前安装 v1.4.8 `TaleWorlds.CampaignSystem.dll`（`Campaign.CreateCampaignEvents`、`CampaignPeriodicEventManager`、`CampaignEventDispatcher`、`MapState`）和 `Modules/SandBox/bin/Win64_Shipping_Client/SandBox.dll`（`CampaignMissionComponent.OnMissionTick`）、`AgentObserver.cs`；为源码映射，未完成实际消费者或运行时全量清点。

## A04 CampaignEvents 事件总线

当前安装 v1.4.8 的 `CampaignEvents` 暴露263个公开 `IMbEvent` 通道，覆盖生命周期、时钟、战争/领地、英雄/队伍/聚落、王国、任务、对话与存档等。`Campaign.OnInitialize` 建立 `CampaignEventDispatcher`，初始接收器依次为 `CampaignEvents`、`IssueManager`、`QuestManager`；`AddCampaignEventReceiver` 会追加接收器。各转发入口按该接收器数组顺序调用；其中 `CanHeroLeadParty`、`CanHeroMarry` 等带 `ref result` 的询问类入口，会在结果变为 false 时停止继续询问，因此总线既传递通知，也承载可否决操作的查询，不是单一含义的“发生了某事”。

Campaign 模块的 `CampaignBehaviorManager` 保存 `CampaignBehaviorBase` 列表，`RegisterEvents` 按列表顺序逐个调用每个行为的注册函数；动态 `AddBehavior` 会立即对新行为注册事件。新战役由 `OnNewGameCreatedInternal` 在战役创建回调中调用该注册过程；读档则先恢复行为 `SyncData`，再重建事件订阅。公开通道存在并不表示每个行为都订阅，也不意味着每种事件都发生或会显示给玩家。

Chronicle `SubModule.RegisterEvents` 当前订阅 DailyTick、Tick、GameLoaded、SaveOver；新角色创建回调仅 Harness 模式订阅。`AgentObserver` 不订阅事件总线，按需生成状态快照。263 是公开事件通道数，不是玩家动作数；实际加载 Behavior 的完整订阅者及事件到玩家可见结果的映射未盘点。证据：当前安装 v1.4.8 `TaleWorlds.CampaignSystem.dll`（`CampaignEvents`、`CampaignEventDispatcher`、`CampaignBehaviorManager`、`Campaign.OnInitialize`）、本地 `SubModule.cs`/`AgentObserver.cs`；运行时通道覆盖未知。

## A05 存档与读档

玩家入口：在地图界面按 ESC 打开暂停菜单；菜单 `Save` 与 `Save And Exit` 都调用 QuickSave，后者只在 OnSaveOver 确认成功后退出。默认快捷键 F5（`MapHotKeyCategory.QuickSave = 54`）也调用 QuickSave。`Save As` 打开存档列表的保存模式，可选择现有档并确认覆盖，或选“Create New Save Slot”输入新名称；`Load` 打开同一界面的读档模式。`EscapeMenu.xml` 与 `SaveLoadScreen.xml` 的按钮通过 ViewModel 命令进入这些 handler。ESC 菜单的 QuickSave 受存档槽位上限约束（铁人模式可覆写活动槽）且在地图对话期间禁用；Save As/Load 在铁人模式及地图对话期间禁用。F5 handler 源码直接调用 QuickSave，地图对话期间的可用性未单独验证。

原生保存不是同步写文件：`SaveHandler.QuickSaveCurrentGame` / `SaveAs` 将请求排入队列；活动 `MapState.OnTick` 发现队列非空时逐帧运行 `SaveTick` 并暂不执行该帧的 Campaign Tick。保存开始先等待 Campaign 异步任务、发出 OnSaveStarted，再发出 OnBeforeSave 并调用 `MBSaveLoad` 的 QuickSave/SaveAs/AutoSave；异步完成后发出 OnSaveOver(success, name)。失败会显示保存错误提示；Save And Exit 只有成功才退出。

自动保存间隔来自 `BannerlordConfig.AutoSaveInterval`，当前版本默认30分钟，设置值4映射为关闭值-1。它依据 `DateTime.Now` 与上次自动保存的墙上时间差，而非 Campaign 游戏日：`CampaignTick` 只在 `TimeControlMode != Stop` 时检查，实际排队还要求活动 GameState 为无地图对话的 `MapState`。注意 `FastForwardStop` 虽不推进 CampaignTime，也不等于 `Stop`，因此仍满足外层检查。另有优先自动保存入口 `SignalAutoSave`，使用配置间隔的75%作为阈值；该方法的调用方尚未映射。自动存档完成时会更新墙上时钟基点，成功与失败结果都经过 OnSaveOver。

Mod 存档数据通过 `CampaignBehaviorManager` 接入：保存前它清空行为数据表，对每个 `CampaignBehaviorBase` 按 `StringId` 调用 `SyncData(IDataStore)`，将键值记录随 Campaign 存档序列化；读档时依 `StringId` 找回记录并调用相同的 `SyncData`，旧行为ID还存在按类型名回迁的兼容分支。恢复状态后重新 `RegisterEvents`。Chronicle 当前将 `_stateVersion`、`_dailyTickCount`、`_lastDailyTickDay` 写入 `SyncData`；`AgentProtocol.save` 排队 `SaveAs` 并等待名称匹配的 OnSaveOver 回执；CLI 的 `load` 停止当前进程并启动新进程加载指定存档。

读档界面异步枚举存档，按 Campaign ID 分组并将损坏档单列；行内可查看存档版本、主角、日期和记录模块。损坏或缺少原版明确禁止加载的模块会禁用该项；其他模块增删/版本不匹配可能弹窗要求确认；存档版本比当前客户端新时不提供继续加载选项。选择加载后读取 `LoadResult` 并经 `SandBoxGameManager` 走读档生命周期，不进入角色创建。加载失败会提示错误并停留在读档流程。

Chronicle 自动证据：Protocol 测试从 `AgentBridgeLifecycle` disposable 源夹具启动，运行暂停/恢复/显式推进，保存到单次唯一命名的测试档，再以新进程加载；比较保存与读回的 `campaignDay`、`dailyTickCount` 并核对源夹具 SHA-256 不变。`TestResults/20260925-105941/Protocol.log` 通过：保存/读回日数均为91077.393，DailyTick计数均为2，推进约0.015日，源 fixture 哈希未变，`ProtocolSaveCleaned=true`；本次生成的 `.sav` 在记录名称/哈希与断言后已删除。测试存档属于 Harness，不是正式战役存档。

来源：当前安装 v1.4.8.119303 的 `TaleWorlds.MountAndBlade.dll`（`MapHotKeyCategory`、`BannerlordConfig`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen`、`SaveLoadScreen`）、`SandBox.ViewModelCollection.dll`（`SaveLoadVM`、`SavedGameVM`）、`SandBox.dll`（`SandBoxSaveHelper`、`SandBoxSaveManager`）、`TaleWorlds.CampaignSystem.dll`（`SaveHandler`、`CampaignBehaviorDataStore`、`CampaignBehaviorManager`），以及本地 `SubModule.cs` / `AgentProtocol.cs` 与 Protocol 运行收据。

未知项：当前没有从真实 ESC/F5 输入完成保存/读档的视觉运行测试；F5 在地图对话中的可用性、优先保存调用方、保存失败/进程崩溃时的 UI 恢复尚未逐项运行验证；`SyncData` 对各类型、跨版本迁移和删除/更名行为数据的规则仍需按实际行为字段继续核验。Protocol 测试只验证 Chronicle 当前少量状态字段与基础 Campaign 状态往返，不证明任意大型存档或所有 Mod 数据均可恢复。

## A06 难度与战役选项

入口：创建战役选项页、战役内 Campaign Options。1.4.8默认Provider提供预设及8项难度(部队伤害/招募/地图速度/说服/战斗AI/战斗死亡/家族死亡/潜行伪装，均三档)；另含perk自动分配、Ironman。其他 Provider 可扩展，列表随版本/Mod变化。

UI VM 写入选项并协调预设关联/禁用项；直接改 CampaignOptions 字段不等价。Agent快照不含配置；无自动/视觉验证。来源：已安装 v1.4.8 CampaignOptions.cs、DefaultCampaignOptionsProvider、CampaignOptionsVM。难度可配置化仅是潜在价值，非已选方案。

## A07 日志、通知与百科信息

用户确认N开百科，可查NPC经历/现况；本版界面未复核。1.4.8 `LogEntry.AddLogEntry` 写战役时间与递增ID；每项自有保留期，周清理过期项。`CampaignInformationManager` 将 `IChatNotification` 转为信息栏消息，地图通知独立保存、读档后重放。

AgentObserver 不读取日志/地图通知，无日志查询动作；Chronicle 诊断只记自身命令。证据：`LogEntryHistory`/`CampaignInformationManager` 及 AgentObserver/Protocol。

## A08 教程与概念提示

`CampaignTutorial` 含类型/优先级/标题/说明；`CampaignEvents` 提供教程收集/完成事件。`Concept` 由 XML 加载，含标题/说明/分组/百科链接。`StoryMode.TutorialPhaseCampaignBehavior` 处理教学流程。AgentObserver/Protocol 无教程状态或概念查询；FreshCampaign 跳过开场不代表教程适配。UI链未核实。
