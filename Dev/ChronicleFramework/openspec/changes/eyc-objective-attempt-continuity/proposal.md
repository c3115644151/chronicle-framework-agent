# Proposal

## Why

同一自然Campaign的有限续跑表明：Host重启后会重新花费模型决策识别EYC并选择目标；模型有时重复走同伴路线，另一次则在只读查询志愿兵报价后遇到预算保护，没能做出招募选择。要让玩家在停机/费用边界后续玩同一存档，Host需要保留可核验的路线结果，让模型知道上次停在哪里、当前原版状态是否已变化。

## What Changes

- 在Native Campaign checkpoint中保存EYC目标ID、最后结果类别、原版Journal前后值与Native路线状态指纹；不保存提示词、模型原始文本或密钥。
- 新Host从同一存档恢复时，Journal目标未变化的预算待续路线直接恢复子流程，但每个具体动作仍重新观察Native目录；无进展失败路线只在Journal与Native路线指纹均未变化时暂时排除。费用上限记录为“待继续”，不能误判为路线失败。
- Journal增长或相关Native路线状态变化后重新开放相应目标；剩余有效目标仍由模型选择，不硬编码游戏进度顺序，不注入资源/目标/动作，也不改变Bannerlord机制。

## Capabilities

### New Capabilities

- `eyc-objective-continuation-memory`: 让EYC规划器跨同一Campaign Host重启保留已核实的路线结果，并在费用边界/无进展后根据当前Native状态恢复规划。

### Modified Capabilities

无。此变更细化GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130)，不改变其两场新战役完成原版EYC的总门禁。

## Impact

影响AgentHost EYC父级循环、只读目标规划器、既有Native Campaign checkpoint与Host回归测试。Native存档身份/结构继续使用现有Campaign checkpoint；不新增外部数据库或玩家配置，不引入新的Native gameplay action。包测试与真实Campaign证据分别记录，最终EYC完成仍由Issue #130验收。
