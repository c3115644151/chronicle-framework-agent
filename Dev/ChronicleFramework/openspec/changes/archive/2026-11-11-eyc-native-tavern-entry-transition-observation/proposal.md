# 提案：确认原版酒馆场景入口完成后再决策

## 为什么

自然测试 `TestResults/20261111-012818` 中，Companion路线先选原版Town的 `town_backstreet`，再选酒馆区里的 `town_tavern`。用户确认第一步进入酒馆菜单；在该菜单点“造访酒馆”会进入3D酒馆，长按Tab返回酒馆菜单。本机1.4.8反编译 `TaleWorlds.CampaignSystem.dll` 的 `PlayerTownVisitCampaignBehavior.game_menu_town_town_tavern_on_consequence`亦确认该第二步调用 `CreateAndOpenMissionController(... tavern)`。但此次真实测试在该菜单动作后下一次Native读取仍为 `MapState/town_backstreet`；画面先出现加载帧，然后回到城镇画面，AI又选择 `town_backstreet_back`，没有观察到 `MissionState` 或读取酒馆内Agent。Host没有等待这个Native异步状态转换。

## 变更内容

- 在模型选择当前可用的 `town_tavern` 后，Host有限期被动读取Native状态，直到确认酒馆Mission启动或超时。
- 过渡期间不发额外模型请求/游戏动作，不因旧菜单仍可见而让模型选“返回”。
- 只有确认进入Mission后，才把当前城镇标为本轮已访问并继续查询场景Agent；若超时或原版返回Map而未进入Mission，则保留城镇可重试状态并安全停止/交回父规划器。

## 能力

### 新增能力

- `native-tavern-entry-transition-observation`：确认原版酒馆菜单选项之后的Mission状态转换。

### 修改能力

无。

## 影响

修改EYC Companion Native路由和Fake Native/Provider延迟状态回归；属于GitHub #130，不新增产品工作项，也不改变原版入口或Mission。
