# K 类研究：地图、移动与环境

适用本体：Bannerlord v1.4.8.119303。本文是 K 域唯一研究资料，按 K01-K08记录地图观察/导航/追踪/天气/海路/遭遇/藏身处/匪患。Player移动的时钟与UI契约引用MAINLINE；Party AI和战斗结算引用F/G，本文不重复复制其它域权威事实。

## K01 World Map：地图可见对象与点击

玩家在 Campaign Map通过鼠标/手柄观察图标、悬停实体、选择队伍/聚落、点击地图位置或打开地图菜单。`SandBox.View.Map.MapScreen`接收地图输入，将当前鼠标射线命中视觉实体或合法地形点解析为不同操作；点击玩家主队会清目标并Hold，点击移动Party/Settlement会尝试调用视觉实体的原生 `OnMapClick`，地形点击则走位置导航请求。目标实体即使可见，若无有效导航面/无法构成有效路径也不一定接受移动输入。源码显示有效地图实体点击会把 `MapFollowModifier` 热键状态传给 `OnMapClick`；`MobilePartyVisual.OnMapClick` 在同一导航可达条件下根据该参数分别调用 `SetMoveEscortParty`（跟随/护送）或 `SetMoveEngageParty`（接敌追近）。这两种输入有不同默认AI行为，不能合并；双击配置、鼠标焦点和当前Encounter/地图State也会改变可用路径。

玩家当前看到的是经过地图可视/侦察/模糊距离/百科等规则筛选的信息，不等于全图Campaign对象清单。`IsVisible`、`IsInspected`、图标、悬停详情、ALT兵力信息及百科“最后发现地点”是不同观察入口；其所有字段与实际玩家UI一一映射尚未完整核实，详见MAINLINE Observation contract。玩家点击移动/队伍的时钟行为也以MAINLINE机制表为准：普通移动是原生导航命令，地图点击根据用户配置改变时间档并让Campaign自然运行，不附加Harness快进。

Chronicle对附近队伍只报告半径内最多12项摘要；Settlement局部摘要也不是Campaign Map上的地图标记清单：`AgentObserver`当前仅筛`Settlement.IsActive && Settlement.IsVisible`，再按`max(12, MainParty.SeeingRange)`范围限8项。游戏引擎截图运行`TestResults/20260927-071832/Temp/SettlementOverlayFailure-map.bmp`时，MapState位置为(207.088,386.957)，结构化观察只列Sargot (`town_V1`)；同帧地图则显示周围多个聚落图标。Native数据中Sargot绑定村庄Calioc (`village_V1_1`)在(186.614,391.233)，距主队约20.9个地图单位；W2-F运行检查确认该Settlement可见但被nearby半径滤掉。用户已确认玩家会从大地图进入村庄/聚落互动；因此“未出现在nearbySettlements”不能当作玩家无法选择的证据，也不能用隐藏全局SettlementId代替地图观察。

静态源码核实了地图标记链：`SettlementVisualManager.OnInitialize`为`Settlement.All`建立视觉对象，`SettlementVisual`按`MapEntity.IsVisible`控制Entity绘制；`PartyBase.UpdateVisibilityAndInspected`对Settlement通常以`ISpottable.IsSpotted`控制IsVisible，IsInspected则按与主队距离另算。玩家实际鼠标选择还须由`MapScreen`当前camera ray命中该可见visual，`SettlementVisual.OnMapClick`再检查`IsVisible`及`NavigationHelper.GetInteractionDataForMainParty`。因此“IsVisible地图标记”“IsInspected近距离调查”“当前viewport hit-test”是三个不同门槛。W2-F新增独立的按需只读`mapSettlementTargets`查询，仅含活动且原版IsVisible的Settlement map marker；既有`nearbySettlements`继续保持局部半径语义，普通`state`不重复携带大清单，未发现Settlement不泄漏。观察完整MapScreen知识标记不等于把隐藏Settlement.All直传AI。

## K02 Navigation：路径、可达性与移动模式

当前运行补证（1.4.8.119303）：`TestResults/20260930-023203/Temp/MapSettlementTargetsResult.json`中Native诊断493个active settlements、Observer返回的393个活动且`IsVisible`聚落marker集合完全一致；100个不可见聚落没有泄漏，试图对隐藏藏身处调用`move`被拒，位置/目标/CampaignDay/源存档均不变。`TestResults/20260930-022948/Movement.log`在同一一次性Campaign中从Agent的`mapSettlementTargets`列表选中可见非敌对Sargot，距离6.467，调用`move`后通过Harness独立显式步进让原生地图AI自然抵达`town_V1`的`town`菜单；CampaignDay自然增加0.024日，源存档hash不变、进程退出。此证据连接“地图观察候选→移动命令→自然抵达”；Harness时钟步进不属于`move`动作，不证明玩家鼠标/相机射线的像素级点击命中。

地图点击地点首先经过当前队伍导航类型、位置NavMesh面、陆海地形与可行路径检查；默认 `DefaultPartyNavigationModel.CanPlayerNavigateToPosition`要求有效面、当前/目标陆地等条件，而 `NavigationHelper`提供Land/port/embark-transition路径辅助。有效请求将目标/MoveMode存入MobileParty，之后Campaign地图AI按tick沿可导航路径更新；它不是一次传送。碰到路径无效、目标消失/失明、目标出海、遇到队伍或遭遇时，短期AI可Hold、绕行、逃离或切换Interaction/Encounter状态。

点击队伍视觉实体时，普通点击调用 `MobileParty.MainParty.SetMoveEngageParty`，按住 `MapFollowModifier`调用 `SetMoveEscortParty`；后者写入 `TargetParty`、当前目标位置、导航类型并设置 `DefaultBehavior = EscortParty`，不是敌对接近。地图Screen对两者使用同一有效点击后的 `HandleClickTimeChange`，所以点击时间档副作用来自原版地图点击策略，而不是跟随动作额外快进。

已从本机安装版 `TaleWorlds.CampaignSystem.dll`（v1.4.8.119303）重新反编译核对 `MobilePartyAi.TickInternal` 与 `GetFollowBehavior`：`TickInternal`仅在主队 `DefaultBehavior == EngageParty` 且目标 `IsVisible == false` 时调用 `SetMoveModeHold`；Escort分支进入 `GetFollowBehavior`，它在目标为null或非active时Hold，目标位于聚落时改设聚落导航，否则继续把目标Party位置作为跟随点。此源码没有对Escort检查目标 `IsVisible`。`MobileParty.IsVisible`属性本身仅读写`_isVisible`标记，不能单独解释成玩家的视野/屏幕可见距离。所以普通追近的不可见停步分支有代码依据；Escort的相应分支仍需辨明玩家实际输入和目标状态，再用一次性运行验证。不能只凭类似中文描述合并行为。

原生移动、追击、Hold及时间副作用以MAINLINE Mechanic Contract为准；直接设置MobileParty目标setter仍会跳过 `MapScreen`可视目标条件与点击流程。Chronicle W2-A目前提供 `follow`白名单动作；`TestResults/20260926-200045/Temp/AgentPursuitResult.json`证明可见有效目标、无效目标拒绝、Escort setter结果、Hold和后续追击遭遇。`TestResults/20260926-203358/Temp/AgentPursuitVisibilityResult.json`以原版点击时间模式自然观察45秒（Campaign Day +0.055），目标由7.037距离靠近至0.056，始终留在Chronicle附近队伍观察集中，`DefaultBehavior=EscortParty`和`StoppablePlay`保持；未遇到目标失去附近观察或停步事件。因此该运行仅证明跟随追上目标并持续自然推进，不覆盖真正的失去视野分支。

点击空地图地形点另走位置导航：当鼠标射线取得有效NavMesh面、面间路径存在且允许地图输入时，`MapScreen.HandleLeftMouseButtonClick`调用 `MapState.ProcessTravel`；它会先清`MainParty.ForceAiNoPathMode`，具海上导航能力时会计算海陆/港口Transition与死区目标，再经`NavigationHelper.CanPlayerNavigateToPosition`验证并使用`MobileParty.MainParty.SetMoveGoToPoint` 写入目标坐标；某些海上过渡完成路径还会取消导航Transition。目标不可达/Face无效时不提交移动；但`ProcessTravel`先清ForceAiNoPathMode，所以不能把“没有移动”误作“完全无状态副作用”。UI在ProcessTravel前还有`MapScene.DoesPathExistBetweenFaces`和MapCamera/Encounter条件，直接API调用绕过这些屏幕输入门禁。该操作与点击Settlement（到访交互对象）或MobileParty（Engage/Escort实体）有不同目标语义与抵达后果，不合并为同一Action。只有有效地图点击进入原版 `HandleClickTimeChange`；API本身不改Campaign时间。`CampaignVec2`不仅含X/Y，也需Land/Sea语义；Face由MapSceneWrapper延迟计算。

W2-B仅实现陆地目标：`moveToPoint(X,Y,Surface=land)`在AgentProtocol验证当前是陆上Campaign Map、目标Face及导航模型，随后调用本机`MapState.ProcessTravel`并复现一次地图点击时间档；`AgentObserver`schema 9在主队GoToPoint时输出自身`location.targetPosition{x,y,isOnLand}`，并不枚举其他Party/全图路线。`TestResults/20260926-211402/Temp/AgentMoveToPointResult.json`显示一次性夹具从(207.018,389.419)自然移动至(208.518,389.419)，一步到达；超界目标被拒且玩家位置、目标、时间模式未改，存档哈希不变/进程已结束。此结果只覆盖陆上有效导航和一个无效坐标，不代表海上导航、港口死区、地图屏幕射线或NavMesh地形全覆盖；海上分支须作为独立任务研究验证。

Chronicle现有move/pursue/hold是研究桥，使用指定Settlement/Party ID、目标校验、原版目标setter与地图点击时间语义，再独立等待自然路径/遭遇结果；不代表完整NavMesh/路径故障/海陆迁移或任意地图点击覆盖。证据：`MapScreen`、`DefaultPartyNavigationModel`、`NavigationHelper`、`MobilePartyAi`、Protocol主队动作及MAINLINE机制运行记录。未知：所有陆地Navmesh孔洞/港口/地形障碍/移动速度影响，玩家输入锁定与模型可达性的全部分支，Mods对导航模型与PathDistance的更改。

W2-AC运行补证：`TestResults/20260930-025002/Temp/AgentHoldResult.json`在一次性Campaign中先让主队进入可见Settlement导航，再调用产品`hold`。Hold清除了目标并使`DefaultBehavior=Hold`；`timeControlMode`原始值仍为`StoppablePlay`，但`context.isWaiting=true`。无Pause/advance命令经过4秒自然观察，Party稳定为`isMoving=false`且CampaignDay精确保持91077.387；源fixture hash未变、进程正常退出。此证据只说明当前Stoppable mode下的Hold有效停表，不能推广到Unstoppable mode或玩家双击速度档。

## K03 Tracking：足迹、发现与侦察信息

`MapTracksCampaignBehavior`对符合 `MapTrackModel.CanPartyLeaveTrack` 的移动Party按小时记录行进轨迹；只有位置变化超过阈值并通过track drop检查才生成Track。主队由QuarterHourly tick尝试发现一定半径内的未发现Track：有效Scout/Scouting作用达到模型难度门槛后才标为Detected；Track还受寿命、距离、目标Party规模、夜间、侦察Skill/Perk等影响。玩家未侦察到的Track不应被显示成已知敌人坐标。

已发现足迹的悬停描述具有信息层级：可逐步显示模糊Party Size、经过时间、速度、Mounted Troops、Party Type、Prisoners、Pack Animals、是否敌对、Culture及Party Name；显示的不确定范围会依据玩家Scouting能力修正。这里明确区分玩家通过地图足迹得到的可见情报与全局读取一个NPC Party当前对象状态。证据包括 `DefaultMapTrackModel.GetTrackDescription`和 `MapTracksCampaignBehavior.QuarterHourlyTick`。

玩家通过地图上自动发现的Track悬停读取描述；当前1.4.8 `TrackVisual.OnHover`直接打开Track tooltip。点击调用`TrackVisual.OnMapClick`但该handler返回false，Track没有专用点击效果；MapScreen的Track action按键调用继承的`MapEntityVisual.OnTrackAction`空方法，`TrackVisual.OnOpenEncyclopedia`亦为空。因此本体源码证据目前支持一个被动观察面`OBS-K03-01`，未发现独立的“开始追踪/调查足迹”玩家ACT；地图通用点击回落行为不等于Track专用操作。追踪丢失/过期不代表Party消失。Chronicle Observer的Nearby Parties不是Track列表，不报告最后足迹位置、Detected/追踪状态或每个精度层级。源码未证明悬停或点击会获得Scouting XP；该奖励链仍未知，不据此虚构输入动作。

证据：当前本机v1.4.8.119303的SandBox.View `TrackVisual.OnHover/OnMapClick/OnOpenEncyclopedia`、`MapEntityVisual.OnTrackAction`以及`MapScreen.HandleLeftMouseButtonClick/OnHoverMapEntity`反编译调用链；没有实机视觉核对地图缩放下每个Tooltip字段。未知各面板/ALT轨迹显示条件、Tracking skill具体值到所有精度字段的映射和Track遗失提示尚未全部核实。

## K04 Weather：天气、季节与地图环境

`MapWeatherCampaignBehavior`按天气模型周期更新地图天气节点；`DefaultMapWeatherModel`按位置、季节和Campaign时间计算Atmosphere、雨雪、湿润、温度/风与日照等表现/数据，并提供进入战斗Scene所需的天气参数。默认Map Weather的数据更新周期为约4 Campaign小时并在Weather Nodes间分摊更新；它不是实时气象Agent或独立气候模拟器。Battle Mission的天气效果由Sandbox/Mission weather model转译，Campaign map和实际Mission可能有不同呈现/副作用。

玩家被动通过地图天气与Mission场景看到环境；当前未找到玩家可单独选取/控制World Map天气的操作。不要仅从雨雪外观推断移动速度、粮食、疾病或战斗惩罚，具体效果必须追对应Campaign/Combat model。Campaign时间自然推进参与天气周期；游戏暂停时不应由Chronicle人为更新天气。

Chronicle不观测当前天气、局部雨雪参数、湿润/风、时间与区域Atmosphere，也无天气控制动作。来源：`MapWeatherCampaignBehavior`、`DefaultMapWeatherModel`、`SandboxApplyWeatherEffectsModel`及本体地图天气View；v1.4.8.119303。未知Campaign Weather各环境量是否被Party移动/AI/速度读取，天气图标/地区预测的玩家完整UI入口，各模式/Mod天气更新和战斗天气差异。

## K05 Sea 与 Port：海域导航和船只边界

当前安装程序集中存在 `Ship`、`PortState`、Embark/Disembark、Naval MapEvent/Mission等类型，说明游戏架构拥有海洋/港口/船只数据和过渡接口；这不等于当前原版玩家一定能进行Campaign海上旅行。本机 `DefaultPartyNavigationModel.HasNavalNavigationCapability` 默认实现直接返回false，而 `CanPlayerNavigateToPosition`默认将玩家目标限制在Land/有效Navmesh；实际是否开放海航取决于当前Active模块/替换模型/游戏模式。

玩家入口、UI和操作成本需基于实际启用导航模型确认：若启用海航，目标可能要经Port和Embark/Disembark transition，Party舰队、船员/船只限制、海上Mission遭遇与陆地地图移动均需分开；若活动模块集未启用，则船只类型/海战程序集本身不构成玩家可用入口。当前本机 `Modules`目录未见WarSails模块，但这只是安装情况，不证明其它Mod不启用Naval替换模型。不可把naval对象反编译存在误报成玩家能直接点海面航行。

基础版1.4.8交叉目录将K05标为N/A：`DefaultPartyNavigationModel.HasNavalNavigationCapability`返回false，默认`CanPlayerNavigateToPosition`限制在Land/NavMesh；安装程序集存在Ship/Port/Embark类型不能证明无Naval扩展的玩家可使用这些接口。该N/A仅针对未替换默认导航模型的基础版本，不声称覆盖当前已安装的所有Mod组合。Chronicle现无船队/港口/登离船状态字段或动作。证据：`DefaultPartyNavigationModel.HasNavalNavigationCapability`、`NavigationHelper.GetEmbarkAndDisembarkDataForPlayer`、`Ship`、`PortState`和本机Modules目录未见WarSails。未知：实际启用的模块与运行时model overrides、Naval扩展的玩家入口/舰队条件、启用后路径/天气/时间/海战后果全链；检测到替换模型时必须撤销该N/A并重新加入分母评审。

## K06 Encounter Flow：地图接触与模式切换

地图接敌不是单一战斗按钮。主队通过点击/追近/观察目标进入会面，`PlayerEncounter`及`DefaultEncounterGameMenuModel`按Entity、双方Faction、Army、SiegeEvent、Raid/Settlement及当前Party状态决定切到对话、Encounter、Join/Siege等不同分支；菜单选项的可用条件再决定发起战斗Mission、坐镇模拟、谈判、加入他方/援助/离开/投降。详细Entry与MapEvent结果分见F10及G01-G03。

地图目标视觉点击可自动引发会面或战斗接触，直接API发起 `StartBattleAction`会跳过MapScreen点击时间档和前置UI选项条件。实时Mission时Campaign地图时钟停止，BattleSimulation和WaitGameMenu走另外时钟规则；Chronicle现有地图移动和Encounter/Simulation研究桥以实际状态复核，不能声称覆盖每种Encounter入口。来源：MAINLINE机制契约、F/G唯一研究文档、`MapScreen`与`PlayerEncounter`；特殊兵种/水陆模式输入未知。

### 2026-10-31 Native EngageParty 丢失目标后的等待

`TestResults/20261031-150443/Temp/AgentEngageVisibilityResult.json`以Harness Native fixture验证：在明确暂停 Campaign 后用原版 Native fixture 建立一支距离6、5人的 hostile Looters Party，同时fixture将 MainParty 1→101；随后调用产品 `pursue`，由原版点击时间策略进入 `StoppablePlay`。两个有效地图观察中目标仍是可见Marker/附近Party、主队 `DefaultBehavior=EngageParty`。下一观察目标同时退出Marker和Nearby Party集合，原版状态变为 `targetPartyId=null`、`MoveMode=Hold`、`DefaultBehavior=Hold`、`isWaiting=true`；虽时间模式字段仍为 `StoppablePlay`，目标丢失后8.43秒 CampaignDay 未变化，三张引擎帧中稳定停留在同一地图状态。源fixture hash未变、Host/游戏进程已关闭。该测试证实的是“测试fixture里一次原版追近目标消失→Native Hold/有效停表”的状态链，不是自然Bandit逃跑率、地形截停能力或EYC声望进度。

## K07 Hideout：藏身处发现、接近与清剿

Hideout是地图Settlement/Hideout实体与相关Bandit Party、场景Mission、Wait/夜袭选项组成的活动，不等同于普通地图落单Party。玩家需先在地图情报中发现相应Hideout，再接近/进入其原生Encounter/menu；具体是否可以谈话、等夜间潜入、直接突击、坐镇指挥或派兵结果取决于敌方数量/时间/玩家状态。 `HideoutCampaignBehavior`与`PlayerEncounter`把此链路分发到Mission、BattleSimulation、等待和Loot/伤亡结算。

`DefaultHideoutModel`记录清理后隐藏/重现时长，并影响队伍规模/派兵成功；藏身处战斗的初始营地人数、巡逻、首领和Boss阶段由Settlement与BattleMission逻辑共同控制。K07的3D战斗/伤亡与战后落点分别引用G03/G09和F10的坐镇结果；驻点密度与定期刷新的详细来源在K08。

Chronicle没有地图Hideout视觉发现、夜袭/Wait、队伍部署和Hideout Mission目标/首领状态的完整动作观察；只复用一般Encounter/战斗层部分。Campaign地图等待可能继续自然时间、Mission暂停地图时钟；不可把Mission倒计时视作Campaign日数。证据：`HideoutCampaignBehavior`、`DefaultHideoutModel`、`HideoutEventComponent`、SandBox Hideout Mission controllers以及F/G。未知地图隐匿可见条件、不同主线/文化Hideout变体、围绕NPC Party的具体可用路径和击败后各波/奖励的视觉恢复流程。

## K08 Bandit Density：匪患生成、区域密度与恢复

匪患不是单个定点队伍。`BanditSpawnCampaignBehavior`维护Bandit Clan、各Culture Hideout列表和各Hideout bandit counts；新档阶段生成初始Hideouts/looters/bandits，后续DailyTick可能增加Hideout，夜间HourlyClanTick按当前数量、区域限额和比例生成Looters/Hideout-bandits，Settlement进出也有首领Party生成检查。当前DefaultModel的Hideout Mission人数还可按`PlayerProgress`动态调整。

因此一股劫匪被消灭后世界的补充不是“此队伍固定时间复活”，而是Bandit Clan总量、Hideout infestations、区域/文化、战役推进及spawn限额影响的分布式更新。Looters每种派系有自身数量上限/市场与食物逻辑；Bandit密度与其战斗能力/Party模板、Hideout人数、商队/村民安全和玩家行为都可能相互反馈，具体发生频率需要重复运行基线而不是一次遭遇。

玩家入口是地图观察/跟踪可见Bandit Party或Hideout、追近并进入Encounter；玩家只能看到可见/侦察的信息，不能从某一队伍快照推导全球spawn预算。Chronicle当前NearbyParty输出视距内有限Party摘要，不提供BanditClan总队伍数、Hideout分布/感染状态、目标密度模型或刷出预测；可以用追击/战斗研究桥处理个别遭遇，但不是完整匪患模拟控制器。证据：`BanditSpawnCampaignBehavior`每日/夜间Spawn、`DefaultBanditDensityModel`、`HideoutCampaignBehavior`、F/G队伍/战斗资料、Chronicle Observer/Protocol。未知所有Clan/地区阈值、夜间刷出概率的实际默认值/难度差异、Spawner在现有Mods中的覆盖和自然世界密度长时统计。
