# D 类研究：聚落与领地

状态：机制盘点中；D01-D03 已完成首轮静态盘点，目前继续研究 D04 村庄状态与生产，未进行方案评审。

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

### 时间与证据边界

D01 中的实体分类、所有权查询与绑定关系是读取对象状态，不会自行推进 Campaign 时间。城镇/村庄的每日状态计算由各组件的 `DailyTick` 执行，并受 Campaign 时钟调度；具体数值模型和状态变化分别留给 D02-D04。直接读取属性不等价于玩家打开地图百科或聚落界面；本节没有声称 UI handler 与直接 API 的完整交互已经运行验证。

证据：本机 `TaleWorlds.CampaignSystem.dll` 的 `Settlement`、`SettlementComponent`、`Town`、`Village`、`Hideout`；Chronicle `AgentObserver.cs` 的附近聚落采集与序列化逻辑。当前本节结论来自 v1.4.8.119303 安装程序集反编译及本地代码静态核对。

未知项：玩家地图上不同聚落类型的精确图标/悬停/ALT/百科字段及遮蔽规则；OwnerClan为空或绑定改变的具体场景；每类 Settlement 的地图可见与侦察状态如何由原版行为更新；直接 VM/API 读取与玩家界面展示之间的全部差异。后续 D02-D10 分域补足，不从这些未知项预设设计方案。

## 研究范围状态

D01-D04 已完成首轮静态对象、城镇与城堡发展、村庄状态/生产和 Observer 覆盖盘点。D05-D10 尚未研究；继续按 `SYSTEM_INVENTORY.md` 的 D 域范围逐项核对，不将此文档视作聚落系统整体已完成。
