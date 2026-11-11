# 任务

## 1. Native部署完成契约与桥接

- [x] 1.1 按本机1.4.8源码和Deployment现场反例更新MAINLINE/Research G：记录Ready/准备按钮、OrderOfBattleVM到F1 DeploymentHandler的Native调用链、普通野战与围城Inquiry差异、UI提交与直接API差异、Campaign时间以及未知项；运行`Set-ContextFocus.ps1 -Review`和`Run-Harness.ps1 -Phase Docs`。Evidence: installed assemblies/decompilation; early waiting failure `TestResults/20261111-070839`; direct underlying-handler NullReference `TestResults/20261111-074838`; corrected Native UI VM transition `TestResults/20261111-084224`; Docs/OpenSpec receipts `TestResults/20261111-085023` and `TestResults/20261111-085023`.
- [x] 1.2 增加Guard严格限定的Native `missionFinishDeployment`：只调用当前OrderOfBattle ViewModel的`ExecuteBeginMission`，要求`CanStartMission=true`、普通Campaign野战Mission Deployment模式、Campaign Stop、无弹窗；Build和Native负向探针验证MapState拒绝及重复请求无状态改变，并读取Mission进入Battle后才能发F6。Evidence: Build `TestResults/20261111-081052`; Host package `TestResults/20261111-083035`; Native MapState/duplicate rejection and successful UI Ready receipts `TestResults/20261111-084224`.

## 2. Host Attack→Deployment→Battle→F6闭环

- [x] 2.1 扩展`AgentHostBattleMissionLoop`：识别原版Deployment，执行Ready一次、被动等待同一Mission进入Battle后再F6一次；失败/超时/进程切换不重放；Fake Host集成测试覆盖Deployment→Battle→F6→BattleEnd的完整顺序且无部署期模型调用，运行`Run-Harness.ps1 -Phase AgentHostPackage`。Evidence: `TestResults/20261111-083035` passed; 0 model calls/0 Native game commands.
- [x] 2.2 更新`Test-AgentBattleMissionFormationProbe.ps1`与opt-in Harness phase，Native `Attack`后若处于Deployment先走完成路径，再读取MainAgent Formation/Detach、委派、健康/位置/时钟并收尾；记录零模型Native结果、源存档Hash不变、Native SaveAs测试副本按Hash清理及进程退出，运行`Run-Harness.ps1 -Phase BattleMissionFormationProbe -BattleSimulationSourceSaveName ChronicleEycDev-freshB-20261111013050-0065ffbe`。Evidence: `TestResults/20261111-084224` passed; source SHA unchanged, test clone deleted, zero model calls; Native Ready→Battle→F6→MissionEnded→prisoner_wait; the battlefield result was defeat/capture, not a victory claim.

## 3. 完成闭环记录

- [x] 3.1 把成功/失败现场信号回填MAINLINE、Research/G和Issue #132，明确不把deployment等待或Native败北误报为战斗胜利；完成`Set-ContextFocus.ps1 -Review`、`openspec validate --all`及`Run-Harness.ps1 -Phase Docs`。Evidence: `TestResults/20261111-084224` Native UI Ready→Battle→F6→prisoner_wait; `TestResults/20261111-085531` Docs passed; OpenSpec validate all checked in this change archive sequence. Issue #132保持In Progress，#130保持Todo，因为MainHero在战斗中仍不自主行动且安全条件未通过。

## Workflow follow-up

- 这只是#132子Issue的部署阶段补齐；不要关闭#132或移动父#130状态，除非其剩余MainHero安全/完整接受标准也通过。
