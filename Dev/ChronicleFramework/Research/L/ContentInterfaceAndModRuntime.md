# L 类研究：数据内容、玩家界面与Mod运行边界

适用本体：Bannerlord v1.4.8.119303。本文是 L 域唯一研究资料，按 L01-L13 区分游戏内容数据、原生玩家界面和Mod引擎接入。开发期Harness不属于L类玩家系统，不在本文作为产品入口研究；现有玩家行为的功能细节分别交由A-K资料。

## L01 XML 数据：对象与静态内容定义

官方模块的 `SubModule.xml` 通过 `<Xmls><XmlNode><XmlName id=... path=...>`声明内容类别及其数据资源，例如Items、NPCCharacters、Settlements、Factions、GameText、SkillSets、CraftingPieces等，并可约束所含GameTypes。加载时数据进入对象/内容管理器，再由Campaign、UI、Mission及模型引用。XML中角色、兵种、物品、聚落或文本的单项定义不是运行中的完整Hero/MobileParty对象。

玩家没有单独“打开XML”游戏入口；文化、兵种、商店、任务文本、菜单选项等界面与世界结果是数据被加载后间接显现。改动原始XML改变的是模块内容数据，不等于执行一次原生玩家动作；错误ID、引用或内容类别会导致加载/构建失败。Campaign时钟在模块加载/内容读取时未运行，内容本身不会推进游戏时间。

当前源码/资源证据：Native/SandBox的 `SubModule.xml` 与 `ModuleData` XML、`Module`/`MBObjectManager`类。Chronicle玩家动作不编辑游戏XML；这些定义的游戏对象副作用按相应A-K类别研究。未知：所有XML类别的GameType条件/合并优先级、多个模块对同一对象的重复ID冲突和实际加载次序；不从某个文件名推出完整对象生命周期。

## L02 XSLT 覆盖：非破坏性数据变换

本机安装的非官方 `HarvestAndProduction` 模块包含与其XML资源同名的XSLT，使用identity template复制未匹配内容，并针对WorkshopType选择性改写/新增Production节点；这证明确有现成模块采用XSLT作为XML内容改写方式。该样例是本机文件证据，不证明所有模块都使用相同合并协议，也不代表它在所有1.4.8模块集合中兼容。

XSLT没有玩家单独可见的游戏动作；其结果应在模块解析后体现为生产/对象数据。多个模板匹配同一节点、节点顺序、身份模板、加载先后及输出验证都可能影响结果；直接删除官方文件、XSLT变换和运行时Harmony修改是不同技术路径。此过程本身没有Campaign时钟副作用。

证据：本地该模块 `SubModule.xml`对WorkshopTypes资源的声明及 `ModuleData/sandbox_spworkshops/spworkshops.xslt`。当前安装官方Native/SandBox未检出 `.xsl/.xslt`资源；游戏是否对每种扩展来源自动执行、具体变换与XML merge优先级没有从当前解析流水完整反编译，故此处只确认样例存在，未宣称完整加载合同。Chronicle没有XSLT运行时玩家界面。

## L03 Game Menu：条件选项、等待和状态切换

Campaign原生菜单由 `GameMenuManager`及`GameMenu/GameMenuOption`构成；`CampaignGameStarter.AddGameMenu/AddGameMenuOption`声明菜单ID、文本、Init、Condition、Consequence、离开类型、顺序/重复项。玩家在Encounter、Settlement、Hideout、Captor、Quest、Incident等不同上下文看到动态菜单；按下同一显示文本不保证相同内部ID或效果。菜单Condition会根据当前Campaign对象、身份、权限、资源、任务状态重新计算，选项可能Disabled或消失。

普通菜单项会调用Consequence和切换menu/game state；`AddWaitGameMenu`另有Tick/Duration参数并由原版Wait逻辑管理Campaign时间。UI调用会显示选项、禁用解释、离开提示、过渡和Cancel行为；直接执行consequence或switch menu可能跳过条件/文本/UI cleanup。时间行为取决于菜单是否Wait及宿主GameState；不能让普通menuSelect默认快进。

Chronicle `observe`可输出当前GameMenu与动态选项条件；`menuSelect`只选当前实际存在且enabled的菜单/选项并重验ID。证据：`GameMenuManager/GameMenuOption/MenuCallbackArgs/CampaignGameStarter.AddGameMenu*`、MAINLINE菜单/等待契约与AgentProtocol。未知所有官方/Story/Mod菜单玩家路径及每个选项的切换和时钟副作用总分母，必须在对应J/F/D类别逐项研究。

## L04 Dialogue System：条件句、token和对话后果

对话Flow可由XML/Dialogue Resource或`CampaignGameStarter.AddDialogFlow/AddPlayerLine/AddDialogLine`等运行时注册；每句保留输入/输出token、Condition、Text、clickable condition、Consequence、优先级和Persuasion option provider。`ConversationManager`按当前角色、标签、关系、身份、任务/Encounter与token上下文筛选可用句子。对话界面显示的是此时真实开放句，不是为Hero固化的一张选项清单。

玩家通过地图队伍会面、聚落Notable、Party/俘虏、任务和Mission等入口开始不同ConversationFlow；选择句后可能改Hero/Clan/Party状态，开始Barter/Persuasion/Quest或切换到Mission/Scene。UI处理开场/发言者/动画/Continue/离开流程，直接 `ConversationManager.DoOption`只对当前有效可选项有意义；手调其Consequences会绕过Flow条件和结尾清理。Dialogue/Encounter时钟与Wait菜单区别见MAINLINE和J类。

Chronicle目前有研究性 `dialogueSelect`与`dialogueContinue`，基于当前可见选项并拒绝失效Option，但不扫描全部注册Flows或合成未出现选项。证据：`ConversationSentence/ConversationManager/CampaignGameStarter.AddDialogFlow`、Map/Scene conversation调用点、本地 `AgentProtocol`及J类。未知全局Flow去重目录、优先级相撞顺序、模组增加条件句的合并效果、不同Scene开场和中断恢复。

## L05 Encyclopedia：百科与回看信息

百科以页面/条目/筛选构成对象浏览系统；玩家此前确认N键可以打开总表，并从Hero页面看状态和个人日志。`EncyclopediaManager`/PageViewModel通过注册的Page/Data provider生成Hero、Clan、Kingdom/Faction、Settlement、Unit、Concept、Ship等条目，按可见/已知条件提供Last Seen、关系和历史字段；地图可见性与百科永久知晓不能混为一谈。具体页面字段依Page与查询源，不是所有实体的完全本地实时状态。

N/百科交互通常只改变当前界面/筛选/书签，不写Campaign主体状态或推进时间；点击地图链接可以让相机定位目标，也不必然代表Agent应该获得远处即时坐标。UI页面注册或直接读取百科模型不等于体验了玩家当前有限情报。Chronicle目前没有百科全库/筛选历史/页面导航支持；其附近party摘要不能替代N百科所有页面。证据：本机 `EncyclopediaManager/Page`、多个DefaultEncyclopedia页面、角色历史来源B07；用户确认的N键入口。未知不同身份/探索条件的全部可见字段、玩家未发现的对象百科条目隐藏规则及N界面逐页视觉覆盖。

## L06 Notifications：地图通知、QuickInfo与场景弹窗

事件消息有多个出口：`MapNotification`通常保存于CampaignInformationManager，由MapNotificationVM按通知类型创建条目/定位行为；QuickInformation/Inquiry是短提示/请求；SceneNotification播放人物/家庭等演出；Quest JournalLog和事件日志是回看数据。`DefaultNotificationsCampaignBehavior`订阅各Campaign事件后创建通知，但通知出现本身不应被当成事件状态已完成。

玩家点通知可能打开任务/决策/百科、定位目标或展示演出，Dismiss也可能只移除提示；NPC/事件真正后果应从对应Action/Quest状态验证。部分Notification/弹窗会锁定或遮挡地图输入，其他短消息不一定停时钟，需逐类型确认。

Chronicle当前Observer没有Notification queue/已读标记/待处理调查/场景弹窗字段；J07已有通知系统消费者盘点。证据：`CampaignInformationManager`、ViewModelCollection `MapNotificationVM/MapNotificationItemBaseVM`、Sandbox `DefaultNotificationsCampaignBehavior`。未知每类菜单点击/过期/重复推送/离线恢复和GameState锁时钟策略全矩阵。

## L07 Scene 与 Mission：战役场景实例化

玩家从地图进入聚落、藏身处、会话/任务互动或战斗时，Campaign对象/WorldMap状态切换为相应Scene/Mission交互。进入后按Scene资源、地点模板、MissionInitializerRecord、MissionLogic和Agent数据构造实际场景；离场/任务完成经各Mission结束逻辑返回Campaign/Encounter/GameMenu并提交相应后果。Campaign层的Settlement/Hero/Party对象与Mission内的Agents、Formations、Scene props不是同一生命周期对象。

玩家通过场景内移动、交谈、用物、战斗、控制编队等真实输入行动；实际Mission入口和不同离场结算分别见D/J/G/F。一般单机Mission内Campaign地图时钟停止，Mission的本地dt运行；地图Wait/菜单不能统称为Scene Mission。直接创建/结束Mission会绕过玩家进入点、场景启动行为和Battle结果提交链。

Chronicle已判定若干GameState/Mission上下文并验证过特定Battle Mission retreat；目前另有仅供Startup Town/Tavern Location Mission使用的短输入和同场景原生导航，不是通用3D操作能力。W2-D早期酒馆入口运行`TestResults/20260926-225650/TavernMission.log`通过：不使用桌面键鼠，从Campaign Map自然抵达萨哥特，选择Town菜单`town_backstreet → town_tavern`，等待Mission.MainAgent激活；Campaign时钟为Stop、附近样本是非Notable Wanderer。引擎截图确认进入酒馆，但未验证Notable/Focus/Action/Conversation。

这些运行只证实对应菜单→Location Mission实例化链和附近Agent映射；不证实任务对话。Town菜单的实际交谈入口需按当前Issue位置数据选择；地图门菜单不等价于任务主人已出现。未知完整Scene转场/同Mission恢复矩阵，以及动态Notable进入场景的条件。

本机Native `TaleWorlds.MountAndBlade.View.dll`反编译`MissionMainAgentController.ControlTick`显示原版每帧读取MovementAxis并写入MainAgent的`MovementInputVector`；`TaleWorlds.MountAndBlade.dll`确认该属性有公开setter。早期直接设置向量的测试虽然回执成功，位置却未变（`20260927-232619`）；运行与反编译共同定位到原版ControlTick会覆盖一次性写入。当前受限Harmony补丁仅在有效短lease期间、且原版ControlTick执行后覆写该值；随后Town/Tavern测试已验证实体移动和到期清零。输入仍需有界并逐步重观察，不能靠持续输入让主角失控。原版`MissionMainAgentInteractionComponent.FocusTick/FocusStateCheckTick`负责更新视线命中和Action门禁；直接调用`Agent.OnUse`会跳过前面的视线/焦点测试，不能当作玩家交谈成功。

W2-D后续运行在`MissionMainAgentController.ControlTick`加了受限Harmony postfix：仅当存在同一个MainAgent的短时输入lease时，原生输入控制器先执行，随后在该tick尾部写入有界`MovementInputVector`；lease最多0.5秒，到期由Protocol清零；场景守卫限`MissionMode.StartUp`且SceneName包含`tavern`或`_town_`，不会把它作为战斗输入扩展。`TestResults/20260926-234252/Temp/TavernMissionResult.json`实际复核：deterministic-only测试Provider依据Mission观察到的MainAgent LookDirection和附近Hero位置，计算一小步`missionInput`，持续0.35秒后MainAgent移动0.897游戏单位，目标距离3.039降至2.142；向量自动清零、后续位置漂移为0、Campaign Day与Stop时间不变，fixture/hash与进程清理通过。该样本只证实一位附近Wanderer的单步接近，不是Notable/Issue目标，也不是模型自主完成路线。不得直接调用`Agent.Position`瞬移，也不能拿`missionInput`回执代替移动状态验证。

Observer schema 19提供有限`nearbySceneAgents`：只枚举当前Mission中Human Agents在MainAgent周围12场景单位内的阵营/位置/职业/Notable标记及本次Mission临时`AgentIndex`，不枚举整场景Agents。这个球形邻域**不是**屏幕视线/无遮挡判断；与之分开，`mission.nativeFocus`直接读取`MissionMainAgentController.InteractionComponent.CurrentFocusedObject`，是该原生视线射线当前命中的对象；若焦点为Agent，`isInteractable`按FocusTick相同的`Agent.CanInteractWithAgent`判定返回原生可交谈状态；`mission.navigation`只回报当前AgentNavigator路线状态/临时目标。城镇中心的初始快照即便Mission有142个活动Agent，主角门外的本地12单位名单仍为空；因此必须让AI移动后重观察，不能在初始状态泄露整镇人物列表，也不能把球形列表直接称为“玩家正在看见”。 Campaign菜单`availableMenuOptions`提供原版`GameMenuOption.OptionQuestData`的数值和枚举名，反映菜单条件执行后的Issue/Quest标记，便于识别当前入口是否有关联的任务状态。 Harness工具另有`harnessMissionDiagnostics`，仅在一次性visual-capture临时运行中查询当前Location Mission全体已激活Notable/Issue标记/距离，用于诊断场景生成；这个全场景列表只写Harness收据，不进入Agent状态快照或DecisionLoop白名单。

导航尝试核实了MainAgent控制模式边界。`Sandbox.AgentNavigator.SetTargetFrame`在1.4.8会调用`Agent.SetScriptedPositionAndDirection`并在`Tick`中检测位置/朝向到达。首次对仍处于Player Controller的MainAgent设置脚本目标，状态为`GoToTarget`但8秒位置未变化（`TestResults/20260927-024449/Temp/TownCenterMissionResult.json`）。当前`missionNavigateToAgent`只支持Startup Town/Tavern Location Mission：目标必须是最近12单位观察里的有效非敌Agent且原版NavMesh报告可达；短时把MainAgent交给AI Controller，最多8秒，抵达/超时/取消/场景变化时清目标并尝试恢复原Player Controller。Tavern运行`20260927-030716`对Townsman目标实走0.837单位（2.224→1.435），控制器恢复、Campaign Stop、存档未变。Town Center运行`20260927-031458`对当前局部Townsfolk实走3.507单位，导航返回`arrived`并恢复Player Controller；Campaign Stop、fixture未变、进程正常退出。后一条证明本Town Center区域的局部原生寻路有效，不证明任意障碍/全镇路线或Notable交谈。

Town Notable W2-D运行`TestResults/20260927-014511/Temp/TownCenterMissionResult.json`与菜单源码确认入口：Town `town_streets`→`center`会按center Location附加Issue/Quest位置数据并进入`vlandia_town_e` MissionState。新档样本在镇门外生成，初始局部12单位内没有Human Agent；Campaign停时，确定性Provider做32次≤0.35秒的本地轴输入，主角累计真实移动18.989单位、输入会清零且存档不变。此测试只算探索/感知基线，不算任务人选已发现。不同Town中心样本先后观察到garrison Soldiers和Townsfolk，仍未找到Local Notable/Issue owner。相机bearing公共setter的一次运行将bearing从2.221改到2.748，但FocusedObject仍为空；修改bearing不是命中Focus的等价证明。之后`TestResults/20260927-031458/Temp/TownCenterMissionResult.json`用导航器对当次局部Townsfolk实走3.507单位并到达1.435范围内，证明该Town Center区域局部NavMesh导航已能驱动主角；它不证明穿越任意城门/障碍，也未找到Notable或对话。当前剩余门槛是获得真实Notable样本后验证Focus和原生对话；不要把本地移动、地图Issue提示或全场景对象读取当作完成。

Observer schema 19把当前菜单项的原版`GameMenuOption.OptionQuestData`作为`questMarkerFlags`与`questMarkerNames`输出。菜单VM `GameMenuItemVM.InitializeWith`会把同一Flags转换成玩家菜单的`QuestMarkerVM`，所以这是原版任务标记数据，不是Agent自己推算的可能性。运行`TestResults/20260927-033506/Temp/TownCenterMissionResult.json`实际读到Sargot `town_streets`=`AvailableIssue`（数值1）；这证明该保存样本的镇中心存在可用Issue标记，但不表示已看到Issue主人。

进一步路线测试`TestResults/20260927-034201/Temp/TownCenterMissionResult.json`在44次≤0.35秒输入后从门外墙角侧移到城门口，局部12单位观察到一名非Notable Townsfolk。`missionNavigateToAgent`按下令瞬间的NPC位置设NavMesh目标，结束靠近旧坐标约1.41单位后，NPC已移动到门另一侧、当前距离约6.39；截图的原生Focus为`CastleGate`而非NPC。Campaign时钟保持Stop、fixture hash不变、控制器恢复、进程清理通过。因此原生寻路确实将主角移到城门口，但单次“到达目标快照”不等于追上移动NPC；接下来必须重观察更新的本地目标并继续路径，且穿门、Notable/Focus/Conversation仍未知。

`TestResults/20260927-035523/Temp/TownCenterMissionResult.json`在同一测试路线44步后进入城门道，但附近12单位内无NPC，Campaign时钟保持Stop；`TestResults/20260927-040042/Temp/TownCenterMissionResult.json`把路线延长至52个短步后，于局部观察到瓦兰迪亚新兵（非Notable），原生导航实走3.724单位、终点距目标1.42。配套原始状态`TestResults/20260927-040042/Temp/TownCenterMissionNativeFocusState.json`显示原生CurrentFocusedObject就是该Agent（AgentIndex 36），游戏截图显示原版`F 交谈`提示；未按F、未启动Conversation或Quest。所有运行均恢复Player Controller、Campaign保持Stop、fixture hash不变且进程正常关闭。这验证本地非Notable角色的物理接近+原生Focus提示；Notable和任务对话仍未实现。


W2-D核验的Settlement Characters overlay人物上下文项，原生代码名为`Conversation`，但本机Native UI字符串`str_menu_overlay_context_list.Conversation`映射到`toK51MD4`，中文显示“造访”。StoryMode官方教程`VzE9aVBh`也说明：顶栏重要NPC头像菜单选择“造访”。因此用户描述的地图人物头像“造访”与W2-D目标式Conversation是同一玩家目标式入口，不应重复建立第二个产品动作/Issue。用户补充的场景结果是进入相应NPC附近；后续由SandBox `MissionConversationLogic`以目标Hero启动原生Conversation。

W2-D测试通过协议调用同一Native路线，在Settlement overlay选择目标Notable、进入其Location Mission并自动开始该Hero对话；它没有模拟鼠标点击/菜单焦点动画，但保留原生`OnPlayerStartTalkFromMenu`及目标式Mission创建/Conversation语义。此前“进center按固定方向走数十步找任务人”的测试路线被目标式入口取代，不再重复运行。另需保留边界：overlay中出现Issue marker不代表Quest一定可接，具体Quest仍受Issue条件控制；W2-E目前仅证明不满足锻造等级时被原版拒绝，成功接取分支仍未验证。

Observer schema 19只在当前GameMenu实际带Characters/Characters+Parties overlay时返回`settlementOverlayCharacters`，成员筛选直接复用本体`MenuLocations + WillBeListedInOverlay`，questMarkers调用本体`CampaignUIHelper.GetQuestStateOfHero`。CLI动作`talkToSettlementHero(HeroId)`仅接受该当前overlay名单中的Hero，重验Settlement归属和原生TalkPermission；UI无权限回调时沿用原VM默认可用语义。操作通过原生OnPlayerStartTalkFromMenu/targeted LocationMission链，不直改Issue/Quest。Harness全场景Notable诊断是QA专用，绝不进入普通Agent观察或Action allowlist。

运行`TestResults/20260927-052705/Temp/SettlementOverlayConversationResult.json`：Sargot overlay返回五名角色中的唯一Issue Notable“大拳头”维拉特鲁德及`AvailableIssue`“特殊武器订单”；`talkPermissionWasReported=false`，和原VM“无回调时默认enabled”逻辑一致。目标式Talk调用后进入`center` Mission；Conversation partner ID/name与overlay目标一致，自动显示原版问候句和三项可点击回复。Campaign时钟保持Stop，Quest列表仍为0，源档哈希不变且进程正常关闭；`SettlementOverlayConversation-frame.bmp`直接显示目标NPC和原版对话界面。此为真实Notable Conversation进入的通过证据，不证明Quest已接受或解决；Issue链下一步由J02/W2-E处理。

## L08 Localization：字符串与玩家文本呈现



UI/对话/日志常通过稳定String ID、语言表、`TextObject`变量和复数/条件格式化生成文本，而不是将最终中文/英文硬编码成世界对象状态。Module通过Languages/字符串XML提供目标语言文本；运行时TextObject将当前上下文变量（Hero、金币、数量、目标等）注入同一Localizable string。缺失ID、format变量或语言文件/模块优先级冲突，可能导致占位文本/回退文案而非状态行动失败。

玩家通过每个菜单/Tooltip/Dialogue/Notification实际看到本地化结果，但文本可能是摘要/提示，不能当成结构化真值。语言包选择不是Campaign动作，不推进世界时钟。Chronicle协议对部分文本只返回当前客户端 `TextObject.ToString()`显示结果，也会保留数值/稳定ID，模型不得从翻译词义逆推枚举状态。证据：Native/Sandbox/StoryMode Language XML、`TextObject/GameTexts`及个别Dialogue/Menu VM。未知完整语言fallback/模块覆盖顺序、简繁中文资源完整度、文本变量被Mods覆盖时的格式行为。

## L09 Module Loading：模块声明与加载阶段

每个Mod由`Modules/<Id>/SubModule.xml`等声明名称/Id/Version/Category、依赖模块/版本、加载前后关系、SubModule DLL/class/tags、XML资源及GameType。用户通过Launcher/受支持的模块管理工具选择并排序模块；游戏在前置启动和GameType建立时加载启用模块，缺失依赖/不兼容/非法程序集可能导致模块禁用、加载提示或进程错误。Native→SandBoxCore→Sandbox→StoryMode等官方依赖示例可从本机XML看到；StoryMode是可选单机Story模块。

`MBSubModuleBase`有 `OnSubModuleLoad/OnGameStart/OnGameLoaded/OnCampaignStart/OnApplicationTick`等生命周期回调；模块安装不等于其CampaignBehavior已经添加，也不等于目标GameType使用其内容。加载/排序阶段不推进Campaign时间；只有模块创建的游戏系统在运行后才影响玩法。XSLT数据变换与程序集Harmony Patch是另一种边界，分别见L02/L12。

玩家实际入口在游戏Launcher/管理器，而非战役内按钮；Chronicle Harness的module manifest仅定义自动测试集合，不替代玩家Mod Launcher当前启用集。证据：Native/Sandbox/StoryMode `SubModule.xml`、`TaleWorlds.MountAndBlade.Module`及`MBSubModuleBase`，安装路径下Mod目录；当前活跃module load order未在本轮读取。未知启用模块依赖具体顺序、多个mod相同资源/patch冲突优先级、缺版本/拷贝DLL/加载事件是否可回滚及真实玩家Launcher UI提示矩阵。

## L10 CampaignBehavior：Campaign规则生命周期

`CampaignBehaviorBase`要求实现 `RegisterEvents()`和`SyncData(IDataStore)`；`CampaignGameStarter.AddBehavior`把它加入当前Campaign starter，之后其事件订阅/小时日周tick、任务和存读档同步才会工作。行为在通常的CampaignGameStarter阶段由Module/behavior registrar创建；只看到类/override不代表在Sandbox或StoryMode已启用。注册顺序、事件监听器次数、`SyncData`持久状态命名和移除/升级行为决定是否在新档/旧档中正确恢复。

玩家没有专门入口选择一个CampaignBehavior；它是驱动菜单/任务/AI/奖励的后台引擎执行单元，影响通过对应游戏动作/通知显现。行为Tick基于Campaign自然小时/日/周，不能自带快进除非明确调用time manager。Chronicle自身有ChronicleCampaignBehavior用于状态/协议实验，作为Mod能力不属于玩家技术入口清单或Harness测试步骤。

来源：本机 `CampaignBehaviorBase/CampaignGameStarter`接口与Sandbox行为注册代码；Chronicle行为只作本模块样本。未知各官方Campaign模式所有Behavior依赖/启用矩阵、并行tick顺序、Behavior ID迁移和旧存档模块缺失兼容清理。

## L11 GameModel：规则公式替换与玩家后果

Campaign GameModels从 `CampaignGameStarter.AddModel`注册，系统通过 `Campaign.Models.Get<T>()`读取对应模型进行判断/计算（如 Party导航/天气、Clan Tier、外交、任务奖励）。Mod替换某模型可能改动多个实际玩家后果；模型本身一般不保存行动历史/发起UI，也不等于触发它的玩家操作。一个数值变化必须追“哪段Action/Behavior调用模型，再如何写回对象/UI”，不能只看Model方法认定完整玩家路径。

玩家的直接入口属于使用该规则的Settlement/Party/Kingdom/Mission UI；加载/注册Model不会自行推进Campaign或发生奖励。Harmony补丁可以与AddModel产生不同影响面。Chronicle未添加/替换Campaign Model，Harness基线操作不能代表改变公式。来源：`CampaignGameStarter.GetModel/AddModel`、多个DefaultModels以及B-L研究中对应调用链。未知同类型多个Model谁最终被选中、不同GameType/model registry替换优先级、第三方Mod对已观察变量的交叉副作用矩阵。

## L12 Harmony / BLSE：外部代码插桩与加载器

Harmony是为.NET方法添加/组合Prefix/Postfix/Transpiler补丁的社区运行库；BLSE是第三方Bootloader/启动环境，可能使非官方依赖或早期注入Mod参与启动。二者不是Bannerlord原版玩家按钮、不是Campaign内容系统，也不是本项目玩家必须单独配置的功能。启用它们的产品影响来自实际Mod `SubModule.xml`依赖、patch target、Harmony patch priority/before/after关系和加载器版本。

用户看到的风险一般是启动器模块列表/兼容提示、运行崩溃或具体被修改的游戏行为；并不存在“打开Harmony”时的Campaign时间/世界状态。当前安装Modules中可见 `Bannerlord.Harmony`等社区依赖；BLSE不是Native/Sandbox SubModule声明的原生组件。是否实际加载、谁安装在外部以及当前活动patch顺序未在本轮启动检查，因此不将本机安装目录存在等同活动依赖。

源码无法给出所有私有补丁目标/第三方Runtime状态。证据：模块清单与SubModule descriptors、`MBSubModuleBase/Module`及已安装Harmony模块目录；不把Crash/Harness弹窗处理算法列入玩家游戏系统。未知Harmony/BLSE具体构建与游戏/子模块版本配套、patch排序/卸载恢复、launcher报错对普通玩家显示和失败后的存档安全。

## L13 SaveSystem：Campaign保存、Mod状态与恢复

玩家从Pause/Escape/快速保存等原生界面触发保存或载入；游戏存档包含Campaign对象状态及注册的Saveable字段/类型，`IDataStore`/SaveSystem为Behavior `SyncData`提供持久数据。自定义类型需要稳定的SaveableTypeDefiner/field IDs；代码版本升级需考虑旧字段缺失、新枚举ID/类型映射与load lifecycle。Harness disposable save另见DEVELOPMENT，不能把自动测试夹具视为玩家存档路径。

保存本身不应推进Campaign时间，但在主界面/地图/对话/战斗等GameState下，可用保存入口和读回上下文不同。Mod移除/更新可能造成未知类型、迁移或状态丢失；调用 `SaveAs`/API成功不等于玩家存档列表/UI历史和完整载入后重建均验证成功。当前Chronicle自定义行为保存状态有限；不声称已实现玩家长期模型记忆/回滚。

证据：本机 `TaleWorlds.SaveSystem.dll`（`IDataStore`相关和Saveable attributes/TypeDefiner）、Campaign Behavior `SyncData`接口、Native save菜单/本地Chronicle样本及DEVELOPMENT保存验证阶梯。未知正式UI保存/覆盖/读档选项全部确认语义、Mod缺失/换序/跨版本迁移矩阵、崩溃时部分写入恢复机制和多Behavior同步序。

## L类的当前适配与未知总览

这些系统不是13个额外的可玩按钮：L01/L02/L07-L13主要是玩家体验所依赖的内容装载/显示/规则运行技术，L03-L06则直接承载游戏菜单、对话、回看信息和通知入口。准确的玩家动作分母仍由A-K真实行为研究与W1-M交叉去重；L不凭XML节点/SubModule/模型方法数量扩大游戏行为数。除已关联MAINLINE的研究适配动作外，未声称Chronicle完整覆盖所有L用户入口、模式、模块组合或存档场景。
