# F 类研究：军事、队伍与战役 AI

适用本体：Bannerlord v1.4.8.119303。本文是 F 域唯一研究资料；按 F01-F13 系统清单编号组织事实、现有适配和未知，跨域内容以链接为主。

## F01 MobileParty 与 PartyBase 对象

### 对象关系

`MobileParty` 是 Campaign Map 中可能移动、拥有目标和 AI 行为的 Party 实体；它通过 `PartyComponent` 指定用途/所有者/领袖与初始化行为，并持有独立的 `PartyBase`。`PartyBase` 既可包装一个 MobileParty，也可包装一个 Settlement；它提供成员 `MemberRoster`、俘虏 `PrisonRoster`、物品 `ItemRoster`、Party地图事件/战斗状态和数量/上限等通用 roster 侧信息。地图位置、AI、路径和移动目标由 MobileParty 层持有，不能把 `PartyBase`/roster 与一个地图队伍实体混写。

组件类型包括 Lord/WarParty、Caravan、Garrison、Villager、Bandit、Militia、Patrol、Custom 等。MobileParty 可有 `LeaderHero` 与 `Owner` 两种角色来源；两者不应假定始终是同一 Hero。`IsLordParty`、`IsCaravan`、`IsGarrison`、`IsVillager` 等类型标志和对应 PartyComponent共同决定各系统是否把队伍视为AI领主、商队、驻军或居民运输队。

每种 roster 的量化含义有差异：MemberRoster 包含部队成员和伤兵数量；PrisonRoster 独立保存被俘成员；ItemRoster 保留 EquipmentElement及数量。`NumberOfAllMembers`、健康/伤兵数、Prisoner数、PartySizeLimit、PrisonerSizeLimit、库存载重与 Food 各自服务不同系统，不能用一个“部队人数/物品总数”字段替代整个 Party 状态。

### 生命周期与引擎连接

Campaign 管理全体 MobileParty 及各类别集合；`MainParty` 是 Campaign 当前玩家主队。队伍组件创建/销毁、加入/离开 Settlement、队长/Owner变化、Party转为俘虏/驻军/商队、加入/脱离Army以及 MapEvent 结束会分别触发 Action、PartyComponent钩子和 CampaignEvent。故 Party 身份、所属阵营、地图行为、rostering、工资/食物、战斗和战后处理是互相连接但由不同引擎子系统维护的状态。

`PartyBase` 还能表示 Settlement garrison/settlement party，但并非所有 PartyBase 都是可移动 Party；Militia、Garrison、Villager等虽会有对应MobileParty组件，但资格、导航和定时行为常由不同Model/Behavior进行过滤。Party 可能在地图层被抽象移动/结算；进入 Encounter、Town/Scene或Battle Mission 才启用相应地点/战斗状态。抽象队伍和 Mission 的实际 Agent/Formation不是同一层实体。

### 玩家入口与 Chronicle 当前观察

玩家的主要 Party 是地图上 `MobileParty.MainParty`。创建和管理人员、装备、俘虏的玩家入口分布在 Party Screen、地图遭遇/战后、聚落驻军和战斗队伍界面；具体 PartyScreen 提交、伤兵转移、升级与俘虏操作入口分别由 F11/F12、G/H域深入记录，本节不以 API setter 替代玩家流程。地图移动、追击、Hold、Wait与Campaign时钟的原生玩家行为以 MAINLINE 机制契约为准。

Chronicle当前常驻Snapshot对MainParty输出成员/健康/伤员/俘虏人数、总物品数、粮食、每日FoodChange、DailyWage、速度、士气、cargo weight/capacity、AI MoveMode/DefaultBehavior和目标ID。NearbyParty只枚举可见且活动的队伍、按观察半径排序并最多给前12项，字段含ID/Name/Type/Distance/Hostile/IsMoving/CurrentSettlementId/成员数/估算实力；不列具体Roster、领袖身份、物品/现金/食物、目标Settlement、任务或AI思考评分。另有按需只读`mapPartyTargets`，列出Campaign Map中active、非Garrison/Militia、未附着其他队伍且`PartyBase.IsVisible`的移动Party marker，不受附近半径/12项限制；输出marker/nameplate摘要。普通已inspection MobileParty和Army leader分别进入两种原版Tooltip路径，均通过`mapPartyComposition(partyId)`按需读取。

当前观察所以是“一个玩家队伍的较丰富结构化观察 + 附近队伍有限摘要 + 按需全局可见marker摘要 + 按需单对象组成”，不是全图Party roster census，也不是所有战役队伍完整自省。玩家视觉核对：地图可见队伍显示人数；悬停并按住ALT可查看政治队伍兵种/人员构成。此入口为用户实际观察确认、未留截图。源码把基础marker可见与`IsInspected`详细侦察区分；不要将ALT详情推广到不可见或未inspection对象。Army leader提示使用另一套Native Army Tooltip及聚合VM。

官方 `MobileParty.IsInfoHidden` 字段会被官方 PartyNameplateVM 读取，但用户确认原版不存在这一信息隐藏玩法，只有部分Mod实现；在已检查的官方CampaignSystem/SandBox/StoryMode代码中也未找到赋值点。因此它作为UI兼容钩子/Mod扩展字段处理，不作为Chronicle原版观察过滤条件。Harness一次性战役所用模块包含Harmony、ButterLib、UIExtenderEx、MBOptionScreen等前置；本次六个可见Party样本字段均为false，只能作为该测试模块集证据，不能称为纯净原版运行。

`mapPartyTargets`窄运行 `TestResults/20260927-122102/Temp/MapPartyTargetsResult.json`：六个返回项与本体可见marker候选ID一致；名称、类型、检查状态、健康成员/伤员/俘虏人数及距离逐项匹配；重复稳定、Campaign/存档不变、进程退出。它依据Campaign `IsVisible`定义marker目标，不声称等于当前摄像机屏幕裁切；attached Army子队伍不重复列为独立地图目标。

普通Party `mapPartyComposition(partyId)`窄运行 `TestResults/20260927-131611/Temp/MapPartyCompositionResult.json`：六个可见/inspected候选中挑选一支Lord Party，13种成员类型的ID、名称、数量/健康/伤兵/Hero字段匹配Roster诊断，且名称出现在官方1.4.8 `PropertyBasedTooltipVM(IsExtended=true)`扩展提示中。无效ID `rejected`、重复稳定、Campaign/存档未变、进程退出。不是ALT键输入模拟或玩家画面录屏；测试模块有Harmony/ButterLib/UIExtenderEx/MBOptionScreen等前置，不称纯净原版。

Army leader `mapPartyComposition`窄运行 `TestResults/20260927-140439/Temp/MapArmyCompositionResult.json`：Harness通过官方`Kingdom.CreateArmy`并加入一支同Faction Party建立一次性Army；随后使用Army的原生`AddPartyToMergedParties`入口使该Party附着。原生`RefreshArmyTooltip`扩展VM与Agent聚合Roster一致，leader与附属Roster合并后为14种成员行，UI VM逐项匹配。源档未保存、campaign停止、进程退出。此验证测试Native合并方法/tooltip数据，不等价于真实AI部队旅行到达或玩家点Army按钮。

源码显示Army leader tooltip把leader与AttachedParties Member/Prison roster合并；本机Harness以Native `Kingdom.CreateArmy`初始化Army及受邀Party后再调用Native合并入口，避免单独构造Army或绕过CampaignEvent。早前不完整的直接Attach夹具曾在`StatisticsCampaignBehavior.OnPartyAttachedAnotherParty`空引用（`TestResults/20260927-130944`）；根因是夹具未按原生Army邀请/注册顺序建立状态，而不是客户端自然运行崩溃；该次进程关闭、存档未保存。当前一个附属Party的成员聚合已验证，但自然Campaign邀请/移动/抵达及多附属Army、非空伤兵/俘虏输出仍未知。`IsInfoHidden`是Tooltip兼容字段，用户确认本体没有对应信息隐藏玩法。

证据：本机 `TaleWorlds.CampaignSystem.dll` 的 `MobileParty`、`PartyBase`、PartyComponents、Roster与Encounter事件；Chronicle `AgentObserver.cs`、`AgentProtocol.cs` 及 MAINLINE 原版动作契约。静态证据版本 v1.4.8.119303，没有声称各类 Party UI 或 Mission roster 已完整视觉验证。

未知项：各种 PartyComponent 的所有创建源、Destroy/Convert、Owner/Leader/Clan/Faction转移及 SaveData 生命周期；主队/领主队/Minor Faction/Caravan/Garrison/居民等模型过滤矩阵；伤员、英雄、俘虏和Roster操作各玩家 UI 的逐项结果；Map/Encounter/Mission 三层 Party 状态在暂停、结算、保存/加载时的交接边界；不同Mod对类型标志、AI和Roster的新增字段/行为。

## F02 Party AI 决策与执行层

### Campaign 战略目标选择

原版 `AiPartyThinkBehavior` 订阅 `TickPartialHourlyAiEvent`。新建 Campaign 后它会对已存在 Party 初始化触发 Think；MobilePartyCreated 会标记 `RethinkAtNextHourlyTick`。战争/和平、Clan换Kingdom、SettlementOwnerChanged 等事件会结束或修正失效的领地目标、要求重新评估 Army/Party 行为。

参与 Think 的 Party 必须启用 AI 且未被 `DoNotMakeNewDecisions` 禁止；Party Think 明确排除 `MobileParty.MainParty`。正常 NPC Party 的目标重算约以数个 HourCounter 间隔执行；Army Leader、Transition、Attached Party、显式重想标记和围攻/掠夺战斗会调整频率。Encounter中的普通Party不会照常任意换目标，Raid/SiegeAssault 的特定攻击方是例外。

### 目标候选如何聚合

Think 时清空 `PartyThinkParams` 并派发 `CampaignEvents.AiHourlyTick(party, thinkParams)`。注册的各 AI Behavior 向参数中添加 `AIBehaviorData` 和分数；候选记录行为类型、目标 Party/Settlement 或位置、NavigationType/港口参数及是否计划聚集 Army。`AiPartyThinkBehavior` 选择最高分候选，并另保留一个不要求 Gather Army 的候选，之后结合当前 Army、目标、ObjectiveValue、DoNotChangeBehavior 和随机阈值选择是否切换。

当前安装版公开接口细节：`AIBehaviorData`为公开struct，字段包括`Party:IMapPoint`、`Position:CampaignVec2`、`AiBehavior`、`WillGatherArmy`、`IsFromPort`、`IsTargetingPort`和`NavigationType`；构造形式分别接受地图实体目标或位置目标。`PartyThinkParams`对外暴露`AddBehaviorScore`、`SetBehaviorScore`、`TryGetBehaviorScore`和候选只读列表，同时有`DoNotChangeBehavior`、`CurrentObjectiveValue`、Army强度等控制/诊断字段。`AiPartyThinkBehavior.PartyHourlyAiTick`先跳过`Ai.IsDisabled`或`Ai.DoNotMakeNewDecisions`的Party，再在重想时同步派发`AiHourlyTick`，之后读取分数并决定是否调用`SetPartyAiAction`。这些是Campaign AI内部目标选择接口，不是人类玩家的UI输入。

### 原版候选行为提供者清点（2026-10-19，本机1.4.8.119303）

对当前安装的`TaleWorlds.CampaignSystem.dll`逐类检查`CampaignEvents.AiHourlyTickEvent.AddNonSerializedListener`及对应候选构造/写入，发现以下七个内置提供者。表中“提供什么”是源码支持的候选类别，不是每个NPC都会得到该项，也不是最终必选项；Think资格、Party类型、事件状态、分数与随机切换阈值仍会过滤结果。

| 内置提供者 | 产生的决策面 | 主要适用边界/含义 |
| --- | --- | --- |
| `AiArmyMemberBehavior` | 给军团附属Party产生指向LeaderParty的`EscortParty`候选 | 仅非Leader且确为Army成员；围城封锁/海陆导航、成员是否已附着等会改变或阻止候选。这是组织从属行动，不是Actor自己的独立长期目标。 |
| `AiEngagePartyBehavior` | 产生针对地图Party的`GoAroundParty`绕行候选，并维护`CurrentObjectiveValue` | 仅特定王国/玩家阵营的领主队伍、非Caravan/非附属Army成员、可进入地图接敌计算的状态；根据敌对目标与路径条件评估是否绕开特定队伍。它不直接提交`EngageParty`战斗动作；结果不等于已经发生遭遇或战斗。 |
| `AiLandBanditPatrollingBehavior` | 给非Boss陆地劫匪队产生围绕HomeSettlement的`PatrolAroundPoint`候选 | 会检查Bandit身份、陆地导航、Hideout驻扎数量/感染状态；随机分数会受Hideout队伍数量影响。是劫匪活动候选，不是领主通用选择。 |
| `AiMilitaryBehavior` | 给合格军事Party提供`RaidSettlement`、`BesiegeSettlement`或`DefendSettlement`类聚落目标候选；可带`WillGatherAnArmy` | 排除民兵、商队、村民、劫匪、巡逻队、解散中Party及不合格Faction/Leader；分数结合战争目标、目标价值/距离、军团凝聚、队伍规模和食物等模型。候选不保证宣战、组军或攻城结果。 |
| `AIMoveToNearestLandBehavior` | 给当前在海上的MobileParty产生`MoveToNearestLandOrPort`候选 | 需正在海上、有陆地导航能力且可计算有效陆地点；属于海上导航恢复分支，不应当成无DLC本体的普遍NPC玩法。当前测试存档模块列表不含War Sails，尚未验证该分支能在此安装/存档条件触发。 |
| `AiPatrollingBehavior` | 给合格Party产生围绕聚落的`PatrolAroundPoint`候选，含陆上及条件性海上巡逻子分支 | 主要是有领地/派系支撑的领主队；会过滤民兵、商队、村民、劫匪、巡逻队、围城、Army成员及食物不足等状态。分数与本方聚落拓扑、导航距离、兵力/补给有关。 |
| `AiVisitSettlementBehavior` | 给目标聚落产生`GoToSettlement`候选；支持Bandit Hideout路径及聚落访问/队伍合并相关子分支 | 会排除围城状态及不适格Party；非Bandit Lord/Army Leader可依据队伍补充、聚落/驻军角色、交易卖货分数、访问间隔/目标竞争等计算访问分。源码还含解散/无领袖Party寻找合并聚落的评分，这不是一般Hero自主任务。 |

边界：这是CampaignSystem安装程序集内已反编译确认的七个`AiHourlyTick`候选提供者，不代表已穷举第三方Mod动态注册的监听器；SandBox.dll与StoryMode.dll当前静态反汇编未检出`AiHourlyTickEvent`引用，不能据此推断所有安装Mod都没有扩展。一次只读提取的`AgentBridgeLifecycle.sav`元数据列出`Native`、`SandBoxCore`、`Sandbox`、`BirthAndDeath`、`CustomBattle`、Chronicle及四个前置框架；它不代表玩家其他模组集，也没有运行时事件轨迹。证据是本机游戏版本和`ilspycmd`对上述类型的反编译/事件注册扫描；字段/分支的完整逐个评分模型仍未拆完。

### 一次真实 Campaign 的 Think cache 观察

`CampaignActorThinkTrace`在 `TestResults/20261019-022445/Temp/CampaignActorThinkTraceResult.json` 通过。只读查询公开的`MobileParty.ThinkParamsCache`，从`AgentBridgeLifecycle`中捕获到非MainHero Lord `lord_1_21`、Party `lord_1_21_party_1`、Clan `clan_empire_north_1`的一次非空Native Think候选集合。该样本含110条目标候选：`GoToSettlement` 47、`PatrolAroundPoint` 38、`RaidSettlement` 18、`BesiegeSettlement` 7；最高观察分为前往`town_EN2`的`GoToSettlement` 2.842。样本Party当时已处于`GoToSettlement`、当前目标为`town_EN2`、位置约`(453.598,473.122)`，`AiDisabled=False`、`DoNotMakeNewDecisions=False`、`DoNotChangeBehavior=False`、`CurrentObjectiveValue=0`；记录列出目标ID/位置、分数、Army聚集标记、导航与港口标记。不同目标各自有同一行为候选，故110是该样本的目标候选行数，不是110种独立动作或概率。

Harness对本次disposable进程显式发出`advance 0.25 days`；Native遭遇在目标日到达前中断该推进，响应`completedBy=encounter`，时钟回到Stop。战役日从91077.378推进到91077.537。源档中的MainParty原先正以原生`GoToPoint`行为移动至既有目标；时间推进期间由`(207.018,389.419)`自然到达`(206.647,395.887)`，没有发出Agent `move`命令。Harness将此作为显式时钟推进下的原版移动记录，不误判为只读采样器写入，也不把普通移动与时间控制合并。采样器未写ThinkParams/Party、未提交Actor动作；MainHero身份、队伍、Gold、Renown一致，源存档SHA一致，游戏/CLI正常停止。此记录只证明一个存档/模块集、一个Hero/Party在一次Think cache下确有真实候选分数；没有证明候选被最终选中、下一次Think不覆盖它、LLM能决策，或Actor可持续实现目标。由于遭遇使Native时间推进提前结束，不把目标推进0.25日写作已完成。

这份提供者清单与单次Think cache样本不是当前MainHero AI Player的动作分母，也没有产生任何NPC控制能力。它为W8候选研究提供基础；不同Party/战役阶段下候选分布、候选到`SetPartyAiAction`的选中时序、多个Think周期中的稳定性及任何AI Actor扩展均未作为当前产品开发门禁。

因此观察到“一个 Lord Party 当前正围城/进攻”通常只说明 Campaign AI 当前已接受某个行为目标；具体行为候选来自多个 Behavior 评分，而不是 MobileParty 自己存有一个完整自然语言计划。目标会因目标消失、攻守态势、关系/战争变化、Settlement易主、Army状态和重新评估随机门限而被放弃/替换。

### 目标决定怎样落成地图行为

选定行为后，通过 `SetPartyAiAction` 写入原生行动：前往聚落、巡逻、护送、袭击、围城、守卫、绕行队伍、加入/解散 Army等。某些攻/守/巡逻行为可请求创建 Army，行动变化也可能解散原Army。地图移动目标和结算条件随后由 MobileParty/PartyThink/MapEvent/Encounter 子系统处理；当前目标调用成功不等于部队已经抵达或战斗已结束。

### Chronicle 当前覆盖

Chronicle 不读取 NPC的候选分数、`ThinkParams`、ObjectiveValue、Rethink标志、Initiative、AI禁止决策标志或目标评估理由；附近Party摘要只呈现有限状态。Protocol对 MainParty 有少量 move/pursue/hold/Wait动作，不具备向任意NPC Party设置目标/行为或控制其行动分值的动作。原版 AI 的 Campaign执行与 Chronicle Agent的玩家动作适配是两层系统。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `AiPartyThinkBehavior`、`PartyThinkParams`、`AIBehaviorData`、`MobilePartyAi`、`DefaultMobilePartyAIModel`、`CampaignEventDispatcher.AiHourlyTick`、`SetPartyAiAction`；使用本机`ilspycmd`对v1.4.8.119303 DLL读取类型/方法签名；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`。未采集不同真实Party AI Think的完整运行轨迹。

未知项：具体 AI Behavior 对各候选的评分表、模型权重与每种Party专属冷却/禁用门禁尚未全部拆开；AI HourCounter在各 Campaign 模式/地图tick速率下的精确自然时间映射；多队伍同时通过随机决策门限时 Army/Settlement目标竞争次序；Mod新增Behavior的注册和评分合并影响。

## F03 原版 Party AI 行为类型

当前 `TaleWorlds.CampaignSystem.Party.AiBehavior` 定义包括 Hold、None、GoToSettlement、AssaultSettlement、RaidSettlement、BesiegeSettlement、EngageParty、JoinParty、GoAroundParty、GoToPoint、FleeToPoint、FleeToGate、FleeToParty、PatrolAroundPoint、EscortParty、DefendSettlement、DoOperation、MoveToNearestLandOrPort。它们是原版地图行为枚举，不全是“AI长期目标”：Hold/GoToPoint/FleeToPoint等描述的可执行地图状态与攻城、袭击、Escort、DoOperation等高层行为粒度不同。

枚举行为被赋给 `MobileParty.DefaultBehavior`/`ShortTermBehavior`时，必须结合 `TargetSettlement`、`TargetParty`、`ShortTermTarget...`、地图事件与Scene状态才能理解。相同行为名称可能有不同状态转换：例如 EngageParty 是朝目标接敌的地图行为，不等于已发起战斗；DefendSettlement 可能组织周边队伍支援；FleeToGate 会以地形/聚落出口为逃离路径；这些表现与具体 `SetPartyAiAction`/`MobilePartyAi` 条件相关。

此为枚举完整名单，不意味着每类 Party 可选择全部选项。组件类型、所属Faction、地形导航、Campaign状态、Army、SiegeEvent/MapEvent和行为提供者会过滤候选；每类候选的生成逻辑归 F02/F04 及后续逐项行为链核实。`None`表示未设定候选，不等于玩家空闲操作；`DoOperation`的具体操作目标/支持子系统本轮尚未闭环。

### 地图提示中的玩家可见行为文字

当前安装版 `TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `TooltipRefresherCollection.RefreshMobilePartyTooltip` 会在队伍已 `IsInspected` 时加入 `CampaignUIHelper.GetMobilePartyBehaviorText`；该帮助方法转到 `MobileParty.GetBehaviorText`，将部分 `DefaultBehavior`/`ShortTermBehavior`/目标组合转换成可读文字，例如“Engaging”“Chasing”“Running from”“Defending”“Raiding”“Besieging”“Patrolling”或“Following”。这不是完整计划，也不是原始枚举的逐项展示；Army成员可能优先显示 `Army.GetLongTermBehaviorText`，未匹配组合则可能呈现通用 travelling/unknown 文本。

`PartyBase.UpdateVisibilityAndInspected` 为源码所见的 `IsInspected` 写入路径：正常移动 Party 的可见与调查状态受当前地图距离和 `MapVisibilityModel.GetPartySpottingRatioForMainParty` 筛选；同一 Army 的 Attached Party 可跟随 Leader 的可见性，且主队同 Army 的成员 `MobileParty.IsInspected` getter 强制为真。玩家已确认ALT悬停可查看政治Party兵种构成，但这不能证明“行为摘要”也用相同修饰键/同一可见门槛。当前证据确认源码会在满足`IsInspected`时给地图tooltip添加可读队伍行为；该行为字段的具体玩家视觉触发方式及未侦察/不同行为类型表现仍未核全，须与已经确认的ALT兵种详情分开标记。

Chronicle `mapPartyBehavior(partyId)`只对当前可见/inspected Party调用Native `CampaignUIHelper.GetMobilePartyBehaviorText`，不从后台AI字段另做翻译。`TestResults/20260927-143749/Temp/MapArmyBehaviorResult.json`中，普通Lord party返回“正在萨哥特周围巡逻。”，单成员Army leader返回“正在塔利维尔堡附近集结。”；两段结果均与对应普通/Army `PropertyBasedTooltipVM`里的行为行逐字一致。重复读取与无效ID/状态保护通过；测试模块含框架前置，未称人工屏幕视觉核验或完整文本分支统计。

## F04 决策循环与短期移动状态

Party战略 Think 与 `MobilePartyAi` 的短期地图导航是两个相邻层。前者按 partial-hourly campaign 事件统计 AI Behavior score、选择/保留 DefaultBehavior、管理Army目标；后者结合当前目标与Model重算 ShortTermBehavior、导航Point/Party，处理接近 Settlement/Party、攻击/规避/逃跑、地形路径和海陆转换。

`MobilePartyAi.TickInternal` 会在Party不活动或处于MapEvent时暂停一般短期计算；否则检查禁用期限或依据当前DefaultBehavior/目标生成短期状态。它可问 `MobilePartyAIModel.GetBestInitiativeBehavior` 对附近敌方Party选 attack/avoid 方向；不同于Strategic Think的 `AiHourlyTick` 多行为评分。主队当前追击目标丢失可触发原版Hold分支，这属于 MainParty 的地图导航规则，而不是自动NPC Think目标选择。

动作落成后，`SetPartyAiAction`设置DefaultBehavior及目标；`MobilePartyAi.UpdateBehavior`进一步映射GoTo/Flee等为目标点导航、Engage为跟随Party导航、Hold为停止，部分Defend/Flee状态经其他模型继续计算。地图到达、视野失去、遭遇启动、自然战斗和行为结束需另外由 Campaign/Encounter/MapEvent系统决定，不能把每个AI状态枚举直接当成玩家可调用的原语。

证据：当前安装 `MobilePartyAi` 的 `TickInternal`、`GetBehaviors`、`UpdateBehavior`、`CalculateFleePosition` 等；`DefaultMobilePartyAIModel` 主动/规避评分；`SetPartyAiAction`；Chronicle `AgentProtocol` 既有 MainParty move/pursue/hold 动作与 MAINLINE机制契约。时钟随 Campaign 正常模式自然推进；本节源码调用中没有给普通AI地图行为追加测试快进操作。

未知项：短期 navigation Tick/AI Think Tick/游戏每小时的引擎调度比；Initiative行为评分如何与已有 DefaultBehavior 和 Army目标优先级精确竞争；目标不可见、导航断连、港口过渡与MapEvent完成等边缘恢复的所有分支尚未录制/运行穷举。

## F05 Army 军团对象、召集与解散

### Army 结构与玩家入口

`Army` 属于某一 Kingdom，包含一个 LeaderParty 与附属 `MobileParty`；ArmyOwner、ArmyType、目标 `AiBehaviorObject`、参与 Parties、Cohesion、集合地点与创建时间等状态由 Army 保存。ArmyType 枚举包含 Besieger、Raider、Defender、Patrolling。Party 进入 Army 后仍然保有各自的 roster/Leader/Faction，但其地图行动会受 ArmyLeader 的长期目标和集合命令协调。

玩家入口至少包含 Kingdom Armies 管理页中的 `KingdomArmyVM`（列表、选择、地点、Manage/Disband/Create）与 `ArmyManagementVM`（邀请/移除 Party、估算 Strength/Influence Cost、提升 Cohesion）。实际界面入口的按键与可视交接仍未运行验证；VM源码显示玩家主要从 Kingdom Army 上下文管理自己的主军团，不能假设拥有同阵营每一支军团的同等权限。

### 地图加入未交战的行军Army（ACT-F05-04；W2-AS）

用户确认Army场景边界：正在战斗的友军Army显示JoinBattle/Leave，双方中立时只显示离开；未交战且在地图行军的Army可以加入成为成员；围城加入另属攻城入口。这与Kingdom Armies管理页编辑Army roster不同。

源码链：`PlayerEncounter.DoMeetingInternal`可在合格Army Leader会面时转入`army_encounter`；`game_menu_army_join_on_condition`要求MainParty与Army同`MapFaction`、MainParty未属于该Army，并检查Safe Passage限制。Native consequence设置`MainParty.Army`、调用`Army.AddPartyToMergedParties`建立AttachedTo并结束PlayerEncounter；直接设置`Party.Army`不能复现全部成员事件/地图状态。

Native Runtime `TestResults/20261002-165845/Temp/MovingArmyJoinResult.json`确认：Army Leader处于`GoToPoint`并移动、没有MapEvent/SiegeEvent；玩家经原版地图接近进入`army_encounter`。Engine帧显示“与军团领袖交谈 / 加入军团 / 离开…”。选择当前Enabled的`army_join_army`后，MainParty进入Army.Parties并AttachedTo Leader、PlayerEncounter关闭，随后进入Native `army_wait`。Join前CampaignDay=91077.405429/Stop；Join命令即时回执Day=91077.405/Stop，之后`army_wait`切`UnstoppableFastForward`并自然推进至Day约91077.516。Join命令本身没有显式时间动作，等待菜单推进属于原版后续状态。Gold/双方Influence不变。夹具在disposable memory中用Native `ChangeKingdomAction.ApplyByJoinToKingdom`准备同Faction、`Kingdom.CreateArmy`建立行军Army；不代表玩家政治加入/Army Management UI已视觉核验。前后截图、结构化收据、源档hash不变、进程退出。SafePassage禁用条件、围城Join、Army Management编辑仍待后续核验。
### 玩家建军与召集条件

`DefaultArmyManagementCalculationModel.CanPlayerCreateArmy` 拦截玩家未加入 Kingdom、作为 Mercenary、已作为 Leader 指挥另一支 Army、在海上、囚禁、raft、Mission、地图遭遇、对村庄掠夺或被围城等情况。管理 VM 的篮子必须保留玩家 MainParty，至少需一个可加入/现存的额外 Party 才能创建；ArmyMembership influence cost 经 Model 计算而非固定创建费。被邀 Party 还要求适配阵营、未加入另一 Army、不是 Kingdom Ruler Party、未在战斗/围城/解散等待，队伍规模通常高于 PartySizeLimit 的指定比例、在召集距离内且有可用导航/船只。关系、Party Strength/Size/距离、Clan政策、LeaderPerk和文化特性都会修正影响力成本。

确认 VM 草稿后，如 MainParty 当前尚无 Army 且在王国阵营，会建立玩家领导的 Army 并把选中 MobileParties 关联到它，按总 Influence Cost 扣除影响力；取消则不提交草稿。玩家可通过同一窗口移除 Party 或显式解散（另有影响力成本/确认）；`DisbandArmyAction` 会释放成员 Party 并记录原因事件。

ArmyManagement VM还可在已有玩家Army时逐次`Boost Cohesion`：每次把草稿`NewCohesion`提高10点（上限100），并以`ArmyManagementCalculationModel.GetCohesionBoostInfluenceCost`累加费用；Done时`ApplyCohesionChange`调用`Army.BoostCohesionWithInfluence`并结算Influence，Cancel则退回打开管理页时的Influence。它可与Party加入/移除在同一Army管理窗口/Done中组合，但目标数值和Influence效果与改成员名单独立，因此目录另列`ACT-F05-03`，不混在建军/Party roster操作里。

### 集结过程与持续管理

创建不是把所有 Party 瞬间合并为同一位置。`Army.Gather` 设集合目标，再经 `GatherArmyAction` 分发 ArmyGathered；Leader 向聚集点移动，AttachedParties 各自执行 Escort 到 Leader 的地图目标，抵达可遭遇的距离后才加入合并 Party 位置/Overlay。玩家 Army 以主队附近的可达聚落作为 gathering point；AI Army 由目标/目标 Settlement 决定适合的集合地点。

Army Cohesion 默认从 100 开始并受模型每日变化影响。基础下降、成员 Party 数量、饥饿、低士气、目标、Perk/政策、围城等都可能参与；玩家可消耗 Influence 主动提升Cohesion。Cohesion持续减损、长时间不活动、缺粮、无战争等条件可触发不同的ArmyDispersionReason并解散。已验证枚举原因包括 CohesionDepleted、ObjectiveFinished、FoodProblem、NoActiveWar、Inactivity、LeaderPartyRemoved、PlayerTakenPrisoner、ArmyLeaderIsDead、NotEnoughParty等；各条件对玩家/AI Army并不相同。

### AI 与互动边界

原版 AI Party Think 可根据高分 `WillGatherArmy` 决策由 Kingdom 创建 Raider/Defender/Besieger 等 Army，并为候选 WarParties 算参军意愿/Influence成本；`AiArmyMemberBehavior` 使成员 Party 随 LeaderParty，在海上、围城、地图遭遇时有特别处理。F02已记录 Think 评分过程；此节只记录 Army 作为多个 Party 的组织对象，ArmyWarTarget 的战争原因与围城细节另见 F06-F08。

Army并不提升成员Party所有经济/人员状态为共享池。每个队伍仍分别携带食物、工资预算、士气、受伤和物品；军团聚合人数、Army cohesion、Leader map behavior是集合层。发生战斗后参战 roster、每Party贡献和队伍存活/脱离由 MapEvent/战斗结算层负责，不是Army加入本身。

### Chronicle 当前覆盖

Observer目前只对 Nearby Party 摘要输出成员数和 EstimatedStrength，不输出其Army ID、ArmyLeader、AttachedParties、ArmyType、Cohesion、Objective或成员招募代价；MainParty快照也没有军团管理页面内容。Protocol未实现从 Kingdom Army 页面选择Party、创建/解散Army、调整军团目标或BoostCohesion的完整交互；只适配MainParty移动、菜单与少量其他事务。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Army`、`DefaultArmyManagementCalculationModel`、`GatherArmyAction`、`DisbandArmyAction`、`AiPartyThinkBehavior`、`AiArmyMemberBehavior`；ViewModelCollection 的 `ArmyManagementVM`、`KingdomArmyVM`；Chronicle Observer/Protocol和MAINLINE。版本v1.4.8.119303源码证据，尚未实机建立、召集、取消或解散玩家 Army。

未知项：Kingdom管理页面具体按键/Army管理View打开与取消恢复序；玩家AI Colony/领地页以外可触发Army管理的其他入口；每类 Party 的完整 eligibility 和成本公式在修改/费率Perk下的变化；Army与军团分裂/继承、战争/和平、玩家囚禁和结盟同步的全部后果；真实地图集结期限/自动解散条件与UI通知顺序。

## F06 Clan War Party 与玩家家族队伍

### WarPartyComponent 与 Clan 队伍名册

`WarPartyComponent` 是族长/领主的可移动 Party Component 基类；`OnInitialize/OnFinalize` 分别登记/移除 `Clan.WarPartyComponents`，Clan 改变时同步从旧/新 Clan 的名册迁移。`Clan.WarPartyLimit` 由 ClanTierModel 按当前 Clan Tier 计算；`CurrentTotalStrength` 会汇总 Clan WarPartyComponent队伍和其名下 Fief Garrison 的 EstimatedStrength。Caravan、Garrison等有各自 Component/名册，不能直接等同为所有 `WarPartyComponents`。

NPC Lord Party 的初始化会以 Lord Hero 为Party Leader，按所属 Clan DefaultPartyTemplate（Rebel Clan则用 RebelPartyTemplate）填入初始队伍，并给予一批 Grain；Campaign与PartyUpgrader/招募/升级等系统后续维护 roster。具体NPC招募频率与目标是 F11/F03/F04交叉项，本节不把全体NPC队伍模板当成玩家复制的“自动成长”。

### 玩家从Clan页面创建家族Party

`ClanPartiesVM` 在Clan管理的Parties类别中提供“Create new party”，默认模型与VM共同要求仍有Party slot (`WarPartyLimit - WarPartyComponents.Count > 0`)、有可带队的可用 Clan Hero/Companion、地图操作允许且MainParty没有在海上/raft，并要为该新Leader补足 `ClanFinanceModel.PartyGoldLowerThreshold` 的资金。创建时会列出候选及每名 Hero 的状态/限制；被囚禁、未成年、Governor、已带队、Fugitive、正在海上或资金不足等候选不可用或显示禁用原因。

确认后 `MobilePartyHelper.CreateNewClanMobileParty` 创建以新 Hero 为领袖的 `LordPartyComponent`。如果该 Hero 仍在 MainParty，先从 MainParty roster 移除；随后在当前 Settlement 或当前/合适地图位置生成新队伍，VM 将最低 party gold补给给其 Leader，并将新队伍设为 Hold。关键差异：`LordPartyComponent.InitializeLordPartyProperties` 对非玩家 Clan Party 会按 Clan 默认PartyTemplate填兵；PlayerClan新建 Party走 `InitializeMobilePartyAtPosition` 分支，不复制NPC DefaultPartyTemplate，初始化对象明确添加的只有 Leader 和约 15–30 Grain。因而“创建一个家族Party”本身不保证得到可自行战斗/收税的满编部队；士兵/物资如何补齐需走Party管理和F11渠道。

同一 Clan Parties VM 的既有Party卡片有三个独立操作族，而非一个通用“管理Party”：

- **更换Leader**（`ACT-F06-02`）：仅`ClanPartyType.Member/Caravan`显示按钮；候选需通过`FactionHelper.IsMainClanMemberAvailableForPartyLeaderChange`等条件。Done Inquiry确认后，旧Leader用DelayedTeleport回MainParty、新Leader去目标Party；若目标Hero低于最低Party Gold，玩家补足差额，界面提示预计旅行时间。
- **Disband**（`ACT-F06-03`）：同一Leader selection popup包含`Disband Party`候选，但只有地图操作可用且目标不是MainParty/Garrison/Militia/已解散/战斗或围城Party时可选。确认后旧Leader被移出并成为Fugitive，再由`DisbandPartyAction.StartDisband`标记处理；派对可能等待、移动到Settlement后再合并/销毁，不是点击后Roster立即消失。此为Clan移动Party解散，不是`ACT-F05-02`Kingdom Army解散。
- **Party Objective**（`ACT-F06-04`）：仅非Clan leader领导的、非Caravan且未Disband的Party可在卡片选择Neutral/Defensive/Aggressive。Selector按`SetPartyObjective`写`MobileParty.Objective`；`AiMilitaryBehavior`和`DefaultTargetScoreCalculatingModel`会据此改变防守/攻城/劫掠目标的权重及追敌倾向，它不是指定某个单一地图目标。

Garrison卡片还单独显示Settlement的`Auto Recruitment`开关；虽然它出现在同一个Clan Parties VM，写入的是`Town.GarrisonAutoRecruitmentIsEnabled`并影响未来聚落每日自动招募，因此归D07 `ACT-D07-03`，不并进Clan War Party Objective，也不新增F06 ACT。自动招募的志愿者/费用/食物/上限条件见D07。

Leader候选Inquiry在选普通Hero与选Disband之间切换；弹窗组件相同但最终状态不同，故分列ACT。Parties列表中的Caravan只有Leader/Disband适用项；Garrison不可使用此ChangeLeader UI。Role选择另映射H06，不在此重复计算。

### 对照 AI Clan War Party 与 Chronicle 覆盖

NPC Party 的 `LordPartyComponent` 由角色/clan war party 系统持有，模板生成和AI补兵链与上面的玩家新队伍入口不同。AI PartyThink选择 Army/战术目标是 F02/F05，不应把 WarPartyComponent 入册/生成等同一个长程自主目标。Clan改王国、领地变化、Hero死亡或Party被销毁，会改变 WarPartyComponent 名册、控制关系或Army成员，需要按各Event路径继续追踪。

Chronicle主队Snapshot有Party摘要，但没有Clan Owned WarPartyComponent的全量 roster、PartyLimit使用情况、各队Leader/Home/工资/自动行为、创建草稿候选或新Party初始化后状态；Protocol没有 `CreateNewClanMobileParty`/队伍编成/编队补兵命令。当前静态证据不代表Agent可自主管理新的家族移动部队。

证据：当前 `TaleWorlds.CampaignSystem.dll` 的 `WarPartyComponent`、`Clan.WarPartyLimit/WarPartyComponents/CurrentTotalStrength`、`DefaultClanTierModel`、`LordPartyComponent`、`MobilePartyHelper.CreateNewClanMobileParty`、`ClanFinanceModel.PartyGoldLowerThreshold`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `ClanPartiesVM`/`ClanPartyItemVM`；Chronicle `AgentObserver.cs`。源码版本 v1.4.8.119303；没有实机点击Create New Party、扣款、检查新party roster或返回MainParty的UI验收。

未知项：AI NPC WarParty生成/死亡/损失后的完整补充频率和玩家Party的后续兵员增长策略；PlayerClan新Party在初始MainParty、城镇、队伍外等不同Hero位置下的所有位置/物资前后态；Party management中角色、兵种、伤兵、物品、工资上限和Disband各按钮的视觉输入/提交顺序；WarPartyLimit不同Tier、Clan类型与NPC衡量的实际差异；队伍被俘、改Faction、Leader死亡对Clan roster和军团存档恢复的完整结果。

## F07 战争状态下的聚落目标与军事行动候选

### 从战争关系到地图目标

War/Peace stance与宣战前置已在 C03 研究；当战争状态已存在时，F 域的 `AiMilitaryBehavior` 才会给Lord Party或Army Leader计算本地战略军事行动候选。它通常从派系 `FactionsAtWarWith` 的地图聚落筛选目标，再依ArmyType转换为 `RaidSettlement`、`BesiegeSettlement` 或 `DefendSettlement` 候选；NPC 的 Party/Army 后续行为由 F02 Think 分数体系决定，不是玩家直接下达一张全图战争路线。

已追到的候选边界：

- **Defender**：主要指向当前可用的 Settlement.LastAttackerParty 相关防守目标；别的本方/Army已承诺保卫的力量会参与本地防守强度和重复目标考虑。
- **Raider**：以Normal状态村庄为目标；BeingRaided/Looted、已有 MapEvent 等状态会拒绝或显著改变候选。现有 Army/准备集合的某些分支不能再当作普通独立掠村目标。
- **Besieger**：以 Fortification 为目标，跳过己方/无效围城、已经由敌方其他行动处理或相关 MapEvent/SiegeEvent 不兼容的聚落。仅有城镇/城堡是敌人的并不足以让所有 Party 都立即出征。

War目标在完成的 war decision之外仍受 `AiMilitaryBehavior` 的 Party type、ArmyType、目标状态、局部力量、玩家作弊/事件回避标志和可用导航影响。定居点所有权变化、宣战/议和、Clan更换 Kingdom会检查/废止针对变更聚落/派系的失效移动目标，再触发AI重想；这会让同一战争中的路线随着目标归属/地图事件变化而改变。

### 目标分数与行动可行性

军事候选分不是单按“最近敌城”选。`AiMilitaryBehavior` 至少将 `TargetScoreCalculatingModel.GetTargetScoreForFaction` 的目标价值、距离/港口导航分、Army Cohesion、Party SizeScore、食物可持续天数、PartyObjective（Aggressive/Defensive）等相乘/修正后送入 F02 候选列表。Besieger 对相邻敌我 Fortification 拓扑与海陆导航算距离分；Defender考虑LastAttacker与本方援防力量；Raid考虑村庄安全/派系/当前事件。粮食低于 Raider/Siege Model threshold 时可不给目标或大幅降低分数，军团的多个成员可按平均可食天数计算。

Army Leader 进行防守/掠村/围城类候选时可以使用 `WillGatherArmy` 和 PossibleArmyMembersStrength；满足 ArmyManagementModel 条件后可发出“召集军团再进攻”的候选。Objective、Army Cohesion、Party SizeRatio和是否正在 disbanding 会继续影响该目标分数。最终行动经 F02 的Think循环接受后才由 `SetPartyAiAction` 实施；分数不是保证它一定采取行动的概率，也不是绝对目标队列。

### 玩家对目标选择的影响

玩家能通过 C03 的外交宣战/议和、选举/政策/领地、加入或离开 Kingdom、攻守战果与聚落易主等原版系统，改变AI军事筛选使用的战争关系、Objective、Settlement owner、敌友、力量和粮食环境；玩家并没有一个直接菜单替NPC选择“下一个攻城目标”的原版通用动作。主动加入/指挥 Army、帮助战斗、围城或掠夺会进入不同 F/G 入口，不能视为单纯修改 AI Objective。

Chronicle目前可以为 MainParty设置有限地图目标，并能观察附近可见 Party的摘要；不会读取 Kingdom的 `FactionsAtWarWith` 军事候选、NPC Army Objectives、目标分数、WarParties分配、敌我Strength估算明细、合法行动原因，也无NPC战争目标/攻城战略控制接口。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `AiMilitaryBehavior`、`DefaultTargetScoreCalculatingModel`、`AiPartyThinkBehavior`、`DefaultArmyManagementCalculationModel`、`ChangeOwnerOfSettlementAction`及 War/Peace handlers；Chronicle `AgentObserver.cs`/`AgentProtocol.cs`与 MAINLINE 主队 action contracts。v1.4.8.119303 源码证据，未运行战争目标AI的周期统计或验证实机判定排序。

未知项：`DefaultTargetScoreCalculatingModel`在不同版本/个性/危机下完整权重与随机数；进攻目标估值与和平战场边界变化下目标重算延迟；Army Leader、Attached Party、族长和Kingdom's AI role在军事候选生成中的优先级；AI何时从单队转Army/何时放弃目标的全部阈值组合；战争目标是否对玩家主动不可见信息进行遮蔽或特殊保证。

## F08 围城周期、攻防与围城后果

### SiegeEvent 对象与 Campaign 周期

`SiegeEvent` 连接 BesiegedSettlement 与 BesiegerCamp，后者保存围攻方阵营、参加 Party、战场人数、战术和器械容器；Settlement/Defender side 持有另一个 SiegeEventSide。壁段受损比例、围城准备时间/开始时间、Blockade、被围城/围攻方人数、各方 siege engine construction progress、预制/部署的 siege engines 和炮击目标分别是数据，不等于一个“攻城进度百分比”。

围城是在地图行动/对象抵达后形成的 Campaign 战略状态，并由 SiegeEventTick/`SiegeEventCampaignBehavior` 按时间处理。模型控制器械建造速度、墙/武器损坏、炮击命中与伤亡；派对进出、和平、其他军团和军团目标会改变 BesiegerCamp 参与名单或使 Siege Event 结束。城墙基础属性见 D03；实际 Mission的兵力编组/器械操作另见 G03/G08。

### 玩家可进入的 Siege menu 与 Mission

处于玩家攻/守 SiegeEvent 上下文时，原版 `menu_siege_strategies` 是 WaitGameMenu；从 menu option 进入时钟自然推进直到 assault或其他事件，点 Lead an assault 会进入原生 `assault_town`/PlayerSiege Mission，Send troops 调用模拟/坐镇路径；防守方在条件允许时可以 Request a parley、Leave或Leave Army。没有可用 siege engine、Player wounded、玩家不在 siege command等情况会令 Lead Assault disabled 或给出说明。离开/终止 siege 另有确认菜单，且可失去/销毁器械。

在 Siege preparation 与 Map Event之间分层：`PlayerSiege.StartSiegePreparation` / `StartPlayerSiege`分别处理初始化/玩家攻守进入，`StartSiegeMission`建立真实围城战场。Camp 战略菜单、地图“在围城中”、实时攻城 Mission和已经结束的战后决策不可互相替代。Simulation/Send Troops 的 outcomes由MapEvent/战斗结算处理，真实 Mission则进入 Formation、Siege mission tactics和结束条件。

### 结束、战后决策与经济影响

Siege之后会根据 attacking/defending outcome、capturer与 MapEvent contributions 进入 `SiegeAftermathCampaignBehavior`。玩家在攻陷 fortification 后可在条件开放时选择 Continue/Devastate/Pillage/Show Mercy等，不同后果分别改 Settlement Prosperity/Projects/Loyalty/Notables/Clan Relation/Army gold/Influence等；AI胜负则通过 `DefaultSiegeAftermathModel`/战后 behavior 自动决定。最终 settlement ownership变化由 `ChangeOwnerOfSettlementAction` 统一落地及通知（D10）；围城战损/士兵伤亡/驻军去向受 F10/G09、F12/F10等Battle/Captivity链影响，不应和after-action独立菜单选择合并成一个效果。

围城不仅是 siege progress：Attacker food、Defender garrison food、围城/村庄受害、Settlement战损、阵营与Army支援、战后是否占领等会并行变化。点击“接到 siege menu”、“lead assault、battle完成、战后选项完成、改变所有权”是有条件的多个阶段，不是一个按钮。

### Chronicle 当前观察/动作覆盖

`AgentObserver` 附近Settlement仅输出 `underSiege` Boolean；主party context与battleSimulation仅显示少量battle状态，不读 SiegeEvent side、BesiegerCamp、谁被围、Siege strategy、blockade、food/engine/wall/assault readiness、战后Aftermath options或多队贡献。Protocol可对当前原生Campaign GameMenu执行已启用Option的menuSelect，也有部分Autobattle和战后loot适配；没有 siege-setup/engine placement/strategy/assault Mission通用Agent动作。本地 `menuSelect`完成只能说明本体菜单option consequence被调用，不代表3D攻城或整个防守/战后闭环已完成。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `SiegeEvent`、`BesiegerCamp`、`PlayerSiege`、`SiegeEventCampaignBehavior`、`SiegeAftermathCampaignBehavior`、`SiegeAftermathAction`、`DefaultSiegeEventModel`/`DefaultSiegeAftermathModel`；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`及 MAINLINE `autoresolve`/`retreat` contracts。源码版本 v1.4.8.119303，未启动攻城、战斗或战后Mission验证。

未知项：围城准备到 `menu_siege_strategies` 的完整玩家地图点击/状态链和真实时钟模式；攻城武器部署/构建UI和引擎可见反馈对应的所有字段；Lead Assault/Send Troops在玩家作为 Army leader、附属队伍、单Party时的具体进入路线及伤亡差异；各个Aftermath选项的全部公式和战斗贡献分配；战后state resets/故障恢复与保存加载跨系统顺序。

## F09 掠夺、营地防守与领土受侵

### Military Raid 与 Village hostile actions

AI `RaidSettlement`、玩家强征 supplies/volunteers 和玩家劫掠村庄不是一个统一操作。AI进行战役地图掠夺时，Raid会创建 `MapEvent.BattleTypes.Raid` 并挂上专用 `RaidEventComponent`，在该事件中对 Village `SettlementHitPoints` 逐tick造成损害。默认 `RaidModel.CalculateHitDamage` 大致按 `(sqrt(attacker troop count)+5)/900 × CampaignTime.DeltaTime hours` 计算损害，并可受参与 Raider Perk 影响。

RaidEvent开始将 VillageState 置为 BeingRaided、派 Village militia 到防守方；战斗被结束时若聚落伤害归零则转换为 Looted，否则回到 Normal，发 `RaidCompleted` 并结束 MapEvent。这不是常规双侧野战即时损害：settlement hitpoints、村庄状态、掉落商品和在场/参与 party 都与普通 FieldBattle MapEvent 不同。玩家从菜单主动掠村或强征志愿兵/补给使用另外的 GameMenu/MapEventContext 链，D04已列明入口和 Village 被掠状态，不能将 player hostile action 与AI常规 `RaidSettlement` 目标选择混写。

Raid component 在战斗进度/胜负路径中依村庄产物、RaidDamage和 loot 随机模型生成物品与资金/经验结果；破坏村庄货物、绑村安全、村民货物在途商队的后果分别见 D04/E03。若攻击者被打散/撤退，MapEvent以相应撤退/战后逻辑 finalize；之后的失去 troop、俘虏/赎金、物品转移属于 F10/F12，不在 raid component一处全部处理。

### 聚落与 Party 防守

防守不是只有军队在Settlement里等敌人：城堡/城镇有 Garrison、Militia与附近WarParty/Army等防御来源；村庄允许其 militia及同派系单位参与Raid defending party，具体FIEF/settlement类型、地图事件类型会筛选防守对象（D07/G相关）。NPC防守Party目标源和援防权重由F07 `AiMilitaryBehavior`/TargetScore模型选择。

村民Party在SiegeEvent开始时会停止地图移动；Villager raid出击和村庄 Hostile action的保护/警告另有专用CampaignBehavior。具体遭遇是否打断Raid、玩家MainParty是attack/defend、主人是否自动加入等，需结合 `PlayerEncounter`、`MapEvent` 和Village menu conditions分类，不能凭 map 图标/IsUnderRaid状态直接假定进入战斗了。

### 结果回调、观察与 Chronicle覆盖

`RaidEventComponent` 的RaidCompleted/MapEventEnded事件，聚落 `SettlementHitPoints`、VillageState转换、Loot roster和关系/日志触发时机不同；AI低频意图与玩家菜单逐项确认亦不同。原版代码将这些结果拆到 `RaidEventComponent`、`VillageHostileActionCampaignBehavior`、`MapEvent`、Ransom/Combat rewards等若干层。

Chronicle附近Settlement摘要没有 `VillageState`、`SettlementHitPoints`、RaidDamage、粮食/生产损失或Looted状态；Party摘要不含 `MapEvent.BattleTypes`、双方部队构成和raid结算进度。现有 Protocol可在当前Campaign菜单选择可用option，也支持部分AutoResolve和战后操作，但没有主动把任意 VillageParty转换成RaidMapEvent、编排Raid战斗或核验攻击村庄后果的通用指令。

证据：本机 v1.4.8.119303 `DefaultRaidModel`、`RaidEventComponent.CreateRaidEvent/OnBeforeFinalize/FinalizeComponent`、`MapEvent`、`Village.GetDefenderParties`、`VillageHostileActionCampaignBehavior`、Chronicle `AgentObserver.cs`、`AgentProtocol.cs`；村庄访问前置与经济后果见 D04/E03。静态源码证据，没有从玩家菜单运行劫掠、强征或驻军守卫回归。

未知项：不同目标与Player/AI参与时MapEvent何时建立/结束、RaidDamage战役tick和胜利结果全分支；村庄防守联盟在围城、Army、叛乱、非敌对派系下的完整Party候选；强征vs Raid状态值、钱物/声望/关系副作用差异和Recovery时间；D09实体村庄Mission/场景交互与战役Raid抽象的具体切换条件。

## F10 Campaign MapEvent 与坐镇战斗模拟

### MapEvent 对象和双方 Party

Campaign 地图上的遭遇/战斗由 `MapEvent` 管理；它区分 `BattleTypes`（FieldBattle、Raid、ForceSupplies/Volunteers、Siege、SallyOut、SiegeOutside、Hideout、Blockade等），用 `MapEventSide`/`MapEventParty` 保存攻守侧、参战Party、Roster、Round casualty、伤兵、击杀/溃逃/参与贡献等。Settlement/raid/siege等MapEventComponent会把不同类型事件的目标状态和结算副作用接入同一 MapEvent框架；Field Battle不等于每一种MapEvent。

一个 party开始战斗/遭遇后，还可以有其他Party在符合导航、派系、任务/战争等条件时加入其中。`MapEventSide` 按总战力、成员/健康队伍、守备器械/船只、贡献等管理本方实际参与，故“地图附近势力”“当前MapEvent involved Parties”“UI看到的实时 Mission troops”不一定是一套名单。

### 坐镇模拟与真实 Mission 区别

玩家开始遭遇后，原版可以把 `FlattenedTroopRoster` 的可用参战兵种交给 `BattleSimulation`。BattleSimulation 初始化或复用 `PlayerEncounter.Battle`，标记 player simulation，并按 CombatSimulationModel 为双方运行模拟 Tick/Round；胜负由 MapEvent battle state/Simulation continuation确定。它使用战斗模型、Army/Party composition、士气、领袖Perk和地形/攻守加成，不是只按总战力/人数比直接得胜。

模拟状态是 Play、FastForward、Skip、Pause。`Tick(dt)` 中 FastForward 把simulation delta乘6，Pause把simulation dt设0；Skip在当前上下文同步反复调用模拟直至 `MapEvent.HasWinner`。这些是战斗模拟自己的进度控制，不是打开/关闭 Campaign TimeControlMode，也不等同于真实3D Mission暂停或快进。真实作战由 `PlayerEncounter.StartAttackMission` 与 Mission/Formation/战术Order链完成；F10只盘点地图抽象战斗，真实3D作战细节留 G 类。

模拟结束后 UI通常返回原生 Encounter result flow；最终 `MapEvent` 结果计算/提交伤亡、胜者/撤退、俘虏捕获、战利品/失去金币、Hero死亡/昏迷、Renown/Influence/Morale、Party 状态和地图位置变化。若玩家伤亡/结束后仍有可领取物品，则需要通过后续Party/Inventory屏幕完成对应领取；结果界面显示、Party roster变化和世界状态提交是多个阶段，不应以“skip 调用成功”替代奖励/恢复验证。

`BattleSimulation.OnPlayerRetreat` 会提交部分 XP 后返回遭遇流程，和 `BattleMission TryExit/RetreatMission`、玩家从地图Party撤退、战败被俘是不同的玩家入口/结果链；真实 Mission与Simulation的损伤/撤退/奖励处理不能互相复制。

### Chronicle 当前处理与证据

Observer 在BattleSimulation活动时只提供 finished/retreated/battleState等少量模拟状态，Encounter section输出当前参与方基本身份/loot count；Protocol中battlePause/battleSkip、完成和战后清理入口需以 MAINLINE的精确 actions契约为准。现有测试夹具可以为目标窗口注入明确的battle数据，但这不证明任意自然战斗、所有MapEvent类型和各种Party援军的Autonomous战斗处理已完整支持。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `BattleSimulation`、`PlayerEncounter`、`MapEvent`、`MapEventSide/Party`、`DefaultCombatSimulationModel`、Raid/Siege等EventComponents；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`和现有 MAINLINE 战后/模拟契约。版本 v1.4.8.119303；本节没有启动战斗 Mission或修改存档运行结果。

未知项：所有Encounter prompt到坐镇Simulation/Join Battle UI入口和按键焦点；Mission Battle与MapEvent simulation各技能/XP/伤亡/战利品差异矩阵；每一MapEvent Component结果回执字段、失效/中断与重新载入边缘条件；援军Party何时加入/退出的具体距离/同盟门禁；Pause/Skip Simulation与Campaign clock各平台/当前时间模式的所有精确边界验证。

## F11 部队补充、训练、治疗与流失

### Troop XP 与自动升级

Party troop progression由 `TroopRoster` 的成员计数/伤员数/XP与 `CharacterObject.UpgradeTargets` 兵种树共同表示。`MobilePartyTrainingBehavior` 监听DailyTickParty给普通 troop 加模型计算的 daily XP；Battle/MapEvent参与可在战后 commit另外的共享XP。玩家升级不等于这种后台 XP 累积。

`PartyUpgraderCampaignBehavior` 在每日 Party tick 和 MapEvent结束时检查可升级 troop；默认升级行为显式忽略 `PartyBase.MainParty`，NPC Party可按模型权重/首领偏好在多个升级分支中选一个。升级前可能检查 XP成本、Gold成本、队伍工资上限、所需 ItemCategory物品、Perk条件及Bandit来源限制；真正执行时从旧 roster扣人数/XP，加入目标兵种，并向Party Owner或Leader扣Gold/授予军需/Leadership相关技能经验。玩家通过Party Screen的升级交互是另一入口，具体操作是否即时提交、无法升级时的角色/tooltip提示未做当前版本视觉验证。Recruitment与加人入口见D09及当前 Protocol Recruitment Adapter；Garrison Volunteer自动招募见D07，战后Captured Prisoner吸收则见F12。

### 日常训练与熟练度边界

默认 `PartyTrainingModel` 可按NPC Lord party是否是主领主/Army、部队等级与领导Perk等累计日常 XP；技能效果还可能按当前Party角色/行军或驻扎/海上状态变化。MainParty不应直接按NPC每日经验规则假设自动升级；玩家Roster成长来自招兵、战斗技能奖励、Party XP结果与主动PartyScreen升级等不同入口。

### 治疗、伤病与俘虏健康

`PartyHealCampaignBehavior` 将伤兵/英雄治疗作为 PartyBase的队员与 Prisoner 两套 roster单独处理，溢出Healing rate 会随下次周期tick累加。其监听每日/每小时/每QuarterDaily Party tick与 MapEvent结束：MainParty有每小时治疗调用，其他Party约每QuarterDaily tick，Settlement party另有每日；`PartyHealingModel`决定治疗或因缺粮/伤病环境发生额外血量变化。Hero命中点恢复和Regular Troop伤员复原不是一种数量转换，伤兵仍留在 MemberRoster wounded count，除非被其他治疗/战后规则治愈或死亡。

俘虏治疗独立调用 Prisoner伤兵/英雄恢复率并维护各自溢出缓存；俘虏逃跑/处决/兑换则见F12。不同场景/监狱/garrison和Mission时的治疗权限、正确玩家待机入口及玩家能看到的预估治疗项未在F11运行验证。

### 逃兵、限额与资源不足

`DesertionCampaignBehavior` 每日仅检查活动、在陆上、非Disbanding、非MapEvent且为Lord/Caravan/Garrison等符合条件、且仍有Regular troop的Party。模型按低Morale、工资限额超支、超PartySizeLimit等算要逃兵数量/选择Troop；Garrison对欠薪还有额外流失分支。实际移除从MemberRoster执行并发TroopsDeserted；队伍成员归零则销毁Party。故“目前人数小于PartySizeLimit”并不代表永不减员，缺粮/欠薪/士气是持续限制。

食物/工资背景及玩家Clan每日付款入口分别见E06/E07；适用于Battle/Season/Army的士兵补充或逃兵结算还由相关WarParty/Army/Settlement Models调整。Roster改变的结果通常跨越上方XP、Food、Wage、Heal、Desertion等循环产生反馈。

### Chronicle当前适配与缺口

Observer输出主队成员/健康/伤兵/俘虏总数与Party SizeLimit，不输出每个兵种、UpgradeXP/UpgradeTargets、兵种技能/工资、招募上限/报名槽、逐兵伤病状态或模型推算逃兵风险。Protocol存在RecruitmentVM专用的一人招募流程和战后部分Party处理，但没有通用PartyScreen兵种转移、升级候选/费用核验、医疗治理或Roster rollback/retry动作；单兵总数变化不能替代“升级成功/伤病恢复/内部交换”细节。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `PartyUpgraderCampaignBehavior`、`MobilePartyTrainingBehavior`、`DefaultPartyTrainingModel`、`DefaultPartyTroopUpgradeModel`、`PartyHealCampaignBehavior`、`DefaultPartyHealingModel`、`DesertionCampaignBehavior`、`DefaultPartyDesertionModel`；Chronicle `AgentObserver.cs`/`AgentProtocol.cs`。源码版本 v1.4.8.119303，没有实机触发训练长期XP、治疗周期、Troop升级或欠薪逃兵。

未知项：Player PartyScreen里升级/治疗/人头不足等各操作结果和取消事务；所有招募渠道的出现频率、市场志愿者/家族同伴限额与失败后补充；Wounded Troop的动态疗效和长周期差异；AI party对 troop roster补充、随机晋升、伤员治疗和Army成员凋零的完整行为策略；相关 mods替换PartyUpgrade/Training/Healing/Desertion Model时的冲突。

## F12 Hero 俘虏、管理与释放

本节保留既有俘虏子系统研究。俘虏转移涉及 Factions、战斗、菜单/Party UI 和关系/叙事，相关的关系后果与日志消费者另见 B/C/J 类研究。

### 玩家入口、状态观察与时间边界

本体 `PartyVM` 暴露主队/对方的 Prisoner 列表、俘虏容量警告、转移全部俘虏/解雇等命令，以及在适用模式出现的俘虏招募弹窗；战后则进入 F10 记录的 PartyState/PartyScreen 流程。俘虏英雄的 Barter/对话释放属于另一条交互，不等同于普通兵俘转移。各操作受 PartyScreen 模式、Roster 容量、可转移对象和行动上下文限制。这里确认的是源码中的玩家界面模型能力；从地图按钮到不同 PartyScreen/酒馆/地牢/对话的每一种可视入口与确认流程尚未逐项实测，不将其压成一个“管理俘虏”按钮。

Chronicle 主队观察输出俘虏总数，当前 PartyState 观察分别序列化左右双方成员与 Prisoner roster。`partyTakeAll` 仅允许战后 Loot 模式并通过原生 PartyScreen handler 的 Done 提交；它不是通用俘虏交易、招募或释放动作。现有协议没有独立的普通俘虏转移/卖出/招募/英雄释放命令。俘虏Roster读写本身不显式推进 Campaign 时间；赎金评估、逃脱等是由后续日常/小时 Campaign 行为驱动，进入不同 Wait/Encounter/PartyScreen 时是否继续运行按其宿主 GameState 的时钟规则决定，F12没有把它们另行快进。

战后普通兵俘虏另有明确玩家处置点：`PlayerEncounter`先以`DoFreeOrCapturePrisonerHeroes`把仍被敌方关押的Hero移出待分配成员Roster，使用`FreeOrCapturePrisonerHero`对话处理；之后若存在普通成员或俘虏Roster，`DoLootMembersAndPrisonersOfParty`打开`PartyScreenHelper.OpenScreenAsLoot`的`Aftermath` PartyScreen。`DefaultDoneHandler`按本次Roster差异分别将玩家接收的俘虏交给`TakePrisonerAction.ApplyByTakenFromPartyScreen`，并将玩家放弃的俘虏交给`EndCaptivityAction.ApplyByReleasedByChoice`，Encounter随后清理临时战后Roster。此战后普通兵俘分配记为`ACT-F12-11`，不与日常普通兵俘招募`ACT-H04-02`或Hero俘虏对话合并。自然战斗中不同MapEvent/胜负条件是否始终到达该界面、容量反馈和取消后的完整迁移仍待运行核验。

玩家确认，战后可逐项挑选俘虏，不必全收；应按当前目标决定接收哪些人。玩家同时指出俘虏会拖慢队伍，超出容量时还会逃跑。故EYC等长程目标不能把`Take All`当作固定策略：每次都要比较当前目标进度、可用俘虏、当前容量/超限后果与队伍后续移动需要，再提交原版Roster选择；超限确认必须基于当时UI/Native状态重新决策。该段是玩家经验确认，具体移动减速幅度、逃跑时点和概率仍以1.4.8源码/运行证据为准，不能从本次回答推定数值。

`partyTakeAll`只在Loot模式走本体handler；这是战后接收Roster的现有Harness适配，不代表常规PartyScreen俘虏招募、日常容器转移或Hero处置已完整支持。

普通主队俘虏出售是另一种原生Roster事务：Town Backstreet“选择要卖的俘虏”打开Ransom PartyScreen，逐人由`PartyCharacterVM.ExecuteTransferSingle`暂存到买方左侧，Done才通过`IPartyScreenPrisonHandler`提交`SellPrisonersAction`。用户确认玩家可按目标选择其中一部分；俘虏降低地图队伍速度，超出俘虏上限后会逃跑，因此不应把“卖出/接收全部”写成通用Agent策略。Chronicle新增的Ransom适配和EYC Gold sale目录仅把当前Native右侧可转移行逐名开放，并要求用当前非零金币草稿/Done状态核验；2026-10-29源代码及AgentHost离线契约测试通过，但Bannerlord客户端仍加载旧DLL，本次尚无新适配的运行时提交证据。具体移速变化、逃跑时间/数量、卖出Hero的关系及技能影响未在本次确认，不外推用户提供的规则。

### 被俘

`TakePrisonerAction` 主要执行：

- 从原队伍成员列表移除 Hero；
- 如果 Hero 是队长，移除队长身份；
- 记录 `CaptivityStartTime`；
- 将 Hero 状态改为 `Prisoner`；
- 加入捕获方 Party 的 PrisonRoster；
- 如果是玩家，进入 `PlayerCaptivity`；
- 清除 Hero 的 StayingInSettlement；
- 触发 `HeroPrisonerTaken`。

该动作直接处理队伍归属和人物状态，不在动作本身修改个人关系。

### 俘虏持有

Hero 俘虏可以存在于：

- 移动队伍；
- 城镇、城堡等聚落地牢；
- 驻军；
- 战争队伍；
- 商队等拥有 Party 的对象。

俘虏可以通过 `TransferPrisonerAction` 在 Party 之间转移。转移会更新 PrisonRoster，并可能触发聚落俘虏变化事件。

### 释放类型

`EndCaptivityAction` 提供以下主要结束路径：

- `Ransom`：赎金释放；
- `ReleasedAfterPeace`：和平后释放；
- `ReleasedAfterBattle`：战后释放；
- `ReleasedAfterEscape`：逃脱；
- `ReleasedByChoice`：玩家或 Party 主动释放；
- `ReleasedByCompensation`：补偿释放；
- `Death`：死亡结束俘虏状态。

释放动作会：

- 从 PrisonRoster 移除 Hero；
- 改变 Hero 状态；
- 对部分同伴生成 Fugitive 状态；
- 将 Hero 放回当前聚落或释放位置；
- 触发 `HeroPrisonerReleased`。

释放动作本身不统一处理个人关系后果。

### 监狱突围与营救Hero

玩家可从`town_keep_dungeon`、`castle_dungeon`或`town_enemy_town_keep`选择`Stage a prison break`。`DefaultPrisonBreakModel.CanPlayerStagePrisonBreak`要求Fortification、存在Hero prisoner，且聚落Faction与玩家Clan不属同Faction；菜单还会在MainHero受伤时禁用。冷却期内该入口转入警戒提示。

选项启动后，`PrisonBreakCampaignBehavior`把Settlement与Garrison prisoners合并成目标清单，仅保留Hero：与玩家Faction敌对者禁用，金币不足者显示预计Bribe cost并禁用。费用由`PrisonBreakModel.GetPrisonBreakStartCost`按Hero赎金价值、聚落Security和玩家Roguery计算。选中目标后Start调用`GiveGoldAction`扣款、写入该聚落7日冷却并打开`PrisonBreakMission`；目标Inquiry记为`OBS-F12-01`，付费启动记`ACT-F12-13`。

这不是直接调用救援结果：Mission分潜行接近囚犯与警报后护送逃离两段。关押者附近互动按Use键；第一阶段在守卫未警觉时互动会切换到第二阶段、让囚犯跟随并触发守卫警戒/追捕；`StealthFailCounterMissionLogic`记录潜行失败。Mission结束时主角昏迷会被留作Settlement俘虏；囚犯Agent不可用则救援失败/可能重伤死亡；双方仍active且未触发失败才进入救援成功菜单。

成功后离开Settlement并与囚犯Hero对话，最终经`EndCaptivityAction.ApplyByEscape`释放，默认`PrisonBreakModel` relation reward为+15并给予Roguery XP；若目标是玩家Companion，专属对话分支还会将Hero置为Active并加入MainParty。成功后的状态提交单列为`ACT-F12-14`，与付费启动/Mission阶段分开。实际潜入、近身交互、护送和战斗控制由G03 Mission身体承载，Chronicle当前没有3D控制动作。Inquiry和Mission UI视觉、Campaign/Scene时钟、失败分支保存恢复未运行核验。

被救Hero在Mission中的跟随控制是另一实际提交：`PrisonBreakMissionController.OnAgentInteraction`仅在MainAgent作用于目标prisoner、且所有存活守卫未Alarmed时响应。第一次交互会生成第二阶段守卫、切至第二阶段并调用`SwitchPrisonerFollowingState`；之后再次交互切换跟随/停止跟随。该Action仅改变Mission内护送状态，不能单凭“开始跟随”推断Hero已脱离囚禁；最后仍需成功结束Mission并经过上段的`ACT-F12-14`。此交互单列`ACT-F12-15`，与Campaign释放和进入突围Mission分开。

### 赎金与 Barter 转移

玩家要通过普通领主Barter与对方谈判，BarterVM是否出现Hero俘虏条款由`BarterablesRequested`监听者按双方Party/Faction状态动态构造；Conversation/Barter入口和通用议价状态见 [E10](../E/EconomyAndTrade.md#e10-barter-交换谈判)，此处只记录俘虏状态变化。战后PartyScreen、主角被俘GameMenu与对话Barter不是同一入口。

### 赎金

`RansomOfferCampaignBehavior` 会按日评估是否提出赎金，受以下因素影响：

- 俘虏所属 Clan；
- 捕获方 Clan；
- Hero 是否为领袖；
- 赎金价值；
- 赎金支付者金币；
- 之前是否拒绝过赎金；
- 随机机会率。

`SetPrisonerFreeBarterable` 使用赎金模型计算价值，并根据俘虏时间提高部分家族方价值。

玩家确认：主角收到赎金提议时，游戏界面明确显示赎金金额，并提供接受/拒绝选项。Harness Native运行也曾观察到 `mno_captivity_end_ransom_accept` 与拒绝选项，并分别核验支付释放与拒绝后继续被俘；详见 `DEVELOPMENT.md` 的 `CaptivityOutcome` 记录。此确认只描述该赎金提议界面，不意味着任何被俘存档都会立即出现报价；Host仍须以当前Native菜单/启用选项与当前报价为准。

本机1.4.8 `PlayerCaptivityCampaignBehavior.AddGameMenus`还注册了一组被俘期间的原版剧情菜单。它们不是普通战斗菜单；玩家只能点击当前菜单里真实出现、已启用的选项。W7-O从已被俘状态出发，所以只把这些原版菜单的当前选项作为可选动作，后验仍以Native状态为准：

| Native菜单 | 可见选项 | 原版回调效果 |
|---|---|---|
| `menu_captivity_end_no_more_enemies` | `mno_continue`（Continue） | `EndCaptivityAction.ApplyByEscape(Hero.MainHero)` |
| `menu_captivity_end_by_ally_party_saved` | `mno_continue` | `EndCaptivityAction.ApplyByReleasedByCompensation(Hero.MainHero)` |
| `menu_captivity_end_by_party_removed` | `mno_continue` | Captor已无领袖且无成员时按战后释放，否则按逃脱释放 |
| `menu_captivity_end_wilderness_escape`、`menu_escape_captivity_during_battle`、`menu_captivity_end_prison_escape` | `mno_continue` | `EndCaptivityAction.ApplyByEscape(Hero.MainHero)` |
| `menu_released_after_battle`、`menu_captivity_end_exchanged_with_prisoner` | `mno_continue` | 保护玩家侧、设置Captor暂不攻击并退出当前结果菜单；是否已脱俘由其前置原版事件和新鲜Native状态决定 |
| `menu_captivity_end_propose_ransom_wilderness`、`menu_captivity_end_propose_ransom_in_prison` | `mno_captivity_end_ransom_accept` / `captivity_end_ransom_deny` | 接受时按当前Native金额扣金并执行`ApplyByRansom`；拒绝时退出到原Captivity等待 |
| `menu_captivity_transfer_to_town` | `mno_continue` | 退出剧情菜单、激活`settlement_wait`并恢复`LastTimeControlMode`；此处可能仍被俘且原版恢复时钟是菜单回调副作用 |
| `menu_captivity_castle_remain` | `mno_continue` | 退出结果页回到此前地牢等待，不等于已脱俘 |

Wait菜单本身 (`prisoner_wait`/`settlement_wait`) 另由 `PlayerTownVisitCampaignBehavior` 注册；其`StartWait/EndWait`和`PlayerCaptivity.Update(dt)`约束见本节下文。`menuSelect`在Chronicle中必须保留当前menuId/optionId，并受当前Native available+enabled门控；不直接调用上述Captivity API。源码覆盖的是已安装Native/System程序集静态回调；哪些分支会在本次存档实际出现、Continue后是否自由、队伍是否恢复，都不能从注册表推断，必须按实际Native状态验收。真实模型已复现从`prisoner_wait`自然等待转为`menu_captivity_end_wilderness_escape`且当前只有`mno_continue`启用；画面与Native状态证据见 `TestResults/20261018-121747/AgentHostCampaignRun-01/Temp/LiveModelLoopResult.json` 与 `TestResults/20261018-121747/AgentHostCampaignRun-01/LiveModelWindow-contact.jpg`，该次因原菜单白名单不完整而安全停止，未点击菜单、未运行Battle、源存档未变。

W7-O真实闭环通过：`TestResults/20261018-135026`使用FreeLLMAPI `auto:reliable`，模型选择原版显式`resume`，经Native菜单返回自由剧情后确认当前 `menu_captivity_end_wilderness_escape`/enabled `mno_continue`并走原版回调。主角回到自由MapState，Party 0→1；活动`Establish Your Clan`仍存在，模型随后从官方Journal当前未完项目标选择Gold 32/2000。此时Journal Party进度仍0/25，但实时Roster已有1人；本机`RebuildPlayerClanQuest.UpdateProgresses()`以事件/HourlyTick更新的`JournalLog.CurrentProgress`作为四项完成缓存，因此这是原版任务缓存稍晚于Roster的状态，不能由Agent改写或用live值覆盖。差异已保留为诊断信号，官方Journal值作为规划输入。该次显式clock动作只有resume，队伍自然变化、原版Continue及只读Journal都没有额外Clock动作。源存档哈希不变、W7-O临时副本/进程/CLI session清理通过、画面全覆盖，视频提取关键帧后删除。此结果仅证明已俘虏Campaign的原版恢复与目标再规划切片，不代表Establish Your Clan目标达成。

真实Host闭环补证：`TestResults/20261018-050124`通过 `AgentHostBattleAndCaptivityEvaluation`。FreeLLMAPI `auto:reliable`以12次模型决策/路由完成Native bandit接敌与Send Troops；战后确实观察到MainHero Captive、`prisoner_wait`无选项，Host在不发出任何时钟动作下自然等待，1.522 Campaign日后出现野外Native赎金界面。模型依据当前报价选择 `mno_captivity_end_ransom_accept`，Native赎金112使Gold 324→212；MainHero解囚、MainParty 0→1并回MapState。Renown 20→20，最终`playerOutcome=captured-then-recovered`。源档SHA前后相同、临时副本/游戏/Host/session清理，窗口画面覆盖率100%并在提取索引后删除原视频。此证据覆盖一次真实野外赎金恢复，不外推为其他Captor、监狱、逃脱或Captivity等待时长规律。

本机1.4.8 `PlayerCaptivity.Update(dt)`源码补充：仅当MainHero仍为Captor俘虏且`dt > 0`，或MapState当前并非位于菜单时，才同步Captor位置并调用`ICaptivityCampaignBehavior.CheckCaptivityChange(dt)`。因此Stop+`prisoner_wait`菜单中Host单纯延迟/重复读取不推进Captor变化；从Stop恢复必须是单独的原版时间档位动作，并先确认Native当前菜单确实`IsWaitMenu && IsWaitActive`，此时 `AgentProtocol.SetNativeTimeSpeed(1)`才满足原生context gate。Capture observer当前schema25暴露raw `timeControlMode`、`isWaitMenu`和`isWaitActive`，让Host可区别“可显式Play”与“时间本已运行时被动观察”。这来自本机`PlayerCaptivity.Update`、`GameMenu.StartWait/EndWait`、`SetNativeTimeSpeed`源码，W7-O首次运行验收再验证当前Player Captivity menu的实际运行值和后果；不把显式Resume藏进Host等待。

### 转移

`TransferPrisonerBarterBehavior.CheckForBarters`遍历双方Party的`PrisonerHeroes`：一方所持的Hero若与对方Party所属Faction处于战争状态，就把该Hero作为`TransferPrisonerBarterable`加入俘虏Barter组，双方方向分别检查。玩家调整谈判条款并接受后，`TransferPrisonerBarterable.Apply`再次确认交战关系，并调用`TransferPrisonerAction`把Hero俘虏转入对方Party；此转移本身不改Hero个人关系。取消Barter则不调用Apply，因此不转移。

此为对方Party接收仍处敌对关系Hero的“转交俘虏”行为，不能与释放混为一项。目录记录为`ACT-F12-01`，活跃议价盘的信息与报价状态共用`OBS-E10-01`。

`SetPrisonerFreeBarterBehavior`会为双方Party持有的Hero prisoner检查其所属Faction是否未与对方Faction交战；满足时可加入`SetPrisonerFreeBarterable`。若一方Party领袖也是其Clan领袖，该方Clan的dungeon prisoners也会进入遍历。接受条款时，只要该Hero仍为prisoner，就以对方Hero作为`ransompayer`调用`EndCaptivityAction.ApplyByRansom`。这条Barter释放路径可以涉及补偿，但不等同MainHero自己在PlayerCaptivity菜单接受定期Ransom offer；目录记录为`ACT-F12-02`。具体候选对象在玩家屏幕中如何排序/显示、金额与关系效果如何体现，尚未运行核实。

### 自动释放

`PrisonerReleaseCampaignBehavior` 会在以下情况下释放部分俘虏：

- 和平达成；
- 家族加入或离开 Kingdom；
- 阵营关系变化后不再敌对；
- 每日逃脱检查；
- 某些版本迁移和队伍异常修复。

释放概率会受俘虏所在 Party 是否移动、是否为玩家 Party、队伍规模等条件影响。

### 关系相关路径

### 主动释放

领主对话至少有三种由不同ConversationContext区分的放行结果，不能把关系奖励简化成“释放俘虏必加固定好感”：

- `CapturedLord`战后对话中，combatant与noncombatant对应的“free to go”玩家选项共用一条后果；若仍是prisoner则`EndCaptivityAction.ApplyByReleasedAfterBattle`，否则`MakeHeroFugitiveAction`，玩家关系+4（`conversation_talk_lord_defeat_to_lord_release_on_consequence`）。
- 持有的普通俘虏在`hero_main_options`中选择放行，受Party/Clan Settlement归属及ConversationContext条件限制；使用`EndCaptivityAction.ApplyByReleasedByChoice`，关系+4，并可能离开Encounter（`conversation_player_let_prisoner_go_on_consequence`）。
- `FreeOrCapturePrisonerHero`的非首次Lord对话中，对“Am I free?”选择确认释放，关系+10；若目标仍是prisoner再调用`ReleasedAfterBattle`。交战目标另有重新囚禁选项（`conversation_player_liberates_prisoner_on_consequence`）。该路径不能简单标成“释放非战斗俘虏+10”。

放行、EndCaptivityDetail与关系奖励是可分别触发/核验的副作用；以上三种玩家入口及不同结果分别登记为目录`ACT-F12-03/04/05`。它们与Barter释放`ACT-F12-02`、自动释放和主角赎金菜单不同。

相邻的收押与处决路径也不能漏计：`CapturedLord`战后对话中，玩家可确认把被击败领主收为俘虏（`conversation_talk_lord_defeat_to_lord_capture_on_consequence`），与遭遇中MainHero投降不同；在`FreeOrCapturePrisonerHero`对话中，交战对象可以触发“重新囚禁”选项，只有目标此时仍是prisoner才真正调用`TakePrisonerAction`（`conversation_player_fails_to_release_prisoner_on_consequence`）。两者来源状态与结果守卫不同，分别记为`ACT-F12-06/07`。

同一`CapturedLord`对话还提供`Off with your head`处决分支，但对话本身并不立即调用Kill action：目标先经请求处决/最后辩词回到玩家选择；选择“Prepare to die”调用`CreateForInformingPlayer`弹出`HeroExecutionSceneNotificationData`，该面板只有Proceed确认而无否定选项。此确认面属于共享`OBS-J07-03` SceneNotificationData观察面，处决结果归F12动作，不另创建只服务执行场景的新观察ID。通知的`OnAffirmativeAction`将执行标记延迟到关闭时，由`PostponedAffirmativeAction`在受害者非MainHero时根据MapEvent是否仍存在调用`KillCharacterAction.ApplyByExecutionAfterMapEvent`或`ApplyByExecution`；未确认而关闭不会调用此执行分支。因此“对话表态”和真正处决提交是复合流程中的前置与最终确认，目录将整个有状态结果计为`ACT-F12-12`，不将开面板当作已处决。关系/家族影响经执行模型和HeroKilled事件处理，数值需另按I域/执行模型核实。视觉确认与取消行为尚未实测。

以上对话UI与`FreeOrCapturePrisonerHero`特殊ConversationContext的完整游戏入口仍未运行核验。

### 地牢、赎金商人与俘虏容器操作

除了领主Barter，玩家还可在聚落菜单与Ransom Broker处理俘虏：`town_backstreet`提供一次出售全部可卖对象和打开挑选式PartyScreen两项；Ransom Broker对话中的“卖俘虏”同样打开`PartyScreenHelper.OpenScreenAsRansom`。全卖入口会排除被锁定对象，挑选/商人入口经Ransom PartyScreen的Done handler提交；三者最终都调用`SellPrisonersAction`，故合并为`ACT-F12-08`，按“全部/选择集合”作为参数，不重复计算。出售普通兵会移除其俘虏Roster并按Ransom model支付金币；Hero则按buyer上下文释放/转交；移动Party出售还触发俘虏出售技能经验和`OnPrisonerSold`。镇内菜单与Merchant对话的条件/具体现示、Sale UI、数值以及Campaign时间尚未视觉核验。

对非玩家Clan拥有、但与玩家同Faction的要塞，玩家在Dungeon菜单选择`Donate prisoners`打开单向PartyScreen；要求存在可用地牢容量，Done时Hero俘虏进入Settlement，整体Roster变动发`OnPrisonerDonatedToSettlement`。若捐赠队伍和聚落OwnerClan均不属于玩家Clan，原版Influence行为按`PrisonerDonationModel`结算Influence；玩家捐赠Hero还可能按关系模型提高玩家与OwnerClan Leader关系。该行为是把俘虏交给同Faction要塞，不是卖给Ransom Broker，记为`ACT-F12-09`。

玩家在本Clan拥有的Town/Castle地牢可选`Manage prisoners`，打开`PrisonerManage`模式PartyScreen调整MainParty与Settlement dungeon prisoner roster；这是俘虏容器整理，不产生卖价，也不是把Hero招入队伍。只在玩家Clan拥有且同Faction的Fortification开放，Done按roster差异同步Hero Settlement/Prisoner状态；具体双向提交副作用与Cancel回退尚未实机核实，记为`ACT-F12-10`。

### 其他释放路径

赎金、和平释放、逃脱、战后释放和自动释放主要改变 Hero 状态、Party 和日志；不同路径不统一产生个人关系变化。

### 俘虏捐献

`DefaultPrisonerDonationModel` 会根据：

- 俘虏价值；
- 俘虏与聚落领主的关系；
- 俘虏是否为王国领袖或家族领袖；

计算捐献英雄俘虏后的关系收益。

### 日志与通知

`DefaultLogsCampaignBehavior` 监听：

- `HeroPrisonerTaken`，创建 `TakePrisonerLogEntry`；
- `HeroPrisonerReleased`，按 `EndCaptivityDetail` 创建 `EndCaptivityLogEntry`；
- 部分释放路径可以关闭通知，因此不一定产生玩家可见日志。

### 已核实边界与未知

- 俘虏丢失队伍、状态和 Party 归属；
- 俘虏时间和赎金价值被保存；
- 释放类型被区分；
- 释放事件可被多个 Behavior 监听；
- 关系奖励只在部分玩家对话路径中明确写入；
- 被俘造成的军队损失、家族压力、个人羞辱、报复意愿和长期记忆没有统一数据入口。

证据：本机 v1.4.8.119303 `TaleWorlds.CampaignSystem.dll` 中 `TakePrisonerAction`、`TransferPrisonerAction`、`EndCaptivityAction`、`RansomOfferCampaignBehavior`、`PrisonerReleaseCampaignBehavior`、`DefaultPrisonerDonationModel`、相关 Barterable 和日志 Behavior。本节描述源码链；各来源路径、触发分支及通知的玩家可见时点尚未全量运行/UI核验。

## F13 军团召集、领主加入/退出与影响力

本节聚焦 AI 领主如何提议并维持 Army，以及玩家如何看见、管理这些结果；玩家创建/邀请/解散自己军团的基础入口与 VM 草稿提交过程见 F05，不在此重复展开。

### 玩家入口与可观察结果

玩家可从 Kingdom 管理中的 Armies 页面查看军团列表、选择军团并尝试定位、管理或解散。可用命令由 `KingdomArmyVM` 根据所选 Army、玩家是否为管理者及影响力/解散条件启用；进入管理窗口后，`ArmyManagementVM` 展示可参与队伍、Strength、Influence Cost 与 Cohesion。点 Done 才提交 Party 与 Army 关系的改动；Cancel按管理窗口打开时与当前的 Influence 差额退款后关闭。实际游戏中从 Kingdom 页面打开此子页、悬停提示和确认弹窗的逐步视觉路径仍未核实，不能把反编译 VM 直接称作完整 UI 实测。

地图上可看到集合/跟随中的领主队伍；Army 名单和状态属于额外的王国面板信息。当前 Chronicle 附近队伍观察没有 Army ID、领袖、成员名单、Cohesion 或目标；MainParty 观察只输出玩家 Clan Influence 数值，既不是军团成员成本，也不是军团管理页的完整信息。Protocol 没有玩家 Army 管理动作。

### NPC 发起军团与候选成员

一条已确认的 AI 路径从 `AiPartyThinkBehavior` 派发 Think 开始：`AiMilitaryBehavior` 为 AI 领主评估军事目标；符合 `CanLordCreateArmy` 时，它能把符合条件的 WarParty 候选放入 `PartyThinkParams`，并在相应的 Besieger 目标候选上标记 `WillGatherArmy`。随后如果该行为赢得 AI 目标选择，`AiPartyThinkBehavior` 调 `Kingdom.CreateArmy`，由 `Army.Gather` 与 `GatherArmyAction` 建立集合过程。它是周期性 Campaign Think/Army tick 驱动，不是玩家点击命令；满足某个静态条件也不代表必然组军，仍受军事候选评分、随机阈值和现有行为影响。

当前模型要求建军领主不在海上、Clan Influence 大于 100、不是佣兵、食物足以支撑围城模型门槛、王国正在与拥有领地的势力交战、主队规模比例大于 AI 门槛 0.6；领主还须是 Clan Leader，或满足无其他 Clan Leader Party 且当前是 Clan 首个 WarParty 等分支。可能被召集的对象必须为可带队的 Lord Party，不能是主队、君主队伍、已经参军、战斗/围城/等待解散/正在解散/raft 中或被 `DoNotMakeNewDecisions` 禁止的队伍，且自身食物与规模比例也要超过门槛并处于最大召集距离内。不同导航能力会影响距离判断。

候选顺序不是单纯按关系高低：模型用 `CalculatePartyInfluenceCost` 计算成本估值，再以预计战力、伤员比例与成本构成排序；同 Clan 队伍的成本为 0。跨 Clan 成本受两位领主关系、Party 规模和预计战力、距离、随机乘数，以及王国政策、领主 Perk 与文化特性影响。王国内现有军团数量会限制新 Army 可获得的候选 Party 数；有领地王国还要求候选合计的围城攻击战力达到源码门槛。F07/F08 继续解释 Army 接下来选何种军事目标和围城过程。

### 参军、集合与离队

加入不是一个由领主自由对话确认的同意流程。成为 Attached Party 后，`AiArmyMemberBehavior` 为追随 Leader Party 提供 `EscortParty` 候选分数：常规范围 20 至 10；食物不足或 Party 规模比例低于模型门槛时分数下降；无法计算通往领袖的可行导航时只给很低分。实际移动和聚集距离由地图 AI 与 Army Tick 决定，短期目标抵达可合并距离后才加入地图位置/Overlay 上的合并队伍；参与 Party 仍保留各自 Roster、食物、工资和士气。

成员退出 Army 的已核实路径主要是其关联被解除或整个 Army 解散，而不是本节已经证实了 NPC 会通过一次“拒绝邀请”离开。AI Leader 的 Army 在目标行为切换到不适合作为 Army 目标的类型、目标完成或其他目标失效时可能被解散；`DisbandArmyAction` 按原因释放队伍。玩家手动解散是不同分支：只有 `DismissalRequestedWithInfluence` 明确扣玩家影响力并按成员/Leader 分别扣关系；AI 食物、失去战争、低凝聚、无活动等解散原因不会走该玩家成本分支。不要将玩家主动解散的关系损失推广到所有自动解散。

### 持续成本、凝聚力与解散

Army 每小时更新会按模型每日 Cohesion 变化除以游戏小时数累加；基础日变化为 -2，并受到附属 Party 数量、挨饿、低士气/兵力不足，以及 Perk/围城等影响。模型对 AI Army 使用较低的部分负向系数，但不代表 AI 永不缺粮或永不解散。低于 50 Cohesion 时 AI 有尝试提升凝聚力的内部路径；AI Army Cohesion 低于 30 且不在战斗/围城时可解散。另有明确的解散检查：Army 成员中超过一半的队伍饥饿、没有正在争夺领地的战争（源码检查中有随机判定）、Cohesion 趋近于零、领主队伍失活，或达到约 48 小时的某些不活动计数阈值。该“不活动计数”按 Leader 当前行为增减，并非单纯静置 48 小时。

AI 与玩家的费用不能混为一谈：VM 对玩家建军/邀请队伍显示并提交影响力成本；AI 模型也计算成员成本用于候选排序。但在核过的 `CanLordCreateArmy`、`Kingdom.CreateArmy`、`Army.Gather` 和该分支解散调用链中，没有确认 AI 创建/邀请时实际扣除 Clan Influence。`GetInfluenceBudgetWhileCreatingArmy` 返回 Clan Influence 的 70%，但在已反编译的调用点返回值未被接收，不能据此声称其构成扣费上限或已经花费。

### Chronicle 当前覆盖与证据边界

已覆盖的是 MainParty Influence 标量和附近 Party 有限摘要；没有当前玩家 Army 成员/凝聚/目标观察，也没有针对 NPC 建军、候选筛选、追随、脱离、Army 解散原因的事件化观察。现有 Army 机制尚无 UI 级运行验证；以上具体阈值和调用链均为本机 v1.4.8.119303 安装程序集反编译事实，不等于随机战役统计已验证。

主要证据：`TaleWorlds.CampaignSystem.dll` 的 `AiMilitaryBehavior.AiHourlyTick`、`AiPartyThinkBehavior.PartyHourlyAiTick`、`DefaultArmyManagementCalculationModel.CanLordCreateArmy/CalculatePartyInfluenceCost/CalculateDailyCohesionChange`、`AiArmyMemberBehavior.AiHourlyTick`、`Kingdom.CreateArmy`、`Army.HourlyTick/Tick/CheckArmyDispersion/CheckInactivity/IsWaitingForArmyMembers/AddPartyToMergedParties`、`DisbandArmyAction`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `KingdomArmyVM` 与 `ArmyManagementVM`；Chronicle `AgentObserver.cs`、`AgentProtocol.cs` 及 F05 相关记录。

未知项：AI 各分支实际 Influence 扣除是否发生于未覆盖的其他 CampaignBehavior/模型路径；随机军团生成/解散在真实 Campaign 中的发生率、持续时间和通知顺序；玩家从 Kingdom 页打开、修改、确认/取消 Army 的完整可视流程；不同 Party 类型/Mod 对召集门槛、成本和行为评分的改写；成员是否存在本节未覆盖的独立 NPC 拒绝/退出决策；自然地图时间与 Army hourly tick 在各时间模式下的精确运行分布。
