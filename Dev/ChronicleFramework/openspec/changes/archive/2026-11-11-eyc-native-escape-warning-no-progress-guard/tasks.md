# 任务

## 1. Native无进展合同与保护

- [x] 1.1 为原版Try-to-get-away拒绝后的Encounter状态实现临时快照指纹，只在遭遇/双方队伍状态未变化时暂时隐藏已拒绝的 `leave_soldiers_behind`。
- [x] 1.2 增加Fake Native/Provider集成回归：经历打开警告→原版拒绝→返回遭遇；验证同一选项被隐藏、其它选项保持，玩家选择下一选项由模型决定。
- [x] 1.3 验证玩家方/敌方人数变化及遭遇ID变化会清除防重复限制；原版接受撤退仍走既有Native结算路线。
- [x] 1.4 Fake Native/Provider验证：Try-to-get-away抑制后Native只留下已启用的 surrender 时，恢复模式把它列给模型，模型选中后经原版赎金页面返回自由Map；普通模式仍不开放surrender。

## 2. 验证与收尾

- [x] 2.1 `Run-Harness.ps1 -Phase AgentHostPackage`通过`TestResults/20261111-012232`，完整BattleSimulation包自测的真实模型调用/真实游戏动作均为0。
- [x] 2.2 更新MAINLINE与Research/G，运行`Set-ContextFocus.ps1 -Review`及Docs/OpenSpec校验（最终Docs回执`TestResults/20261111-013806`，包括真实续跑和零模型检查点读回证据）。
- [x] 2.3 从同一`freshB`安全源档做一次最多20决策/¥0.20封顶续跑：`TestResults/20261111-012818` 17决策、估算¥0.09358752。真实路线选择Companion/继续Renown，未进入Bandit Encounter/撤退警告，EYC Journal没有目标增长；保存了同Campaign安全检查点`ChronicleEycDev-freshB-20261111013050-0065ffbe`（SHA-256 `4BCDE64809141E96D059AFCD95A715A5DE5CC3BDF12C08A1C5E040E29CEBC2E0`）。零模型读取`TestResults/20261111-013459`确认该检查点同Campaign、MapState Town，Gold0、Party16（12健康/4伤员）、Renown20、EYC Journal仍0/2000、16/25、20/50、Companion0/1；源Save hash未变、0 provider calls、进程清理通过。此续跑没有覆盖撤退警告触发，故自然运行验证仍未知；按原计划不重复同一试跑，保留Fake Native/Provider证据。
