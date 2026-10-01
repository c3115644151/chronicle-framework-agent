# J 类研究：任务、事件与叙事

适用本体：Bannerlord v1.4.8.119303。本文是 J 域唯一研究资料，按 SYSTEM_INVENTORY 的 J01-J12 次序记录。关系数据机制归 B/C/I；此处只研究任务、事件、对话、日志等消费者与玩家入口，不复制个人关系模型。

## J01 Issues：NPC委托与问题

### 真实入口、生成与接取

Issue是带有发起者、频率/冷却、解决条件和后果的Campaign委托。玩家此前确认地图中出现蓝色感叹号的委托标记；这里将其记录为玩家界面观察，不把它冒充本机UI实测。`IssueManager`会检查Hero的候选Issue类型/冷却、建立/分配Issue，并按每日/每小时tick使其失效、迁移、终结或转交AI领主处理；`IssueBase`保留Owner与DueTime，并让每个具体Issue提供 `CanPlayerTakeQuestConditions`、留存条件、超时后果和 `GenerateIssueQuest`。

玩家入口通常是有有效Issue的Notable/领主交互；地图标记/菜单提示用于显示可交谈人，交谈后由Issue特定条件决定哪些解决分支开放。1.4.8 `IssuesCampaignBehavior` 的共用Conversation链提供Quest、Alternative和Lord三种不同处理：Quest通过`IssueManager.StartIssueQuest`进入Issue Quest；Alternative需有可派遣同伴、通过Issue自己的`AlternativeSolutionCondition`，选择同伴并在条件要求多名士兵时打开PartyScreen配置满足人数/兵种的健康部队，确认后从MainParty roster移出并调用`StartIssueWithAlternativeSolution`，同伴进入busy状态，部队延迟返回；其后还会按Issue设置的天数、伤亡/失败风险结算。Lord Solution要求Issue自己的`LordSolutionCondition`、Issue owner当前聚落属于玩家Clan且玩家Influence足够；玩家选项先调用`StartIssueWithLordSolution`，随后仅在存在CounterOfferHero且issue owner仍在Settlement时开启第二段对话，否则通用代码自动走拒绝counteroffer结算。拒绝该NPC的counteroffer会扣`NeededInfluenceForLordSolution`并走成功/拒绝counter的Issue后果；接受则走Betrayal后果，不扣这笔Influence。以上三条的入口、前置、时间/资源与终态不同，不以“接委托”合并；Alternative和Lord能否按更细子类/确认节点继续分族，仍需查具体Issue override与提交/取消恢复。

玩家已于2026-10-01确认：进入村庄/定居点后，右上人物列表列出当地要人；有委托的Hero名字旁显示蓝色感叹号。地图贵族部队领主名字旁也有蓝色委托标记。点本地要人后有“交谈”与“造访”两条不同路径：前者直接快速对话，结束后回到地图聚落菜单；后者进入其Location场景，对话结束仍留在场景，键鼠长按Tab约2秒（本体Leave Area）才返回。1.4.8 SettlementMenuOverlayVM分别创建QuickConversation与Conversation，Native中文Localization对应“交谈”(OPhlqUVl)与“造访”(toK51MD4)；GameMenuOverlay.ExecuteTroopAction(QuickConversation)校验SettlementOverlayQuickTalkPermissionEvent后调用CampaignMapConversation.OpenConversation，Conversation则校验SettlementOverlayTalkPermissionEvent、触发OnPlayerStartTalkFromMenu并创建目标Hero Location Mission。当前Observer只暴露玩家所在聚落人物列表与Quest markers；地图党派观察未暴露贵族Leader的Quest marker，故不能声称地图人物标志覆盖完整。当前talkToSettlementHero实现的是Conversation/造访而非QuickConversation/交谈，命名和产品语义不符，必须拆为talkToSettlementHero（交谈）与visitSettlementHero（造访）。旧TestResults/20260927-052705只验了Visit/Mission路径；快速路径的进入、Dialog观察、结束回菜单和Campaign时钟仍待运行验证。

W2-E目前只验证真实原版门槛的拒绝分支，正向接取仍未完成。运行`TestResults/20260927-060748/Temp/SettlementOverlayQuestAcceptanceResult.json`使用上述目标式Conversation，Harness只选择当时实际可用的问候/`hero_give_issue`选项；IssuesCampaignBehavior未开放Quest solution，Conversation返回“你得有些锻造经验”，Quest仍为0，未接受Alternative/Lord方案。1.4.8 `GangLeaderNeedsSpecialWeaponsIssue.CanPlayerTakeQuestConditions`显示需Crafting≥30、关系不低于-10且不处于战争；运行命中锻造等级门槛并被原版拒绝，没有存档/状态变化。此结果只证明前置保护工作，不代表成功接取任一Quest，也未穷举其他Issue类型/合法接受分支。须再以自然满足条件的Notable/Issue通过原版接受选项启动一个Quest，方能关闭W2-E。

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

Chronicle新增按需`mapNotifications`，仅在Campaign Map状态读取`Campaign.CampaignInformationManager`的Notice队列。1.4.8没有公开枚举接口，当前适配通过版本内反射读取`_mapNotices`，先检查`InformationData.IsValid()`，再用Native `MapNotificationVM.AddMapNotification`经过其注册表生成对应`MapNotificationItemBaseVM`；向Agent只返回原版ItemVM提供的类型、标题、描述、NotificationIdentifier、ForceInspection，不枚举底层对象/额外目标字段。临时VM只为映射Notice数据，在finally中逐个`OnFinalize`并自身`OnFinalize`，不触发点击、相机跳转、焦点、移除或Proceed回调。因为这不是活动UI中的具体焦点控件，不返回`IsFocused`。

`TestResults/20260930-061737/Temp/MapNotificationsResult.json`在disposable Campaign中经Native `CampaignInformationManager.NewMapNoticeAdded`加入一个Harness-only已注册`TraitChangedMapNotification`、一个未注册自定义InformationData和一个`IsValid=false`自定义InformationData；查询只返回注册类型，具体ItemVM为`TraitChangedNotificationItemVM`，本地化标题“获得特质”、描述文本、NotificationIdentifier保真。重复读取保持顺序/内容稳定， invalid/unregistered都不泄漏；Gold/Roster/Quest/位置/时钟/日期无变化，源fixture哈希相同且进程退出。此运行只验证一个受注册类型；未验证真实自然通知产生频率、每个Notice子类的专属字段、实际屏幕焦点/鼠标跳转/移除按钮、通知过期后现存UI的清理，也不覆盖QuickInfo、SceneNotification、Quest Journal与百科日志。

来源：`CampaignInformationManager._mapNotices/OnGameLoaded/NewMapNoticeAdded/MapNoticeRemoved`、`MapNotificationVM.PopulateTypeDictionary/AddMapNotification/GetNotificationFromData`、`MapNotificationItemBaseVM`、`DefaultNotificationsCampaignBehavior`及各通知类。未知各notice类型对同一物件的目标摘要如何表达、模态覆盖时UI可见范围、优先级/已读/失效边缘和第三方注册通知兼容。

## J08 Conversations：NPC对话流程

对话不是一组静态按钮列表。`ConversationManager`保留当前ConversationFlow/参与者/标签/阶段和可用Sentence；每句包含Condition、文本、InputToken/OutputToken、Consequences等内容，选项在当前上下文动态增删。`CampaignMapConversation`、Mission/Scene Conversation、聚落Notable交谈、地图队伍遭遇/领主会面、俘虏和Issue等入口会加载不同Flow与身份数据。

玩家实际通过进入相应谈话对象/场景开始会面、选择当前开放句、继续/退出；场景交谈可能先经过3D移动、HUD互动、地图遭遇菜单或GauntletMission。Sentence consequence可调用多个Campaign actions或创建/更新Quest/Barter/Persuasion/Party状态。直接调用某个后果会绕过Sentence条件、当前Conversation状态、正常动画/离场和提示。

跨域分母边界：`dialogueSelect`只是代理/输入层对当前valid Sentence执行点击的通用工具操作，不等于一项单独的Bannerlord行为。会创建/完成Quest、改变关系/阵营、开启或提交Barter/Persuasion、释放俘虏、开启Mission等Sentence consequence由各自领域的实际ACT承载，不能再加一个“点击对话选项”ACT重复计数；没有世界状态提交的询问/过场/显示信息，其信息与新Option列表并入`OBS-J08-01`。新发现的Sentence分支若产生此前未映射的实际世界效果，应补该领域ACT，而不是扩成一个吞并所有Conversation后果的J08族。

原有关系反馈的边界见 I01/I04/I09与本J文关系段：文本/选项由Identity、Faction、Trait、关系、任务和世界状态筛选，关系不一定作为独立历史来源呈现。Chronicle通用Conversation适配目前只覆盖Map Lord会面首段：pursuit自然接触→Observe开放选项→invalid option/Continue guard→选择当前intro response→re-observe新Sentence/选项。运行收据`TestResults/20260926-214832/Temp/AgentConversationResult.json`显示问候后出现`hero_give_issue`等后续选项，本测试未选择Quest/Barter/关系分支；该垂直切片证明Protocol操作已进入ConversationManager，不代表全量对话目录或自动跑3D接近。来源：Campaign `ConversationManager/ConversationSentence/CampaignMapConversation`、Sandbox DialogFlow/ConversationBehaviors、ViewModelCollection `ConversationVM`、当前Chronicle Protocol。未知全体ConversationFlow/条件去重分母、对话状态被任务/战斗打断后的恢复、不同语言和Mods扩展的动态选项。

## J09 Persuasion Dialogues：说服过程

Persuasion是J08对话内的一种状态化子流程。`PersuasionTask`保存当前目标、目标值/成功值、难度、可用Argument与已尝试情况；`DefaultPersuasionModel`以目标Trait、关系、ArgumentStrength、玩家Skill/Perk和difficulty multiplier等参数计算success/critical/failure概率和下一阶段/封锁选项效果。实际尝试以当前Conversation开放的argument为入口，结果再由该Task/Conversation consequences决定增加进度、继续、失败、关系变化或Quest后果。

求偶、说服领主、Quest谈判等会分别初始化不同task，不能将一项Persuasion成功率输出到所有NPC。UI必须显示合法选项和条件提示；直接反复调用概率模型不会生成合法对话尝试或完整失败后果。当前Chronicle只尝试选择真实开放选项，无专用Persuasion状态/机会/剩余尝试观测。数值数据与社交入口见I04/I10。来源：`Persuasion/PersuasionTask/PersuasionAttempt`、`DefaultPersuasionModel`、`PersuasionVM`和Romance/Issue相关behaviors；未知不同Task建立源/概率公式全部权重、重复点选/关闭对话后的持久状态、测试seed与真实随机分布。

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

来源：`StoryMode.dll`的 `StoryModeManager/MainStoryLine`、`TutorialPhaseCampaignBehavior`、First/Second/Third phase Quest behaviors/QuestTasks、`StoryModeEncounterGameMenuModel`与Campaign `QuestBase`；版本v1.4.8.119303。未知Story/New Campaign各设置对流程的精确删减、分支是否会阻塞/过期、跳过/回档时任务数据的存取，以及所有剧情分支完整玩家操作/失败恢复矩阵。

## 跨域关系与当前适配边界

传统关系数据、家庭和Trait的规则以B/C/I为准；对话、说服、Quest/Incident/日志在此描述它们出现的消费者，不将关系变成一个全局活动清单。Evidence等级区分：本机反编译/数据资源、结构化State运行、自动UI动作/结果和人工视觉确认；本篇大量分支目前只有本机源码链，没有完整Campaign实测。

Chronicle Observer目前重点覆盖Campaign状态、附近对象和Quest摘要；Protocol能读部分GameMenu/Conversation选项和走过的特定Issue/战斗流程，但不是通用Story/Quest/Incident/Journaling/Notification/Tournament/BoardGame Agent。当前没有任何因分类编号而自动推断“已支持”的结论。各域未决玩家行为/观察分母留待W1-M与A-L类别交叉去重，不在此复制完整日志或项目状态。
