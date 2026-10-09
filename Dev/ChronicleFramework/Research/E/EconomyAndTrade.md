# E 类研究：经济与贸易

状态：E01-E10 已完成经济/贸易领域首轮静态盘点，未进行方案评审；所有界面和长期运行未知项仍在文中分别标记。

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

W2-V用原版 Town `trade` 菜单进入 Trade `InventoryState`，按需读取当前 `SPInventoryVM` 左右候选及Native item cost；买卖暂存分别走 `SPItemVM.ExecuteBuy/ExecuteSell(amount)`，Done/Cancel复用活动Trade Inventory的Gauntlet handler。它不把旧的Map态独立报价/InventoryLogic快路径当作玩家Trade GUI已验证。专门的交易事务运行结果留在W2-V测试回执；市场时间序列/可视UI仍不在此静态研究结论内。

证据：本机 `TaleWorlds.Core.dll`（`ItemObject`、`ItemCategory`、`EquipmentElement`、`ItemRosterElement`）、`TaleWorlds.CampaignSystem.dll`（`ItemRoster`）；官方 `Modules/SandBoxCore/ModuleData/items/*.xml`、StoryMode物品XML；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`、`AgentTradeAdapter.cs`。结论基于当前 v1.4.8.119303 安装源码/数据和当前Native Trade VM adapter；当前玩家Trade入口运行验收见W2-V。

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

城镇玩家菜单 `trade` 由 `InventoryScreenHelper.OpenScreenAsTrade` 建立 Trade `InventoryState`。Native Trade `SPInventoryVM` 持有这份 `InventoryLogic`；市场/玩家候选用实际 `InventorySide` 分别显示，`SPItemVM.ExecuteBuy(amount)`与`ExecuteSell(amount)`分别进入绑定的VM回调，设置 TransferCommand 草稿。Gauntlet Done 调 `SPInventoryVM.ExecuteCompleteTranstactions`并由`HandleDone`提交/处理商人资金提示；Cancel调用`ExecuteResetAndCompleteTranstactions`，有未提交草稿时原生Inquiry决定是否丢弃。Chronicle W2-V现从活动Trade VM读取候选和modifier，调用SPItemVM买卖回调与当前屏幕Done/Cancel handler；此与原先新建独立InventoryLogic的快路径是不同的路径，分别保留证据等级。

当前 Observer 常驻状态不列出市场 item price/stock 表；玩家在 Town 环境请求 tradeOptions 才能获取具名报价。`TestResults/20260928-090808/Temp/TradeTransactionResult.json`实测萨哥特Town：活动Native Trade VM的碎裂箭报价60，与同一InventoryLogic单位价格相符；候选区分OtherInventory/PlayerInventory及modifier。此次覆盖一个城镇、一种带modifier商品和一件交易，不代表其它聚落/特殊交易模式全覆盖；对不同Settlement、被俘/战争、商队、村庄市场及事件影响的动态报价仍未声称全覆盖。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `TownMarketData`、`ItemData`、`TradeCampaignBehavior`、`DefaultSettlementEconomyModel`、`DefaultTradeItemPriceFactorModel`、`Town.GetItemPrice`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的`SPInventoryVM.ProcessBuyItem/ProcessSellItem/HandleDone`、`SPItemVM.ExecuteBuy/ExecuteSell`；Chronicle `AgentTradeAdapter.cs`、`AgentProtocol.cs`。静态证据版本 v1.4.8.119303。运行收据`TradeTransactions`验证Native Trade VM报价、带modifier物品的买卖事务、Cancel/Done、双方库存与Gold后置条件和Stop时间边界；不推定市场供需时间序列已完成。

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

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Village`、`DefaultVillageTradeModel`、`VillageTradeBoundCampaignBehavior`、`VillagerCampaignBehavior`、`SellGoodsForTradeAction`、`TownMarketData`、`SettlementTaxModel`；Chronicle `AgentObserver.cs`、`AgentTradeAdapter.cs`仅查询Town当前Trade Inventory VM，不控制/观察完整村庄商路。村庄生产上游细节依 D04；本节为 v1.4.8.119303源码链核对，未在战役中运行长周期村庄商队观察。

未知项：默认 VillageTradeBound 在关系/海路/封锁/地图连接变化下的所有重算条件；村民贸易 Party 负载量、路程中被劫后恢复/重生及具体到货时间分布；村庄交易税从 Accumulated 到 Clan 财政的全部调用链；玩家/商队同一小时买卖对村庄商路库存的竞争顺序；其他 Mod 添加生产类型或贸易点时的兼容与当前启用情况。

## E04 Workshop 工坊

### 工坊与生产配方

`Workshop` 是固定在 Town 的产业实例，包含 WorkshopType、Hero Owner、Capital、InitialCapital、初始/当前运行时间及进度；`ProfitMade` 只是 `max(Capital - InitialCapital, 0)` 的差值，不等于累计销售额或 Clan 日收入。`WorkshopType` 定义多个 `Production`；每个 Production 以 ItemCategory 和数量列输入/产出，并有 ConversionSpeed。工坊经营因此需要配方输入、成本、转化速度、产物类别、库存/商铺资金共同计算，不是“每天固定发钱”的属性。

### 玩家取得与经营入口

Sandbox 将 shop worker 和 Workshop Owner 放入城镇中心 `center` 地点的对话系统；WorkshopType 的 owner/team 定位依 workshop Tag。面对 owner notable 的对话可购买其一个/多个公开工坊；条件包括没有与该 Town 派系交战、玩家黄金足够且玩家 Clan 拥有数没有达到 `ClanTier + 1` 的模型上限。单工坊价默认是 `WorkshopType.EquipmentCost + Town.Prosperity × 4 + Workshop.InitialCapital / 5`。买入最终调用 `ChangeOwnerOfWorkshopAction.ApplyByPlayerBuying`。

玩家与 shop worker 对话可查看生产类型、切换工坊生产（`ChangeProductionTypeOfWorkshopAction`；默认转换成本等于目标 WorkshopType 的 EquipmentCost）、出售工坊给 town notable，也可请求访问Warehouse。玩家变更生产不是改配方 XML，而是在现有工作坊实例上替换 WorkshopType；转让所有权由独立action处理。准确对话按钮/确认显示仍未视觉运行验证，所在town center入口见D09。

另有两类仓库交互位于不同界面，不能和生产切换/Workshop买卖合并：Clan Management→Finance的`ClanFinanceWorkshopItemVM`允许切换“Use Warehouse as Input”，直接写`IsGettingInputsFromWarehouse`；并允许选择0/25/50/75/100%的产出入仓比例，写`StockProductionInWarehouseRatio`。两者只影响后续生产取料/分配，不直接转移当前物品。Town center的`WorkshopsCampaignBehavior`则注册`manage_warehouse`菜单和shop-worker对话，调用`InventoryScreenHelper.OpenScreenAsWarehouse`打开主队与该城Workshop Warehouse双侧物品界面，仓库侧容量由WorkshopModel给定；存取物品属于原生库存转移，不是按市场报价交易。界面Done/Cancel实际回执尚未运行核验。

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

玩家与自有Caravan leader对话的 “We need to talk business” 分支有两个独立偏好动作。其一，选择改换 HomeSettlement 后分步选一个有可用Town的 Kingdom，再选Town，最后由 `CaravanPartyComponent.ChangeHomeSettlement`提交；目标不等同于设置逐城路线，Naval caravan 还要求目标有Port。其二，选择“trade partners”后对候选Kingdom逐项切换禁止/恢复贸易，改变 `CaravansCampaignBehavior`保存的 `_prohibitedKingdomsForPlayerCaravans`；当前双方在战争中时，回复文本明确说明即使将来议和也不会开始贸易。Quest使用中的Caravan不能配置禁贸名单。另有询问Trade Rumors和打开Caravan Trader库存交易的对话，后两者分别映射J06和E02，不与偏好设置重复。

上述偏好选项调用对话/RepeatablePlayerLine Handler，不扣Gold/Influence，也不改变Caravan Owner/Leader；Home位置和禁贸清单是两种不同状态。战时目标、玩家Owner Caravan贸易许可和已设置的禁贸名单会共同影响后续AI选址与交易。设置动作的源码handler没有显式改CampaignTime，但对话宿主State时钟/条件变化后的重新选址时机本轮未运行核实；这些操作只是贸易偏好，不是逐站手工路由。

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

W5-H 的 `MultiDaySupplyBaseline` 在本机1.4.8 disposable Campaign中做了三轮配对原版对照（每轮从同一模板分别重载无补给/补给支路，非三个独立随机Seed）。主队由1人经Native招募到6人，随后在萨哥特按Native `town_wait`/`rest` 跨过daily tick 2→5，实际Campaign推进约3.1日。三轮无补给均从 Gold 900 / Food 0.95 / FoodInventory 0 开始，结束为 Gold 870 / Food 0.05 / FoodInventory 0、FoodChange -0.3、DailyWage 10、Morale 49；三轮补给均通过当轮Native TradeVM购买4个橄榄（当轮报价9/个、共36），等待前 Gold 864、Food 4.95、FoodInventory 4，等待后 Gold 834 / Food 4.05 / FoodInventory 4，其余上述状态一致。两支均自然经过相同三个每日边界，无Harness时钟命令；Town Wait 墙钟耗时每轮60–61秒。配对起始日偏差最大0.009日，资源结果三轮完全一致，源Campaign文件SHA-256前后相同，所有游戏进程已停止。证据：`TestResults/20261009-022936/Temp/MultiDaySupplyBaselineResult.json`；Harness阶段通过。

这证明当前固定队伍与Town Wait场景下，MainParty的Gold确实每跨一个Daily tick减少10，且4件该次报价的粮食购买可使三日后Food从0.05提高到4.05；这是限定条件下的实测，不是任意队伍规模、兵种、市场或战役的通用工资/消耗公式。`foodInventory`保持4而`Food`减少0.9，报告两个字段时不可互相替代或据此推导未观察的库存消费细节。该场景足以作为下一步真实模型测试的单个可证伪候选，不代表模型已通过长期补给规划。

W5-I候选目标的食品下限另以一轮配对Native实测（同模板、不是新Seed，ProvisionAmount=1）：购买1个橄榄，当前报价9，Gold 900→891、Food 0.95→1.95、FoodInventory 0→1；自然跨过三个daily tick后 Gold 861、Food 1.05、FoodInventory 1、DailyWage 10、Morale 49。对应无补给分支三日后 Food 0.05、Gold 870。收据TestResults/20261009-123759/Temp/MultiDaySupplyBaselineResult.json通过，源档哈希不变、进程清理。由此只确认在该固定6人Town场景、该类报价下购买1单位已达到“3日后Food≥1.0”的候选门槛；不能推广到别的队伍组成/市场，也不代表真实模型已能规划。

W5-I食品下限另以一轮配对Native实测（同模板、不是新Seed，ProvisionAmount=1）：购买1个橄榄，当前报价9，Gold 900→891、Food 0.95→1.95、FoodInventory 0→1；自然跨过三个daily tick后 Gold 861、Food 1.05、FoodInventory 1、DailyWage 10、Morale 49。对应无补给分支三日后 Food 0.05、Gold 870。收据TestResults/20261009-123759/Temp/MultiDaySupplyBaselineResult.json通过，源档哈希不变、进程清理。由此只确认在该固定6人Town场景、该类报价下购买1单位已达到“三日后Food≥1.0”的候选门槛；不能推广到别的队伍组成/市场，也不代表真实模型已能规划。

### 货物、负重、动物与战后物资

Party `ItemRoster` 同时承载食品、贸易物、动物与战利品；缓存的 `TotalFoodAtInventory`、`TotalWeightCarried`、`InventoryCapacity`、动物数量会分别影响食物、载重、速度或交易判断。战后 ItemRoster 可能先进入 Encounter 的待领取 Loot Roster，再经原生 InventoryState 领取到 Party；那不是“战斗奖励已到账”的同义词，处理链见 G/H 域及 MAINLINE 的 partyLoot 契约。队伍内囚犯、受伤/健康成员、战利品/库存的转移则由对应 PartyScreen、InventoryLogic 和结算动作分别提交。

### Chronicle 当前经济观察面

Observer 当前主队输出 Gold、Party人数/健康/伤兵/囚犯、Item总量、食物库存/变化、总工资、速度/士气、cargo weight/capacity；它不列具体普通物品、各 troop 的单兵工资、可用工资预算、欠薪比例、动物细分、非食物载货价值或全部战利品详情。若战后 Loot InventoryState 正在打开，Observer只计数左右物品数和有无 UI handler；Protocol有领取当前战后物品的专用处理，不是任意背包移动工具。玩家可以在城镇市场按菜单购买粮，且当前适配复用InventoryLogic交易；截图级的玩家 UI 路径与返回结果不据此宣称完成。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `MobileParty`、`DefaultPartyWageModel`、`DefaultMobilePartyFoodConsumptionModel`、`DefaultPartyDesertionModel`、`FoodConsumptionBehavior`、`PartiesBuyFoodCampaignBehavior`、`DefaultClanFinanceModel`；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`、`AgentTradeAdapter.cs`；相关战后 Loot 路径见现有 G/H研究/MAINLINE。该适配仅在活动Trade InventoryState提供食物候选/原生购买草稿，不直接改粮食/库存；本节仍未运行欠薪、粮尽、牲畜宰杀或债务时间序列。

未知项：上述固定6人Native招募主队以外的工资写入事件/调用顺序、ClanFinance钱包切分及不同队伍组成/支付策略下的实际Gold后果；各 trooper/wounded/hero/mercenary/garrison/daily-payment policy 的全部工资细节；背包重量/马匹分类影响速度上限和交易容量的完整公式；Army食物分享和债务/破产处理边缘条件；Player UI在 roster/item transfer中所有键鼠/提交/取消和失败恢复副作用。

## E07 Clan 财政与玩家财务页

### Clan Gold 与每日记账循环

`Clan.Gold` 不是与领袖并列的一笔独立 Treasury 字段，而是 `Clan.Leader?.Gold ?? 0` 的派生属性；`DefaultClanFinanceModel` 计算 Clan 收支，并将产生的净变化应用到 Clan Leader Hero 的 Gold。`ClanVariablesCampaignBehavior.DailyTickClan` 是当前找到的实际每日写入链：调用 `ClanFinanceModel.CalculateClanGoldChange(..., applyWithdrawals:true)`，再通过 `GiveGoldAction` 应用总变化；对玩家 Clan 显示“Daily Gold Change”通知。Clan Finance UI 预测值不能当成现金已经结算。

玩家在地图按 L 打开 Clan 页面后进入 Income/Finance 面板。`ClanManagementVM.RefreshDailyValues` 调用 `CalculateClanIncome/CalculateClanExpenses`（默认 `applyWithdrawals:false`）显示当前 Gold、总收入、总支出、DailyChange 和预计余额；计算预览与上面每日 tick 的真实扣款/入账参数不同。Clan Income 区域另列玩家工作坊、Supporters、Alleys等资产/收益列表。当前 UI 有财务估算及分类资产页，不代表 Agent 已能查看相同明细。

### 默认收入来源

`DefaultClanFinanceModel.CalculateClanIncomeInternal` 对每个 Clan 按上下文汇总：

- 领地收入：Town 税、TradeTaxAccumulated 摊销后关税、建设项目收入、绑定 Village 收益；数值还受 SettlementTaxModel、政策与建筑影响。
- 产业与队伍：Leader 资产中的工作坊利润按模型平滑；Party/Caravan 等流动资金在满足模型阈值时计入，Clan Finance detail 与 Clan Income 资产页不是同一展示列表。
- 派系收入：Mercenary service、贡金、TradeAgreement/Call-to-War约定、作为统治 Clan 的 Kingdom预算/政策收入、符合条件时的 Kingdom 支持。
- Player Clan 专属渠道：拥有 Alley 的收入；角色 Perk/特定资产事件还可能叠加。

城镇/村庄税收源自已盘点的聚落状态；关税与村庄税使用 TradeTaxAccumulated 的平滑/领取过程，Workshop/Caravan 的经营资金也不会简单将全部营业额一次性当成 Clan 收入。

### 默认费用、债务与资金来源

`CalculateClanExpensesInternal` 汇总 Leader Party、其他 Clan Party、Caravan/War Party、各个领地 Garrison 的工资支出；另可能支出雇佣兵、贡金、auto recruitment 成本、Kingdom debt、Workshop expense、Call-to-War 等费用。部分 NPC Clan 高额超额余额会转入 Kingdom Budget；这不是玩家 Clan 的统一收入规则。

`applyWithdrawals:true` 时模型按可用余额限制工资支付；欠薪的真实后果由 `PartyMoraleModel` 等产生 Morale penalty，特定 party 还会受限薪/人数导致 Desertion（见 E06）。Clan `DebtToKingdom` 按当前可用资金偿付并逐步减少，而不是与 Player Gold 共用的普通负数余额。`AutoRecruitmentExpenses` 通过每日分摊逐步从 Clan 结算；PartyTradeGold/Workshop Capital 与 Leader Gold 的归属边界见 E04-E06。

### 可见财务与 Chronicle 适配

原版 Clan 财务页有当前 Gold、预测日净变更和收入/支出说明；`DefaultClanFinanceModel` 同时支持 includeDescriptions/details 用于组成解释文本。Chronicle 常驻 Observer 只读 Main Hero Gold、Clan Influence/Renown/Tier，不输出 Total Income/Expenses、daily breakdown、DebtToKingdom、领地税收、Garrison wage 明细、AutoRecruitmentExpenses 或资产收益。Protocol 没有按用户要求交易之外的 Clan Gold 调整/缴债/领地财务动作。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Clan.Gold`、`DefaultClanFinanceModel`、`DefaultPartyWageModel`、`ClanVariablesCampaignBehavior.DailyTickClan`、`GiveGoldAction`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` 的 `ClanManagementVM.RefreshDailyValues`、`ClanIncomeVM`、财务条目 VM；Chronicle `AgentObserver.cs`。静态证据版本 v1.4.8.119303；未运行长周期结算验证每日 UI 数字和实际余额的每一项对应。

未知项：财务面板 income/expenses 明细与模型 `includeDetails` 的一一映射、负数/零收入显示和预计值舍入差异；各税/收益的实际领取事件顺序、自动招聘/欠薪/债务写入的相互顺序；非Player Clan 经济评估/工资限制的全部门槛；Clan Leader变更时 Gold/债务的继承规则；面板项目变更/滚动的完整玩家UI操作证据。

## E08 Kingdom 钱包、预算及跨 Clan 财政

### Kingdom 保存的钱包与 Clan Gold 的区别

`Kingdom` 分别保存 `KingdomBudgetWallet`、`TributeWallet`、`MercenaryWallet`、`CallToWarWallet` 等预算/协议资金；它们不是 `Kingdom.Leader.Gold`，也不是统治 Clan 的独立可支配个人余额。Clan 财政仍通过 Leader Hero Gold 入账/扣账（E07）；若规则文字说“王国提供支持”，需要区分王国预算池实际扣款、领主 Clan 收入和外交 Stance 的每日贡金。

在本机默认财政链中，王国预算池主要承担受条件限制的 Clan 补助/制度性资金分配：当非玩家、非佣兵且未达到特定财务条件的 Kingdom 成员可获支持时，`AddIncomeFromKingdomBudget` 依据 Clan 当前 Gold 分档计算支持上限，且不超过 KingdomBudgetWallet；在玩家的 Clan Management 收支计算中，这个补助被排除。财务每日处理还会按条件把 NPC Clan 超过 100,000 的余额的一部分汇入所属 Kingdom 预算池；Kingdom ruler 每日另有预算保底/低余额随机注资逻辑。详细阈值及随机支路位于 DefaultClanFinanceModel/ClanVariablesCampaignBehavior。

王国账池不是全体 Fief 收入自动汇总后的一个总余额：Settlement 税费通常先进入实际拥有 fief 的 Clan 财政；统治 Clan 的 Land Tax、War Tax、Crown Duty 等政策会按 DefaultClanFinanceModel 读取 Village/Town 税收或 TradeTaxAccumulated，并依具体政策添加至统治 Clan 收入。Town TradeTax 的累计池和 KingdomBudgetWallet 是不同字段；各税/协议调用也可能有不同的累计、摊销和 event 记录。

### 钱包的流入/流出通道

- `KingdomBudgetWallet`：NPC Clan 超额财富贡献、统治者预算注资以及面向部分低余额 Clan 的补助。钱包是否低于 1M/2M、Clan Gold 阈值、是否是玩家 Clan或 mercenary 会影响分配/注资；它不是玩家直接提款用的 King 按钮资金。
- `TributeWallet`：和平协议每日贡金链相关的王国间中间账户；净流出由 ClanFinanceModel 按各 Clan share 分摊，Clan 实际缴不起时会增加 `DebtToKingdom`。最终外部收款/入账由贡金相关行为与 stance 记账共同处理，完整支付时序/每次现金落在哪个 faction wallet 需和 C03/C10 原协议调用链合并核对。
- `MercenaryWallet`：王国用于雇佣兵支出的资金池；负余额会通过各非佣兵 Clan 的 share 形成 Clan 费用/债务，加入雇佣兵服务的 Clan 另通过 MercenaryIncome 获得报酬。合同/账池更新入口见 C07、C10。
- `CallToWarWallet`：调用援战协议相关 Clan 支出/收入的一项中间余额；耗费分配不足会按模型生成 Clan DebtToKingdom。该钱包参与外交约定，不等价于君主随时下达一支可购买 Army 的通用军费。

因此 kingdom-level 财政是若干协议与预算池，再由 ClanFinanceModel 按派系关系分摊的账务流；不能用单一 Kingdom “总收入 - 总支出”数字解释全部状态。

### 玩家可见性与 Chronicle 当前覆盖

当前源码中可见 Kingdom 钱包字段与 ClanFinanceModel 影响各 Clan 收支的调用链。`KingdomManagementVM` 当前未见直接绑定/显示上述 Wallet 字段的 ViewModel 属性；玩家管理页面是否有其他内嵌/间接文本呈现尚未实机核实，故不能断言玩家可以读取确切 treasury 数额。Kingdom Diplomacy 的盟约、贡金、援战和 Clan Finance 页提供的是若干协议/本 Clan 收支入口，分别见 C 类与 E07。

Chronicle Observer 不返回玩家所属 Kingdom ID/预算钱包/Tribute、Mercenary、CallToWar钱包、各成员 Clan财政或预算分配状态；Protocol 无 KingdomTreasury 或财政付款动作。只读 K 页面/Clan Finance 页面也没有被接入持续观察。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `Kingdom` 钱包字段、`DefaultClanFinanceModel`（统治 Clan政策、预算分配、Clan surplus转账、贡金/雇佣兵/CallToWar费用与 debt）、`ClanVariablesCampaignBehavior.DailyTickClan`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` `KingdomManagementVM` 与 `ClanManagementVM`；Chronicle `AgentObserver.cs`、`AgentProtocol.cs`；C03/C07/C10 的政治协议研究。静态源码版本 v1.4.8.119303；未运行王国钱包长期变化或 UI 视觉核验。

未知项：TributeWallet/MercenaryWallet/CallToWarWallet 所有正负余额的写入者、清零条件与跨 Kingdom 转账完整事件序；`KingdomManagementVM` 是否通过间接 formatter 显示预算值、K页面的准确菜单分区和权限；各 Kingdom 政策对领主 Clan Gold 或王国预算池影响的完整消费者；NPC预算自动注资随机结果、Clan财政/预算现金实际写入时序与存档恢复行为；其他 Mod 替换 ClanFinanceModel 对钱包规则的改写。

## E09 Trade 技能、经验与 Perk

### 玩家交易导致的 Trade XP

本机 `TradeSkillCampaignBehavior` 监听 `PlayerInventoryExchangeEvent`。交易时，它为未加 ItemModifier 的 ItemObject 保存玩家购买件数和平均采购价；之后卖出时只对此前记录的购买数量计算可确认的正利润，按玩家本次卖出份额与历史平均采购成本比较，才调用 `SkillLevelingManager.OnTradeProfitMade(PartyBase.MainParty, profit)` 并发出 `OnPlayerTradeProfit`。没有采购记录、没有实现利润、带 ItemModifier 的装备以及非 `isTrading` 的转移都不等价于这个 Trade-XP 事件。

这套经验判定在内存/存档中维护按物品的交易数据；它不是只看本次卖出价格高于 ItemObject.Value，也不是所有获得金币都会被认定为 Trade Profit。`GetProjectedProfit` 用记录的平均买入价与查询价格估算利润，但此提示数值不替代提交交易后的实际 Skill XP 结果。

### 技能对价格的影响

`DefaultPartyTradeModel.GetTradePenaltyFactor` 通过 `DefaultSkillEffects.TradePenaltyReduction` 计算 Party 的交易惩罚倍率；`DefaultTradeItemPriceFactorModel` 再将它用于 Context TradePenalty。模型还按照买卖方向、Town/Village/Caravan seller、与 Settlement 派系关系、贸易商品/动物/普通装备、战争关系等加入不同惩罚；多个 trade Perk 直接参与其加成/折减，例如 WholeSeller、Appraiser、Granary Accountant、Village/Rumor Network、Caravan Silver Tongue 等。明细规则见 E02，不将“Trade Skill 等级”误当成单一固定价格百分比。

工坊转换速度、Caravan 的买卖决策、村庄生产、Workshop/Trade Rumor 等也会读取 Trade Skill/Perk；有关收益/所有权流分别见 E03-E08。M3源码复核确认 `DefaultBarterModel.GetBarterPenalty` 的 ItemBarterable分支读取 Trade Perk SelfMadeMan并改变物品条款估值；是否还有Trade Skill等级影响其它Barterable、Barter成交是否触发Trade XP尚无证据，详见E10。Barter报价效果不重复算成Inventory交易XP。

玩家可见的价格辅助有不同消费者：`SPItemVM.UpdateProfitType`在Trade模式下，对玩家库存检查`Appraiser`或`WholeSeller`，用`IPlayerTradeBehavior.GetProjectedProfit`推导利润标记；对聚落市场库存检查`CaravanMaster`或`MarketDealer`，比较当前与平均价格因子。物品详情中的异地买卖价来自另一条`ItemMenuVM`贸易传闻链，显示函数没有统一技能等级门槛；`TravelingRumors`/`Tollgates`分别扩充商队/工坊情报来源，具体过滤、过期与用户实玩依据见J06。不能把所有价格颜色、利润提示和异地情报统一解释为一个“高交易等级解锁”开关。以上为本机1.4.8源码依据，尚未进行无专长/有专长的运行对照。

### 玩家入口与 Chronicle 当前覆盖

玩家在 Town `trade` 菜单进入原生 InventoryState 执行交易，完成 Transaction 后才触发 PlayerInventoryExchangeEvent；对话 barter、任务奖励、Party loot、Workshop 自动产出及 Caravan 自动买卖是不同来源，不能因为改变 Gold 就推定 Trade XP。该入口路径见 D09/E02。

Chronicle `AgentTradeAdapter` 通过活动Native `SPItemVM.ExecuteBuy/ExecuteSell`产生TransferCommand草稿，再经原生Trade Gauntlet Done提交。买入报价超过主角金币时，adapter根据Native `InventoryLogic.TotalAmount`检查实际整笔金额；若买入不能支付或Native VM表示不可完成，则通过原版Cancel Inquiry撤销这个新草稿后拒绝动作。`TestResults/20260928-095145/Temp/TradeTransactionResult.json`从Campaign Map明确设置`UnstoppablePlay`进入Town Trade：Native Trade InventoryState、买入和卖出draft/Done调用均维持`UnstoppablePlay`；成交自身CampaignDay前后不变，但地图日能在动作间自然增长。测试以1000金币角色尝试购入报价1258的`balanced_bow`，动作Rejected、原版取消询问清除草稿并回到Town菜单、Gold和物品数量不变。容量对照中重量40的羊超过玩家cargoCapacity 30，但Native Trade仍给出可完成事务；测试取消该草稿，Chronicle不增加比原版更严的负重限制。同一Active档测试买入clay 9再按Native卖回7；Stop档另买入一组`default_arrows/splintered_arrows`支出60，再卖出21；双方roster/Gold回执一致，modifier身份保持。`TestResults/20260928-095822/Temp/TradeTransactionResult.json`还确认离开Native Trade InventoryState后使用旧候选调用trade会Rejected，Campaign仍在MapState且Gold与Party物品数量不变。如果原版提交触发 `PlayerInventoryExchangeEvent`/`OnPlayerTradeProfit`，仍须从交易结果独立核验XP差值，不因交易成功自动声称Trade XP成长。Observer 不输出完整Trade技能经验/Perk/ItemTradeData的常驻历史字段，也没有单独的技能训练规划动作。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `TradeSkillCampaignBehavior`、`DefaultPartyTradeModel`、`DefaultTradeItemPriceFactorModel`、`SkillLevelingManager.OnTradeProfitMade`；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` Trade Skill/Character VM；Chronicle `AgentTradeAdapter.cs`、`AgentObserver.cs`、`AgentProtocol.cs`。版本 v1.4.8.119303 源码链已核；交易XP增量/Trade XP条件和存档重载仍未由W2-V买卖测试验收。

未知项：所有 Trade Perk 对价格/XP/结算的写入点和副作用；多个交易订单/部分卖出/回购/市场退货等情况下平均买入成本数据如何更正；NPC Caravan/贸易委托、Workshop 产出的价格变化是否给主角 Trade XP；Trade XP 最终调用和 CharacterDeveloper UI 增长显示间的用户可见结果；存在其他 Mod 交易监听器时事件顺序。

## E10 Barter 交换谈判

### Barter 不是 Inventory 市场交易

Barter 是按 Hero/Party/Faction 对方建立的谈判数据。`BarterData` 保存 Offerer/Other Hero 与 Party、阵营、初始化 Context、BarterGroup 和双方可加入的 `Barterable`；事件 `OnBarterablesRequested` 可由各系统追加本次上下文允许的选项。普通金币/物品转移、领地与囚犯交换、和平/宣战、加入/离开 Kingdom、佣兵服务、婚姻、安全通行等由不同 Barterable 类型和行为系统提供，具体有效范围、价值和后果因类型而异。

这和 E02/E04 的买卖不同：Inventory 是按市场报价、数量与转移命令成交；BarterVM 则在双方谈判盘中修改一组将一并接受或取消的 Barterables，并以阵营视角计算总 offer value/AI可接受性。不同项之间可互相平衡、带有兼容/链接关系，不能用 ItemMarketPrice 对所有 Barterables 求和来替代原版评估模型。

### 玩家入口与确认链

普通领主谈判来源是与 Hero 进行地图/定居点 Conversation，进入对话的 Speak Diplomacy/谈判分支并选择“我有一个可能让双方受益的提议”。原版条件要求对象是非囚犯 Lord、不是 Minor Faction Hero、且不与玩家阵营交战；同一 Hero 受 BarterManager 的冷却计时限制。特殊的 Peace、Safe Passage、Prisoner、Marriage、Join/Leave Faction 等系统可以传入自定义 Context和初始 Barterables，故并非全部从同一个通用对话按钮产生。

`BarterManager.StartBarterOffer` 建立 BarterData、添加当前基础/上下文 Barterables，再派发可扩展请求事件并开启 `BarterVM`。Map原生 `GauntletMapConversationView.InitializeConversation` 将`BarterBegin`绑定到`GauntletMapConversationBarterView.CreateBarterView`，该View在同一Gauntlet层创建实际`BarterVM(args)`并加载`BarterScreen`；Mission宿主则由`MissionGauntletBarterView.OnBarterBegin`建立当前ViewModel。玩家在面板调整两侧项目与金额、查看 offer validity 后选择 Offer/Accept 或 Cancel；接受时执行全部所选 `Barterable.Apply`，发 `OnBarterAccepted`，关闭谈判并延续原对话；取消则不执行交易效果，关闭并发 `OnBarterCanceled`。UI的Offer输入先检查`BarterVM.IsOfferDisabled`，但`BarterVM.ExecuteOffer`自身会直接调用`ApplyAndFinalizePlayerBarter`而不重复检查；Agent必须保留该UI门槛。超额补偿可能按BarterModel给非敌方Hero加个人关系，冷却在接受后更新。

### 官方调用点全景与统一界面边界

对本机v1.4.8官方CampaignSystem程序集中`StartBarterOffer`和`ExecuteAiBarter`调用者进行检索后，玩家与Agent真正共用Barter UI的路径分为以下上下文族。它们都会由`StartBarterOffer(... isAIBarter:false)`→`BeginPlayerBarter`→`BarterBegin(BarterData)`进入Map/Mission BarterView，并创建同一个原生`BarterVM`类；不能因此推断初始条款和Apply结果一样。

| 玩家入口族 | 官方调用来源/Context | 原生提案/最终效果差异 | Chronicle统一接口处理 |
| --- | --- | --- | --- |
| 普通Lord提案 | `LordConversationsCampaignBehavior.hero_barter` → `conversation_set_up_generic_barter_on_consequence`；`ContextInitializer=null` | 普通Item/Gold候选；提交适用各`Barterable.Apply`，超额可能改关系 | 普通入口的VM观察、条款编辑、Auto Balance、Offer/Cancel已做运行验收 |
| Safe Passage/过路费 | 玩家入口来自Lord敌对遭遇或`BanditInteractionsCampaignBehavior.bandit_start_defender`；对话选“Maybe we can work out something”后调用`bandit_start_barter_consequence`。Bandit分支须遭遇方是`IsBanditFaction`且玩家为Defender；海上用piracy文本。它不以“逃兵”任务命名判别 | Lord路线初始化`SafePassageBarterable`+5日`NoAttackBarterable`；Bandit路线只有`SafePassageBarterable`。金额与优势按`FindAllNpcPartiesWhoWillJoinEvent`计算；附近对玩家中立但敌对BanditFaction的NPC可加入玩家方。Auto Balance调用共享BarterVM，不等同于接受交易 | Lord与Bandit Safe Passage已验证共用原生BarterVM；Bandit主动追击遭遇、自动平衡、144第纳尔报价被接受、支付及退出遭遇均已运行验证。成交后即时32小时DoNotAttack字段/Hold已核；一次性战役再用显式Harness fast-forward推进32.4小时，观察到原生期限归零、劫匪转为`PatrolAroundPoint`/`PartyMoveMode=Party`且完整时段没有再次遭遇。该期间没有中途采样，因此不声称逐时行为轨迹，见下方“Safe Passage 运行验收” |
| 任务型逃兵勒索（非Barter） | `ExtortionByDesertersIssue`接取后等待；任务的`StartAmbushEncounter`建立逃兵攻击、村庄/守方防御的任务遭遇并用`CampaignMapConversation.OpenConversation`直开对话。该Quest自己的`DeserterPartyAmbushedDialogFlow`显示勒索台词和“这次你们要为此而战”选项 | 此对话分支没有`StartBarterOffer`、`BarterVM`或`SafePassageBarterable`；它属于Quest/遭遇行为（J域），不得把台词中的银钱/葡萄酒误判为玩家可议价/缴费条款 | 这是“逃兵勒索”与普通Bandit Safe Passage容易混淆的一条官方路径；如果玩家描述的是此Quest，应继续用本地Conversation/Quest流程而非Barter适配器。完整Quest outcomes见J域；当前W2-W不覆盖此流程 |
| 和平议和 | `LordConversationsCampaignBehavior`和平谈判分支 → `InitializeMakePeaceBarterContext` | 有Kingdom/战争/贡金状态结果，可能伴随特殊价格/冷却 | 使用相同VM接口但保留context/type标记；和平结算与时钟仍未运行核验 |
| 领主归附/倒戈 | `LordDefectionCampaignBehavior` → `InitializeJoinFactionBarterContext` | `JoinKingdomAsClanBarterable`和阵营成员/身份变更 | 共用观察和Native Offer门控，不直改Clan/Kingdom；归附结算未运行核验 |
| 婚姻/配偶与亲属婚姻 | `RomanceCampaignBehavior`多个起始流程，及`LordConversationsCampaignBehavior`家庭提案 → `InitializeMarriageBarterContext` | `MarriageBarterable`需配合亲属/浪漫/Clan/年龄等前置，Apply会写婚姻/关系/家族身份 | 同VM候选/流程结构，Context/特殊对象不误标为普通物品；婚姻结算仍属于I04且未由本任务运行核验 |
| AI自治谈判，不是玩家入口 | `DiplomaticBartersBehavior`和`RansomOfferCampaignBehavior`调用`ExecuteAiBarter` | AI直接构造、自动平衡并调用Manager交易；不触发玩家`BarterBegin`/UI | 明确排除在BarterVM动作接口之外；不把后台AI Barter算成Agent正在操作谈判界面 |

#### Safe Passage 运行验收（W2-W）

本机1.4.8的`BarterContexts`验收由一支782人的`looters` BanditFaction party原生`SetMoveEngageParty(MainParty)`开始，没有直接调用`EncounterManager.StartPartyEncounter`。测试按原版遭遇半径和势力关系记录一支132人的中立NPC领主部队；该部队与玩家不敌对、与劫匪敌对，因此可并入玩家方。实测遭遇玩家侧为2支队伍、133人、`CustomStrength=165.332`，劫匪为`361.284`。玩家通过原生`moveToPoint`向一个有效导航近点移动，时钟由地图点击自然进入`StoppablePlay`，劫匪继续主动追击并触发`encounter_meeting`；原版选择了玩家Defender路线，出现劫匪威胁对白和Safe Passage选项。不同运行抽到不同中文威胁句子，说明对白应视为本地化随机变体而非固定文案。

选择Safe Passage后捕获到真实`InitializeSafePassageBarterContext` BarterVM。Auto Balance显示玩家支付144第纳尔的提案，并保留不可转让的`SafePassageBarterable`离场条款；自动平衡前后玩家/附近队伍状态、Campaign时间档和时间均未变化。测试随后调用原生Offer，`LastBarterIsAccepted=true`：金币从1000降到856，遭遇与谈话均结束；成交动作自身不推进Campaign时间/改变时间档。Offer后Harness只读查询Bandit `MobilePartyAi.DoNotAttackMainPartyUntil.RemainingHoursFromNow=32.0`，并观察到劫匪队伍仍活动且`DefaultBehavior/PartyMoveMode`均为Hold。这确认原版Apply即时写入了32小时非攻击期限/停留模式。原始即时结算证据：`TestResults/20260928-161518/Temp/SafePassageBarterContextResult.json`。

独立Cancel分支已用未保存fixture运行通过。Native `barterCancel`回执显示它返回Encounter对话，金币/双方Roster/Campaign时间档和时值均未变化；继续原版回应对白后，游戏回到仍活动的Encounter菜单（`menuId=encounter`），其中`attack`选项可用，而不是重新显示Safe Passage威胁选择。这里验证的是取消原生谈判草稿并返回遭遇菜单，不执行Fight。证据：`TestResults/20260928-170916/Temp/SafePassageBarterCancelResult.json`。

独立Fight分支从威胁对话仍活动时选择原生`bandit_start_defender_1`（“够胆就过来动手吧！”）。原版回应/Continue后回到同一Bandit Encounter菜单，`attack`（玩家进入战斗）与`str_order_attack`（交由部队作战）均启用；仅选择威胁回应不会扣金币、推进Campaign日或改变Stop档。该测试没有启动/结算战斗，所以只证明谈判以外的原生Fight路由仍开放，不等于坐镇模拟结果已经覆盖。夹具hash不变且进程已停。证据：`TestResults/20260928-175833/Temp/SafePassageFightResult.json`（Harness独立阶段`BarterFightRoute`，Preflight/Build/游戏验证均通过）。

Safe Passage时限到期验收使用同一一次性存档；接受144第纳尔报价并记录即时32小时期限后，Harness显式调用`advance 1.35`（只用于测试，不是玩家/Agent移动动作）。原生快进请求达到32.4小时并按`requestedDuration`结束；劫匪仍活动，其剩余非攻击时限为-0.401小时，`DefaultBehavior`从`Hold`变为`PatrolAroundPoint`、`PartyMoveMode`为`Party`，本次推进期间没有新遭遇。由此确认原生定时回避到期且AI恢复普通巡逻，但未每小时采样中间状态，也未量化回避期间各类接近/目标选择。玩家金币已按Safe Passage结算、存档文件hash不变、进程停止。证据：`TestResults/20260928-181704/Temp/SafePassageBarterContextResult.json`。


夹具曾用`MainParty.Position + (0.5, 0)`生成劫匪，该点未经原版导航验证。真实触发遭遇时，Native `bandit_start_defender_condition`抛出`NullReferenceException`；源码显示该方法会查找劫匪最近的Town/Village，随后不做空值保护地读取SettlementComponent。这使无效Party位置/最近定居点查找成为有源码依据的嫌疑，但异常堆栈没有行号，旧夹具也未记录该查询结果，因此精确的空对象尚未证实。新夹具现在先用原版导航选有效生成点、确认`FindNearestSettlementToMobileParty`可返回定居点，再触发原生AI遭遇；完整对白和BarterVM流程随之通过。我们消除了夹具的未验证环境前置，没有改写原版条件。异常原件：`TestResults/20260928-150648/Temp/CrashException-18860.txt`。

以上源代码调用检索覆盖到的玩家UI族与AI-only族共存于`TaleWorlds.CampaignSystem.dll`。统一技术接口用当前BarterVM暴露的所有native分类/上下文标记，依照其`IsItemTransferrable`和`IsOfferDisabled`实施编辑/提交门槛；它不是把婚姻、和平、过路费等都压成一种GenericItem交易，也不宣称每种特殊Context的World outcome已经过运行验证。第三方BarterManager/BarterVM替换与非官方Barterable需要额外兼容验证。

跨域目录将活跃BarterVM视为独立观察面（`OBS-E10-01`）：玩家需要看到谈判双方、当前加入两侧的条款和Offer有效状态，才知道能否提交。玩家在该VM的另一个共同操作是编辑临时提案草稿：通过兼容检查加入/移除Barterables、改变可分数量或Reset草稿，映射`ACT-E10-01`；这会写入当前`BarterData`并更新报价，但尚不改变World roster/Gold/关系。`ExecuteOffer`触发接受/拒绝并关闭谈判；接受后的持久后果仍映射到婚姻、家族归附、俘虏等上下文ACT，不创建重复的通用成交ACT。完整候选集合、报价解释和屏幕/时间语义仍需按各上下文核验。

### 本体1.4.8 Barter入口分布

针对本机官方 Native/SandBox/SandBoxCore/StoryMode 程序集中搜索 `StartBarterOffer` 与 `ExecuteAiBarter`，玩家发起且显示 BarterVM 的调用按 context 分组如下。多处调用共享VM，不代表它们共享同一个 Barterable 集、价值模型或 `Apply` 副作用。

| 玩家流程族 | 官方入口/调用源 | Data初始化差异 | 可见谈判VM / W2分类 |
| --- | --- | --- | --- |
| 普通领主物品/金币提案 | `LordConversationsCampaignBehavior.hero_barter` → `conversation_set_up_generic_barter_on_consequence` | `ContextInitializer=null`；Barterables由 `OnBarterablesRequested`补普通物品/金币；要求非囚犯Lord、非Minor Faction、双方不处战争且Barter冷却结束 | 原版 `GauntletMapConversationBarterView`建同一BarterVM；W2-W本次全链运行验收的首入口 |
| 议和/Peace | Lord Politics/War 对话选项 → `InitializeMakePeaceBarterContext` | 初始`PeaceBarterable`与特殊接受/拒绝对话后果；Offer效果是王国和平/贡金而非普通金币买卖 | 走原生BarterVM/Offer护栏；和平模型及后果本卡只源码映射，运行差异待特殊context测试 |
| Safe Passage/过路费 | Lord hostile/encounter会话；或玩家作为Defender遭遇BanditFaction移动队伍后，在`BanditInteractionsCampaignBehavior`选择“Maybe we can work out something.”；后者另有海上piracy文案 | 两者走同一`InitializeSafePassageBarterContext`及BarterVM，但Bandit上下文只有`SafePassageBarterable`；Lord上下文还含5日`NoAttackBarterable`。Bandit预览收费与`SafePassageBarterable`的估值公式是不同数据，接受后才由原生Apply离开Encounter/设置32小时回避 | Bandit地图遭遇、威胁对话、Native BarterVM/Auto Balance/Offer/Cancel及32.4h到期后的巡逻恢复已运行核验。Lord hostile路径和额外NoAttackBarterable、海上piracy仍未运行核验 |
| Quest型Deserter勒索（非Barter） | `ExtortionByDesertersIssue`接取并等候村庄伏击；Quest自建Deserter Encounter后直接`CampaignMapConversation.OpenConversation` | `DeserterPartyAmbushedDialogFlow`显示劫掠句及Fight选项；源码调用不创建`BarterData`/`BarterVM`/`SafePassageBarterable` | 不进入E10共用谈判接口；复用J域Quest/Conversation入口与其自身Encounter outcome。与BanditFaction Safe Passage分开 |
| 加入或脱离王国/领主归附 | `LordDefectionCampaignBehavior`对话发起 → `InitializeJoinFactionBarterContext` | `JoinKingdomAsClanBarterable`及Clan/Faction上下文 | 原生BarterVM相同、Offer后果改变王国归属；当前未运行验收 |
| 结婚/婚约交易 | `LordConversationsCampaignBehavior`与`RomanceCampaignBehavior`数个求婚/家族提案入口 → `InitializeMarriageBarterContext` | 默认`MarriageBarterable`，tuple中的双方Hero/亲属与浪漫状态决定婚配/归属 | 原生BarterVM相同，提交最终触发Marriage/Clan后果；当前未运行验收，详见I04 |
| AI自动政治协商/赎回被俘Hero | `DiplomaticBartersBehavior`与`RansomOfferCampaignBehavior`调用`ExecuteAiBarter` | 直接由AI构造/平衡/执行BarterData；不经过玩家`StartBarterOffer`/`BeginPlayerBarter`视图事件 | 没有玩家BarterVM入口，不纳入“AI代理操作界面”共同适配器；其世界结果属于后台模拟 |

当前UI共用层验证事实是：普通或特殊玩家context只要走`StartBarterOffer`并`BeginPlayerBarter`，都会经BarterManager `BarterBegin`交给Map/Mission宿主创建同一类Native `BarterVM`。共同候选/Offer/Cancel控制可以统一，context分类、默认固定条款、VM兼容性和提交后的领域效果必须保留。Chronicle当前capture可识别全部非AI玩家BarterVM，并向决策器输出当前`contextInitializer`方法线索及固定Barterable类型；是否已覆盖所有官方加载场景/第三方替换仍有运行门禁。

`BarterVM.ExecuteAutoBalance`是议价窗中间的原生自动平衡按钮入口；Chronicle的`barterAutoBalance`直接调用当前捕获VM的这个方法，不另算价格、不保证对方接受，也不提交世界交易。它按当前Barterable各方估值补/移报价，VM同时更新双方进度条字段与`IsOfferDisabled`。`TestResults/20260928-121703/Temp/BarterTransactionResult.json`在真实地图Lord谈判中提出2匹大陆骑乘马（领主侧估值3260），Harness仅在未保存的运行内注入一把可交易武器后按原生自动平衡；原版把玩家全部1000第纳尔和该武器加入提案，保留2匹马，双方进度字段变为offerer -1 / other 37，Offer仍禁用。调用前后World金币/物品roster、Stop档和Campaign日值均不变；夹具物品在关闭进程前按精确物品+modifier删除，原始存档hash未变。这证明现金不足时原生可把可用玩家现金和需要的自有物品纳入草案，但该有限夹具不证明有多种贵重物品时会无差别地“全放进去”；也不能把进度条当精确接受概率或成交保证。

### 价值与失败规则

`Barterable` 保存原始所有者 Hero/Party、所在 BarterGroup、是否上下文依赖、被提出数量及可链接项；各子类提供自己的 `GetUnitValueForFaction` 和 Apply 副作用。普通View的提案列表是当前`BarterData`的原生VM投影；`BarterItemVM.ExecuteAddOffered/ExecuteRemoveOffered`调用当前VM处理器，`CurrentOfferedAmount` setter写对应Barterable并触发VM报价/兼容性刷新。一般 offer 是否被接受读取对方视角的净 `GetOfferValue`；`IsOfferAcceptable` 的基础条件是该值不得低于约 0。UI在Offer按钮禁用时不会调用VM的`ExecuteOffer`，直接API若绕过该检查可能提交不应允许的条款。DefaultBarterModel还对物品交换应用双方角度不同的交易Penalty，并影响overpay→Relation结果；和平/政治承诺、Marriage、俘虏/赎金与领地另有自定义价值/前置/结果模型，不具有同一通用估值公式。

与E09的Trade Skill连接经本机`DefaultBarterModel.GetBarterPenalty`核对：对`ItemBarterable`计算双方视角的Penalty时，会读取原主/对方领主是否有Trade Perk `SelfMadeMan`，按PrimaryBonus修正该物品条款的估值；这证明Trade Perk会影响Barter盘的物品报价，不代表通用Trade Skill等级作用于所有Barterable。PlayerInventoryExchange/Trade XP属于E02市场交易提交链；目前追到的Barter草稿编辑/接受链没有派发该市场交易事件的证据，因此不把Barter选项编辑计作Trade XP来源；自定义Barterable/Mod扩展仍未知。

失败/拒绝意味着保持原物品/金币/领地状态，仅结束本轮或沿剧情继续对话；接受后多个关联 Barterable 一并生效，故可能同时修改 faction stance、城镇/家族归属、 prisoner状态、角色婚姻和关系。具体前置、取消/协商结果留给 C/I/F/J 域补齐；本节不将“Barter UI 打开”算作交易成功。

### Chronicle 当前覆盖与未知

Chronicle现通过Harmony在原生`BarterVM(BarterData)`构造后捕获实际VM引用，并在BarterManager.Close/VM finalize时释放。观察与提案编辑共用同一接口，面向所有`StartBarterOffer`创建且由MainHero发起的当前玩家BarterVM；枚举VM全部原生分类，返回上下文初始化器、固定条款类型、双方进度比例和Offer有效状态。普通可转条款用原生BarterItemVM handler/selector编辑；上下文固定/不可转条款只观察，不伪造编辑。`barterReset`、`barterAutoBalance`、`barterCancel`、`barterOffer`分别复用同一VM的原生方法。AI决策接口使用最新观察产生的candidate ID，不创建第二个BarterVM，也不直接执行Barterable.Apply。普通物品/金币完成Map运行验收；和平/政治归附/婚姻/安全通行/俘虏等入口和领域结果已有官方源码调用链盘点，但各特殊上下文尚未逐一运行验收。

`TestResults/20260928-121703/Temp/BarterTransactionResult.json`真实地图Lord对话`hero_barter`→原版回应/继续→捕获实际BarterVM。测试在只读入内存的Harness模式注入一把可交易武器；普通Item 2匹提案执行原生自动平衡，报价加入全部1000 Denar和该把武器，报价仍禁用且进度条字段更新；世界金币/roster、Stop档或Campaign日值不变。原版Reset清空该草稿，最新candidate可继续编辑而旧candidate被拒；原版Cancel后双方party物品指纹、Gold和Hero基础关系不变。第二次从当前Conversation打开普通Barter，以Native Offer提交1 Denar，原版接受且Gold精确转为玩家999/领主10001；夹具武器已精确清除，Barter关闭后恢复MapState。源存档hash相同、游戏进程停止。只测试一类玩家物品与普通Lord；不同物品挑选、原生拒绝Offer、活动时钟、MissionBarter及特殊Context运行结果未覆盖。

证据：当前安装 `TaleWorlds.CampaignSystem.dll` 的 `BarterManager`、`BarterData`、`Barterable`/各子类、`DefaultBarterModel`、`LordConversationsCampaignBehavior`、BarterBehaviors；`TaleWorlds.CampaignSystem.ViewModelCollection.dll` `BarterVM`/`BarterItemVM`；`Modules/SandBox/bin/Win64_Shipping_Client/SandBox.GauntletUI.dll` 的`GauntletMapConversationView`、`GauntletMapConversationBarterView`、`MissionGauntletBarterView`；Chronicle `AgentBarterAdapter.cs`、`AgentBarterViewCapture.cs`、`AgentProtocol.cs`。源码版本v1.4.8.119303；普通Lord Item/Gold runtime范围及限制见`TestResults/20260928-112520`，MissionBarter和特殊Barterable结算仍未知。

未知项：全部玩家触发入口（NPC/Encounter/监狱/婚姻/政治等）的条件矩阵；各 Barterable 的具体报价算法、计算视角、数量限制、链路兼容和取消恢复；BarterVM 活跃期间 Campaign clock 与对话生命周期；协议可观察 offer 值与现有 tooltip/动画/AI接受判断一致性的验证；跨 C/F/I/J 域的 Barter 对话/关系/战俘结局须按各类系统继续研究。

## 研究范围状态

E01-E10 已完成经济/贸易全域首轮静态研究，涵盖商品数据、供需/定价、村庄、Workshop、Caravan、Party/Clan/Kingdom财政、Trade技能与 Barter。域级资料与代码门禁不等于所有UI/运行路径都已验证，也不等于 Chronicle 已实现这些玩家行为。
