# 任务

## 1. 原版转换验证与合同

- [x] 1.1 记录本机1.4.8 `PlayerTownVisitCampaignBehavior` 的Town Backstreet `town_tavern`入口与原版Tavern Mission启动callback；用户确认第一步到酒馆菜单、第二步进入3D，长按Tab返回。
- [x] 1.2 为Native Companion路由增加有限、只读的Tavern Mission转换观察，并在确认进入Mission后才标记Town已访问。
- [x] 1.3 Fake Native/Provider覆盖延迟进入Mission、未进入时超时、Host取消；断言等待期间没有Provider请求、重复菜单动作或时钟动作。

## 2. 验证与收尾

- [x] 2.1 `Run-Harness.ps1 -Phase AgentHostPackage`通过`TestResults/20261111-024453`；Fake测试0真实模型调用/0真实Native动作。
- [x] 2.2 更新MAINLINE及Research/D，运行`Set-ContextFocus.ps1 -Review`和Docs/OpenSpec校验（`TestResults/20261111-024925`）；不重复`TestResults/20261111-012818`同配置真实模型测试。
