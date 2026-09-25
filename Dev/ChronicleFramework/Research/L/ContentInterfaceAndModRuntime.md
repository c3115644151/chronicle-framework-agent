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

Chronicle已能判定若干GameState/Mission上下文并测试特定Battle Mission retreat；尚无通用场景寻路/角色接近/物件互动/3D操作桥。证据：Campaign `CampaignMission/PlayerEncounter/CampaignMissionFactory`、MountAndBlade `Mission/MissionState`与Mission behaviors、D/F/G/J具体入口。未知所有Scene menu到Mission的转场、同Mission恢复/存读档和战争地图时钟交接矩阵。

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
