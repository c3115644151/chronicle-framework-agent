# 设计

## 背景

Native `encounter`菜单的 `leave_soldiers_behind` 会打开 Try-to-get-away 损失估计。用户或AI可以在该页选择原版 `try_to_get_away_reject` 返回先前遭遇菜单。真实自然运行 `TestResults/20261110-235029` 中，AI在没有队伍规模或敌队变化的情况下重复提交这两个选项，费用预算在重复期间耗尽。

## 目标

- 在同一次BattleSimulation循环中识别“Native撤退提示被拒绝后回到同一遭遇”的无进展状态。
- 仅隐藏本轮已经拒绝的 `leave_soldiers_behind`，保留所有其它当前可用的原版选项。
- 当遭遇身份或玩家/敌方队伍规模变化时清除临时限制。
- 保留模型对下一项行动的自主选择，且不伪造原版结果。

## 非目标

- 不代替模型选择Fight、Leave、Surrender或接受撤退损失。
- 不修改Native `PlayerEncounter`、菜单、队伍或时间。
- 不跨Campaign/存档持久化这项临时遭遇防重复状态。

## 决策

- 用 `encounteredPartyId`、当前目标ID、MainParty成员/健康/伤员/俘虏数量、当前可观察敌队成员数构造本次拒绝指纹。
- 在Native `try_to_get_away_reject` 成功并回到当前Encounter后，将该指纹保留在子流程内存中。
- 当指纹与当前Encounter相同，选项目录排除 `leave_soldiers_behind`，并向模型说明该尝试已经被拒绝且状态未变；目录中的其它Native可选项保持原样。
- 若坐镇、原版Leave及刚被拒绝的撤退尝试均不可用，且MainHero BattleAndCaptivity恢复模式开启、Native仍启用投降，则把当前原版 `surrender` 作为备选列给模型；只有模型选择后才调用它，随后走现有Native俘虏恢复。
- 队伍指纹或遭遇目标改变即清除限制；这让伤亡、援军、目标变更后重新评估Native行为。
- Fake Native/Provider覆盖拒绝后隐藏同一选项、其他选项保留、队伍规模变化重新开放、恢复模式下Native surrender回退、正常BattleSimulation继续、单个Episode内无需额外存档。

## 风险

如果Native状态缺少其中某个规模值，指纹要明确保留未知分量而不能凭空估值；至少仍需可确认遭遇身份。不能将通用“尝试撤退”动作永久屏蔽，也不能误把一次明确拒绝变成自动离开或自动战斗。
