# E 类研究：经济与贸易

状态：机制盘点中；E01 已完成首轮盘点，目前研究 E02 市场库存与动态定价，未进行方案评审。

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

## 研究范围状态

E01-E02 已完成首轮物品对象、容器、MarketData/默认定价和 Chronicle 覆盖盘点。E03-E10 尚未研究；继续按 `SYSTEM_INVENTORY.md` 的 E 域范围逐项核对，不把单价模型盘点视作经济与贸易系统整体完成。
