# Proposal

## Why

真实 EYC 续跑显示，同伴搜索会在 Host 重启后重复访问已确认无候选的城镇；劫匪中断原版行军后，子流程也曾丢失正在执行的原版目的地并重复移动。`TestResults/20261107-043410`记录了重复 EW2 移动，`TestResults/20261107-053329`则证明原版投降与赎金恢复可运行，但队伍成长目标仍未完成。重复决策增加费用，且阻碍长程 Campaign 验证。

## What Changes

- 将“此城镇当前没有合格同伴”的 Native 观察保存在当前 Campaign 的 Agent 检查点中，并在恢复时根据当前 EYC Journal 进度判断是否继续适用。
- Town Tavern 没有可招募 Wanderer 且 Native 只有“离开”选项时，Host 走原版离场；存在候选或对话选择时，仍由真实模型决策。
- 子流程遇到 Bandit 等中断后，若 Native 仍在行军，就接回当前原版目标；已确认的敌对劫匪则优先进入原有 BattleSimulation / Captivity Recovery 路线。
- 通过受预算限制的自然 Campaign 续跑验证这些恢复路径，并保留确切 TestResults 收据与估算费用。

## Capabilities

### New Capabilities

- `companion-search-recovery`: 为原版 EYC 同伴搜索及其行军、敌对遭遇和跨 Host 恢复提供可验证的连续性行为。

### Modified Capabilities

无。本变更在 GitHub 产品 Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130) 范围内细化实现与验证，不改变其完整门禁。

## Impact

影响 `AgentHostEstablishClanCompanionLoop`、`AgentHostEstablishYourClanAutonomyLoop`、Native Campaign checkpoint 邮箱协议和 Harness 运行证据。不得写入 EYC 目标进度、战斗结果或主角资源；仍要求真实原版交互、Native 后验和完整的两场自然 Campaign 验收。
