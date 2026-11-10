# 提案：阻止重复打开已拒绝的撤退警告

## 为什么

自然战役续跑 `TestResults/20261110-235029` 在同一劫匪遭遇中反复循环：AI选择 Native `leave_soldiers_behind` 打开 Try-to-get-away 风险提示，再选择 `try_to_get_away_reject` 返回 Encounter，随后重复同一路径直到¥0.20预算保护拒绝下一请求。循环没有形成新的Native行动结果，也没有安全检查点。

## 变更内容

- Native Try-to-get-away 被拒绝后，记录当前遭遇双方的队伍规模快照。
- 若回到同一遭遇且双方队伍状态未改变，暂时不再把同一个 `leave_soldiers_behind` 选项列给模型；其他当前可用的Native遭遇选项继续由模型决定。
- 若遭遇目标或任一方队伍规模改变，则重新开放Native原选项并重新评估。
- 若撤退选项已被临时抑制、坐镇/撤退不可用而Native仍提供投降，且BattleAndCaptivity恢复路径已启用，则把投降作为当前可选的原版生存路线交给模型决定。
- 不替模型选择战斗、离开、投降或其他遭遇选项；不改变原版UI、队伍或Campaign时间。

## 能力

### 新增能力

- `native-escape-warning-no-progress-guard`：在同一未变化的遭遇中阻止重复提交已拒绝的Native撤退尝试。

### 修改能力

无。

## 影响

修改现有 `AgentHostBattleSimulationLoop` 遭遇选项目录及 Fake Native/Provider 回归。属于 GitHub #130 的 MainHero 长程StoryMode验收，不新增产品工作项。
