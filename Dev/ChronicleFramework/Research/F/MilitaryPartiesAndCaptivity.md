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

Chronicle 当前常驻 Snapshot 对 MainParty 输出成员/健康/伤员/俘虏人数、总物品数、粮食、每日FoodChange、DailyWage、速度、士气、cargo weight/capacity、AI MoveMode/DefaultBehavior 和目标 ID。NearbyParty 仅枚举可见且活动的队伍、按观察半径排序并最多给前 12 项，字段含 ID/Name/Type/Distance/Hostile/IsMoving/CurrentSettlementId/成员数/估算实力；不列具体Roster、领袖身份、物品/现金/食物、目标Settlement、任务或 AI 思考评分。

当前快照所以是“一个玩家队伍的较丰富结构化观察 + 附近队伍的有限摘要”，不是全图 party census，也不是敌方/友方所有战役队伍的完整自省。`IsVisible`筛选和玩家地图图标/悬浮/ALT之间的精确视图对应关系尚未逐项验证，见 MAINLINE Observation contract 与 K 类。

证据：本机 `TaleWorlds.CampaignSystem.dll` 的 `MobileParty`、`PartyBase`、PartyComponents、Roster与Encounter事件；Chronicle `AgentObserver.cs`、`AgentProtocol.cs` 及 MAINLINE 原版动作契约。静态证据版本 v1.4.8.119303，没有声称各类 Party UI 或 Mission roster 已完整视觉验证。

未知项：各种 PartyComponent 的所有创建源、Destroy/Convert、Owner/Leader/Clan/Faction转移及 SaveData 生命周期；主队/领主队/Minor Faction/Caravan/Garrison/居民等模型过滤矩阵；伤员、英雄、俘虏和Roster操作各玩家 UI 的逐项结果；Map/Encounter/Mission 三层 Party 状态在暂停、结算、保存/加载时的交接边界；不同Mod对类型标志、AI和Roster的新增字段/行为。

## F02 Party AI 决策与执行层

### Campaign 战略目标选择

原版 `AiPartyThinkBehavior` 订阅 `TickPartialHourlyAiEvent`。新建 Campaign 后它会对已存在 Party 初始化触发 Think；MobilePartyCreated 会标记 `RethinkAtNextHourlyTick`。战争/和平、Clan换Kingdom、SettlementOwnerChanged 等事件会结束或修正失效的领地目标、要求重新评估 Army/Party 行为。

参与 Think 的 Party 必须启用 AI 且未被 `DoNotMakeNewDecisions` 禁止；Party Think 明确排除 `MobileParty.MainParty`。正常 NPC Party 的目标重算约以数个 HourCounter 间隔执行；Army Leader、Transition、Attached Party、显式重想标记和围攻/掠夺战斗会调整频率。Encounter中的普通Party不会照常任意换目标，Raid/SiegeAssault 的特定攻击方是例外。

### 目标候选如何聚合

Think 时清空 `PartyThinkParams` 并派发 `CampaignEvents.AiHourlyTick(party, thinkParams)`。注册的各 AI Behavior 向参数中添加 `AIBehaviorData` 和分数；候选记录行为类型、目标 Party/Settlement 或位置、NavigationType/港口参数及是否计划聚集 Army。`AiPartyThinkBehavior` 选择最高分候选，并另保留一个不要求 Gather Army 的候选，之后结合当前 Army、目标、ObjectiveValue、DoNotChangeBehavior 和随机阈值选择是否切换。

因此观察到“一个 Lord Party 当前正围城/进攻”通常只说明 Campaign AI 当前已接受某个行为目标；具体行为候选来自多个 Behavior 评分，而不是 MobileParty 自己存有一个完整自然语言计划。目标会因目标消失、攻守态势、关系/战争变化、Settlement易主、Army状态和重新评估随机门限而被放弃/替换。

### 目标决定怎样落成地图行为

选定行为后，通过 `SetPartyAiAction` 写入原生行动：前往聚落、巡逻、护送、袭击、围城、守卫、绕行队伍、加入/解散 Army等。某些攻/守/巡逻行为可请求创建 Army，行动变化也可能解散原Army。地图移动目标和结算条件随后由 MobileParty/PartyThink/MapEvent/Encounter 子系统处理；当前目标调用成功不等于部队已经抵达或战斗已结束。

### Chronicle 当前覆盖

Chronicle 不读取 NPC的候选分数、`ThinkParams`、ObjectiveValue、Rethink标志、Initiative、AI禁止决策标志或目标评估理由；附近Party摘要只呈现有限状态。Protocol对 MainParty 有少量 move/pursue/hold/Wait动作，不具备向任意NPC Party设置目标/行为或控制其行动分值的动作。原版 AI 的 Campaign执行与 Chronicle Agent的玩家动作适配是两层系统。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `AiPartyThinkBehavior`、`PartyThinkParams`、`AIBehaviorData`、`MobilePartyAi`、`DefaultMobilePartyAIModel`、`CampaignEventDispatcher.AiHourlyTick`、`SetPartyAiAction`；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`。源码版本 v1.4.8.119303；未采集不同真实Party AI Think的完整运行轨迹。

未知项：具体 AI Behavior 对各候选的评分表、模型权重与每种Party专属冷却/禁用门禁尚未全部拆开；AI HourCounter在各 Campaign 模式/地图tick速率下的精确自然时间映射；多队伍同时通过随机决策门限时 Army/Settlement目标竞争次序；Mod新增Behavior的注册和评分合并影响。

## F03 原版 Party AI 行为类型

当前 `TaleWorlds.CampaignSystem.Party.AiBehavior` 定义包括 Hold、None、GoToSettlement、AssaultSettlement、RaidSettlement、BesiegeSettlement、EngageParty、JoinParty、GoAroundParty、GoToPoint、FleeToPoint、FleeToGate、FleeToParty、PatrolAroundPoint、EscortParty、DefendSettlement、DoOperation、MoveToNearestLandOrPort。它们是原版地图行为枚举，不全是“AI长期目标”：Hold/GoToPoint/FleeToPoint等描述的可执行地图状态与攻城、袭击、Escort、DoOperation等高层行为粒度不同。

枚举行为被赋给 `MobileParty.DefaultBehavior`/`ShortTermBehavior`时，必须结合 `TargetSettlement`、`TargetParty`、`ShortTermTarget...`、地图事件与Scene状态才能理解。相同行为名称可能有不同状态转换：例如 EngageParty 是朝目标接敌的地图行为，不等于已发起战斗；DefendSettlement 可能组织周边队伍支援；FleeToGate 会以地形/聚落出口为逃离路径；这些表现与具体 `SetPartyAiAction`/`MobilePartyAi` 条件相关。

此为枚举完整名单，不意味着每类 Party 可选择全部选项。组件类型、所属Faction、地形导航、Campaign状态、Army、SiegeEvent/MapEvent和行为提供者会过滤候选；每类候选的生成逻辑归 F04 与 F03后续逐项行为链核实。`None`表示未设定候选，不等于玩家空闲操作；`DoOperation`的具体操作目标/支持子系统本轮尚未闭环。

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

### 玩家建军与召集条件

`DefaultArmyManagementCalculationModel.CanPlayerCreateArmy` 拦截玩家未加入 Kingdom、作为 Mercenary、已作为 Leader 指挥另一支 Army、在海上、囚禁、raft、Mission、地图遭遇、对村庄掠夺或被围城等情况。管理 VM 的篮子必须保留玩家 MainParty，至少需一个可加入/现存的额外 Party 才能创建；ArmyMembership influence cost 经 Model 计算而非固定创建费。被邀 Party 还要求适配阵营、未加入另一 Army、不是 Kingdom Ruler Party、未在战斗/围城/解散等待，队伍规模通常高于 PartySizeLimit 的指定比例、在召集距离内且有可用导航/船只。关系、Party Strength/Size/距离、Clan政策、LeaderPerk和文化特性都会修正影响力成本。

确认 VM 草稿后，如 MainParty 当前尚无 Army 且在王国阵营，会建立玩家领导的 Army 并把选中 MobileParties 关联到它，按总 Influence Cost 扣除影响力；取消则不提交草稿。玩家可通过同一窗口移除 Party 或显式解散（另有影响力成本/确认）；`DisbandArmyAction` 会释放成员 Party 并记录原因事件。

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

同一 Clan Parties VM 支持更换 Party Leader、分配 Party Roles/部分行为、查看 party 名单/工资等类别；更换 Leader 会调用对应Party/DelayedTeleport逻辑。解散操作拒绝 MainParty、Garrison、Militia或处于战斗/围城的队伍；普通自有 Party 的解散还涉及返回的 Settlement/物资及俘虏处理，分别在 F11/F12 边界核查。

### 对照 AI Clan War Party 与 Chronicle 覆盖

NPC Party 的 `LordPartyComponent` 由角色/clan war party 系统持有，模板生成和AI补兵链与上面的玩家新队伍入口不同。AI PartyThink选择 Army/战术目标是 F02/F05，不应把 WarPartyComponent 入册/生成等同一个长程自主目标。Clan改王国、领地变化、Hero死亡或Party被销毁，会改变 WarPartyComponent 名册、控制关系或Army成员，需要按各Event路径继续追踪。

Chronicle主队Snapshot有Party摘要，但没有Clan Owned WarPartyComponent的全量 roster、PartyLimit使用情况、各队Leader/Home/工资/自动行为、创建草稿候选或新Party初始化后状态；Protocol没有 `CreateNewClanMobileParty`/队伍编成/编队补兵命令。当前静态证据不代表Agent可自主管理新的家族移动部队。

证据：当前 `TaleWorlds.CampaignSystem.dll` 的 `WarPartyComponent`、`Clan.WarPartyLimit/WarPartyComponents/CurrentTotalStrength`、`DefaultClanTierModel`、`LordPartyComponent`、`MobilePartyHelper.CreateNewClanMobileParty`、`ClanFinanceModel.PartyGoldLowerThreshold`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `ClanPartiesVM`/`ClanPartyItemVM`；Chronicle `AgentObserver.cs`。源码版本 v1.4.8.119303；没有实机点击Create New Party、扣款、检查新party roster或返回MainParty的UI验收。

未知项：AI NPC WarParty生成/死亡/损失后的完整补充频率和玩家Party的后续兵员增长策略；PlayerClan新Party在初始MainParty、城镇、队伍外等不同Hero位置下的所有位置/物资前后态；Party management中角色、兵种、伤兵、物品、工资上限和Disband各按钮的视觉输入/提交顺序；WarPartyLimit不同Tier、Clan类型与NPC衡量的实际差异；队伍被俘、改Faction、Leader死亡对Clan roster和军团存档恢复的完整结果。

## F12 Hero 俘虏、管理与释放

本节保留既有俘虏子系统研究。俘虏转移涉及 Factions、战斗、菜单/Party UI 和关系/叙事，相关的关系后果与日志消费者另见 B/C/J 类研究。

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

### 赎金与 Barter 转移

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

### 转移

`TransferPrisonerBarterable` 允许在满足阵营敌对条件时通过 Barter 转移俘虏。转移本身不改变 Hero 个人关系。

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

领主对话中存在明确关系奖励：

- 玩家主动释放战败后俘虏的领主，会调用 `ApplyPlayerRelation(..., 4)`；
- 玩家选择释放非战斗俘虏的领主，会调用 `ApplyPlayerRelation(..., 10)`；
- 释放行为和关系奖励是两个独立调用。

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

## F01 MobileParty 与 PartyBase 对象

### 队伍是 Campaign 实体，不是单一 troop 列表

`MobileParty` 是可移动/可参加战役行动的 Campaign 实体；它持有 `PartyBase`、位置/路径、移动模式与目标、PartyComponent、LeaderHero、Roster、库存、食物/士气/工资及 AI 行为状态。`PartyBase` 持有成员、俘虏、物品 roster、地图事件/遭遇等战斗与物资数据。二者关系相关但不应当作同一个对象：地图移动、AI和目标通常看 MobileParty；伤亡/交易/人员物资常经过 PartyBase/Roster。

队伍类型由组件和派生标志区分，包括玩家 MainParty、Lord WarParty、Caravan、Garrison、Villager、Bandit、Militia、Patrol 等。它们的行动主体和系统资格并不相同：例如驻军有 GarrisonPartyComponent 且没有地图导航 AI；商队是 CaravanPartyComponent 且有独立 PartyTradeGold；Militia与Villager不按 Lord Party 行为结算。D04/D07/E05/E06已有对应对象/经济细节，本节不重复逐项重写。

Roster 按成员/俘虏/物品分开：成员伤兵仍处于成员 roster 并有 wounded count，俘虏在 PrisonRoster，货物在 ItemRoster。玩家队伍还可受到军团附属/临时支援/战后事件等上下文影响，`PartyBase.NumberOfAllMembers`、`MemberRoster.TotalManCount`、`PrisonRoster.TotalManCount` 和 UI当前可转移数量不应混用。

### 入口、生命周期与 Campaign边界

玩家的 Party 状态主要通过地图主队、Party Screen（队伍成员/升级/俘虏转移）、定居点驻军管理、遭遇/战后结算等入口变化。队伍生成/毁灭、成员加入/离队、Leader更换、Faction变更和Settlement进入/离开由 PartyComponent/Action/CampaignEvent 及不同 CampaignBehavior 管理；“地图上队伍图标”只是其一个可见阶段，不等同队伍成员 roster 或任务处理过程。

Leader/Clan所属、移动AI、Faction敌对、队伍与军团关系、驻军、粮食/工资、俘虏、战斗和贸易都有独立状态及不同 tick。玩家移动/追近/停步/等待的时间入口由 MAINLINE 原版机制契约约束；一般 MobileParty 属性读取本身不推动Campaign时间。Mission内的Party由场景/队伍编制逻辑实例化，Campaign地图抽象与真实 Mission Party 不能无条件互推。

### Chronicle 当前观察与行动覆盖

Observer 当前主快照以 Player MainParty 为中心，给出成员/健康/伤兵/俘虏人数、物品总数、食物、工资、速度、士气、负重/容量、位置和移动目标；Nearby Parties 限于一定视距内可见队伍并最多截取若干项，输出种类、距离、敌对状态、是否移动、当前Settlement、人数/估算强度等，未展开完整 troop/item roster、Leader详细身份、Food、Wage、俘虏、目的地决策或内存目标。

Protocol已有 move/pursue/hold、菜单/遭遇/战后部分操作；动作契约与限制继续引用 MAINLINE，不在 F01 重新定义。Agent目前不是通用队伍Roster/AI行为编辑器，也不能因为有MainParty快照就声称覆盖所有 AI MobileParty。

证据：本机 `TaleWorlds.CampaignSystem.dll` 的 `MobileParty`、`PartyBase`、`PartyComponent`、Concrete PartyComponents、`TroopRoster`、`ItemRoster`、CampaignEvent/Action；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`、MAINLINE 机制契约。当前结论来自 v1.4.8.119303 安装程序集与现有代码，不代表各Party类型的可视呈现、队伍屏幕所有操作或地图AI目标已实机穷举。

未知项：不同PartyComponent队伍完整生命周期/创建源及Faction派生矩阵；玩家 PartyScreen 从入口到提交/取消的所有操作和限制；战争、遭遇、围城中 Party roster/Leader/Faction切换的完整顺序；单机抽象模拟与Mission单位的边界及同步细节；当前 Observer 截断规则与每类队伍对玩家UI情报面的一一对应关系。
