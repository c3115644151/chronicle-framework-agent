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
- [ ] 3.2 After package and Docs pass, make one persistent `freshB` continuation from the existing safe Native save, which has no new `eycObjectiveAttemptMemoryV1` entry yet. Hypothesis: the production Host writes a bounded pending record before executing the model-selected EYC subgoal; the passive video index also receives the Host decision timeline. Expected signal: same Campaign ID, checkpoint attempt write/read summary, decision-aligned keyframes including repeated Tavern navigation if it occurs, and the source MP4 is removed after indexing. Limit: at most 20 provider decisions and `CHRONICLE_LLM_MAX_RUN_COST_CNY=0.20`. If the Host ends in Mission/Encounter and safe SaveAs is refused, retain the prior verified checkpoint and mark attempt durability unverified; do not automatically repeat the same save/prompt.

  Attempt `TestResults/20261107-100410` ran 16 provider decisions / 85 Native actions, then stopped before the next request because the conservative reserved-cost ceiling reached 0.19735 CNY and another request would exceed 0.20 CNY; summed estimated model cost was 0.10317 CNY. The production Host reports that the selected Companion route read a matching Journal checkpoint and wrote one completed checkpoint record. The real model navigated to a Tavern NPC and the Native interaction opened the conversation (event frame `TimelineFrames/018-missionInteract-MissionState---event.jpg`); it later returned to MapState, but did not complete hiring or the EYC goal. The capture indexed 18 events, emitted 50 decision/state keyframes plus a 24-sample contact sheet, and deleted the source MP4. This is useful Host/runtime and visual-capture evidence, but it does **not** prove the checkpoint survives a process restart or that the post-run Campaign save contains it; keep this task open for an explicit safe save + fresh Host readback. The run result is failed for the full Campaign gate, no second model run was launched.

## Workflow follow-up

- This is a focused sub-change under the existing GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130). The two independent natural Campaigns and original EYC completion gate remain in that issue.
