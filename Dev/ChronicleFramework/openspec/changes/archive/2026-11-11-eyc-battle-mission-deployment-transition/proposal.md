# 提案

## 原因

零模型现场探针确认：Native遭遇菜单的“攻入敌阵”会先进入`MissionState/Deployment`，而现有Host只等待`Battle`模式，结果没有执行F6委派并在超时后停止。为完成#132所需的原版战斗切片，Host必须先走Native部署结束处理，再等Battle模式就绪。

## 变更内容

- 为普通Campaign野战Battle Mission增加一个受限的Native部署结束动作，只在当前Mission处于`Deployment`且Campaign时钟为Stop时调用。
- Host在Native `attack`后观察到Deployment时，无需模型调用地提交该动作；回读Battle模式后再执行一次F6等价队伍委派。
- 处理拒绝、未能进入Battle、弹窗/Inquiry和超时：不得重放非幂等的Native部署动作，不得声称战斗已开始或已结算。
- 保持坐镇优先；不扩展围城、藏身处、海战、友好Mission或玩家自定义队形编辑。

## 能力

### 新能力

无。

### 修改能力

- `native-battle-mission-delegation`：增加Attack Mission从Deployment进入Battle的Native部署结束阶段，并在此后执行原版F6队伍委派。

## 影响

影响`AgentProtocol`、`AgentBattleMissionAdapter`、AgentHost BattleMission loop、Agent CLI和零模型Native探针。验证使用可丢弃Campaign存档副本；不调用LLM、不修改原版结算或Campaign时钟。产品工作属于GitHub #132，不新增Issue。
