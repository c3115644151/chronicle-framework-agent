# I 类研究：角色关系、家庭与社会互动

适用本体：Bannerlord v1.4.8.119303。本文是 I 域唯一研究资料。B类保留 Hero/Clan/Faction关系对象与持久数据事实，C类保留王国外交/决策，F12/H12保留俘虏Roster及玩家囚禁，J类保留对话/任务/叙事消费者；本类只补I01-I10中玩家进入社会关系互动的流程和跨域边界，不复制上述资料里的公式和事件清单。

## I01 Personal Relation：Hero个人关系

玩家在领主/同伴对话、说服、婚姻Barter、政治支持、任务结果、释放俘虏等原生社交过程与各Hero互动；许多关系变化是选择结果，不存在通用“关系+1”菜单。详细数据读写见 [B09关系模型](../B/WorldEntitiesIdentity.md#b09-个人关系的基础值与有效值)：基础关系、有效关系、Trait/身份映射和 `ChangeRelationAction` 是不同层；来源样本和消费者已在B/J整理。

玩家能观察到的反馈散布在关系提示、对话态度/选项、Barter估值、百科/日志等，不是一个永久关系历史面板；当前Chronicle不提供raw/effective Hero relation、近期关系来源历史或修改动作。常规对话是玩家入口，Story/Map/Barter当前上下文会限制选项；直接写 `CharacterRelationManager` 绕过有效关系模型、魅力增益/随机取整、事件和UI结果。Campaign时间遵循具体对话/Barter宿主GameState，不由关系动作隐式快进；各宿主的时钟差异见J/MAINLINE。未知：完整关系写入/读取调用点分母、玩家每个界面如何显示当前对象的关系、关系改变消息与历史日志的完整对应表。

## I02 Faction Relation：阵营关系、敌对与和平

关系社会系统中的Faction Stance回答Clan/Kingdom等阵营是否为War/Neutral/Allied，不等同两位Hero的个人关系或亲属身份。地图遭遇、Faction敌对条件、王国Diplomacy/Election、和平贡金与联盟中会读写这条状态；详细玩家入口和状态变更分别见 [B08](../B/WorldEntitiesIdentity.md#b08-faction-与-stance) 与 [C03-C05](../C/PoliticalDiplomacyAndRelationConsumers.md)。

玩家入口可能是地图敌对行动立刻发起War，也可能是K→Diplomacy提交提案、经过决策投票后改变Stance；行动原因、Influence/关系/贡金副作用不同。Chronicle只在附近队伍摘要中给Hostile状态，未观察完整Faction关系历史或外交动作。`IsAtWarAgainstFaction`的查询结果不是永久保证；Faction/Clan/Party归属转换会改变玩家看到的敌我上下文。宣战/和平走原生Campaign状态变化，不由查询工具推进时间。未穷举的特殊派系、犯罪敌对与Mod自定义Stance例外仍属未知。

## I03 Prisoner Social State：俘虏身份中的关系后果

俘虏作为Hero状态既影响当前归属/可行动身份，又可能经对话释放、赎金、和平、逃脱和捐献产生不同关系/声望后果。`TakePrisonerAction`本身和某个玩家对话给关系奖励不是同一个效果；各释放路径详见 [F12](../F/MilitaryPartiesAndCaptivity.md#f12-hero-俘虏管理与释放)，玩家特殊囚禁态/等待见 [H12](../H/PlayerPartyAndProgression.md#h12-player-captivity玩家被俘等待与脱身)，文本/选择见[J02]。

玩家真实入口依当前Capture来源可能是战后俘虏列表、Lord encounter/对话、barter或PlayerCaptivity GameMenu；不同入口对Hero/普通兵俘的能力不相同。Chronicle只读主队俘虏数量、有限PartyState roster和PlayerCaptivity所在GameState上下文；没有释放英雄、赎金、转移俘虏或处理囚禁菜单动作。囚禁等待需要Campaign时间/检查事件自然流转；不要把菜单回执当作时间已推进。关系细项避免在此重复F12/J，尚未知UI不同释放选项/同一事件的所有关系通知顺序。

## I04 Marriage 与 Romance：求偶、婚约和婚姻结算

### 玩家发起与多阶段求偶

当前 `RomanceCampaignBehavior` 把玩家求偶入口放在与Eligible Hero的一对一会面/对话中。初始选项只有在对方非Minor Faction、不是囚犯、符合MarriageCourtshipPossibility且当前RomanticState为Untested等条件时开放；失败兼容/现实条件后可能再次尝试。开始Courtship后经过多个阶段与说服选项，Persuasion结果把双方Romance状态推进、继续或失败；这些选项与普通的“谈恋爱聊天”不同，是有条件的行动链。

求偶成功后，双方同意结婚仍不是最终完成：对Clan领袖提案会开启Marriage Barter/家族联结谈判，由 `MarriageBarterable`和Barter系统确认；另一类相对人物/亲属提案走不同的对话选择。最终执行 `MarriageAction`写Spouse、关系、Clan归属和身份后果，详见B02；直接设置Spouse或调用MarriageAction会跳过求偶、婚约协商和UI可行性。

默认MarriageModel门槛包括两方Clan可婚、不能双方都为Clan Leader、当前模型要求异性、排除一定亲属范围、排除存在冲突的跨Clan Courtship，并要求双方CanMarry/达到适用年龄。每条门禁会让对话选项不出现或拒绝结算。NPC家族间婚姻由RomanceCampaignBehavior另有每日决策，不是玩家菜单选择。

Chronicle没有主动寻找可婚对象、查看完整RomanceState/兼容拒绝理由、执行求偶说服或婚姻Barter工具；只可经通用Conversation/Barter研究接口观察当前上下文。Campaign时间：NPC婚姻/求偶冷却含日常tick；玩家对话中的流程属于遭遇/对话时间规则，不能将Courtship按钮当作天数流逝。证据：`RomanceCampaignBehavior`、`DefaultRomanceModel`、`DefaultMarriageModel`、`MarriageAction/MarriageBarterable`、B02及J01/J03。未知：完整玩家起始相遇入口、各阶段选项的数值/身份条件、求偶失败可重试时间/随机条件、婚姻Barter UI的逐页提交/取消与真实可视效果。

## I05 Family 与 Kinship：家庭关系、继承与生命周期

父母、子女、兄弟姐妹、配偶和ExSpouse是Hero对象之间独立持久关系，不由Clan membership或个人关系值替代；婚姻、生育和孩子生成/教育链见 [B02](../B/WorldEntitiesIdentity.md#b02-家庭婚姻与子女)。玩家百科/N页面可查看角色与家庭线索，但并不存在“改亲属关系”按钮。玩家能够通过婚姻、家族身份变化、继承/死亡事件间接改变家庭网络，具体操控入口取决于恋爱/婚姻/家族管理流程。

家族死亡、继承人和玩家角色切换会作用于不同系统对象，不能将同Clan或友好关系推为有血缘、继承权或忠诚义务。Chronicle当前不输出完整亲属树、婚姻历史或家族继承资格，也没有构造/改变亲属身份动作；关系数据、可见百科入口与Campaign生命周期分别见B01/B02/B05、J06。继承玩法、Player死亡后的续任选择以及各类Clan解散时亲属关系如何留存/显示仍需专门核查。

## I06 Education：子女教育选择

Education不是玩家创建主角时的背景选择（H01），而是Campaign内Player Clan子代成长过程。`EducationCampaignBehavior.OnDailyTick`检查玩家家族未成年Hero，按照ChildAgeState处理约2、5、8、11、14、16岁阶段；年龄节点到达时显示 `EducationMapNotification`，玩家由地图通知进入 `EducationState`，按分页回答选项后 `Finalize`对儿童应用属性/技能/Focus等效果并记录阶段。

`EducationVM.OnOptionSelect`把当前选项ID写入本次教育流程的`_selectedOptions`，更新获得项预览并开放下一页；中间页的Next只切换页面。Summary页的按钮文字为Done；`ExecuteNextStage`在最后页调用`EducationCampaignBehavior.Finalize(child, selectedOptions)`后关闭EducationState，形成与单页选择不同的最终提交动作。第一页的Previous/Exit走`onDone(true)`而不调用Finalize；返回前页是流程导航，不是新的学习结果。对应玩家族可重复收到不同年龄通知、同一教育阶段中多个选项按页选择，因此“选项选择”和“最后Done提交”分列ACT，自动补课不计玩家动作。

若Campaign跳过了先前未完成教育阶段，源码先调用 `DoEducationUntil`，按当时可用选项随机补完前序阶段，然后才对最近阶段发玩家通知；角色到成年事件时会自动完成剩余阶段并清理教育历史。Education通知只对父母在PlayerClan的孩子流程开放；同一个Hero一般不能由玩家编辑其他Clan儿童的课程。选择效果会累积在孩子的HeroDeveloper/特征/技能，不是只生成一个文本日志。

Chronicle当前没有EducationNotification/State快照、翻页/选项选择或教育完成结果动作。时间由Campaign每日事件检查；在战斗MapEvent时某些DailyTick可能被跳过；打开教育面板后的父GameState是否冻结世界需运行核实，不用固定快进。证据：`EducationCampaignBehavior.OnDailyTick/DoEducationUntil/OnHeroComesOfAge/Finalize`、`EducationState`、`EducationVM.OnOptionSelect/ExecuteNextStage/ExecutePreviousStage`、通知VM/类型与B02/H10交叉事实；均为本机v1.4.8.119303静态源码，未跑可视教育界面。未知：所有年龄节点默认课程树、模式/Mod增补课程、玩家未点击通知时何时和怎样随机补选、教育面板离开/存档/跳过过程中是否重复发奖励。

## I07 Traits 与 Reputation：人格特征和声誉反馈

Hero人格Traits、Clan Renown、Faction Crime Rating、个人关系是四条不同数据链；Trait可以修正关系/说服/战斗等其他系统，但不等同“某人对玩家的好感”。相关Trait等级、XP、可见UI和写入样本见 [B10](../B/WorldEntitiesIdentity.md#b10-traits-与-reputation)，Trait如何出现在说服/称谓见J03/J01。

玩家没有常规Trait直接编辑器；个性变化是行为/选择带来的累计结果，角色开发页展示Traits但不允许任意点选修改。Trait更改与声誉日志提示属于反馈，不保证每次变化都能追溯其唯一行为来源。Chronicle未观察Trait、特征XP或其历史来源，也无设置动作。未知：所有Trait写入点的完整分母、当前难度/模块具体倍率、Trait和关系有效值在不同身份转换中的详细消费者矩阵。

## I08 Crime 与 Reputation：犯罪评级及赎罪

Crime Rating由Faction分别保存，不是Hero Trait中的Honor，也不是Hero个人关系。犯罪/敌对行为可能对某些Faction升Crime Rating，系统还可能发通缉/敌对反应；轻/中/重评级的意义由CrimeModel与调用者分别判断。数据含义/默认阈值见B10，犯罪产生的关系/特征/政治后果可跨到C03/J。

玩家缴罪的入口包括被带到城镇广场审判或与城镇执法势力讨论投降；原生GameMenu会按犯罪地区与模型可支付条件显示选项：接受体罚、支付Gold、支付Influence、体罚+Gold、接受处决或忽略指控。金额由 `PayForCrimeAction.GetClearCrimeCost`/CrimeModel按支付方式计算，执行用 `PayForCrimeAction.Apply`，之后根据Settlement类型离开到town/castle外菜单。菜单检查金币/影响力、当地Faction、Crime severity和当前玩家身份；直接将Crime Rating设0会绕过支付、处罚、关系和菜单迁移。

CrimeRating在Campaign每日模型中衰减/积累，并受Faction、玩家所属阵营、战争、Perk与Alley等影响；停在人物面板查看它不推进时间。Chronicle当前Observer不读取每个Faction犯罪值，Protocol没有犯罪清偿、投降或处理审判动作。来源：`CrimeCampaignBehavior.AddGameMenus`、`DefaultCrimeModel`、`ChangeCrimeRatingAction/PayForCrimeAction`、B10、当前Chronicle源码。未知项：所有增加Crime Rating的实际玩家行为与敌对条件、各支付方式完整罚金/后果、执行/忽略的结果和死亡保护、地区/Clan犯罪值在UI/百科的可见路径未全量验证。

## I09 Dialogue Relation：对话中的关系入口

关系值不会单独弹出一个社交面板让玩家任意选择；多数入口是地图Party/领主相遇、聚落NPC交谈、Barter、Issue/Quest对话和俘虏交涉。Dialogue sentence的条件、身份、阵营、任务、Relationship、Trait和Encounter都会一起筛选当前可选项，选项效果可能同时影响Relation、Clan/Faction状态、任务、Gold或Captivity。

J01/J02/J04已经记录原版Lord、Prisoner、Issue/Quest对话消费者。Chronicle通用Conversation适配只能读取当前真实开放选项并调用原生 `DoOption`；它并没有全部对话参与者/对话上下文的完整可见清单、可读懂的关系变化历史或具名社交策略。当前Conversation State可能因Party遭遇、Mission、聚落场景或GameMenu而不同；直接调用后果Action绕过当前对话的条件、开场/阶段和玩家选择反馈。各场景时钟要分开核查，不因选项名称判断时间是否推进。

## I10 Persuasion：说服任务与阶段结果

Persuasion是附着于特定对话选择/社会互动的有限次检定任务，不是所有交谈都有的统一成功率。`PersuasionTask`拥有多个可选argument、target/goal value、当前进度、难度及attempt状态；`DefaultPersuasionModel`根据ArgumentStrength、技能/特征、玩家与目标关系及难度计算成功/暴击/失败机率，attempt之后应用进度和后续阶段/封锁选项效果。求偶、王国选择或任务说服可各自创建task、提供不同选项与后果。

玩家入口是进入具体交谈并由真实条件开放Persuasion选项；选中argument后原生Persuasion状态计算尝试结果，UI展示进度/可能性和成功/失败结果。直接计算chance或调用 `PersuasionTask.ApplyEffects`并不能替代先决状态、随机尝试、对话当前阶段及结果效果处理。详细基础事实见J03。Chronicle一般对话适配目前仅能从开放选项选择，没有PersuasionTask/target/current-success/剩余attempt/概率与上一步失败阶段的结构化观察，也没有专属重试策略；只记录原生真实选择即可。时间遵循宿主Dialog/Encounter/Wait GameState，不做隐式 `advance`。未知：每个系统具体task初始化条件/数值/argument文本去重、random seed与存读档、失败后的处罚/替代选项跨行为一致性及Model改写影响。
