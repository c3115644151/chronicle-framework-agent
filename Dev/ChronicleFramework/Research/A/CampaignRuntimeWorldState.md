# A 类：战役运行与世界状态

状态：机制拆解，未进行方案评审

本文只描述 Bannerlord 原版机制、状态、输入、输出和玩家可见入口，不评价设计质量，不提出优化方案。

## A01 战役生命周期

玩家入口：新建/继续/读档，经历加载并进入地图。1.4.8 `MBSubModuleBase.OnGameStart` 提供 `CampaignGameStarter`，战役注册 CampaignBehavior；`CampaignEvents` 暴露新档创建、早期加载、读档、读档完成、会话开始等回调。事件名不等于所有玩法界面已就绪；不同 Campaign 类型的顺序/差异未核实。

Chronicle 在 OnGameStart 加入行为，RegisterEvents 建立协议。FreshCampaign Harness 跳过开场并测选项到角色创建完成、MapState快照；这是自动夹具，不是Agent自主创建角色。来源：安装v1.4.8 CampaignSystem源码、SubModule、FreshCampaign测试；Story/Sandbox全生命周期矩阵与UI未核实。

## A02 战役时间与时间控制

玩家入口：地图时间条选停止/正常/快进；聚落等待菜单另行开始/结束等待；移动的时间副作用见 MAINLINE 机制契约。1.4.8 `MapTimeControlVM.ExecuteTimeControlChange` 调 `Campaign.SetTimeSpeed(0/1/2)`；不同停止/正常/快进模式控制 `TickMapTime` 是否推进 `CampaignTime.Now`。待命、等待、从属军团会使正常/快进不可停止；档位不保证等于具体模式。时间以小时/日等单位驱动日历、期限和周期。

Agent 覆盖：快照给出 `campaignDay`、`timeControlMode`；`pause`/`resume` 直接赋模式，`advance` 是 Harness 固定步进，不是玩家动作。源码：已安装 v1.4.8 `TaleWorlds.CampaignSystem.ViewModelCollection.dll`、`Campaign.cs`；Movement `061109/055319`、Rest `055458`、Protocol `100325`。自动状态证据已覆盖；物理输入绑定、画面反馈及锁定下可用性未知。

## A03 周期事件与调度粒度

没有独立玩家按钮；事件依 A02 战役时钟运行。1.4.8 `Campaign.cs` 建立日(1d)、小时(1h)、QuarterHourly(0.25h)周期；小时与四分之一小时事件由 `CampaignEventDispatcher` 分发。每日分发后按战役已过日数对 7 取模触发周事件。另有 Party/Town/Settlement/Hero/Clan 日事件。

影响包括队伍与 AI、食物工资、市场、聚落、英雄、任务、战争外交等；每种 CampaignBehavior 可订阅不同事件，加载组合决定实际消费者，行为总数尚未盘点。AgentObserver 是轮询快照：给出日期、玩家队资源/移动、可见聚落/队伍、进行中任务期限；不订阅 CampaignEvents，不输出通用事件增量/日志历史。证据：已安装 v1.4.8 `Campaign.cs`/`CampaignEvents.cs`、`AgentObserver.cs`；源码映射，未完成消费者或运行时全量清点。

## A04 CampaignEvents 事件总线

已安装 v1.4.8 `CampaignSystem.dll` 的 `CampaignEvents` 暴露 263 个公开 `IMbEvent` 通道，覆盖生命周期、时钟、战争/领地、英雄/队伍/聚落、王国、任务、对话与存档等。`CampaignBehaviorBase.RegisterEvents` 建立运行时订阅，`CampaignEventDispatcher` 分发；多 Behavior 可监听同一通道，非序列化订阅须在加载时重建。

Chronicle `SubModule.RegisterEvents` 当前订阅 DailyTick、Tick、GameLoaded、SaveOver；新角色创建回调仅 Harness 模式订阅。`AgentObserver` 不订阅事件总线，按需生成状态快照。263 是公开事件通道数，不是玩家动作数；实际加载 Behavior 的订阅者、顺序及事件到可见结果的映射未盘点。证据：v1.4.8 反编译源码与本地 SubModule/Observer；运行时通道覆盖未知。

## A05 存档与读档

玩家入口：快速/手动保存、自动存档与存档列表读档。1.4.8 `SaveHandler` 异步排队，SaveTick→OnBeforeSave→MBSaveLoad→OnSaveOver；自动档按墙钟间隔检查，要求时钟运行且处于无对话 MapState。Mod 字段经 `CampaignBehavior.SyncData` 读写；事件订阅加载后重建。

Agent `save` 调原生 SaveAs 并等 OnSaveOver；CLI `load` 重启进程选择存档。Protocol `100325` disposable 往返验证日期/tick及源 fixture 哈希不变；存档菜单与全对象恢复未核验。

## A06 难度与战役选项

入口：创建战役选项页、战役内 Campaign Options。1.4.8默认Provider提供预设及8项难度(部队伤害/招募/地图速度/说服/战斗AI/战斗死亡/家族死亡/潜行伪装，均三档)；另含perk自动分配、Ironman。其他 Provider 可扩展，列表随版本/Mod变化。

UI VM 写入选项并协调预设关联/禁用项；直接改 CampaignOptions 字段不等价。Agent快照不含配置；无自动/视觉验证。来源：已安装 v1.4.8 CampaignOptions.cs、DefaultCampaignOptionsProvider、CampaignOptionsVM。难度可配置化仅是潜在价值，非已选方案。

## A07 日志、通知与百科信息

用户确认N开百科，可查NPC经历/现况；本版界面未复核。1.4.8 `LogEntry.AddLogEntry` 写战役时间与递增ID；每项自有保留期，周清理过期项。`CampaignInformationManager` 将 `IChatNotification` 转为信息栏消息，地图通知独立保存、读档后重放。

AgentObserver 不读取日志/地图通知，无日志查询动作；Chronicle 诊断只记自身命令。证据：`LogEntryHistory`/`CampaignInformationManager` 及 AgentObserver/Protocol。

## A08 教程与概念提示

`CampaignTutorial` 含类型/优先级/标题/说明；`CampaignEvents` 提供教程收集/完成事件。`Concept` 由 XML 加载，含标题/说明/分组/百科链接。`StoryMode.TutorialPhaseCampaignBehavior` 处理教学流程。AgentObserver/Protocol 无教程状态或概念查询；FreshCampaign 跳过开场不代表教程适配。UI链未核实。
