# F 类专题：俘虏与释放

状态：机制拆解，未进行方案评审

本文描述 Hero 俘虏、转移、赎金、释放、逃脱和相关关系/日志入口。

## F01 被俘

`TakePrisonerAction` 主要执行：

- 从原队伍成员列表移除 Hero；
- 如果 Hero 是队长，移除队长身份；
- 记录 `CaptivityStartTime`；
- 将 Hero 状态改为 `Prisoner`；
- 加入捕获方 Party 的 PrisonRoster；
- 如果是玩家，进入 `PlayerCaptivity`；
- 清除 Hero 的 StayingInSettlement；
- 触发 `HeroPrisonerTaken`。

该动作直接处理队伍归属和人物状态，不在动作本身修改个人关系。

## F02 俘虏持有

Hero 俘虏可以存在于：

- 移动队伍；
- 城镇、城堡等聚落地牢；
- 驻军；
- 战争队伍；
- 商队等拥有 Party 的对象。

俘虏可以通过 `TransferPrisonerAction` 在 Party 之间转移。转移会更新 PrisonRoster，并可能触发聚落俘虏变化事件。

## F03 释放类型

`EndCaptivityAction` 提供以下主要结束路径：

- `Ransom`：赎金释放；
- `ReleasedAfterPeace`：和平后释放；
- `ReleasedAfterBattle`：战后释放；
- `ReleasedAfterEscape`：逃脱；
- `ReleasedByChoice`：玩家或 Party 主动释放；
- `ReleasedByCompensation`：补偿释放；
- `Death`：死亡结束俘虏状态。

释放动作会：

- 从 PrisonRoster 移除 Hero；
- 改变 Hero 状态；
- 对部分同伴生成 Fugitive 状态；
- 将 Hero 放回当前聚落或释放位置；
- 触发 `HeroPrisonerReleased`。

释放动作本身不统一处理个人关系后果。

## F04 赎金与转移

### 赎金

`RansomOfferCampaignBehavior` 会按日评估是否提出赎金，受以下因素影响：

- 俘虏所属 Clan；
- 捕获方 Clan；
- Hero 是否为领袖；
- 赎金价值；
- 赎金支付者金币；
- 之前是否拒绝过赎金；
- 随机机会率。

`SetPrisonerFreeBarterable` 使用赎金模型计算价值，并根据俘虏时间提高部分家族方价值。

### 转移

`TransferPrisonerBarterable` 允许在满足阵营敌对条件时通过 Barter 转移俘虏。转移本身不改变 Hero 个人关系。

## F05 自动释放

`PrisonerReleaseCampaignBehavior` 会在以下情况下释放部分俘虏：

- 和平达成；
- 家族加入或离开 Kingdom；
- 阵营关系变化后不再敌对；
- 每日逃脱检查；
- 某些版本迁移和队伍异常修复。

释放概率会受俘虏所在 Party 是否移动、是否为玩家 Party、队伍规模等条件影响。

## F06 关系相关路径

### 主动释放

领主对话中存在明确关系奖励：

- 玩家主动释放战败后俘虏的领主，会调用 `ApplyPlayerRelation(..., 4)`；
- 玩家选择释放非战斗俘虏的领主，会调用 `ApplyPlayerRelation(..., 10)`；
- 释放行为和关系奖励是两个独立调用。

### 其他释放路径

赎金、和平释放、逃脱、战后释放和自动释放主要改变 Hero 状态、Party 和日志；不同路径不统一产生个人关系变化。

### 俘虏捐献

`DefaultPrisonerDonationModel` 会根据：

- 俘虏价值；
- 俘虏与聚落领主的关系；
- 俘虏是否为王国领袖或家族领袖；

计算捐献英雄俘虏后的关系收益。

## F07 日志与通知

`DefaultLogsCampaignBehavior` 监听：

- `HeroPrisonerTaken`，创建 `TakePrisonerLogEntry`；
- `HeroPrisonerReleased`，按 `EndCaptivityDetail` 创建 `EndCaptivityLogEntry`；
- 部分释放路径可以关闭通知，因此不一定产生玩家可见日志。

## F08 当前机制边界

- 俘虏丢失队伍、状态和 Party 归属；
- 俘虏时间和赎金价值被保存；
- 释放类型被区分；
- 释放事件可被多个 Behavior 监听；
- 关系奖励只在部分玩家对话路径中明确写入；
- 被俘造成的军队损失、家族压力、个人羞辱、报复意愿和长期记忆没有统一数据入口。
