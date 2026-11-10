# native-escape-warning-no-progress-guard Specification

## Purpose
在原版遭遇撤退警告被拒绝后，阻止AI于双方状态未变化时重复打开同一警告，同时保留其他当前可用的原版选择。

## Requirements

### Requirement: 已拒绝且未变化的原版撤退警告不可重复提交
同一 Native Encounter 中，若AI拒绝 Try-to-get-away 警告且遭遇目标及双方可观测队伍规模未变化，Host MUST 暂时从当前可选目录中移除再次提交 `leave_soldiers_behind` 的选项，并保留其他当前可用的原版Encounter选项。Host MUST NOT 自动替模型选择其中任一选项。

#### Scenario: 原版撤退警告被拒绝且遭遇未变化
- **GIVEN** AI在Try-to-get-away页面选择当前可用的原版拒绝选项
- **WHEN** Native返回相同遭遇，且遭遇ID和双方队伍规模快照不变
- **THEN** Host不再列出 `leave_soldiers_behind`，并将其他当前可用的原版选项交给AI决定

#### Scenario: 双方队伍规模发生变化
- **GIVEN** 同一Encounter中的原版撤退警告此前被拒绝
- **WHEN** Host观察到玩家队伍或敌方队伍规模发生变化
- **THEN** Host重新开放当前Native `leave_soldiers_behind` 选项，让AI根据新的风险状态重新评估

#### Scenario: 遭遇对象发生变化
- **GIVEN** 先前的撤退警告在一支敌队的遭遇中被拒绝
- **WHEN** 当前Native Encounter指向另一支队伍
- **THEN** 先前的限制不影响新遭遇的当前可用选项

#### Scenario: 原版撤退已被接受
- **GIVEN** AI接受Native Try-to-get-away损失估计
- **WHEN** Native进入原版撤退结算/离开遭遇流程
- **THEN** Host继续处理当前Native结果，不把已拒绝选项的防重复限制应用到新状态

#### Scenario: 其他遭遇行动不可用时保留已启用的原版投降
- **GIVEN** Try-to-get-away已被拒绝、坐镇和Leave不可用，BattleAndCaptivity恢复路径已启用且Native仍启用了投降
- **WHEN** Host为当前Encounter生成选项目录
- **THEN** Host列出当前Native投降选项交给模型决定；模型选择后才走原版俘虏恢复，不将投降解释为战斗胜利
