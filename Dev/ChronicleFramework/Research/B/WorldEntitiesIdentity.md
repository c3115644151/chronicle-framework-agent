# B 类：世界实体、身份与关系

状态：原版机制事实，未进行方案评审。

本文是 B 类唯一研究文档，合并 Hero、Clan、Kingdom、Faction、个人关系、身份转换、关系来源与消费者。优化判断只进入 `DESIGN.md`。

## 实体与身份

### Hero

- 生命周期状态包括 Active、NotSpawned、Traveling、Prisoner、Released、Fugitive、Disabled、Dead；
- 主要归属包括 Clan、OriginClan、CompanionOf、SupporterOf、MapFaction、PartyBelongedTo、PartyBelongedToAsPrisoner 和聚落位置；
- 角色身份包括王国/家族领袖、领主、队伍领袖、总督、同伴和各类 notable occupation；
- 持久资料包括文化、年龄、属性、技能、Perk、Trait、装备、关系和历史日志引用。

### Clan

- 成员、领袖、领地、队伍、文化、家园、家族等级、声望、影响力、金币和总军力；
- 所属 Kingdom、佣兵状态、债务、贡金钱包、Aggressiveness、叛军/匪徒/贵族类型；
- 在政治系统中作为 KingdomDecision、加入/离开、领地分配和战争行为主体。

### Kingdom

- 统治家族、成员 Clan、领地、政策、Army、预算和外交 Stance；
- 持久状态包括未解决决策、总军力、PoliticalStagnation、钱包和最近决策时间。

### Culture、Faction 与 MapFaction

- Culture 提供兵种、PartyTemplate、默认政策、Trait、聚落和场景数据；
- Faction 类型包括 Kingdom、Clan、Minor/Bandit Faction、Outlaw 和 Rebel Clan；
- Hero 通常经 Clan 映射到 Kingdom，Party 的 MapFaction 可能与 Hero 的个人状态不同；
- MapFaction 参与敌对判断、AI、战争、菜单和遭遇条件。

## 阵营关系

`FactionManager` 管理 Faction 之间的 Stance。`StanceLink` 保存双方、战争与和平时间、伤亡、围城、掠夺、城镇攻占和贡金等统计。

阵营敌对通过 `FactionManager.IsAtWarAgainstFaction` 等路径判断，与 Hero 个人关系分开存储。身份转换会改变 Clan、Kingdom 和 MapFaction，但不会自动重建个人关系历史。

## 个人关系数据模型

```text
关系来源
→ ChangeRelationAction
→ DiplomacyModel.GetEffectiveRelationChange
→ 性别/Charm/Trait/Emissary等修正
→ GetHeroesForEffectiveRelation
→ 通常折算为双方 Clan Leader
→ CharacterRelationManager 写入整数
→ HeroRelationChanged 事件
```

- `Hero.GetBaseHeroRelation` 读取基础整数；
- `Hero.GetRelation` 读取 DiplomacyModel 计算后的有效关系；
- 有效关系可叠加亲属、Honor、Valor、Mercy 等修正并 Clamp；
- 玩家本人和玩家同伴存在特殊解析例外；
- 两个非玩家领主之间的有效关系经常实际读取双方家族领袖关系；
- 个人关系、Clan 关系、Faction Stance 和亲属关系是不同数据路径。

关系事件包含变化双方、变化量、原始 Hero 和 `ChangeRelationDetail`，但当前整数关系不保存完整原因链，也没有统一的恩情、仇恨、债务或关系阶段对象。

## 关系写入来源

| 类别 | 原版来源 |
| --- | --- |
| 新档初始化 | 距离、文化、领袖身份、人格冲突和随机值 |
| 战斗与地图事件 | 战斗贡献、援军、守村、商队/村民战斗、救援 |
| 围城与领地 | 围城结果、领地价值、旧领主、占领者、Siege Aftermath |
| 聚落 | 安全、忠诚、显贵状态和村庄保护 |
| 政治身份 | 加入/离开王国、叛乱、投奔、政策和王国决策 |
| 家族生命周期 | 婚姻、领袖死亡、支持、封臣和佣兵行为 |
| 任务与对话 | Issue、Quest、LordConversation、Persuasion 的固定或模型化结果 |
| 俘虏 | 被俘、赎金、和平/战后释放、主动释放、逃脱、捐献和转移 |
| 其他 | Barter、贸易协定、Incident、Perk、Trait、犯罪和同伴行为 |

不同来源可以写入相同数值；Charm、Trait、性别和有效 Hero 解析会导致相同原始值产生不同最终变化。

## 关系消费者

| 消费域 | 读取结果 |
| --- | --- |
| 婚姻 | MarriageBarter 价值、可行性和婚姻关系变化 |
| 家族招募 | 加入、离开、接纳、驱逐王国的评价与 Barter |
| 外交政治 | 宣战、议和、联盟、贸易协定、KingdomDecision 支持 |
| AI | 接战/追击目标评分、聚落目标、军团管理；通常先经过阵营敌对筛选 |
| 聚落 | 进入限制、忠诚、安全、志愿兵招募和显贵互动 |
| 交易 | Barter、安全通行、俘虏和政治服务价值 |
| 对话说服 | 文本、选项、拒绝、初始进度和成功率 |
| 任务问题 | 条件、奖励、失败和关系门槛 |
| 信息出口 | 百科排序、历史评论、日志、传闻和通知 |

已确认模型消费者包括 `DefaultDiplomacyModel`、`DefaultAllianceModel`、`DefaultTradeAgreementModel`、`DefaultMarriageModel`、`DefaultSettlementAccessModel`、`DefaultSettlementLoyaltyModel`、`DefaultSettlementSecurityModel`、`DefaultVolunteerModel`、`DefaultTargetScoreCalculatingModel`、`DefaultArmyManagementCalculationModel` 和 `DefaultPrisonerDonationModel`。

## 身份转换

主要事件包括：

- Hero 加入/离开 Clan；
- Clan 加入/离开 Kingdom；
- 统治家族变化；
- 佣兵与封臣转换；
- 婚姻、出生、成年、死亡和继承；
- 俘虏、释放和逃脱；
- Clan/Kingdom 创建、毁灭和叛乱；
- Personal Relation 与 Faction Stance 变化。

这些事件会更新归属、阵营、队伍和政治状态，但个人关系通常保留原值。对话和任务主要根据玩家当前身份切换文本，历史身份不一定进入统一条件链。

## 玩家可见出口

- 固定门槛：选项、进入、招募、任务；
- 公式修正：战争、和平、Barter、AI 和政治；
- 文本反馈：称呼、态度、感谢、威胁和拒绝；
- 历史反馈：日志、百科、传闻和通知。

## 当前未知项

- 当前 `v1.4.8` 下全部关系写入调用点及其精确数值尚未重新探针；
- 全部消费者的阈值、权重和身份例外尚未形成机器可读表；
- `ChangeRelationDetail` 在各来源中的覆盖完整性未验证；
- 新档、读档和长期运行中的事件重复与状态恢复未验证。

这些未知项完成前，本文件不推导具体关系重构方案。
