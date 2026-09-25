# E 类研究：经济与贸易

状态：机制盘点中；E01-E05 已完成首轮盘点，目前研究 E06 Party 经济，未进行方案评审。

适用本体：Bannerlord v1.4.8.119303。基于当前安装 `TaleWorlds.Core.dll`、`TaleWorlds.CampaignSystem.dll`、官方模块物品 XML 和 Chronicle 本地 Observer/Protocol 源码。静态对象核对不表示物品市场或背包 UI 已运行验证。

## E01 物品与商品对象

### 定义对象与分类

`ItemObject` 是物品的定义对象，以 `StringId` 标识，并持有名称、ItemType、ItemCategory、基准 Value、Weight、Tier、文化、旗标和可选 ItemComponent 等数据。ItemType 区分武器、箭矢/弩矢、盾牌、防具、Goods、Horse/Animal、书籍、旗帜等类别；具体装备能力则来自 Weapon/Horse/Armor/Banner/Saddle 等 ItemComponent。一个物品不是“某玩家背包里的一件实例”，而是可供库存、装备、战利品和市场引用的定义。

`ItemCategory` 是另一个数据层：它带有自身 ID、IsTradeGood/IsAnimal、替代品及 SubstitutionFactor、BaseDemand/LuxuryDemand 和 Property。Property 的默认枚举包括 BonusToProduction、BonusToFoodStores、BonusToProsperity、BonusToLoyalty、BonusToMilitia、BonusToGarrison、BonusToTax。这些 Settlement/市场效果标记不等于 ItemType，也不直接等同实时市场售价。

必须区分如下字段：

- `ItemObject.Value` 是 ItemObject 的基础数值；城镇特定的购买价/出售价由 MarketData/InventoryLogic 等在 E02 研究，不得把 Value 当成玩家当前成交价。
- `ItemObject.IsFood`、`IsTradeGood`、`IsAnimal`、`NotMerchandise`、`IsUniqueItem`、`IsCraftedByPlayer` 等是不同旗标/分类，不能仅用 `ItemCategory.IsTradeGood` 替代所有判断。
- `ItemObject.IsTransferable` 会询问 `ItemValueModel.GetIsTransferable`；是否能在 UI/PartyScreen 中转移并非只由物品类别名称决定。

官方物品定义分散在 Native/SandBoxCore/StoryMode 等模块 XML（例如 SandBoxCore 的 `ModuleData/items/*.xml`）；其他启用 Mod 也能增加对象、组件或替换数据。因此“官方基础类型和字段”与“当前完整加载物品清单”是不同分母。当前 E01 不枚举全部 ItemObject，也不把 XML 行数视为玩家行为数。

### 库存不是 ItemObject 列表

`EquipmentElement` 代表一个可装备/交易的具体物品形态，除 ItemObject 外还可带 ItemModifier、IsQuestItem、CosmeticItem 等状态。`ItemRosterElement` 再将一个 EquipmentElement 与数量关联；`ItemRoster` 以这些元素集合表示 Party/Settlement 等对象的库存，并维护 VersionNo、TotalFood、FoodVariety、TotalValue、TradeGoodsTotalValue、驮畜/牲畜/坐骑数量等缓存值。故库存的“物品种类”“变体/修饰”“数量”“计算缓存”是不同层次。

原版有多种 Roster/物品容器，party cargo、英雄装备、城镇市场、村庄库存、Settlement stash、战后可领取战利品和 InventoryState 的左右交易侧不能混成同一背包。哪些 UI 入口如何在它们之间移动物品、何时 Commit/取消、和角色装备槽如何关联，分别留到 E07 与 E02/D09 交叉研究。

### 价格与物品用途边界

基准 Value、商品类别需求字段和市场成交价是三个不同概念。市场价格与供需/市场库存及买卖方向的关系归 E02；商品生产归 E03；装备、负重、Party日粮和使用用途还涉及 H/F 等域。本节只建立数据类型与容器模型，不从物品字段直接推导价格、可售性或玩家如何操作。

### Chronicle 当前物品信息与操作覆盖

`AgentObserver` 当前对主队只返回 `itemCount`、Food库存、Food总量变化、cargoWeight 和 cargoCapacity；不会列出普通 Party ItemRoster 的 item ID、名称、类别、数量、modifier、装备槽或转移条件。战后活动 `InventoryState` 仅输出模式、双方物品数量及是否有 Inventory Handler，不输出逐物品清单。故 Agent 的常驻观察不足以识别背包里具体有什么非食物商品。

已有独立交易查询 `AgentProvisioning.GetTradeOptionsJson` 可在城镇环境下使用原生 `InventoryLogic` 列出当前市场买入项与 Party 出售项的 ID、名称、数量、当前方向价格、重量及是否食物；当前 Protocol 还有按 ItemId/数量提交交易和食品购买的窄接口。这是本地按需交易适配，不是常驻库存观察，也不是玩家在原生交易 GUI 里逐格操作的证据。相关成交价格、库存变化和 UI/API 差异继续见 E02/E07。

证据：本机 `TaleWorlds.Core.dll`（`ItemObject`、`ItemCategory`、`EquipmentElement`、`ItemRosterElement`）、`TaleWorlds.CampaignSystem.dll`（`ItemRoster`）；官方 `Modules/SandBoxCore/ModuleData/items/*.xml`、StoryMode物品XML；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`、`AgentProvisioning.cs`。结论为当前 v1.4.8.119303 安装源码/数据及本地适配静态核对，未视觉验证背包/交易各页。

未知项：当前加载模块顺序下的完整可用 ItemObject/ItemCategory 集合及 Mod 覆盖；ItemCategory demand 数据进入 E02 价格模型的全部公式；全部装备/修改器/任务物品在各 InventoryMode 下的限制；Chronicle 未打开 InventoryState 时是否存在其它可核验的逐物品观察源；玩家在正式库存和交易屏幕内的实际排序、筛选、修饰键和 Commit/取消副作用。

## E02 市场库存与动态定价

### TownMarketData 的价格状态

城镇市场以 `ItemCategory` 而非每个 ItemObject 为键保存 `ItemData`：Supply、Demand、InStore 数量和 InStoreValue（该类别库存 item base value 的数量加权和）。因此一个商品的售价不仅是它自己的 `ItemObject.Value`，同类库存也会影响其 price factor。

`TownMarketData.GetPrice` 将查询交给当前 `TradeItemPriceFactorModel`，参数包括具体 EquipmentElement、买卖方向、交易 Party/商人、该类别 InStoreValue/Supply/Demand。城镇 Owner Party 的 `ItemRoster` 变化通过 `OnTownInventoryUpdated` 更新类别库存统计；`TradeCampaignBehavior.DailyTickTown` 也会定期从当前城镇 roster 重建库存值。因此市场货物变化可以在库存缓存更新后影响类别报价。Village 的 `GetPrice` 则委托给 TradeBound Town 市场，具体 Village 交易入口留待 D09/E03。

### 默认价格倍率

`DefaultTradeItemPriceFactorModel` 先算类别基础倍率。关键分子为 Demand，分母综合 `0.1 × Supply + 0.04 × InStoreValue + 2`；库存出售的价格预估会先将本次转入物品的 BaseValue 计入库存值。之后按类别用不同指数计算并限幅：ItemCategory.IsTradeGood 类别倍率约束在 0.1–10，非贸易商品约束在 0.8–1.3；动物类别指数也不同。

最终成交还叠加根据买/卖方向、商品或装备类别、买卖双方阵营/商人类型、PartyTradeModel 与适用 Perk 等计算出的 TradePenalty：买入倍率乘以 `1 + penalty`，卖出价格按 `1 / (1 + penalty)` 调整。`GetPrice` 把 EquipmentElement 的 ItemValue 乘以倍率，买入向上取整、卖出向下取整，并把最终单价至少限制为 1。由此 Base Value、当前市场单价、同类供需/库存和交易者优惠是四个不同信息层。

### 供需初始化与更新调用边界

新战役 `TradeCampaignBehavior.InitializeMarkets` 为所有有效 ItemCategory 初始化 Supply=2、Demand=3；Town MarketData 还暴露 AddSupply/AddDemand/SetSupplyDemand。默认 `SettlementEconomyModel` 提供随城镇繁荣度计算的每日需求与供需平滑模型（旧值 85%、新值 15%，Supply 有下限），但本轮在当前 1.4.8 安装源码中尚未把该模型的每日结果应用到 TownMarketData 的完整调用者闭环；`TradeCampaignBehavior.DailyTickTown` 当前追到的是更新 InStore。不能据此预先声称默认 Supply/Demand 每日一定自动漂移或被所有事件更新。

这意味着本轮已经确认两条价格动态来源：Town market 实际库存和交易者情境模型；供需值除新档初始化外的所有 native 写入来源仍需沿 caravan/trading actions/外部 Mod 继续核对。其他 Mod 可以直接扩展这些公开 MarketData 接口，故“本体调用链”与“玩家当前模块组合的市场行为”也须分开。

### 玩家入口与 Chronicle 当前适配

城镇玩家菜单 `trade` 通过 `InventoryScreenHelper.OpenScreenAsTrade` 打开原生 Trade InventoryState；点击报价和完成事务属于 InventoryLogic/View 路径（菜单入口见 D09）。本地 `AgentProvisioning.GetTradeOptionsJson` 以 `InventoryLogic`、Town MarketData 和 `useBasePrices:false` 列买入/卖出报价；`TradeItem` 创建 TransferCommand，检查数量/金币/负重和 `CanPlayerCompleteTransaction`，调用 `DoneLogic` 后核对双方库存数量与金币差。它是在 Harness/Protocol 中直接驱动本体交易逻辑的适配，不等同于已自动操作可视 Trade Inventory UI。

当前 Observer 常驻状态不列出市场 item price/stock 表；玩家在 Town 环境请求 tradeOptions 才能获取具名报价。对不同 Settlement、被俘/战争、特殊交易品、商队、村庄市场、修改器装备和事件影响的动态报价，未声称已全覆盖。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `TownMarketData`、`ItemData`、`TradeCampaignBehavior`、`DefaultSettlementEconomyModel`、`DefaultTradeItemPriceFactorModel`、`Town.GetItemPrice`；`TaleWorlds.CampaignSystem.dll` InventoryLogic/Trade；Chronicle `AgentProvisioning.cs`、`AgentObserver.cs`、`AgentProtocol.cs`。静态证据版本 v1.4.8.119303；本节未实机跑市场价格/供需时间序列。

未知项：默认 supply/demand 模型的完整消费者与每日/每周更新链；Caravan/商队/商人买卖对 MarketData Supply、Demand、InStore 的全部写入；各项 TradePenalty 全部规则与真实 UI 展示；Modified EquipmentElement、交易数量对阶梯报价和单笔合计的完整差异；其他 Mod 替换 Model/交易逻辑后的当前实际加载表现。

## E03 村庄生产、商路与城镇供应

### 生产到运输的分段链

村庄经济不是 `VillageType.Productions` 直接持续写入绑定城镇市场，而是分段流转。D04 已记录：每日生产行为先将商品/食物放入村庄 Settlement 的 ItemRoster；生产受 VillageState、Hearth、仓库容量和当前产量模型影响。E03 在此接续“已产出的村庄 roster 如何变成城镇库存”。

Villager Party 在村庄与城镇之间承担运输。原版按小时聚落 tick 对正常、无 MapEvent 的村庄进行尝试：随机机会通过、村庄物品总量至少到仓储容量、Party/地图条件允许时，会创建/补充 Villager Party，从村庄库存随机批量取货（每轮按单项约五分之一并受载重容量限制），然后设置目标为 `Village.TradeBound` 城镇；目标缺失或围城时不会照常发运。货物上限不是一个固定数量，而与仓库容量、商品重量和 Party InventoryCapacity 有关。

Villager Party 到达 Town 时由 `VillagerCampaignBehavior.OnSettlementEntered` 调用 `SellGoodsForTradeAction.ApplyByVillagerTrade`。结算用目标 Town 的实时 `GetItemPrice(..., villagerParty, isSelling:true)`，受城镇金币限制；成交商品从 Villager Party roster 移到 Town Settlement owner 的 ItemRoster，城镇金币扣减、PartyTradeGold 增加。低价值 Pack Animal 有额外保留规则，故“载货总量”不等于“所有物品都会卖掉”。市镇库存更新再反映到 E02 的 TownMarketData 当前在店统计。

完成返乡后，Villager Party 携带的交易收入在进入 Home Village 时由 SettlementTaxModel 计算税额，累加到 Village.TradeTaxAccumulated 并清空该 PartyTradeGold。税款实际进入 Clan/领主财政的后续结算调用留给 E07，不在此处推断为立刻到账。战斗损失、封锁、围城、敌对与 Party 销毁会打断“生产→运输→市场”链；村民队伍被打败时 Loot 由战斗/掠夺规则处理，不能把本地库存视为必然到货。

### TradeBound 目的地选择

`Village.Bound` 与 `Village.TradeBound` 分开：Bound 若为 Town，则 TradeBound 直接是该 Town；若 Bound 为 Castle，`VillageTradeBoundCampaignBehavior` 会按新档、易主、战争/和平与 Clan 王国关系变化重新选 trade destination。默认模型先找最近且同 MapFaction 的 Town；没有合格目标时再找距离范围内、非同派系但不处于战争关系的 Town；超出预估路程范围则不分配 TradeBound。

默认距离门槛约以“三倍最近城镇间距”按估算 Villager Party 速度换算成行程时间，再转回 MapDistanceModel 距离比较。该路由属于默认 Model，可被其他 Mod 替换；它不是“绑定城堡旁最近城镇”的纯几何直线距离。战事/城主变动重选目的地可能改变已存在的商路，即使村庄 Bound 本身未改变。

### 玩家贸易与自治贸易的区别

玩家从 Town `trade` 入口与市场进行一次直接 InventoryLogic 买卖；Villager Party 则由 Campaign 自动移动，并在到 Town 时走专用 `SellGoodsForTradeAction`，按照 PartyTradeGold 和 Village tax 流程结算。它不是由 AI Agent 决定每种商品是否卖出，也不是玩家 trade UI 的自动复刻。村庄商品在 NPC 商路完成前，玩家/其他系统能否按该村庄 roster 直接交易需由具体入口判断，不可假设已经计入城镇市场库存。

### Chronicle 当前观察覆盖

Observer 的附近 Party 列表可能识别可见的 `villager` Party 类型和部分人数/位置状态，但没有输出其 Home Village、TradeBound、携带物品、PartyTradeGold 或目的地商品清单；Settlement 快照也不返回 Village TradeBound 和库存。当前 Agent 能从 Town `tradeOptions` 看到当前城镇市场买卖项，但看不到完整村庄生产量、在途商品、运输失联和交付税收链。Protocol 没有建立商路、指挥 Villager Party 或修改 TradeBound 的动作。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Village`、`DefaultVillageTradeModel`、`VillageTradeBoundCampaignBehavior`、`VillagerCampaignBehavior`、`SellGoodsForTradeAction`、`TownMarketData`、`SettlementTaxModel`；Chronicle `AgentObserver.cs`、`AgentProvisioning.cs`。村庄生产上游细节依 D04；本节为 v1.4.8.119303 源码链核对，未在战役中运行长周期村庄商队观察。

未知项：默认 VillageTradeBound 在关系/海路/封锁/地图连接变化下的所有重算条件；村民贸易 Party 负载量、路程中被劫后恢复/重生及具体到货时间分布；村庄交易税从 Accumulated 到 Clan 财政的全部调用链；玩家/商队同一小时买卖对村庄商路库存的竞争顺序；其他 Mod 添加生产类型或贸易点时的兼容与当前启用情况。

## E04 Workshop 工坊

### 工坊与生产配方

`Workshop` 是固定在 Town 的产业实例，包含 WorkshopType、Hero Owner、Capital、InitialCapital、初始/当前运行时间及进度；`ProfitMade` 只是 `max(Capital - InitialCapital, 0)` 的差值，不等于累计销售额或 Clan 日收入。`WorkshopType` 定义多个 `Production`；每个 Production 以 ItemCategory 和数量列输入/产出，并有 ConversionSpeed。工坊经营因此需要配方输入、成本、转化速度、产物类别、库存/商铺资金共同计算，不是“每天固定发钱”的属性。

### 玩家取得与经营入口

Sandbox 将 shop worker 和 Workshop Owner 放入城镇中心 `center` 地点的对话系统；WorkshopType 的 owner/team 定位依 workshop Tag。面对 owner notable 的对话可购买其一个/多个公开工坊；条件包括没有与该 Town 派系交战、玩家黄金足够且玩家 Clan 拥有数没有达到 `ClanTier + 1` 的模型上限。单工坊价默认是 `WorkshopType.EquipmentCost + Town.Prosperity × 4 + Workshop.InitialCapital / 5`。买入最终调用 `ChangeOwnerOfWorkshopAction.ApplyByPlayerBuying`。

玩家与 shop worker 对话可查看生产类型、切换工坊生产（`ChangeProductionTypeOfWorkshopAction`；默认转换成本等于目标 WorkshopType 的 EquipmentCost）、出售工坊给 town notable，也能请求仓库入口。玩家变更生产不是改配方 XML，而是在现有工作坊实例上替换 WorkshopType；转让所有权由独立 action 处理。准确对话按钮/确认显示仍未视觉运行验证，所在 town center 的入口见 D09。

### 每日生产与市场/仓库流

`WorkshopsCampaignBehavior` 监听 `DailyTickTownEvent`。正常城镇每日对各 Workshops 运行生产和费用逻辑；城镇叛乱期间暂停生产 cycle，但仍处理每日 workshop expense。Notable 工作坊从 Town ItemRoster 读取并消耗输入类别，再由 TownMarketData 价格模型计算输入/产出估值；商品产物回到 Town ItemRoster/市场。

玩家所有工坊有额外仓库分支：其 WorkshopData 可决定从 Town 市场或玩家 Warehouse 获取投入，也可按 `StockProductionInWarehouseRatio` 把合格 trade-good 输出分入 Warehouse，不能入仓的或比例部分仍走 Town 市场库存。仓库有总体容量，输入不足、Owner资金不足、Town 金币或 Warehouse 容量限制、产物价值覆盖不了输入成本/转换成本等条件都可能让该 cycle 不发生。生产速率由 WorkshopType 配方、ConversionSpeed、所属地和 Perk/政策/建筑模型修正。

生产成功时消耗对应输入数量并调用 OnItemConsumed；产出写入 Town 或 Warehouse，并发 OnItemProduced。对可进入市场的产物，Town 金币与 Workshop Capital 会按当时价格结算；另有每日固定 Expense。从 Capital 或 Owner 资金支付均按 workshop 类型/余额状态区别处理，资金不足可能触发破产并转让 Owner。Gross sales、市场输入成本、固定费用、周转资金与 ProfitMade 不是同一数值。

### 所有权变化与原版后果

Workshop Owner Changed 会新建/删除玩家 Warehouse 数据；Town 所有权、Clan 进入战争、Clan 改变 Kingdom、Hero 死亡等 Campaign 事件可改变/转移玩家工坊。在玩家离开某 Town 的最后一个自有工坊时，该 Town Warehouse 物品会按原版行为转移到 MainParty 或清理；具体时机受是否仍拥有同镇工坊和当前 Settlement 上下文影响。完整破产、战时易主和王国/聚落易主的所有分支尚未穷尽。

### Chronicle 当前适配

Chronicle Observer 目前只给 PlayerClan 的 Gold/Influence/Renown，不枚举 OwnedWorkshops、输入/产出配方、Workshop Capital、DailyExpense、生产进度、Warehouse存货或所有者变更风险；没有 Workshop 买入/卖出/改产/经营 Warehouse 的 Protocol 动作。现有 town market TradeOptions 能看当前市场报价，不等价于管理 Workshop 或查询产能/盈利。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Workshop`、`WorkshopType`、`DefaultWorkshopModel`、`WorkshopsCampaignBehavior`、`WorkshopsCharactersCampaignBehavior`、`ChangeOwnerOfWorkshopAction`、`ChangeProductionTypeOfWorkshopAction`、`TownMarketData`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` Clan Finance workshop summary VM；SandBox workshop/shop-worker dialogues 与地点生成；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`。本节为 v1.4.8.119303 静态源码链核对，未运行购买、改产或多个周期收益验证。

未知项：全部官方 WorkshopType 配方/EquipmentCost、其他 Mod 配方及当前启用状态；玩家对话买卖/改产每一支实际费用和确认后状态；仓库 UI 的输入/输出比例和容量、取消/返回的提交边界；生产周期按库存、城镇金库和 MarketData 价格的全公式与随机变化；Workshop profit 与 Clan 每日财政报表的精确结算时间、破产触发及贸易经验后果。

## E05 Caravan / Trade Convoy 商队

### 玩家创建入口与初始化

玩家建立 Caravan 的原版入口是在城镇中心与 Merchant/Artisan notable 对话。对话根据所在 Town 是否有 Port 将其呈现为陆路 Caravan 或 Trade Convoy；要求玩家有可带队的 Player Clan Companion（不在 Governor 等互斥岗位）和足够第纳尔。玩家可选择标准或更高品质的护卫队伍，再指定一名 Companion 为 Caravan Leader。创建后该 companion 从 MainParty 离开，成为 caravan leader；新 MobileParty 的 owner 是 Hero.MainHero，并初始化 PartyTradeGold。

默认模型标准创建成本为 15,000；高品质为 22,500，第纳尔可受 Aserai Trader culture feat 修正。模型的 naval 参数默认不改变费用，但港口会影响陆/海模板。Standard PartyTradeGold 为 10,000，玩家拥有的 Caravan 额外 +5,000；高品质初始贸易金为 17,500，玩家仍有该加成。单物品类别最大购买预算默认 1,500。以上是 1.4.8 默认模型，不保证替换 Model 的 Mod 使用相同值。

这与 NPC 商人生成不是一个入口：`DailyTickHero` 对符合 `CaravanModel.CanHeroCreateCaravan` 的非玩家 Merchant Hero 按日随机尝试生成；该检查包含 Merchant occupation、无队伍归属、无有效现存 Caravan、Hero可用且能带队。玩家对话创建则选择一个陪伴 Hero 作为 Party Leader，owner 仍是 Main Hero；不能用 NPC 的 `CanHeroCreateCaravan` 前置解释玩家创建条件。

### NPC 贸易循环与目的地

`CaravansCampaignBehavior` 注册每日 Hero、每日和每小时 Party tick，以及进入城镇、离开城镇、MapEvent结束、Party被摧毁等事件。每小时 Caravan 在可贸易、没有遭遇/海上raft等可用条件满足时检查当前目标：敌对、目标被围/封锁或目标失效会触发重新选址。路线由适用城镇、Faction trade许可、价格指数、库存、NavigationType、路程、HomeSettlement 回访间隔、Party载货率等评分；海路和陆路受港口/船只条件区别约束。

Caravan 到达 Town 时先按本地 `Town.GetItemPrice` 尝试卖货，使用本地价格与预算/Party重量条件买货则发生在后续每日/小时交易决策中。购买倾向高价值品类并受分类预算、市场库存、单位类别限额、载重、初始资金与城镇金库约束；海上 Caravan 还有特定食物/船只逻辑。卖货会保留一定数量的包驮动物和牲畜，TradeActionLog 记录部分品类的买入/卖出地点与价格差，用于贸易传闻，而非完整逐日财务报表。

玩家可与可遇到的 Caravan 对话，询问贸易传闻或打开 Caravan Trader 的 Inventory trade；其 Owner/leader 可通过对话改变 HomeSettlement、禁止某些 Kingdom 作为贸易对象。Caravan 与目标城镇若处于战争关系，不会继续与之交易；玩家 Owner 的 Caravan 还会检查由对话配置的禁贸王国列表。这些控制是经营规则配置，不是直接指定逐步路线。

### 战斗、损毁与恢复

Caravan 是 CaravanPartyComponent 管理的 MobileParty，持有 owner、leader、home、商队资金、货物和护卫 roster。遭遇战后会按战斗处理幸存 roster、装备、负重/动物与船只；Party 被摧毁时 Caravan 行为会清理对话/交易日志等缓存。损失货物、主人资金和 companion leader 的最终去向受 MapEvent 与战后处理链影响，本项未运行验证。

原版每日商队重生尝试明确排除 Hero.MainHero，所以 NPC merchant Caravan 被毁和玩家自有 Caravan 被毁不能假定共享自动重建流程。当前源码未发现 player-owned Caravan 的通用自动重建承诺；本地不创建正式存档/不触发销毁测试。

### Chronicle 当前观察与动作覆盖

附近 Party 快照可把可见目标标为 `caravan`，并返回部分位置/移动/人数/估算实力信息；不会返回 Owner、Leader、Home、TargetSettlement、ItemRoster、PartyTradeGold、正在买卖的类别、交易日志或损毁恢复状态。Protocol 没有建立 Caravan、设置路线/贸易偏好、转移资金/商品、管理船只或重建商队的动作。现有 `dialogueSelect`/市场交易只在 Encounter/Conversation 已打开后可使用，不能自行完成战役地图追近、物理对话接近和创建所需 UI 流。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `DefaultCaravanModel`、`CaravanPartyComponent`、`CaravansCampaignBehavior`、`CaravanConversationsCampaignBehavior`、`TownMarketData`、`TradeItemPriceFactorModel`、`MapEvent`与Party销毁事件；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`。为 v1.4.8.119303 源码证据，未运行 Caravan 新建、长期跑商、被劫或恢复。

未知项：创建后的首个购买/移动时序及被指定 companion 的恢复/复用流程；目的地评分的全部权重、随机扰动和对外解释字段；交易日志/传闻与 NPC实际交易量、利润的关系；Naval船只补充/损毁、战损/俘虏与玩家 Owned Caravan 被毁的完整跨域后果；当前启用 Mod 对 CaravanModel/交易AI的替换情况。

## E06 Party 经济：工资、食物、货物与人员

### Party 的经济状态不是单一余额

`MobileParty` 的成员 `MemberRoster`、囚犯 `PrisonRoster`、物品 `ItemRoster`、剩余粮食比例、`PartyTradeGold`、工资支付上限及军团挂靠状态分别保存/派生。`PartyTradeGold` 对有 Leader Hero 的 Lord Party 映射到 Leader 的 Hero.Gold；Caravan/Garrison 等 Party component 则使用自己的 PartyTradeGold。玩家 Hero.Gold、Clan/Leader财政、PartyTradeGold、Town金库、Caravan流动资金不可当成同一“金币”。Clan 对这些Party/驻军每日工资支出的最终归属见 E07。

### 工资、预算与欠薪后果

`MobileParty.TotalWage` 由 `PartyWageModel.GetTotalWage(MobileParty, MemberRoster)` 计算；默认基础工资随 troop Tier 从 1/2/3/5/8/12/17 起算，Mercenary occupation 单位有加成，Hero、Leader、perk、garrison 等还可能有模型修正。`PrisonRoster` 不传入该 Party TotalWage 算式；囚犯会走食物消费链但不是普通在队兵工资。

Party component 可限制每天工资支付额，`PaymentLimit` 未有限额时返回模型上限；`GetAvailableWageBudget()` 是 PaymentLimit - 当前 TotalWage - 5。ClanFinanceModel 按 Clan 的余额和 party 类型计算实际付薪；支付小于 TotalWage 时写入 `HasUnpaidWages` 并依未付比例降低 Morale。若特定 party 长期超出工资/队伍容量限制，Desertion Model 还会选择 troop 从 MemberRoster 离开。欠薪造成 morale / desertion，不能只记录为金币差额。

### 粮食消耗、购买与牲畜

`MobileParty.FoodChange` 由 `MobilePartyFoodConsumptionModel` 按成员总数加囚犯数量一半折算消耗，并可受 Steward/Scout等 Perk、地形、Sea和其他模型修正；`Food` 将库存总粮与 `RemainingFoodPercentage` 合并表示。Daily `FoodConsumptionBehavior` 根据消费缺口逐份从 ItemRoster 随机移除 `IsFood` 物品，可能宰杀 Livestock 转成 Meat；军团部分缺粮时还有 Party 间分配粮食的处理。正常食物消费对象筛除 Villager、Garrison、Caravan、Bandit、Militia、Patrol等 Party 类型；聚落驻军的供粮另归 D02/D07 SettlementFoodModel。

原版 `PartiesBuyFoodCampaignBehavior` 在 Party 进入 Settlement/小时检查后，给适用的非玩家 Party 自动补买粮食；调用分支显式跳过 MainParty，所以玩家不能依赖它替自己自动补粮。Town/Village 的可买食品来源与买入结算由 `PartyFoodBuyingModel`、SettlementComponent/MarketData、`SellItemsAction` 等处理。Chronicle 已有的 Town food options/`provision` 是一次按需查询/交易；Observer 会持续输出主 Party `food`、`foodInventory`、`foodChange`，但不输出全部 food roster。

### 货物、负重、动物与战后物资

Party `ItemRoster` 同时承载食品、贸易物、动物与战利品；缓存的 `TotalFoodAtInventory`、`TotalWeightCarried`、`InventoryCapacity`、动物数量会分别影响食物、载重、速度或交易判断。战后 ItemRoster 可能先进入 Encounter 的待领取 Loot Roster，再经原生 InventoryState 领取到 Party；那不是“战斗奖励已到账”的同义词，处理链见 G/H 域及 MAINLINE 的 partyLoot 契约。队伍内囚犯、受伤/健康成员、战利品/库存的转移则由对应 PartyScreen、InventoryLogic 和结算动作分别提交。

### Chronicle 当前经济观察面

Observer 当前主队输出 Gold、Party人数/健康/伤兵/囚犯、Item总量、食物库存/变化、总工资、速度/士气、cargo weight/capacity；它不列具体普通物品、各 troop 的单兵工资、可用工资预算、欠薪比例、动物细分、非食物载货价值或全部战利品详情。若战后 Loot InventoryState 正在打开，Observer只计数左右物品数和有无 UI handler；Protocol有领取当前战后物品的专用处理，不是任意背包移动工具。玩家可以在城镇市场按菜单购买粮，且当前适配复用InventoryLogic交易；截图级的玩家 UI 路径与返回结果不据此宣称完成。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `MobileParty`、`DefaultPartyWageModel`、`DefaultMobilePartyFoodConsumptionModel`、`DefaultPartyDesertionModel`、`FoodConsumptionBehavior`、`PartiesBuyFoodCampaignBehavior`、`DefaultClanFinanceModel`；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`、`AgentProvisioning.cs`；相关战后 Loot 路径见现有 G/H研究/MAINLINE。此处为 v1.4.8.119303 静态源码与本地协议对照，未运行欠薪、粮尽、牲畜宰杀或债务时间序列。

未知项：Player/MainParty的每日实际工资扣款事件/调用顺序和与 ClanFinance 的精确钱包切分；各 trooper/wounded/hero/mercenary/garrison/daily-payment policy 的全部工资细节；背包重量/马匹分类影响速度上限和交易容量的完整公式；Army食物分享和债务/破产处理边缘条件；Player UI在 roster/item transfer中所有键鼠/提交/取消和失败恢复副作用。

## 研究范围状态

E01-E06 已完成首轮物品、市场定价、村庄供应链、Workshop、Caravan 与 Party经济盘点。E07-E10 尚未研究；继续按 `SYSTEM_INVENTORY.md` 的 E 域范围逐项核对，不把这些子系统的静态首轮盘点视作经济与贸易系统整体完成。
