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

玩家Party Screen的 `PartyVM`按PartyScreen两侧区分成员和俘虏列表，显示健康/伤员、容量和可转移状态，并提供转移、全取/全放、排序、升级弹窗、俘虏招募弹窗等控件。升级或招募会因可用升级分支/兵种、经验与升级成本、玩家资金、双方 roster 容量及当前PartyScreen模式而开放/拒绝。Done会将 `PartyScreenLogic` 命令提交；Cancel/Reset走原生VM回滚/关闭，不等于已提交的TroopRoster写入。

军队人数变化还有战后俘虏转入、聚落志愿兵、招募俘虏、疾病/伤病、逃兵/死亡等来源；不应把升级、招募、伤兵治疗和战争损失压成一个“Roster调整”动作。自动NPC Troop升级、Party训练、恢复/逃兵另见 F11；玩家进入真实UI后的具体交互顺序仍未被Chronicle全自动覆盖。直接修改 `TroopRoster`会绕过UI可用性、价格/经验条件、容量和PartyScreen确认副作用；当前协议只在特定原生招募/战后PartyState入口支持有限提交。

时间：打开PartyScreen的Roster事务本身没有显式推进Campaign小时/日；具体屏幕所在GameState/父菜单管理游戏时钟，不能把显式 `advance`藏入 roster动作。Chronicle当前只返回主队总量和战后PartyState双方成员/俘虏 roster；不常驻枚举完整MainParty troop树，也不支持一般招募、所有升级、伤病治疗/复原和任意Roster拖放。证据：本机 `PartyScreenLogic`、ViewModelCollection `PartyVM/PartyCharacterVM/PartyUpgradeTroopVM/PartyRecruitTroopVM`、Chronicle `AgentObserver/AgentProtocol`；完整升级费用规则、各Roster来源与取消确认的视觉反馈、正常PartyScreen的完整玩家入口、非战后模式事务时钟仍需分别验证。

## H05 Companion：同伴招募、家族成员与离队

同伴是Hero，通常以可招募Wanderer身份在Settlement出现；加入PlayerClan后不再只是战斗Roster兵种：有个人技能/Perk/装备、关系和忙碌状态，可进入主队、担任角色、创建家族Party、被俘或离队。伴侣模板按周期由 `CompanionsCampaignBehavior`管理，生成/淘汰与Clan上限、世界人口和模板池有关；不是玩家可随时从固定菜单无限抽取的兵种。

原版玩家雇佣入口由 `LordConversationsCampaignBehavior` 注册：与未雇用、不是当前Companion、且不属于某个Party的Wanderer交谈，出现“I can use someone like you in my company”；后续对话先显示 `CompanionHiringPriceCalculationModel.GetCompanionHiringPrice`报价。接受选项要求 Main Hero 金币严格大于报价且未达到 `Clan.PlayerClan.CompanionLimit`，确认后依次调用 `GiveGoldAction`、`AddCompanionAction` 与 `AddHeroToPartyAction`，因此结果是支付后加入Clan并加入MainParty；看报价/拒绝/取消本身不会支付。默认价格按候选Hero军用与民用Equipment在城镇的市场价格之和取一半，再加角色等级价格项及玩家Perk修正；不是只按好感度固定报价。死亡、雇佣解雇、任务结果或同伴转为领主等会走不同 `RemoveCompanionAction` 分支，某些离队还需要结束其Party/当前领导状态；不能把“从主队离开”自动等同“从Clan删除”。

已有玩家Companion若被敌方关押，监狱突围成功时走F12 `ACT-F12-14`：同一Hero结束Captivity、恢复Active并`AddHeroToPartyAction`加回MainParty；这不是新的Wanderer雇佣，不触发雇佣报价/Gold门槛，因此H05交叉表引用F12-14而不另造“救援招募同伴”ACT。救援Mission/选择入口和失败后果由F12/G03负责。

Chronicle主观察不逐个列出Clan成员/同伴、能力/装备/当前位置/忙碌状态，PartyScreen存在成员列表但只在相应PartyState读取；没有Wanderer寻访/对话雇佣、解雇/转封臣、个人状态管理工具。跨入同伴、任务和亲属关系后的变化见B/C/J；家族职责见H06，创建家族Party见F06。来源：`CompanionsCampaignBehavior`、`AddCompanionAction`、`RemoveCompanionAction`、`DefaultCompanionHiringPriceCalculationModel`、`LordConversationsCampaignBehavior`、当前Chronicle Observer/Protocol。本轮源码已核清雇佣句、门槛、扣款和加入Clan/MainParty的提交顺序；仍未知Wanderer生成/出现地点、从地图到酒馆/场景的完整玩家进入流程、Conversation宿主时钟，以及等待失败/取消分支在实际UI中的呈现。

## H06 Party Roles：家族成员职责分配

玩家可通过Clan管理页面的Party/角色职责区域，为该Party成员安排军需官、侦察、军医、工程师等职责；`ClanPartyItemVM`逐一读取`ClanMemberPartyRoleModel.GetAssignablePartyRoles()`并据其生成可见职责行。v1.4.8默认`DefaultClanMemberPartyRoleModel`只返回Quartermaster/Scout/Surgeon/Engineer四项，并分别关联Steward/Scouting/Medicine/Engineering技能；`ClanRoleItemVM/ClanRoleMemberItemVM`基于资格和技能生成候选人，玩家提交后由对应MobileParty setter写入角色并触发界面分配事件。

`MobileParty`另存FirstMate/Navigator，`PartyRole`也定义这两个枚举值，通用Role VM包含其文本标识/effective owner/setter分支；但默认角色模型不把它们返回到`ClanPartyItemVM`职责列表，因此当前1.4.8基础游戏中没有这两个角色的玩家任命入口，记录为`N/A-H06-01`，不扩展行为分母。若Mod替换`ClanMemberPartyRoleModel`后开放这些Role，通用VM有接入能力，需在该Mod实际加载时重查。

角色不是Clan全局的荣誉称号，而是某个MobileParty当前由哪位Hero提供角色能力。Hero死亡、被俘、成为Governor/忙碌、离开Clan或其他无资格状态时，`PartyRolesCampaignBehavior`可清除其Party Roles；角色效果因此可能随队伍/成员状态改变。不同角色是否可由一个Hero兼任、每个版本的技能下限、Naval技能效果与UI限制须按Party Role Model和界面逐项判断，不由“同伴技能最高”直接推导。

Chronicle不观察各Party的Surgeon/Quartermaster/Scout/Engineer Hero ID和对应效果，也没有设置角色的动作；当前快照只给MainParty速度、食物/粮食变化、每日工资等结果字段，不足以反推出谁在承担角色。证据：Campaign `DefaultClanMemberPartyRoleModel`、`PartyRolesCampaignBehavior`、ViewModelCollection `ClanManagementVM/ClanRoleItemVM/ClanRoleMemberItemVM`、Chronicle `AgentObserver`。具体玩家从Clan页面进入职责tab、每个空槽/候选的实际UI条件、改派后模型数值与刷新时点、Party离开/角色失效的地图反馈尚未实机视觉验证。

## H07 Inventory：玩家物品库存与交易容器

玩家Inventory界面由 `InventoryState`/`InventoryLogic`及 `SPInventoryVM`等ViewModel组成。左/右容器的具体含义来自当前场景：可为玩家与商店的买卖双方、战后Loot，也可能是管理装备的Hero/容器；必须读取当前InventoryMode与双方roster，不能因为相同屏幕都列出物品就假设交易语义相同。`ItemRoster`保留物品类型、数量与装备修饰；金币、载重限制、物品分类/交易价格和装备栏都是不同字段。

玩家可以在库存UI选择、买卖、堆叠转移、装备/卸装、屠宰、捐赠、排序或切换当前Hero装备；各操作会检查模式、市场库存/价格、Gold、容量、可使用条件与交易方。VM由点击/拖拽处理意图，再经InventoryLogic提交；直接改ItemRoster或Equipment会绕过模式、成本、容重、双方库存差额和Done/Cancel事务。

交易与商店价格/库存/交易影响见 E02；战后物品如何生成见 F/G10。Chronicle观察当前MainParty item数量及InventoryState的基础两侧数量；交易测试通过原生InventoryLogic，战后loot动作限制在Loot状态，未覆盖所有人物装备、道具使用、场景容器和捐赠模式。Inventory操作本身没有显式Campaign时间推进；父GameState/场景控制地图时钟，具体交易界面打开时钟与各模式Cancel恢复状态仍需运行验证。来源：`InventoryState/InventoryLogic`、ViewModelCollection `SPInventoryVM`及Chronicle Observer/Protocol。各场景左右侧玩家可见内容、交易确认提示与Mods添加容器的范围仍未知。

## H08 Equipment：角色装备、装备集与穿戴限制

玩家可在Inventory的装备区域选择当前Hero与装备模式，将可用Item从库存移入武器、防具、坐骑、马具等槽位；`SPInventoryVM`根据当前Hero、装备集/EquipmentMode、物品要求和槽位判断可否装备。Campaign可能分别管理Battle和Civilian Equipment，某项物品能否装备不只取决于有无库存，还受角色能力、物品类别、装备槽、模式和Mod替换规则影响。NPC同伴/Family Hero的Equipment是其Hero状态的一部分，队伍普通Troop单位则使用Character equipment/template；不能用一个英雄装备槽代表整个Party士兵装备。

ViewModel会执行选择、预览、装备/卸装、可用性与重量更新；最终由本体Equipment/Inventory容器状态处理。角色可用性与UI比对提示不同于直接设置 `Equipment`元素。是否已保存装备，应观察当前Hero的Battle/Civilian装备及Inventory变动，而不是只看角色纸娃娃预览。

Chronicle当前不提供角色Equipment槽观察、切换装备模式或给英雄穿戴/脱下装备的动作；只观察队伍物品总量/载重。证据：ViewModelCollection `SPInventoryVM`的装备模式、可装备检查、Equip/Unequip流程及Campaign Equipment/InventoryLogic；与 E02交易及 F12俘虏 roster区分。打开装备界面的准确玩家路径、每项物品限制/提示、主角与同伴的装备提交/取消差异、装备造成的即时属性刷新时点和可视映射仍未逐项运行验证。

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
