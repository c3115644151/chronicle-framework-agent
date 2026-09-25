# B 类：世界实体、身份与关系

状态：原版机制事实，未进行方案评审。

本文是 B 类唯一研究文档，合并 Hero、Clan、Kingdom、Faction、个人关系、身份转换、关系来源与消费者。优化判断只进入 `DESIGN.md`。

## 实体与身份

### Hero

- 生命周期状态包括 Active、NotSpawned、Traveling、Prisoner、Released、Fugitive、Disabled、Dead；
- 主要归属包括 Clan、OriginClan、CompanionOf、SupporterOf、MapFaction、PartyBelongedTo、PartyBelongedToAsPrisoner 和聚落位置；
- 角色身份包括王国/家族领袖、领主、队伍领袖、总督、同伴和各类 notable occupation；
- 持久资料包括文化、年龄、属性、技能、Perk、Trait、装备、关系和历史日志引用。

#### B01 生命周期与状态读取

当前安装 v1.4.8 的 `Hero.CharacterStates` 枚举值为 NotSpawned、Active、Fugitive、Prisoner、Released、Dead、Disabled、Traveling。`Hero.IsActive` 等标志只是从 `HeroState` 派生；特别是 `IsAlive` 的源码判定是“状态不等于 Dead”，所以 Disabled、Prisoner、Fugitive 并不自动等同于 Dead。

`Hero.ChangeState` 写入 HeroState，并通知所属 Clan 的 `OnHeroChangedState` 及 `CampaignObjectManager.HeroStateChanged`；转入 Traveling 会派发 `OnHeroGetsBusy`，转入 Active 会派发 `OnHeroActivated`。死亡不是普通 `ChangeState` 的替代调用：`KillCharacterAction` 先检查 `CanDie` 与遭遇/围城中的延迟死亡标记，再走 `BeforeHeroKilled`、死者状态/DeathDay、俘虏或队伍清理、Clan/Kingdom 继承/解散及 `HeroKilled` 等后果；玩家主角会先进入 `OnBeforeMainCharacterDied` 分支，由其专门处理。

年龄不靠逐日累加字段：`Hero.Age` 在 Life/Death 周期启用时由 CampaignTime 与 BirthDay 即时计算（存活 Hero 到当前时间，死亡 Hero 到 DeathDay）；周期关闭时返回创建/设置生日时记录的 `_defaultAge`。默认 `AgeModel` 中成年门槛为18岁、老年起点55岁、最大年龄128岁。默认死亡概率模型在 Life/Death 周期开启且年龄大于55后才产生老死风险，概率按年龄由0增加，到127岁为1；`Hero.CanDie(DiedOfOldAge)` 仍会受周期选项限制。死亡、成年的实际触发行为可能来自战斗/故事/家族生命周期的不同调用方，不能只从年龄字段推导发生时机。

可见信息：百科 Hero 页面显示名字、年龄、职业、关系、当前 Last Seen 文本、死者标记及筛选出的个人历史。玩家此前确认 N 可打开百科；本版本键位注册和页面完整交互仍需实机复核。普通地图观察主要覆盖附近/已知队伍及当前位置，不能据此推定整个 Hero 清单都对玩家可见。Chronicle Observer 目前只报告与Agent相关的有限身份/周边字段，不提供全体 Hero 生命周期事件流。

证据：安装 `TaleWorlds.CampaignSystem.dll`（`Hero.CharacterStates`、`Hero.Age`、`Hero.ChangeState`、`KillCharacterAction`、`DefaultAgeModel`、`DefaultHeroDeathProbabilityCalculationModel`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`EncyclopediaHeroPageVM`），以及 A03 的对象级 Campaign tick 事实。未知项：造成年龄跨阈值事件的全部行为、所有死亡模型调用点、不同身份/StoryMode下的死亡和继承分支、真实百科/附近观察UI覆盖仍未完成；本段只确立 Hero 本体生命周期合同，不提前扩展到 Clan 继承或关系消费者。

#### B02 家庭、婚姻与子女

Hero 的 `Father`、`Mother` 是独立持久引用；设置父/母属性时会将子 Hero 加到相应父/母的 `_children` 列表。`Children` 直接返回存储列表；`Siblings` 是按父母列表动态计算的派生枚举（若有 Father 则遍历父方列表，否则用 Mother 列表）。因此 family links 不等同于同 Clan 成员关系，也不是通过个人关系值推算。

`Spouse` 是双向关系属性：设置一方会把对方的 `Spouse` 设回自身；解除/换配偶时原配偶被放入 `_exSpouses`。实际结婚流程不是单独写这个字段：`MarriageAction.Apply` 先检查 `MarriageModel.IsCoupleSuitableForMarriage`，写双方 Spouse、增加关系，再依据 MarriageModel 结果变更其中一方 Clan；若人物当前为总督/队伍/军团成员，Clan 变更还会撤总督、转队伍归属/可能解散队伍或军团并清理敌对行为，最后结束 Courtship 并设置 RomanticState.Marriage。配偶死亡时 `KillCharacterAction` 解除另一方 Spouse，历史配偶关系进入 ExSpouses。

初始既有家庭由新档 `InitialChildGenerationCampaignBehavior` 在 `OnNewGameCreatedPartialFollowUp` 阶段生成；不是出生动画或玩家操作。运行中怀孕由 `PregnancyCampaignBehavior` 按 Hero 每日回调检查成年、Life/Death 周期开启、存活、女性、非叛军 Clan、婚姻及妊娠状态，并用 PregnancyModel 概率与位置条件计算受孕。怀孕记录单独保存 Mother、Father 与 DueDate；到期后随机双胞胎/死胎/母亲产后死亡分支，正常新生 Hero 由 `HeroCreator.DeliverOffSpring` 建立父母引用、族群/文化/性别/生日等，并分发 OnGivenBirth。玩家主角作为父/母时，子女沿用玩家 Clan/Culture；其他家庭中新生子女进入父亲 Clan，文化在父母间选取。子女的出生日龄、父母关系、所属 Clan 与配偶身份为不同字段/关系链。

百科 Hero 页可展示家庭成员；玩家婚姻谈判/婚姻选项的具体 UI 入口涉及 J 类对话/Barter 路由，本段只记录 `MarriageAction` 与持久对象关系。证据：`TaleWorlds.CampaignSystem.dll`（`Hero`、`HeroCreator`、`MarriageAction`、`InitialChildGenerationCampaignBehavior`、`PregnancyCampaignBehavior`、`MarriageModel`），以及已有百科 Hero 页源码。未知项：婚姻对话到 Barter 的完整 UI 调用链、各代际/失去父母后 `_children` 列表处理、叛军/佣兵/婚姻 Clan 变更例外、妊娠概率和持续时间的默认数值仍需分别追对应系统；未从字段关系推断情感/忠诚含义。

#### B03 能力成长与角色开发界面

地图界面快捷键 C（`GenericCampaignPanelsGameKeyCategory.CharacterWindow`）在主 Hero 存活时打开 `CharacterDeveloperState`。界面 ViewModel 包含可选择的 Hero、属性、技能、当前技能的 Focus 点、可用 perk 选择、等级与未分配点数；`ExecuteDone` 应用待修改项，`ExecuteCancel` 撤回界面未提交的修改，Reset 按钮恢复开发点/Perk 选择。列表来自玩家 Clan 的 Hero 集合和 Companions，筛掉 null、Disabled、死亡或未成年 Hero；这不是战役内所有 Hero 的总览。

状态数据分属 Hero 与 `HeroDeveloper`：技能当前值、属性、已选 Perk 与等级由 Hero/角色数据持有；`HeroDeveloper` 另保存每项 skill XP、新增 Focus map、Total XP、未用 Focus 点及 Attribute 点。这些字段使用 SaveableField/SaveableProperty 随 Campaign 存档恢复。开局/新增 Hero 时 `InitializeHeroDeveloper` 根据已有技能建立初始等级、分配待用点；NPC/行为侧调用 `DevelopCharacterStats` 时会自动分配剩余点并选择 Perk，不能将其与玩家打开 C 后手动配置混为同一输入。

技能成长链：`HeroDeveloper.AddSkillXp` 用 `GenericXpModel` 计算加成 XP，并根据 `CharacterDevelopmentModel.CalculateLearningRate` 的属性/Focus/当前技能值计算学习率；达到模型要求时更新 Hero 技能值、触发 `OnHeroGainedSkill`；原始 XP 增长会计算 Level，并按模型配置给 Focus 点、周期性给 Attribute 点并分发 `OnHeroLevelledUp`。各类 XP 的进入点由技能行为/战斗/任务等系统各自调用，本段不预设完整来源清单。

Chronicle 当前 Observer 不输出属性、技能XP、Focus、Perk或未分配点数；Protocol 当前没有角色开发动作。只读/测试动作接口不得直接替代 UI 中的点数校验、临时变更、提交与撤销行为。证据：安装 `TaleWorlds.MountAndBlade.dll`（快捷键 C）、`TaleWorlds.CampaignSystem.dll`（`HeroDeveloper` Saveable 字段、成长接口）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`CharacterDeveloperVM`、`CharacterDeveloperHeroItemVM`、`SkillVM`/`PerkVM`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen.OpenCharacterDevelopmentScreen`）和本地 `AgentObserver.cs`/`AgentProtocol.cs`。未知项：Character Developer 全部适用 Hero 的运行时筛选条件、每个技能完整 XP 来源与奖励/上限、角色开发 UI 锁定条件及同伴技能是否拥有同样的全部操作尚未逐项核实。

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
