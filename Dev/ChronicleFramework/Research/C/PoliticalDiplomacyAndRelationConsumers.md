# C 类专题：政治、外交与关系消费者

状态：机制拆解，未进行方案评审

本文描述王国决策、战争/和平、家族身份转换以及它们对关系的读取方式。

## C01 KingdomDecision

### 决策结构

- `KingdomDecision` 有提案 Clan；
- 决策属于某个 Kingdom；
- 决策有候选结果、提案者、支持者和选择者；
- 决策消耗 Influence；
- 支持存在 Choose、Neutral、SlightlyFavor、StronglyFavor、FullyPush 等权重；
- 决策可以被取消、自动解决或进入玩家参与的选举。

### 关系读取

- Sponsor Clan 与 Proposer Clan 的 Hero 关系会参与支持判断；
- 支持者关系会影响支持权重和支持意愿；
- 家族之间的关系通过 Clan Leader 关系计算；
- 关系与影响力成本、候选结果概率共同决定决策结果。

## C02 KingdomDecisionProposalBehavior

- 在 `DailyTickClanEvent` 中为符合条件的 Clan 评估提案；
- 需要 Clan 存活、属于 Kingdom、拥有军力和足够 Influence；
- 可能生成战争、和平、政策、联盟、贸易协定和吞并类决策；
- 对战争和和平存在冷却、重复决策和当前战争状态检查；
- 决策加入 Kingdom 的未解决决策列表；
- 战争、和平、王国毁灭和家族换王国会触发决策列表更新；
- 过期或不再适用的决策会被取消或自动选举解决。

## C03 战争与和平

### 宣战

`DeclareWarAction`：

- 设置 Faction Stance 为 War；
- 根据双方领地规模可能调整 PoliticalStagnation；
- 分发 `WarDeclared`；
- 宣战原因通过 `DeclareWarDetail` 区分王国决策、叛乱、玩家敌对、王国创建等来源。

### 和平

`MakePeaceAction`：

- 将双方 Stance 设为 Neutral；
- 设置每日贡金和持续时间；
- 分发 `MakePeace`；
- 和平来源通过 `MakePeaceDetail` 区分默认和王国决策等路径。

## C04 战争/和平评分

`DefaultDiplomacyModel` 会在战争和和平评价中读取：

- 双方军力和队伍数量；
- 领地、驻军和伤亡；
- 成功围城、攻城和掠夺次数；
- 边境暴露和距离；
- 同文化和联盟因素；
- 贸易协定；
- evaluating Clan 与相关领袖/家族的关系；
- 战争已经持续的时间。

模型可以提供理由文本，例如力量不足、战争代价过高、敌人过强、敌人太多等。

## C05 家族加入、离开和叛变

`ChangeKingdomAction` 处理：

- 加入 Kingdom；
- 叛变加入 Kingdom；
- 离开 Kingdom；
- 叛乱离开；
- 佣兵加入和离开；
- 建立 Kingdom；
- 因 Kingdom 毁灭离开。

身份转换可能同时处理：

- Clan.Kingdom；
- 阵营 Stance；
- 领地所有权；
- 队伍返回和移动；
- 佣兵状态；
- 债务和贡金；
- 战争和和平；
- `OnClanChangedKingdomEvent`、`OnClanDefectedEvent`。

## C06 家族加入/离开评价

`DefaultDiplomacyModel` 对 Clan 加入或离开 Kingdom 的评价会读取：

- 统治家族与目标 Clan 的关系；
- Clan 与其他成员家族的关系；
- 文化是否相同；
- Clan 领地价值和军力；
- Kingdom 领地价值与敌人力量；
- Clan WarPartyLimit；
- Clan 最近换阵营时间；
- Clan 的可靠性常数；
- 是否正在与目标 Kingdom 交战。

## C07 联盟与贸易协定

- 联盟评价读取统治者关系、双方力量、文化、战争和外交状态；
- 贸易协定评价读取统治者关系、已有贸易状态、经济因素和随机周级变化；
- 协议建立与结束会产生 CampaignEvent 和 LogEntry；
- 关系只是评分因素，不会独立形成盟约承诺或个人外交协议。

## C08 领地和政治结果

- 领地分配使用 KingdomDecision 和选举支持；
- 领地易主可能触发旧领主与家族成员关系变化；
- 家族离开王国会处理其领地、队伍和战争关系；
- 家族关系、领袖关系、王国政策和影响力同时参与政治结果。
