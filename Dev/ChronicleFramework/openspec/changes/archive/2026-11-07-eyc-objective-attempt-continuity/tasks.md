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
- [x] 3.2 `TestResults/20261107-100410`: persistent `freshB` continuation kept Campaign identity `683a2e21c4a64cfd8a1bb4f3392afc3d`, read a Journal-matching Companion attempt and wrote a completed checkpoint record, then saved a Native Map/settlement-menu checkpoint `ChronicleEycDev-freshB-20261107100711-de315fda` (`92C2D3E62D63F9BF85264D5F30FDFF48C859E1FE4709B51FF7EEBEA8B729296D`). The run stopped before request 17 because estimated spend was 0.10317 CNY but the conservative reserved-cost ceiling had reached 0.19735 CNY against the 0.20 CNY limit. The real model opened a Tavern conversation (indexed frame `TimelineFrames/018-missionInteract-MissionState---event.jpg`); it did not complete hiring or the EYC goal. The passive capture indexed 18 events into 50 keyframes plus a 24-sample contact sheet, removed the source MP4, and reported complete capture coverage (645/645 frames over 129 seconds). This validates the one bounded continuation and its evidence pipeline, not checkpoint reload or EYC completion.

  Attempt `TestResults/20261107-100410` continued the same Campaign instance `683a2e21c4a64cfd8a1bb4f3392afc3d` from save `ChronicleEycDev-freshB-20261107081300-dd5fe3a8`; it produced the verified Native Map/settlement-menu checkpoint `ChronicleEycDev-freshB-20261107100711-de315fda` (`92C2D3E62D63F9BF85264D5F30FDFF48C859E1FE4709B51FF7EEBEA8B729296D`). It ran 16 provider decisions / 86 Native actions, then stopped before another request because the conservative reserved-cost ceiling reached 0.19735 CNY and another request would exceed 0.20 CNY; summed estimated model cost was 0.10317 CNY. The production Host reports that the selected Companion route read a Journal-matching checkpoint and wrote one completed checkpoint record. The real model navigated to a Tavern NPC and the Native interaction opened the conversation (event frame `TimelineFrames/018-missionInteract-MissionState---event.jpg`); it later returned to MapState, but did not complete hiring or the EYC goal. The capture indexed 18 events, emitted 50 decision/state keyframes plus a 24-sample contact sheet, and deleted the source MP4. Runtime, same-Campaign identity, safe-save, and capture signals passed; a fresh Host has **not yet reloaded and reported the checkpoint property**, so restart persistence remains unverified. The run result failed the full Campaign gate; no second model run was launched as part of this attempt.

- [x] 3.3 `TestResults/20261107-103044`: `EycObjectiveCheckpointReadback` loaded the manifest-selected `freshB` save in a new game process and read the Native checkpoint. The saved schema-1 `eycObjectiveAttemptMemoryV1` contained the Companion attempt in `pending` status and matched Campaign instance `683a2e21c4a64cfd8a1bb4f3392afc3d`; save SHA-256 remained unchanged, the process/session were removed, and both provider-call count and model cost were zero. Receipt: `PersistentEycObjectiveCheckpointReadback.json`. The phase did not launch an AgentHost or prove end-to-end objective re-entry; that transition remains covered by Fake Native/Provider Host restart contracts rather than a billed live-model call.

## Workflow follow-up

- This is a focused sub-change under the existing GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130). The two independent natural Campaigns and original EYC completion gate remain in that issue.
