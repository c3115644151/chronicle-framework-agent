# Tasks

## 1. Campaign-scoped search memory

- [x] 1.1 通过Native checkpoint读写保存Campaign ID绑定的EYC同伴搜索记忆；验证编解码拒绝错战役/无效结构并保留既有字段：`TestResults/20261107-040422/AgentHostPackage.json`。
- [x] 1.2 空酒馆结果仅在原版Leave返回MapState后落盘；Host重启后按同一Journal快照排除已搜空Town：`TestResults/20261107-040422/AgentHostPackage.json`、`TestResults/20261107-043410/Temp/AgentHostProgress.jsonl`、`TestResults/20261107-050137/Temp/AgentHostProgress.jsonl`。
- [x] 1.3 无模型Host回归验证：Gold从1000降至670时保留并刷新空Tavern记录、正向Journal进度时清除；同时从旧版仅有Journal指纹的Campaign检查点恢复基线并升级为新快照格式：`TestResults/20261107-064923/AgentHostPackage.log`（361 Provider、26 CampaignLoop、26 BattleSimulationLoop场景；包含该内存自测）。
- [x] 1.4 同Campaign有界续跑已进入Companion路线：`TestResults/20261107-070300/Temp/AgentHostProgress.jsonl`记录EYC识别→模型选择Companion→原版`menuSelect town_backstreet`，3次模型决策/1条Native动作，成本估算¥0.01301761；同Campaign安全checkpoint和清理通过。memory trace为`checkpointReadAttempted=true`、`noCandidateTownCount=0`、`memoryMatchedCurrentJournal=true`、`memoryReusedAfterJournalDecrease=false`。诊断确认此分支没有旧空Tavern记录，故旧格式运行时迁移未判定；不在同一无记录存档重复测试。
- [ ] 1.5 后续只有当Native自然写入至少一个“无候选Town”记录，且同一Campaign随后发生资源下降时，才验证新格式快照在实际checkpoint中的保留/刷新；需要有checkpoint读取、记录数量、`memoryReusedAfterJournalDecrease`、重访Town与写入成功的连续trace。如果两Campaign门禁完成前未自然产生此条件，保留“运行时未验证”，不为验证记忆单独操控资源或重复模型调用。

## 2. Native Tavern与原版行军恢复

- [x] 2.1 当前Tavern没有合格Wanderer且Native只列Leave时自动离场，不为只读扫描/唯一动作付模型调用：`TestResults/20261107-040422/AgentHostPackage.json`、`TestResults/20261107-041139/Temp/AgentHostProgress.jsonl`。
- [x] 2.2 子流程在Bandit中断后继承已有`GoToSettlement`目标，不重复请求地图目标或重发同一Move：`TestResults/20261107-044809/AgentHostPackage.json`、`TestResults/20261107-050137/Temp/AgentHostProgress.jsonl`。
- [x] 2.3 当前Map仍有监视器确认的敌对Bandit时，BattleSimulation优先于通用暂停移动恢复；无兵时走原版投降/赎金/俘虏恢复：`TestResults/20261107-051813/AgentHostPackage.json`、`TestResults/20261107-053329/Temp/AgentHostProgress.jsonl`及`LiveModelLoopResult.json`。

## 3. 继续当前自然Campaign

- [ ] 3.1 从最新安全Native聚落检查点继续同一自然Campaign，由Agent依据Journal与当前Native状态自主选择目标；记录原版Journal的实际增量、Native副作用、provider决策/token/成本，以及同Campaign保存和进程清理。Harness不可预选PartySize或其它目标代替模型。已尝试的一轮10决策/¥0.10续跑发生费用拒绝：9个请求后预留已达¥0.0921528，下一请求预计¥0.0097224会超限；Host处于`encounter_meeting`，因不能安全保存而保留上一检查点。下一次只续跑一次，最多20个决策、`CHRONICLE_LLM_MAX_RUN_COST_CNY=0.20`，假设该界限可完成当前Encounter恢复/安全回图并保存；信号为原版Journal增量或同Campaign新安全Native SaveAs。若仍无法安全保存或无可见Journal进展，就停止当前连续运行并按证据修代码/循环，不用同一输入自动重试。

## Workflow follow-up

- 完成本变更后回到GitHub issue #130继续剩余EYC目标。两个独立自然Campaign和原版Quest完成仍由#130完整验收，不由本变更代替。
