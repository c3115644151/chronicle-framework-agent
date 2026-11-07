# Tasks

## 1. Checkpoint model

- [x] 1.1 `TestResults/20261107-091843/AgentHostPackage.log` 通过Native checkpoint回环及无效 objective/status/fingerprint 拒绝，保留无关字段；尝试记录仅含规范化路由/Journal信息，无提示词或凭据。
- [x] 1.2 同一Campaign fake checkpoint复核证明：仅Journal和Native状态指纹相同才维持route block；Journal/Native变化会重开，time-only变化被现有route fingerprint测试排除：`TestResults/20261107-091843/AgentHostPackage.log`。

## 2. Parent planner integration

- [x] 2.1 Fake Native两次Host调用共享同一Campaign checkpoint；第二次直接恢复已选objective，跳过高层objective planner，且仍进入fresh Native child loop：`TestResults/20261107-091843/AgentHostPackage.log`。
- [x] 2.2 目标选择后先写入pending attempt；budget exhaustion不转为blocked，checkpoint safe map验证在同一fake/save状态读写成功：`TestResults/20261107-091843/AgentHostPackage.log`。
- [x] 2.3 Fake Native重启后的blocked Companion不在planner action catalog中，Gold仍可选；route fingerprint变化或Journal进度变化时恢复：`TestResults/20261107-091843/AgentHostPackage.log`。
- [x] 2.4 新attempt property和运行trace只保存规范化objective/result/Journal/fingerprint/checkpoint状态；无原始provider output或credentials，且保留Native checkpoint其它字段：`TestResults/20261107-091843/AgentHostPackage.log`。

## 3. Verification and one live continuation

- [x] 3.1 `Run-Harness.ps1 -Phase AgentHostPackage` passed at `TestResults/20261107-091843` (Build + packaged Host; 363 Provider contract scenarios, zero real-model calls); `Run-Harness.ps1 -Phase Docs` and OpenSpec validation passed at `TestResults/20261107-092406` (1 active change + 1 stable spec valid).
- [ ] 3.2 After package and Docs pass, make one persistent `freshB` continuation from the current verified Native save, which has no attempt-memory record yet. Hypothesis: the production Host writes a bounded pending record before executing the model-selected EYC subgoal and safely preserves it in the same Campaign SaveAs. Expected signal: `eyc-objective-attempt-checkpoint-written`, same Campaign ID, safe new save, and structured attempt status with zero raw model text/credentials. Limit: at most 20 provider decisions and `CHRONICLE_LLM_MAX_RUN_COST_CNY=0.20`. This run cannot by itself prove restart-resume because the source save has no prior attempt; the Fake Native restart tests cover that contract. Do not automatically repeat if no safe save or no new signal.

## Workflow follow-up

- This is a focused sub-change under the existing GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130). The two independent natural Campaigns and original EYC completion gate remain in that issue.
