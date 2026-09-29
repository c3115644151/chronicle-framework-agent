# H 类研究：玩家、队伍与成长

适用本体：Bannerlord v1.4.8.119303。本文是 H 域唯一研究资料，按 H01-H12记录玩家身份与成长相关的真实入口、游戏对象、原版后果、Campaign时间、Chronicle适配和未知。经济/训练/关系/战争等已由 E/F/B/C 域拆解的事实仅作引用，不重复维护第二份相同机制文档。

## H01 玩家身份与角色创建

### 身份对象不是同一个东西

玩家Hero由 `Hero.MainHero` 表示，对应可被Mission生成的 `CharacterObject.PlayerCharacter`；玩家家族是 `Clan.PlayerClan`；当前玩家控制的战役队伍是 `MobileParty.MainParty`。这三者拥有不同ID、状态和生命周期：主角可离队/被俘，Clan管理领地/成员/影响力，MainParty携带移动队伍与roster。`MainHero`不等于队伍领袖、王国领袖或Clan身份的所有者字段，角色身份变化应按对应行动及当前Campaign state判断。

### 创建界面与最终效果

当前Sandbox源的 `CharacterCreationCampaignBehavior.InitializeCharacterCreationStages` 注册 Culture、FaceGen、Narrative、Banner、Clan naming、Review、Options阶段。阶段由 `CharacterCreationManager`管理；玩家在界面选择文化、外观、背景/经历选项、家族徽记和名字等，Review前的Narrative选项可追加数值、装备、特征、身份和起始资源效果。不同Campaign类型/Story模式可能扩展Stages和选项，不能将Sandbox阶段列表当成所有玩法模式的完整菜单。

确认创建时，`CharacterCreationManager.ApplyFinalEffects`先把 `Clan.PlayerClan.Renown`重置为0，再应用玩家Culture与选中的Narrative最终效果、更新特征经验；如文化有起始坐标，会将MainParty放至有效导航位置，并触发创建结束Handlers。最终起始Hero/Culture/Clan/Party不是仅保存角色外观：玩家选择改变的是Campaign初态。具体各背景选项增加/减少的技能、装备、声望、资金与起始位置须逐项读取当前内容定义，不能只从选项文本猜奖励。

UI流程会限制阶段顺序、选项条件、FaceGen及Review；直接构造Hero或调用某个最终效果函数不等价于走完原生 CharacterCreationState。角色创建本身不是Campaign内可反复使用的成长动作；最终后果在新Campaign初始状态内生效。Chronicle当前不操控创建界面，Agent从已建立Campaign的 `Hero.MainHero`开始；没有角色创建、文化/经历选择或重开建档能力。来源：`CharacterCreationState/Manager`、`CharacterCreationCampaignBehavior`、当前 Chronicle `AgentObserver`；UI所有选项可视顺序和各模式差异尚未逐项截图核验。

**跨入口去重核验（v1.4.8.119303）**：Character Creator 的 Clan naming VM 只暂存编辑文本并校验；玩家确认 Next 时，`CharacterCreationClanNamingStageView.NextStage`直接调用`Clan.PlayerClan.ChangeClanName`，与Clan Management询问框确认后调用的`ClanManagementVM.OnChangeClanNameDone`完全相同，因此创建期/存档内改名是`ACT-H02-01`同一行为族的两个上下文入口。Banner阶段由`CharacterCreationBannerEditorView`创建同一个`SandBox.GauntletUI.BannerEditor.BannerEditorView`并传入`Clan.PlayerClan.Banner`；同一个`BannerEditorVM`编辑该Banner，Cancel反序列化恢复初始Banner，Done时创建期回调更新Clan颜色、把Banner传给`CharacterCreationContent.SetMainClanBanner`再推进stage。既有Clan管理也复用通用BannerEditor，Done确认同一Clan Banner编辑结果；故两处统一映射`ACT-H02-02`，仅记录创建期的内容草稿写入为附加副作用，不重复计算ACT。Narrative各页则用统一“选择当前NarrativeMenu的一项”入口更新`SelectedOptions`；不同选项的属性/技能/装备/资源等收益属于参数化结果，不增加选择动作族。`CharacterCreationManager.ApplyFinalEffects`在Review完成时应用所选Culture与Narrative options、Trait XP和起始位置，并调用注册handlers；Review确认仍单列`ACT-H01-06`。来源：当前1.4.8.119303 `CharacterCreationClanNamingStageVM/CharacterCreationClanNamingStageView.NextStage`、`ClanManagementVM.OnChangeClanNameDone`、`CharacterCreationBannerEditorView.AffirmativeAction`、`BannerEditorView.Exit`、`BannerEditorVM.ExecuteCancel/ExecuteDone`、`CharacterCreationNarrativeStageVM`与`CharacterCreationManager.ApplyFinalEffects`；尚未人工视觉验证和通过运行时回读最终对象。

## H02 Player Clan：家族等级、权限与家族面板

玩家Clan持有Renown/Tier、Influence、家族成员、家族领地、家族Party、财务/Workshop等数据；成员的个人Gold/关系/技能仍属于Hero或其他对象。王国成员/雇佣兵状态与Clan本身身份也是不同字段。家族Level并非一个只影响称号的数值：`DefaultClanTierModel`将Renown阈值映射为Tier，Tier又影响家族Party上限、同伴上限、玩家队伍规模加成、Workshop上限，并解锁佣兵、封臣、建国等门槛。当前默认阈值数组为0、50、150、350、900、2350、6150；Mod可能替换模型或配置，不能把这些数值跨版本固化。

玩家入口为家族/Clan管理面板中的成员、Party、领地、收入等分类；`ClanManagementVM`汇总并切换这些类别，子VM允许查看Hero/Party/Settlement/Workshop，并存在改名、Banner、Finance等操作。王国加入/退出和家族/领地转移需走独立政治/动作链，不能仅以Clan面板打开/点击代表完成。财务日结见 E07，Party创建/Army另见 F06/F13，关系及Kingdom成员后果见 B/C。

跨域提交映射：Clan Fiefs子页任免Governor走D07 `ACT-D07-01`（与Town Management同一`ChangeGovernorAction`结果）；Parties子页创建、换Leader、Disband与Objective selector映射F06 `ACT-F06-01..04`；Garrison party card的AutoRecruit switch映射D07 `ACT-D07-03`；Party职责任命仍是H06 `ACT-H06-01`。这些属于子系统动作，不合成一个“Clan面板管理”行为，也不因进入相同ClanManagementVM重复建ID。

Chronicle主快照已返回Hero/Clan ID与名称、Clan Tier、下一级所需Renown、Gold、Influence和Renown；不输出完整Clan roster、领地、Workshop、Clan finance分项或Kingdom成员权限，没有Clan management操作。源码证据：`Clan`、`DefaultClanTierModel`、ViewModelCollection `ClanManagementVM`及各分类VM、Chronicle `AgentObserver.cs`。当前数值基于本机v1.4.8.119303；实际从Campaign界面进入各tab、不同身份权限、每种Tier的具体加成/解锁文本和显示状态尚未做完整视觉验证。

## H03 Main Party：玩家控制队伍状态

`MobileParty.MainParty`是地图层玩家队伍；其 `PartyBase`下的MemberRoster、PrisonRoster与ItemRoster分开记录部队、俘虏和物品。速度/地图位置/移动目标/Army归属属于MobileParty，成员伤病和工资/食品等从Roster及模型计算，不应把“军队人数”“可战斗人数”“俘虏人数”和“地图估计实力”当成同一指标。Party类型、军团/支援、粮食和工资日结分别见 F01/F05、E06，Battle伤亡与自动恢复见 F10/F11。

玩家通过地图Party入口/Party Screen管理随队人员，也会经移动、商店、战斗和驻军界面使MainParty状态变化；不同界面是不同事务。当前 Chronicle主快照已读成员/健康/伤员/俘虏、物品总数、Party size limit、速度、士气、粮食及日变化、工资、负重、坐标/目标/移动模式和所属上下文；它不是包含每个成员与每项装备的完整Party管理器。一般Party状态读取不推进Campaign；正常世界时间仍服从Campaign TimeControl，自然旅行/结算见MAINLINE机制契约。打开界面后的逐项时钟模式、UI快捷键与可见数字之间的完全映射尚未人工视觉核验。

## H04 Troop Roster：队伍成员、伤员与编制操作

玩家Party Screen的 `PartyVM`按PartyScreen两侧区分成员和俘虏列表，显示健康/伤员、容量和可转移状态，并提供转移、全取/全放、排序、升级弹窗、俘虏招募弹窗等控件。升级或招募会因可用升级分支/兵种、经验与升级成本、玩家资金、双方 roster 容量及当前PartyScreen模式而开放/拒绝。Done会将 `PartyScreenLogic` 命令提交；Cancel/Reset走原生VM回滚/关闭，不等于已提交的TroopRoster写入。W2-K新增的按需`partyRoster`只复制MainParty成员/俘虏名单及健康伤员语义，不打开PartyState，也不提供转移/升级/招募按钮。

W2-P MainParty升级适配：`partyUpgradeOptions`仅在Campaign Map打开Normal PartyState，通过`PartyScreenHelper.OpenScreenAsNormal`取得原生`PartyScreenLogic`并构造本体`PartyVM`读取当前升级目标和费用/经验/物品/Perk可用条件；查询后走原生Cancel关闭。`upgradeTroop`要求最近观察到的普通成员ID与升级目标索引，只调用原生`PartyVM.ExecuteUpgrade(troop,index,1)`与`ExecuteDone()`，将单人升级草稿经`PartyScreenLogic.ValidateCommand/DoneLogic`提交；不直接改`TroopRoster`。有效运行夹具`villager_aserai`→`aserai_recruit`：人数1→0/0→1、XP100→0、金币1000→995；无效ID及升级后XP不足的有效兵种/目标均被拒且队伍、金币、Campaign日值无变化。测试暂时把兵种与经验加到内存中的disposable Campaign，未保存，原存档hash不变，进程停止。第二轮`TestResults/20260927-164831`另验证临时PartyVM按原生要求初始化销毁字段后，查询与升级路径均可正常`OnFinalize`清理，避免遗留全局事件/按键回调。测试只验证原生VM数据/事务，不是玩家可见UI手动点击；本轮没有物品需求或金币不足的目标负向样本。证据：`TestResults/20260927-164831/Temp/PartyUpgradeResult.json`及`AgentPartyUpgradeAdapter.cs`。

W2-Q MainParty普通俘虏招募：按需`prisonerRecruitmentOptions`从Normal PartyScreen原生PartyVM读取右侧MainParty普通俘虏与当前Conformity可招数；`recruitPrisoner(TroopId)`只调用当前 `PartyCharacterVM.ExecuteRecruitTroop()`（原版默认一人）、原生Done及Campaign招聘事件，不直接改Roster。成功从PrisonRoster扣一人和每人Conformity XP、MemberRoster增一人、RecentEventsMorale改变；不扣金币。Harness动态选原生Tier 2非Bandit regular，设置XP为279*2-1，实际可招1人。`TestResults/20260927-174107/Temp/PartyPrisonerRecruitmentResult.json`确认：在MainParty已经20/20满员时，VM仍显示可招1人，但原版提示将超限；Done弹出“超出上限”询问，文本说明士兵暂留、之后离队且移动变慢。接口先将完整原生文案暴露给Agent；未明确提供`confirmPartySizeWarning=true`就拒绝并重置草稿、保持Roster不变，明确确认后才调用原生 affirmative callback，结果人数20→21、俘虏2→1/XP557→278、RecentEventsMorale0→-1、金币不变。剩余278 XP不足279门槛时再次招募被拒且无变化。这里记录的是版本本机原版的超额规则，不自行添加容量硬限制。Campaign Stop和UnstoppablePlay档位均保持；存档hash不变、游戏进程停止。

W2目录复核发现H04遗漏了 `ACT-H04-03`普通聚落志愿兵招募：本机1.4.8 `PlayerTownVisit.game_menu_recruit_volunteers_on_consequence`在`town`、`town_backstreet`、`village`共用`MenuContext.OpenRecruitVolunteers`，Gauntlet视图会创建自己的`RecruitmentVM`。Done消费Notable一个`VolunteerTypes`槽、将兵加入MainParty并按原生Gold cost扣款；超容量会进入独立Inquiry，不同于H04-02俘虏Conformity招募、D08 Alley周招募与F09强征。当前CLI `recruitOptions/recruit`先核MapState/Settlement和同一个Native `recruit_volunteers`菜单项确实存在且可用，再用Native `RecruitmentVM`提供offer/调用Done；它不打开Gauntlet View、不模拟焦点，但在每个请求结束后使用与Native Gauntlet View一致的HotKey/KeyText初始化并调用`OnFinalize`清理VM事件订阅。满员时不确认会捕获/隐藏Native `InquiryData`并回滚草稿，只有决策显式带`ConfirmPartySizeWarning=true`才调用该Inquiry原始affirmative callback；没有直接写Roster/Gold。

运行`TestResults/20260930-045312/Recruitment.log`在Sargot `town`菜单确认可用项，确定性Provider正常招一名瓦兰迪亚新兵（Gold 1000→980、MainParty +1）；离开Settlement再查询被拒且roster/gold不变。Harness只为capacity分支在disposable内存Campaign填入普通兵至20/20：无显式确认时出现本体“超过上限”警告、拒绝且volunteer slot/Gold/MainParty不变；带显式确认后提交原生Inquiry回调，增至21/20并扣20 Gold。确定性Provider循环、Build/Docs均Passed；raw时钟Stop、day 91077.402保持，源fixture hash不变且进程退出。Gauntlet UI View未真正打开，不能据此声称UI视图的时钟语义已实测。

军队人数变化还有战后俘虏转入、聚落志愿兵、招募俘虏、疾病/伤病、逃兵/死亡等来源；不应把升级、招募、伤兵治疗和战争损失压成一个“Roster调整”动作。自动NPC Troop升级、Party训练、恢复/逃兵另见 F11；玩家进入真实UI后的具体交互顺序仍未被Chronicle全自动覆盖。直接修改 `TroopRoster`会绕过UI可用性、价格/经验条件、容量和PartyScreen确认副作用；当前协议仅对MainParty升级、普通俘虏招募、聚落志愿兵招募及战后PartyState等明确范围提供原生VM事务适配，不是通用Roster控制器。

时间：升级事务本身不附加Campaign时间推进或显式改档。原版`PartyState.IsMenuState=true`；Campaign `RealTick/Tick`由`MapState`仅在自身是ActiveState时驱动，因此PartyState压在地图上期间地图Campaign tick不执行。原版`PartyScreenHelper.ClosePartyPresentation`完成或取消后PopState回父State，PartyState/MapState激活关闭路径不会自动改写时间档。W2-P Harness在Stop与UnstoppablePlay下即时打开/关闭均看到各自档位原样保留，Stop下查询前后Campaign日值相同；该测试不是长时间保持实际视觉屏幕的录制，但时间暂停和回到地图后的档位语义已有源码路径支持。


## H05 Companion：同伴招募、家族成员与离队

W2-S端到端运行验收：Harness在Tavern本地HeroAgent观察到动态Wanderer `CharacterObject_1604`，其高度比入口地面高5.48，Native `missionNavigateToAgent`用20秒租约自然到达至1.438米；没有传送。`missionInteract`经Native Agent.OnUse启动该Hero对话，继续当前原生选项到雇佣报价。价格模型报价660：Harness将本次GoldFixture设为660时，严格`Gold > price`条件隐藏accept并保留拒绝句；660+1时accept可用，原生Consequences花660、余1 Gold，同伴计数0→1、Hero Clan为PlayerClan且进入MainParty，MainParty人数+1。源存档SHA-256不变、游戏进程正常停止。证据：`TestResults/20260927-201154/Temp/CompanionHiringResult.json`与`CompanionHiring-frame.bmp`。这只证明当前一名动态Wanderer和一套本机Mod/存档，未证明所有生成地点/角色/设备路径均相同，也没有完成解雇/转封臣等其它ACT。

同伴是Hero，通常以可招募Wanderer身份在Settlement出现；加入PlayerClan后不再只是战斗Roster兵种：有个人技能/Perk/装备、关系和忙碌状态，可进入主队、担任角色、创建家族Party、被俘或离队。伴侣模板按周期由 `CompanionsCampaignBehavior`管理，生成/淘汰与Clan上限、世界人口和模板池有关；不是玩家可随时从固定菜单无限抽取的兵种。

原版玩家雇佣入口由 `LordConversationsCampaignBehavior` 注册：与未雇用、不是当前Companion、且不属于某个Party的Wanderer交谈，出现“I can use someone like you in my company”；后续对话先显示 `CompanionHiringPriceCalculationModel.GetCompanionHiringPrice`报价。接受选项要求 Main Hero 金币严格大于报价且未达到 `Clan.PlayerClan.CompanionLimit`，确认后依次调用 `GiveGoldAction`、`AddCompanionAction` 与 `AddHeroToPartyAction`，因此结果是支付后加入Clan并加入MainParty；看报价/拒绝/取消本身不会支付。默认价格按候选Hero军用与民用Equipment在城镇的市场价格之和取一半，再加角色等级价格项及玩家Perk修正；不是只按好感度固定报价。死亡、雇佣解雇、任务结果或同伴转为领主等会走不同 `RemoveCompanionAction` 分支，某些离队还需要结束其Party/当前领导状态；不能把“从主队离开”自动等同“从Clan删除”。

已有玩家Companion若被敌方关押，监狱突围成功时走F12 `ACT-F12-14`：同一Hero结束Captivity、恢复Active并`AddHeroToPartyAction`加回MainParty；这不是新的Wanderer雇佣，不触发雇佣报价/Gold门槛，因此H05交叉表引用F12-14而不另造“救援招募同伴”ACT。救援Mission/选择入口和失败后果由F12/G03负责。

Chronicle主观察不逐个列出Clan成员/同伴、能力/装备/当前位置/忙碌状态，PartyScreen存在成员列表但只在相应PartyState读取；当前只在玩家自然进入Tavern并且Wanderer位于Mission局部观察后支持对话雇佣，没有全局Wanderer检索/刷新等待、解雇/转封臣或个人状态管理工具。跨入同伴、任务和亲属关系后的变化见B/C/J；家族职责见H06，创建家族Party见F06。来源：`CompanionsCampaignBehavior`、`AddCompanionAction`、`RemoveCompanionAction`、`DefaultCompanionHiringPriceCalculationModel`、`LordConversationsCampaignBehavior`、当前Chronicle Observer/Protocol。本轮源码已核清雇佣句、门槛、扣款和加入Clan/MainParty的提交顺序；运行仅覆盖一名Tavern Wanderer；所有Wanderer生成/出现地点、等待刷新/失败/取消分支、其他场景和设备模块兼容仍未全面验证。

## H06 Party Roles：家族成员职责分配

玩家可通过Clan管理→Parties→展开某个Party成员/职责区域，为该Party中的家族Hero安排军需官、侦察、军医、工程师等职责。`ClanPartyItemVM`逐一读取`ClanMemberPartyRoleModel.GetAssignablePartyRoles()`建立职责行；点击职责行写入`LastOpenedRoleSelection`并显示候选列表。v1.4.8默认`DefaultClanMemberPartyRoleModel`只返回Quartermaster/Scout/Surgeon/Engineer四项，分别关联Steward/Scouting/Medicine/Engineering技能；候选成员需在该Party roster内、属于PlayerClan、不是Governor，并通过`IsHeroAssignableForPartyRole`的当前角色模型资格检查。Clan Leader单独提供为角色VM，不同于普通可选成员；空成员项代表“Remove assignee”。`ClanPartyItemVM.RefreshMembers`另外读取`CampaignUIHelper.GetMapScreenActionIsEnabledWithReason`，在主角被俘、Mission/Encounter/围城、地图事件或其他禁用情境下禁用该Party的职责控件。

默认模型的`MaximumPartyRoleAssignmentCount`为2。一个Hero已有两个职位时若再调用原生`SetParty*`分配第三项，MobileParty setter会先执行`RemoveOnePartyRoleOfHero`再设置新职位；移除按原生角色枚举检查顺序清除该Hero的第一个职位，并非保持其它旧职位不变。角色赋值由`ClanRoleMemberItemVM.ExecuteAssignHeroToRole`调用对应party setter；非空任命还触发`ClanRoleAssignedThroughClanScreenEvent`，然后`ClanPartyItemVM.OnRoleAssigned`重新刷新职责VM。移除当前行走对应setter写null，再刷新VM。直接调用setter会漏掉UI候选/禁用条件、赋值事件和VM刷新，不能等同玩家入口。

`MobileParty`另存FirstMate/Navigator，`PartyRole`也定义这两个枚举值，通用Role VM包含其文本标识/effective owner/setter分支；但默认角色模型不把它们返回到`ClanPartyItemVM`职责列表，因此当前1.4.8基础游戏中没有这两个角色的玩家任命入口，记录为`N/A-H06-01`，不扩展行为分母。若Mod替换`ClanMemberPartyRoleModel`后开放这些Role，通用VM有接入能力，需在该Mod实际加载时重查。

角色不是Clan全局的荣誉称号，而是某个MobileParty当前由哪位Hero提供角色能力。Hero死亡、被俘、成为Governor/忙碌、离开Clan或其他无资格状态时，`PartyRolesCampaignBehavior`可清除其Party Roles；角色效果因此可能随队伍/成员状态改变。不同角色是否可由一个Hero兼任、每个版本的技能下限、Naval技能效果与UI限制须按Party Role Model和界面逐项判断，不由“同伴技能最高”直接推导。

Chronicle增加按需`partyRoles`读取MainParty职位及可任命候选，不扩充默认`state`；`setPartyRole`对当前VM候选执行`ClanRoleMemberItemVM.ExecuteAssignHeroToRole`，`unassignPartyRole`选择原生Remove assignee VM项；两者随后按`ClanPartyItemVM.OnRoleAssigned`刷新所有职位VM。执行前也复核`CampaignUIHelper.GetMapScreenActionIsEnabledWithReason`；并非直接改MobileParty setter。分成明确的任命/撤职动作，避免需要模型传一个真假开关。Harness夹具注入Wanderer仅用于提供当前PlayerClan/MainParty测试Hero，不是产品路径。

W2-T运行证据 `TestResults/20260927-213318/Temp/PartyRolesResult.json`：一名当前Hero在Native角色VM/候选列表、MainParty职责状态中可见，角色VM任职者与MobileParty原生getter读数一致；Quartermaster+Scout之后给同一Hero设第三职Surgeon，Native setter副作用清除旧Quartermaster、保留Scout及新Surgeon；独立`unassignPartyRole`只移除所选Surgeon。`FirstMate`、不是本队候选的Hero和对未分配职位执行Remove均被拒，无状态修改。Stop模式下连续任命/撤职不改Gold、Party roster、Campaign日或时间档；`UnstoppablePlay`查询/赋值期间TimeControlMode保持原档且Campaign日自然推进。源存档hash一致、进程退出。该Harness从Campaign Map创建对应Native Role ViewModels并调用UI绑定的`ExecuteAssignHeroToRole`提交handler；它没有打开或模拟实际ClanManagement页面的点击/Tab导航。玩家页面的具体可点区域、ClanState打开时钟、第三职旧角色被清除的其他组合顺序、第三方角色Model覆盖仍未运行验证。证据源：Campaign `DefaultClanMemberPartyRoleModel`/`MobileParty`/`PartyRolesCampaignBehavior`，ViewModelCollection `ClanManagementVM/ClanPartyItemVM/ClanRoleItemVM/ClanRoleMemberItemVM/CampaignUIHelper`。

## H07 Inventory：玩家物品库存与交易容器

玩家Inventory界面由 `InventoryState`/`InventoryLogic`及 `SPInventoryVM`等ViewModel组成。左/右容器的具体含义来自当前场景：可为玩家与商店的买卖双方、战后Loot，也可能是管理装备的Hero/容器；必须读取当前InventoryMode与双方roster，不能因为相同屏幕都列出物品就假设交易语义相同。`ItemRoster`保留物品类型、数量与装备修饰；金币、载重限制、物品分类/交易价格和装备栏都是不同字段。

玩家可以在库存UI选择、买卖、堆叠转移、装备/卸装、屠宰、捐赠、排序或切换当前Hero装备；各操作会检查模式、市场库存/价格、Gold、容量、可使用条件与交易方。VM由点击/拖拽处理意图，再经InventoryLogic提交；直接改ItemRoster或Equipment会绕过模式、成本、容重、双方库存差额和Done/Cancel事务。

交易与商店价格/库存/交易影响见 E02；战后物品如何生成见 F/G10。Chronicle观察当前MainParty item数量及InventoryState的基础两侧数量；交易测试通过原生InventoryLogic，战后loot动作限制在Loot状态，未覆盖所有人物装备、道具使用、场景容器和捐赠模式。Inventory操作本身没有显式Campaign时间推进；父GameState/场景控制地图时钟，具体交易界面打开时钟与各模式Cancel恢复状态仍需运行验证。来源：`InventoryState/InventoryLogic`、ViewModelCollection `SPInventoryVM`及Chronicle Observer/Protocol。各场景左右侧玩家可见内容、交易确认提示与Mods添加容器的范围仍未知。

战斗结束后，`InventoryScreenHelper.OpenScreenAsLoot(itemRostersToLoot)`创建`InventoryState`并设置`InventoryMode.Loot`：左侧是该战斗分给MainParty的Loot ItemRoster，右侧是MainParty.ItemRoster。Native Gauntlet `ExecuteTakeAll`调用`SPInventoryVM.ExecuteBuyAllItems/TransferAll(true)`，形成从Loot容器到玩家队伍的物品事务；不是市场Purchase，不扣金币。Native Done经`SPInventoryVM.ExecuteCompleteTranstactions`提交；若仍有OtherInventory Loot物品，会弹`str_leaving_loot_behind` Inquiry后再决定退出/提交，全部Take All后才直接Done。时间推进来自父Campaign GameState，不来自物品转移。当前Chronicle `inventoryTakeAll`复用`InventoryState.Handler.ExecuteLootingScript()`；但`inventoryDone`直接`InventoryScreenHelper.CloseScreen(false)`绕过SPInventoryVM的未收取物品警告逻辑。W2-X需先保证剩余loot非空时不被Agent静默关闭，再按Done结果回读Player ItemRoster并退出。`TestResults/20260924-154639/PostBattle.log`在Native BattleSimulation胜利后使用Harness专属`seedVisualLoot`注入13件wool以取得确定性界面样本；Take All后Player item count 0→13、Loot 13→0，Native Done回Campaign Map、源存档hash不变、进程停止。该结果仅验证Loot UI/事务闭环，明确`naturalDrop=false`，不代表自然战利品生成率。来源：当前本机1.4.8 `InventoryScreenHelper.OpenScreenAsLoot`、`GauntletInventoryScreen.ExecuteTakeAll/ExecuteConfirm`、`SPInventoryVM.ExecuteBuyAllItems/ExecuteCompleteTranstactions/HandleDone`、`InventoryLogic.DoneLogic`、Native `module_strings.xml`及Chronicle `AgentProtocol`。

## H08 Equipment：角色装备、装备集与穿戴限制

本机1.4.8玩家从Campaign Map导航栏的Inventory入口进入：`MapScreen.TickNavigationInput`按当前绑定调用Inventory项权限与`OpenInventory`，鼠标入口则由`InventoryNavigationElement.OpenView`走相同ScreenHelper。该入口会检查地图导航是否开启、Hero被俘/Raft、已有InventoryState及当前Mission的Inventory access；然后经`MapNavigationHelper.SwitchToANewScreen`调用`InventoryScreenHelper.OpenScreenAsInventory`。Helper创建`InventoryState`/`InventoryLogic`，右侧为`MobileParty.MainParty.ItemRoster`和成员Roster，活动角色为`CharacterObject.PlayerCharacter`，非商店交易，权限允许SpecialActions。Native `GauntletInventoryScreen.OnReady`取得这份`InventoryLogic`，用当前Mission是否要求Civilian模式和原版`GetItemUsageSetFlag`构造`SPInventoryVM`。

`SPInventoryVM`当前定义Civilian/Battle/Stealth三种EquipmentMode并将其映射到各自Equipment库存侧；当前MainHero可切换模式，但本次W2-U首切片只支持当下原生VM模式，不默认三种全覆盖。玩家在UI将可用Item从PlayerInventory拖到具体Equipment槽：Native绑定进入`ExecuteTransferWithParameters(SPItemVM, index, targetTag)`；它判断Item来源/当前装备模式、目标`EquipmentIndex`、`CharacterHelper.CanUseItem`、`Equipment.IsItemFitsToSlot`、性别/民用使用/骑乘Harness条件，再经Equip/Unequip VM处理器创建`TransferCommand`并加入`InventoryLogic`草稿。换槽时原装备按原生ItemRoster/Equipment transaction逻辑返还，武器槽会按Equipment类型/空位选择；装备不是简单把物品写进Equipment数组。装备候选兼顾`EquipmentElement` modifier，普通库存堆叠与每个装备槽单件不是同一数量语义。

确认/取消不同：`GauntletInventoryScreen.ExecuteConfirm`调`SPInventoryVM.ExecuteCompleteTransactions`并由`InventoryLogic.DoneLogic`最终处理原生转移；ESC Cancel调`ExecuteResetAndCompleteTransactions(true)`撤回本次未完成事务。故执行VM Equip handler但未Done只能算草稿，不可报告装备完成。某项物品能否装备除库存外还受角色技能/Perk/Item条件、类别与槽位、Civilian/Stealth模式和Mod规则影响。NPC同伴/Family Hero的Equipment是各自Hero状态；队伍普通Troop单位使用Character equipment/template，不能用一个英雄装备槽代表全Party。

ViewModel会执行选择、预览、装备/卸装、可用性与重量更新；最终由本体Equipment/Inventory容器状态处理。角色可用性与UI比对提示不同于直接设置 `Equipment`元素。是否已保存装备，应观察当前Hero的Battle/Civilian装备及Inventory变动，而不是只看角色纸娃娃预览。

W2-U (#48)已有代码切片：`inventoryOpen`走Campaign Map原生Inventory导航项；`heroEquipmentOptions`读取GauntletInventoryScreen当前SPInventoryVM；`equipHeroItem/unequipHeroItem`使用本体`ExecuteTransferWithParameters`建立草稿，`inventoryConfirm`调用当前页面原生Done，`inventoryCancel`和`inventoryCancelChanges`分别实现无草稿离开与明确确认撤回。查询/动作只针对当前被选中的MainHero及当前equipment mode，且一次只操作一个Item/slot；不直接写Equipment/ItemRoster，不包含商店交易、Loot等其他InventoryMode。打开/提交/撤销均不主动调用Campaign时钟API，Inventory State期间的自然时钟行为仍未知。

本地测试证据按阶段区分：旧适配版`TestResults/20260927-220236`只证明Native InventoryState/Handler打开和基本Cancel；`InventoryNavigation`在新适配下的`TestResults/20260927-232822`已实测读取当前SPInventoryVM、MainHero装备槽、Stop/活动时钟表现与原生Cancel，存档hash未变且进程退出。首次`EquipmentTransactions`运行`TestResults/20260928-060737`实测当前模式MainHero的Cape槽（`hood`，EquipmentIndex 9）经原生VM卸装并Done提交；随后重装备暴露空槽索引错误：旧观察器将空`SPItemVM.ItemType=-1`当槽索引。已依据本机1.4.8 `SPInventoryVM.GetItemFromIndex(EquipmentIndex)`改为从Native VM反查槽Property并保留枚举索引。第二轮`TestResults/20260928-061907`的所有装备草稿/Done/Cancel/非法项流程都实际运行成功；单独失败的断言是槽读数没有提供`modifierId`字段，导致无法比较未带modifier的盾牌与空字符串。补齐槽与候选物品的原生`EquipmentElement.ItemModifier.StringId`读取后，`Run-Harness.ps1 -Phase EquipmentTransactions`在`TestResults/20260928-062215/Temp/EquipmentTransactionResult.json`全项通过：Weapon0盾牌原生卸下→Done、重装备→Done、产生第二次卸装草稿后通过原生Cancel Inquiry确认丢弃、重新打开确认槽和modifier恢复、非法VM ID拒绝且无装备变化；时钟档位Stop未变、正式fixture哈希前后均为`DEF0806F0F74573CF775DAEB855080D05FA28F617001C1B111BCC631ED8CE469`、测试进程正常退出。此次选中槽没有原装备交换，非空modifier样本、Civilian/Stealth模式和活动时钟下的完整事务尚未验证。另在`TestResults/20260928-061907/Temp/startup-dialog-58948.json`记录到精确着色器缓存提示被目标进程自身“确定”控件自动确认；后一轮缓存已重建、提示未重现。来源链：当前1.4.8 `MapScreen.TickNavigationInput/OpenInventory`、SandBox.View `InventoryNavigationElement.GetPermission/OpenView`、Campaign `InventoryScreenHelper`/`InventoryLogic`、`GauntletInventoryScreen`、ViewModelCollection `SPInventoryVM`/`SPItemVM`。

### H08 当前运行验收（2026-09-28）

最新最终结果为`TestResults/20260928-071313/Temp/EquipmentTransactionResult.json`，此前本段前的各轮失败/修复记录均为调试历史，不再代表当前状态。全项通过：InventoryState内原生VM单件装备、卸装、Done提交、occupied-slot交换并恢复原槽、Cancel Inquiry回滚；有效旧候选、随机无效ID及主手剑放入Torso不兼容槽位都拒绝且无Equipment/Inventory变动。测试专用`masterwork_sword` modifier以同一EquipmentElement穿戴、Done、卸下、Done后从库存读回相同modifier，再按唯一Item+modifier清除临时物品。同一`vlandia_sword_1_t2`普通剑与非空modifier剑同时在库存时，SPInventoryVM提供了不同`viewModelItemId`，Harness确认唯一标识后才装备普通剑。最后重新核对12个装备槽、MainParty人数/伤病/俘虏/物品数量/载重、Gold/Influence/Renown、Campaign位置/日/时间模式、存档hash全都恢复到基线；Bannerlord进程退出。尚未覆盖Civilian/Stealth模式、活动时钟下完整事务，以及第三方替换SPInventoryVM。

## H09 Crafting：城镇锻造、炼制与熔炼

锻造入口依托玩家在Settlement找到黑smith并通过对话进入原生 `CraftingState`；`CraftingCampaignBehavior`注册blacksmith交互，并提供Crafting、Smelting、Refinement等工作区。`CraftingVM`选择执行锻造的Hero、武器类别/模板/部件及各部件尺寸，更新预计属性、所需材料、技能和Smithing stamina；`ExecuteConfirm`在条件满足时才执行当前主操作。炼制需要材料与能量，熔炼消耗既有装备并回收材料/经验，锻造消耗材料/能量并按设计难度、技能、Perks、随机质量等生成武器；Town订单模式另有目标规格、时限/结果、报酬和失败质量，不能把自由锻造和订单交付当成同一动作。

材料/解锁部件/武器历史/每位Hero Smithing stamina由Crafting系统与CampaignBehavior分别管理；某一Hero的技能并不代表任意家族成员可无条件执行。Crafting系统订阅Hourly/Daily Campaign事件恢复/更新部分状态，但进入UI期间这些事件是否以及如何推进取决于GameState与时间模式；不能因为存在HourlyTick就说玩家在锻造界面里会边点边回精力。制造/熔炼等事务经原生CraftingVM与Campaign crafting logic提交；直接创建Item会跳过部件解锁、材料、Stamina、经验、订单验证和历史记录。

Chronicle没有Settlement场景黑smith交互、SmithingState/CraftingVM观察、锻造/炼制/熔炼动作或物品设计反馈；库存和玩家技能快照不等于Crafting能力。证据：Campaign `CraftingCampaignBehavior`、`DefaultSmithingModel`、`CraftingState`、ViewModelCollection `CraftingVM/SmeltingVM/RefinementVM/WeaponDesignVM`；本机v1.4.8.119303。具体对话入口/菜单条件、自由模式与订单模式完整扣费/失败结果、当前界面时钟下Stamina恢复和各类部件何时解锁仍需运行验证。

## H10 Skills 与 Perks：经验、技能成长和选择

Hero的 `HeroDeveloper`持有Skill XP/Level、Attributes、Focus和未花点数/Perks；这些和当前有效技能效果是关联但不同的数据。角色经验由战斗/任务/贸易/制造/旅行等多个系统产生，XP经Skill/CharacterDevelopment模型计算；升级角色等级后可分配Attribute与Focus，技能达到相应解锁点才出现Perk选择。Perk值又会被队伍、战斗、贸易等其他模型读取。

玩家从角色发展(Character Developer)面板选择适用Hero，检查技能、升级进度、属性/Focus点数与开放Perks；`CharacterDeveloperVM`先保存拟改值，Done时调用 `ApplyAllChanges`写回`HeroDeveloper`，Cancel会复原未提交更改并关闭面板。另一个独立的Reset控件调用`ExecuteReset`，遍历所有适用Hero执行`ResetChanges(isCancel:false)`并刷新选择器：复原本次面板会话中的未提交编辑，但不关闭页面，玩家可继续分配；因此Reset不等于Done，也不等于Cancel，映射`ACT-H10-02`。直接调用 `HeroDeveloper.AddFocus/AddAttribute/AddPerk`绕过UI可用点数、前置技能、Perk选择提示和取消事务；不能把点数读出或界面打开当成成长发生。

Chronicle常规schema21通过`mainHeroSkills`只读提供MainHero当前SkillObject等级，来源于原版`Hero.GetSkillValue`；Agent需要判断成长条件时，再显式调用`characterDevelopment`读取主角属性/属性点、等级经验、技能等级与经验进度、Focus余额/投入、模型学习率与上限，以及当前技能等级下角色发展面板列出的Perk状态。查询不把完整Perk目录重复放入每轮提示，也不判断某个Issue能否接受；Issue仍以原版对话选项为准。

本机1.4.8 `CharacterDeveloperVM`/`CharacterDeveloperHeroItemVM`/`SkillVM`/`CharacterAttributeItemVM`直接构建角色发展面板字段。`TestResults/20260927-095403/Temp/CharacterDevelopmentResult.json`在disposable fixture中对照原生`CharacterDeveloperHeroItemVM`，6个属性与18个动态Skill对象、等级/经验进度/下一等级需求/Focus/学习率/学习上限/可否加Focus/当前等级Perk列表及状态、角色经验和点数余额逐项一致；重复查询稳定、状态未变、Campaign时间与存档文件hash不变、Bannerlord正常停止。该夹具当前有0个等级已解锁Perk，所以非空已解锁Perk分支仍需在后续适合的自然角色状态中补验；此结果不作为Perk选择动作或UI视觉自动化证据。

W2-I已实现主角的按需`spendSkillFocus(SkillId, Count)`动作。它接受当前`characterDevelopment`观察中的SkillId，用原生`CharacterDeveloperHeroItemVM/SkillVM`在一个协议命令内起草Focus变化并通过`SkillVM.ApplyChanges`提交；余额不足或技能Focus上限不足时整体拒绝，不保留跨回合编辑草稿。`TestResults/20260927-102057/Temp/SpendSkillFocusResult.json`在Harness显式暂停的disposable fixture中验证Crafting Focus 0→1、余额3→2、更新后学习率及原生VM值；超余额与超技能上限请求均拒绝且状态不变，Quest与技能等级列表不变，Campaign时间/存档hash不变并清理进程。测试不等于玩家实际打开并点击Character Developer界面的视觉验收；属性点、Perk投入、Cancel UI/多回合草稿、同伴与第三方成长仍未适配。技能经验来源见战斗/任务/贸易/制作等域，不能视作角色面板功能。来源：本机当前1.4.8 Character Developer ViewModel及W2-G/H/I运行证据。

## H11 Renown 与 Influence：声望、权限和政治资源

默认系统中Clan Renown决定Clan Tier；Clan Influence是可增减的政治/军团资源。Renown不会直接等同金钱、Hero关系或影响力。当前1.4.8默认Tier下限为0/50/150/350/900/2350/6150，Tier 1可达佣兵资格，Tier 2可达封臣资格；家族Party上限、同伴上限、主队规模和Workshop上限也会受Tier与Perks等模型修正。实际条件应由当前TierModel重新计算，不能用旧版本固定数值。

Renown来源不是一个单独按钮；已源核实的野战/模拟战斗奖励按战力、贡献份额、敌方伤亡比例、奖励模型和Perk等变化，见MAINLINE Tier 1证据与F/G10。其他战斗、任务、锦标赛和政治行为有各自前置/路径，须按H11行为来源去重，不能把RewardModel调用点数当成玩家可达途径数。Influence收入/消耗见E07/F13/C：例如军团召集、凝聚力与政治决策是不同支出，不应该合并成一个“声望系统”行为。战役时钟不因读取数值或打开相关面板而快进；来源动作各自遵循原版Campaign事件/行动。

Chronicle主观察已返回Clan Renown、Influence、Tier、下一级Renown需求和佣兵门槛，但不解释变化因果，也无Renown主动增减、政治决策或通用Influence交易动作。证据：`DefaultClanTierModel`、`DefaultBattleRewardModel`、F/G战斗及E/C政治经济资料、Chronicle `AgentObserver`。未知为全部自然玩家Renown来源/前置/收益的去重分母、不同模式或Mod修改阈值、Influence自动收入和支出事件的完整覆盖、收益在UI/日志可见时点及失败重试后果；不得因此把Tier 1测试当成已掌握全部成长闭环。

## H12 Player Captivity：玩家被俘、等待与脱身

玩家Hero被捕后会进入特殊的PlayerCaptivity流程，不只是普通Party PrisonRoster中的一个成员；`PlayerCaptivity`记录Captor Party、开始时间、赎金/提案状态，并由PlayerCaptivityCampaignBehavior管理相应菜单与定时检查。相关一般Hero捕获/释放动作的Roster和关系后果见 F12，玩家专属菜单、恢复与时钟分支在此补充。

玩家面对的原生结果包括随队/转入聚落囚禁、逃脱机会、赎金要约/接受/拒绝、盟友支付赎金、俘虏方被击败/队伍解散/和平或身份状态不再敌对后结束。每条路经 `EndCaptivityAction`以不同Detail提交；不是一次统一的“等待X天”。`CheckCaptivityChange`在Campaign推进时根据 captor类型、Campaign PlayerProgress、是否在Settlement/领主队伍等计算下一次检查等待时间；关系与随机值也参与部分处置分支。源码另有条件性处决风险，不能从“被俘”必然推出会被处死。

玩家入口是被战斗结果强制转为Captor关系后出现的Captivity菜单与可用选项；正常时间推进驱动等待/赎金和escape检查，Agent不能把移动、普通点击或屏幕等待伪装成加速时间。具体菜单选项、逃脱的玩家技能与队伍状态要求、受伤/队伍战败/劫狱/交换俘虏的分支要分别处理。Chronicle目前能观察玩家GameState/Party prisoner count及一般MapEvent结算，但没有PlayerCaptivity menu的观察/选择、逃脱和赎金交互/赎金支付动作。证据：本机 `PlayerCaptivity`、`PlayerCaptivityCampaignBehavior`、`TakePrisonerAction/EndCaptivityAction`、Chronicle Observer/Protocol；未知每一捕获方/俘虏菜单完整选项及玩家可视反馈、各结局对应资源/时间/关系全后果和自动队伍转移后的恢复/清理顺序。
