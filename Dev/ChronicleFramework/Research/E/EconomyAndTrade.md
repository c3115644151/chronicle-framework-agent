# E 类研究：经济与贸易

状态：机制盘点中；目前完成 E01 物品/商品对象与 Chronicle 当前物品观察，未进行方案评审。

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

## 研究范围状态

E01 已完成首轮对象/容器/Chronicle覆盖盘点。E02-E10 尚未研究；继续按 `SYSTEM_INVENTORY.md` 的 E 域范围逐项核对，不把物品数据对象盘点视作经济与贸易系统整体完成。
