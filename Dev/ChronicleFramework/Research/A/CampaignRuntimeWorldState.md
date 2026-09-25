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

ESC菜单的`Save And Exit`是QuickSave之后退出的复合入口：`MapScreen.GetEscapeMenuItems`调用QuickSave并置`_exitOnSaveOver`，只有`OnSaveOver(success)`为真才执行`OnExit`。`Exit to Main Menu`则不先保存，先显示确认询问，确认后调用`OnExitToMainMenu`，拒绝回到当前地图；因此两者都不应被折叠为单纯QuickSave或同一个退出动作。源码链已映射至跨域目录`ACT-A05-03/04`，具体确认/拒绝画面和保存失败运行回执未验证。

原生保存不是同步写文件：`SaveHandler.QuickSaveCurrentGame` / `SaveAs` 将请求排入队列；活动 `MapState.OnTick` 发现队列非空时逐帧运行 `SaveTick` 并暂不执行该帧的 Campaign Tick。保存开始先等待 Campaign 异步任务、发出 OnSaveStarted，再发出 OnBeforeSave 并调用 `MBSaveLoad` 的 QuickSave/SaveAs/AutoSave；异步完成后发出 OnSaveOver(success, name)。失败会显示保存错误提示；Save And Exit 只有成功才退出。

自动保存间隔来自 `BannerlordConfig.AutoSaveInterval`，当前版本默认30分钟，设置值4映射为关闭值-1。它依据 `DateTime.Now` 与上次自动保存的墙上时间差，而非 Campaign 游戏日：`CampaignTick` 只在 `TimeControlMode != Stop` 时检查，实际排队还要求活动 GameState 为无地图对话的 `MapState`。注意 `FastForwardStop` 虽不推进 CampaignTime，也不等于 `Stop`，因此仍满足外层检查。另有优先自动保存入口 `SignalAutoSave`，使用配置间隔的75%作为阈值；该方法的调用方尚未映射。自动存档完成时会更新墙上时钟基点，成功与失败结果都经过 OnSaveOver。

Mod 存档数据通过 `CampaignBehaviorManager` 接入：保存前它清空行为数据表，对每个 `CampaignBehaviorBase` 按 `StringId` 调用 `SyncData(IDataStore)`，将键值记录随 Campaign 存档序列化；读档时依 `StringId` 找回记录并调用相同的 `SyncData`，旧行为ID还存在按类型名回迁的兼容分支。恢复状态后重新 `RegisterEvents`。Chronicle 当前将 `_stateVersion`、`_dailyTickCount`、`_lastDailyTickDay` 写入 `SyncData`；`AgentProtocol.save` 排队 `SaveAs` 并等待名称匹配的 OnSaveOver 回执；CLI 的 `load` 停止当前进程并启动新进程加载指定存档。

读档界面异步枚举存档，按 Campaign ID 分组并将损坏档单列；行内可查看存档版本、主角、日期和记录模块。损坏或缺少原版明确禁止加载的模块会禁用该项；其他模块增删/版本不匹配可能弹窗要求确认；存档版本比当前客户端新时不提供继续加载选项。选择加载后读取 `LoadResult` 并经 `SandBoxGameManager` 走读档生命周期，不进入角色创建。加载失败会提示错误并停留在读档流程。

Chronicle 自动证据：Protocol 测试从 `AgentBridgeLifecycle` disposable 源夹具启动，运行暂停/恢复/显式推进，保存到单次唯一命名的测试档，再以新进程加载；比较保存与读回的 `campaignDay`、`dailyTickCount` 并核对源夹具 SHA-256 不变。`TestResults/20260925-105941/Protocol.log` 通过：保存/读回日数均为91077.393，DailyTick计数均为2，推进约0.015日，源 fixture 哈希未变，`ProtocolSaveCleaned=true`；本次生成的 `.sav` 在记录名称/哈希与断言后已删除。测试存档属于 Harness，不是正式战役存档。

来源：当前安装 v1.4.8.119303 的 `TaleWorlds.MountAndBlade.dll`（`MapHotKeyCategory`、`BannerlordConfig`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen`、`SaveLoadScreen`）、`SandBox.ViewModelCollection.dll`（`SaveLoadVM`、`SavedGameVM`）、`SandBox.dll`（`SandBoxSaveHelper`、`SandBoxSaveManager`）、`TaleWorlds.CampaignSystem.dll`（`SaveHandler`、`CampaignBehaviorDataStore`、`CampaignBehaviorManager`），以及本地 `SubModule.cs` / `AgentProtocol.cs` 与 Protocol 运行收据。

未知项：当前没有从真实 ESC/F5 输入完成保存/读档的视觉运行测试；F5 在地图对话中的可用性、优先保存调用方、保存失败/进程崩溃时的 UI 恢复尚未逐项运行验证；`SyncData` 对各类型、跨版本迁移和删除/更名行为数据的规则仍需按实际行为字段继续核验。Protocol 测试只验证 Chronicle 当前少量状态字段与基础 Campaign 状态往返，不证明任意大型存档或所有 Mod 数据均可恢复。

## A06 难度与战役选项

玩家入口：新建战役流程中的 Character Creation “Options/Difficulty”阶段由 `CharacterCreationOptionsStageVM` 展示；战役中可按 ESC→Campaign Options 打开 `MapCampaignOptionsView`。两者都从 `CampaignOptionsManager` 取得选项数据，但开局阶段调用 `GetCharacterCreationCampaignOptions`，战役内设置页调用 `GetGameplayCampaignOptions`，可显示集合并不完全相同。

当前 `DefaultCampaignOptionsProvider` 的三个预设是 Freebooter、Warrior、Bannerlord；手动改值会被控制器匹配为已有预设或Custom。八项难度相关OptionId分别是`PlayerTroopsReceivedDamage`、`MaximumIndexPlayerCanRecruit`、`PlayerMapMovementSpeed`、`PersuasionSuccess`、`CombatAIDifficulty`、`ClanMemberBattleDeathPossibility`、`BattleDeath`、`StealthAndDisguiseDifficulty`；均为Selection字段，Provider setter写入对应`CampaignOptions`值（Recruitment项对应`RecruitmentDifficulty`）。各值采用VeryEasy、Easy、Realistic三档；`BattleDeath`会受Life/Death周期选项与其注册模块影响而禁用。另有Boolean `AutoAllocateClanMemberPerks`；Ironman Boolean只在开局Options中可用/DisabledLater，Gameplay页固定Disabled。游戏内设置页另注册`ResetTutorial`和`EnableCheats`两个Action项，后者仅在Gamepad active时提供。配置项集合会随已加载Mod注册的Provider改变。

界面数据流：`CampaignOptionsManager.Initialize` 扫描已启用游戏程序集并实例化所有 `ICampaignOptionProvider`；读取选项时按 Provider 列表倒序追加数据。`CampaignOptionItemVM` 根据Boolean/Selection/Numeric/Action类型生成控件，将选择写回Provider setter；`CampaignOptionsControllerVM` 在选择预设时对关联字段执行批量`SetValue`，手动改其中一个关联字段后重算预设（匹配不上则为Custom），并刷新禁用状态。两个Options上下文的字段集不同；ResetTutorial Action会弹Inquiry，确认后发出`ResetAllTutorialsEvent`；手柄输入时才注册的EnableCheats Action调用`MapState.Handler.OnGameplayCheatsEnabled`，源码追到`MapScreen.OpenGameplayCheats`加入`MapCheatsView`并置`IsMapCheatsActive`。这只证明打开地图作弊View；其内部命令和对Campaign/作弊状态的最终效果仍未知。直接设置一个`CampaignOptions`属性虽能写字段，但不会自动执行预设联动、禁用条件、界面提示和回调。Campaign配置字段随战役保存。

Sandbox的原生作弊列表另有独立内容链：`GameplayCheatsManager.GetMapCheatList`提供13个顶层条目（堡垒内才出现完成建设项；其中Boost Skill是进入子列表的组），包括金钱、Influence、Renown、材料、兵力、粮食、战马、队伍治疗、锻造解锁和地图迷雾等效果；`GetMissionCheatList`在满足Mission条件时提供敌方受伤及主角治疗。`GameplayCheatsVM`将组映射为导航子页、将可执行项映射为`CheatActionItemVM`；玩家点具体项时调用`GameplayCheatItem.ExecuteCheat`，随后显示Cheat Used提示。故打开作弊菜单与执行其内状态改动是不同入口/结果；具体每项的完整副作用由相应Cheat类定义，以上仅记录列表与调用层。

八项默认难度值均由`DefaultDifficultyModel`按VeryEasy/Easy/Realistic返回值，以下是已追到的原版消费者链（第三方替换GameModel/OptionProvider后的结果另算）：

- `PlayerTroopsReceivedDamage`：返回0.50/0.75/1.00伤害乘数；`MapEvent`战斗结算读取它，Sandbox Mission亦将其用于玩家军队相关的`DamageToFriends`与`DamageFromPlayerToFriends`。
- `MaximumIndexPlayerCanRecruit`：返回+2/+1/+0玩家招募槽位奖励；`DefaultVolunteerModel.MaximumIndexCanPartyRecruitFromHeroInternal`只在buyer为MainHero时将其加入可见上限。
- `PlayerMapMovementSpeed`：返回+10%/+5%/+0；`DefaultPartySpeedCalculatingModel`只给`MobileParty.MainParty`追加此速度因子。
- `PersuasionSuccess`：返回+0.10/+0.05/+0基础成功因子；`DefaultPersuasionModel`将其作为难度修正纳入劝说成功机会计算，不等同固定加10个百分点。
- `CombatAIDifficulty`：返回0/0.5/1.0；Sandbox `SandboxAgentStatCalculateModel.GetDifficultyModifier`将其交给Mission Agent difficulty modifier。
- `ClanMemberBattleDeathPossibility`：返回-1.0/-0.5/0死亡因子；`DefaultPartyHealingModel.GetSurvivalChance`仅在死亡角色属于PlayerClan时将其作为生还计算因子。
- `BattleDeath`是独立的特殊存活规则：`DefaultPartyHealingModel`在VeryEasy时让Hero必定存活，在Easy时让MainHero必定存活；Realistic回到正常生还计算。
- `StealthAndDisguiseDifficulty`返回两条不同乘数：潜行警觉累积为0.5/0.75/1.0，伪装怀疑度为0.4/1.0/1.2；消费者分别是Sandbox `AlarmedBehaviorGroup`与`DisguiseMissionLogic`。

`AutoAllocateClanMemberPerks`不是上述八项难度值：开启后，CharacterCreation结束时自动分配其他存活且非Child的玩家Clan成员成长，并参与这些成员后续周期/激活时的`DevelopCharacterStats`路径。`IronmanMode`由`SaveHandler`将保存路由到固定Ironman命名存档，并在GameOver时触发QuickSave。由此，A06原先“后续模型消费者未追”的未知已有以上本机基础源码映射；设置UI真实显示/输入、第三方Provider覆盖与实际运行各效应仍未核实。

开局与战役中入口的差异：Character Creation 阶段提供难度预设、八项难度值、Perk 自动分配和 Ironman；存档槽位达到上限时 Ironman 项带禁用说明，否则其启用状态为 `DisabledLater`。战役内 Gameplay 列表提供预设和难度值，但 Ironman 项固定为 Disabled，不能从该页切换；其余包含 Perk 自动分配、ResetTutorial，以及满足手柄条件时的 Cheats 操作。

Chronicle 当前状态：Observer/Protocol 快照不读取这些选项；没有自动快照字段或覆盖这八项的状态测试，也未模拟 Character Creation Options 或 ESC→Campaign Options 的点击。来源：当前安装 v1.4.8.119303 `TaleWorlds.CampaignSystem.dll`（`CampaignOptions` save fields）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`DefaultCampaignOptionsProvider`、`CampaignOptionsManager`、`CampaignOptionsVM`、`CampaignOptionsControllerVM`、`CampaignOptionItemVM`、`CharacterCreationOptionsStageVM`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen` / `MapCampaignOptionsView`），以及 `Modules/SandBox/GUI/Prefabs/CampaignOptions.xml`。

未知项：不同 Provider 在同一设置页的实际排列与互相覆盖顺序尚未用含相关 Mod 的运行实例核验；单项难度切换对每个游戏模型的最终数值影响没有逐项追踪；Character Creation `DisabledLater` 对可改时点的具体UI表现、在设置页开启 Cheats 的输入设备门槛及最终 Campaign 保存时点均待运行核实。

## A07 日志、通知与百科信息

玩家入口：用户确认按 N 可打开百科总查表并从 Hero 页面查看该 NPC 的经历和现况；当前尚未通过实机按键再次核验。源码中的 `EncyclopediaHeroPageVM.RefreshValues` 清空 `History` 后从全局 `LogEntryHistory.GameActionLogs` 倒序遍历，只保留 `IEncyclopediaLog.IsVisibleInEncyclopediaPageOf(hero)` 为真的条目；`EncyclopediaHistoryEventVM` 显示条目的 Campaign 时间和百科文本。Hero 页面还读取 `HeroHelper.GetLastSeenText` 生成 Last Seen 字段。因此 NPC 历史不是每个 Hero 各有独立日志文件，而是由全局 log history 按条目可见条件筛出。

`LogEntry.AddLogEntry` 在条目上写入 `CampaignTime.Now` 与单调递增的 ID，然后交给 `LogEntryHistory`；重载入口也允许提供明确的 CampaignTime。`LogEntryHistory` 保存全局有序列表及最后使用的 ID，支持按类型/条件查询。基类默认历史保留期为7天，具体 LogEntry 可覆盖；WeeklyTick 调用 `DeleteOutdatedLogs` 删除已过保留期或已失效的条目，所以这不是无限期全量历史。百科 Hero 历史从该列表读取，按条目提供的可见规则筛选。

通知与历史分开：新增条目若实现 `IChatNotification` 且允许显示，`CampaignInformationManager.NewLogEntryAdded` 会在 Session 已启动后调用 `InformationManager.DisplayMessage` 显示信息栏消息；这条即时提示不是持久通知。Map Notices 另存在 `CampaignInformationManager._mapNotices`（SaveableField），移除时同步删除；读档后清除失效项并重新投递仍有效的 Notice。它们与 LogEntryHistory 是不同的数据集和 UI 表面。

Chronicle 当前 `AgentObserver` 不读取 LogEntryHistory、百科 Hero History 或 Map Notices；Protocol/命令诊断只记自身的 Agent 命令回执，不等同于游戏事件日志。证据：当前安装 v1.4.8.119303 `TaleWorlds.CampaignSystem.dll`（`LogEntry`、`LogEntryHistory`、`CampaignInformationManager`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`EncyclopediaHeroPageVM`、`EncyclopediaHistoryEventVM`）、本地 `AgentObserver.cs`/`AgentProtocol.cs`。未知项：N 到 Encyclopedia 的当前键位注册与 Hero 页历史列表实际画面尚未实机复核；每种 LogEntry 的具体保存期和百科可见条件由其子类实现，未完整枚举。

## A08 教程与概念提示

`CampaignTutorial` 是一个按 `TutorialTypeId` 和 `Priority` 标识的提示数据对象；标题和说明通过 `str_campaign_tutorial_title/description` 本地化文本解析。`CampaignEvents` 提供收集可用教程列表及教程完成事件。教程列表不是一个固定全局清单：运行中的 CampaignBehavior 可以按会话、任务或战斗等条件增添条目，收集时再合并并按优先级排序；`BannerlordConfig.EnableTutorialHints` 关闭时教程列表收集不返回提示。

StoryMode 的 `StoryModeTutorialBoxCampaignBehavior` 维护当前可用教程、已展示教程和待恢复的优先级备份；它在 `SyncData` 保存展示/备份列表，在 Session 开始时布置 Encyclopedia、编队、招募、升级、Perk 等提示优先级，在特定 StoryMode 任务开始/完成时加入后续步骤提示；收到 TutorialCompleted 事件后将条目标记为已展示并移出当前/备份列表。此行为属于 StoryMode 的战役行为，不能将其全部提示认作 Sandbox 默认提示。另有 StoryMode 教学任务阶段与具体 Mission 教程逻辑，和通用 CampaignTutorial 提示是不同层。

`Concept` 是另一种按需查询资料：由 SandBox 的 `concept_strings.xml` 加载，数据含标题、说明文本、分组与链接 ID；原版概念百科页一次列出有效 Concept，按 Characters、Kingdoms、Clans、Parties、Armies、Troops、Items、Campaign Issues 八组过滤。用户确认 N 可以进入百科查看 NPC 记录；Concept 页面在百科中的具体点击路径未实机复核。

Chronicle Observer/Protocol 当前不读 CampaignTutorial 列表、教程完成状态或 Concept 页面数据；FreshCampaign 跳过开场并自动走角色创建，不代表 StoryMode 教程状态已适配。来源：当前安装 v1.4.8.119303 `TaleWorlds.CampaignSystem.dll`（`CampaignTutorial`、教程事件、`Concept`、`DefaultEncyclopediaConceptPage`）、`Modules/StoryMode/bin/Win64_Shipping_Client/StoryMode.dll`（`StoryModeTutorialBoxCampaignBehavior`）、`Modules/SandBox/ModuleData/concept_strings.xml`、本地 `AgentObserver.cs`/`AgentProtocol.cs`。未知项：实际 UI 弹出/消失、玩家确认或关闭方式、Sandbox 下启用教程的其他 Provider、教程状态在不同 StoryMode阶段的画面规则均未实机验证。
