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
