# D 类研究：聚落与领地

状态：本类 D01-D10 已完成首轮源码盘点，未进行方案评审；界面实测与已标明的未知项仍未穷尽。

适用本体：Bannerlord v1.4.8.119303。依据安装目录中的 `TaleWorlds.CampaignSystem.dll` 反编译结果和 Chronicle 当前 `AgentObserver.cs`；本节是静态代码证据，不代表已经在游戏界面逐项实测。

## D01 Settlement 基础状态

### 对象层级与分类

`Settlement` 是战役地图上的统一聚落对象。它持有稳定 `StringId`、名称、位置、`Culture`、地图派系、可见/已侦察标志、内部 `Party`、驻留队伍/英雄/要人缓存、绑定村庄列表，以及可选的 `Town`、`Village` 或 `Hideout` 组件。`IsTown`、`IsCastle`、`IsVillage`、`IsHideout` 是从所挂组件派生的分类；`IsFortification` 表示 Town 组件中的城镇或城堡。城镇和城堡共用 `Town` 类型，通过组件内部的城堡标志区分，并非两套完全独立的领地对象。

`SettlementComponent` 通过其 `Owner` PartyBase 回指所属 `Settlement`，并提供 `MapFaction`、名称、金币及聚落类型钩子。它是统一组件基类，不意味着所有 Settlement 都有同样的所有权或发展字段。

### 所有权与派系归属

- 城镇/城堡的 `OwnerClan` 由 `Town` 保存；改变它会从旧 Clan 移除并向新 Clan 登记领地。
- 村庄不单独持有 OwnerClan：`Settlement.OwnerClan` 经 `Village.Bound.OwnerClan` 解析，`Village.MapFaction` 同样取自绑定聚落。其 `Bound` 变更会维护双方的绑定村庄集合；贸易绑定另有 `TradeBound`，如果绑定对象本身是城镇则直接以该城镇为贸易对象。
- Settlement 的 `MapFaction` 委托给当前组件。藏身处不是普通 Clan 领地：其派系先从藏身处内的匪徒队伍取得 ActualClan；没有此类队伍时回退到可用的匪徒 Clan，找不到时可能为空。
- Settlement 的 `Culture` 是单独保存的文化对象，不应从当前领主 Clan 或 MapFaction 推断。所有权、地图派系、文化和村庄绑定是相关但不等价的状态。
- `Settlement.Owner` 只是 `OwnerClan.Leader` 的便捷派生属性；对没有可解析 OwnerClan 的对象，不应据此假定存在领主 Hero。

### 组件特有的基础字段

`Town` 同时承载城镇/城堡数据：OwnerClan、繁荣度、忠诚、安全、食物、建筑及建设队列、驻军相关组件、总督、市场和绑定村庄等。字段的计算和每日变化属于 D02/D03/D05-D07，不在 D01 中展开。

`Village` 保存 VillageType、村庄状态、Hearth、绑定聚落、贸易绑定和市场数据。源码定义状态包括 Normal、BeingRaided、ForcedForVolunteers、ForcedForSupplies、Looted；`IsDeserted` 在 Looted 状态为真。每日 hearth/militia 更新属于 D04，不在此处推导其全部来源。

`Hideout` 是独立 SettlementComponent，具有被侦察标志、可攻击时间、匪徒队伍和空置后隐藏/停用等生命周期行为；这些袭击入口与生命周期后果留到 D09/D10 研究。

### 玩家可见性与 Chronicle 当前观察

Chronicle `AgentObserver` 当前以 MainParty 位置和 `max(12, SeeingRange)` 作为附近 Settlement 半径，从 `Settlement.All` 中筛选 `IsActive && IsVisible`，按距离排序并最多输出 8 项。每项只返回 ID、名称、派生类型、距离、是否与玩家派系交战、是否遭围攻。

现有附近 Settlement 观察不返回 OwnerClan/领主、Culture、Village 的绑定聚落、Town 的繁荣/忠诚/安全/食物/驻军/总督或 Village 的 Hearth/状态。`Settlement.IsVisible` 与 `IsInspected` 是不同字段；目前不能仅凭字段名称证明它们与玩家地图图标、悬停提示、ALT详情或百科内容逐项等价。实际地图呈现仍需对照当前版本运行时/界面验证。

玩家地图点击并进入城镇/城堡/村庄等入口属于聚落访问与地图移动契约（D09及 MAINLINE 对应动作），D01 只界定对象与状态归属，不把点击、进入场景或菜单行为误写成 Settlement 基础字段的副作用。

## D02 城镇发展状态与每日更新

### 状态更新入口

`Town` 提供 `ProsperityChange`、`FoodChange`、`LoyaltyChange`、`SecurityChange`、`MilitiaChange` 和 `Construction` 等派生计算值；对应的 `...Explanation` 属性调用同一个模型并要求附带逐项解释。它们不是互相独立的常数，而是读取当前 Settlement、Town、Village、派系政策、建筑、总督、驻军、Issue 等状态后由 `Campaign.Current.Models` 计算。

`Town.DailyTick` 将忠诚度和安全度分别加上模型变化值；有库存时触发 Owner 的食物消耗，然后按 `FoodChange` 更新食品库存并夹在 0 与 `FoodStocksUpperLimit()` 之间。库存耗尽会将 Owner 的 `RemainingFoodPercentage` 置为 -100；库存未耗尽则重置为 0。之后该日常更新继续处理繁荣度、民兵与城墙维修。Loyalty、Security 属性被限制在 0–100；Prosperity 属性只设有 0 下限，没有同样的固定上限。

建筑由独立的 `BuildingsCampaignBehavior` 订阅 `DailyTickSettlementEvent` 处理：AI 所有的聚落会分别进行是否补建设队列、是否切换日常项目的随机判断；当前非日常项目且未围城时，以 `Town.Construction` 增加建设进度，并检查是否升级完成。队列权限、玩家建筑操作和项目细节归 D05/D06，不把这段引擎更新当作玩家菜单操作。

### 各发展量的主要计算输入

- **繁荣度**：模型综合食物短缺/盈余、城镇人口住房成本档位、市场售出且带繁荣加成的商品、建筑效果、总督特长、忠诚度条件及 Issue 效果。住房成本项会随当前繁荣度档位变化；城堡与城镇共享模型，但部分住房/市场计算只适用于 Town.IsTown。
- **食物**：模型把地产与未被掠夺的绑定村庄、建筑和政策等生产项，与繁荣度/驻军规模对应的消耗项相减，再合入 Issue 效果；非围城与围城采用不同的生产分支。另一个参数可选择是否把市场售出商品日志中的食物库存加成计入。每日更新最终限制库存范围，因此“每日净变化”不等于库存一定按该数值无限累积。
- **忠诚度**：输入组包括食物库存、总督/领主文化、政策、聚落项目、Issue、安全度、要人关系、总督特长和忠诚度漂移。具体解释可由 `LoyaltyChangeExplanation` 请求；基于名称不能把某一项单独视为决定因素。
- **安全度**：输入组包括附近被感染的藏身处、绑定村庄被掠夺、围城、繁荣度、驻军力量、政策、总督、项目、Issue、特长、漂移、建筑与巡逻队。故安全并非仅由“当前驻军人数”决定。
- **民兵**：模型含要塞/村庄基础生成、现有民兵自然流失、繁荣度（要塞）或 Hearth（村庄）、叛乱低忠诚条件、市场特定商品、政策、文化、建筑、总督特长和 Issue 等输入。D04 再展开村庄民兵，D07 再展开驻军构成与管理。
- **建设能力**：每日建设模型以繁荣度为基础，并可叠加建设加速消耗、总督技能/特长、建设相关市场商品、建筑效果和忠诚度条件。建设能力只是可用进度值；当前项目、围城和队列决定其是否实际转成 BuildingProgress。

### 状态之间的反馈与边界

这些量形成原版内循环：食物库存变化会影响繁荣与忠诚；繁荣既是独立目标，也进入食物消耗、安全修正、民兵生成和建设能力；安全、忠诚、驻军、村庄受损和政策再反向改变每日变化。模型通过 `ExplainedNumber` 汇总正负项和倍率，而不是每个状态只有一条固定增减公式。某次行动可以通过原版模型间接影响多项城镇指标，但本节不据此提议或实现玩家行为。

Campaign 时间仍由全局时间控制推进；普通读取这些派生值不会推进时间，城镇日常更新属于 Campaign 的聚落日 tick。此处的源码核对没有运行定时快进验证每项更新的确切执行先后，也没有改变时间或写入存档。

### 玩家与 Agent 的当前信息面

地图上的附近 Settlement 快照仍只给出 D01 所列的六项信息；`AgentObserver` 不读 Town 的繁荣、食物、忠诚、安全、民兵、建筑进度、驻军或总督，也不输出这些模型的 Explanation。玩家在聚落/领地/百科界面实际能看到哪些数值、在哪一页看到、是否有条件限制，本轮没有做界面运行验证，归 D09 的入口盘点交叉确认。当前只能确定游戏逻辑持有这些状态，不能据此说 Agent 已感知或能管理它们。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Town`、`DefaultSettlementProsperityModel`、`DefaultSettlementFoodModel`、`DefaultSettlementLoyaltyModel`、`DefaultSettlementSecurityModel`、`DefaultSettlementMilitiaModel`、`DefaultBuildingConstructionModel`、`BuildingsCampaignBehavior`；Chronicle `AgentObserver.cs`。其中模型默认实现是安装版本源码证据，不意味着其他 Mod 替换模型时数值保持相同。

未知项：玩家界面中这些变化值/解释字段的逐页呈现与操作入口；日 tick 内各行为订阅者之间的完整执行次序及其跨版本稳定性；经济、建筑、总督、驻军、叛乱、Issue 对指标的全部子公式与边缘条件；当前 Agent 是否应在特定观察请求中按需读取其中某些状态，留待全域盘点及后续设计讨论，不在本研究中预判。

## D03 城堡发展、城防、绑定村庄与领地价值

### 城堡不是独立于 Town 的第二套发展对象

城堡仍由 `Town` 组件承载；`Settlement.IsCastle`/`Town.IsCastle` 是 `_isCastle` 标志的分类结果，城镇和城堡共用 OwnerClan、繁荣度、食物、忠诚、安全、民兵、建筑、建设队列、总督、驻军和城墙状态字段。Castle/Town 专属差异通过各模型检查 `IsCastle` 或 `IsTown` 分支实现，不能将城镇公式直接照搬到城堡。

本机默认模型中已确认的城堡差异包括：

- 城堡不走只适用于 `IsTown` 的住房成本档位和市场繁荣加成；它仍使用公共繁荣模型中的食物、建筑、Perk、忠诚等影响。
- 非围城时食物模型给城镇基础土地生产 15、城堡 10；正常绑定村庄和建筑等仍会参与生产，围城时切换为另一套生产分支。
- 城堡的建筑加速成本/奖励使用 Castle 参数；建设模型还区分城堡军事建筑与城镇建筑对应的总督 Perk。
- Settlement 估值的基础值公式分别是城堡 `250,000 + Prosperity × 1,000`、城镇 `750,000 + Prosperity × 1,000`；若启用计入绑定村庄，会递归累加村庄价值。调用者可选择是否计入绑定聚落，并可按英雄 Clan 的领地中心距离应用估值修正。该函数是内部估值，不等同于玩家购买价、投票价值或屏幕显示值。

### 城墙与围城相关状态

`Settlement.IsFortification` 对城镇/城堡均为真。每个 fortification 有两个城墙区段；当前和最大城墙耐久比例分开保存/计算，最大总墙体耐久经 `WallHitPointCalculationModel.CalculateMaximumWallHitPoint(Town)` 得出，单区段最大值再由两段均分。`Town.DailyTick` 会按驻军维修模型的每日修复额度逐段恢复城墙比例；围城状态通过 `Settlement.IsUnderSiege` 关联其他模型输入。城堡与城镇共享该城防数据结构，具体围城工程和攻防过程属于 F/G 类，不在 D03 展开。

`Settlement.SettlementHitPoints` 是另一个保存字段，不应与两段城墙的 `SettlementWallSectionHitPointsRatioList` / `SettlementTotalWallHitPoints` 混为一项。结构化观察当前没有输出这些城防字段；它们是否以及如何出现在玩家地图、城镇管理页或围城界面，本轮没有运行时核实。

### 绑定村庄与收益关系

城堡和城镇都通过 `Settlement.BoundVillages` 暴露绑定村庄集合。绑定关系不只是地图归属：每日城镇食品生产会遍历绑定村庄，取决于其状态与 Hearth 等级；繁荣度、安全度也分别读取食物/被掠夺村庄等状态；Settlement 估值可递归计入绑定村庄。村庄文化/地图派系与所属 Clan 等关系见 D01。村庄绑定的形成/改动入口、玩家可见绑定列表和失去村庄后的完整后果未在本项实机验证，分别留待 D09/D10 及 D04 交叉盘点。

### 玩家与 Agent 信息面

玩家与城堡的地图遭遇、进入城堡、管理页面/领主大厅等实际入口归 D09；本节只核实底层 Castle/Town 数据复用、模型分支与关联状态。Chronicle 目前附近 Settlement 项不返回城堡所有者、绑定村庄、繁荣/食物/驻军/建设或墙体数据。任何“Agent 已知道一座城堡防御情况”或“直接 API 等于玩家管理操作”的结论都超出现有证据。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Settlement`、`Town`、`DefaultSettlementProsperityModel`、`DefaultSettlementFoodModel`、`DefaultBuildingConstructionModel`、`DefaultSettlementValueModel`、`DefaultWallHitPointCalculationModel`；Chronicle `AgentObserver.cs`。公式和结构结论来自 v1.4.8.119303 安装程序集反编译；没有启动游戏验证 UI 数值或城堡管理流程。

未知项：玩家城堡管理页的精确字段/操作/权限；估值方法各调用者是否用于领地分配、AI 决策或玩家展示的全链路；城墙最大耐久模型的全部参数和围城各阶段 UI 对应；村庄绑定更改时的事件、税收/贸易/食物联动及玩家可操作条件。

## D04 村庄状态、生产、村民队伍与掠夺

### Hearth 与村庄状态

`Village` 的 `Hearth` 是参与村庄繁荣、生产和村民队伍规模计算的数值，不是一个直接等同于可见居民人数的 roster。`VillageType` 定义基础生产商品及每种商品产量；Settlement 自身文化提供村民 Party 模板。`Bound` 是政治归属/绑定城镇或城堡，`TradeBound` 是经济交易目的地，二者并非始终相同。

默认繁荣模型对正常村庄按 Hearth 档位计算基础每日增长：低于 300 为 +4，300–599 为 +1.2，达到 600 起为 +0.2；政策、文化、Issue、绑定城镇/城堡建筑及相关 Perk 可继续修正。被掠夺状态另有 -1 的基础项。`Village.DailyTick` 应用模型给出的 Hearth 变化后把 Hearth 下限保持在 10；随后更新关联 Settlement 民兵，并将村庄持有金币回调到 1000。模型数值只是默认 1.4.8 规则，其他 Mod 可替换模型。

状态枚举为 Normal、BeingRaided、ForcedForVolunteers、ForcedForSupplies、Looted。`Village` setter 对 Normal、BeingRaided、Looted 分发各自的专属事件；强征状态没有对应的专属事件分支。原版 `ChangeVillageStateAction` 在状态实际改变时对所有这些状态分发统一 `OnVillageStateChanged(old,new,raider)` 并刷新 Settlement Party 视觉等级遮罩。Looted 使 `IsDeserted` 为真；村庄民兵模型在非 Normal 状态不增加或减少，普通产出模型也仅对 Normal 状态给出产量。围城的驻留村民 Party 会被停止移动。

### 生产与仓储流

`VillageGoodProductionCampaignBehavior` 订阅每日聚落 tick。每轮先统计村庄 Settlement Party 的物品 roster；若总物品量低于仓储容量的 1.5 倍才运行商品和食物产出。仓储容量约为五天预计产出量的上取整，至少为 5；模型把预计每日食物产出与 `VillageType` 各项商品产出相加后计算。

商品模型要求 VillageState 为 Normal，按 VillageType 的商品基准量和 Hearth 档位乘数 `(HearthLevel + 1) × 0.5` 计算，再叠加适用的绑定城镇 Perk、文化和绑定建筑效果，最后以随机舍入转成整数。食物产出按 HearthLevel+1 计算，可被 Issue 效果修正；每份食物会从原版可食生品类中按价值权重随机抽取。每日生产的商品先进入村庄的物品 roster 并发出 `OnItemProduced`；它不是即时直接写入绑定城镇市场。

后续村民运输有独立行为：每小时 Settlement tick 只考虑 Normal、未进入 MapEvent 的村庄；在随机判断通过、村庄库存达到容量且 Party/地图条件允许时，按 Hearth 和 PartySizeLimitModel 条件生成或补充 Villager Party，从村庄库存装载部分商品并驶向 TradeBound 城镇。路途、敌对关系、围城、队伍被拦截或仓储库存都会影响货物是否抵达，不能把“村庄每日生产”误当作“绑定城镇每天必然收到同量商品”。贸易绑定会在新档/载入、领地易主、宣战/议和、Clan 变更王国等事件后重新计算；具体 trade-bound 选择算法留待经济/贸易域交叉核对。

### 掠夺与恢复边界

玩家对村庄的敌对行动由原版 Village hostile-action GameMenu/Encounter 链处理，涉及袭击、强征志愿兵或补给等不同分支，不是一个统一的“村庄受损”结果。Village 状态转换会记录行为者并广播事件；袭击、强征可能分别改变 SettlementHitPoints、Hearth、村庄 roster、Party roster/战利品和外交状态。具体前置、警告、遭遇与结果要按 D09 的玩家入口分支及 D10 的所有权/后果复核，本节不把不同分支合并成固定数值。

`SettlementHitPoints` 是聚落受损数据，不等同 Hearth。`VillageHealCampaignBehavior` 对血量低于 1、没有 MapEvent 且没有 SiegeEvent 的村庄/城镇逐日恢复部分 SettlementHitPoints；来源/领地力量和 Perk 会影响恢复速度。被掠夺村庄对绑定城镇安全度的影响见 D02；生产何时恢复、Hearth 如何回补、伤害/事件如何清理的完整生命周期仍未从所有状态转换调用点闭环。

### Chronicle 当前覆盖与玩家观察边界

Chronicle 附近 Settlement 快照不返回村庄 Hearth、VillageState、VillageType/产物、仓库容量、村民 Party、Bound/TradeBound 或 SettlementHitPoints，因此 Agent 当前不能从此接口判断村庄是否正常生产、是否被掠夺、货物是否已运出或有哪些绑定关系。玩家从地图点击进入村庄后所见菜单、交易/强征/Issue 入口以及百科显示字段尚未在本项运行观察，归 D09 逐入口核验。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Village`、`DefaultSettlementProsperityModel`、`DefaultSettlementMilitiaModel`、`DefaultVillageProductionCalculatorModel`、`VillageGoodProductionCampaignBehavior`、`VillagerCampaignBehavior`、`VillageTradeBoundCampaignBehavior`、`ChangeVillageStateAction`、`VillageHostileActionCampaignBehavior`、`VillageHealCampaignBehavior`；Chronicle `AgentObserver.cs`。本节为 v1.4.8.119303 静态程序集证据，没有运行新战役、掠夺村庄或改存档。

未知项：各类村庄在 UI/百科中显示 Hearth、生产、绑定与受损状态的具体入口和限制；所有强征/袭击分支的条件、损害及战争/关系后果；TradeBound 模型选择逻辑、村民货物运输丢失/到货调用链；被掠夺结束后状态恢复的完整触发与时序；Hearth 变化的全部模型修正项和跨域事件消费者。

## D05 聚落建筑与建设队列

### 建筑对象与类型

`BuildingType` 是建筑种类定义：最高等级为 3，数据含起始等级、各级生产成本、效果枚举及等级增量、是否为军事项目/日常项目和随机等级变化概率。每个聚落的 `Town.Buildings` 保存本聚落对应实例；实例另有当前等级、建设进度和当前日常项目标志。类型效果由 `Building.AddEffectOfBuilding`/Town 的效果汇总入口交给对应 Campaign Model 读取，等级变化会发 `OnBuildingLevelChanged`。

`DefaultBuildingModel.CanAddBuildingTypeToTown` 按城镇/城堡身份筛选允许的类型：城镇型 fortifications、marketplace、warehouse 等不允许添加到城堡；Castle fortifications、granary、craftsman quarters 等不允许添加到城镇。默认日常项目类型也按城镇或城堡区分。具体可用建筑和效果以当前加载的 `BuildingType` 数据及替换模型为准，不能只用名称推断。

### 两种发展槽位

Town 把一个当前日常项目（`CurrentDefaultBuilding`）与普通建造队列（`BuildingsInProgress`）分开。日常项目通过 `IsCurrentlyDefault` 标记，不进入普通建设队列；普通建造项目按队列顺序施工。`CurrentBuilding` 在普通队列非空时返回队首，否则返回当前日常项目。因此查看“当前建筑”时要同时读取队列和日常项目，不能把两者当成同一槽位。

游戏启动初始化会为各城镇/城堡创建所有适用的 Building 实例，再基于 `VarianceChance` 对起始等级做随机调整，并为其选择初始日常项目与普通建设队列。AI 持有聚落的后续自动选择由 `BuildingsCampaignBehavior` 进行：队列空时有随机机会提取 `BuildingScoreCalculationModel.GetNextBuilding`；另有较低频率机会选择 `GetNextDailyBuilding`。这是原版 AI 的聚落治理逻辑，不是玩家操作。

### 施工、完成与队列变更

`BuildingsCampaignBehavior` 订阅 `DailyTickSettlementEvent`。对于城镇/城堡，若当前不是日常项目且当前没有围城、队列也非空，会把 `Town.Construction` 加到队首建筑的 `BuildingProgress`，随后由 `BuildingHelper.CheckIfBuildingIsComplete` 对照该等级施工成本。达到成本后建筑升一级并出队；达到 3 级后不再升级。围城会阻止此建筑施工推进。每日施工能力的输入和数值见 D02，建筑效果如何被各模型消费须结合具体 effect 与建筑类型查证。

玩家管理 VM `SettlementProjectSelectionVM` 分别维护可用建设、日常项目与本地开发队列草稿；但每次队列项增删/设为当前优先/重排都会触发`OnChangeInBuildingQueue`，父级`TownManagementVM.OnProjectSelectionDone`立即调用`BuildingHelper.ChangeCurrentBuildingQueue`，所以不是等管理窗口的Done才提交。选择日常项目走`SettlementDailyProjectVM.ExecuteSetAsActiveDevelopment`→同一父级回调，立即`ChangeDefaultBuilding`；仅`ExecuteSetAsCurrent`改变VM当前预览选择而不写Settlement。窗口Done负责关闭/结束，不应误当队列与日常项目唯一提交点。页面还提供Building reserve控制：`TownManagementReserveControlVM.ExecuteConfirm`按当前储备和本次输入金币调用`BuildingHelper.BoostBuildingProcessWithGold`，修改`Town.BoostBuildingProcess`供后续Construction逻辑使用；它不是立即升级建筑或绕过队列。源码/VM调用已定位，玩家实际输入数额、失败回执和建设储备后续扣用仍未运行核实。

### 易主、等级与效果事件

`BuildingsCampaignBehavior` 监听 Settlement owner change：新 Owner 不属于 Player Clan 时清空已有普通建设队列；玩家获得聚落时此条件不成立。建筑等级提升后会发出等级变化事件；本体监听器会更新受容量类建筑影响的驻军/监狱 roster 版本，并继续处理完成后的技能经验等效果。该事件是建筑升级与其他系统之间的连接点，不能仅把建筑当作静态聚落装饰。

### Chronicle 当前覆盖与玩家观察边界

附近 Settlement 快照不返回建筑类型/等级、普通队列、当前日常项目、施工进度或加速余额，也无相应协议动作。当前研究只追到 ViewModel 项目选择与底层队列/进度辅助逻辑，尚未从玩家真实按键一路运行到完成确认并核对聚落状态；管理页面准确入口、可用按钮、费用预览与取消/提交语义留待 D09 及 UI 验证。项目中使用 `Town.DailyTick` 或直接改 `BuildingProgress` 不能证明玩家 UI 路径相同。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Building`、`BuildingType`、`DefaultBuildingModel`、`DefaultBuildingScoreCalculationModel`、`DefaultBuildingConstructionModel`、`BuildingsCampaignBehavior`、`BuildingHelper`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `SettlementProjectSelectionVM`、`SettlementBuildingProjectVM`；Chronicle `AgentObserver.cs`。本节结论为 v1.4.8.119303 静态源码核对，不代表建筑管理 UI 已实机验证。

未知项：管理/建筑页面从玩家可见菜单进入的完整路径与确认按钮副作用；每类官方建筑的完整等级效果和成本数据；建筑建成后各模型/事件消费者的完整清单；所有权转换时日常项目、建筑等级与建设加速余额的保留/重置规则；其他 Mod 替换建筑类型/模型后的兼容行为。

## D06 城镇与城堡日常项目

### 与普通建造的区别

原版 `BuildingType.IsDailyProject` 标记不进入普通建设队列的日常项目。选中的项目作为 `Town.CurrentDefaultBuilding`，其效果在各发展模型计算经过 `Building.AddEffectOfBuilding` 汇总时生效；若它不是当前被选项目，对应日常效果不会应用。它不是消耗建造进度升到等级 2/3 的普通建筑，也不是一次性的按钮奖励。项目切换由 `SettlementProjectSelectionVM` 和 `SettlementDailyProjectVM` 展示/选择，实际聚落数值仍由模型在相应状态计算或每日更新时应用。

### 默认项目及其模型效果

以下效果来自本机默认 `DefaultBuildingTypes` 定义，数字是 effect 输入值；模型如何在具体状态上组合它们，应与 D02 的繁荣/忠诚/民兵/建设模型和 D07 驻军相关链路一起理解。

| 聚落类型 | 日常项目 | 本机定义的效果 |
| --- | --- | --- |
| 城镇 | Housing | Prosperity +2 |
| 城镇 | Train Militia | Militia +2；GarrisonAutoRecruitment +1 |
| 城镇 | Festival and Games | Loyalty +3 |
| 城镇 | Irrigation | 绑定村庄 Hearth 每日 +1 |
| 城堡 | Slacken Garrison | GarrisonWageReduction -5%（AddFactor） |
| 城堡 | Raise Troops | Militia +3；GarrisonAutoRecruitment +2 |
| 城堡 | Drills | ExperiencePerDay +8 |
| 城堡 | Irrigation | 绑定村庄 Hearth 增长 +50%（AddFactor） |

普通建筑与日常项目是两套并行发展位：日常项目不会排队施工，也不随普通建筑升至三阶；普通建筑则通过施工进度逐级升级。项目选择不会把城镇项目提供给城堡，`CanAddBuildingTypeToTown` 按 `IsTown`/`IsCastle` 过滤适用类型。

### 玩家、AI 与时间

玩家 VM 暴露 daily-project 候选、当前默认项目、项目效果与选择回调；完整的屏幕入口、确认/取消时提交到 Town 的具体链路和玩家可见文本仍未做运行验证。AI 的默认项目选择已在 D05 记录：原版 Campaign 行为会在每日聚落 tick 中低频尝试改选，不属于玩家 UI 操作。读取项目类型/效果本身不推进 Campaign 时间；其效果进入相关模型，底层日常数值依 Campaign 时间 tick 更新。

Chronicle Observer 不读取当前默认日常项目，也不计算这张表的模型结果；Protocol 没有日常项目选择动作。因此目前只有引擎内部定义被核实，尚未证明 Agent 能看见、决定或提交项目切换。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `DefaultBuildingTypes`、`BuildingType`、`Building.AddEffectOfBuilding`、`DefaultBuildingModel`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `SettlementProjectSelectionVM`、`SettlementDailyProjectVM`；Chronicle `AgentObserver.cs`。数据与 VM 逻辑为 v1.4.8.119303 静态程序集证据，尚无游戏内项目选择运行结果。

未知项：玩家实际点击具体daily项目后的视觉回执及聚落/围城上下文禁用条件；每项效果最终经过哪些模型及调用方；默认 AI 改选发生时所处 UI/围城/易主条件的全部限制；Mod 新增/替换日常项目时，ViewModel 与模型是否自动支持新效果。源码已表明选择即时写入；不可再把普通关闭窗口说成可回滚所有daily project改动。

## D07 总督任命与驻军

### 总督对象与玩家任命链

`Town.Governor` 与 `Hero.GovernorOf` 双向关联。原版 Town Management VM 在当前 Settlement 是 fortification 时建立 `SettlementGovernorSelectionVM`；候选来自 OwnerClan.Heroes，并须满足 `ClanPoliticsModel.CanHeroBeGovernor`，且尚未担任别处总督（或已经是当前聚落总督）。列表另有空选项用于移除。Sandbox 概念百科也把“聚落所有者在 town management window 指派同伴/家族成员”为官方入口说明；这里核实到的是代码/文本链，尚未实机点击整个窗口流程。

提交新总督时 `TownManagementVM.OnGovernorSelectionDone` 调用 `ChangeGovernorAction.Apply`。如果 Hero 已在该 Settlement 且不是囚犯，立即登记为 Governor；否则先清掉当前任命并经原版传送行为安排其之后前往。操作会解除旧 Governor 的 `GovernorOf`、派发 `OnGovernorChanged`，并将新 Governor 标记为因任职而忙碌。领主改变 Clan 后若不再属于聚落 OwnerClan，GovernorCampaignBehavior 会移除其任命。直接给 `Town.Governor` 赋值不等同于这一行动/事件链。

跨入口去重：Clan Management→Fiefs子页的`ClanFiefsVM.ExecuteAssignGovernor/OnGovernorSelectionOver`也可为其选中的Town/Castle打开候选Popup与确认Inquiry，最终同样调用`ChangeGovernorAction.Apply`或`RemoveGovernorOfIfExists`，与Town Management窗口归为同一`ACT-D07-01`，不是额外的第二种“Governor指派”结果。Clan页Governor/fief观察字段仍与Town Management信息层次有差异，由B05/H02与D07现有Observation scopes保留。

总督技能/Perk 会进入忠诚、安全、繁荣、建设等模型（见 D02/D05）；Town Management VM 的工具提示会显示总督相关效果，并在窗口统计中显示聚落状态与预测变化。GovernorCampaignBehavior 的 Settlement 日 tick 还会按其 Perk触发少量要人关系变化并授予治理经验。这个角色是一种持续的聚落治理指派，不只是文本头衔。

### 驻军数据对象与民兵区别

驻军是绑定 fortification 的 `GarrisonPartyComponent` / `MobileParty`；组件把自己登记到 `Town.GarrisonPartyComponent`，禁用 Party AI、将导航类型设为 None，并通过自身接口使用聚落的 wage-payment limit。其成员 roster 保存驻军士兵；没有创建 Garrison Party 时某些代码路径允许该值为空。它与 Settlement 民兵不是同一 roster：民兵是另一个派对组件及模型值，见 D02/F 类；不能把聚落总防御人数当作单一的“驻军人数”。

新战役初始化会创建 fortification 的 Garrison Party，并按聚落文化的默认 PartyTemplate、繁荣度与随机权重填入初始兵员。普通 Campaign 中至少有两条自动化补充/调度链：

- `GarrisonRecruitmentCampaignBehavior` 每日更新 fortification。Issue/叛军模型可能提供基础变化；自动招募则要求开关启用、`FoodChange > 0` 且没有 MapEvent/SiegeEvent。它从聚落要人和正常状态的绑定村庄要人处建立志愿者列表，受可用工资预算、Party Size Limit 与每日最大招募数共同限制；当前默认模型的每日自动招募上限是 1。招入时消耗对应志愿者槽，并记入 Clan 的自动招募费用。GarrisonAutoRecruitment 日常项目效果（D06）会进入该计算。
- `GarrisonTroopsCampaignBehavior` 在 AI Lord Party 进入同阵营 fortification 时运行编队/驻军转兵逻辑；它不是让玩家的 MainParty 自动换兵。AI 的保留人数综合领地理想驻军、队伍理想规模、食物与工资限制等，并可能在 Party 和 Garrison roster 间转兵。新攻占聚落有特殊处理条件。

玩家另可在Clan Management→Parties选中Garrison Party卡片切换`Auto Recruitment`。这由`ClanPartyItemVM.IsAutoRecruitmentVisible/AutoRecruitmentValue`控制可见状态，setter直接写所属Town的`GarrisonAutoRecruitmentIsEnabled`；不是Town Management的PartyScreen转兵入口，也不会立即招募。该卡片状态复用`OBS-B05-01`，玩家开/关设置映射`ACT-D07-03`。DailyTick随后仍须满足食物盈余、无MapEvent/SiegeEvent、Notable候选、工资/人数上限才尝试招募。

驻军还进入 D02 食物模型的消耗、Settlement Security、围城防守、驻军工资和建设容量效果链。Town Management VM 显示驻军数量及模型预测的每日变化，但本轮没有把“玩家手动从 Party 转移士兵”入口、工资上限调节入口及它们的完整 UI handler/API 副作用闭环；不依据自动招募或 AI Lord 转兵来声称玩家可以通过同一操作执行它们。

### Chronicle 当前覆盖

Nearby Settlement 快照不返回 Governor ID、GovernorOf、Garrison Party ID、驻军 roster、自动招募开关、志愿者来源、工资上限或估算每日变化。Town Management VM 是玩家可见的原版管理面之一，ClanPartiesVM另提供Garrison Auto Recruitment开关；Chronicle目前不读取这些聚落/Clan管理字段，也不调用Governor/Garrison UI操作。开关入口现在已用源码映射为`ACT-D07-03`，其视觉状态、地图输入禁用/提示条件和实际自动招募结果仍未运行验证。本节说明原版有两套差异化的治理/补兵机制，不等于Agent能操作。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Town`、`ChangeGovernorAction`、`GovernorCampaignBehavior`、`GarrisonPartyComponent`、`GarrisonTroopsCampaignBehavior`、`GarrisonRecruitmentCampaignBehavior`、`DefaultSettlementGarrisonModel`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `TownManagementVM`、`SettlementGovernorSelectionVM`、`TownManagementReserveControlVM`；Sandbox `concept_strings.xml` 的 Governor 玩家说明；Chronicle `AgentObserver.cs`。目前是 v1.4.8.119303 静态源码和资源说明证据，未运行 UI。

未知项：Town Management 窗口从地图/聚落的精确按键入口、实际提交/返回的时序；玩家 Party 与驻军间手动士兵转移的真实 UI 路径及 roster、伤兵、升级和军需副作用；GarrisonWagePaymentLimit 的玩家修改 UI 与日工资结算调用链；AI 驻军转兵完整目标公式与排除条件；新征领地/失去领地时驻军、Governor 和工资设置的所有后果。

## D08 聚落犯罪与帮派巷道

### 城镇巷道与帮派占有

每座城镇的 `Settlement.Alleys` 保存若干 `Alley` 区域。Alley 保存所属 Settlement、tag、名称、AreaState 和当前 Owner Hero；这是 Town 中的区域/派系状态，不是独立的城堡或村庄，也不等同于整个 Clan 所有权。城镇中的 gang leader Notable 可以拥有多条 Alley，原版每日聚落 tick 会按随机概率尝试让帮派占有未分配 Alley 或失去已有 Alley；概率随当前 Alley 数量改变。

Sandbox `AlleyCampaignBehavior` 是该系统的主要生命周期行为。Town 的玩家入口来自 `town` 菜单新增的“Go to alley”，并进入 `manage_alley` 原版管理GameMenu；菜单初始化注册`alley` MenuLocation，但W2-BB运行确认此入口仍在Campaign Map，无Location Mission/3D场景。已在同一disposable PlayerAlley夹具下逐项检查Native菜单：可见的是应对袭击、更换负责人、管理守军、放弃、返回；不存在负责人的对话选项，管理页人物overlay为空。独立`town_streets`入口会启动`center` Location Mission，原版`AddPlayerAlleyCharacters`把当前Assigned Clan Hero生成在镇中心，负责人对话条件要求该Hero确为`Hero.OneToOneConversationHero`。故玩家要进入其对话至少需要在Mission中接触这名角色；测试发现他并不在城镇菜单可快速交谈的人物overlay里。用户回忆“进入巷子”或许也能对话，但与当前1.4.8已截取的原版管理面板不符，尚不按事实采纳。不要把`MenuLocations`字段推断成已进入物理场景/建立对话。战斗、招募等具体后果继续交叉引用相应D/G/H域。

### 玩家经营 Alley 的状态循环

玩家在 Alley 战斗中获胜后，`AlleyOccupiedByPlayer` 事件让主 Hero 成为 Alley Owner、保存驻守 roster 与指定 Clan Member，并添加 Alley 经验。占领会降低原帮派首领关系；若该镇不属于玩家 Clan，还会降低镇主和部分非帮派 notable 关系。清除/放弃玩家 Alley 会移除 Owner，改变与原 gang leader/notables 的关系并可解除对方的攻击状态。

玩家 Alley 要指定一名 Clan Hero 领导并驻守一队打手，默认人数范围 5–10；可派 Hero 受 Roguery 至少 30、Mercy 不高于 0，以及“不能另任 Alley leader、Governor、囚犯、正在解 Issue/旅行/忙碌/逃亡”等资格限制。Alley 模型每个该 Hero 每日授予 200 XP，主角治理 Alley 每日有对应 Roguery XP；Alley 收入按 Town Prosperity / 50 计算。每个归主角所有的 Alley 每日向该派系 Crime Rating 增加 0.5。

玩家拥有 Alley 会产生被其他 gang 攻击的长期风险。Campaign 每日以随机概率尝试发起 Alley attack；模型根据守军 roster 估算回应期限，默认区间为 8–12 天。期限前可进入 Alley 应对/战斗；到期未回应时 PlayerAlleyData 会被移除且 Alley 被销毁/失去控制。能否发生 attack 还要求城镇存在其他适用的 Alley state；具体全条件及不同战斗结果分支尚需进一步追踪。

玩家每周有概率从 Alley 得到一批帮派兵种，模型根据固定随机值决定零人或不同组成，之后进入 MainParty roster 并更新上次招募时间。Town 菜单/对话管理项还能打开 Alley 打手 roster 管理、改变指定 Clan Member 或放弃 Alley；底层屏幕管理使用 `AlleyHelper.OpenScreenForManagingAlley`。这不是镇内普通志愿兵招募入口。

### Alley 的玩家操作链与跨域动作边界

在拥有玩家 Alley 的 Town 菜单，`go_to_alley`选项以`GameMenu.SwitchToMenu("manage_alley")`进入 Alley管理GameMenu；其仍是Campaign Map菜单，不是3D Alley Location Mission。Native菜单将Alley Location注册到`GameMenuManager.MenuLocations`，但该字段不意味着运行中Mission已打开。W2-BB验证此Town菜单进入与`back`返回；两者CampaignDay/raw Stop/waiting稳定。Town GameMenu管理项可在此原版管理界面操作；指定Alley leader对话则需另一个能真正实例化Alley NPC的入口，来源/场景流程尚未验证：

- **更换 Alley leader**：`change_leader_of_alley`或 manager 对话打开 `AlleyHelper.CreateMultiSelectionInquiryForSelectingClanMemberToAlley`；`AlleyModel.GetClanMembersAndAvailabilityDetailsForLeadingAnAlley`筛掉无资格者，选中后`ChangeTheLeaderOfAlleyInternal`更新AssignedClanMember、替换守军Roster中的Hero并延迟传送新Leader到Settlement。Alley受攻击时菜单此项禁用。此处改变责任Hero，不等同占领/改Owner。
- **管理 Alley 打手Roster**：Town GameMenu或 manager 对话打开专用 PartyScreen；Helper只允许Troop transfer，禁止传Hero/Prisoner，Done条件检查一般打手人数处于Model给定最小/最大值。Done回调把左侧Roster保存到PlayerAlleyData，Scene已开启时刷新 Alley Agents。W2-AZ 已实测Town `manage_alley_troops`路线，通过当前Native `PartyCharacterVM`逐名转移、PartyVM Done/Cancel处理；取消草稿不改两侧真实Roster，Done提交后左右成员按原生结果变化，越过Alley最小/最大兵数时Done禁用。只覆盖Campaign Map菜单入口；负责人3D对话中同一PartyScreen入口及Scene已有时刷新Agent尚未运行测试。
- **放弃 Alley**：Town菜单确认或 manager 对话确认都会`PlayerAlleyData.AbandonTheAlley`，将非Hero守军转回MainParty、清空PlayerAlleyData并移除Owner；对话Scene路径额外清理非玩家Alley Agents。W2-BA已实测Town菜单No回manage_alley且不改变状态；Yes在非UnderAttack夹具下将普通守军返还MainParty、清掉PlayerAlleyData/Owner并回到Town菜单。源码请求`town_outside`，但实际运行观察menuId是`town`并显示放弃通知，按玩家可见画面/遥测记录。攻击中放弃会把Owner交给敌对帮派，不属于该安全分支。它和放弃聚落Fief不是同一行为。
- **领取本周打手**：`AlleyCampaignBehavior`注册的负责人Conversation分支是玩家先选`alley_talk_start_player_owned_alley_manager_answer_2`询问志愿者；`PlayerAlleyData.RandomFloatWeekly`在离上次招募未超过7日时固定返回2（暂无），否则以Campaign周和Alley Tag作Native seeded float。对话按`RandomFloatWeekly>0.5`走“下周再来”，否则显示`GetTroopsToRecruitFromAlleyDependingOnAlleyRandom`得到的兵种/数量。Default模型阈值：`r≥0.5`返回空Roster；`0.3<r<0.5`是thug1+地区BasicTroop1；`0.15<r≤0.3`为thug2+basic1+其第0级升级兵1；`0.05<r≤0.15`为thug3+basic2+升级兵1；`r≤0.05`为thug2+basic3+升级兵3。`r=0.5`时上游无兵条件用`>0.5`而模型空Roster条件用`>=0.5`，需保留为边界分支未知，不能把模型值透给Agent。若有兵，玩家选`alley_talk_start_player_owned_alley_manager_volunteers_3`确认，原生把Roster加入MainParty、发QuickInfo并更新LastRecruitTime；未见Gold扣除或容量确认。它不是Town `recruit_volunteers`菜单。来源确认负责人对话入口按`AssignedClanMember == Hero.OneToOneConversationHero`筛选。W2-BB与运行`20261006-005326`确认`town→manage_alley`只开地图管理面板，人员overlay为0、无Mission，选项不含对话。独立运行`20261005-163503`/`163815`从Native `town_streets`打开`vlandia_town_e`中心Mission；Harness-only diagnostics在全场景中找到Assigned Hero，但人物不在Town menu `settlementOverlayCharacters`。其样本距离为26.697与136.178；8个0.5秒Native前行输入只在一个样本中将主角移动9.959、目标间距降到127.982，尚未进入12单位局部观察或对话。测试save module set仅含四前置、Native/SandBoxCore/CustomBattle/Sandbox/BirthAndDeath及Chronicle，无额外Gameplay overhaul；存档hash未变，进程已清理。用户回忆“进入巷子”也许可对话，但本机当前版本面板画面不同，先保留为不确定而非覆盖运行事实。负责人如何在Town scene中被玩家定位、是否有其他真实入口、实际谈话/无兵/有兵分支、谈话结束返回和时钟结果仍待验证。

`TestResults/20261006-010249/Temp/AlleyLeaderSceneEntryResult.json`补充同一入口的 bounded visual probe：按镜头前方执行24次0.5秒Native MainAgent移动后，总位移29.980；Harness-only census中Assigned Hero距离196.842→167.336，但普通12单位`nearbySceneAgents`仍为空，未尝试隐藏目标导航/对话。引擎截图显示主角到达城门处且有“大门”提示；截图尚不能确认门是否挡路或需要玩家互动，该细节待核。源Campaign hash未变、游戏进程退出。这个实验说明直接固定前行仍未找到负责人，不是`town_streets`入口/交谈闭环通过。
- **回应 Alley attack**：仅在PlayerAlleyData.IsUnderAttack时出现与敌对帮派首领对话；可选Confront会结束当前Conversation并启动专用`OpenAlleyFightMission`。它不是地图 `MapEvent` 坐镇指挥入口，战斗后以胜/败更新 Alley Owner 与Roster，战役时钟按 Mission规则停走。

以上核心入口及状态写入由当前 `SandBox.CampaignBehaviors.AlleyCampaignBehavior` 与 `Helpers.AlleyHelper` 源码确认；多菜单/对话别名按同一个最终提交动作合并。AlleyLeader选择的Town菜单入口、管理Roster的Town菜单入口、放弃Alley的No/Yes原生后果均已有本机1.4.8测试；Chronicle只覆盖MAINLINE列出的窄菜单上下文，并非所有Alley交互都已适配。负责人对话上下文、对话进入Scene、已有Alley Mission时刷新Agent、袭击中Owner交接及不同Alley生命周期的运行效果仍未做视觉回归。

### Faction 犯罪值与处置

主角 Crime Rating 按 `IFaction` 分别保存；抢劫或对同王国居民实施侵害会增加相应派系罪恶值，处在战争状态和特定 Quest 行为有不同规则。默认每日模型根据目标派系与玩家的关系衰减罪恶值：自家 Clan 或作为君主的王国 -5/日；当前所属王国 -1.5/日；同王国其他 Clan -1.25/日；交战派系 -0.25/日；其他派系基础 -1/日。该派系下主角每拥有一个 Alley 又增加 0.5/日。具体犯罪行为的增量由调用者分别指定，不能把所有犯罪统一成一个常数。

默认等级边界是轻微 `(0,30]`、中等 `(30,65]`、严重 `≥65`，最大 Crime Rating 100；和平时针对玩家所属阵营的罪恶值可能按模型阈值下调。进入有罪恶值的定居点可走原版 `town_inside_criminal`/surrender 处置菜单，选项依等级、当前阵营和支付能力包含金币、影响力、接受可能致命的惩罚、惩罚加付款或无视指控等分支；处置通过 `PayForCrimeAction` 处理并可能回到 Town/Castle 外部菜单。付清成本以罪恶值相对最低可接受阈值的 `pow(x,1.2)` 计算，金币按约 `×100`，Influence 按原值。完整死亡、逮捕、关系和进入城镇权限副作用留待 I/J/G 交叉研究。

### Chronicle 当前覆盖

当前 AgentObserver 不返回 Settlement.Alleys、Gang Leader、Alley Owner/State、玩家 Alley 守军/攻击期限/收入/周招募、各派系 MainHeroCrimeRating 或犯罪菜单选项；Protocol 也没有经营 Alley、招募 Alley 打手、面对帮派进攻或处理 Crime Rating 的动作。静态源码已明确这里存在一个独立且会持续变化的城镇经济/治安支线生态，但 Agent 当前既看不到，也不能管理；这句话描述覆盖事实，不是设计结论。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Alley`、`DefaultAlleyModel`、`DefaultCrimeModel`、`CrimeCampaignBehavior`、`ChangeCrimeRatingAction`、`PayForCrimeAction`、`AlleyHelper`；`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.dll` 的 `AlleyCampaignBehavior`；Sandbox `ModuleData/settlements.xml`、`concept_strings.xml`；Chronicle `AgentObserver.cs`/`AgentProtocol.cs`。为 v1.4.8.119303 静态程序集和数据/菜单文本证据，未执行街巷战斗、占领、追击或赎罪 UI。

未知项：不同 Settlement alley tag/state 的完整生成与玩家可见地图入口；各个任务/对话/战斗结果对 Alley Owner 和关系的全部影响；玩家攻占/防守 Mission 的可用 roster、撤退/死亡/胜负处理细节；Attack 到期/被占领失败所有数据清理副作用；所有侵害行为的 Crime Rating 增量与 Arrest/接战/处置完整条件；巷道经营收入是否还经 Clan 财政其他比例或事件调整。

## D09 聚落访问入口、菜单与地点场景

### 地图抵达后的入口层级

玩家通过战役地图抵达并进入 Settlement 后，原版按类型建立当前聚落菜单上下文；常规菜单 ID 为 `town`、`castle`、`village`，村庄被掠夺时可能转至 `village_looted`。在地图移动后出现哪一种类型入口属于 MAINLINE `move` 契约；本节只说明进入后按菜单/地点如何继续。选项不是固定按钮全集：`GameMenuOption.GetConditionsHold`、`IsEnabled`、AccessModel、当前派系/任务/聚落状态会决定可见或可用情况，其他 CampaignBehavior 还会向菜单动态增加选项。

### 城镇 `town` 菜单和子菜单

| 玩家菜单入口 | 原版后续界面/操作 | 主要门禁或差异 |
| --- | --- | --- |
| Manage town | `TownManagementVM`：发展/项目队列、日常项目、总督、城镇每日数值、绑定村庄、商店等管理显示 | `SettlementAccessModel.ManageTown`；菜单 option 的 VM 转接由 SandBox View 注册，需从游戏内做完整视觉验证 |
| Recruit troops / `ACT-H04-03` | 玩家在`town`/`town_backstreet`/`village` Settlement菜单选`recruit_volunteers`，进入Native Volunteer RecruitmentView；候选来自当前Notable volunteer slots | `PlayerTownVisit.game_menu_recruit_volunteers_on_consequence`将三个菜单入口交给同一个`MenuContext.OpenRecruitVolunteers`；Gauntlet view创建RecruitmentVM，`ExecuteDone`提交Roster与Gold。不同于F09村庄强征、D08 Alley周招募和D07自动驻军招募。`TestResults/20260930-045312/Recruitment.log`实际核对Sargot Town菜单option可用和一人RecruitmentVM结果，也用Native Over Limit Inquiry测试拒绝/确认回调及off-menu拒绝；town_backstreet/village的运行可用性、完整Gauntlet视图/焦点及菜单时间仍未实测 |
| Settlement Characters overlay → choose Hero/Notable → Conversation | `SettlementMenuOverlayVM.CharacterList`只取当前`GameMenuManager.MenuLocations`中由`HeroAgentLocationModel.WillBeListedInOverlay`判定可列出的角色；选择后原版Conversation上下文动作按目标Hero创建其Location Mission | 先发`SettlementOverlayTalkPermissionEvent`；进入场景不等于已接Quest，任务选项/前置仍由该Notable原版Conversation决定 |
| Trade | `InventoryScreenHelper.OpenScreenAsTrade` 打开城镇市场 | SettlementAccessModel 交易许可/市场状态 |
| Go to keep | 进入 `town_keep` 聚落菜单，不立即进入 lordshall Mission | AccessModel 可能要求伪装/贿赂/拒绝；敌国或 Crime Rating会改变条件 |
| Go to the arena → Enter the arena | 先到 `town_arena` 再打开 `arena` Location Mission | 仅白天、不可伪装等条件；不是打开城镇管理面板 |
| Go to tavern district → Visit the tavern | 先到 `town_backstreet` 再打开 `tavern` Location Mission | 人物/Issue/招募候选由具体地点/任务条件动态决定 |
| Enter smithy | 打开锻造界面 | Craft 访问权限、角色/耐力等由锻造系统门禁决定 |
| Take a walk around the town center | `town_streets`→`LocationComplex.Current.GetLocationWithId("center")`，调用`LocationEncounter.CreateAndOpenMissionController`打开中心 Location Mission | `SettlementAccessModel.CanMainHeroAccessLocation`；Condition为center Locations调用`MenuHelper.SetIssueAndQuestDataForLocations`，该入口对center Locations调用Issue/Quest检查；GameMenuOption.OptionQuestData经GameMenuItemVM生成菜单任务标记，不代表本次必有任务Notable |
| Wait here | 切换到 `town_wait_menus` 原生 Wait menu | 通过 `StartWait` 推进时间；见 A02/MAINLINE，不等价于驻足查看菜单 |
| Leave | 退出聚落，返回 Campaign Map | 军团/海上等状态可限制 |

1.4.8运行`TestResults/20260927-014511/Temp/TownCenterMissionResult.json`沿真实菜单选项验证Sargot `town_streets`可用，并进入`vlandia_town_e` MissionState；Campaign时间Stop，MainAgent从镇门外开始。Harness以32次0.35秒有界输入自然移动约18.989单位，输入lease会清零且 Campaign Day不变；局部观察样本找到的两个Agent都是Soldier，无Notable。该运行仅验证Town中心菜单→Location Mission与局部移动/观察起点；其它运行在附近视野里发现过Townsfolk，也仍未找到Notable或进入对话，不能从单个空局部列表推断整场景没有Notable。更详细的Mission Agent/Focusing链由L07与MAINLINE记录。 后续`TestResults/20260927-033506/Temp/TownCenterMissionResult.json`中`town_streets`的原版`OptionQuestData`为`AvailableIssue`（1），表明该样本镇中心存在可用Issue标记；`TestResults/20260927-034201/Temp/TownCenterMissionResult.json`沿44个短步抵达城门口后观察到镇民，但导航期间对方移动到门另一侧，最终Native Focus命中CastleGate而非角色。标记说明存在Issue，不表示主角已到人或成功交谈；场景路径/Focusing细节见L07与MAINLINE。 `TestResults/20260927-040042/Temp/TownCenterMissionNativeFocusState.json`进一步显示引擎导航能让主角到一名普通瓦兰迪亚新兵约1.42单位处，原版Focus命中该Agent，画面出现`F 交谈`提示；不等于向该NPC执行了对话，也不是Issue Notable。

用户确认Settlement本地人物overlay提供所有当地Notable名字及Issue蓝色标志；选人后有QuickConversation（交谈）与Conversation（造访）。1.4.8 SettlementMenuOverlayVM创建两个独立Context action：QuickConversation对应Native中文“交谈”(OPhlqUVl)，检查SettlementOverlayQuickTalkPermissionEvent并调用CampaignMapConversation.OpenConversation；Conversation对应“造访”(toK51MD4)，检查SettlementOverlayTalkPermissionEvent，经OnPlayerStartTalkFromMenu和LocationEncounter.CreateAndOpenMissionController启动目标Hero的Location Mission。用户观察交谈完回地图聚落菜单；造访完仍留Location Mission，须长按Tab约2秒离场。旧TestResults/20260927-052705/Temp/SettlementOverlayConversationResult.json只核验造访分支：targeted Mission partner/Greeting/Options正确，Campaign Stop、Quest 0→0、源档hash不变且进程正常清理。Chronicle旧talkToSettlementHero复刻的是造访，不能再当成交谈；分别实现talkToSettlementHero与visitSettlementHero。Settlement overlay Observer只返回当前聚落本体列出的Hero和Quest markers，不代表全图Issue giver；地图贵族党派蓝标与QuickConversation时钟/返回尚待独立测试。

`town_keep` 另含通往 dungeon、驻军管理、向驻军捐兵、stash、lord’s hall 和返回 town 的选项。Manage Garrison 通过 `PartyScreenHelper.OpenScreenAsManageTroops` 打开真实 troop transfer 界面；Donate troops 是另一种受限的派对捐兵入口。`town_keep_dungeon` 包含捐俘虏、管理俘虏、进入 prison Location 和返回。Lord’s Hall 与 dungeon Location 是进一步打开的物理 Mission，不是名称为 keep/dungeon 的当前菜单本身。

### 城堡 `castle` 菜单

城堡没有 town-center/tavern/arena 那组入口；它有城堡管理、驻军管理/捐兵、stash、围绕城堡走动、领主大厅、地牢、等待、返回军团和离开等选项。管理城堡同样进入聚落管理 VM；“走动”对应 castle location，lordhall/prison 对应进一步的 Location Mission。访问领主大厅、地牢按派系关系、战争、Crime Rating、贿赂等条件判断。Castle 与 Town 共享部分选项 ID 但不可假定全部选项相同。

### 村庄 `village` 菜单

Normal 村庄入口包含招募 troops、购买产品、走入 village center、等待、返回军团和离开；`VillageHostileActionCampaignBehavior` 等还按玩家身份、与该阵营的关系和当前 VillageState 增加 raid/强征 supplies/volunteers 或警告选项。Looted 村庄菜单只保留符合受损/在海上状态的退场选择，并非仍可沿用 Normal village 全部菜单。玩家先从 Settlement 菜单选择地点/操作；进入实体村庄 Scene、与头人 Notable 对话、处理 Issue 是后续独立交互链，不能把 `village` 菜单出现当成已完成谈话或已接任务。

### 门禁与运行层级

`DefaultSettlementAccessModel` 为主城堡/领主大厅、地牢、中心、竞技场、酒馆以及 Recruit/Trade/Wait/ManageTown 等动作提供访问结果和禁用理由。领主大厅/地牢可以是 FullAccess、LimitedAccess（Disguise 或 Bribe）或 NoAccess；同阵营、OwnerClan、Neutral/War、犯罪、在城内伪装与 Bribe 条件会改变结果。竞技场夜间关闭；Tavern、Town Center、Village/Keep 位置亦各自经地点/任务条件检查。

这些入口分为不同运行层级：GameMenu 切换、UI Window/PartyScreen/InventoryScreen、物理地点 Mission、Conversation/Issue 任务流程。相同屏幕的直接 VM/API 调用跳过了前置菜单条件、View 生命周期或 Location Mission 上下文，不可作为从玩家入口走通的证据。自然 Campaign 时钟遵守 A02；只有 wait 菜单明确以 `StartWait/EndWait` 控制等待，进入物理 Location 则进入 Mission 语义；普通菜单选项不应被包装为隐含的快进/暂停。

### Chronicle 当前入口覆盖

`AgentObserver` 在已有 `CurrentMenuContext` 时输出当前 `GameMenu` 的可用选项 ID、文本、available/enabled/isLeave；它不会预先列出 Town/Keep/Village 尚未打开的子菜单和物理 Location 的所有按钮。Protocol `menuSelect` 会核对当前菜单 ID、选项 ID 和 `GetConditionsHold` 后运行本体 option consequence；不能任意点尚未出现的选项，重复型选项不支持。部分后果会直接打开原生 Trade/PartyScreen/Mission；当前协议没有通用的任意 UI 点击或 3D 地点导航能力，所以“菜单后果调用完成”不代表它会继续完成物理 Scene 的全部互动。

本地协议还存在专用招募/交易流程，但这些操作的自动验证不能倒推为已从可视窗口进入并体验。当前测试最高只说明相应本体 VM/事务可被 Harness 调用；Town/Keep/Village 从世界地图菜单到具体 3D 场景、再到返回地图的连续视觉流仍未运行验收。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `PlayerTownVisitCampaignBehavior`、`DefaultSettlementAccessModel`、`GameMenu`/SettlementAccess 接口；`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.View.dll` 的 `MenuTownManagementView`；Sandbox `TownManagementVM`、`VillageHostileActionCampaignBehavior`、`AlleyCampaignBehavior`、`CrimeCampaignBehavior` 和 `GameMenu` 注册；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`。本节依据 v1.4.8.119303 安装源码和 XML/菜单定义，未开启游戏逐一目测所有条件与按钮。

未知项：MapScreen 实际到达时的鼠标/键盘操作与各入口 GameState 切换全链；TownManagementVM、PartyScreen、交易屏幕、菜单选项的可视呈现、默认焦点、关闭/取消恢复行为；敌对、犯罪、城镇状态、在海上、部队归属等全部条件组合；Quest/Issue 从人物对话回到菜单/地图的入口矩阵；Mod 新增 MenuOption/Location 对 Chronicle 当前菜单观察和操作的影响。

## D10 易主、占领与后续聚落状态

### 原版所有权变更的单一入口

`ChangeOwnerOfSettlementAction` 用不同 detail 标记 Default、BySiege、ByBarter、ByLeaveFaction、ByKingDecision、ByGift、ByRebellion、ByClanDestruction。fortification 所有者写入 `Town.OwnerClan`，由 Clan 侧移除旧领地/登记新领地；Settlement 的地图派系和 Owner Hero 随现任 Clan 解析。Town 会将 `IsOwnerUnassigned` 清为 false。城堡/城镇文化字段并不由这个 action 改写。

随后 action 处理驻军、总督、地图视觉和事件：任何 fortification 易主都会移除原 Governor；BySiege 会销毁现存 Garrison Party，再在缺失时创建新驻军 Party，因此攻占城镇的守军 roster 不会作为完整驻军保留到新领主名下。非 siege 的易主分支是否保留现有 garrison，由具体 action/detail 与其他事件逻辑共同决定，不能拿攻城结论套用到贸易/赠地/王国决策。

通过围城、Clan毁灭或家族离开王国造成的 fortification 易主会以 `openToClaim` 参数通知后续认领处理；攻城入口还记录 `Town.LastCapturedBy`。Campaign `OnSettlementOwnerChanged` 会通知订阅行为并传递新/旧 Owner、Capturer 和 Detail，具体后果由各订阅者分摊，不是某一条统一的“换领主奖励”公式。

### 已追到的跨系统后果

- Settlement 及绑定村庄的地图视觉会标脏。村民 Party 若正朝绑定村庄移动、并且没有与新 Owner 开战，部分路径会切换到 Hold；战事/围城相关的目标 Party 也可能被要求停止原目标。
- `BuildingsCampaignBehavior` 监听易主：新 Owner 不属于 Player Clan 时清除现有普通建设队列；当前日常项目和既有建筑等级不由该分支直接清空。建筑队列结果因此存在易主方向差异。
- `VillageTradeBoundCampaignBehavior` 监听易主并重新计算 TradeBound；村庄 `Bound` 本身仍指向原城镇/城堡，所以 Village MapFaction 随被绑定聚落的新派系解析。Bound 与 TradeBound 的更新是不同机制。
- `GarrisonTroopsCampaignBehavior` 在攻城易主且 `openToClaim` 时记录“刚攻下的聚落”，后续领主 Party 进入时进行原版 AI 转兵；它会排除普通玩家 MainParty（除刚占领特殊场景外），不等价于玩家手动管理驻军。
- `OnSettlementOwnerChanged` 还可触发 Kingdom/fief claim、日志、通知和 NPC 评论；不同 detail 继续影响认领与王国决策链。相应政治、战争、叛乱与日志资料分属 C/J/G 域，本段不重复重写。

这个 action 本身没有直接重置 Prosperity、FoodStocks、Loyalty、Security、Militia、Buildings 或 Settlement.Culture。可是换 OwnerClan 会改变所属 Kingdom、政策、Governor（被移除）、安全/忠诚/经济模型输入和 Village/TradeBound 等后续状态；这些是状态模型随时间重新计算的连锁，而不是“易主时所有发展值归零”。围城战损、驻军被捕获/伤亡和建设 queue 的 detail 分支应分别从 G/F/D05 核对。

### 玩家可见性与 Chronicle 当前覆盖

原版使用地图通知/事件日志、王国领地认领/决策以及 `SettlementOwnerChanged` 相关行为表现易主；攻城、赠地、叛乱、离开王国、王国决策等不是同一种玩家入口，也可能具有不同的 `openToClaim`/驻军后果。玩家地图附近 Settlement 当前只返回 type、距离、hostile、underSiege 等，Chronicle Observer 不提供 OwnerClan/owner Hero、所有权变化原因、Bound/TradeBound、认领资格、建筑 queue 是否被清空或新旧驻军差异；Protocol 也没有易主/认领操作。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `ChangeOwnerOfSettlementAction`、`Town.OwnerClan`、`Clan.OnFortificationAdded/Removed`、`Settlement.BoundVillages`；`BuildingsCampaignBehavior`、`GarrisonTroopsCampaignBehavior`、`VillageTradeBoundCampaignBehavior`、`SettlementClaimantCampaignBehavior` 及易主通知/日志类型；Chronicle `AgentObserver.cs`。结论基于 v1.4.8.119303 静态源码；本节未在存档中触发围城、王国决策或所有权转换，也没有检查玩家收到的可视通知。

未知项：全部 OnSettlementOwnerChanged 订阅者的逐一完整清单及运行顺序；攻城胜利后 defender garrison 的士兵/俘虏去向与战斗结算顺序；失去/取得 fief 的 relationship、影响力、收入、通知和日志按 Detail 的差异；领地认领期间无人所有状态的可视入口、超时处理与多 Clan 冲突；绑定村庄和贸易路线在战争、叛乱、投降或新王国成立后的完整链路。

### 时间、证据等级与跨域边界

读取 Settlement/Town/Village/Alley 字段本身和直接 `ChangeOwnerOfSettlementAction` 状态转换都不调用 Campaign clock 控制；每日状态、建筑、驻军、村庄生产/恢复和 Alley 犯罪/帮派处理由各自 Campaign Tick 在原生时间推进时运行。D09 的 Wait 菜单使用原生 StartWait/EndWait；进入真实 Location/Mission 按 A02 的 Mission 时间语义处理。普通菜单、移动或占领动作不应暗中追加测试快进/暂停。

各 D01-D10 段落已分别列出本机 v1.4.8.119303 程序集、SandBox 行为、ViewModel、官方模块数据或 Chronicle 代码的来源；这些属于源码/资源核实。没有进行当前界面逐项点击、全条件组合运行、Mission战斗、围城、领地转换或长周期经济的视觉/运行验收。遇到直接 API 与玩家 UI 的差异，文中分别写出已证实调用链和未核实的界面/状态，不能互相替代。

D 类观察总缺口：目前 Nearby Settlement 快照没有 OwnerClan/文化/Bound 与 TradeBound、Town/Village 发展指标、建筑/项目、Governor/Garrison roster、Alley/犯罪状态或易主原因。Observer 仅能读取当前已打开 GameMenu 的动态菜单选项；未打开的子菜单与 3D Location 内交互不可由该字段推断。对应实际玩家入口、按键/菜单、访问限制、原版副作用和未知分别在 D01-D10 记录，跨域去重与行为分母仍留给 W1-M。

## 研究范围状态

D01-D10 已完成首轮静态聚落对象、发展、生产、建筑/项目、总督/驻军、犯罪巷道、玩家入口和易主后果盘点；整体仍是源码研究首轮，尚未声称所有动态条件、UI路径和运行时结果均已穷尽。
