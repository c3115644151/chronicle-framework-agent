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

百科 Hero 页可展示家庭成员；玩家婚姻谈判/婚姻选项的具体 UI 入口涉及 J 类对话/Barter 路由，本段只记录 `MarriageAction` 与持久对象关系。Chronicle Observer 当前没有输出完整家庭链，也没有婚姻/生育动作。证据：`TaleWorlds.CampaignSystem.dll`（`Hero`、`HeroCreator`、`MarriageAction`、`InitialChildGenerationCampaignBehavior`、`PregnancyCampaignBehavior`、`MarriageModel`），以及已有百科 Hero 页源码。未知项：婚姻对话到 Barter 的完整 UI 调用链、各代际/失去父母后 `_children` 列表处理、叛军/佣兵/婚姻 Clan 变更例外、妊娠概率和持续时间的默认数值仍需分别追对应系统；未从字段关系推断情感/忠诚含义。

#### B03 能力成长与角色开发界面

地图界面快捷键 C（`GenericCampaignPanelsGameKeyCategory.CharacterWindow`）在主 Hero 存活时打开 `CharacterDeveloperState`。界面 ViewModel 包含可选择的 Hero、属性、技能、当前技能的 Focus 点、可用 perk 选择、等级与未分配点数；`ExecuteDone` 应用待修改项，`ExecuteCancel` 撤回界面未提交的修改，Reset 按钮恢复开发点/Perk 选择。列表来自玩家 Clan 的 Hero 集合和 Companions，筛掉 null、Disabled、死亡或未成年 Hero；这不是战役内所有 Hero 的总览。

状态数据分属 Hero 与 `HeroDeveloper`：技能当前值、属性、已选 Perk 与等级由 Hero/角色数据持有；`HeroDeveloper` 另保存每项 skill XP、新增 Focus map、Total XP、未用 Focus 点及 Attribute 点。这些字段使用 SaveableField/SaveableProperty 随 Campaign 存档恢复。开局/新增 Hero 时 `InitializeHeroDeveloper` 根据已有技能建立初始等级、分配待用点；NPC/行为侧调用 `DevelopCharacterStats` 时会自动分配剩余点并选择 Perk，不能将其与玩家打开 C 后手动配置混为同一输入。

技能成长链：`HeroDeveloper.AddSkillXp` 用 `GenericXpModel` 计算加成 XP，并根据 `CharacterDevelopmentModel.CalculateLearningRate` 的属性/Focus/当前技能值计算学习率；达到模型要求时更新 Hero 技能值、触发 `OnHeroGainedSkill`；原始 XP 增长会计算 Level，并按模型配置给 Focus 点、周期性给 Attribute 点并分发 `OnHeroLevelledUp`。各类 XP 的进入点由技能行为/战斗/任务等系统各自调用，本段不预设完整来源清单。

Chronicle 当前 Observer 不输出属性、技能XP、Focus、Perk或未分配点数；Protocol 当前没有角色开发动作。只读/测试动作接口不得直接替代 UI 中的点数校验、临时变更、提交与撤销行为。证据：安装 `TaleWorlds.MountAndBlade.dll`（快捷键 C）、`TaleWorlds.CampaignSystem.dll`（`HeroDeveloper` Saveable 字段、成长接口）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`CharacterDeveloperVM`、`CharacterDeveloperHeroItemVM`、`SkillVM`/`PerkVM`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen.OpenCharacterDevelopmentScreen`）和本地 `AgentObserver.cs`/`AgentProtocol.cs`。未知项：Character Developer 全部适用 Hero 的运行时筛选条件、每个技能完整 XP 来源与奖励/上限、角色开发 UI 锁定条件及同伴技能是否拥有同样的全部操作尚未逐项核实。

#### B04 Hero身份与归属

Hero 的职业身份（`Occupation`）与 Clan/Faction 归属、队伍位置、生命周期状态分别存储。`IsLord` 只是 `Occupation == Lord`，notable 判定由数种 notable occupation 组合派生；它不等同于“属于一个 Clan”或“当前在某支 Party”。`SetNewOccupation` 写入职业并分发 `OnHeroOccupationChanged`。

有效 `Hero.Clan` 读取为 `CompanionOf ?? _clan`；加入玩家 Companion 关系后，显示 Clan 与存储的原始 Clan/OriginClan 可以不同。更改底层 `_clan` 会更新 Clan 的领主名单、清理 HomeSettlement 缓存并分发 `OnHeroChangedClan`。`Hero.MapFaction` 优先取 Clan 所属 Kingdom，否则取该 Clan；没有 Clan 时 Special occupation 返回 null，否则先看 HomeSettlement 的 MapFaction，再回退到当前 Party 的 MapFaction。因此 Hero 的个人地图阵营不总等于 Party 的阵营。

位置/隶属另由 `PartyBelongedTo`、`PartyBelongedToAsPrisoner`、`StayingInSettlement` 保存；普通 Party 变更会在离开旧队伍时移除旧队长身份和队伍角色，战俘归属不是普通成员队伍。百科 Hero 页面显示 occupation、Clan/faction、Last Seen 等字段；玩家与 Hero 的对话/Barter文本还会依据职业、Faction 和当前关系生成身份称谓/选项。Chronicle 现有 Main Hero 快照仅包含有限 Hero/Clan 标识；附近 Party 快照不会展开每个 Party Leader 的完整职业、原始 Clan、OriginClan 等身份链。

证据：当前 v1.4.8 `TaleWorlds.CampaignSystem.dll`（`Hero.Clan`、`MapFaction`、`Occupation`、`SetPartyBelongedTo`、`SetNewOccupation`）、`TaleWorlds.CampaignSystem.Actions.ChangeKingdomAction`、百科 Hero 页面源码及 `AgentObserver.cs`。未知项：所有职业转换动作的 UI入口和数据副作用、Clan/Kingdom转换后每类 Hero 的文本/可见信息矩阵、营地与聚落中NPC身份判定差异、Party与Hero MapFaction不一致的全部情境尚未穷举；Clan 与 Kingdom 归属操作分别在 B05/B06/C07 继续拆解。

### Clan

- 成员、领袖、领地、队伍、文化、家园、家族等级、声望、影响力、金币和总军力；
- 所属 Kingdom、佣兵状态、债务、贡金钱包、Aggressiveness、叛军/匪徒/贵族类型；
- 在政治系统中作为 KingdomDecision、加入/离开、领地分配和战争行为主体。

#### B05 Clan数据与玩家家族界面

Clan 是 Faction 子类；`Clan.MapFaction` 在有 Kingdom 时为所属 Kingdom，否则为 Clan 自己。`Clan` 保存/提供 Leader、Heroes、Companions、Settlements/Fiefs、WarPartyComponents、Culture、HomeSettlement、Renown、Influence、Kingdom、佣兵状态等。`Tier` 是 Campaign 的 ClanTierModel 管理的缓存值，并受等级上下限约束；下一等级声望门槛和家族可带队伍上限也由 ClanTierModel 查询。需要区分 `Clan.Gold`：它返回 `Leader?.Gold ?? 0`，不是另一份独立的家族金库余额。

`Hero.Clan` 变更会增删 Clan 的领主成员并分发 HeroChangedClan；`Clan.SetLeader` 同时把新 Leader 的 Clan 指向该 Clan。Clan Influence 属于 Clan；减少 Influence 时会调用当前 Leader 的 InfluenceSpent 技能经验处理。

玩家入口：地图快捷键 L（`ClanWindow = 41`）在主 Hero 存活时推入 `ClanState`；`ClanManagementVM` 读取 `Hero.MainHero.Clan`。页面分成员、队伍、领地、收入四类数据，显示 Leader、Renown/Tier进度、Gold/日收入，并提供更改 Clan 名称、编辑旗帜等入口。控制台/接口直接改 Clan 字段不能自动执行上述 UI 的名单刷新、弹窗校验或派对/领地管理操作。

Chronicle Observer 当前仅给出玩家 Clan ID/名称/Tier、玩家 Gold、Influence、Renown；没有输出完整 Heroes/Companions、领地、家族队伍、佣兵状态或领导权。Protocol没有Clan管理动作。证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`Clan`、`ClanTierModel`、`Hero.Clan`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`ClanManagementVM`）、`TaleWorlds.MountAndBlade.dll`（`GenericCampaignPanelsGameKeyCategory.ClanWindow`）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen.OpenClanScreen`）与 `AgentObserver.cs`。未知项：Clan页面中各类别实际可用操作和权限、不同Clan类型（Player/Noble/Mercenary/Rebel/Minor）字段/菜单差异、英雄死亡后的领导权选择与家族解散链、Kingdom成员转换对家族界面的完整影响尚未逐项运行核验。

### Kingdom

- 统治家族、成员 Clan、领地、政策、Army、预算和外交 Stance；
- 持久状态包括未解决决策、总军力、PoliticalStagnation、钱包和最近决策时间。

#### B06 Kingdom数据与玩家界面

Kingdom 是独立 Faction；`MapFaction` 返回 Kingdom 自身。`RulingClan` 持有王国统治家族，`Leader` 从该 Clan 的 Leader 派生；`Clans`、`Fiefs/Towns/Villages` 与 `Armies` 暴露只读集合，`KingdomBudgetWallet` 是王国预算余额。Kingdom 与 Clan 不是同一所有者：Clan 的 Kingdom 归属将 Hero/Clan 映射到王国阵营，但 Hero 个人关系和 Clan 自己的成员/财富仍由各自数据持有。

玩家入口：地图快捷键 K（`GenericCampaignPanelsGameKeyCategory.KingdomWindow`）只有在 Main Hero 的 MapFaction 是 Kingdom faction 时才打开 `KingdomState`。`KingdomManagementVM` 以 Player Clan 当前 Kingdom 建立界面，包含 Clans、Fiefs、Policies、Armies、Diplomacy 五类页面；Policies/Diplomacy 是否允许切换还受 PlayerHasKingdom 状态控制。领导者/普通王国成员见到的“王国行动”不同：分别显示退位或离开王国/结束佣兵服务，执行时还要过原生权限检查与确认流程。

身份变更边界：Clan 加入/离开 Kingdom 由 `ChangeKingdomAction` 处理，而不是修改某个 Hero 的个人身份文本字段。其动作会调整 Kingdom 对 Clan 的隶属及 Stance/贡金相关收尾、在离境情形处理领地、队伍移动及战争状态，并分发 `OnClanChangedKingdom`；Defection 另分发 `OnClanDefected`。具体外交/决策后果归 C 类研究，本段记录 Kingdom 与 Hero/Clan 的对象连接及界面入口。

Chronicle 当前 Player snapshot记录Clan标识、名称、Tier、Gold/Influence/Renown，但不读取 `Clan.Kingdom` / Kingdom id、RulingClan、Clans/Fiefs/Armies、KingdomBudgetWallet或Policies；尚无 Kingdom 管理动作。证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`Kingdom`、`ChangeKingdomAction`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomManagementVM`）、`TaleWorlds.MountAndBlade.dll`（K键）、`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll`（`MapScreen.OpenKingdomScreen`）、`AgentObserver.cs`。未知项：国王/普通成员/佣兵/叛军的各页面差异、Kingdom faction关闭或废弃过程中的残留 Hero/Clan 状态、王国管理每项读写权限和 UI 确认分支尚未完整核验；战争/选举/政策效果不在本项重复拆解。

### Culture、Faction 与 MapFaction

- Culture 提供兵种、PartyTemplate、默认政策、Trait、聚落和场景数据；
- Faction 类型包括 Kingdom、Clan、Minor/Bandit Faction、Outlaw 和 Rebel Clan；
- Hero 通常经 Clan 映射到 Kingdom，Party 的 MapFaction 可能与 Hero 的个人状态不同；
- MapFaction 参与敌对判断、AI、战争、菜单和遭遇条件。

#### B07 Culture选择与数据载体

新战役角色创建中的 Culture 阶段由 `CharacterCreationCultureStageVM` 调用当前 `CharacterCreationContent.GetCultures()` 建列表；点击文化项后选中该 Culture，可能按其 `DefaultCharacterCreationBodyProperty` 更新玩家脸部/体型数据，并设 `Hero.MainHero.Culture`；进入下一阶段时将选择写回 CharacterCreationContent。该选择属于角色创建，不是 Clan/Kingdom 身份；本机尚未找到 Campaign 内通用“更换文化”入口。

`CultureObject` 是 XML 数据对象，提供 BasicTroop、DefaultPartyTemplate、默认政策、CulturalFeats、名字列表、Lord/Notable/叛乱 Hero 模板和可用船体等文化内容。Hero、Clan、Kingdom 与 Settlement 各有 Culture 字段/引用；模型与生成器选择各自读取这些字段，文化不是 MapFaction 的别名。玩家通常通过可见 NPC/Settlement、兵种和百科页接收文化信息；Chronicle Observer 当前未读取 Hero/Clan/Kingdom 的 Culture 字段。

证据：当前 `TaleWorlds.CampaignSystem.dll`（`CultureObject.Deserialize` 与数据属性）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`CharacterCreationCultureStageVM`）、本机 Story/Sandbox/Native Data XML与 `AgentObserver.cs`。未知项：Culture 的全部模型效果、沙盒/故事模式可选文化集合、特殊 Culture 与阵营之间的变化规则和完整可见UI字段未全量枚举。

## 阵营关系

`FactionManager` 管理 Faction 之间的 Stance。`StanceLink` 保存双方、战争与和平时间、伤亡、围城、掠夺、城镇攻占和贡金等统计。

#### B08 Faction 与 Stance

Faction 关系经 `FactionManager` 查询/更新，双方阵营状态由 `StanceLink` 保存；该链接还保留战争/和平起止、伤亡、围城、掠夺、攻占城镇和贡金等统计。王国间、Clan与王国、叛军等对象共享 Faction 接口，但具体参战和固定战争规则会由 DiplomacyModel/行动调用方进一步过滤。

阵营敌对通过 `FactionManager.IsAtWarAgainstFaction` 等路径判断，与 Hero 个人关系分开存储。Hero 的 `MapFaction` 通常经 Clan 指到 Kingdom；Party 自己也有 MapFaction，因此同一角色与所在队伍的阵营信息在无 Clan、特殊 Hero、叛逃或代理 Party 情形下可能不同。身份转换会改变 Clan、Kingdom 和 MapFaction，但不会自动重建个人关系历史。玩家可在 Kingdom Diplomacy 等页面触发政治行动；本项只记录状态/对象，不重复 C03-C10 的宣战、议和、联盟和决策过程。

证据：当前 `TaleWorlds.CampaignSystem.dll`（`FactionManager`、`StanceLink`）、本地 `Hero.MapFaction` 与 `AgentObserver.IsHostile` 路径。未知项：各 Faction 配对的无链接默认 Stance、ConstantWar 和特殊势力的具体例外、遭遇/AI/菜单处使用的全部 MapFaction 判定点仍需按 C/F/G 系统研究交叉核实。

## 个人关系数据模型

#### B09 个人关系的基础值与有效值

```text
关系来源
→ ChangeRelationAction
→ 正向变化的 DiplomacyModel/Charm 修正
→ GetHeroesForEffectiveRelation
→ 通常折算为双方 Clan Leader
→ CharacterRelationManager 写入成对整数
→ HeroRelationChanged 事件
```

- `Hero.GetBaseHeroRelation` 读取基础整数；
- `Hero.GetRelation` 读取 DiplomacyModel 计算后的有效关系；
- 当前 DefaultDiplomacyModel 的有效关系会叠加 Honor、Valor、Mercy 等修正并 Clamp；亲属身份在独立关系路径中，不在此模型的 trait 修正函数中。
- 玩家本人和玩家同伴存在特殊解析例外；
- 两个非玩家领主之间的有效关系经常实际读取双方家族领袖关系；
- 个人关系、Clan 关系、Faction Stance 和亲属关系是不同数据路径。

当前源码中 `CharacterRelationManager` 持久保存 Hero ID 对的整数关系（key 按两 Hero ID 排序，查询为对称 raw value）；`Hero.GetBaseHeroRelation` 读取原始值，`Hero.GetRelation` 交 `DiplomacyModel` 得到 effective value。`DefaultDiplomacyModel` 会先通过 `GetHeroesForEffectiveRelation` 通常把双方替换成所属 Clan Leader；若两者因此相同，或涉及玩家本人和玩家 Companion，则使用原 Hero。随后将 Honor、Valor、Mercy 的 Trait 组合加减到 raw value 并 Clamp。因为特质修正以传入的 Hero 与 effective Hero 计算，raw value 对称不意味着所有身份情形下的 effective value 必然对称。

`ChangeRelationAction` 在写入前只对正向变化调用 `GetRelationIncreaseFactor`（Charm 经验/Perk等来源会调整增长量并随机取整）；再选 effective Hero pair，将原始整数相加并 Clamp 到[-100,100]。随后通过 `Hero.SetPersonalRelation` 写入并分发 `OnHeroRelationChanged`，事件参数同时携带 effective pair、变化量、原始调用双方与 `ChangeRelationDetail`。`CharacterRelationManager` 不为每笔整数变化保存完整原因链；没有独立恩情、仇恨、债务或关系阶段字段。旧档加载仍有对早于v1.1版本无效Hero ID的清理。

Chronicle Observer/Protocol 当前不读取或写入 raw/effective Hero relation，也没有关系历史/关系动作；关系源和消费者目前是源码映射，尚无自动测试。证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`CharacterRelationManager`、`DefaultDiplomacyModel`、`ChangeRelationAction`、`Hero.GetRelation`）、本地 `AgentObserver.cs`/`AgentProtocol.cs`。未将 B/C/F/J 中的每个 relation caller 合并去重，B09 的玩家行为/观察总数仍留待 W1-M 交叉整理。

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

#### B10 Traits 与 Reputation

Hero Traits 与 Crime/Reputation 不是同一数值。原版五种可见人格 Trait 为 Mercy、Valor、Honor、Generosity、Calculating，等级区间 -2…2；当前 DefaultDiplomacyModel 用 Honor/Valor/Mercy 组合修正有效关系。Trait XP 由 `TraitLevelingHelper` 经 `PlayerTraitDeveloper` 累积，通过 CharacterDevelopmentModel 转成 Hero trait level；等级改变时发 `OnPlayerTraitChanged`。足够大的 trait XP 变化还会生成 `PlayerReputationChangesLogEntry`。可见写入来源包括战斗英勇、牺牲兵力、处决领主、违约、劫掠村庄、敌对行动、善待/饿坏队伍、Issue/Quest结果、释放领主、说服叛逃与围城战后处理；此列表是源码已确认的调用样本，尚非所有调用点的完备分母。

Crime Rating 则按 `IFaction.MainHeroCrimeRating` 分阵营保存，随玩家阵营变化可以不同；`DefaultCrimeModel` 的轻度条件为0<x≤30，中度为30<x≤65，严重为x≥65，故边界65同时满足中度和严重查询；Declare War 使用60门槛，最大值100。罚款计算和处罚后回落使用 CrimeModel 单独公式。因此 Honor/Trait、Hero间 personal relation 与对Faction的犯罪评价属于三条数据链；一次行为可能写入不止一条。

Hero 的 Trait 在角色开发界面以条目显示而不由玩家直接任意编辑；普通 Agent Observer 当前不包含 Trait/Crime 字段。来源：当前安装 `TaleWorlds.CampaignSystem.dll`（`TraitLevelingHelper`、`DefaultTraits`、`DefaultCrimeModel`、`Faction.MainHeroCrimeRating`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`CharacterDeveloperHeroItemVM`/traits显示）、本地 `AgentObserver.cs` 与已追踪的 Trait/Relation 消费者模型。未知项：全部Trait写入调用点及数值、Faction犯罪评级的所有UI入口、各难度/模块对Trait/Renown/Crime的修正尚未完成机器可读清点。

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
