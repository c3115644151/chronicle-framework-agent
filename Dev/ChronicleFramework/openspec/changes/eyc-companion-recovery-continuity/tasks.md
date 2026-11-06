# Tasks

## 1. Campaign-scoped search memory

- [x] 1.1 通过Native checkpoint读写保存Campaign ID绑定的EYC同伴搜索记忆；验证编解码拒绝错战役/无效结构并保留既有字段：`TestResults/20261107-040422/AgentHostPackage.json`。
- [x] 1.2 空酒馆结果仅在原版Leave返回MapState后落盘；Host重启后按同一Journal快照排除已搜空Town：`TestResults/20261107-040422/AgentHostPackage.json`、`TestResults/20261107-043410/Temp/AgentHostProgress.jsonl`、`TestResults/20261107-050137/Temp/AgentHostProgress.jsonl`。
- [x] 1.3 无模型Host回归验证：Gold从1000降至670时保留并刷新空Tavern记录、正向Journal进度时清除；同时从旧版仅有Journal指纹的Campaign检查点恢复基线并升级为新快照格式：`TestResults/20261107-064923/AgentHostPackage.log`（361 Provider、26 CampaignLoop、26 BattleSimulationLoop场景；包含该内存自测）。
- [x] 1.4 同Campaign有界续跑已进入Companion路线：`TestResults/20261107-070300/Temp/AgentHostProgress.jsonl`记录EYC识别→模型选择Companion→原版`menuSelect town_backstreet`，3次模型决策/1条Native动作，成本估算¥0.01301761；同Campaign安全checkpoint和清理通过。memory trace为`checkpointReadAttempted=true`、`noCandidateTownCount=0`、`memoryMatchedCurrentJournal=true`、`memoryReusedAfterJournalDecrease=false`。诊断确认此分支没有旧空Tavern记录，故旧格式运行时迁移未判定；不在同一无记录存档重复测试。
- [x] 1.5a 新格式记录经Native checkpoint + SaveAs可跨Host/游戏重启保留：`TestResults/20261107-072137/Temp/AgentHostProgress.jsonl`写入1个empty-Town记录后生成`ChronicleEycDev-freshB-20261107072404-a9aa2b09`；下一轮`TestResults/20261107-072945/Temp/AgentHostProgress.jsonl`再次读取到`noCandidateTownCount=1`且`memoryMatchedCurrentJournal=true`，同Campaign ID不变。两次结果均`memoryReusedAfterJournalDecrease=false`，不构成资源下降验证。
- [x] 1.5b 同一Campaign自然出现赎金与队伍状态变化：`TestResults/20261107-073719/Temp/AgentHostProgress.jsonl`显示资源下降后`memoryReusedAfterJournalDecrease=true`；随后原版Journal PartySize从被俘时0恢复到1，`memoryInvalidatedByJournalProgress=true`，两次Native checkpoint写入均confirmed。Gold 670→424是减量；后续清除排除项对应正向PartySize变化。Runtime日志未暴露Town ID，故不宣称已核实“没有重访某个具体Town”；变更行为有Runtime与Package证据，不为记录Town ID单独进行付费测试。

## 2. Native Tavern与原版行军恢复

- [x] 2.1 当前Tavern没有合格Wanderer且Native只列Leave时自动离场，不为只读扫描/唯一动作付模型调用：`TestResults/20261107-040422/AgentHostPackage.json`、`TestResults/20261107-041139/Temp/AgentHostProgress.jsonl`。
- [x] 2.2 子流程在Bandit中断后继承已有`GoToSettlement`目标，不重复请求地图目标或重发同一Move：`TestResults/20261107-044809/AgentHostPackage.json`、`TestResults/20261107-050137/Temp/AgentHostProgress.jsonl`。
- [x] 2.3 当前Map仍有监视器确认的敌对Bandit时，BattleSimulation优先于通用暂停移动恢复；无兵时走原版投降/赎金/俘虏恢复：`TestResults/20261107-051813/AgentHostPackage.json`、`TestResults/20261107-053329/Temp/AgentHostProgress.jsonl`及`LiveModelLoopResult.json`。

## 3. 继续当前自然Campaign

- [ ] 3.1 从最新安全Native聚落检查点继续同一自然Campaign，由Agent依据Journal与当前Native状态自主选择目标；Harness不预选目标。`TestResults/20261107-071342`在¥0.10上限前发生费用拒绝：9个请求、估算¥0.04364508、预留¥0.0921528，下一请求需预留¥0.0097224；Host处于`encounter_meeting`，不能安全SaveAs。
  - [x] 3.1a 仅为诊断该中断而进行的一次同Campaign续跑`TestResults/20261107-072137`将上限提高到20决策/¥0.20：模型选择Native `leave`离开劫匪遭遇，不把它报成胜利；随后由模型选择Renown目标但无安全行动，再选择PartySize并发布到EW3的原版移动。总19决策、54326输入/1069输出token，估算¥0.093680064；Journal仍未增长。安全Native SaveAs成功，保存同一Campaign `ChronicleEycDev-freshB-20261107072404-a9aa2b09`（SHA-256 `943D835DD38AB58483D4E85427F8C6078194FD512CC6D8100AB41BDD28A375F0`），进程清理通过。
  - [x] 3.1b 从该安全检查点执行一轮20决策/¥0.20续跑：`TestResults/20261107-072945`恢复同一Campaign并读取到1个已保存empty-Town记录；Agent多次自主选择Companion，在途中处理一支劫匪遭遇的原版对话，后选PartySize/Companion交替。19决策、52757输入/1112输出token、估算¥0.091832544。没有招募或Journal进度；安全Town状态Native SaveAs成功为`ChronicleEycDev-freshB-20261107073215-51b70a75`（SHA-256 `F4E2A052BCFBC1C46617B8B538F5E7ABDFE8854B00EB18631C4294465F140503`），进程清理通过。
  - [x] 3.1c `TestResults/20261107-073719`从同一Campaign安全Map存档续跑19决策、¥0.090696288；原版劫匪赎金使Gold 670→424，MainParty暂时归零，之后Host恢复。PartySize / Companions / Renown最终Journal未增长；安全Native SaveAs为`ChronicleEycDev-freshB-20261107073947-178ae0f7`（SHA-256 `290434B413E7BF260B83C933F4654D09724EBD9DC457A562DCBCD3DC4C0EB35C`），进程清理通过。checkpoint仍在前往EW6途中。
  - [ ] 3.1d 从该新安全Campaign map checkpoint做下一轮，最多30决策、`CHRONICLE_LLM_MAX_RUN_COST_CNY=0.30`。预期移动到当前模型选择的聚落后进入原版志愿者界面并使PartySize Journal增长；若模型仍在同伴搜索与俘虏恢复之间循环或未增加Journal，保留完整原因，先修循环/反馈，不对同一状态自动重复。

## Workflow follow-up

- 完成本变更后回到GitHub issue #130继续剩余EYC目标。两个独立自然Campaign和原版Quest完成仍由#130完整验收，不由本变更代替。
