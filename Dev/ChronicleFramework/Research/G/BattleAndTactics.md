# G 类研究：遭遇、战斗与战术

适用本体：Bannerlord v1.4.8.119303。本文是 G 域唯一研究资料，按 G01-G10 记录玩家入口、引擎链、原版后果、Chronicle 当前适配和未知。F10已盘点 Campaign 坐镇模拟；本类进一步区分地图遭遇、真实 Mission、战术命令与战斗结算，不重复重写 F 域事实。

## G01 Encounter：接敌、会面和进入战斗

### 玩家入口与状态分支

玩家可在战役地图上接近/点击队伍并进入原生 Encounter；敌对接触也可能由地图追近自然触发。进入后并非所有情况都进入同一“战斗界面”：`DefaultEncounterGameMenuModel.GetEncounterMenu` 根据双方 Party、Settlement 类型、Army、SiegeEvent、MapEvent、当前阵营和海陆等状态选择 `encounter`、`army_encounter`、`join_encounter`、`join_siege_event`、村庄/城堡/城镇外部菜单等分支。无可交战对象时也可能只是营地或场景访问。

普通 `encounter` 菜单的原生选项可能包括攻击、坐镇指挥、试图逃脱、投降、离开、放弃军团；是否可选由原生条件决定。加入他人战斗时则可能要求选择帮助攻击方/防守方、离开或放弃Army；围城与村庄遭遇另有突围、援助、防守、强征/掠夺等专属入口。Army交战还能提供与军团领袖或成员会面、加入/攻击/离开的不同选项。因此 Agent 不能把“接触一个队伍”简化为必然开战。

### 从遭遇到 MapEvent

`PlayerEncounter.StartBattleInternal` 按上下文建立不同的 `MapEvent`：野战、Raid、围城、突围/出击、Hideout、强征志愿者/物资、Blockade或Ambush等。附近队伍能否进入由 `CheckNearbyPartiesToJoinPlayerMapEvent`、`MapEvent.CanPartyJoinBattle` 等规则过滤；所属阵营、Army、战斗事件类别、距离与活动状态都会改变参与者和敌我侧。点攻击只会令原版入口继续到符合上下文的战斗处理，不等于胜负已经产生。

攻击的敌对后果需与“已经处于战争”的遭遇区分。当前 `Helpers.MenuHelper.EncounterAttackConsequence` 与 `EncounterOrderAttack` 都会调用 `BeHostileAction.ApplyEncounterHostileAction`；当主队和对方属于不同Faction、之前不在战争中且 `EncounterModel.IsEncounterExemptFromHostileActions` 未豁免时，原版会对双方Leader关系写入惩罚并调用 `DeclareWarAction.ApplyByPlayerHostility`。前者继续进入Mission，后者继续坐镇模拟，因此是两个战斗处理ACT共享同一宣战副作用，不是另一个可独立点的“Declare War”按钮。源码：当前 v1.4.8.119303 `TaleWorlds.CampaignSystem` 的 `Helpers.MenuHelper`、`BeHostileAction`、`DeclareWarAction`。

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

当前安装 v1.4.8.119303 将MainAgent玩家操作分散到 `CombatHotKeyCategory`、`MissionMainAgentController` 和 `MissionMainAgentInteractionComponent`：`CombatHotKeyCategory` 有移动轴、Attack/Defend、Action/Jump/Crouch/Kick、步行/武器模式、装备槽切换、主副手切换、Drop/Sheath及视角/锁定等输入；`MissionMainAgentController.ControlTick`把移动轴转为 MainAgent movement vector/flags，并根据当前武器和状态处理攻击、防御、装备及姿态输入。`MissionMainAgentInteractionComponent.FocusTick`通过视线/raycast检查Agent、`IFocusable`、`UsableMissionObject`和`UsableMachine`；`FocusStateCheckTick`再按 Action 输入及 reach/permission/vacancy 条件开始或停止使用对象。Formation Orders 是另一条独立的 `MissionOrderVM`/`OrderController` 链，不能把 Formation 下令当作MainAgent身体控制。

本机1.4.8 `CombatHotKeyCategory`与`MissionMainAgentController.ControlTick`进一步确认：`MovementAxisX/Y`持续输入统一写入MainAgent `MovementInputVector`，骑乘时由当前Mount执行运动，因此步行/骑乘是同一位移动作族的上下文分支；Jump发出独立Jump控制，步行时Crouch改变蹲伏flag、乘骑时Crouch走下马/延迟下马分支，ToggleWalkMode切换WalkMode事件状态。手柄`ControlModeToggle`短按切换最近一次选中的Walk/Crouch模式（初始默认Crouch），长按超过约0.22秒打开同一Walk/Crouch选单；只在MainAgent有效、步行、非水中且未使用物件等条件下开放，单人展开期间向Mission加0.25 TimeSpeedRequest、关闭后移除，不推进Campaign时间。它们仍映射`ACT-G03-20/21`，不另算快捷菜单。目录据不同状态结果把Jump、步行蹲伏、WalkMode分列`ACT-G03-03/20/21`，乘骑Crouch仍映射下马`ACT-G03-16`，不按输入键数或上下文别名重复计数。当前只核对Native DLL的静态调用链，动画、移动量及潜行后果未运行验证。

攻击、防御、Kick也不按按键别名合并：Attack输入根据当前weapon usage进入近战/远程对应控制分支，攻击方向写入Agent movement flags；Defend输入写入防御方向flags，启用AutoBlock时向`AutoBlockModel.GetBlockDirection`取方向；Kick只有`KickClear()`或当前骑乘等条件成立才发起Kick控制事件。它们是三种不同动作意图/控制状态，目录分别列`ACT-G03-04/05/06`。源码只确认输入会请求动作，不足以证明击中、挡住伤害、消耗弹药或造成Kick伤害；这些是动作后的战斗结果，须由Mission状态/伤害事件另行观察。源码：本机1.4.8 `CombatHotKeyCategory.Attack/Defend/Kick`、`MissionMainAgentController.ControlTick`、`Agent.AttackDirectionToMovementFlag/GetDefendMovementFlag/KickClear`、`AutoBlockModel`。

Mission可通过`IPlayerInputEffector`在每帧向同一MainAgent控制器附加原生EventControlFlags，这些是任务方强制状态，不是新玩家输入。在本次反编译的Sandbox/Story任务实现中，`DisguiseMissionLogic`首个控制tick只返回一次Walk flag，强制伪装Mission以步行状态开局；随后以每MissionTick的可疑度模型读取可见性/警卫个人空间、玩家速度与旋转、Crouch/Walk、持械、当前动作、`IsUsingGameObject`或对话状态等，累积至阈值会使Disguise Agents进入潜行状态、过近警卫可能开启对话。`CorpseDraggingMissionLogic`则在提起/放下切换时附加Crouch+Sheath0或恢复Stand/Crouch及先前主手武器槽flag；这些自动状态变化已并入`ACT-G03-18`后果，不额外计数。此结果说明同一移动/交互动作族在特定Mission里会被任务模型重新解释，具体警戒阈值与失败/恢复仍未运行验证。

Mission层还允许各`MissionBehavior`经`IPlayerInputEffector.OnCollectPlayerEventControlFlags`覆盖本帧主角控制flag；本机SandBox/Story源码只找到`CorpseDraggingMissionLogic`与`DisguiseMissionLogic`两个实现。尸体拖拽在捡起/放下姿态转换时会追加Crouch+Sheath0或Stand+原主手Wield flag，因此`ACT-G03-18`含自动姿态/装备变化与按旧状态恢复，不只是尸体ragdoll；Disguise Mission在第一个控制tick强制Walk一次，这是场景初始化规则而非玩家ACT。该Mission后续可疑度模型还读取敌我可见/个人空间、移动向量、IsUsingGameObject/Conversation、CrouchMode、WalkMode、是否可使用机器、持械和当前动作类型；实际惩罚/任务结果要按Disguise Mission链核，不从InputEffector本身推断。

这些类型提供了输入/handler事实和上下文门槛，但原始按键数量不是玩家动作族分母：持续移动轴、攻击方向、按住防御、上下马、拾取/启动机关等仍须按持久结果、上下文与失败后果拆分或合并；视角/缩放等不改变世界状态的输入还需与观察控制区分。目录不得把它们概称为已由现有Formation订单覆盖。证据：当前安装 `TaleWorlds.MountAndBlade.dll` 的 `CombatHotKeyCategory`/`Agent`，`TaleWorlds.MountAndBlade.View.dll` 的 `MissionMainAgentController` 与 `MissionMainAgentInteractionComponent`；当前仅静态源码核对，未运行点击/键鼠操作验证。

当前镜头类输入可继续追到本机 `MissionScreen`：`Zoom`按住时改变camera zoom amount/视距；`ViewCharacter`使第三人称视角暂时查看主角；`CameraToggle`改变`Mission.CameraIsFirstPerson`（鼠标输入时可点击切换，非鼠标需保持约0.5秒）；`LockTarget`切换MainAgent的target-lock/look行为。它们直接改变的是本地Mission画面/瞄准状态，不直接改变Campaign世界实体或Party roster，先作为`OBS-G03-01`的视图/目标控制方式记录，不另建普通世界ACT；若AI战斗规划依赖锁定目标，则仍须作为攻击动作的瞄准控制参数核验。对应源码：`MissionScreen.IsViewingCharacter/UpdateCamera/CanToggleCamera/GetCameraToggleProgress`、`MissionMainAgentController.ControlTick`。

Cheer键打开的是径向Taunt/Shout选单，不等同“提高部队士气”：`MissionGauntletMainAgentCheerControllerView`在按键保持/类别选择/释放时控制菜单；选Taunt后单人分支调用`Agent.HandleTaunt(index, true)`，多人分支发`TauntSelected`；选Shout则调用`Agent.HandleBark(index)`或发`BarkSelected`。所追执行链体现MainAgent动画/语音及多人同步，没有调用`BattleMoraleModel`/`MobileParty.Morale`的证据，故Taunt和Bark先按表现结果分列候选动作，不虚报士气增益。执行过程有类别子菜单与4秒Taunt/2秒Bark冷却；具体菜单实际显示、每个cosmetic可用门槛和战斗打断效果仍未运行验证。

装备控制需区分已有槽位切换与拾取地面物品。数字槽/主副手输入经`MissionMainAgentController.ControlTick`调用`TryToWieldWeaponInSlot/WieldNextWeapon`，映射`ACT-G03-08`。`EquipmentSwitch`(U/手柄RB，GameKey 34)由`MissionGauntletMainAgentEquipDropView`消费：短按少于0.3秒调用`OnWeaponUsageToggleRequested`，同一`ToggleAlternativeWeapon`控制映射`ACT-G03-09`；长按打开装备/丢弃轮盘。轮盘里选择另一个装备槽会Wield(`ACT-G03-08`)，选择当前持握槽会Sheath(`ACT-G03-10`)，长按对应方向超过0.5秒会Drop(`ACT-G03-11`)；单人轮盘打开时添加0.25 `Mission` TimeSpeedRequest并在关闭时移除，Campaign时钟不推进。

地面装备由专用`MissionGauntletMainAgentEquipmentControllerView`处理：键盘F/手柄R上键是`Action`(GameKey 13)；焦点为`SpawnedItemEntity`时短按释放要求`Agent.CanQuickPickUp(item)`为真，再经`HandleStartUsingAction`取得，列为独立`ACT-G03-22`。索引`-1/None`由本体按`MissionEquipment.SelectWeaponPickUpSlot`自动选择可替换槽，无有效槽则拒绝；长按F超过0.5秒会开同一装备选择VM，可指定拾取槽。通用`MissionMainAgentInteractionComponent.FocusStateCheckTick`明确排除`SpawnedItemEntity`，所以这是独立装备View提交，不另记通用Use。DropWeapon(GameKey 22)也有短按快丢/长按选槽流程，最终均映射`ACT-G03-11`。上述轮盘/快捷键是装备、切换、拾取和丢弃ACT的别名/参数，不另以UI开合计行为。源码：本机v1.4.8 `CombatHotKeyCategory`、`MissionMainAgentController`、`MissionMainAgentInteractionComponent.FocusStateCheckTick`、`MissionGauntletMainAgentEquipDropView`、`MissionGauntletMainAgentEquipmentControllerView`、`MissionMainAgentEquipmentControllerVM`、`Agent.CanQuickPickUp/GetWeaponToReplaceOnQuickAction`、`MissionEquipment.SelectWeaponPickUpSlot`。

上/下马共用Action键，但结果由焦点Mount身份决定：`MissionMainAgentInteractionComponent.FocusTick`仅把无人骑乘、可达的Mount设为上马目标；若焦点是MainAgent当前坐骑，按Action可交互条件检查（视线俯角、低速等）后，经`Mission.OnAgentInteraction`调用`Agent.Main.Mount(同一坐骑)`，`Agent.Mount`在非Rear状态置`Dismount` flag。骑乘时按Crouch也发起同一最终下马状态；低速时直接置flag，高速或马匹Rear时进入`_autoDismountModeActive`并带后退运动控制，等待速度/动作条件满足再置flag。故上马`ACT-G03-15`与下马`ACT-G03-16`分开；“Crouch”与“Action对准当前Mount”是同一Dismount动作族的不同入口/等待条件，不另计ACT。静态调用链已核；高速移动中断、Mount行为被打断和Mission结束清理仍未运行验证。

Action键对普通Agent还有另一结果路径：当焦点目标不是Mount且不是`UsableMissionObject`时，`MissionMainAgentInteractionComponent.FocusStateCheckTick`调用目标的`Agent.OnUse(MainAgent, boneIndex)`，再由`Mission.OnAgentInteraction`分发到当前Mission各`MissionBehavior.OnAgentInteraction`。若由`MissionConversationLogic`启动对话，这是进入`OBS-J08-01`当前对话视图的入口，不独立计一个World ACT；随后改变关系、接任务、婚姻/政治/交易等效果映射各自的上下文ACT。只有MissionBehavior直接写入了独立Mission状态的分支（如prisoner follow、corpse drag或cover animal movement）才分别列ACT；不能把generic Agent.OnUse入口本身与其下游状态结果重复计数。

当前1.4.8 `SandBox.dll`与`StoryMode.dll`的Mission构造调用点中，Agent互动消费者进一步分出明确场景结果：Campaign Mission的一般NPC talk由`MissionConversationLogic`启动对话；棋桌对手由`MissionBoardGameLogic`委托同一Conversation，所以棋桌入口不重复计Agent互动，但后续选棋/下棋仍是J11行为。`PrisonBreakMissionController`在MainAgent对指定囚犯Hero交互且存活守卫未Alarmed时切换阶段并改变Follow状态，另列`ACT-F12-15`。`CorpseDraggingMissionLogic`在多个SandBox/Story任务加载，玩家对尸体交互后启动ragdoll拖拽、限制自身速度并可能令尸体武器掉落，另列`ACT-G03-18`。`StealthPatrolPointMissionLogic`在对应Story/Stealth任务加载，MainAgent交互未开始移动的CoverAnimal后调用`StartMovement`，另列`ACT-G03-19`。

`Mission.OnObjectUsed`的官方调用者扫描还发现Hideout结果：相关StealthArea内守卫全部清除后，玩家使用`StealthAreaUsePoint`会调用援军生成回调，并让`HideoutAmbushMissionController`进入CallTroopsCutScene状态、启动状态计时、完成当前目标并淡出区域守卫，目录列`ACT-G03-23`。MissionExit结果由`PassageUsePoint.IsMissionExit`提交`Mission.EndMission`，目录列为`ACT-G03-24`；StoryMode的`SneakIntoTheVillaMissionController`另监听MainAgent使用该出口并调用`VillagersInNeed.OnHeadmanRescued`设置救人标志，因此该Quest side effect映射J12但不另算一次Action。

其它本机SandBox对象类还提供可聚焦的专用Action结果。带`ToLocation`的`PassageUsePoint`可在玩家权限允许时改变`GameMenuManager.NextLocation/PreviousLocation`并结束当前Location Mission；门锁条件不通过只显示“门被锁”提示，目录另列`ACT-G03-25`。`TeleportUsePoint`明文允许玩家控制的Agent在未停用、满足不同Lair/Door/Gate距离时使用，按`TargetPointTag`传送至本Mission场景另一位置并FadeIn，另列`ACT-G03-26`。`ShadowingSecureZoneUsePoint`与`DisguiseMissionUsePoint`的目标文案分别为Blend与Steal information，前者让MainAgent执行Idle，二者都经过UsableMissionObject的Use生命周期；活跃的`DisguiseMissionLogic`以共同的`Agent.IsUsingGameObject`标志参与可疑度计算，不区分两种点的世界结果。故先合并为带目标参数的“使用掩护/伪装交互点”候选`ACT-G03-27`；代码没有证明该动作必然窃取任务情报或阻止侦测。`AnimationPoint`/`DynamicObjectAnimationPoint`与`ChairUsePoint`按场景配置使Agent执行姿态/动画，部分可启用配对点并改变局部动画对象；可见性/玩家可用条件及是否产生更深任务结果未全核，暂列同一场景动画目标族`ACT-G03-28`候选。它们在当前目录体现为专用Use子类结果，不再与`ACT-G03-07`通用Use协议重复计数。

类存在不证明当前官方Mission会实例化：`SearchBodyMissionHandler`、`MissionPathGenerationLogic`均在程序集里带有处理方法，但扫描当前SandBox/Story Mission构造调用点未发现二者注册，暂不计可用ACT，保留活动装配未知。部分`ShadowingSecureZoneUsePoint`、`DisguiseMissionUsePoint`和Animation/Chair类型只在SandBox Prefab/编辑器模板中找到定义；Prefab存在不等于当前战役场景放置，也不能用模板数量当玩家行为分母。Teleport及这些专用点在完整当前场景资产中的实际放置仍未穷尽；当前只按源码入口列候选。对其它模组的动态注册也未穷尽。

Multiplayer Mission还有独立于Campaign战斗指令的VoiceChat：`VoiceChatHandler`在voice chat enabled且音频/平台权限允许时，按`PushToTalk`(33)按下启动录音、松开后停录并将压缩音频作为`SendVoiceRecord`发服务器；服务器按接收列表与同队关系转发`SendVoiceToPlay`，客户端再解压播放并更新Peer voice status。未连接网络Mission的单机战役没有这条语音传输路径；该行为不修改Campaign、Army或Mission Agent战斗状态，但属于联网玩家沟通入口。Chronicle没有麦克风输入、语音转录或语音输出适配。

Multiplayer Flag Domination的Class Loadout另有`ForfeitSpawn` (X/手柄R左键)快捷行为：`MissionGauntletClassLoadout.OnTick`在按键释放后调用`MissionMultiplayerGameModeFlagDominationClient.OnRequestForfeitSpawn`并请求服务器执行`ForfeitSpawning`。仅在当前Peer已生成Agent视觉对象、游戏设置启用金币且回合进行中时，服务器移除该Peer的spawn visuals并扣1金币；其他状态下请求无效果。它不是Campaign撤退或普遍的Mission离开，暂列`ACT-G03-29`多人模式候选。源码：当前Native/Multiplayer 1.4.8 `MissionGauntletClassLoadout`、`MissionMultiplayerGameModeFlagDominationClient`、`MissionMultiplayerFlagDomination.ForfeitSpawning`。

Prison Break是F12从地牢菜单启动的自定义Sandbox Mission subtype，而非通常的MapEvent战斗：启动入口/囚犯选择/Bribe提交映射F12 `ACT-F12-13`，成功后的Captivity结束对话映射`ACT-F12-14`。`PrisonBreakMissionController`在单一场景中交替处理潜行接近和警报后的护送/战斗，玩家须使用Use交互俘虏触发跟随，警卫感知和StealthFailCounter会改写结果；它不是进入场景后自动营救。该Mission消费G03通用移动、姿态、武器和交互输入；囚犯跟随是额外的Mission状态提交`ACT-F12-15`，Mission能力是否完整覆盖仍取决于这些共用输入与具体失败/恢复路径，不能把F12启动入口算作完整营救支持。

### Campaign 后果与适配边界

真实 Mission 的战斗时间推进属于局部场景；Campaign世界时间在战斗期间停止。Mission结束后再由Encounter/MapEvent流程应用死亡/昏迷、伤兵、经验、俘虏、战利品、关系/战斗奖励及是否继续战斗；与“坐镇指挥”模拟的伤亡和UI选择路径不应互相替代。Mission本身结束也可能进入下一段连续战斗、俘虏处理或战后 Party/Inventory 状态，而不是立即回到地图。

Chronicle当前可以启动战斗模拟并读取模拟结果，也有Mission撤退逻辑探针；没有针对 Mission 主角移动/攻击/骑乘、编队选择/命令/部署、增援、伤亡提示与 Mission结果的自主动作/观察桥。Mission UI模型和本机结构化状态不能证明Agent已具备3D操作能力。证据：Campaign `PlayerEncounter`/`CampaignMission`、MountAndBlade `BattleMissionStarterLogic`、`DefaultBattleMissionAgentSpawnLogic`、`BattleEndLogic`、Chronicle Observer/Protocol。尚未知：玩家攻击选项到各类Mission starter的完整逐类型路径、实时Mission里每种TAB退出后果、不同BattleSize/模块对实际同时在场人数与增援节奏的影响、Mission结束至MapEvent/Party roster提交之间完整的可视和故障恢复顺序。

## G04 Formation：部队编组、部署和队形

Mission中的 `Team` 拥有多个 `Formation`；Formation 把参战Agent组织成可分开选择与指挥的队伍，记录单位、逻辑/物理兵种类别、领队/队长、队形、目标位置/方向、间距、骑乘、射击等状态。`Formation` 不是战役 Party，也不等于兵种树/Party roster：战役队伍先提供可参战 troop 来源，Mission再生成场景Agent并分配给Team与Formation。

玩家在可部署战斗的 Order of Battle 界面可调整Formation类型、权重、队长/英雄分配和自动部署；开始 Mission 后，还可用Formation选择控件、兵种分类与Orders控制多个Formation。适用性受Mission类型、战斗部署阶段、剩余可参战成员、队伍是否锁定/已有可用兵种影响；至少一个可参战Formation是开始条件之一。围城Mission中的器械/梯队有额外部署及控制对象，不应简化成野战队形设置。

当前1.4.8 `OrderOfBattleVM`源码显示这些交互设置在不同字段上，但类别、兵种Filter与Weight共同定义同一套Troop→Formation部署分配，并经`OrderController.RearrangeFormationsAccordingToFilters`重排Mission Agent；目录把它们作为一个“配置编队兵力分配”行为族，以类别/筛选/权重为参数，不按设置字段机械计数。Captain assignment还会写`Formation.Captain`、Hero Agent所属Formation与旗帜，并记录玩家角色指挥选择；Hero Troop assignment单独把Hero Agent加入Formation但不设Captain，故与Captain分成两个行为族。`ExecuteAutoDeploy`（仅Player General可用）通过Mission部署回调批量分配后刷新Formation与角色，是独立的自动部署行为。`ExecuteBeginMission`收集每个Formation启用的troop filter配置，再经Gauntlet Order of Battle UI callback→`MissionGauntletSingleplayerOrderUIHandler.OnBeginMission`→`MissionOrderDeploymentControllerVM.ExecuteBeginMission`结束部署；攻城分支若有器械未安置会先确认，成功后统一`FinishDeployment`并继续战斗，因此与G08 Siege成功路径去重为同一“结束部署、继续战斗”行为族。

对照G08攻城器械部署控制器，野战OOB Begin与Siege `FinishDeployment`虽入口/额外提示不同，成功后都是关闭部署配置阶段并继续真实战斗；目录去重为一个部署结束动作`ACT-G04-05`，把剩余攻城器械二次确认记录为上下文分支。玩家界面可能增加部署预览、确认、快捷键与输入焦点规则，具体撤销恢复/视觉流程仍未运行核验；直接设置Formation属性不等价于走完VM部署并验证可用阵型。

Formation配置/部署发生在当前Battle Mission生命周期内，不由其本身额外推进Campaign地图时钟。Chronicle目前没有Battle Mission的Formation观察/创建/单位重分配/部署命令，也没有据此控制实际Agents。当前依据：MountAndBlade `BattleDeploymentMissionController`/`DeploymentMissionController`/`Formation`/`FormationAI`，ViewModelCollection `OrderOfBattleVM`、`OrderOfBattleFormationItemVM`、`OrderOfBattleFormationClassVM`、`OrderOfBattleHeroItemVM`；本机1.4.8.119303静态源码。完整部署界面玩家入口、改类/权重/筛选、Captain与Hero Troop指派的撤销/恢复、部署结束与G08 Siege deployment共用的确认边界、不同队伍组成的自动部署结果、Naval差异和输入焦点状态仍需可视/运行验证。

## G05 Orders：玩家在Mission中下达命令

玩家在战斗Mission通过原生Orders UI/快捷键选择Formation、打开Order set并选具体命令；部分命令需光标世界坐标、主角Agent或另一Formation作目标。`MissionOrderVM.PopulateOrderSets`会调用`VisualOrderFactory.GetOrders`，从当前已注册且可用的Provider中采用优先级最高者。当前源码确认的Native `DefaultVisualOrderProvider`把基础界面组织成Movement/Form/Toggle三组；旧版Order Layout改变选项布局/快捷键别名，不应重复计数。SandBox的`HideoutVisualOrderProvider`仅在Hideout Mission启用，其移动组缺少Advance；因此订单集合依Mission上下文变，不可直接用普通战场清单代表所有Mission。

本机1.4.8 Default provider的行为语义包括：Movement组的Move（目标位置）、Follow Me（目标Agent）、Charge（无目标或目标Formation）、Advance、Fall Back、Stop/StandYourGround、Retreat；Form组以同一`ArrangementOrder`字段设置Line/Close/Loose/Circular/Schiltron/V/Column/Scatter，属于参数化队形设置；Toggle组包含Facing（Face Direction需位置/Face Enemy）、Fire at will/Hold fire、Mount/Dismount、单机Formation AI control on/off，以及单独的TransferTroopsVisualOrder。不同热键快捷入口映射回相同VisualOrder，不另建ACT；其参数选项因改变不同状态字段或目标类型而保留。手动 siege weapon DeploymentPoint 操作由MissionOrderDeploymentControllerVM处理，归G08，不重复列入Order。

`MissionOrderVM`管理当前Provider给出的OrderSet/Order列表、Formation选择、快捷键、焦点/选中状态、UI开关和执行回调；`VisualOrder.ExecuteOrder`再通过`OrderController.SetOrder`及`SetOrderWithAgent/Position/Formation/...`将被选Formation的订单更新为原生状态。TransferTroops按钮只开启转编模式；玩家另选目标Formation及数量后点确认，才经`SetOrderWithFormationAndNumber(OrderType.Transfer, ...)`提交，Cancel只关闭模式不移动Agent。单击选择Formation/打开OrderSet属于操作导航而非已提交新战斗命令；每个Orders类行为须按效果字段/目标/可用条件区分。直接调用Controller虽能下原生Order，却绕过UI可见选择、目标条件、快捷键与失败提示；要证明成功，应复观察Order状态及Agent执行，不可把按钮/命令送达当成功。

Mission期间推进的是本地战场仿真，不是Campaign时钟；暂停、部署界面及Mission终止有各自本体规则。Chronicle现有Agent没有战斗中常规Order动作，也没有读取`MissionOrderVM`的当前可选项或Confirmation状态。依据：Native `DefaultVisualOrderProvider`、SandBox `HideoutVisualOrderProvider`、`MissionOrderVM`/`OrderSetVM`/各`VisualOrder`、MountAndBlade `OrderController`与Formation订单Setter；当前Chronicle `AgentProtocol`未实现此族。未知包括其它MissionProvider是否注册、键盘/手柄和重设Order Layout对应视觉映射、目标失效与命令不可用提示、TransferTroops提交/撤销边界及订单执行反馈覆盖；现列出的Action候选仍未完成玩家视觉/运行核验。

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

本机1.4.8 `MissionOrderDeploymentControllerVM`由当前Mission的`DeploymentPoint`/`SiegeDeploymentHandler`填充器械部署点。选择部署点的器械项会按库存数量检查，再对该点执行 `Disband` 或 `Deploy`；这是Mission场景内器械放置状态，不是Campaign SiegeEvent中的制造/建造。Auto Deploy会重算`IMissionDeploymentPlan`，攻城分支自动部署Siege weapon及Team，普通分支调用`DeploymentHandler`。Begin命令如果还有可部署但未安置器械，会先显示“仍可部署器械，是否开始？”确认；接受后执行`FinishDeployment`并关闭Orders toggle。器械逐点部署和Auto Deploy各是独立配置动作；成功确认与G04 OOB Begin Mission去重为统一`ACT-G04-05`，保留攻城时额外弹确认的上下文差别。

攻城/野战Mission中，MainAgent按Action使用`RangedSiegeWeapon`的StandingPoint后，`RangedSiegeWeaponViewController.OnObjectUsed`会为Ballista/Mangonel/Trebuchet添加相应View。MainAgent成为`PilotAgent`时View切入器械视角/锁定视线；鼠标或CameraAxis控制方向与仰角，经`RangedSiegeWeapon.GiveInput`更新器械瞄准。`RangedSiegeWeapon.OnTick`检测PilotAgent的Attack movement flags：Idle状态触发`Shoot`发射当前装载弹药；满足`AttackClickWillReload`时攻击键可触发`ManualReload`进入重装流程。因此分列器械瞄准`ACT-G03-30`、开火`ACT-G03-31`和条件式手动装填`ACT-G03-32`，与G08的器械部署/移动/命令区分。设备是否装弹、点击装填规则、弹种和可用StandingPoint受具体武器/场景资源影响；当前只核对1.4.8静态调用链，未运行画面/射击/伤害与补弹验证。Mission内摄像机和攻击进度使用Mission时间，Campaign日期仍暂停。

Chronicle当前只有围城战略菜单/战后研究和 Mission retreat 拦截；没有攻守器械布置、命令、墙门状态或围城Agent行为观察。依据：MountAndBlade `TeamAISiegeComponent`/`TeamAISiegeAttacker`/`TeamAISiegeDefender`、`MissionSiegeEnginesLogic`、`SiegeMissionPreparationHandler`、`BattleEndLogic`、`DeploymentPoint`、`DeploymentHandler`/`SiegeDeploymentHandler`，ViewModelCollection `MissionOrderDeploymentControllerVM`/`DeploymentSiegeMachineVM`，并与 Campaign `PlayerEncounter`/F08关联。尚未知：当前build每种围城Mission里玩家从菜单到部署到场景的视觉顺序、器械选择/替换/撤下的可视提交与取消边界、Auto Deploy真实部署结果、Begin/Finish deployment时UI退出或失败恢复、不同城/墙缺口/器械和士兵数量的实际spawn矩阵、撤退/守军投降/城门破坏具体胜利条件的全部组合、围城场景的可靠视觉/结构化测试。

## G09 Combat Resolution：伤害、击倒、死亡与战后Roster

Mission中的攻击先经过武器碰撞与 `AgentApplyDamageModel` 计算伤害/修正；生命归零后再由 `AgentDecideKilledOrUnconsciousModel` 判定Killed或Unconscious，并由Mission逻辑移除/标记Agent、记战斗结果、处理战场离场条件。它不是把Agent受击直接转换成PartyRoster数量；Mission战斗结束后的遭遇/Mission结果和MapEvent结算才把伤亡分流为DiedInBattle/WoundedInBattle等队伍结果，俘虏捕获再经过 Campaign action。

Campaign事件结束后 `CampaignBattleRecoveryBehavior.OnMapEventEnded` 对适用的FieldBattle/Siege/SiegeOutside侧进行额外恢复处理，包括符合perk条件的 wounded troop XP、死亡坐骑恢复机会等；标准伤亡Roster与后续治疗仍按 F11/F12 处理。主角或领主的死亡/昏迷还可能由Campaign英雄死亡模型、难度/角色身份条件处理，不可由Mission UI一条伤害消息推断永久死亡。

玩家入口是实时Mission的实际攻击、受击、退出/胜负以及之后原生战后结算；坐镇模拟由另一套Simulation规则。Mission内伤害/濒死不会使Campaign地图时钟并行推进，Mission结束后才按结算链更新战役Roster。Chronicle可观察结算前后MainParty roster及俘虏数，Mission只试探撤退；没有武器输入、命中确认、Agent血条/状态或伤害模型观察。来源：MountAndBlade `CustomAgentApplyDamageModel`、`DefaultAgentDecideKilledOrUnconsciousModel`、`BattleEndLogic`、Mission casualty逻辑；Campaign `MapEvent`、`PlayerEncounter`、`CampaignBattleRecoveryBehavior`、Kill/Prisoner actions。未知：当前玩家设置/外部Mod对伤害和死亡模型的完整重写，Mission Agent到每个Party roster entry的逐项匹配/伤亡提交顺序，英雄濒死/救治/永久死亡的所有条件和中断恢复。

## G10 战斗奖励：贡献分配与玩家收到的结果

胜负确定后，Campaign `MapEvent`按双方基础战斗价值、伤亡/存活、各Party的贡献份额和结果上下文结算；战斗声望、王国影响力、士气、俘虏、缴获物品/金币/战旗等有各自模型和分配路径。`DefaultBattleRewardModel.CalculateRenownGain`将胜方贡献份额乘以胜方RenownValue及乘数，再加入perk/文化效果；影响力还受是否Kingdom faction和对应perk影响；这不是“打赢固定加X”。物品、俘虏和现金分配也会过滤Party类型、参与贡献和目标类别，战后界面操作决定何时把可转移roster/loot正式写回玩家队伍。

实时Mission先由Combat/Mission结果转入 CampaignBattleResult/MapEvent，玩家可能还需依序完成战后Party俘虏/成员处理、Inventory Loot、对话/英雄处置和返回地图；坐镇模拟走同一战役结算框架但不产生即时操控Mission体验。战斗之后的玩家结算界面不会把Campaign时钟当作额外奖励步骤推进；奖励状态随原生Encounter/MapEvent结果提交。具体奖励入口与声望证据、F10奖励分配已在 MAINLINE Tier 1研究记录；本节不重复奖励公式，重点指出玩家面对的是一串依状态开放的战后步骤。

Chronicle现有battleFinish后能够读取部分奖励/roster结果，Harness研究模式曾采集battle renown telemetry；战后Party/Inventory动作仅支持已开放的原生Loot模式，并不覆盖Mission的伤害控制、所有战后选项或真实随机场景统计。依据：Campaign `MapEvent.CalculateMapEventResults/CommitCalculatedMapEventResults`、`DefaultBattleRewardModel`、`PlayerEncounter.GetBattleRewards/DoApplyMapEventResults/DoLootMembersAndPrisonersOfParty/DoLootInventory`、Chronicle `AgentProtocol`及Harness收据。未知：不同类型战斗的玩家奖励项目/提示顺序全矩阵、投降/撤退/援助方/多人Party贡献权重、自然Mission战斗与BattleSimulation奖励差异的重复运行统计、各Mod奖励模型替换后的覆盖与兼容。
