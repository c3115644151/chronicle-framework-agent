# C 类专题：政治、外交与关系消费者

状态：机制拆解，未进行方案评审

当前本体：Bannerlord v1.4.8.119303。本文描述王国决策、战争/和平、家族身份转换以及它们对关系的读取方式。

## C01 KingdomDecision

### 决策对象与提案提交

`KingdomDecision` 保存提案 Clan、所属 Kingdom、候选结果、选择者与 TriggerTime；基类默认触发等待为48小时，子类可覆写。各决策子类分别提供合法条件、提案 Influence 成本、候选方案、支持评分、提案者、次级效果和选定结果的具体应用。

决策进入 Kingdom 时经 `Kingdom.AddDecision`：除非调用方明确忽略成本，否则先从 ProposerClan 扣除该决策规定的提案成本；随后分发 `OnKingdomDecisionAdded` 并判断玩家是否参与。属于玩家 Kingdom 的决策进入 `UnresolvedDecisions`，留给 Kingdom 管理界面处理；其他 Kingdom 的决策创建 `KingdomElection` 并立即启动 NPC 选举。故“有决策对象”“加入未解决列表”“玩家收到待处理入口”是不同状态。

### 决策提案来源

`KingdomDecisionProposalBehavior` 订阅 `DailyTickClanEvent`，按 Clan/Kingdom 状态、军力、Influence、未解决决策、当前战争/和平和冷却等条件尝试提案。当前已见类型包括宣战、议和、政策、联盟/贸易协定及领地吞并类决策；各决策类型有自己的候选计算与模型阈值。战争、和平、家族换 Kingdom 和 Kingdom 消灭等事件会更新或取消相关未决项。该行为提供原版 AI Clan 的提案源，不是玩家发出的菜单操作。

### 关系读取

Sponsor Clan 与 Proposer Clan 领袖 Hero 的个人关系可参与支持计算；候选 Sponsor、Influence 与候选结果评分共同决定支持选择。玩家所在 Kingdom 的决策进入后续选举/支持流程，见 C02。

## C02 KingdomElection

`KingdomElection.Setup` 从 Decision 取得初始候选，调用 `NarrowDownCandidates(..., 3)` 最多留下三个；同时调用 `DetermineSupporters`（该 Decision 所属 Kingdom 内非佣兵 Clan）、`DetermineChooser`、`DetermineSponsors`，计算候选 InitialSupport 与 Likelihood。Decision 是否由 King 选择还是由支持票决定取决于具体 Decision 子类提供的 Chooser。

玩家入口是地图 K→Kingdom 窗口→Decisions 页面，且玩家必须是 Chooser 或 Supporter。`KingdomDecisionsVM.OnFrameTick` 监视新的玩家 Kingdom `UnresolvedDecisions`；遇到玩家参与的决策先给待处理提示，打开后由对应 `DecisionItemBaseVM` 展示候选、支持强度、影响力成本及预估胜率。Player Supporter 为候选选择 Choose/StayNeutral/SlightlyFavor/StronglyFavor/FullyPush；Player Chooser 选择结果，君主也可弃权转由 AI 选择。非玩家参与者由选举逻辑自行处理。

支持的基准 Influence 成本为0/0/20/60/150（Choose、StayNeutral、SlightlyFavor、StronglyFavor、FullyPush），Leader的 Flexible Ethics Perk 可调整该成本；具体决策可覆写基准。结果应用时支持者扣影响力，未胜出的支持可按规则减半，独自投票的一Clan决策成本可归零，Good Natured 等 Perk 也参与成本处理；Chooser 推翻多数结果可能额外付费。批准候选还会调用该 Decision 的 `ApplyChosenOutcome` 与 `ApplySecondaryEffects`，并可能因赞助者/反对方产生个人关系变化。

玩家决策弹窗/选项与 K 窗口的 `KingdomDecisionsVM` 是UI决策层；`KingdomElection` 保存/计算本轮候选、支持者、Choice与最终 outcome。结论后触发 `KingdomDecisionConcluded`；被取消则触发 Cancelled。多个实现（King selection、Settlement claimant、policy、war/peace、alliance/trade）共享选举框架但各自提供候选和结果效果。

源码链：`Kingdom.AddDecision`→`KingdomDecision.DetermineSupporters/DetermineChooser`→`KingdomElection.Setup/StartElection`→玩家Kingdom的`UnresolvedDecisions`→K管理页`KingdomDecisionsVM.HandleDecision`→具体`DecisionItemBaseVM`→`OnPlayerSupport/ApplySelection`→Decision应用与Influence结算。非玩家 Kingdom 在 AddDecision 时立即启动 election。Chronicle Observer/Protocol 当前不读取未解决决策、候选、支持/投票状态，也没有决策参与动作；已安装 `TaleWorlds.CampaignSystem.dll`（`KingdomDecision`、`KingdomElection`、`Kingdom.AddDecision`）与 `TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomDecisionsVM`、`DecisionItemBaseVM`）为源码证据。未知项：决定刚产生时玩家弹窗的实机时点、Timeline/保存/载入时选举中间状态、各 Decision 子类的特有权限、投票界面按键/关闭恢复未逐项运行测试。

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

玩家王国菜单入口为 K→Diplomacy：选中正在交战的 Kingdom，会显示提议和平/已有和平决策 Resolve；选中中立/停战 Kingdom，会按条件显示提议战争/已有战争决策 Resolve。VM检查 MapScreen行动权限、佣兵状态、Influence 与 `KingdomDecisionPermissionModel`；确认战争/和平提议后创建 `DeclareWarDecision` 或 `MakePeaceKingdomDecision`，调用 `Kingdom.AddDecision` 并打开C01/C02的选举/决议流程，不直接写 Stance。议和方案显示日贡金额、持续时间和支持预估。单Clan王国可能即时按单人决策路径解决。

另一个入口是地图上的玩家敌对行为，由 `DeclareWarAction.ApplyByPlayerHostility` 标记原因。宣战应用经 `FactionManager.DeclareWar` 建立 War Stance，并可能按双方领地规模降低 PoliticalStagnation、标记玩家可见敌方 Settlement/Party Visual dirty，最后分发 `WarDeclared(faction1, faction2, DeclareWarDetail)`。当前 `DeclareWarDetail` 还区分 KingdomDecision、Rebellion、CrimeRatingChange、KingdomCreation、ClaimOnThrone、CallToWarAgreement 等来源。

`MakePeaceAction` 会将 Faction Stance 设为 Neutral、在既有 `StanceLink` 写入 daily tribute 及持续天数，必要时刷新玩家可见的敌方 Settlement/Party Visual，并发 `MakePeace`。普通 `Apply` 写0贡金/0时长；KingdomDecision专用入口传入经过模型/选举的贡金和期限。故和平对政治关系、贡金流和视觉变化是一个原子行动的多个后果。

来源：当前安装 `TaleWorlds.CampaignSystem.dll`（`DeclareWarAction`、`MakePeaceAction`、`FactionManager`、`StanceLink`）和 `TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomDiplomacyVM`、`KingdomDecisionPermissionModel`）。Chronicle 目前只使用 Faction 敌对判断验证地图目标，并在局部观察中返回附近部队的 hostile 状态；尚无宣战/议和模型动作或 Kingdom Diplomacy UI 适配。王国决策时间与 Campaign clock 依 A02 运行；本段不让外交操作隐式推进或暂停时间。

玩家直接地图敌对和王国菜单提案是两种起点：前者可能立即通过 DeclareWarAction；后者先进入 KingdomDecision/Election 并可能被否决。两者最后都更新 Faction Stance，但原因事件、Influence成本、贡金和关系/视觉后果不同。当前源代码路径已映射，K菜单点击/敌对交战效果未实机测试。

### 战争/和平评分

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

## C04 联盟与援战

- K→Diplomacy中选择非敌对 Kingdom 时可提出联盟；`KingdomDiplomacyVM` 检查 Player Clan 是否为佣兵、Influence和`StartAllianceDecision.IsAllowed`后创建决策。决策只有同意/拒绝两个结果；同意调用 `AllianceCampaignBehavior.StartAlliance`。
- `DefaultAllianceModel` 负责适用条件、提案成本、联盟评价和最长持续时间。通过后 `AllianceCampaignBehavior` 保存 Kingdom 对及到期时间，更新双方 AlliedKingdoms，并分发 OnAllianceStarted；结束时移除关系并发 OnAllianceEnded。外交/关系因素是提案评分输入，不是独立个人盟约状态。
- Call-to-War 是已结盟 Kingdom 间单独的一次援战协议，不等于常驻 Alliance，也不等于双方自动进入同一支军团。协议保存 CallingKingdom、CalledKingdom、TargetKingdom 与 EndTime；盟友提出后由 Called Kingdom 的 KingdomDecision 决定接受或拒绝。
- 玩家提出 Call-to-War 的原版入口已在 `LordConversationsCampaignBehavior.AddPoliticsAndBarter` 追到：大地图与盟友领主对话的 Diplomacy 选项中，玩家可提出援战请求。条件要求玩家和对话方分别属于 Kingdom、Player Clan 不是 mercenary、双方处于 Alliance、Called Kingdom 没有同一目标的未决援战提案；候选目标是玩家 Kingdom 当前交战、但盟友尚未交战的 Kingdom。目标重复选项显示 `AllianceModel.GetCallToWarCost`，金币不足时禁用；点击后走 `StartCallToWarAgreement(..., isPlayerPaying:true)`，后续是否对方接受仍由 Kingdom decision 决定。
- 接受时将援战费用按 `isPlayerPaying` 路径从 Hero.MainHero.Gold 或 CallingKingdom 的 CallToWarWallet 转到 CalledKingdom 钱包；创建协议并可延长联盟期限，分发 OnCallToWarAgreementStarted 后通过 `DeclareWarAction.ApplyByCallToWarAgreement` 令 CalledKingdom 与目标进入战争。拒绝时调用相应关系惩罚处理；到期/取消时移除协议并分发 Ended 事件。
- 证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`LordConversationsCampaignBehavior`、`ProposeCallToWarAgreementDecision`、`AcceptCallToWarAgreementDecision`、`AllianceCampaignBehavior`、`AllianceModel`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomDiplomacyVM`）。入口/成本/决议链由v1.4.8.119303源码确认，但援战通知实机显示/接受、协议到期UI和Campaign时间均尚未运行核验。

## C05 王国政策

玩家入口为 K→Policies 类别；`KingdomPoliciesVM` 将 Active Policies 和 Other Policies 分组，切换 Propose/Disavow 模式后选择某个 Policy。若同一 Policy 已有未决 `KingdomPolicyDecision`，按钮执行 Resolve；否则在非佣兵、有 MapScreen 操作权限且 Influence 足够时创建新的 `KingdomPolicyDecision` 并经 `Kingdom.AddDecision` 扣提案影响力、进入 C02 选举。页面会显示政策支持估计与成本；玩家是王国唯一 Clan 时按钮文案为 Enact。

每个 `KingdomPolicyDecision` 提供 enforce/disavow 两个 outcome、选举支持计算和 policy rule check。最终选 enforce 会调用 `Kingdom.AddPolicy(Policy)`，拒绝时不加；对已启用的 Policy 提出相反方向决策时会在结算后 `RemovePolicy`。政策具体收益/限制由 PolicyObject 的相关模型和消费者处理，本节记录决定与挂载路径。

证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`KingdomPolicyDecision`、`Kingdom.AddPolicy/RemovePolicy`、`PolicyObject`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomPoliciesVM`、`KingdomDecisionPermissionModel`）、`Modules/SandBox/GUI/Prefabs/KingdomManagement`政策页面。Policy items全部运行按钮权限和后果、各政策效果模型未逐项核验。

## C06 领地分配

玩家入口：K→Fiefs 页面列出玩家 Kingdom 的 Town/Castle；选择后，可能出现 Resolve、Gift、Give Away 或 Annex/Propose 动作。当前 Hero 为 RulingClan Leader 且拥有该 Settlement 时，Gift 弹窗列出可接收家族，确认后 `KingdomManager.GiftSettlementOwnership` 直接交给选定 Clan，并给双方 Clan Leader 加关系、再走 `ChangeOwnerOfSettlementAction.ByGift`；当前 Hero 是领地所属 Clan 成员但非统治者时，只能确认 Give Away，`RelinquishSettlementOwnership` 建立新的归属决策让王国统治者分配。

若选中的 Kingdom Settlement 属于其他 Clan，页面可显示拟改变所有权的 PreliminaryDecision；其候选“Yes/No”先询问王国是否需要另选所有者，按影响力/权限等禁用条件检查后进入 C02 选举。Yes 的 outcome 会自动建立一条正式 `SettlementClaimantDecision` 并强制到 RulingClan 作为选择者，候选为当前王国所有非佣兵、未消亡、Leader存活的 Clan（排除当前所有者）；其 Merit/支持会考虑现有堡垒领地价值/距离、军力、Tier、是否王族、刚征服情况、Leader特征与关系等。最终决策调用 `ChangeOwnerOfSettlementAction.ByKingDecision`，更新 Town.OwnerClan，刷新可见Settlement/BoundVillage visuals、驻军/Governor及相关MapEvent/Party行为，并发 `OnSettlementOwnerChanged`。

通过围城夺取、叛乱、离开/毁灭Clan、Kingdom决策、Gift/Barter 等不同路径都会进入不同 `ChangeOwnerOfSettlementDetail`，并可能有不同的开放申请、驻军、敌对队伍、关系副作用。AI ProposalBehavior 不是所有领地分配的唯一来源：玩家K页、王国决策、攻城结算和关系变更都可能触发相同Settlement所有者写入。

来源：当前安装 `TaleWorlds.CampaignSystem.dll`（`SettlementClaimantDecision`、`SettlementClaimantPreliminaryDecision`、`ChangeOwnerOfSettlementAction`、`KingdomManager`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomSettlementVM`、`KingdomManagementVM`、`KingdomGiftFiefPopupVM`）。未知项：完整候选评分的所有权重、被玩家按Fiefs实际点击后的界面时序、不同Settlement类型/权限和叛乱/攻城连续事件的完整前后态尚未运行穷举。

## C07 家族加入、离开和叛变

`ChangeKingdomAction` 处理加入/叛变加入、离开/叛乱离开、佣兵加入/离开、建立 Kingdom 与 Kingdom 毁灭导致的离开。身份转换会改 Clan.Kingdom 与 Faction Stance，并可能处理领地/驻军/队伍、佣兵状态、债务和贡金，发 `OnClanChangedKingdomEvent` / `OnClanDefectedEvent`。

玩家离开入口为 K→Kingdom Action：若 Main Hero 是 RulingClan Leader，按钮是 Abdicate，并受 KingdomCreationModel 的 abdication permission 限制；否则是 Leave Kingdom。佣兵会确认结束合约；无领地封臣确认后离开并承担关系影响；有领地封臣需选保留（触发叛乱离开并与旧 Kingdom 开战）或归还领地（避免该战争路径）。

加入服务也有独立的原版领主Conversation入口，不应统称为Barter：`LordConversationsCampaignBehavior.AddPoliticsAndBarter`先提供“I would like to enter your service”对话，适用于玩家未加入Kingdom或已为佣兵、目标是另一Kingdom且双方不在战争状态；再分成两支。佣兵分支由玩家选择“我的剑属于你，给出合适价钱”，可点击条件调用 `FactionHelper.CanPlayerOfferMercenaryService`（含Clan Tier、关系、领地和阵营战争兼容检查），接受后 `ChangeKingdomAction.ApplyByJoinFactionAsMercenary` 并给玩家5点Influence。结束佣兵合约另有Conversation句：需玩家在当前Kingdom服务、与目标领主同一Faction、对方非囚犯且MainParty不在Army；确认会先把Clan当前Influence清零，再执行 `ApplyByLeaveKingdomAsMercenary`。Kingdom管理页结束合约使用不同入口，反编译到的VM只直接提交后一个Action，故不得静默合并两入口。

封臣支系是誓约Conversation，不是generic Barter：玩家可选择向领主宣誓效忠；只有Kingdom领袖能直接授予封臣身份，若当前对话对象不是领袖则会要求/引导玩家去见领袖。可点击条件通过 `FactionHelper.CanPlayerOfferVassalage` 检查Clan Tier、与领袖关系及战争兼容性；接受后 `ApplyByJoinToKingdom`，若从佣兵转封臣则先结束旧佣兵服务，并可能提交入仕奖励/关系/Influence。已确认上述玩家实际入口和核心提交点，但没运行视觉交互；完整Barterables `JoinKingdomAsClanBarterable`、`MercenaryJoinKingdomBarterable`、`LeaveKingdomAsClanBarterable` 是否另有可由玩家主动发起的改投路径仍需逐项核实，不能用其类名推定有第二入口。

加入/离开支持模型会读取统治家族与目标 Clan 的关系、其它成员Clan关系、Culture、领地与军力、WarPartyLimit、最近换阵营时间、可靠性常数及当前战争状态；精确模型分数仍由政治子系统进一步追踪。

K页离境交互与上述Conversation路径是两组入口：`KingdomManagementVM` 根据身份提供Abdicate或Leave Kingdom；佣兵/无领地/有领地分支各自确认，拥有领地时选择保留或归还。加入佣兵、结束佣兵服务、立誓成为封臣的对话链已由 `LordConversationsCampaignBehavior` 定位；其前置、退出代价与UI提交不同，参见本节上方。单独的通用改投Barter仍未追完。

Chronicle Observer 当前不记录 player/Clan `Kingdom` 身份状态或敌友盟约历史；Protocol 没有加入/离开 Kingdom 动作。证据：当前安装 `ChangeKingdomAction`、三种 Clan Kingdom Barterable、`KingdomManagementVM`、`LordConversationsCampaignBehavior` 与 `FactionHelper.CanPlayerOfferMercenaryService/CanPlayerOfferVassalage`；当前为源码调用链证据，UI/对话结果未运行测试。

## C08 王国创建与毁灭

创建边界由 `KingdomCreationModel` 提供：当前 Default 模型要求 Player Clan 独立、至少 Clan Tier 4、拥有至少一个 Town/Castle、队伍及领地守军中有至少100名健康士兵；最多四项初始政策。StoryMode `CreateKingdomQuest` 会用离开王国状态、Clan Tier、主队健康人数与自有堡垒来跟踪任务进度；帝国路线要求 Imperial culture 的堡垒，其它路线可选任意 Town/Castle。任务日志提示条件完成后要与Governor谈话创建王国，但该 Governor 对话的完整UI handler及Sandbox模式通用入口尚未定位。

核心建立入口 `KingdomManager.CreateKingdom` 创建 Kingdom 并设名称、文化、旗帜、家园及初始描述，再经 `ChangeKingdomAction.ApplyByCreateKingdom` 把 Founder Clan 转入该 Kingdom；先前对 Founder Clan 有战争的 Faction 可能由 KingdomCreation 来源自动宣战，初始政策逐个加入，最后发 `OnKingdomCreated`。玩家可选 Kingdom culture 的来源为 Player Clan culture 与自有 Town/Castle cultures。

王位退让与王国毁灭不同：`KingdomManager.AbdicateTheThrone` 在可用 Clan 多于1时改RulingClan并加入强制 KingSelectionDecision；若只剩一个非佣兵 Clan，则让其退出王国并在清理战争关系后毁灭该 Kingdom。`DestroyKingdomAction` 会 Deactivate Kingdom，对成员 Clan 各调用 DestroyClanAction、移除 Clan 集合与 Faction war，并分发 `OnKingdomDestroyed`；每个被销毁 Clan 再处理其 Party、Heroes、Fiefs与 Kingdom 归属。

证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`KingdomCreationModel`、`DefaultKingdomCreationModel`、`KingdomManager.CreateKingdom/AbdicateTheThrone`、`DestroyKingdomAction`、`DestroyClanAction`）、`Modules/StoryMode/bin/Win64_Shipping_Client/StoryMode.dll`（`CreateKingdomQuest`）。未知项：Sandbox玩家创建 Kingdom 的完整可见入口、Governor对话条件/响应、Rebel Clan转正、王国毁灭时跨Clan领地继承的顺序，以及相同条件下源代码/实机任务文本差异未核实。

## C09 叛乱

1.4.8 `RebellionsCampaignBehavior` 在 `DailyTickSettlement` 检查 Town：仅在叛乱系统启用、Settlement不是玩家当前所在点、没有MapEvent/Siege、Owner Clan不是Rebel时运行。忠诚 ≤ `RebelliousStateStartLoyaltyThreshold`（默认25）会切换 Town.InRebelliousState 并发状态事件；真正判定开始叛乱则要求忠诚 ≤ `RebellionStartLoyaltyThreshold`（默认15）、Militia至少达到守军+同阵营在场Lord Party战力的1.4倍，并通过每个有效日Tick的0.25随机检查。围城开始也重新检查Rebellious标志。

叛乱触发后自动建立新Rebel Clan与多名 Hero/Party、分配随机初始Renown、使其与原所有者Faction开战，重置城镇 Loyalty/Food/Militia/Garrison，并分发 OnRebellionFinished；初始Garrison中部分旧守军转为俘虏。新Rebel Clan存在持续天数记录，消亡时清理数据与相关Hero。玩家没有“创建叛军”按钮；可以从城镇状态、通知/日志观察后，以战争/围城行动参与。

证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`RebellionsCampaignBehavior`、`RebelliousStateStartLoyaltyThreshold`、`RebellionStartLoyaltyThreshold`）、`TaleWorlds.CampaignSystem.GameComponents.dll`（`DefaultSettlementLoyaltyModel`）、`KingdomManager` 和 Campaign事件/通知类型。Chronicle Observer当前没有读取Town忠诚/叛乱状态或军民力量用于预警；具体玩家界面通知、战后领地/关系/日志细节未实机验证。

## C10 贸易协定与贡金

Kingdom Diplomacy 的中立对象页可提出 TradeAgreement；UI检查现存协定、佣兵状态、Influence与 `TradeAgreementDecision.CanMakeDecision`，再创建决策并由 Election 决议。Decision生成、支持及成本路径见 C01/C02。遇到来自其他 Kingdom 的贸易协定提议时，`TradeAgreementsCampaignBehavior.OnTradeAgreementOfferedToPlayer` 为非佣兵玩家创建玩家Kingdom决策，佣兵身份则走自动接受分支。

`TradeAgreementsCampaignBehavior` 以 `SyncData` 保存协议列表与结束时间；协议到期、王国毁灭或双方开战时会移除。有效协议期间，拥有启用贸易行为的 Caravan 进入另一签约 Kingdom 的 Town，`SettlementEntered` listener 通过 TradeAgreementModel 计算这次访问利润并累积到协议双方记录。开战终止协议时，若来源为玩家敌对，系统对双方Leader写入-50关系；当写入者是 Main Hero 时另扣 Honor Trait XP，并生成 DishonestBusinessQuarrel 原因的 Reputation LogEntry。收到他国贸易协定提议时，非佣兵玩家走决策流程，佣兵身份的玩家直接接受。

议和贡金由 `MakePeaceKingdomDecision` 决定后交 `MakePeaceAction` 写入 `StanceLink.SetDailyTributePaid(payer, amount, duration)`；直接 `MakePeaceAction.Apply` 默认是0日贡金、0期限。`TributesCampaignBehaviour` 本身只监听 `OnClanEarnedGoldFromTributeEvent`，在末笔支付完成且涉及玩家Faction时投递 TributeFinished MapNotice；每日实际转账/计期代码调用方还未定位，因此分清贡金状态、支付事件和完成通知三个环节。

证据：当前安装 `TaleWorlds.CampaignSystem.dll`（`TradeAgreementDecision`、`DefaultTradeAgreementModel`、`TradeAgreementsCampaignBehavior`、`TributesCampaignBehaviour`、`StanceLink`、`MakePeaceAction`）、`TaleWorlds.CampaignSystem.ViewModelCollection.dll`（`KingdomDiplomacyVM`）。未知项：交易协定对 E 类日常市场价格/供应的完整模型连接、贡金每日转账调用方与提前终止/破产分支尚未逐一运行核验。

## C01-C10 的 Chronicle 现有覆盖

当前 Observer 只暴露玩家 Clan 基础字段及附近队伍的 hostile 标志；不会枚举 unresolved KingdomDecision、候选/支持/投票、War/Peace StanceLink、Kingdom政策或领地投票、联盟/Call-to-War/TradeAgreement、Kingdom创建/毁灭或城镇叛乱状态。AgentProtocol 目前仅用 `IsAtWarAgainstFaction` 检查选定地图目标是否敌对，没有任何 C 类政治外交变更动作。以上覆盖状态来自 `AgentObserver.cs`/`AgentProtocol.cs` 与本地 C# action 列表检查；没有决策、战争、政策、领地分配或协议的运行时功能测试。行为/观察族精确分母留待 W1-M 对 A-L 目录交叉去重。
