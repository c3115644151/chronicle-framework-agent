# 设计

## 背景

参见 proposal.md 与稳定 `native-battle-mission-delegation` 规格。当前 `AgentHostBattleMissionLoop` 等待 `MissionMode.Battle` 后才委派；`TestResults/20261111-070839`显示原版 `attack` 会先进入 `MissionState/Deployment`，在无Native Ready提交时一直停留。安装版1.4.8的 `MissionOrderDeploymentControllerVM.ExecuteBeginMission` 对普通野战关闭F1 Orders UI并调用 `DeploymentHandler.FinishDeployment()`；围城另有未部署器械Inquiry分支。Order of Battle预部署UI的 `OrderOfBattleVM.ExecuteBeginMission`还保存 formation 配置后再回调此链。

## 目标与非目标

**目标：**

- 在活动普通Campaign野战、Deployment、Campaign Stop且没有弹窗时，触发Native部署完成处理。
- 只在回读同一进程/同一Mission变成Battle后才执行已有一次性F6委派。
- 部署失败、Native拒绝或期限耗尽时停下并记录状态，不重复提交、不卡成“已开始战斗”。

**非目标：**

- 不修改围城/攻守器械/海战部署或其“Yes/No”部署询问。
- 不重排/重配Formation，不修改BattleSimulation士气门禁，不替MainHero发出攻击/移动输入。
- 不推进、暂停或切换Campaign时钟，不在部署/战斗中调用模型。

## 决策

1. **复用当前Native Ready ViewModel命令，不注入桌面按键。** `OrderOfBattle.xml`将“准备”按钮绑定到活动`MissionGauntletOrderOfBattleUIHandler`的`OrderOfBattleVM.ExecuteBeginMission`；该命令检查CanStartMission、保存当前Formation配置，再经UI回调进入F1部署VM并最终调用`DeploymentHandler.FinishDeployment()`。Native `missionFinishDeployment`在执行前解析当前Mission持有的该View实例及数据源；找不到View、Ready未启用、非普通野战或有Inquiry时拒绝。早期直接调用`DeploymentHandler.FinishDeployment()`触发`SPOrderOfBattleVM.SaveConfiguration`空引用（`TestResults/20261111-074838`），因此不再直接调用底层handler。用户未自定义Formation配置由Native当前View提交，Host不会覆盖。现场通过Battle Mode和BattleEnd结果核验成功。
1. **走原版Ready ViewModel回调，不注入桌面按键。** Native `OrderOfBattle.xml`把Ready/“准备”按钮绑定到当前`OrderOfBattleVM.ExecuteBeginMission`；它先保存现有Formation配置，然后经`MissionGauntletOrderOfBattleUIHandler`进入F1部署控制器，普通野战最终调用`DeploymentHandler.FinishDeployment()`。`missionFinishDeployment`只允许当前Battle Mission处于Deployment、Ready已启用、Campaign Stop、没有Inquiry时，调用当前Mission View的这个Native命令；找不到ViewModel或Ready不可用即拒绝。它不替Agent重排Formation，也不直接调用`Mission.EndMission`。不使用Windows按键或鼠标。实际本地按钮文本、特定战场配置和进入Battle的运行时序由现场探针核验。
2. **顺序是Attack → Deployment完成 → 确认Battle → F6委派。** 不在Deployment猜测Mission已开始；部署Finish命令一次后只读等待，同一Mission到Battle才调用已有`missionDelegateTroops`。Host仍优先坐镇；只有Simulation禁用、Attack开启且有健康士兵时才进入此支路。
3. **超时和状态切换均不重放。** 任务使用同一Native进程ID和Mission检查，状态/菜单/弹窗不匹配时返回明确失败；部署Finish和F6都是非幂等请求，超时作为ambiguous记录，不再重发。Campaign时间始终保持Stop。

## 风险与取舍

- **Native UI细节尚未人工目视确认。** Source显示Order of Battle Ready文本为CN“准备”，且F1 Deployment菜单有自己的ExecuteBeginMission链；用户的实际UI回答待回收。引擎源、UI prefab和一次现场截图作为佐证；不硬编码OS键盘/鼠标。
- **Direct Native handler与整个UI callback不完全相同。** 我们调用的底层`FinishDeployment`不提交模型未编辑的Order of Battle个人配置。现场若自然队形配置、副作用或UI遮挡不同，则改为可验证的当前原版ViewModel回调或停止该支路。
- **败北或主角受伤仍是独立风险。** 部署结束后F6仍只控制部队；MainHero保持Player控制。已有只读健康/位置/编队观察不构成通用生存保证，不能据一例宣称安全。

## 回滚

移除`missionFinishDeployment` Native/Host调用并关闭 Attack Mission fallback；原有坐镇/Native encounter Leave/Try-to-get-away路径不受影响。disposable SaveAs副本只在Hash仍与测试保存后一致时删除，源Campaign哈希必须保持不变。
