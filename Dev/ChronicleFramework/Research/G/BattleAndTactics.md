# G 类研究：遭遇、战斗与战术

适用本体：Bannerlord v1.4.8.119303。本文是 G 域唯一研究资料，按 G01-G10 记录玩家入口、引擎链、原版后果、Chronicle 当前适配和未知。F10已盘点 Campaign 坐镇模拟；本类进一步区分地图遭遇、真实 Mission、战术命令与战斗结算，不重复重写 F 域事实。

## G01 Encounter：接敌、会面和进入战斗

### 玩家入口与状态分支

玩家可在战役地图上接近/点击队伍并进入原生 Encounter；敌对接触也可能由地图追近自然触发。进入后并非所有情况都进入同一“战斗界面”：`DefaultEncounterGameMenuModel.GetEncounterMenu` 根据双方 Party、Settlement 类型、Army、SiegeEvent、MapEvent、当前阵营和海陆等状态选择 `encounter`、`army_encounter`、`join_encounter`、`join_siege_event`、村庄/城堡/城镇外部菜单等分支。无可交战对象时也可能只是营地或场景访问。

普通 `encounter` 菜单的原生选项可能包括攻击、坐镇指挥、试图逃脱、投降、离开、放弃军团；是否可选由原生条件决定。加入他人战斗时则可能要求选择帮助攻击方/防守方、离开或放弃Army；围城与村庄遭遇另有突围、援助、防守、强征/掠夺等专属入口。Army交战还能提供与军团领袖或成员会面、加入/攻击/离开的不同选项。因此 Agent 不能把“接触一个队伍”简化为必然开战。

### 从遭遇到 MapEvent

`PlayerEncounter.StartBattleInternal` 按上下文建立不同的 `MapEvent`：野战、Raid、围城、突围/出击、Hideout、强征志愿者/物资、Blockade或Ambush等。附近队伍能否进入由 `CheckNearbyPartiesToJoinPlayerMapEvent`、`MapEvent.CanPartyJoinBattle` 等规则过滤；所属阵营、Army、战斗事件类别、距离与活动状态都会改变参与者和敌我侧。点攻击只会令原版入口继续到符合上下文的战斗处理，不等于胜负已经产生。

Campaign时间边界取决于进入的 GameState/Menu：玩家实际进入战斗 Mission 时战役时钟停止；地图等待菜单（例如部分围城准备）可能继续自然推进；遭遇菜单/会面也不能与 Wait menu 的时间规则混为一谈。接敌和创建 MapEvent 本身不是 Agent 隐式 `advance`。F10 记录的 BattleSimulation 使用独立战斗结算进度，不应伪装成 Campaign 日期快进。

### Chronicle 当前适配、证据与未知

Chronicle 有地图 Party 点击/追近入口、通用原生菜单选项读取/选择、战役坐镇模拟 pause/skip/finish/retreat，以及 Mission 内撤退探针；目前没有完整的遭遇类型/菜单迁移矩阵。源证据：本机 `DefaultEncounterGameMenuModel.GetEncounterMenu`、`EncounterGameMenuBehavior.AddGameMenus`、`PlayerEncounter.StartBattleInternal/DoMeetingInternal`、`StartBattleAction`。UI逐步视觉核对、各遇敌状态的按钮条件、离开/投降失败结果和不同 GameState 的精确时钟回执仍未知。

## G02 MapEvent：交战双方、参战队伍与事件生命周期

`MapEvent` 是战役层战斗事件，不等于真实3D Mission。它拥有事件类型、攻击/防守两侧、各 `MapEventParty` 的来源Party、加入次序/贡献/兵力和当前战斗状态；`MapEventSide` 将多个Party组织成单侧战力。遭遇入口通过 StartBattleAction/各 EventComponent 建立对应事件；周边部队是否增援经过可加入规则，而不是所有附近地图图标自动参战。围 siege、raid、sally out、救援/加入等有各自的地图事件类型和后续路径。

玩家选择“攻击/坐镇”后，事件仍需分辨处理方式：真实战斗交给 Mission；BattleSimulation按战斗模型迭代；非玩家地图战斗由 Campaign 仿真周期推进。每条路径都可能有伤亡、溃败、俘虏、队伍离场、贡献分配和事件继续条件；MapEvent状态或一侧败退未必立即完成 Settlement战后流程。详细模拟回合与战后结算引用 F10；本类继续盘点其Mission/战术边界。

玩家地图战斗期间 Campaign 地图时钟不会与 Mission 内时间并行；AI/其他Campaign状态不会因此获得独立多人服务器式时钟。没有战斗中的主动玩家输入并不意味着可以把地图外事件直接当作已经完整执行的玩家战斗。

Chronicle可观察战斗模拟 finished/retreated/MapEvent battle state 等少量字段，并对测试坐镇流程调用原生模拟接口；当前未提供完整 MapEvent 两侧 roster、参战来源/贡献、增援时序或 Mission 与地图事件的全量观察。证据：`MapEvent`、`MapEventSide`、`MapEventParty`、`MapEventManager`、各种 EventComponent、`PlayerEncounter.FindAllNpcPartiesWhoWillJoinEvent`、Chronicle `AgentObserver/AgentProtocol`。未知包括每种遭遇的完整Join过滤矩阵、长战斗增援运行顺序、不同胜负后仍保留的Event/围城状态，以及多Mod替换模型后的差异。

## G03 Battle Mission：场景内真实战斗

### Mission 身体与入口

地图遭遇后，攻击菜单与 `MenuHelper.EncounterAttackConsequence` 接入玩家战斗流程；派生战斗类型决定使用野战、突围/攻城、村庄Raid/防守、Hideout等 Mission 场景。`CampaignMission` 提供不同的 Battle/Siege Mission 开启路径；Mission 中按队伍来源和场景生成双方 Agent/Formation，`DefaultBattleMissionAgentSpawnLogic` 分阶段生成初始部队和后续增援。地图Roster规模、场景可容纳人数与逐波入场并非同一数量。

Mission 内操作通过键盘/鼠标即时控制主角，TAB菜单可打开离场/撤退流程；将领/部队命令则经原生Order UI控制 Formation，而非通过地图Party AI目标。`BattleEndLogic.TryExit` 对离场动作判定其本体结果；不同 Siege攻守状态的离开语义可能是投降或不可撤退，不能只用“Mission结束”推断为安全撤退。当前 Chronicle 的 `missionRetreat` 会检查 Mission 与 BattleEndLogic，读取 `TryExit`，并拒绝把围城守军的 SurrenderSiege 误报为撤退。

### Campaign 后果与适配边界

真实 Mission 的战斗时间推进属于局部场景；Campaign世界时间在战斗期间停止。Mission结束后再由Encounter/MapEvent流程应用死亡/昏迷、伤兵、经验、俘虏、战利品、关系/战斗奖励及是否继续战斗；与“坐镇指挥”模拟的伤亡和UI选择路径不应互相替代。Mission本身结束也可能进入下一段连续战斗、俘虏处理或战后 Party/Inventory 状态，而不是立即回到地图。

Chronicle当前可以启动战斗模拟并读取模拟结果，也有Mission撤退逻辑探针；没有针对 Mission 主角移动/攻击/骑乘、编队选择/命令/部署、增援、伤亡提示与 Mission结果的自主动作/观察桥。Mission UI模型和本机结构化状态不能证明Agent已具备3D操作能力。证据：Campaign `PlayerEncounter`/`CampaignMission`、MountAndBlade `BattleMissionStarterLogic`、`DefaultBattleMissionAgentSpawnLogic`、`BattleEndLogic`、Chronicle Observer/Protocol。尚未知：玩家攻击选项到各类Mission starter的完整逐类型路径、实时Mission里每种TAB退出后果、不同BattleSize/模块对实际同时在场人数与增援节奏的影响、Mission结束至MapEvent/Party roster提交之间完整的可视和故障恢复顺序。

## G04 Formation：部队编组、部署和队形

Mission中的 `Team` 拥有多个 `Formation`；Formation 把参战Agent组织成可分开选择与指挥的队伍，记录单位、逻辑/物理兵种类别、领队/队长、队形、目标位置/方向、间距、骑乘、射击等状态。`Formation` 不是战役 Party，也不等于兵种树/Party roster：战役队伍先提供可参战 troop 来源，Mission再生成场景Agent并分配给Team与Formation。

玩家在可部署战斗的 Order of Battle 界面可调整Formation类型、权重、队长/英雄分配和自动部署；开始 Mission 后，还可用Formation选择控件、兵种分类与Orders控制多个Formation。适用性受Mission类型、战斗部署阶段、剩余可参战成员、队伍是否锁定/已有可用兵种影响；至少一个可参战Formation是开始条件之一。围城Mission中的器械/梯队有额外部署及控制对象，不应简化成野战队形设置。

引擎侧通过 `OrderOfBattleVM` 在部署阶段改变Formation配置/分配，战斗中通过 `Formation.SetMovementOrder/SetFacingOrder/SetArrangementOrder/SetFormOrder/SetRidingOrder/SetFiringOrder` 更新队伍状态；实体Agents之后由Formation AI执行移动与队形。玩家界面可能增加部署预览、确认、快捷键与输入焦点规则，直接设置Formation属性不等价于走完VM部署并验证可用阵型。

Formation配置/部署发生在当前Battle Mission生命周期内，不由其本身额外推进Campaign地图时钟。Chronicle目前没有Battle Mission的Formation观察/创建/单位重分配/部署命令，也没有据此控制实际Agents。当前依据：MountAndBlade `Formation`、`FormationAI`，ViewModelCollection `OrderOfBattleVM` 与Formation配置ViewModels；本机1.4.8.119303静态源码。完整部署界面入口、各选项默认分配规则、不同队伍组成的自动部署结果、Naval/围城Mission差异和输入焦点状态仍需可视/运行验证。

## G05 Orders：玩家在Mission中下达命令

玩家在战斗Mission通过原生Orders UI/快捷键选择Formation或类别、打开命令列表、选中命令，并可能指定位置、朝向、目标Formation或可用攻城对象。具体订单集合会随Mission阶段、选中Formation类别、可用器械、当前输入方式与命令上下文变化，不能预设每个队伍都能使用同一组F键/子选项。

`MissionOrderVM`负责订单集合、快捷键、焦点/选择、UI打开关闭与执行回调；`OrderController.SetOrder`及 `SetOrderWithAgent/Position/Formation/...`再把命令应用给被选中的Formation，更新目标/移动/阵形状态。直接调用Controller可发出原生Order，但绕过UI中的可见选择与条件检查；模拟按键/UI操作则还需处理当前主角控制器、部署状态和输入焦点。要验证命令效果，应看Formation收到的Order及其Agent执行结果，不能只把UI按钮按下算作成功。

Mission期间推进的是本地战场仿真，不是Campaign时钟；暂停、部署界面及Mission终止有各自本体规则。Chronicle现有Agent没有战斗中常规Order动作，也没有读取 `MissionOrderVM` 的当前可选项或Confirmation状态。来源：MountAndBlade `OrderController`、Formation各订单Setter；ViewModelCollection `MissionOrderVM`、Order sets；当前Chronicle `AgentProtocol` 未实现此命令族。未知包括所有默认快捷键与改键映射、键盘/手柄分支、各Mission菜单命令的条件组合、UI和Controller对无效目标的失败/提示差别以及战斗中的实际执行确认。

## G06 Tactics 与战术AI

实时战斗AI是Mission中的队伍/Formation控制，不是 F02 的Campaign Party战略Think。`TeamAIComponent` 持有可用 `TacticComponent` 选项并按周期作出战术决策；战术类有权重/适用条件与 `OnApply/TickOccasionally/OnCancel` 生命周期，能重分配Formation、挑选目标、安排攻击/守点/冲锋/撤退/器械使用等。不同战场类型、攻守方、布阵状态、兵力类别、队形/地形和目标变化会影响可用选项与命令序列；一项Tactic不是每个AI队伍都会照抄的固定脚本。

实际下发过程由具体Tactic调用Formation/OrderController与其行为组件，之后FormationAI和各Agent执行；因此“队伍选择了某Tactic”“Formation收到某Order”“士兵完成移动/攻击”是三种不同证据。玩家可以用Orders影响自己可指挥的Formation，但不能据此断言能直接选择或覆写敌方TeamAI内部Tactic。Campaign地图的Army Attack/Retreat与Mission中的Tactical retreat是不同层次。

Mission战术决策运行在本地Mission tick中；Campaign地图时钟在该战斗Mission期间停止。Chronicle不观察当前TeamAI tactic、候选权重/适用条件、Formation orders、敌我战术状态，也没有战术动作工具。依据：MountAndBlade `TeamAIComponent.MakeDecision/TickOccasionally`、`TacticComponent`及多种 `Tactic*` 类、`FormationAI`、`OrderController`；v1.4.8.119303安装程序集。未知项：各战术权重和具体场景决策阈值、AI与玩家发令的覆盖/冲突规则、改换Tactic前后的状态继承、战斗中途出现Army/增援时的重算顺序及实际Agent行为与内部战术记录的偏差。

## G07 Morale：Mission内士气与溃败

Mission combat士气与战役Party的 `MobileParty.Morale` 是不同状态。Mission侧 `AgentMoraleInteractionLogic` 监听Agent被杀/昏迷/惊慌逃跑，再由 `BattleMoraleModel` 计算双方变化并影响周边Agent；具体影响取决于Agent与队伍、攻击者、状态和场景模型。`BattleEndLogic` 同时监视一方撤退/兵力耗尽等结束条件，单兵逃跑、局部士气下降与整场战斗结束不能等同。该过程推进Mission局部时间，玩家的Campaign地图时钟在战斗Mission期间停止。

玩家没有单独“加/减士气”命令；士气是Battle Mission与Campaign坐镇两条结果链中的状态，不能把战役Party `MobileParty.Morale` 当作Mission formation士气。

用户实玩观察：按F1等打开指挥界面后，己方各编队以五格士气图标显示，每格约代表20点；五格全亮表示约100，敌军和不由玩家指挥的盟友不显示。源码给Agent提供更精确的接口：`MissionOrderTroopControllerVM.Team`绑定`Mission.Current.PlayerTeam`，每个`OrderTroopItemVM.Morale`通过`BattleMoraleModel.GetAverageMorale(formation)`获取整数平均士气。Native `OrderTroopItem.xml`显示Morale图标和`@Morale`整数文本；人的五格读法是士气条的分档，Agent直接使用源值即可。Chronicle目前没有该字段的观察适配。

当前首个AI战斗接入优先使用战役地图的原生坐镇/BattleSimulation流程。Mission里的部署、Orders、F1士气和实时士兵控制仍属于完整产品的观察/行动分母，但不是初始战斗支持切片；不能因为当前暂不接入Mission就把这些玩家可见信息判为不存在或N/A。

坐镇模拟有独立的第二种观察面。`SPScoreboardVM.CreateSimulation`创建坐镇结算面板，`OnTick`在Simulation模式每约一秒分别取 `MapEvent.AttackerSide.GetSideMorale()` 与 `DefenderSide.GetSideMorale()` 写入攻击方/防守方 `SPScoreboardSideVM.Morale`。Native `SPScoreboard.xml`同时呈现双方，`SPScoreboardSideHeader.xml`将0–100分成五段填充；悬停提示标签为“Morale”，显示取整后的数值。它是攻/守双方整侧指标，与Mission F1订单里的单个玩家编队平均士气分属不同信息源和粒度；坐镇Simulation推进自身战斗回合，不等同Campaign日期快进。

Chronicle尚未观察Mission Formation士气或坐镇Scoreboard双方side-morale，也没有影响Mission士气的玩家动作；现有坐镇协议只返回少量战斗状态。证据：MountAndBlade `BattleMoraleModel`、`AgentMoraleInteractionLogic.OnAgentRemoved/OnAgentFleeing`、`BattleEndLogic`；`MissionOrderTroopControllerVM`、`OrderTroopItemVM`、Native `OrderTroopItem.xml`；`SPScoreboardVM.CreateSimulation/OnTick`、`SPScoreboardSideVM.GetMoraleHintStr`、Native `SPScoreboard.xml`/`SPScoreboardSideHeader.xml`；Campaign `MapEvent`/`DefaultBattleRewardModel`。未知：坐镇界面各tick与显示刷新映射、1.4.8各Mission model的伤亡/恐慌参数、围城/海战替换，以及Mission状态映射到Campaign结算。

## G08 Siege Mission：围城场景中的攻守战斗

F08记录 Campaign围城事件、工程/粮食/围困和攻城前后菜单；G08只记录进入围城Battle Mission后的3D边界。攻方/守方使用专门的 `TeamAISiegeAttacker`/`TeamAISiegeDefender` 与 `TeamAISiegeComponent`，场景线路/城门/缺口/梯子影响部队是否能够进出；`MissionSiegeEnginesLogic`和 `MissionSiegeWeaponsController`管理城墙器械、可使用的攻守器械与命令。围城准备阶段和战斗阶段是不同界面；具体可部署器械、初始战术以及实时器械状态由围城状态和场景资源决定。

玩家实际入口是玩家参与攻城/守城并从原生围城选项进入 Mission。攻城方可能先经过部署/器械场景，守城方则有城墙、城门、器械等控制入口；突围、解围军和海上封锁会走专门 encounter/Mission 子类。打破城门/城墙、夺取入口/大厅、守方撤退/援军到达会改变结束条件与后续战斗，不是普通野战Formation命令的换皮。战役世界时间在围城战斗Mission内冻结；Mission结束再进入 MapEvent/Siege Event后果，最终是否攻陷要由 Campaign围城链完成。

Chronicle当前只有围城战略菜单/战后研究和 Mission retreat 拦截；没有攻守器械布置、命令、墙门状态或围城Agent行为观察。依据：MountAndBlade `TeamAISiegeComponent/Attacker/Defender`、`MissionSiegeEnginesLogic`、`SiegeMissionPreparationHandler`、`BattleEndLogic`，并与 Campaign `PlayerEncounter`/F08关联。尚未知：当前build每种围城Mission里玩家从菜单到部署再到场景的视觉顺序、不同城/墙缺口/器械和士兵数量的实际spawn矩阵、撤退/守军投降/城门破坏具体胜利条件的全部组合、围城场景的可靠视觉/结构化测试。

## G09 Combat Resolution：伤害、击倒、死亡与战后Roster

Mission中的攻击先经过武器碰撞与 `AgentApplyDamageModel` 计算伤害/修正；生命归零后再由 `AgentDecideKilledOrUnconsciousModel` 判定Killed或Unconscious，并由Mission逻辑移除/标记Agent、记战斗结果、处理战场离场条件。它不是把Agent受击直接转换成PartyRoster数量；Mission战斗结束后的遭遇/Mission结果和MapEvent结算才把伤亡分流为DiedInBattle/WoundedInBattle等队伍结果，俘虏捕获再经过 Campaign action。

Campaign事件结束后 `CampaignBattleRecoveryBehavior.OnMapEventEnded` 对适用的FieldBattle/Siege/SiegeOutside侧进行额外恢复处理，包括符合perk条件的 wounded troop XP、死亡坐骑恢复机会等；标准伤亡Roster与后续治疗仍按 F11/F12 处理。主角或领主的死亡/昏迷还可能由Campaign英雄死亡模型、难度/角色身份条件处理，不可由Mission UI一条伤害消息推断永久死亡。

玩家入口是实时Mission的实际攻击、受击、退出/胜负以及之后原生战后结算；坐镇模拟由另一套Simulation规则。Mission内伤害/濒死不会使Campaign地图时钟并行推进，Mission结束后才按结算链更新战役Roster。Chronicle可观察结算前后MainParty roster及俘虏数，Mission只试探撤退；没有武器输入、命中确认、Agent血条/状态或伤害模型观察。来源：MountAndBlade `CustomAgentApplyDamageModel`、`DefaultAgentDecideKilledOrUnconsciousModel`、`BattleEndLogic`、Mission casualty逻辑；Campaign `MapEvent`、`PlayerEncounter`、`CampaignBattleRecoveryBehavior`、Kill/Prisoner actions。未知：当前玩家设置/外部Mod对伤害和死亡模型的完整重写，Mission Agent到每个Party roster entry的逐项匹配/伤亡提交顺序，英雄濒死/救治/永久死亡的所有条件和中断恢复。

## G10 战斗奖励：贡献分配与玩家收到的结果

胜负确定后，Campaign `MapEvent`按双方基础战斗价值、伤亡/存活、各Party的贡献份额和结果上下文结算；战斗声望、王国影响力、士气、俘虏、缴获物品/金币/战旗等有各自模型和分配路径。`DefaultBattleRewardModel.CalculateRenownGain`将胜方贡献份额乘以胜方RenownValue及乘数，再加入perk/文化效果；影响力还受是否Kingdom faction和对应perk影响；这不是“打赢固定加X”。物品、俘虏和现金分配也会过滤Party类型、参与贡献和目标类别，战后界面操作决定何时把可转移roster/loot正式写回玩家队伍。

实时Mission先由Combat/Mission结果转入 CampaignBattleResult/MapEvent，玩家可能还需依序完成战后Party俘虏/成员处理、Inventory Loot、对话/英雄处置和返回地图；坐镇模拟走同一战役结算框架但不产生即时操控Mission体验。战斗之后的玩家结算界面不会把Campaign时钟当作额外奖励步骤推进；奖励状态随原生Encounter/MapEvent结果提交。具体奖励入口与声望证据、F10奖励分配已在 MAINLINE Tier 1研究记录；本节不重复奖励公式，重点指出玩家面对的是一串依状态开放的战后步骤。

Chronicle现有battleFinish后能够读取部分奖励/roster结果，Harness研究模式曾采集battle renown telemetry；战后Party/Inventory动作仅支持已开放的原生Loot模式，并不覆盖Mission的伤害控制、所有战后选项或真实随机场景统计。依据：Campaign `MapEvent.CalculateMapEventResults/CommitCalculatedMapEventResults`、`DefaultBattleRewardModel`、`PlayerEncounter.GetBattleRewards/DoApplyMapEventResults/DoLootMembersAndPrisonersOfParty/DoLootInventory`、Chronicle `AgentProtocol`及Harness收据。未知：不同类型战斗的玩家奖励项目/提示顺序全矩阵、投降/撤退/援助方/多人Party贡献权重、自然Mission战斗与BattleSimulation奖励差异的重复运行统计、各Mod奖励模型替换后的覆盖与兼容。
