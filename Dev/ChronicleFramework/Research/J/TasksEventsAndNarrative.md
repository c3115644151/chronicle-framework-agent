# J 类研究：任务、事件与叙事

适用本体：Bannerlord v1.4.8.119303。本文是 J 域唯一研究资料，按 SYSTEM_INVENTORY 的 J01-J12 次序记录。关系数据机制归 B/C/I；此处只研究任务、事件、对话、日志等消费者与玩家入口，不复制个人关系模型。

## J01 Issues：NPC委托与问题

### 真实入口、生成与接取

Issue是带有发起者、频率/冷却、解决条件和后果的Campaign委托。玩家此前确认地图中出现蓝色感叹号的委托标记；这里将其记录为玩家界面观察，不把它冒充本机UI实测。`IssueManager`会检查Hero的候选Issue类型/冷却、建立/分配Issue，并按每日/每小时tick使其失效、迁移、终结或转交AI领主处理；`IssueBase`保留Owner与DueTime，并让每个具体Issue提供 `CanPlayerTakeQuestConditions`、留存条件、超时后果和 `GenerateIssueQuest`。

玩家入口通常是有有效Issue的Notable/领主交互；地图标记/菜单提示用于显示可交谈人，交谈后由Issue特定条件决定哪些解决分支开放。1.4.8 `IssuesCampaignBehavior` 的共用Conversation链提供Quest、Alternative和Lord三种不同处理：Quest通过`IssueManager.StartIssueQuest`进入Issue Quest；Alternative需有可派遣同伴、通过Issue自己的`AlternativeSolutionCondition`，选择同伴并在条件要求多名士兵时打开PartyScreen配置满足人数/兵种的健康部队，确认后从MainParty roster移出并调用`StartIssueWithAlternativeSolution`，同伴进入busy状态，部队延迟返回；其后还会按Issue设置的天数、伤亡/失败风险结算。Lord Solution要求Issue自己的`LordSolutionCondition`、Issue owner当前聚落属于玩家Clan且玩家Influence足够；玩家选项先调用`StartIssueWithLordSolution`，随后仅在存在CounterOfferHero且issue owner仍在Settlement时开启第二段对话，否则通用代码自动走拒绝counteroffer结算。拒绝该NPC的counteroffer会扣`NeededInfluenceForLordSolution`并走成功/拒绝counter的Issue后果；接受则走Betrayal后果，不扣这笔Influence。以上三条的入口、前置、时间/资源与终态不同，不以“接委托”合并；Alternative和Lord能否按更细子类/确认节点继续分族，仍需查具体Issue override与提交/取消恢复。

用户已于2026-10-01确认：本地Settlement overlay人物名字旁的蓝色感叹号表示委托；地图贵族队伍领主姓名旁也有蓝色委托标记。点击本地Hero有“交谈”(QuickConversation)与“造访”(Conversation/Mission)两种模式，结束位置不同。1.4.8 `SettlementMenuOverlayVM`分别生成两种TroopAction；QuickConversation handler校验QuickTalkPermission并调用`CampaignMapConversation.OpenConversation`，Visit handler校验TalkPermission并通过`LocationEncounter.CreateAndOpenMissionController`进入Location Mission。

运行证据：`TestResults/20261001-095934/Temp/SettlementOverlayVisit-Result.json`验证Town overlay可见Gang Leader目标进入`MissionState`/`vlandia_town_e`并打开目标对话，CampaignDay与Stop模式不变、源存档hash不变、进程清理；Visit后仍留在场景，返回地图由Native Leave Area另行完成。`TestResults/20261001-101331/Temp/SettlementOverlayQuickTalk-Result.json`验证Village QuickConversation打开目标Hero对话并回到同一`village`菜单/MapState，Encounter仍活动、无Mission，Quest计数0→0、CampaignDay=91077.564不变、TimeControlMode Stop不变、源档hash和进程清理通过。此测试覆盖当轮自然可见Issue marker人物的一次快速交谈，不代表对话里接受了Quest或覆盖所有Conversation流。

W2-AU已将Native Party Nameplate marker类别扩展到当前`mapPartyTargets`候选；它只返回有限marker信息，不等于全局Issue发现，也不是地图Party的交谈/接Quest入口。

W2-E #29先以Sargot Gang Leader证明`CanPlayerTakeQuestConditions`不满足时原版不显示合法接取选项、Quest保持0；其后`TestResults/20260927-084700/Temp/SettlementOverlayQuest-QuestAccepted-Result.json`已在自然可见Village Notable上经原版`issue_offer_player_accept_quest`启动一条Issue Quest，Quest计数0→1，time/存档/进程断言通过。W2-AI再以`TestResults/20261002-035659`完整接受并交付一件VillageNeedsToolsIssue任务，证明的是一个特定任务闭环，不宣称Alternative/Lord Solution、其他任务子类或全局任务发现/刷新均已覆盖。
### Gold 奖励类 Issue 的源码样本（v1.4.8.119303）

本机 `TaleWorlds.CampaignSystem.dll` 的 Issue 子类中，金币奖励并非统一规则，必须按当前任务文本/Journal和具体 Issue 前置判断，不能把所有蓝色标记视为可盈利任务。

| 原版 Issue | Native 金币/前置/完成事实 | 对首轮 EYC 收入路线的意义 |
|---|---|---|
| Merchant Needs Help with Outlaws | `RewardGold = (int)(400 + 1500 × IssueDifficultyMultiplier)`；直接 Quest 路线要求与发起者关系不低于 -10、主队至少 5 名健康成员、双方不在战争状态，`requiredGold=0`；时限20天；要求在发起者附近摧毁或招募指定数量的合格匪徒队伍，范围由当前难度决定。成功回调给MainHero支付`RewardGold`并增加Clan Renown 1。Alternative是另行派遣同伴/部队的路线，副作用不同。 | 与无预付资金状态兼容，并可能同时增加声望；任务是否在当前世界出现、原版可接文本是否明确呈现奖励及当前遭遇是否属于该Quest目标，仍须观察实际标记/对话/Journal。地图遭遇坐镇指挥与父循环的匪徒遭遇处理代码存在可复用候选，端到端未验证。 |
| Gang Leader Needs Recruits | `RewardGold = 2000 + RequestedRecruitCount × 100`；`CanPlayerTakeQuestConditions` 的已反编译路径不要求技能或金币，关系低于 -10 会阻止接取。该Issue的目标描述需要向帮派领袖提供自愿加入者；俘虏招募及任务接受后的完整结算路径未在当前收入链验证。 | 奖励足以覆盖EYC金币目标，但它需要特定招募来源和交付链；不能仅由奖励公式推断为更容易或保证自然可用。 |
| Village Needs Tools | `RewardGold = 500 + requestedCount × (localPrice + item.Value) / 2`；关系低于 -10或与发起方处于战争会阻止接取；请求数量工具须送达，奖励可能按原版报价支付金币，也可能以指定物品交换。 | 有前期购买/取得工具成本，且不保证纯金币；当前金币为0时不能默认可行。 |

以上是安装版1.4.8.119303的反编译源码事实，不证明自然Campaign里任务出现率、Offer文本可读性、战斗目标总能被地图可见或AI已能跑通这些任务。入口必须先从Native `AvailableIssue` marker和当前Notable QuickConversation观察；只有当前对话实际开放Quest路径才接受，Alternative/Lord方案不可自动当作等价收入动作。该Quest的进度Journal调用把`AddDiscreteLog`标为`hideInformation:true`，但其运行时是否仍会出现在Agent按需读取的QuestDetails里尚未验证；本地还会发出“已猎杀x/y”QuickInformation。正式集成前需检查真实Native QuestDetails/屏幕，不能假定能读到隐藏进度。任务完成以原版Quest完成状态与MainHero Gold前后差值确认，不能只凭文本奖励金额。

## J02 Quests：任务生命周期与结果

`QuestBase`管理Quest giver、期限、奖励、状态、追踪对象、任务Logs和任务回调；`QuestManager`统合开始、Hourly/Daily/Weekly tick、超时、完成、取消和追踪对象。各Quest子类创建时 `SetDialogs`、注册事件，并定义 `OnStartQuest/OnCompleteWithSuccess/OnFailed/OnCanceled/OnTimedOut`等路径；Quest类型共享生命周期但并无相同条件、付款或失败后果。

玩家可通过Issue/Story/NPC交谈、外交/传闻事件等进入任务，也可在任务面板查看进行中任务并切换追踪、目标人物/聚落标记和进度。接受不等于完成：Quest可能有多个阶段、期限、目标事件、选择、目标消失/死亡、失败和取消；完成时可能产生钱物、关系/声望、身份或世界状态后果。`QuestManager.StartQuest`/直接结束方法和经过Quest giver的UI互动不是同一条玩家过程，必须保留Quest子类的前置与提示。

Campaign时钟驱动Quest期限与事件，玩家进入Battle/Mission/对话/等待等GameState时钟规则由父层决定；任务动作本身不应嵌入隐式快进。Chronicle schema21的`state.quests`列出当前观察到的活动Quest ID/标题/可见整日剩余时间；Agent可按需调用`questDetails(QuestId)`读取`QuestItemVM`同一Journal阶段，包括普通记录文字或TaskName/CurrentProgress/Range。查询只接受已观察ID、不读隐藏`QuestTaskBase`清单，不改变任务或日志已读状态。`TestResults/20260927-111022/Temp/SettlementOverlayQuest-QuestDetails-Result.json`在一次真实Issue Quest接受后与1.4.8原生`QuestItemVM`逐阶段对照通过；Sandbox样本期限可见，另以Harness序列化回归检查hidden→null/visible→daysRemaining；真实StoryMode隐藏期限Quest尚未加载验证。该读取能力不构成通用接受/选择/提交任务动作。来源：`QuestBase`、`QuestManager`、`QuestItemVM/QuestStageVM/JournalLog`；具体行动跨J03/F/G/H等域。未知：隐藏Quest目标、Story/Alternative解决方案日志规则、超时/保存加载同步边界以及任务总分母。

## J03 Quest Tasks：任务子步骤与触发器

`QuestTaskBase`是一种嵌在Quest中的步骤机制，可挂接 `DialogFlow`和Success/Failure/Cancel回调；Quest子类也可直接监听Campaign事件、战斗或Settlement变化而不使用该基类。实际目标可能要求到达地点、追踪/护送人物、交付物品/兵力、赢得战斗、指定对话或在期限内触发事件。跨场景任务能依序打开对话、GameMenu、Mission或更新Quest阶段，不能以文本目标名直接调用完成接口。

玩家从任务日志的提示/地图标记/对话选项进入对应步骤，但隐藏条件和可选路径由具体QuestTask/Quest实现控制。可见跟踪标记只说明一项目标被显示，不一定揭露唯一解法或所有失败条件。Harness需以稳定Quest/Task ID、任务前后状态与世界状态变化判断完成，不把日志字符串变化当作成功真值。

Chronicle目前可观察任务摘要及部分菜单/Conversation状态，未实现跨任务的通用Task解析/执行器；Issue任务、Story Quest、护送/救援/交付等必须单独映射玩家原版交互。证据：本体 `QuestTaskBase`、`QuestBase`事件接口、SandBox/StoryMode若干QuestTask；未知项：任务行为/阶段分母、各任务所依赖的NPC/地图/战斗实际入口、目标失败后的恢复可达性、自动任务检查与玩家完成的同步方式。

## J04 Journal：日志、任务记录与信息回看

`JournalLog`以时间戳、文本、类型、可选当前进度/目标范围表示记录；`QuestBase.AddLog/AddDiscreteLog/AddTwoWayContinuousLog`将任务记录与Quest阶段连接，更新进度后可标记完成。它是一个叙事/状态回看面，并不必然是世界状态真值：文本可以延迟、隐藏信息、总结多次变化，且与 `LogEntryHistory`、通知队列、Quest状态是不同存储对象。

玩家可在任务日志面板查看具体Quest记录/当前阶段，也可从N百科的Hero页面查看以Hero为主体的事件历史；这两个“记录”视角不应混为一页。用户已确认百科N能查NPC日志；本体 `JournalLog`/QuestVM是Quest日志与任务进度系统。实际快捷键和全部可见字段还需对当前build做UI核验。

Chronicle返回有限活动Quest摘要并可按需查看一个已观察活动Quest的Journal阶段；不提供已完成Quest历史页、Hero `LogEntryHistory`检索或历史页筛选/跳转动作，也不把任务日志当成全局世界真值。来源：`JournalLog`、`QuestBase`、`LogEntryHistory`、`QuestsVM`与百科VM。未知：任务/人物日志的持久保留/筛选/删除边界、隐藏信息何时向玩家揭示、日志时间与实际事件提交的延迟分布，以及Journal的最终玩家行为分母。

## J05 Incidents：随机/上下文事件

当前本体的 `Incident`不是所有故事事件的同义词：对象包含Trigger、Type、Cooldown、全局条件以及若干带Condition/Effects/Consequence的选项。`IncidentsCampaignBehaviour`监听主队进出Settlement、Conversation/Mission/Menu等上下文，按IncidentModel全局概率与触发冷却挑选适用Incident，并将其交给MapState呈现；玩家从事件面板选择一个条件有效的选项后，每项Effect及option Consequence分别生效并发Resolved事件。

已确认的地图触发源包括进入/离开城镇、城堡、村庄以及围 siege/等待等上下文；全局最小/最大cooldown、事件触发概率随战役模型调整。选择一个事件选项可能消耗资源、改变队伍/聚落/关系或触发任务；UI直接逐个显示效果不代表后果Action只调用一次。用户此前已经用MAINLINE记录过incidentSelect：原生VM确认/关闭和直接API跳过清理不是等价路径。

Chronicle仅在指定Harness研究接口中能读取/选择有限Incident，产品协议未提供通用随机Incident观察/交互；当前MAINLINE标注选择事件的时间锁/恢复证据。证据：`Incident`、`IncidentsCampaignBehaviour.TryInvokeIncident/InvokeIncident/OnGameMenuOptionSelected`、`IncidentModel/DefaultIncidentModel`及Map incident UI；未知所有注册Incident列表、各概率真实值/随机分布、被禁用/过期事件筛选和不同触发环境下玩家界面、事件结果结算的完整覆盖。

## J06 Rumors：传闻和流言信息

玩家入口是Inventory/市场物品的悬停详情。用户在2026-09-25确认：市场栏与玩家物品栏的商品条目可显示异地便宜买入/有利卖出地点，举例有谷物、贵重品、木材和葡萄酒；武器不会显示。马匹方面，本机源码独立确认 tooltip 入口只处理 `InventoryItemType.Goods`，不会处理`Horse`；W2-AE运行查询也返回Horse `applicable=false`且无提示。生成器包含Horse记录不代表悬停界面展示Horse传闻。`SPInventoryVM`把当前物品交给`ItemMenuVM.SetItem`，两侧商品都进入同一个`SetMerchandiseComponentTooltip`，不按玩家栏/市场栏另建观察族。

`TradeRumor`保存Settlement、具体`ItemObject`、BuyPrice、SellPrice和RumorEndTime。字段虽然名为`ItemCategory`，实际类型是`ItemObject`，消费者按具体物品对象相等匹配，不能写成按物品类别匹配。`TradeRumorsCampaignBehavior.TradeRumors`过滤已过期记录；物品详情排除当前聚落，并把记录价格与当前`MarketData.GetPrice`比较：BuyPrice低于当前卖价的0.9倍或SellPrice高于当前买价的1.1倍才显示相应文字。两条件同时成立时该行优先使用便宜买入文字；条目透明度随剩余有效天数变化。这些价格是已收集的记录，不保证玩家抵达时仍可按原价成交；界面也未直接显示全部内部时间字段。

已确认的获取/寿命链包括：主队进入城镇后记录贸易商品价格（同城采集间隔至少1天，记录有效10天）；DailyTick请求一条随机城镇/物品传闻（有效10至19天），同时清理过期记录；`OnTradeRumorIsTakenEvent`接收其他来源。`TravelingRumors`专长允许玩家家族商队进城采集，`Tollgates`专长让自有工坊所在地参与每日采集。该tooltip显示函数及基础进城/每日来源没有统一Trade技能等级检查；技能专长扩充情报来源，与E09记录的利润/行情颜色提示分别核对。各来源最终仍受`AddTradeRumors`接纳/去重逻辑约束，不能把一次采集请求视为所有记录均已更新。

源码依据为本机v1.4.8.119303的`TradeRumor`、`TradeRumorsCampaignBehavior`、`ItemMenuVM.SetItem/SetMerchandiseComponentTooltip/CalculateTradeRumorOldnessFactor`与`SPInventoryVM`。W2-AE实现按需CLI观察`tradeRumors(ItemViewModelId, InventorySide)`，限定当前Town Trade VM最近返回的候选；它不枚举整个传闻库、不调用`ItemMenuVM.SetItem`，以免把观察命令当成玩家悬停触发`InventoryItemInspectedEvent`。`TestResults/20260930-054055/Temp/TradeTransactionResult.json`使用Harness-only的一次性Campaign传闻样本分别核对市场侧与玩家侧候选：结构化方向/报价/地点/新鲜度和Native本地化提示文本逐条及顺序与`ItemMenuVM.TargetItemProperties`一致；正常买/卖提示存在，已过期与当前城镇传闻不返回，Horse候选无提示，无效ItemVM候选被拒绝。商品查询不改变Gold、队伍物品、聚落、时钟档或CampaignDay；源存档哈希相同且进程退出。测试样本注入只改disposable Campaign的内存状态，不进入Agent决策输入。

查看提示本身不写库存/金币或显式切换Campaign时间，价格记录采集/过期依赖原版Campaign事件；当前Trade Inventory宿主状态的时间效果以具体上下文为准。剩余未知是外部传闻事件的全部发起者、采集去重/旧记录更新边缘、第三方Mod对ViewModel的替换及实际鼠标悬停画面/焦点表现。非贸易闲谈与世界消息仍归B/J08，不能从本对象推导出统一的全世界传闻网络。

## J07 Notifications：地图提示、事件通知和操作入口

需要区分Campaign Map Notification、QuickInformation/短提示、Scene notification、Quest JournalLog和Incidents MapState：它们用途/保留期/交互不同。`CampaignInformationManager`收集通知数据，`MapNotificationVM`按通知类型注册对应ViewModel，向玩家展示、定位或允许前往相关操作；Sandbox默认通知Behavior订阅任务开始/完成、Relation变化、征兵/俘虏/聚落/军团/婚姻/战斗等CampaignEvent。`SceneNotificationData`不只用于Battle Mission场景：Campaign对话也会通过`ShowSceneNotification`调用它，Hero Execution scene popup就是可点击Proceed的决策确认；执行结果本身仍在其上下文通知回调发生，不能把“弹窗打开”认作已处置。

通知常是玩家获知新任务/结果/选择权的引导，但通知本身并不必然产生游戏后果；例如点“跳转”会定位对象，不等于自动完成任务。玩家是否能关掉、过期、再次点开或标记已读要由该通知VM决定。

`OBS-J07-02` QuickInformation是另一条短暂显示链：`MBInformationManager.AddQuickInformation`同步触发`FiringQuickInformation`，`GauntletGameNotification.RegisterEvents`把它送给`GameNotificationVM.AddGameNotification`。该VM把当前项放在`CurrentNotification`，其他尚未轮到的项放入私有`_items`；重复文字会合并/忽略，所以队列不是玩家已看见的消息历史。当前显示秒数由固定0.6秒、Native `ExtraTimeInMs`、超过4词的延时和队列数量共同计算；还必须区分`IsDialog`语音项，它也复用同一个VM但不是QuickInfo。`GauntletGameNotification.OnTick`根据SceneNotification/加载窗口等判断是否Suspended，并同步写`GameNotificationVM.IsPaused`。完整画面链从`InformationManager.DisplayMessage`/普通信息栏另行分流，不能和QuickInformation合并。

W2-AG实现按需`quickInformation`观察，Campaign Map下反射读取本机Native `TaleWorlds.MountAndBlade.GauntletUI.GauntletGameNotification.Current._dataSource`。只有Native layer存在、`GotNotification=true`、UI未Paused且current项不是Dialog时才返回当前气泡原文、说话者、ExtraTime、VM duration/fade值；UI unavailable时明确回`available=false`。它不订阅 `FiringQuickInformation`，也不缓存新历史、不枚举私有排队`_items`，因而AI若没有在短时窗口采样就会错过，与“这条消息当前是否仍显示”语义一致。VM公开的`CurrentNotificationDurationInSeconds`是原版显示周期值，不宣称是动画中剩余秒数。

`TestResults/20260930-064259/Temp/QuickInformationResult.json`通过Native `MBInformationManager.ClearQuickInformations/AddQuickInformation`清空disposable UI并发两条原版消息：当前项和排队项；Chronicle连续两次只返回当前项，完整原文与说话者/ExtraTime/VM时长一致，排队文本未泄漏；当前VM ID与文本未变，Campaign/Gold/Roster/时间/存档均不变，进程退出。该测试是一次性Client UI事件链验证，不是桌面截图或鼠标操作；Suspended Dialog/SceneNotification分支、Native UI层缺失情形和不同Mods替换还未实测。

W2-AH SceneNotification观察尚未实现。源码显示`MBInformationManager.ShowSceneNotification`先触发`OnShowSceneNotification`；Native `GauntletSceneNotification`加入内部队列、延迟2帧并按`SceneNotificationData.RelevantContext`确认当前环境后才出队。`CreateSceneNotification`创建`SceneNotificationVM`的ActiveData，加载独立小场景并进入Active/Shown/Ready生命周期；它不是Map Notice，也不是GameNotificationVM的快速提示。VM直接公开Native标题、Affirmative/Negative描述、按钮标题/文本/可见性、Continue提示和SceneID。affirmative、negative、close有各自回调；`HeroExecutionSceneNotificationData`还会把处决后果延迟至CloseAction，故“已显示/选择Affirmative”均不等于世界效果已提交。未来观察只读VM字段，不能调用任何回调；时钟是否暂停/何时恢复还需当前Campaign上下文运行确认。

跨域去重：`OBS-J07-03`覆盖Mission/Scene局部消息及Campaign中以`SceneNotificationData`呈现的确认面；特定弹窗之后果归属对应领域动作（例如俘虏处决为`ACT-F12-12`），不新增通用Scene弹窗观察/确认ACT。确认前可见目标/动作与最终回执必须分开记录；全量视觉确认、宿主时钟与Close/Proceed键鼠路径仍待运行核实。

W2-AH `sceneNotification`仅读当前`GauntletSceneNotification.Current`的Active VM；UI unavailable/当前无Active/Shown项时无内容。它返回VM上的标题、说明、按钮文字/可见状态、Ready/Shown和继续键提示，不公开SceneID/回调委托，也不会执行按钮。由于Scene UI是独立的全局Layer，测试使用Native `MBInformationManager.ShowSceneNotification`入口和内置`HeroExecutionSceneNotificationData.CreateForInformingPlayer`显示一个没有affirmative后果的真实Scene notification；等待Active/Shown/Ready后截图。测试收据`TestResults/20260930-071127/Temp/SceneNotificationResult.json`确认：标题“法尔塞沃处决卢孔”、Proceed按钮显示、取消按钮隐藏，VM字段与原生Data一致；Native独立场景关键帧`TestResults/20260930-071127/Temp/scene-notification-active.bmp`里实际显示了该modal和双角色。它是信息性演示通知：测试未选择Continue/Close，Native后果回调没有由Chronicle调用；Campaign/Gold/Roster/Quest/时钟/存档状态不变，游戏退出。该运行未证明玩家点击回调、真实处决或所有SceneNotification宿主/子类的时钟/场景效果。

用户在连续录像中确认：原版“通知”Yes/No Inquiry点“好”后，Campaign Map可接着出现另一张棕色场景卡片，底部写“点击继续”；卡片显示时大地图时间与部队移动都不继续。这与前一条Yes/No Inquiry是两层原版交互，不应在回应Inquiry后默认地图已恢复。Natural Tutorial-skip 的地图 Inquiry快照`TestResults/20261024-020036/Temp/FreshStoryMode.native-menu-leave.json`显示affirmative callback为`FirstPhaseCampaignBehavior.<OnSettlementLeft>b__11_0`，被识别为`storyModeStartupKind=tutorial-skip-notification`；随后`FindingFirstBannerPieceSceneNotificationItem`绑定`OnPieceFoundAction`，Close会调用`SelectClanName()`并打开家族名`TextInquiry`，确认后`OnChangeClanNameDone`调用`Clan.ChangeClanName`并进入`BannerEditorState`。用户明确要求AI自主完成家族名和旗帜设置，而非额外让玩家代点。其它SceneNotification也可能在Close阶段提交后果，不能泛化成一键关闭。

`TestResults/20261024-010234/Temp/SceneNotificationResult.json`在一次性现存StoryMode Campaign中将原版当前`FirstPhaseCampaignBehavior.OnPieceFoundAction`委托绑定到Native通知fixture，真实引擎帧与状态通过：设为`UnstoppablePlay`后弹窗Active/Shown/Ready，2秒重复读CampaignDay维持91080.225；Native `SceneNotificationVM.ExecuteClose`后实际回调打开Clan name TextInquiry，`pauseGameActiveState=false`且地图日自然推进到91080.236。Test使用当前默认名称“cy”，走Native `TextQueryPopUpVM.ExecuteAffirmativeAction`并通过`FactionHelper.IsClanNameApplicable`校验，进入BannerEditorState；捕获屏幕/Banner代码后走`BannerEditorVM.ExecuteDone`，自然回Map并打开原版“潜行教程/继续”Inquiry。Gold/Roster/Quest未改，`save002.sav`哈希不变，游戏进程退出。`TestResults/20261024-012100` AgentHostPackage合同测试的Fake provider/native闭环按顺序涵盖Notification→名称输入→Banner Done→Stealth Tutorial Inquiry；它不是FreeLLMAPI真实模型行动。新战役菜单验收`TestResults/20261024-020036`确认教程skip后的首个YesNo callback是`FirstPhaseCampaignBehavior.<OnSettlementLeft>b__11_0`并能识别startupKind。模型在自然新Campaign实际完成该开局链仍待Live Model验证；其它SceneNotification类型不泛化支持。

Chronicle新增按需`mapNotifications`，仅在Campaign Map状态读取`Campaign.CampaignInformationManager`的Notice队列。1.4.8没有公开枚举接口，当前适配通过版本内反射读取`_mapNotices`，先检查`InformationData.IsValid()`，再用Native `MapNotificationVM.AddMapNotification`经过其注册表生成对应`MapNotificationItemBaseVM`；向Agent只返回原版ItemVM提供的类型、标题、描述、NotificationIdentifier、ForceInspection，不枚举底层对象/额外目标字段。临时VM只为映射Notice数据，在finally中逐个`OnFinalize`并自身`OnFinalize`，不触发点击、相机跳转、焦点、移除或Proceed回调。因为这不是活动UI中的具体焦点控件，不返回`IsFocused`。

`TestResults/20260930-061737/Temp/MapNotificationsResult.json`在disposable Campaign中经Native `CampaignInformationManager.NewMapNoticeAdded`加入一个Harness-only已注册`TraitChangedMapNotification`、一个未注册自定义InformationData和一个`IsValid=false`自定义InformationData；查询只返回注册类型，具体ItemVM为`TraitChangedNotificationItemVM`，本地化标题“获得特质”、描述文本、NotificationIdentifier保真。重复读取保持顺序/内容稳定， invalid/unregistered都不泄漏；Gold/Roster/Quest/位置/时钟/日期无变化，源fixture哈希相同且进程退出。此运行只验证一个受注册类型；未验证真实自然通知产生频率、每个Notice子类的专属字段、实际屏幕焦点/鼠标跳转/移除按钮、通知过期后现存UI的清理，也不覆盖QuickInfo、SceneNotification、Quest Journal与百科日志。

来源：`CampaignInformationManager._mapNotices/OnGameLoaded/NewMapNoticeAdded/MapNoticeRemoved`、`MapNotificationVM.PopulateTypeDictionary/AddMapNotification/GetNotificationFromData`、`MapNotificationItemBaseVM`、`DefaultNotificationsCampaignBehavior`及各通知类。未知各notice类型对同一物件的目标摘要如何表达、模态覆盖时UI可见范围、优先级/已读/失效边缘和第三方注册通知兼容。

## J08 Conversations：NPC对话流程

对话不是一组静态按钮列表。`ConversationManager`保留当前ConversationFlow/参与者/标签/阶段和可用Sentence；每句包含Condition、文本、InputToken/OutputToken、Consequences等内容，选项在当前上下文动态增删。`CampaignMapConversation`、Mission/Scene Conversation、聚落Notable交谈、地图队伍遭遇/领主会面、俘虏和Issue等入口会加载不同Flow与身份数据。

玩家实际通过进入相应谈话对象/场景开始会面、选择当前开放句、继续/退出；场景交谈可能先经过3D移动、HUD互动、地图遭遇菜单或GauntletMission。Sentence consequence可调用多个Campaign actions或创建/更新Quest/Barter/Persuasion/Party状态。直接调用某个后果会绕过Sentence条件、当前Conversation状态、正常动画/离场和提示。

跨域分母边界：`dialogueSelect`只是代理/输入层对当前valid Sentence执行点击的通用工具操作，不等于一项单独的Bannerlord行为。会创建/完成Quest、改变关系/阵营、开启或提交Barter/Persuasion、释放俘虏、开启Mission等Sentence consequence由各自领域的实际ACT承载，不能再加一个“点击对话选项”ACT重复计数；没有世界状态提交的询问/过场/显示信息，其信息与新Option列表并入`OBS-J08-01`。新发现的Sentence分支若产生此前未映射的实际世界效果，应补该领域ACT，而不是扩成一个吞并所有Conversation后果的J08族。

原有关系反馈的边界见 I01/I04/I09与本J文关系段：文本/选项由Identity、Faction、Trait、关系、任务和世界状态筛选，关系不一定作为独立历史来源呈现。Chronicle通用Conversation适配目前只覆盖Map Lord会面首段：pursuit自然接触→Observe开放选项→invalid option/Continue guard→选择当前intro response→re-observe新Sentence/选项。运行收据`TestResults/20260926-214832/Temp/AgentConversationResult.json`显示问候后出现`hero_give_issue`等后续选项，本测试未选择Quest/Barter/关系分支；该垂直切片证明Protocol操作已进入ConversationManager，不代表全量对话目录或自动跑3D接近。来源：Campaign `ConversationManager/ConversationSentence/CampaignMapConversation`、Sandbox DialogFlow/ConversationBehaviors、ViewModelCollection `ConversationVM`、当前Chronicle Protocol。未知全体ConversationFlow/条件去重分母、对话状态被任务/战斗打断后的恢复、不同语言和Mods扩展的动态选项。

## J09 Persuasion Dialogues：说服过程

Persuasion是J08对话内的一种状态化子流程。`PersuasionTask`包含任务预备的`Options`及对话文本字段；它没有独立的“剩余尝试次数”字段。`DefaultPersuasionModel`以目标Trait、关系、ArgumentStrength、玩家Skill/Perk和difficulty multiplier等参数计算success/critical/failure概率和下一阶段/封锁选项效果。实际尝试以当前Conversation开放的argument为入口，结果再由该Task/Conversation consequences决定增加进度、继续、失败、关系变化或Quest后果。

求偶、说服领主、Quest谈判等会分别初始化不同task，不能将一项Persuasion成功率输出到所有NPC。UI必须显示当前合法选项和对应风险；直接反复调用概率模型不会生成合法对话尝试或完整失败后果。玩家确认：成功、失败、大成功、大失败概率写在每个当前对话选项中；进度用圆圈表现，某任务看到三个圆圈就表示要积累三次进度，实际目标随任务变化。源码将`MissionConversationVM.PersuasionProgress`的圆圈数量绑定`GetPersuasionGoalValue()`，每个当前`ConversationItemVM.PersuasionItem`绑定四类机率、推进/阻断标记；Native `SPConversation.xml`和`ConversationItem.xml`将这些数据绑定到当前会话画面。Task没有剩余attempt计数，不应输出。Chronicle按需`persuasionDetails`只从当前MapConversation Native ViewModel/AnswerList读取并按当前option索引核对；Persuasion `dialogueSelect`只有匹配当前可见且可用AnswerList时才提交，绝不从Task.Options补隐藏候选。

两组运行证据共同界定这一能力。`TestResults/20261006-204936`先验证active VM在AnswerList为空时只返回0/2和两个空圈，不泄漏CurOptions候选，隐藏候选被拒且无对话/资源/时间/存档副作用。正向链在`TestResults/20261007-033330`验证：Harness等待MapConversationVM自身AnswerList加载完成，再仅在当前已渲染的Native answer row上临时装入真实Native `PersuasionTask`、Argument和`PersuasionOptionVM`；这是可重复VM/模型集成夹具，不代表游戏内自然Quest/Courtship host已经开启Persuasion。Observer从该行读取成功60%、失败26%、大成功0%、大失败13%及0/2进度。`dialogueSelect`提交同一可见row，Native consequence随机判为成功，屏幕显示“成功！”，进度成为1/2、圆圈状态为[亮,灭]，对话进入NPC原生后续句。测试未宣称该临时argument等于任何具体原版Quest/Romance论证，也未覆盖自然触发入口、各宿主后果、概率分布或会话时钟。数值数据与社交入口见I04/I10。来源：`Persuasion/PersuasionTask/PersuasionAttempt`、`DefaultPersuasionModel`、`PersuasionVM`、`MissionConversationVM`、`ConversationItemVM`、Native GUI Prefabs及Romance/Issue相关behaviors；未知不同Task建立源/概率公式全部权重、重复点选/关闭对话后的持久状态、测试seed与真实随机分布。

## J10 Tournament：城镇竞技比赛

`TournamentCampaignBehavior`按城镇DailyTick创建/结束赛事；城镇叛乱、围 siege、参赛者与场地状态会使它不可用或结束。玩家从到达Town后的Arena/Tournament菜单查看参与/观战/排行榜选项；选择参与会进入特定Tournament Mission（部分项目有单独规则/控制器），分轮淘汰后由TournamentManager更新参赛者、胜场和奖品。点“参加”不是直接获得胜利或固定Renown，玩家需在Mission中通过实际比赛。

奖品、金钱下注/同伴比赛或声望影响分别由TournamentModel/结果处理、参加者与胜负决定；TournamentSimulation对NPC可用抽象结果，但玩家加入比赛会切换真实Mission，Campaign时间在Mission内停止。Chronicle当前无竞技场Tournament Mission控制、赛事状态/对手/排名观察或胜利动作；tier评测文档只引用锦标赛奖励公式，不代表可用路线。证据：`TournamentCampaignBehavior/TournamentManager/TournamentGame`、`TournamentModel`、Sandbox `TournamentMissionStarter`与Mission controllers、城镇相关GameMenus；未知赛事生成概率、每种比赛的玩家完整菜单路径、投注/奖品的全套结算和自然运行统计。

## J11 Board Games：酒馆棋盘游戏

`BoardGameCampaignBehavior`通过酒馆Host或可玩Lord对话允许设置对手/AI难度/先手和赌注（源码有0至500 Dinar档位条件）；再在Conversation结束后启动 `MissionBoardGameLogic`进行对应棋盘Mission。支持的游戏是具体BoardGame类（例如Tablut、Seega等），每种规则/状态机与AI实现不同；玩家按格子交互走子、吃子/判胜，不是大地图Party行动。

胜负结束后流程读取对手/投注并更新Hero/Settlement每周游戏次数/冠军胜场等数据；赌注资金风险与Relation/活动剧情是不同结果。纪元/AI难度/哪方先手可能影响对局过程。Board Game Mission不是Campaign时间流逝入口，战役地图tick在场景内是否完全停止按Mission宿主验证。

Chronicle没有打开酒馆、对话设置棋局、棋盘格子观察/落子或胜负结果接口。来源：Sandbox `BoardGameCampaignBehavior`、`MissionBoardGameLogic`、BoardGame规则和AI类；Campaign `BoardGameState`/`BoardGameHelper`。未知各城镇可玩对象生成与UI入场路径、每个游戏终局/和局判定、赌注确认/取消/作弊的回执差异、Mission暂停及存档恢复行为。

## J12 Story Mode：教程与主线任务

StoryMode是独立Campaign mode内容，不是所有Sandbox战役必有的任务。StoryMode通过 `StoryModeManager/MainStoryLine`和StoryMode campaign behaviors 注册Tutorial、First/Second/Third phase等阶段任务；教程涉及购买粮食、招募/旅行/村庄协助/找藏身处/营救家人等Quest，之后进入Banner Piece investigation、选择Imperial/anti-Imperial方向、盟友/军团与阴谋任务链。阶段转换有明确前置和角色/时间/战争后果，不能仅按任务文本认定所有剧情章节永远按同一路线线性开放。

玩家入口来自新Campaign Story Mode选择、Tutorial/任务提示和对话；跳过教程会走 `CompleteTutorialPhase(isSkipped)`等专门路径，不等于跳过整条主线。故事子Quest通常复用QuestBase/QuestTask/CampaignMapConversation/Battle/Mission机制，但特定剧情角色、动画、模型和状态检查由StoryMode程序集控制。Chronicle当前的通用Quest摘要不能覆盖这些固定场景路线，也不能对Sandbox使用StoryMode专属Quest下结论。

具体Mission入口例：Tutorial Quest `VillagersInNeed` 的救Headman步骤在StoryMode `SneakIntoTheVilla` Mission中，由MainAgent使用`IsMissionExit`的`PassageUsePoint`调用`OnHeadmanRescued`设置Quest内部救援标记；该3D动作目录为`ACT-G03-24`。本J域记录Quest阶段与后果关联，Mission内触发方式留G03，不再新增泛化“完成任务”ACT。回到Campaign后的Quest推进/成功结算时点仍需按该Quest完整生命周期核验。

`VillagersInNeed`在`StoryMode.dll`中是TutorialPhase的StoryMode支线/救Headman任务。其`OnSettlementEntered`只在MainParty首次进入固定的`village_ES3_2`且`_talkedToVillagers`尚为false时，调用`CampaignMission.OpenConversationMission`与`tutorial_npc_questgiver_villager`对话；所以在自然新档AI用原版MapScreen移动到该村庄时，原版可自动切入一段3D ConversationMission，这不表示“地图点村庄普遍自动开始对话”。它沿当前ConversationManager逐步呈现多段NPC文本与玩家选项。用户确认对话未结束时无法离开，完成后选择“先处理别的事情”会回到沙盒村庄菜单；本轮首门禁不要求跟随NPC进入SneakIntoTheVilla救Headman。1.4.8源码中 `Lead on.` 的玩家选项设置`_startVillaMission=true`，随后`GameMenuOpened`触发`StartVillaMission()`打开`StoryModeMissions.OpenSneakIntoTheVillaMission`；“I have to take care of something else, first.”只调用Native CloseDialog，不设置`_startVillaMission`。该任务/对话仍可留在原版Journal中，不等于EYC主要目标已完成。`dialogueContinue`与`dialogueSelect`应每步读取当前原版ConversationManager的可见句子/答案再调用其Continue/DoOption，不写任务字段、不跳过NPC脚本。证据：本机1.4.8 ILSpy `VillagersInNeed.OnSettlementEntered/OpenConversationWithVillager/GameMenuOpened/StartVillaMission`和`MissionConversationVM.ExecuteContinue`；真实Run `TestResults/20261025-232055`的关键帧显示帝国农民对话，但Host在MissionState处旧逻辑停止，拒绝/回村庄菜单的完整自然闭环尚未自动验证。Campaign Mission精确时钟表现未知。

`VillagersInNeed.OnSettlementEntered`在本机1.4.8 StoryMode `StoryMode.dll`中有一个关键的自启动边界：当MainParty进入固定村庄`village_ES3_2`且`_talkedToVillagers`仍为false时，它调用`OpenConversationWithVillager()`，经原版`CampaignMission.OpenConversationMission`与`tutorial_npc_questgiver_villager`开始对话。此分支不是地图访问村庄的一般规则；普通地图进入定居点仍应先出现沙盒村庄菜单，只有该StoryMode任务前置满足时才自动切入ConversationMission。玩家确认此对话有多段NPC文本，需按原版继续推进，待答案出现并完成，期间无法退出。该Quest目标是解救headman并进入`SneakIntoTheVilla`任务；首轮EYC不要求执行该任务。原版最终选项“Lead on.”设置`_startVillaMission=true`并在下一次`village`菜单打开时调用`StartVillaMission()`；“I have to take care of something else, first.”只关闭对话，用户确认选择推迟后回到对应沙盒村庄菜单。Quest可能仍在Journal，不应伪称完成/取消。Native UI来源本机1.4.8 `MissionConversationVM.ExecuteContinue`→`ConversationManager.ContinueConversation`及`ConversationItemVM`当前答案handler→`ConversationManager.DoOption`；Chronicle的`dialogueContinue`/`dialogueSelect`只在同一ConversationManager状态可用时调用这两个Native方法，不模拟屏幕键鼠。StoryMode XML将该村民作为`NPCCharacter` `tutorial_npc_questgiver_villager`定义，且ConversationManager保留`OneToOneConversationCharacter`与派生`OneToOneConversationHero`两个不同层级。Observer state schema 27的`conversation.characterId/characterName`来自当前OneToOneConversationCharacter，只描述本轮显示的对话人物；旧`heroId`仍用于Hero关联，不能拿来代替通用CharacterId。Run `TestResults/20261026-003516`显示旧Host按heroId拒识该MissionState；真实schema27/CharacterId识别尚待复测。自然Run `TestResults/20261025-232055`证实移动抵达后由`SettlementEntered`触发此分支，但此前PartySize Host把MissionState误当普通无地图态并停止；画面显示第一段帝国农民对话，未覆盖后续答案/推迟/返回村庄RecruitmentVM。Campaign移动从91077.375推进到91077.49；对话Mission期间的精确Campaign时钟行为仍未单独核验。

### 自然新档进入 Establish Your Clan 的 Tutorial 关键依赖

按本机1.4.8.119303 `StoryMode.dll` 的 `TutorialPhaseCampaignBehavior`、`TutorialPhase`、教程 Quest 和 `FindHideoutTutorialQuest`调用链，可确认以下源码路径：

1. 新战役第99号 `OnNewGameCreatedPartialFollowUp` 执行 `InitializeTutorial`：设置/加入长兄、创建指定村庄头人并准备教程粮食；Tutorial 状态是保存中的StoryMode阶段数据，不应仅凭地名或Quest标题推断。`TrainingFieldCampaignBehavior.OnCharacterCreationIsOver` 在`SkipTutorialMission==false`时会把MainParty放到`tutorial_training_field`并立即打开`training_field` Location Mission。该Mission内兄长对话提供继续教程或“Skip tutorial”选择；选择后还会出现“这会结束教程并开始完整单人战役”的确认，确认只设置原版`_completeTutorial`，结束该Mission时调用`CompleteTutorialPhase(true)`。所以“玩家创建角色，Agent在首个稳定Campaign MapState接管”本身无法让Agent选择这条跳过分支——选择发生在首个MapState之前；若AI负责完整未跳过Tutorial，它的接管边界也必须延伸到这个初始训练场Mission。
1. 新战役第99号 `OnNewGameCreatedPartialFollowUp` 执行 `InitializeTutorial`：设置/加入长兄、创建指定村庄头人并准备教程粮食；Tutorial 状态是保存中的StoryMode阶段数据，不应仅凭地名或Quest标题推断。`TrainingFieldCampaignBehavior.OnCharacterCreationIsOver` 在`SkipTutorialMission==false`时会把MainParty放到`tutorial_training_field`并立即打开`training_field` Location Mission。该Mission内兄长对话提供继续教程或“Skip tutorial”选择；用户确认“跳过教程”就是直接离开教程的对话选项，没有另一条独立“离开/再见”选项。选择后还会出现“这会结束教程并开始完整单人战役”的确认，确认只设置原版`_completeTutorial`；兄长后续原版对话需要按“点击继续”推进，结束该Mission时调用`CompleteTutorialPhase(true)`。真实新档运行`TestResults/20261022-194410`选择原版`player_answer_skip_tutorial`、`end_tutorial_yes`并推进两次原生对话，之后自然到达EYC活动的首个MapState，没有使用Tab兜底；`195530`再次通过并保存了明确出口路径字段。用户另确认：若仍留在3D场景，可长按Tab（原版通用Leave Area操作，约2秒）离开；这与随后首个MapState上的训练场地点菜单`training_field_leave`是两个不同状态/入口。另一个Harness试验`TestResults/20261022-193820`在对话仍活跃时抢先模拟Tab离开，游戏抛出`MissionGauntletConversationView.OnConversationEndOneShot`空引用并崩溃；故现在必须等原版兄长对话完全结束，才允许测试使用Leave Area兜底。该特定训练场兜底尚未单独通过；不把Town Mission Leave结果外推到此分支。教程跳过发生在首个MapState之前，因此AI自治若包括未跳过Tutorial，接管边界必须延伸到这个初始训练场Mission。
2. MainParty离开`tutorial_training_field`且教程阶段仍为`None`时，原版启动`TravelToVillageTutorialQuest`。完成后接`TalkToTheHeadmanTutorialQuest`；Headman对话启动`RecruitTroopsTutorialQuest`和`PurchaseGrainTutorialQuest`两条并行任务。两者的原版招募/市场入口已在H04/E02及其MAINLINE契约中分别记录。
3. Headman任务完成后启动`LocateAndRescueTravellerTutorialQuest`。该Quest原生要求击败三个指定劫匪Party，需主队人数至少4；本Quest自定义遭遇菜单把`encounter_raiders_quest_send_troops`置为disabled，而`Attack!`走`MenuHelper.EncounterAttackConsequence`。本机1.4.8 CampaignSystem该Handler对普通非聚落MapEvent调用`CampaignMission.OpenBattleMission`，随后`PlayerEncounter.StartAttackMission`并开始等待；从这个自定义菜单不是直接进入Campaign `BattleSimulation`。Mission内Native指挥/暂停/退出能否安全完成该故事目标仍待Host/运行验证，不能由普通Bandit BattleSimulation样本类推。
4. 该Quest完成后启动`FindHideoutTutorialQuest`并指向教程藏身处；菜单提供原版`Attack`进入Hideout流程。`enter_hideout_on_consequence`直接调用`CampaignMission.OpenHideoutBattleMission("forest_hideout_003", ..., isTutorial:true)`；胜利后才会打开Radagos对话。对话有决斗或“让手下攻击”的分支，分别切换该Mission控制器的duel/battle mode。此为Campaign Mission/Encounter与自定义StoryMode内容，不等于普通地图坐镇战斗已覆盖。
5. 成功击败/解决Radagos后，Quest经过兄长对话、家族名字TextInquiry、`BannerEditorState`和藏身处物品菜单；任务 `OnCompleteWithSuccess` 调 `MainStoryLine.CompleteTutorialPhase(false)`，后者发出`OnStoryModeTutorialEnded`并建立FirstPhase。原版`FirstPhaseCampaignBehavior.OnStoryModeTutorialEnded`随后自然启动`RebuildPlayerClanQuest`（Establish Your Clan）。Tutorial结束后还可能跟着独立的 `VillagersInNeed` Stealth Tutorial；它不是同一个Quest，是否影响家族目标循环需按当时Native状态处理。

实现边界：现有Bridge虽有局部Mission场景观察/接近/互动接口，但`AgentHostCampaignLoop`允许动作及`AgentHostRuntimeController`请求均没有把Mission动作接入StoryMode目标循环；也没有`TextInquiry`/`BannerEditorState`和上述Tutorial任务续接的Host运行证据。因此“已有游戏内动作”并不证明新档路线可通。下一步必须核验Mission里的原生战术指挥/模拟/退出回退能否让AI完成而不逐帧控制，确认Hideout Mission具体目标/胜负/返回状态，补文本输入/旗帜确认状态，以及Tutorial跳过是否属于玩家开局设置的独立原版路径；若自然AI闭环要涵盖未跳过教程，Mission阶段是明确的实现缺口，不得用预备`save002`测试替代。

来源：`StoryMode.dll`的 `StoryModeManager/MainStoryLine`、`TutorialPhaseCampaignBehavior`、First/Second/Third phase Quest behaviors/QuestTasks、`StoryModeEncounterGameMenuModel`与Campaign `QuestBase`；版本v1.4.8.119303。未知Story/New Campaign各设置对流程的精确删减、分支是否会阻塞/过期、跳过/回档时任务数据的存取，以及所有剧情分支完整玩家操作/失败恢复矩阵。

## 跨域关系与当前适配边界

传统关系数据、家庭和Trait的规则以B/C/I为准；对话、说服、Quest/Incident/日志在此描述它们出现的消费者，不将关系变成一个全局活动清单。Evidence等级区分：本机反编译/数据资源、结构化State运行、自动UI动作/结果和人工视觉确认；本篇大量分支目前只有本机源码链，没有完整Campaign实测。

Chronicle Observer目前重点覆盖Campaign状态、附近对象和Quest摘要；Protocol能读部分GameMenu/Conversation选项和走过的特定Issue/战斗流程，但不是通用Story/Quest/Incident/Journaling/Notification/Tournament/BoardGame Agent。当前没有任何因分类编号而自动推断“已支持”的结论。各域未决玩家行为/观察分母留待W1-M与A-L类别交叉去重，不在此复制完整日志或项目状态。

地图贵族Party上的委托图标来源进一步确认：本机1.4.8 `PartyNameplateVM.RefreshDynamicProperties`在Nameplate处于地图显示状态时，把LeaderHero当前`Issue`经`CampaignUIHelper.GetIssueType`编码到`IssueQuestFlags`，并合并`GetQuestsRelatedToParty`返回的活动/追踪Quest；Army leader还会汇总自身与附属Party的标记。`QuestMarkerVM`从flags显示图标；它拥有Quest标题/提示文本字段不代表玩家仅看地图标记就能读到这些信息。Flag区分AvailableIssue、ActiveIssue、ActiveStoryQuest、TrackedIssue、TrackedStoryQuest；只有AvailableIssue对应待接委托提示，活动/追踪旗标不得一概解释为新任务。

用户于2026-10-01确认地图贵族部队领主名字旁的蓝色感叹号是委托标记。W2-AU已在`mapPartyTargets`为原版nameplate候选提供`questMarkers`分类与`hasAvailableIssueMarker`：`null`表示不Spotted或已在Settlement、`[]`表示Native名牌候选无标记、非空数组返回Issue/Quest类别。`TestResults/20261003-101114/Temp/MapPartyQuestMarkersResult.json`用一个原版IssueManager合法候选测试AvailableIssue正向和另一Party空标记负向；结果不泄漏Quest title/description/dueTime，存档未变、进程清理。Settlement人物Overlay仍是另一有限视图；摄像机同屏、Army名牌聚合及Active/Tracked/Story标记实测未覆盖。
运行证据：`TestResults/20261003-101114/Temp/MapPartyQuestMarkersResult.json`。从当前`mapPartyTargets`中选择一名本地可见、已Spotted且不在Settlement的Lord Party；Harness通过Native `IssueManager.CheckForIssues`获得该Hero的41个候选之一，并由`CreateNewIssue`创建有效`TheSpyPartyIssue`。创建前该Party `questMarkers=[]`，创建后Native `GetQuestStateOfHero`与观察器均含`AvailableIssue`；第二个Lord Party保持空数组，重复读取稳定，Quest标题/描述/期限未泄漏。Engine帧对照蓝色叹号、源存档hash不变、进程退出。当前只运行AvailableIssue正向/无标记负向；story/active/tracked flags的具体UI与Army nameplate汇总仍未知。此测试Issue只在disposable Campaign内存，不代表玩家接取或接受任务。
地图贵族Party委托接取与Settlement overlay/QuickConversation必须分开。W2-AV运行`TestResults/20261003-110250/Temp/MapPartyQuestAcceptanceResult.json`：通过`mapPartyTargets`观察一支当前AvailableIssue的Lord Party，Native `pursue`接近后进入地图`encounter_meeting`，观察Hero问候和Issue选项；只沿当前Conversation动态出现的选项前进，包括`hero_give_issue`和Issue说明桥接。`TheSpyPartyIssue`同时开放Alternative说明路径；测试只通过“除了四处打听，还有其它办法吗？”查看可选方案，并未派遣同伴/执行Alternative，最终仅在原版`issue_offer_player_accept_quest`可点时接受。Quest `issue_153_quest`/“谍影迷踪”以该Hero为QuestGiver，Quest计数0→1、期限16日，Gold1000不变，地图接近自然将Day 91077.378→91077.397，对话/接受Stop，源档hash一致、三帧、进程退出。两次初试分别是Harness回执字段与对话状态层级断言错误；失败收据留在`20261003-105312`和`20261003-110002`，修正后最终运行通过。此证据证明一个地图Lord Issue Quest启动切片，不覆盖其他Issue条件、Alternative/Lord方案或后续任务完成。
接受后同一`mapPartyTargets`候选复读结果在`MapPartyQuestAcceptanceResult.json`中亦从`AvailableIssue`变成`ActiveIssue`，`hasAvailableIssueMarker=false`；这避免Agent把已接任务再次误当作可领取委托。此动态标记是观察变化，不自动表示任务步骤完成。

### 2026-10-27：动态对话选项的稳定文本身份

1.4.8 `TextObject`公开`GetID()`；当前StoryMode XML把Villa Mission入口与拒绝入口分别标为`glarczej`/`nhSLTzHk`。真实中文界面中的可选项运行ID是`adg:131`、`adg:132`，说明模型必须按当前可见option ID提交，但安全策略不能把每次变化的运行ID当作语义身份。Chronicle Observer schema 28在每条Conversation option同时传送运行ID、可见文本与原版TextObject `textId`；StoryMode首轮不把`glarczej`加入PartySize子循环允许目录，`nhSLTzHk`仍作为当前可见原版推迟选择。`TestResults/20261027-020732`真实模型曾选择“带路吧”并启动Mission转场；`20261027-022308`只通过包内模拟对动态ID+稳定TextId门禁，真实`GetID()`与推迟后的原版返回状态仍待实机验证。
`TestResults/20261027-022658`实机进一步确认最终拒绝分支的后验：当前NPC对话以动态option `adg:132`提交后返回`MapState`和`sandbox village`菜单，`recruit_volunteers`在同一Native状态可用；没有进入庄园Mission。它随后因Agent输出的`slot`/确认值类型为JSON字符串而在Host参数校验被拒，未执行招募。故原版对话拒绝与返回路径得到运行证据；RecruitmentVM交易仍待新的类型修复运行验证。

`TestResults/20261027-053836`再次从地图移动进入`village_ES3_2`后，Native快照已是`MissionState`、该VillagersInNeed Quest仍active，但ConversationManager的Character ID与选项当时为空；PartySize Host因未识别到已就绪人物而在执行任何对话动作前安全停止。该边界说明`CampaignMission.OpenConversationMission`进入MissionState与当前ConversationManager形成可操作对话之间存在异步帧差。Host只在固定村庄、对应Quest仍活动且MissionState尚无Character ID时最多被动等待10次×500ms并重复Native观察，之后继续严格检查确切Character，不调用时钟/任务修改。Fake Native/Host回归模拟“MissionState无对话→Character/选项就绪→继续当前对话→拒绝Villa Mission→Village菜单”，`TestResults/20261027-054956`Package通过；真实运行还需确认等待期间Mission返回不会变化，以及推迟入口后继续招募。

自然运行`TestResults/20261027-055510`同样移动进入此Quest村庄，但首次可操作Native观察时ConversationManager人物和可选回答已经准备好，故pending-settle计数为0。模型按当前答案选择推迟，返回Village MapState，再由原版RecruitmentVM招募6人；此时PartySize Journal仍未达标。该运行验证已准备完成的对话路径，不证明MissionState无Character的过渡等待分支。
