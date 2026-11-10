# 设计

## 背景

本机1.4.8原版 `PlayerTownVisitCampaignBehavior` 将 `town` 中的 `town_backstreet` 注册为“Go to the tavern district”，再将 `town_backstreet` 中的 `town_tavern` 注册为“Visit the tavern”；后者的原版callback通过 `OpenMissionWithSettingPreviousLocation("center", "tavern")` 启动Tavern Mission。Native mailbox在执行 `menuSelect` 后立刻返回，随后游戏状态转换可能仍在进行。

在 `TestResults/20261111-012818` 中，Native Host在选择 `town_tavern` 后继续读取到 `MapState/town_backstreet`，并把下一步交给模型。连续截图出现加载帧后又回到城镇菜单，Host没有读取到Tavern Mission的Agent列表；模型随后选择 `town_backstreet_back`。这轮Companion子流程因模型 `stop` 结束，原EYC Journal没有推进。

## 目标

- `town_tavern` 回执后让Host观察原版当前状态转换，避免模型基于旧菜单状态再做决定。
- 进入Tavern Mission后继续现有 `missionSceneAgents`、导航、互动和对话流程。
- 未确认进入Mission前不把该城镇计作已完成的Tavern访问，也不伪造场景Agent。
- 过渡有时间上限、支持Host取消，并在停止时保留原版最新状态和明确原因。

## 非目标

- 不新增Tavern按钮、UI或Native游戏动作。
- 不替模型选择NPC、任务或对话选项。
- 不重复调用 `town_tavern`、不点返回、不控制战役时钟来催促加载。

## 决策

- 只在Host成功提交了当前 `town_backstreet` 菜单中精确可用的 `town_tavern` 后开始观察。
- 每秒只读Native状态，最多10秒；看到有效Tavern `MissionState` 即结束观察并继续现有Agent扫描。
- 若到上限仍为原Map/menu或返回其它自由Map，返回 `native-tavern-entry-transition-not-observed`，不把城镇加入已访问/无候选集合，也不自动重发入口。
- Fake Native/Provider验证三种状态：延迟后进入Mission且等待期间无模型调用；原版Map返回/超时后状态不被标成已访问；Host取消时不调用额外Native动作。

## 风险

若原版在加载Mission前会合法地短暂重复报告旧菜单，10秒内每秒轮询应覆盖该延迟；若达到上限，将保留可复核的失败状态而不自动重试。用户对加载动画后正常界面的确认会作为额外视觉证据，不替代本机Native Mission状态。
