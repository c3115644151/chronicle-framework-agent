# D 类研究：聚落与领地

状态：机制盘点中；目前只完成 D01 基础对象与现有观察覆盖，未进行方案评审。

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

### 时间与证据边界

D01 中的实体分类、所有权查询与绑定关系是读取对象状态，不会自行推进 Campaign 时间。城镇/村庄的每日状态计算由各组件的 `DailyTick` 执行，并受 Campaign 时钟调度；具体数值模型和状态变化分别留给 D02-D04。直接读取属性不等价于玩家打开地图百科或聚落界面；本节没有声称 UI handler 与直接 API 的完整交互已经运行验证。

证据：本机 `TaleWorlds.CampaignSystem.dll` 的 `Settlement`、`SettlementComponent`、`Town`、`Village`、`Hideout`；Chronicle `AgentObserver.cs` 的附近聚落采集与序列化逻辑。当前本节结论来自 v1.4.8.119303 安装程序集反编译及本地代码静态核对。

未知项：玩家地图上不同聚落类型的精确图标/悬停/ALT/百科字段及遮蔽规则；OwnerClan为空或绑定改变的具体场景；每类 Settlement 的地图可见与侦察状态如何由原版行为更新；直接 VM/API 读取与玩家界面展示之间的全部差异。后续 D02-D10 分域补足，不从这些未知项预设设计方案。

## 研究范围状态

D01 已完成首轮静态对象与 Observer 覆盖盘点。D02-D10 尚未研究；继续按 `SYSTEM_INVENTORY.md` 的 D 域范围逐项核对，不将此文档视作聚落系统整体已完成。
