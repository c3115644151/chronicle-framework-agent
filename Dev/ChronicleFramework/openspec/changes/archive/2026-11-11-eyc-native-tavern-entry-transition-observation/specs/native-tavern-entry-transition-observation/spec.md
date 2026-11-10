# Spec Delta

## Purpose

确保AI使用原版酒馆入口后先观察状态转换，再从实际酒馆场景继续同伴搜索。

## ADDED Requirements

### Requirement: 原版酒馆入口转换完成前不得提交后续模型决定
当Host成功调用当前可用的Town Backstreet `town_tavern`选项后，Host MUST 先读取新鲜Native状态，直到确认酒馆Mission已启动、确认原版回到MapState，或有限观察超时。观察期间 MUST NOT 发出另一模型决策、重复菜单动作或时钟动作。

#### Scenario: 原版延迟启动酒馆Mission
- **GIVEN** Native `town_backstreet`中当前可用的 `town_tavern` 被选择
- **WHEN** Native仍返回旧Map菜单，随后进入Tavern MissionState
- **THEN** Host在MissionState确认前只被动观察；确认后继续读取当前场景Agent，不让模型选择旧菜单上的返回项

#### Scenario: 原版返回Map且未进入Tavern Mission
- **GIVEN** 当前Native Tavern入口已提交
- **WHEN** 有限观察窗口结束时仍未看到有效Tavern Mission，Native仍在MapState
- **THEN** Host返回最新Native状态，不计该Town为已访问且不重发入口

#### Scenario: Tavern Mission转换超时或Host取消
- **GIVEN** 当前Native Tavern入口转换仍未得到确认
- **WHEN** 达到观察上限或Host取消
- **THEN** Host停止被动观察并报告当前状态，不增加模型/Native动作，也不标记该Town为已访问
