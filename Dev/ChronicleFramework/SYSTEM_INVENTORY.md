# Bannerlord 机制系统清单

状态：第一版盘点，尚未逐项评审

这不是功能愿望表，也不是优化优先级。它的作用是建立研究地图，防止只从少数已知问题反推整个游戏。

## A. 战役运行与世界状态

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| A01 | 战役生命周期 | 新档、读档、战役启动、结束、游戏模式初始化 |
| A02 | 战役时间 | 小时、日、周、季节、年份、时间控制和暂停 |
| A03 | 周期事件 | Tick、小时、日、周、聚落/家族/英雄周期事件 |
| A04 | CampaignEvent 总线 | 原版状态变化、行动结果和生命周期回调 |
| A05 | 存档系统 | 战役对象序列化、版本迁移、Mod 自定义数据 |
| A06 | 难度与战役选项 | 伤害、死亡、经济、AI、出生、铁人等选项 |
| A07 | 事件日志 | `LogEntryHistory`、新闻、通知、百科关联、NPC 历史评论 |
| A08 | 教程与提示 | 概念百科、教程状态、首次体验提示 |

## B. 世界实体与身份

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| B01 | Hero 生命周期 | 出生、成年、老化、死亡、状态转换 |
| B02 | Hero 家庭 | 血缘、婚姻、配偶、子女、继承相关关系 |
| B03 | Hero 能力 | 属性、技能、特长、Perk、特征、经验 |
| B04 | Hero 身份 | 领主、同伴、商人、村民、囚犯、统治者、总督 |
| B05 | Clan | 家族成员、领地、家族等级、声望、影响力、财政 |
| B06 | Kingdom | 王国成员、统治家族、政策、领地、预算、军队 |
| B07 | Culture | 文化属性、兵种、政策倾向、聚落文化、文化效果 |
| B08 | Faction 与 Stance | 阵营关系、敌对、和平、联盟、贡金、永久战争 |
| B09 | Personal Relation | Hero 间个人关系、有效关系、亲属关系修正 |
| B10 | Trait 与 Reputation | 性格特征、荣誉、罪恶、犯罪评价和行为反馈 |

## C. 政治与外交

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| C01 | Kingdom Decision | 决策提案、提案者、支持者、候选结果 |
| C02 | Kingdom Election | 支持度、影响力、投票、玩家介入、自动解决 |
| C03 | 战争与和平 | 宣战、和平、战争状态、战争理由、贡金 |
| C04 | 联盟与援战 | 联盟、援战协议、召集、终止和连锁战争 |
| C05 | 王国政策 | 政策添加、移除、政策效果、政治成本 |
| C06 | 领地分配 | 新领地归属、家族支持、统治者决策、争议 |
| C07 | 家族脱离与投奔 | 离开王国、加入王国、雇佣兵、叛变、忠诚 |
| C08 | 王国创建与毁灭 | 玩家建国、王国消灭、成员转移、遗留状态 |
| C09 | 叛乱 | 忠诚、民兵、叛乱生成、叛军领地、平叛 |
| C10 | 贸易协定与贡金 | 王国间协议、支付、收益、取消条件 |

## D. 聚落与领地

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| D01 | Settlement 基础状态 | 城镇、城堡、村庄、藏身处、所有者、文化 |
| D02 | 城镇发展 | 繁荣、安全、忠诚、民兵、驻军、食物 |
| D03 | 城堡发展 | 建筑、驻军、防御、村庄绑定、领地价值 |
| D04 | 村庄状态 | 生产、繁荣、村民、被掠夺、绑定城镇 |
| D05 | 聚落建筑 | 建筑等级、建设队列、建造速度、建设效果 |
| D06 | 聚落项目 | 建造项目、民兵、灌溉、住房、庆典等项目 |
| D07 | 总督与驻守 | 总督任命、驻军管理、治理效果、角色职责 |
| D08 | 聚落犯罪与帮派 | 罪案、帮派、巷道、控制、清剿 |
| D09 | 聚落访问 | 城镇、城堡、村庄、酒馆、竞技场、领主大厅、地牢 |
| D10 | 聚落易主后果 | 领主变更、驻军、繁荣、忠诚、事件和日志 |

## E. 经济与贸易

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| E01 | 物品与商品 | 物品类别、价格、重量、生产、消耗、稀缺性 |
| E02 | 市场价格 | 供需、城镇库存、买卖、价格传播 |
| E03 | 村庄生产链 | 村庄资源、生产项目、绑定城镇供应 |
| E04 | Workshop | 工坊类型、原料、产出、收益、所有权 |
| E05 | Caravan | 商队创建、路线、货物、收益、被袭击、重建 |
| E06 | Party 经济 | 工资、食物、马匹、俘虏、战利品、负债 |
| E07 | Clan 财政 | 家族收入、支出、债务、贡金、领地收益 |
| E08 | Kingdom 财政 | 王国预算、军费、贡金、雇佣兵、援战支出 |
| E09 | Trade Skill | 贸易经验、Perk、价格优势、商队和交易行为 |
| E10 | Barter | 金钱、领地、俘虏、和平、婚姻、服务交换 |

## F. 军事、队伍与 AI

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| F01 | MobileParty | 队伍创建、移动、速度、食物、工资、目标 |
| F02 | Party AI | 小时级目标选择、移动行为、追击、逃跑、访问 |
| F03 | AI 行为类型 | 巡逻、护送、掠夺、围城、支援、驻守、逃避 |
| F04 | Party Think | 目标评分、行为切换、行动冷却、环境约束 |
| F05 | Army | 组建、召集、领袖、成员、目标、解散 |
| F06 | Clan War Party | 家族战争队伍、生成、补充、战争消耗 |
| F07 | 战争目标 | 目标聚落、敌方队伍、边界、军事行动选择 |
| F08 | 围城 | 围城开始、工程、粮食、攻防、突围、结束 |
| F09 | 掠夺与防守 | 村庄掠夺、护卫、反制、状态恢复 |
| F10 | 战斗模拟 | 地图外战斗、双方实力、伤亡、俘虏、战利品 |
| F11 | 部队补充 | 招募、恢复、升级、逃兵、伤员、驻军补充 |
| F12 | 俘虏体系 | 俘虏容量、英雄俘虏、赎金、逃脱、招募、处决 |
| F13 | 军团与领主决策 | 召集意愿、影响力成本、领主参加和退出 |

## G. 战斗与战术

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| G01 | Encounter | 地图遭遇、敌我判定、谈判、逃跑、战斗入口 |
| G02 | Map Event | 战斗、围城、掠夺、救援、战斗连续性 |
| G03 | Battle Mission | 场景、双方队伍、生成、任务逻辑、结束条件 |
| G04 | Formation | 编队、兵种分类、队长、阵型、队形移动 |
| G05 | Orders | 命令菜单、指挥、响应、AI 执行 |
| G06 | Tactics 与战术 AI | 阵型决策、目标选择、冲锋、撤退、掩护 |
| G07 | Morale | 士气、溃败、战斗表现、人数和战果影响 |
| G08 | Siege Mission | 攻城器械、城墙、门、梯、突击、守城逻辑 |
| G09 | Combat Resolution | 伤亡、死亡/昏迷、技能、医术、俘虏、战利品 |
| G10 | 战斗奖励 | 经验、声望、影响力、金钱、战利品、日志 |

## H. 玩家、队伍与成长

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| H01 | 玩家身份 | 角色创建、文化、家族、王国、统治者 |
| H02 | Player Clan | 家族等级、成员、领地、影响力、声望 |
| H03 | Main Party | 队伍规模、速度、食物、工资、士气、角色 |
| H04 | Troop Roster | 部队数量、伤员、升级、经验、兵种树 |
| H05 | Companion | 招募、职责、关系、离队、家族成员化 |
| H06 | Party Roles | 偵察、医师、工程师、军需官、队长 |
| H07 | Inventory | 装备、物品、战利品、库存、负重 |
| H08 | Equipment | 武器、防具、坐骑、装备槽、属性 |
| H09 | Crafting | 锻造、配方、材料、耐力、装备生成 |
| H10 | Skills 与 Perks | 技能成长、特长、效果、触发条件 |
| H11 | Renown 与 Influence | 声望、影响力、获取、消耗、政治权限 |
| H12 | Player Captivity | 玩家被俘、逃脱、赎金、等待、结束状态 |

## I. 角色社会关系

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| I01 | Personal Relation | Hero 间关系、有效关系、亲属修正 |
| I02 | Faction Relation | 家族/王国关系、敌对、和平、联盟 |
| I03 | Prisoner Social State | 被俘、释放、赎金、逃脱、仇恨、感激 |
| I04 | Marriage 与 Romance | 求婚、婚姻、配偶、家族联结、继承 |
| I05 | Family 与 Kinship | 血缘、家族成员、死亡、继承人、继承影响 |
| I06 | Education | 子女成长、教育选择、特征和技能结果 |
| I07 | Traits | 勇敢、仁慈、荣誉等特征与行为/对话关系 |
| I08 | Crime 与 Reputation | 犯罪评价、悬赏、敌对、赎罪、地区反应 |
| I09 | Dialogue Relation | 对话条件、关系、性格、历史、任务状态 |
| I10 | Persuasion | 说服选项、成功率、关系、性格、结果 |

## J. 任务、事件与叙事

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| J01 | Issues | 聚落问题、领主问题、商人/村民问题、解决者 |
| J02 | Quests | 任务生命周期、目标、失败、完成、奖励 |
| J03 | Quest Tasks | 路径、对话、交付、战斗、护送、追踪 |
| J04 | Journal | 任务日志、更新、状态、展示、隐藏信息 |
| J05 | Incidents | 战役事件、随机事件、触发条件、结果 |
| J06 | Rumors | 传闻生成、传播、来源、过期、可信度 |
| J07 | Notifications | 通知类型、优先级、玩家相关性、历史 |
| J08 | Conversations | 对话树、条件、后果、声音、关系 |
| J09 | Persuasion Dialogues | 说服过程、风险、奖励、失败后果 |
| J10 | Tournament | 赛事生成、参赛、奖励、声望、城镇影响 |
| J11 | Board Games | 棋盘游戏、赌注、技能、城镇活动 |
| J12 | Story Mode | 教程、主线、阴谋、旗帜、阶段性任务 |

## K. 地图、移动与环境

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| K01 | World Map | 地图实体、位置、可见性、互动、标记 |
| K02 | Navigation | 路径、地形、速度、追击、逃脱、障碍 |
| K03 | Tracking | 足迹、侦察、追踪、发现、丢失 |
| K04 | Weather | 天气、季节、地图环境、战斗影响 |
| K05 | Sea 与 Port | 航海、港口、船只、海上移动、登船 |
| K06 | Encounter Flow | 遭遇判断、谈判、战斗、逃跑、菜单切换 |
| K07 | Hideout | 藏身处生成、侦察、攻击、首领、清除 |
| K08 | Bandit Density | 区域匪患、生成、消灭、恢复 |

## L. 内容、界面与技术基础

| 编号 | 系统 | 主要边界 |
| --- | --- | --- |
| L01 | XML 数据 | 物品、文化、兵种、角色、聚落、项目、文本 |
| L02 | XSLT 覆盖 | 非破坏性修改官方模块数据 |
| L03 | Game Menu | 战役菜单、选项、等待、动态文本、条件 |
| L04 | Dialogue System | 对话注册、条件、文本、后果、优先级 |
| L05 | Encyclopedia | 页面、对象、历史日志、筛选、书签 |
| L06 | Notifications | 弹窗、聊天、颜色、声音、优先级 |
| L07 | Scene 与 Mission | 场景、任务控制器、地点、角色、脚本 |
| L08 | Localization | 文本 ID、语言、变量、复数、格式化 |
| L09 | Module Loading | SubModule、依赖、加载顺序、社区元数据 |
| L10 | CampaignBehavior | 生命周期、事件订阅、状态、卸载 |
| L11 | GameModel | 替换/扩展原版计算模型 |
| L12 | Harmony / BLSE | 非公开入口、早期加载、补丁、调试、异常拦截 |
| L13 | SaveSystem | 自定义类型、字段、版本迁移、兼容性 |

## 跨域玩家行动与观察目录

### 目录口径

本目录只数玩家能真实触发的原版行为族和能主动/被动读取的观察面；A-L中的系统对象、API、事件、菜单/GameState、模型和现有Chronicle命令数都不是行为分母。

- **行为族 ID (`ACT-*`)**：在同一游戏上下文有相同原版入口语义、相同核心状态转移/失败类和同一时间副作用的可参数化动作。不同按钮若最终经过同一原版Handler且副作用相同，只保留一个族并列为别名；看似同一个按钮但结果/权限/时间不同则分开。
- **观察面 ID (`OBS-*`)**：玩家能从HUD、地图视觉、悬停/ALT、界面、日志/百科、通知或交互结果读到的一组同源信息。相同数据经多个入口显示时保留入口别名；若可见条件、精度、时效或权限不同，必须分开。
- **跨域映射**：每个目录族连接一个或多个 A-L 系统条目及类别Research段落。复合流程只在各独立状态提交点拆分，不按按钮数或类数切碎；跨域同一行为只保留一个唯一ID。
- **未知处理**：标出具体未查明入口/分支及可能扩充目录的证据，不放进“已核实分母”，也不静默当成N/A。只有源码和/或运行证据确认没有直接玩家affordance时才能标 `N/A`，并写明它为何仅为引擎后台。
- **证据级别**：源/资源确认、结构化运行、原生UI自动执行、玩家视觉确认分别注明；UI路径未知不能因API成功升级为已支持。最终总分母是通过去重和依赖核查后的ACT/OBS ID数量；未映射项数、未知项和单项适配级别另报，不能用“总系统数”填补。

### A域初始交叉映射

以下为A01-A08的首轮目录种子，ID只用于跨域唯一引用；本节不是最终全游戏分母，具体状态/副作用继续指向A域权威研究及MAINLINE契约。

| ID | 类型 | 玩家入口 / 观察语义 | 原版边界与时间 | Chronicle现状 / 证据与未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| ACT-A01-01 | 行为 | 初始菜单→Sandbox新战役 | 建立普通Campaign后进入角色创建；没有既有Campaign时间 | Harness能创建新Campaign，但不通过初始菜单点击端到端验证；新档创建夹具已结构化验证 | A01、B07、L09；`Research/A/CampaignRuntimeWorldState.md` |
| ACT-A01-02 | 行为 | 初始菜单→Story Mode新战役 | 建立`CampaignStoryMode`并进入StoryMode专属开局 | Chronicle未操控StoryMode菜单/主线初始化 | A01、B07、J12、L09 |
| ACT-A01-03 | 行为 | 初始菜单→Continue latest，或已存档游戏→选择slot→Load | 两入口最终均读取一个Campaign存档且跳过角色创建；默认slot选择与手动slot选择作为参数变体保留 | Protocol可指定存档并新进程加载；菜单自身未视觉/自动点击验证 | A01、A05、L13 |
| ACT-A02-01 | 行为 | 地图底部Pause/Normal/Fast-forward时间控件 | 修改`CampaignTimeControlMode`；世界是否实际推进还受MapState、等待、Mission等上下文限制 | Observer读当前timeControlMode；Protocol可暂停/恢复/独立推进，显式`advance`仅Harness用 | A02、K02；MAINLINE原版机制契约 |
| ACT-A05-01 | 行为 | 地图ESC/F5 QuickSave | 排队快速保存；只有保存完成回执后结果成立，F5与ESC别名最终落同入口 | Protocol `save`完成存档往返；没有ESC/F5真实输入测试 | A05、L13；MAINLINE Save验收 |
| ACT-A05-02 | 行为 | Save As→新建slot或覆盖→确认 | 选择名称/覆盖后排队保存；错误/取消不得误报完成 | Protocol使用唯一测试名SaveAs，UI确认流程未验证 | A05、L13 |
| ACT-A06-01 | 行为 | 新战役Character Creation→Options/Difficulty | 选择初始难度/战役选项影响新Campaign初态 | Chronicle不适配角色创建选项控件；自动夹具会跳过/选择预设，不代表模型能力 | A01、A06、H01、L09 |
| ACT-A06-02 | 行为 | Campaign Options界面更改当前存档选项 | 选项由Provider/身份/周期条件启用；会写入Campaign配置或触发模式变化 | Chronicle不观察/不操作Campaign Options VM；逐项门槛未在L域展开 | A06、L03/L08 |
| ACT-A08-01 | 行为 | 新战役开场动画按ESC跳过 | 结束视频播放并进入创建阶段；不应反复空等数分钟 | Harness FreshCampaign设跳过路径；ESC具体 handler 未定位，用户视觉确认可跳 | A01、A08；FreshCampaign验收 |
| OBS-A02-01 | 观察 | 地图时间/日期/速度档 | HUD显示Campaign时钟与当前时间控制档；Mission暂停和战役快进分开 | Observer输出campaignDay/timeControlMode；UI图标/标题尚未实机对照 | A02、L06；MAINLINE |
| OBS-A07-01 | 观察 | Encyclopedia(Hero history)/日志 | 从全局历史条目按页面可见条件筛出角色历史；不等于实时全世界快照 | Chronicle不输出LogEntryHistory或百科历史列表 | A07、L05；用户确认N百科入口 |
| OBS-A08-01 | 观察 | Tutorial提示 | 按Campaign类型/行为状态显示并可完成/关闭；StoryMode提示与Sandbox提示源不同 | Chronicle不读教程提示/完成状态 | A08、J12、L06 |
| OBS-A08-02 | 观察 | Concept百科页 | 按概念分类/页面显示帮助文本与链接；N百科入口UI细节以实测为准 | Chronicle不读Concept数据或页面当前项 | A08、L05、用户确认N百科入口 |
| N/A-A03-01 | N/A | Campaign小时/日/周等周期分发与对象Tick | 由Campaign时间和引擎调度触发，无“执行Tick”玩家入口；具体结果映射到造成状态变化的行为族 | 明确排除玩家动作分母；按时钟/生命周期研究保留来源与例外核查 | A03、`Research/A/CampaignRuntimeWorldState.md` |
| N/A-A04-01 | N/A | CampaignEvent事件总线/订阅回调 | 由原版/Mod代码发布与消费，不存在通用“触发事件”玩家命令；只有带独立玩家入口的专属事件映射为实际ACT | 明确排除玩家动作分母；事件发布者/消费者用于追溯其它目录项 | A04、`Research/A/CampaignRuntimeWorldState.md` |

A06预设/设置页目前只定位到界面族；每个选项的写入字段、条件与后续模型结果可能不同，候选设置操作不计入最终动作分母，待按原生Option ID逐项拆分。A03/A04目前映射为系统后台回调而非玩家直接动作；若某个具体事件存在手动玩家入口，应映射到发起该状态变化的ACT，而不是另造一个“触发CampaignEvent”动作。

| 内部系统 / N/A候选 | 分类理由 | 映射来源 / 仍需排除的直接玩家入口 |
| --- | --- | --- |
| A03 周期事件、A04 CampaignEvent总线 | `N/A-A03-01`、`N/A-A04-01`说明通用调度/事件总线不是玩家动作；带独立玩家入口的具体事件仍映射到其真实ACT | `Research/A/CampaignRuntimeWorldState.md`；若发现事件专属按钮，扩展对应ACT而不复用通用N/A |

### B域初始交叉映射

此表只复用B/H/I/C已研究的真实入口；一个B系统可映射多个行动族，一个行动族也可能服务多个系统。百科、人物身份字段和关系显示目前多数只有源码路径、未视觉复核。

| 系统ID | 映射到的玩家行动族 / 观察面 | 证据与去重边界 |
| --- | --- | --- |
| B01 Hero生命周期 | `OBS-B01-01` Hero百科/状态页；状态变化映射至导致出生/成年/被俘/释放/死亡的具体行为，不创建“改HeroState”玩家动作 | B01/B02/H12/F12；Hero是事件对象，没有通用生命周期操作面 |
| B02 Hero家庭 | `OBS-B02-01` Hero家庭/配偶/子女百科链；婚姻交涉映射`ACT-I04-01`、`ACT-I04-02`、`ACT-I04-03`，教育通知见`OBS-I06-01` | B02/I04/I05/I06；婚姻、出生、教育后果分开，不把亲属字段读写计为动作 |
| B03 Hero能力 | `OBS-B03-01` Character Developer面板；属性/Focus/Perk变更为`ACT-H10-01` | B03/H10；Character Developer待改→Done提交/Cancel撤销是一类界面事务，获得XP来自其它动作族 |
| B04 Hero身份 | `OBS-B04-01` Hero身份/职业/归属信息；婚姻Clan结果见I04，陪伴/封臣/王国变更见H05/C07 | B04/H05/C07/I04；没有通用“设置职业/归属”入口，转换必须映射具体原生流程 |
| B05 Clan | `OBS-B05-01` Clan Management页；改名、旗帜和财务/领地/成员各是待细分操作 | B05/H02/C；Clan页面本身不等于独立行动，不能将13个Tab/VM方法计入分母 |
| B06 Kingdom | `OBS-B06-01` Kingdom Management页；决议/战争/和平/联盟/政策映射C域独立行动族 | B06/C01-C10；K键/界面入口别名不是额外动作 |
| B07 Culture | 创建新Campaign时文化选择别名至`ACT-A01-01`或`ACT-A01-02` | B07/H01/A01；不建立Campaign中普遍存在的“换文化”动作 |
| B08 Faction/Stance | `OBS-B08-01` Diplomacy/地图敌对状态；战争/和平动作映射C03，联盟/援战映射C04 | B08/C；个人Hero关系和Faction Stance不可合并 |
| B09 Personal Relation | `OBS-B09-01` 对话/Barter中针对当前Hero的关系信息；写入来源映射I/J/F及具体动作族 | B09/I01/I09/J08；没有全局关系面板/统一增减关系动作 |
| B10 Trait/Crime | Trait展示映射`OBS-B10-01` Character Developer特征页；犯罪指控/可用处罚选项映射`OBS-I08-01` | Trait和Faction Crime Rating是不同数据族，角色开发页与执法菜单也不是同一观察面 |

#### B域与已引用I域行为/观察族定义

首列ACT/OBS ID是本跨域目录项的唯一声明；前面的系统交叉表仅引用这些ID，引用不重复计数。

| ID | 类型 | 玩家入口 / 观察语义 | 原版副作用 / 失败边界 | Chronicle / 来源 / 未知 |
| --- | --- | --- | --- | --- |
| OBS-B01-01 | 观察 | N→Hero百科页的当前身份/职业/文化等概要；Last Seen与历史日志字段单列到OBS-A07-01 | 页面基于可见/已知资料，不是全部Campaign实时状态 | Chronicle不提供完整Hero页面；B01/B04、A07、L05；页面条件未实机全验 |
| OBS-B02-01 | 观察 | N→Hero页面家庭、父母/子女/配偶等亲属视图 | 亲属对象引用不等同Clan成员、effective Relation或继承权 | Chronicle无家庭树；B02、I05；所有家庭可见规则未知 |
| OBS-B03-01 | 观察 | C→Character Developer的Attributes/Skills/Focus/Perks | 仅对VM筛选出的适用Hero显示；角色开发面板非全世界技能表 | Chronicle不读取完整成长字段；B03/H10/L05；同伴适用/禁用条件待测 |
| OBS-B04-01 | 观察 | Hero百科/对话对象上下文查看Occupation、Clan/Faction/当前归属 | Hero身份/Clan关系和Party所属状态分别显示，不能推断为一个“NPC阵营”字段 | Chronicle提供Main Hero身份和有限Party摘要；不提供周边Hero完整职业/历史归属 | B04、J08、AgentObserver；特例可见性未穷举 |
| OBS-B05-01 | 观察 | L→Clan Management的成员/Party/Fief/Finance页面 | 页面数据随当前PlayerClan刷新；Tab不等于操作 | Chronicle只输出Clan摘要；B05/H02/L05；领导身份差异待测 |
| OBS-B06-01 | 观察 | K→Kingdom Management各管理页 | 可用页面受Player Clan所在Faction与身份约束 | Chronicle无Kingdom/决议详情观察；B06/C/L05 |
| OBS-B08-01 | 观察 | Kingdom外交页面或地图附近Party Hostile摘要 | Stance是Faction对关系，不是Hero personal Relation；地图摘要仅回答敌对 | Chronicle只给附近Party Hostile；B08/I02/C03/L05；全Faction/联盟历史未接入 |
| OBS-B09-01 | 观察 | 对当前对话Hero显示/推导出的相处状态、称呼或选项提示 | 关系可能经过有效关系模型/身份映射，不等于原始整数或完整历史 | Chronicle不输出Hero relation；B09/I01/J08；是否给出数值取决于具体UI/页面 |
| OBS-I06-01 | 观察 | EducationMapNotification→EducationState课程页面 | 显示玩家子女待选年龄阶段/教育选项；逾期阶段可能先自动随机处理 | Chronicle不读取教育状态/选项；I06/H02/A08；通知打开/关闭与时钟需视觉复核 |
| OBS-B10-01 | 观察 | Character Developer页读取当前角色的Trait条目/等级 | Trait由行为累积改变，Character Developer显示Trait状态；不等于Faction CrimeRating或Hero Relation | Chronicle不输出Trait/XP；特征页完整入口和全部显示内容未视觉穷举 | B10/I07、CharacterDeveloperVM、HeroDeveloper |
| ACT-H10-01 | 行为 | C→Character Developer调整适用Hero的Skill Focus/Attribute/Perk后Done；Cancel撤销暂改 | 消耗未用成长点/要求Perk条件；Done才提交，Cancel不改变Hero成长 | Chronicle未实现；B03/H10/L05；子VM逐项前置未全测 |
| ACT-H02-01 | 行为 | L→Clan Management改Clan名称并确认 | 写入名称、触发页面/展示刷新；取消不提交 | Chronicle未实现；B05/H02/L05；当前身份/命名校验待视觉验证 |
| ACT-H02-02 | 行为 | L→Clan Management打开Banner Editor并确认 | 写入Clan Banner；不是单纯展示/百科编辑 | Chronicle未实现；B05/H02/L05；每种画面/确认取消未视觉验证 |
| ACT-I04-01 | 行为 | 与可结婚Hero对话后选择开启Courtship | 仅当对话选项条件开放；写入Romance状态，不直接等于结婚 | Chronicle无Courtship专用动作；B02/I04/J08；目标/兼容性完整门禁见I04 |
| ACT-I04-02 | 行为 | Courtship对话中选择Persuasion argument | 执行一次与当前Persuasion状态匹配的检定并推进/失败Romance阶段；不等于提交婚姻 | Chronicle无求偶说服动作；B02/I04/J09；各argument独立条件/概率仍需逐项映射 |
| ACT-I04-03 | 行为 | 双方同意后向Clan leader提交Marriage Barter并确认 | Barter条款通过后才触发`MarriageAction`、关系/Clan后果；拒绝/Cancel不应计为结婚 | Chronicle无婚姻Barter动作；B02/I04/E10；跨Clan费用、条件、取消后UI恢复未知 |
| OBS-I08-01 | 观察 | 被带到聚落处理犯罪指控时读取当前执法菜单的可用支付/处罚/忽视选项与条件反馈 | GameMenu选项按Faction/地区CrimeModel、金币/Influence余额、严重度和玩家身份动态出现；不由此推断可读取精确CrimeRating数字 | 当前为原版GameMenu条件/选择源码面；Chronicle无当前执法菜单/可用条件快照，金额/拒绝提示视觉未测 | I08/B10、`CrimeCampaignBehavior.AddGameMenus`、`PayForCrimeAction`、L03 |
| ACT-I08-01 | 行为 | 城镇执法菜单选择支付Gold清除Crime Rating | 检查金钱/地区CrimeModel，扣Gold并处理Crime Rating；无钱时选项禁用 | Chronicle未支持；B10/I08；完整降值公式与关系后果待补 |
| ACT-I08-02 | 行为 | 城镇执法菜单选择支付Influence清除Crime Rating | 使用Faction/Clan Influence付款条件和当前Faction crime成本 | Chronicle未支持；B10/I08；实际Influence付款人和精确公式待复核 |
| ACT-I08-03 | 行为 | 城镇执法菜单接受体罚 | 走处罚结算，不等同支付金钱/影响力；伤病/犯罪值后果待核 | Chronicle未支持；B10/I08；来源及精确后果需运行确认 |
| ACT-I08-04 | 行为 | 城镇执法菜单接受体罚并支付Gold | Gold扣费与处罚结算合并，和单独体罚是不同原生选择 | Chronicle未支持；B10/I08；费用公式可源查，视觉回执未知 |
| ACT-I08-05 | 行为 | 城镇执法菜单接受处决 | 导向主角死亡/处置分支，具有终局风险，不等价于普通罚款 | Chronicle未支持；B10/I08；铁人/主角保护/存档后果需运行核实 |
| ACT-I08-06 | 行为 | 城镇执法菜单忽视指控 | 不支付或接受处罚，可能保留Crime/敌对状态并离开裁决；具体后续门禁待核 | Chronicle未支持；B10/I08；实际状态与UI迁移未知 |

上表的B系统映射只覆盖目前可证的玩家端子集。Persuasion argument是否应再按任务/argument类别细分、Crime菜单各处罚是否能通过同一族参数化仍需用原生条件与后果比较，不能由相同屏幕聚类。

### C域初始交叉映射

| 系统ID | 已发现入口/观察族 | 去重与未决 |
| --- | --- | --- |
| C01 KingdomDecision | `OBS-C01-01`未决决策列表；发起决策的ACT需按War/Peace/Policy/Fief/Alliance/Expel等类型拆分 | 决策后统一通过`Kingdom.AddDecision`不代表同一种提案行为；须结合候选与发起者权限 |
| C02 KingdomElection | `OBS-C02-01`候选、Chooser/Supporter、选票/胜率状态；`ACT-C02-01`Supporter态度、`ACT-C02-02`Chooser结果选择 | 角色、权限、费用不同；Decision子类可参数化但其后果需逐类核对 |
| C03 War/Peace | `OBS-B08-01`Faction stance；战争提案`ACT-C03-01`、议和提案`ACT-C03-02` | 地图敌对/开战是其它攻击/Hostile行为的副作用，不另计“DeclareWar按钮”；提案有决策/投票/Influence步骤 |
| C04 Alliance/Call-to-War | `OBS-C04-01`联盟、援战协议、目标/期限；提议Alliance`ACT-C04-01`、对话中向盟友提Call-to-War`ACT-C04-02`，Decision回应复用`ACT-C02-01/ACT-C02-02` | 常驻Alliance、一次援战提案与Chooser响应分开；盟友后续是否接受不由请求动作保证 |
| C05 Policy | `OBS-C05-01`王国当前政策与决策；`ACT-C05-01`提议政策，Decision支持/选择复用`ACT-C02-01/ACT-C02-02` | 政策结果、提出提案与投票支持不能合并 |
| C06 Fief allocation | Settlement/Clan页面观察映射D10/B05/B06；K→Fiefs对其他Clan领地发起Preliminary claim为`ACT-C06-01`，后续投票响应复用`ACT-C02-01/ACT-C02-02` | Proposal、初步Yes/No、正式Claimant选择和最终ChangeOwnerAction是不同阶段；决议回应按C02去重 |
| C07 Clan Kingdom change | `OBS-B04-01/OBS-B06-01`当前Clan/Kingdom身份；`ACT-C07-01`至`ACT-C07-05`区分离境/退位；目标Clan的defection Barter提交`ACT-C07-06`（Persuasion输入复用`ACT-J09-01`）；`ACT-C07-07`开始佣兵、`ACT-C07-08`对话结束佣兵、`ACT-C07-09`宣誓封臣 | 玩家Clan改投与劝说目标Clan归附是方向相反的身份变化；说服attempt和Clan身份提交在不同状态节点，不合成一个动作；K页结束佣兵合同与对话结束合同也不能合并 |
| C08 Kingdom create/destroy | `OBS-C08-01`Story/Kingdom创建任务阶段与Faction状态；`ACT-C08-01`满足模型门槛后与自有聚落Governor创建玩家王国 | StoryMode建国Quest是目标提示，不是第二个建国入口；Kingdom毁灭和AI灭国没有直接玩家按钮，战争/领地行为映射到F/G/C实际动作 |
| C09 Rebellion | `OBS-C09-01`Settlement叛乱状态/通知；叛乱自动由忠诚/民兵等日常模型形成 | 玩家没有“触发叛乱”按钮；观察和参与镇压/攻城分别映射D/F/G，不得创建假动作 |
| C10 Trade/Tribute | `OBS-C10-01`协议/贡金Stance数据；`ACT-C10-01`提议Trade Agreement，决议选择复用`ACT-C02-01/02`；贡金方案映射`ACT-C03-02` | 每日支付和Notice不是玩家动作；历史支付消费者尚未全定位 |

#### C域首轮行动族定义

| ID | 类型 | 玩家入口 / 观察语义 | 原版副作用、权限/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-C01-01 | 观察 | K→Kingdom Decisions查看当前待解决Decision和参与角色 | 列表内容取决于Kingdom、待决项目和玩家是否Chooser/Supporter；打开页面不等于已投票 | Chronicle不读UnresolvedDecisions/候选 | C01/C02、B06、L03 |
| OBS-C02-01 | 观察 | 选中一项选举后查看候选、支持强度/结果预估、可用投票方式 | 决策子类决定玩家是Chooser/Supporter及可选结果；显示机会不是实际结果 | Chronicle不观察Election candidate/choice | C02、KingdomElection、L03 |
| OBS-C04-01 | 观察 | Diplomacy/通知查看当前Alliance、Call-to-War协议目标/期限 | 协议随到期/战争/王国解散终止；通知和协议真值分开 | Chronicle不返回这些条约 | C04/C10、CampaignBehaviors、L06 |
| OBS-C05-01 | 观察 | Kingdom Policies页查看已通过政策/决议状态 | 政策效果由model实际应用，不由名称直接推断 | Chronicle不读policy list | C05、B06/L05 |
| OBS-C08-01 | 观察 | Story Quest/Kingdom状态查看建国进度与已创建身份 | StoryMode跟踪和真实Kingdom实体不同状态 | Chronicle未观察主线阶段/建国资格 | C08、J12、B06 |
| OBS-C09-01 | 观察 | Settlement状态/通知查看叛乱前兆或已叛乱状态 | 忠诚/民兵、Siege与DailyTick共同控制触发；不是“听到新闻”即可得出实时每项公式 | Chronicle无Settlement Rebellion fields | C09、D02/D10、L06 |
| OBS-C10-01 | 观察 | Kingdom diplomacy页查看协议/盟友/贡金 | StanceLink/协议和逐日支付/完成通知属于不同状态 | Chronicle未读取双边协议与贡金余额 | C10、B06/E08/L05 |
| ACT-C02-01 | 行为 | K→已参与Kingdom Election的Supporter选择中立/倾向/支持强度 | 以Decision/候选/支持程度计算Influence费用与投票权重；结果待Election结算 | Chronicle不读/不提交支持；UI源码路径未视觉验证 | C01/C02、B06、L03 |
| ACT-C02-02 | 行为 | K→Chooser角色选择最终候选或弃权/让AI决议 | 通过该Decision合法结果执行Outcome/Secondary Effects；某些Chooser改多数结果另有费用 | Chronicle不支持投票/决策；不同子类Outcome需分别映射 | C01/C02、B06、L03 |
| ACT-C03-01 | 行为 | K→Diplomacy提出Declare War proposal | 创建KingdomDecision/Election而非直接改War Stance；门槛/提案成本依权限模型 | Chronicle不操作决策；源码流程已核，UI未视觉确认 | C01-C03、B06、L03 |
| ACT-C03-02 | 行为 | K→Diplomacy提出Make Peace proposal并提交贡金/时长方案 | 先形成Peace Decision；只有结果通过才执行Neutral Stance及Tribute | Chronicle不操作议和与贡金；日支付不是玩家动作 | C01-C03/C10、E08、B06 |
| ACT-C04-01 | 行为 | K→Diplomacy向非敌对Kingdom提出Alliance proposal | 创建StartAllianceDecision；需通过双方Decision/Barter条件才成为期限协议 | Chronicle不支持Alliance；proposal与Chooser/Supporter响应分开 | C04/C01/C02、B06/L03 |
| ACT-C04-02 | 行为 | 与盟友领主进行Diplomacy对话，选择援战请求、目标敌国并确认费用 | 仅在双方为Kingdom盟友、无冲突未决提案且玩家有足额Gold时开放；调用`StartCallToWarAgreement`发起一次独立协议请求，对方仍须经C02 Kingdom Decision回应 | v1.4.8源码确认条件、重复目标、成本及提案链；Chronicle无此动作，未实机验证对话/时钟/拒绝恢复 | C04/C01-C02/E08、`LordConversationsCampaignBehavior`、`AllianceModel` |
| ACT-C05-01 | 行为 | K→Policies提出增/废Policy提案 | 提案条件/成本通过才进入Election；非直接写Policy集合 | Chronicle不支持Policy提案 | C01/C05、B06/L03 |
| ACT-C06-01 | 行为 | K→Fiefs选择其他Clan拥有的Kingdom Town/Castle，满足条件后点击Annex/Propose并确认 | 仅无未决同城决议时发起；检查玩家地图动作权限、Influence、非Ruling Clan领地及非佣兵身份；调用`SettlementClaimantPreliminaryDecision`。Yes继续建Claimant决议，No不改变Owner；实际易主须之后走C02/正式结果 | v1.4.8源码确认VM入口与handler；Chronicle无提案动作；Campaign决议精确时间/可视确认未运行核实 | C06/C01-C02、B05/B06、D10/L03、`KingdomSettlementVM.ExecuteAnnex`、`SettlementClaimantPreliminaryDecision` |
| ACT-C07-01 | 行为 | 普通Vassal在K→Leave Kingdom，且无Fief | 改Clan Kingdom/关系/阵营状态；需确认菜单合法条件 | Chronicle无身份变更动作 | C07、B05/B06/L03 |
| ACT-C07-02 | 行为 | 有Fief的Vassal选择保留领地并离开 | 可能立即走叛乱离境及与旧王国战争链，区别于归还Fief | Chronicle无身份变更动作 | C07/C09、B05/B06/L03 |
| ACT-C07-03 | 行为 | 有Fief的Vassal选择归还领地再离开 | Clan离境且领地归还；后果不同于保留领地路线 | Chronicle无身份变更动作 | C07/C06、D10/L03 |
| ACT-C07-04 | 行为 | RulingClan Leader在K→Abdicate the Throne | 转移统治权/召集选举；极端Faction条件下可能毁灭王国 | Chronicle无退位动作 | C07/C08、B06/L03 |
| ACT-C07-05 | 行为 | 玩家Mercenary在K页End service | 结束雇佣关系并改变Clan/Kingdom身份 | Chronicle无此动作 | C07、B05/B06/L03 |
| ACT-C07-06 | 行为 | Persuasion成功后，在特殊Clan defection Barter核对条件/条款并接受；敌对/非交战领主与囚犯招降是不同上游入口 | 接受后`JoinKingdomAsClanBarterable(... isDefecting:true)`改变目标Clan所属Kingdom；可协商的Barter条款另按实际选项提交；取消/拒绝不发生Clan改投。前序argument尝试是`ACT-J09-01` | 1.4.8专用Barter初始化/Apply链确认此为身份提交点；普通Lord Barter不是任意加入Kingdom；囚犯入口资格已按王国领袖、目标Clan Leader/囚禁、Faction与ConversationContext及关押位置条件核对；具体界面/可谈条款和取消恢复未视觉运行；Chronicle无动作 | C07/B04/J08/J09/E10、`LordDefectionCampaignBehavior.conversation_leave_faction_barter_consequence`、`conversation_player_start_defection_with_prisoner_on_condition`、`JoinKingdomAsClanBarterable.Apply`、`ChangeKingdomAction` |
| ACT-C07-07 | 行为 | 与异国领主对话“进入其阵营服务”后选择以佣兵身份效力并接受 | 要求目标Faction/战争兼容、Clan Tier/关系/领地等通过`CanPlayerOfferMercenaryService`；调用`ApplyByJoinFactionAsMercenary`并授予5 Influence | 源码确认真实对话句与状态提交；Campaign时间/对话状态语义及玩家视觉流程未运行核实 | C07/B04/J08/E10、`LordConversationsCampaignBehavior`、`FactionHelper` |
| ACT-C07-08 | 行为 | 与同Faction领主对话提出结束佣兵服务并确认 | 需非囚禁且MainParty不在Army；对话路径先清零Clan Influence，再调用`ApplyByLeaveKingdomAsMercenary` | 与K页`ACT-C07-05`使用不同玩家入口；对话路径独有Influence清零，故保持独立；Campaign时间语义未运行核实 | C07/B04/J08、`LordConversationsCampaignBehavior`、`ChangeKingdomAction` |
| ACT-C07-09 | 行为 | 在Lord Conversation提出宣誓效忠、通过条件后完成vassal oath | `CanPlayerOfferVassalage`筛Clan Tier、领袖关系和战争条件；必须向领袖完成授予；可能先结束旧佣兵服务，再`ApplyByJoinToKingdom`并提交入仕奖励 | 源码确认实际玩家选项/提交分支；Campaign时间、拒绝分支及奖励UI/状态结果未运行核实 | C07/B04/J08、`LordConversationsCampaignBehavior`、`FactionHelper` |
| ACT-C08-01 | 行为 | 与玩家所属聚落Governor对话，满足条件后选王国文化、输入名称并确认建国 | Default模型要求Clan独立、Tier≥4、拥有Town/Castle且总计至少100健康驻军/WarParty兵；创建后玩家Clan转入新Kingdom并初始化文化政策/战争关系；StoryMode Quest仅作目标引导 | 当前1.4.8 `GovernorCampaignBehavior`、`SandBoxManager`、Default model和`KingdomManager`源码链已核实；Chronicle无动作，未实机走通条件提示/文化选择/名称取消、时钟与结果恢复 | C08/J12/B06/D09/C03/L03、`GovernorCampaignBehavior`、`DefaultKingdomCreationModel`、`KingdomManager.CreateKingdom` |
| ACT-C10-01 | 行为 | 对非敌对Kingdom提出Trade Agreement proposal | 进入KingdomDecision/Election，并检查权限/Influence | Chronicle不支持 | C10/C01-C02、B06/E08/L03 |
| N/A-C10-01 | N/A | 佣兵玩家收到贸易协定的自动接受分支 | 源码分支自动处理，不是玩家按键/对话行动；一般玩家决议支持仍映射`ACT-C02-01/02` | 不计入ACT分母；Chronicle未观察完整协议状态 | C10、B04/B06/L06 |
| N/A-C08-01 | N/A | AI王国被消灭/玩家看到王国毁灭通知 | 王国消灭是Campaign结算，不存在通用玩家“摧毁王国”按钮；玩家能做的是引发战争/攻城等其它动作 | 不计入ACT分母；相关战争/战斗映射C03/F/G，通知见L06 | C08/C03、B06/L06 |

Decision跨域去重规则：`ACT-C02-01/02`是Decision Election中Supporter/Chooser的共用选择族，Decision子类造成的候选/成本/Outcome差异作为参数与结果记录；战争/议和、Alliance、Policy、Fief claim、Trade agreement的发起入口和核心提交不同，分别保留各自ACT。仲裁条件、费用/结果及单Clan即时结算未知仍留在Research行中，只有发现另一真实玩家入口或独立状态提交点时才扩展ID。`C07-06`已核实为说服目标Clan归附的专用玩家路径，不是泛用Lord Barter。后台自动决议仍以明确N/A或其实际触发玩家行为映射，不计成“触发CampaignEvent”动作。

### D域首轮交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| D01 Settlement基础 | `OBS-D01-01`地图图标/悬停中的可见Settlement信息 | 战斗地图标记与百科/管理面板可见字段不同，入口需分别记录 |
| D02 Town发展 | `OBS-D02-01`Town管理/状态面；建造/日常项目分别`ACT-D05-01/ACT-D06-01` | Prosperity/loyalty等tick结果不单独计作玩家动作 |
| D03 Castle发展 | `OBS-D03-01`Castle管理/防御状态 | 与Town共享部分建筑但村庄绑定/攻城结果不同；重叠UI由参数区分 |
| D04 Village状态 | `OBS-D04-01`村庄产出/绑定Settlement/袭击状态 | 村庄交易/任务/袭击入口分别与E/J/F交叉映射 |
| D05 Building queue | `ACT-D05-01`更改聚落建造队列 | 每日建设自动增长不是玩家动作；所有建筑/权限差异尚需细分 |
| D06 Daily projects | `ACT-D06-01`选择/更换每日项目 | 立即选择和后续日tick效果不同；不能和建筑队列混同 |
| D07 Governor/Garrison | `OBS-D07-01`治理/驻军管理视图；`ACT-D07-01/02`任免Governor和调度驻军 | Garrison PartyScreen转移与其它PartyScreen交易相关但影响对象/权限不同 |
| D08 Crime/Alley | `OBS-D08-01`Alley控制/犯罪状态；进场`ACT-D08-01`、更换Leader`ACT-D08-02`、管Roster`ACT-D08-03`、放弃`ACT-D08-04`、领周招募`ACT-D08-05`、防守帮派进攻`ACT-D08-06`；犯罪处置与B10/I08分开 | 菜单/leader对话的同一Roster/选Hero/放弃后果合并为别名；专用Alley fight任务映射独立D08入口，并跨G03/G09后果核验 |
| D09 Settlement visit | 点击Settlement并抵达映射`ACT-K02-01`；当前Settlement菜单Leave映射`ACT-D09-02`；特定Alley location entry cross-reference `ACT-D08-01` | 抵达菜单是Settlement导航结果，不再与K02地图移动重复计数；等待/对话/Alley入场仍是不同动作 |
| D10 Settlement ownership | 结果观察复用B05/B06/C06、地图/日志通知；改变Owner的来源行动映射C06/F/G | Settlement owner change是结果事件，不另建“地图易主按钮” |

#### D域目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle现状 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-D01-01 | 观察 | Campaign Map查看可见Town/Castle/Village图标、名称与可交互标记 | 范围/悬停字段受玩家可见、侦察、MapEntity类型限制，不代表全图数据库 | Chronicle附近Settlement输出有限摘要；视距/图标详细映射未视觉穷举 | D01、K01、AgentObserver |
| OBS-D02-01 | 观察 | 进入Town后读取菜单/管理面板的建设、民忠、粮食、繁荣、驻军等 | 面板值来自多来源对象/日tick，不由一条“Settlement summary”统一更新时间 | Chronicle能读当前菜单与局部Settlement字段，但无完整Town管理VM | D02/D05-D08、L03 |
| OBS-D03-01 | 观察 | Castle访问/领地管理中的城防、村庄绑定、驻军/工程信息 | Castle特有墙体/被围状态会改变选项，不能与Town菜单字段一一等同 | Chronicle有附近Castle摘要/部分Siege状态，不含完整管理VM | D03、F08、L03 |
| OBS-D04-01 | 观察 | Village列表/地图页面查看绑定Town、产物/村庄状态和生产 | 村庄供应、强征/劫掠/贸易使用不同接口；生产随Campaign tick | Chronicle只限可见Settlements摘要，不展示完整生产链 | D04、E03、F09、L05 |
| OBS-D07-01 | 观察 | 玩家Fief管理面板查看Governor、Garrison、忠诚/安全等 | 任命/军队调度资格受Owner、Hero busy/Party状态与容量控制 | Chronicle不返回Fief管理VM/Garrison详情 | D07、B05、H06 |
| OBS-D08-01 | 观察 | 进入Alley/Clan管理界面查看帮派据点、控制者/收益/防守状态 | 犯罪组织/Alley属独立Clan控制及Settlement子状态，不等于对村庄犯罪评级 | Chronicle不输出Alley当前控制/守卫者状态 | D08、H02、I08 |
| ACT-D09-02 | 行为 | 在当前Settlement GameMenu选择对应Leave选项 | 按Settlement类型/当前State离开Town/Castle/Village回地图；可能触发Incident/事件，不等同点击地图移动 | Chronicle通用menuSelect需以当前Menu/Option ID重验，leave测试为菜单原语 | D09/J05/L03、MAINLINE menu contract |
| ACT-D05-01 | 行为 | Fief管理VM选择/替换一个Building Queue条目并确认 | 消耗建设资源/时间槽，后续Construction由Settlement每日逻辑推进；只有拥有/有资格才可操作 | Chronicle无Building Queue动作；UI权限/确认未运行 | D05/D06、L03 |
| ACT-D06-01 | 行为 | Fief管理VM选择当日项目/自动项目 | 变更聚落日常项目并影响后续日tick；不是立刻完成该项目 | Chronicle无daily project action；Town/Castle允许项矩阵未测 | D06、L03 |
| ACT-D07-01 | 行为 | Fief管理页给当前Settlement任命/移除Governor | 改Hero Governor身份/角色及聚落模型后果；Hero忙碌/囚禁/军团等状态会限制 | Chronicle无Governor assign/remove action | D07、B04/H05-H06、L03 |
| ACT-D07-02 | 行为 | Manage Garrison/PartyScreen在PlayerParty与Settlement Garrison转移成员 | Roster/双方容量/可转移对象决定成败；Done提交，Cancel保留前值 | Chronicle只在有限PartyState/Loot或已实现交易条件下读取Roster，未覆盖一般Garrison UI | D07/F11/H04、L03 |
| ACT-D08-01 | 行为 | 在Town菜单选择“Go to alley”进入玩家已拥有的Alley location | 需当前聚落存在PlayerAlleyData；切换GameMenu并设置Alley location Scene，不直接修改Owner/Roster；该菜单/Scene承载时钟尚未运行核实 | v1.4.8 SandBox `AlleyCampaignBehavior`源码确认Option与SwitchToMenu；Chronicle没有Alley Scene入口 | D08/D09/L03/L07、`AlleyCampaignBehavior.go_to_alley_on_condition/consequence` |
| ACT-D08-02 | 行为 | 在Alley管理菜单或Alley leader对话中选择更换负责人，并从符合条件的Clan Hero里确认新Leader | 攻击期间菜单项禁用；选择由`AlleyModel.GetClanMembersAndAvailabilityDetailsForLeadingAnAlley`筛选；写入AssignedClanMember、替换打手Roster中的Hero并将新Leader延迟传送到聚落 | 两入口调用同一Inquiry与状态Handler；Chronicle无Alley leader动作；玩家对话/时钟运行回执未知 | D08/B04/H02/J08/L03、`AlleyHelper.CreateMultiSelectionInquiryForSelectingClanMemberToAlley`、`ChangeTheLeaderOfAlleyInternal` |
| ACT-D08-03 | 行为 | 从Alley管理菜单或负责人对话打开“Manage Alley”PartyScreen并Done提交守军Roster | 攻击期间禁用；`AlleyHelper`禁止转入Hero/Prisoner并按当前AlleyModel上下限检查普通打手人数；Done更新PlayerAlleyData Roster，Scene内刷新Alley Agents | 两入口使用同一PartyScreen/Done回调；取消边界、双方列表细节和视觉结果未实机核实；Chronicle无Alley roster动作 | D08/F11/H04/L03/L07、`AlleyHelper.OpenScreenForManagingAlley`、`AlleyCampaignBehavior.OnPartyScreenClosed` |
| ACT-D08-04 | 行为 | 在Alley GameMenu确认放弃，或与Alley leader对话确认放弃 | 移除PlayerAlleyData并撤销Alley Owner；普通打手回MainParty roster，UnderAttack时按Alley数据交接/销毁；对话Scene路径额外清理在场Alley Agents | 两入口合并为放弃同一Alley结果；Dialog/Menu的附带Scene清理按上下文记录；Chronicle无动作，完整关系回执/时钟未运行核验 | D08/B09/J08/L03/L07、`PlayerAlleyData.AbandonTheAlley/DestroyAlley`、`AlleyCampaignBehavior.abandon_alley_consequence` |
| ACT-D08-05 | 行为 | 与玩家指定的Alley leader交谈，请求领取当前周可加入主队的Alley Volunteers并确认 | 受 `RandomFloatWeekly`和AlleyModel候选Roster限制；确认后 Troops加入MainParty并更新LastRecruitTime；调用路径不扣Gold；库存量可能为零或暂未开放 | v1.4.8对话行/Party roster handler源码确认；Chronicle无该动作，未实机验证具体刷新/拒绝分支 | D08/E06/H04/J08、`AlleyCampaignBehavior.player_recruited_troops_from_alley`、`DefaultAlleyModel` |
| ACT-D08-06 | 行为 | Player Alley遭帮派袭击时，在manage_alley菜单选择Confront并完成领主对话以守卫据点 | 需当前PlayerAlleyData处于UnderAttack且回应期限未到；对话后调用专用`OpenAlleyFightMission`而非标准MapEvent，结果更新双方Alley Owner/守军 | 源码确认菜单提示、对话和专用Mission路径；Chronicle无Alley Mission动作；实际胜负/撤退、时钟与保有/失去据点的视觉恢复未运行核实 | D08/G01/G03/G09、`AlleyCampaignBehavior.alley_under_attack*`、`CampaignMission.OpenAlleyFightMission` |

D域初步覆盖全部D01-D10系统条目；建设/每日项目以及可视页面/时钟边界仍待补核。D08现已分出Alley场景进入、换Leader、驻守Roster、放弃、周招募和攻击响应六族，其中相同GameMenu/Dialog的同果路径做了别名去重；仍缺玩家运行画面与部分异常恢复证据，故当前分类数不是最终D域行为分母。Town菜单、交易和战斗结果继续交叉引用E/F/C/H/J，不重复创建同一Action ID。

### E域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| E01 Items/商品 | `OBS-E01-01`Inventory容器与市场列表中的具名物品/价格/重量 | Item定义、库存实例、市场状态不同；定义XML不单计玩家观察 |
| E02 Market | `OBS-E02-01`当前Town交易双方库存/报价；买入`ACT-E02-01`、卖出`ACT-E02-02` | 买入和卖出造成的资金/库存/价格改变不同；与Barter分开 |
| E03 Village supply | 村庄资源/绑定城镇状态映射D04/D09，地图可见Villager运输Party复用`OBS-F01-01` | 生产、TradeBound和Villager运输是自动Campaign运行，不是玩家直接“制造货物”动作；摘要不泄露载货状态 |
| E04 Workshop | `OBS-E04-01`Clan工坊清单/Owner/生产状态；购买`ACT-E04-01`、改产`ACT-E04-02`、出售`ACT-E04-03` | 买入、改产、出售为不同交易/所有权结果 |
| E05 Caravan | 地图附近Caravan可见摘要/类型复用`OBS-F01-01`；创建`ACT-E05-01`、改HomeSettlement`ACT-E05-02`、切换禁贸王国`ACT-E05-03` | Caravan只是MobileParty摘要的一种PartyType；Owner/Leader/Home/货物/利润不在该观察面，另有对话/市场行为 |
| E06 Party economics | `OBS-E06-01`主队粮食、工资、负重/roster；补粮映射`ACT-E02-01` | 日工资/食物消耗/逃兵为自动结算，不另建玩家直接“调账”按钮 |
| E07 Clan finance | `OBS-E07-01`Clan财务页的Gold、收入/支出预测/资产说明 | Finance预估与每日实扣分开；已有层级/财产页面映射H02/D域 |
| E08 Kingdom budget | 钱包/协议财务大部分没有确认的玩家直接UI字段；政治信息跨B06/C | 预算注资/分摊为后台模型，不构造“取王国钱”动作 |
| E09 Trade XP/Perk | 交易行为后角色开发页/技能反馈映射`OBS-B03-01` | XP是市场收益动作的后果，不计成单独经验领取动作 |
| E10 Barter | 活跃谈判双方、当前已加入议价盘的Barterables及报价状态共用`OBS-E10-01`；最终提交映射到真实上下文ACT（如婚姻`ACT-I04-03`、Clan defection`ACT-C07-06`、Hero俘虏转交/释放`ACT-F12-01/02`） | BarterVM是独立于Inventory和Conversation option list的观察面；条款编辑属于上下文议价事务，不另造通用`ACT-E10`结果动作，各Barterable的提交后果归其实际领域；候选项全集、完整价值解释和运行展示待核 |

#### E域目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-E01-01 | 观察 | Inventory/Trade屏幕中当前角色与容器的具名ItemObject、数量/价格/重量 | 仅显示当前InventoryMode左右容器，不能从市场视图得知全球库存/村庄在途货物 | Chronicle按需返回Town报价，常驻Party快照只有itemCount | E01/E02、H07/L05 |
| OBS-E02-01 | 观察 | Town `trade`打开InventoryLogic后的当前报价、库存与Gold/容量条件 | 报价由Town MarketData/交易方向/商品/Perk计算；提交后改变市场/双方Roster/Gold | `tradeOptions`可按需读，渲染UI未验证；交易具有限原生接口 | E02、AgentProvisioning、D09/L07 |
| OBS-E04-01 | 观察 | Clan Finance页→工坊资产/收入及工坊Owner/生产状态 | 财务预测与Workshop库存、资本、Daily income分属不同数据 | Observer不列OwnedWorkshop/资本/生产配方 | E04/E07、H02/L05 |
| OBS-E06-01 | 观察 | 主队结构化Party摘要/Party页面查看粮食、FoodChange、Wage、负重/队伍容量/士气 | 数值来源不同，不足以推断完整收入/支出或Troop逐项构成 | Observer输出有限汇总字段，不枚举全部付款人/物品 | E06、H03、F01、AgentObserver |
| OBS-E07-01 | 观察 | L→Clan Income/Finance查看Gold与预测日收支、资产收入 | UI forecast为预览计算，不是已结算每日账单；真实日Tick另按ClanFinanceModel记账 | Observer只有玩家Gold/Clan基础数值，无Income/Expense分项 | E07、H02、AgentObserver |
| OBS-E10-01 | 观察 | 活跃BarterVM中的谈判双方、当前双方已放入的Barterables/数量与报价可接受状态 | 由当前BarterContext及Barterable子类决定候选、估值、兼容关系和最终副作用；读取不等于成交，接受/取消仍走上下文专属ACT | 原版`BarterData`/`BarterVM`为独立谈判界面；Chronicle Observer/Protocol未提供Barter快照或offer调整/接受命令，玩家UI细节与可见数值一致性未运行核验 | E10、I04/C07/C10/F/J、`BarterData`、`BarterManager`、`BarterVM`、`BarterItemVM` |
| ACT-E02-01 | 行为 | Town `trade`中从市场买Item/指定数量并按Done确认 | 检查价格、市场库存、Gold、载重；提交使Player ItemRoster增、Town库存减、Gold扣除 | Chronicle AgentProvisioning/InventoryLogic支持有限商品购买并验收库存/Gold；可视UI未验证 | E01/E02、AgentProvisioning、D09 |
| ACT-E02-02 | 行为 | Town `trade`中从Player Inventory卖Item/指定数量并按Done确认 | 玩家库存减、Town市场和Gold变化；出售方向单价重新计算 | Chronicle有有限出售适配；Modifier/全部Item/特殊模式未全覆盖 | E01/E02、AgentProvisioning |
| ACT-E04-01 | 行为 | Town Center与Workshop owner/merchant notable交谈购买工坊 | 检查Gold、Clan Tier/上限、战争/Owner条件；改Workshop Owner并影响后续财务 | Chronicle无Town 3D交互/Workshop购买 | E04、B05/H02、D09/J08 |
| ACT-E04-02 | 行为 | 与自有工坊经营者交谈切换生产类型 | 可能支付改产成本并改变之后每日输入/产出，不是立即给Gold | Chronicle无改产动作；源码路径存在、未视觉运行 | E04/E02/D09 |
| ACT-E04-03 | 行为 | 通过Notable/Clan经营交互出售Workshop | 转移Owner并结算关联资产/库存；与改产不同 | Chronicle没有Workshop出售动作 | E04/E07、H02/D09 |
| ACT-E05-01 | 行为 | Town Center与商人对话创建Caravan并配置领队/质量 | 支付创建成本；Companion离队成为Leader并创建WarParty/流动资金 | Chronicle无地图3D接近/Caravan创建动作 | E05、H05/F06/J08 |
| ACT-E05-02 | 行为 | 与自有Caravan leader对话，选择可用Kingdom后再选合格Town以改HomeSettlement | 调用`CaravanPartyComponent.ChangeHomeSettlement`；目标须不同于当前Home，Naval caravan要求Town有Port；只设回访Home，不指定逐城路线；handler未见Gold/Influence副作用 | 1.4.8对话源码链已追到最终handler；Chronicle未适配，未运行验证对话时钟、提交/取消视觉路径与重选址时点 | E05/F01/J08、`CaravanConversationsCampaignBehavior`、`CaravanPartyComponent.ChangeHomeSettlement` |
| ACT-E05-03 | 行为 | 与自有Caravan leader对话打开“trade partners”，逐个禁止或恢复一个Kingdom的贸易 | 切换`CaravansCampaignBehavior._prohibitedKingdomsForPlayerCaravans`；Quest使用中的Caravan不能配置；双方战时的对话反馈说明和平后仍维持禁贸；handler未见Gold/Influence副作用 | 1.4.8对话与状态handler源码链已追通；Chronicle未适配，未运行验证对话时钟与菜单视觉/取消路径 | E05/F01/J08、`CaravanConversationsCampaignBehavior`、`CaravansCampaignBehavior` |

E03、E06、E08、E09、E10的大量变化由每日模型、其它玩家动作或跨域Barter驱动，不按Campaign模型调用数计成新玩家动作。市场、Settlement管理与Barter以其实际入口/确认结果为准，不从报价、预估财务或API方法名推断交易已完成。

### F-G域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| F01 MobileParty | `OBS-F01-01`附近可见队伍摘要/玩家队伍状态；玩家视觉核对确认地图可见人数及ALT悬停政治Party兵种详情；移动/追击/停步映射`ACT-K02-01`、`ACT-K02-03`、`ACT-K02-05` | ALT详列证据仅限玩家确认的政治Party，不推广到所有Party；同一Party的对象/AI/roster字段不按每个属性另拆族 |
| F02 Party AI | NPC行动结果在地图/Army/Siege中可观察；内部自主决策记`N/A-F02-01`，玩家影响环境映射至真实战争/军团动作 | `AiPartyThinkBehavior`目标执行属于后台决策；具体可见结果不保证能观察到NPC意图 |
| F03 AI行为类型 | Party概要复用`OBS-F01-01`；`IsInspected`条件下可读行为提示映射`OBS-F03-01` | 原版把部分Default/ShortTerm行为和目标转换为摘要文字，不展示完整计划；用户确认的ALT仅对应政治Party兵种详情，不据此断定行为摘要也由ALT触发；行为tooltip入口仍未视觉核实 |
| F04 Party Think | NPC长期/短期目标评分复用`N/A-F02-01`；影响其条件的玩家动作映射Army/外交/地图行为族 | 不把Think、行为切换或评分模型另计玩家动作；UI是否揭示选择理由未知 |
| F05 Army | `OBS-F05-01`Kingdom Army管理视图；管理己方Army为`ACT-F05-01`、主动解散为`ACT-F05-02` | 调整cohesion/邀请party/取消的提交边界以Army VM事务为准；自动解散与主动解散分开 |
| F06 Clan War Party | 家族Party信息复用`OBS-B05-01`/`OBS-F01-01`；Clan→Parties→Create New Party `ACT-F06-01` | 玩家创建Party由 ClanPartiesVM 提交；NPC War Party自动生成不是玩家按钮；初始PlayerClan Party不自动满编 |
| F07 战争目标 | 地图提示中的部分目标行为文字复用`OBS-F03-01`，军团目标`OBS-F05-01`，围城状态`OBS-F08-01`；AI目标选择/评分原因记`N/A-F07-01` | 原生界面可条件显示部分选定行为/目标，但不显示完整候选、评分或选择理由；无菜单替NPC指定下一目标 |
| F08 Siege | 战略围城状态为`OBS-F08-01`；进入攻城Mission/坐镇/离开按G01遭遇分支和真实Mission动作映射 | Campaign围城周期、围城菜单及攻城Mission是不同状态层，不合并成“攻城”动作 |
| F09 Raid/Defense | 村庄遭遇`ACT-F09-01`劫掠、`ACT-F09-02`强征志愿兵、`ACT-F09-03`强征物资；防守进入G战斗路径 | 三类村庄敌对行动后果不同；AI防守目标不是玩家可指定的直接动作 |
| F10 BattleSimulation | `OBS-F10-01`模拟状态/胜负；坐镇动作映射`ACT-G01-02` | Campaign战斗simulation不等于Mission实时操作；战后伤亡/奖励还映射G09/G10结果观察 |
| F11 troop training/recovery | Party Screen roster观察`OBS-H04-01`；玩家升级`ACT-H04-01`、普通俘虏招募`ACT-H04-02` | 自动NPC升级/治疗/逃兵不是玩家动作；不同PartyScreen上下文仍需交叉去重 |
| F12 prisoners | 俘虏Roster观察`OBS-H04-01`/`OBS-H12-01`；主角赎金菜单`ACT-H12-01/02`；Barter Hero俘虏转交`ACT-F12-01`、以Barter释放`ACT-F12-02`；普通兵招募`ACT-H04-02` | 俘虏所在容器、接收方Faction关系和结果类型不同；战后结果/自动释放不是玩家处置动作；Hero与普通兵俘不可合并 |
| F13 Army decisions | 领主自动组军/加入/解散结果观察`OBS-F05-01`；玩家邀请`ACT-F05-01`/解散`ACT-F05-02` | NPC“意愿”不是独立谈判确认或玩家按钮 |
| G01 Encounter | `OBS-G01-01`遭遇菜单双方/可用选项；Attack `ACT-G01-01`、Send Troops `ACT-G01-02`、escape `ACT-G01-03`、surrender `ACT-G01-04`、join/help/leave `ACT-G01-05` | 接敌、玩家选择、BattleSimulation与Mission入口须分开 |
| G02 MapEvent | 双方Party/参战/战斗持续观察`OBS-G02-01`；真实开始战斗映射遭遇和村庄等发起动作 | 增援/战斗结算是事件过程或结果，不按每个参战Party复制玩家行为 |
| G03 BattleMission | `OBS-G03-01`实际Mission状态；Mission入口复用`ACT-G01-01`；TAB撤退为`ACT-G03-01` | 实时Mission其余3D控制目前是待覆盖范围；Send Troops不是Mission |
| G04 Formation | 编队/部署观察`OBS-G04-01`；Formation composition配置`ACT-G04-01`、Captain指派`ACT-G04-02`、Hero Troop指派`ACT-G04-03`、Auto Deploy`ACT-G04-04`、部署结束`ACT-G04-05`均为独立行为族 | 不按F键/按钮计动作；类别/Filter/Weight是同一Troop分配配置族的不同参数；G08 Siege部署完成路径复用ACT-G04-05 |
| G05 Orders | 当前编队/命令观察`OBS-G04-01`；移动Order`ACT-G05-01`、队形变换`ACT-G05-02`、朝向`ACT-G05-03`、射击模式`ACT-G05-04`、骑乘模式`ACT-G05-05`、AI接管`ACT-G05-06`、Troop Transfer`ACT-G05-07`均已由原版Provider/VM调用链确认 | Order variants按效果/目标字段记录；键盘快捷键别名不重复计数；Hideout Provider与攻城部署另有上下文 |
| G06 Tactics AI | AI执行结果观察复用`OBS-G03-01`/`OBS-G04-01`；战术AI内部选择记`N/A-G06-01` | 战术AI不是玩家可直接选择的菜单动作；玩家显式下令才映射G05 |
| G07 Morale | Mission Order中的玩家Formation平均士气`OBS-G07-01`；坐镇Scoreboard中双方整侧Morale `OBS-G07-02` | 前者来自PlayerTeam formations，后者来自BattleSimulation双方MapEventSide；粒度不能合并；坐镇BattleSimulation优先于Mission Orders接入AI |
| G08 Siege Mission | 实时攻城器械/城门/双方状态观察`OBS-G08-01`；器械点手动配置`ACT-G08-01`、器械/队伍Auto Deploy`ACT-G08-02`由原版VM链确认；战斗Order复用`ACT-G05-01`及G01遭遇分支 | SiegeEvent、器械部署菜单、战术菜单和实时攻城场景分层；部署结束成功转换复用G04 `ACT-G04-05`，攻城未放置器械时多一确认分支 |
| G09 Combat Resolution | 战后伤亡/俘虏/战利品结果复用`OBS-G10-01`；Hero俘虏处置映射F12/H12 | 结算是多个遭遇入口的后果阶段，不是玩家直接“结算”动作；各路径模型差异须保留 |
| G10 Battle Rewards | 领奖结果复用`OBS-G10-01`；经验/声望/影响力/物品均作为触发行为的后果 | 奖励模型不是独立玩家按钮；Simulation夹具不能代替自然战斗奖励证据 |

#### F-G域首轮行动/观察定义

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-F01-01 | 观察 | Map上可见Party显示人数；光标悬停+ALT可查看政治Party兵种/人员构成（玩家视觉核对）；同一观察族包含当前可见MobileParty摘要 | 受地图可见性/侦察状态过滤；ALT详细Roster已确认适用于政治Party，但不外推到所有Party或未可见目标 | Chronicle Observer最多12项摘要，给成员数/估算实力、不列兵种Roster；视觉事实为用户确认、无截图留档，AI信息读取策略仍待设计 | F01/F03/K01、AgentObserver、人类视觉确认（本会话） |
| OBS-F05-01 | 观察 | Kingdom→Armies/Army Management列表查看Army leader/成员/目标/cohesion | 管理权限及Kingdom身份过滤；地图Overlay和Panel有不同字段 | Chronicle没有完整Army/ArmyVM状态 | F05/F13、L03 |
| OBS-F08-01 | 观察 | Siege menu/地图Army overlay观察Camp、Siege、进攻/防守状态 | Campaign siege campaign state不是Mission战场实时状态 | Observer只返回有限Settlement/Encounter信息 | F08/G08、D01、AgentObserver |
| OBS-F10-01 | 观察 | Battle Simulation界面/Native map event的胜负、回合/finish状态 | 模拟推进不等于玩家Mission局部战斗 | Chronicle observer支持Simulation finished/retreated/state字段 | F10/G02、MAINLINE autoresolve |
| OBS-G02-01 | 观察 | Encounter/MapEvent双方与持续战斗状态 | Participants/Side/round/campaign event may have hidden detail; nearby Party entry不等于参战 | Chronicle现有快照不列完整MapEvent parties/contribution | G02/F10/K06、AgentObserver |
| OBS-G03-01 | 观察 | 活跃Battle Mission的主角/队伍/场景/胜负/Agent状态 | 实时Mission与Campaign MapState不同；世界时钟暂停 | Observer当前无完整战术/Agent Mission state；仅missionRetreat查部分状态 | G03/G09、AgentProtocol |
| OBS-G04-01 | 观察 | Deployment/Order UI当前Formation类别、单位、Captain和队形/目标 | 信息随Mission、阶段、选中Formation改变 | Chronicle无Deployment/Formation详情 | G04/G05、AgentObserver |
| OBS-G08-01 | 观察 | Siege Mission攻防方、城门/墙/器械状态 | 场景对象与Campaign siege machine列表是两层 | Chronicle无实时siegeMission物件状态 | G08、AgentObserver |
| ACT-G08-01 | 行为 | 在Siege Mission用地图/Orders界面选择DeploymentPoint，再分配、更换或撤下一个合法Siege weapon | 检查该武器可部署库存后，对当前点调用`Deploy`/`Disband`，改变本次Mission器械放置 | 1.4.8 `ISiegeDeploymentView.OnEntitySelection`到VM/DeploymentPoint handler调用链确认真实玩家选择入口；具体鼠标交互/取消恢复未视觉验证；Chronicle无动作 | G08、`MissionGauntletSingleplayerOrderUIHandler`、`MissionOrderDeploymentControllerVM.OnEntitySelect/OnSelectDeploymentSiegeMachine`、`DeploymentPoint`、`SiegeDeploymentHandler` |
| ACT-G08-02 | 行为 | 在Siege deployment控制面选择Auto Deploy | 重算当前Mission deployment plan，并自动部署可用Siege weapon与攻防Team | 1.4.8 UI handler→VM回调链确认玩家操作；与G04 Formation Auto Deploy对象/结果不同；实际部署结果、撤销恢复和玩家视觉未运行核实；Chronicle无动作 | G04/G08、`MissionGauntletSingleplayerOrderUIHandler.OnAutoDeploy`、`MissionOrderDeploymentControllerVM.ExecuteAutoDeploy`、`IMissionDeploymentPlan`、`SiegeDeploymentHandler` |
| OBS-G10-01 | 观察 | Battle end/Post-battle party/Inventory结果 | 贡献/战斗模型决定XP、Renown/Influence、loot和capture；领奖屏幕与Campaign state提交分开 | Chronicle对Simulation PostBattle有有限结构化验收，不覆盖所有自然Mission | G10/F10、MAINLINE PostBattle |
| ACT-F05-01 | 行为 | K→Kingdom Armies打开ArmyManagement，创建己方Army/选择邀请Party并Done | 检查Kingdom成员/佣兵/Leader与参加Party条件，收取Influence并设置Army/Party关联；Cancel不提交 | Chronicle无Army Management交互 | F05/F13、KingdomArmyVM/ArmyManagementVM |
| ACT-F05-02 | 行为 | Kingdom Army panel/战后上下文主动解散玩家Army | 玩家解散消耗Influence并可能扣参与者关系；自动解散不是同一action | Chronicle无解散Army命令 | F05/F13、DisbandArmyAction |
| ACT-F06-01 | 行为 | Clan Management→Parties→Create New Party，选择符合条件的Clan Hero/Companion并确认费用 | 要有WarParty slot、可带队Hero、允许地图操作、MainParty不在海上/raft，并满足最低Leader资金；可能从MainParty移走该Hero，创建独立PlayerClan MobileParty并补最低资金、停为Hold；不自动复制NPC DefaultPartyTemplate，不能由“创建成功”推断已有完整部队 | v1.4.8 ClanPartiesVM与Prefab源码确认入口/条件/状态变化；Chronicle无动作适配；各Hero位置及正式视觉/运行结果未实测，Clan页面时钟宿主未核 | F06/H02/H05/E06、`ClanPartiesVM`、`ClanPartiesLeftPanel.xml`、`MobilePartyHelper.CreateNewClanMobileParty` |
| ACT-F09-01 | 行为 | 在有效Village encounter选择Raid/Plunder | 进入RaidEvent并造成物资/繁荣/安全与关系等不同后果 | Chronicle无Raid选择动作 | F09/J05、EncounterGameMenuBehavior |
| ACT-F09-02 | 行为 | Village encounter中强征Volunteers | 进入ForceVolunteersEvent，潜在获得部队并触发村庄/政治后果 | Chronicle无强征新兵动作 | F09/J05/G02 |
| ACT-F09-03 | 行为 | Village encounter中强征Supplies | 进入ForceSuppliesEvent，物资获得及Village损害路径不同于Raid/Volunteers | Chronicle无强征物资动作 | F09/J05/G02 |
| ACT-F12-01 | 行为 | 通过有效的领主Barter，在双方Party俘虏条目中把一名Hero列入转移条款并接受 | `TransferPrisonerBarterBehavior`仅在俘虏所属Faction与接收Party交战时加入条款；接受后`TransferPrisonerAction`改变该Hero的囚禁Party；与交易/释放不同 | 本机1.4.8 Barterable请求/Apply源码链确认双向候选与交战复核；需实际可用的Conversation Barter上下文；取消、具体供选与UI时钟未实机核验；Chronicle无Barter适配 | F12/E10/J08、`TransferPrisonerBarterBehavior.CheckForBarters`、`TransferPrisonerBarterable.Apply`、`TransferPrisonerAction` |
| ACT-F12-02 | 行为 | 通过有效的领主Barter，把一名与接收方非交战的Hero prisoner列入Release条款并接受 | `SetPrisonerFreeBarterBehavior`按双方交战状态加入条款；接受后以对方Hero为付款方调用`EndCaptivityAction.ApplyByRansom`；不是MainHero被俘时的Ransom menu | 本机1.4.8 Barterable请求/Apply源码链确认Party prisoners及特定Clan dungeon prisoners候选；场景上下文/视觉、金额呈现与关系结果未运行核验；Chronicle无Barter适配 | F12/E10/J08、`SetPrisonerFreeBarterBehavior.CheckForBarters`、`SetPrisonerFreeBarterable.Apply`、`EndCaptivityAction` |
| ACT-G01-01 | 行为 | 遭遇菜单选择 Attack/Lead an assault等进入实时Mission | 创建对应MapEvent并打开Mission，受类型/装备/围城/兵力条件限制 | Chronicle未实现通用Mission进入/战斗控制 | G01/G03/K06、PlayerEncounter |
| ACT-G01-02 | 行为 | Encounter选择Send Troops/坐镇指挥 | 初始化BattleSimulation并结算Campaign MapEvent；与实时Mission伤亡/交互不同 | Chronicle确定性BattleSimulation可测试，非模型Provider不计自主能力 | G01/F10/G02/K06、MAINLINE BattleSimulation |
| ACT-G01-03 | 行为 | Encounter选择Try to get away/撤离遭遇 | 依据追击/队伍/实力条件进行原生脱离尝试；失败可继续遇战，不等于Mission TAB retreat | Chronicle只处理已启动的战役Simulation retreat；通用逃脱未覆盖 | G01/K06、EncounterGameMenuBehavior |
| ACT-G01-04 | 行为 | Encounter选择Surrender | 触发PlayerSurrender/captivity并改变MainParty/英雄状态，非普通Leave | Chronicle无Surrender动作 | G01/H12/F12/K06、PlayerEncounter |
| ACT-G01-05 | 行为 | JoinEncounter菜单选择帮助攻击/防守一方、放弃Army或离开 | 变更参战方/Army membership或结束Encounter；权限依阵营/Army/当前双方 | Chronicle无支援参战/脱离Army菜单动作 | G01/F13/K06、EncounterGameMenuBehavior |
| ACT-G03-01 | 行为 | Mission的TAB菜单选择Exit/撤退并确认 | `BattleEndLogic.TryExit`返回不同结果；围城守方可能变为SurrenderSiege，不能误报安全撤退 | Chronicle有有限missionRetreat adapter并检查TryExit；未覆盖键盘HUD视觉确认 | G03/G09、BattleEndLogic |

F/G中Mission主角移动/攻击、Formation orders及部署已作为真实玩家行为族进入目录分母；Chronicle目前没有这些3D Mission的Agent动作适配，因此目录行为存在不代表产品已经支持。首个AI战斗接入仍优先用坐镇/BattleSimulation；相同战后/Campaign结果跨域映射到唯一结果观察，按玩家入口与提交点去重。

### H-I域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| H01 Player identity | `OBS-B01-01`身份/百科；新档文化选择映射`ACT-A01-01/02` | Character Creator与Campaign中身份管理是不同上下文 |
| H02 Player Clan | `OBS-B05-01`家族管理面；名称/旗帜操作映射`ACT-H02-01/02` | Gold/财务与E07可见预测共享数据，不重复建Clan finance动作 |
| H03 Main Party | Party/经济汇总映射`OBS-E06-01`与`OBS-F01-01` | Party对象字段和队伍面板字段需按可见细节继续拆分 |
| H04 Troop Roster | `OBS-H04-01`Party roster；升级/俘虏招募暂为`ACT-H04-01/02` | 招募新兵、俘虏招募、自动NPC升级各自不同，后者无玩家入口 |
| H05 Companion | `OBS-H05-01`玩家Clan/Party同伴信息；`ACT-H05-01`游荡者招募 | 战斗加入Party/加入Clan/同伴建Party不是同一动作 |
| H06 Party Roles | `OBS-H06-01`Scout/Surgeon/Quartermaster/Engineer等角色分配状态；`ACT-H06-01`任命Party Role | 军团Captain/Governor/Clan Party Role分别映射F/D/H不同业务 |
| H07 Inventory | `OBS-E01-01`当前Inventory Mode物品列表，交易动作复用`ACT-E02-01/02` | 普通买卖、Battle Loot、囚犯Roster不是同一容器/动作 |
| H08 Equipment | `OBS-H08-01`Hero战斗/民用装备槽；`ACT-H08-01`装备/卸装 | Inventory VM里交易装备与改Hero穿戴是不同State副作用 |
| H09 Crafting | `OBS-H09-01`CraftingVM当前Hero/材料/配方/耐力；`ACT-H09-01..03`锻造/熔炼/炼制 | 三类材料/技能/XP效果不同，不按CraftingVM按钮数合计 |
| H10 Skills/Perks | `OBS-B03-01`成长面板；`ACT-H10-01`已定义点数分配事务 | 战斗/任务/交易/锻造获得经验是各来源行为结果 |
| H11 Renown/Influence | `OBS-H11-01`Clan Tier/Renown/Influence摘要；获取/消费映射F/G/C和E实际行为 | 查询数值与获取声望/影响力、消费影响力是不同族 |
| H12 Player Captivity | `OBS-H12-01`PlayerCaptivity/捕获方/赎金菜单；接受与拒绝offer分别映射`ACT-H12-01/02` | 自动逃脱/交换/战败释放不是玩家action；玩家等待依Campaign时钟 |
| I01 Personal Relation | `OBS-B09-01`上下文中的关系反馈；变化来源映射I/J/F/E实际行为 | 没有统一关系编辑器或全局日志入口 |
| I02 Faction Relation | `OBS-B08-01`阵营敌对/外交状态；政策/宣战/和平等映射C和接敌G | Hero Relation与Faction Stance不同数据族 |
| I03 Prisoner Social State | 俘虏状态映射`OBS-H04-01/OBS-H12-01`；释放/转移/赎金来自F12/J | 不重复创建Release/Take action；按主角/普通Hero/普通Troop区分 |
| I04 Marriage/Romance | Courtship阶段的当前对话选项复用`OBS-J08-01`；开始Courtship/说服/Marriage Barter映射`ACT-I04-01/ACT-I04-02/ACT-I04-03` | Romance阶段通过同一原生Conversation option list观察，不重复建立第二个对话观察ID；NPC每日婚姻算法不是玩家动作 |
| I05 Family/Kinship | `OBS-B02-01`亲属图/百科；家庭产生/婚姻/死亡等结果由A/B/I类实际行为触发 | 无直接修改家族关系菜单 |
| I06 Education | `OBS-I06-01`教育通知与选择面板 | 每个成长年龄选择是玩家可见事项；错过前段会自动随机补选 |
| I07 Traits | `OBS-B10-01`Character Developer Trait展示；行为写入来自其它Action结果 | 玩家通常不能直接编辑Trait |
| I08 Crime/Reputation | 当前执法/指控菜单可见信息映射`OBS-I08-01`；`ACT-I08-01..06`支付/处罚/忽略不同分支 | 不从选项可用性反推玩家能读取精确CrimeRating数值；处罚类型和自动Crime decay分开 |
| I09 Dialogue Relation | 关系反馈映射`OBS-B09-01`；当前Conversation参与者/阶段/开放句复用`OBS-J08-01`，关系专属选择归属于各自行为ID | I09/J08描述同一原生Conversation观察面，不重复建第二个Observation ID；不能把每个string/关系文本条件单独计行为 |
| I10 Persuasion | 当前Task/target/progress/attempt/argument probability观察复用`OBS-J09-01`；argument提交为`ACT-J09-01`，恋爱语境复用`ACT-I04-02` | I10与J09读取同一PersuasionVM/Task观察面，合并一个ID；各Task语境的成功/失败后果仍保留其领域映射 |

#### H-I新增目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-H04-01 | 观察 | PartyScreen查看当前成员/伤员/俘虏Roster及升级/招募控件 | 列表按PartyScreen mode/roster side和容量过滤；UI显示不是全Campaign人口表 | Chronicle常驻只报MainParty总量；战后 PartyState 有有限Roster读取 | H04/F11/H12/I03、PartyVM |
| OBS-H05-01 | 观察 | Clan/Party成员页读取Hero同伴身份/所属Party/可用成员 | 任务/囚禁/领队/忙碌状态会影响能否入队或担任Party职位 | Observer不列完整同伴列表/技能/位置 | H05/B04、AgentObserver |
| OBS-H06-01 | 观察 | Clan管理Party角色区查看每个职责的当前Hero/技能效果 | 角色资格基于Model及目标MobileParty；角色持有人变化后模型效果更新 | Chronicle不报角色Holder ID | H06、ClanRoleItemVM、AgentObserver |
| OBS-H08-01 | 观察 | Inventory/Character Equipment显示Battle与Civilian装备槽/选中Hero | 装备候选受物品用途、装备模式、槽位和Hero资格筛选 | Chronicle无Hero装备槽快照；InventoryItem transaction不是穿戴状态证明 | H08/H07、SPInventoryVM |
| OBS-H09-01 | 观察 | SmithingState显示执行Hero、Stamina、模板/已解锁组件、材料成本/预览 | 当前模式与选中Hero改变可执行Smithing actions | Chronicle无Crafting State/配方观察 | H09/L07、CraftingVM |
| OBS-H11-01 | 观察 | MainParty/Clan状态栏显示Renown、Influence、Tier及下一门槛 | 仅为当前数值，不包含完整来源历史/未决政治支出 | Chronicle identity/economy Snapshot提供有限数值，无变化原因 | H11/B05/AgentObserver |
| OBS-H12-01 | 观察 | MainHero俘虏GameMenu/赎金事件与Captor上下文 | 菜单会根据Captor类型、战争和计时检查分支动态切换 | Observer可见PlayerCaptivity State但没有当前菜单细项/处置报价 | H12/F12/I03、PlayerCaptivity |
| ACT-H12-01 | 行为 | Wilderness/Prison ransom offer菜单选择Accept | 检查当前Ransom Amount/主角金币；扣款后经`EndCaptivityAction.ApplyByRansom`解囚 | Chronicle无Captivity菜单/赎金支付动作；源码路径确认、UI未跑 | H12/F12、PlayerCaptivityCampaignBehavior |
| ACT-H12-02 | 行为 | Ransom offer选择Refuse and wait for a better offer | 不支付本次赎金，接入原生`settlement_wait`并恢复LastTimeControlMode继续时间检查 | Chronicle没有囚禁Wait动作；等待推进依原版当前TimeMode | H12/A02、PlayerCaptivityCampaignBehavior |
| N/A-H12-01 | N/A | Captor败退、盟友支付、时限随机逃脱等自动释放 | Campaign/MapEvent状态触发EndCaptivityAction，无可选择的玩家按钮 | 不计入ACT分母；后果观察映射F12/OBS-H12-01 | H12/F12、PlayerCaptivityCampaignBehavior |
| ACT-H04-01 | 行为 | PartyScreen选兵种可用Upgrade target、支付对应upgrade cost并Done | 消耗兵种升级费用/候选路径及roster变化；取消不提交 | Chronicle有个别招募测试，未提供通用升级动作 | H04/F11/PartyVM |
| ACT-H04-02 | 行为 | PartyScreen从俘虏列表选普通Troop Recruit并确认 | 受是否可招募、忠诚/容量/招募时间/风险模型限制；不是卖俘虏/释放Hero | Chronicle未实现通用Prisoner recruitment | H04/F12/PrisonerRecruitmentModel |
| ACT-H05-01 | 行为 | 与未入Party/未属Player Clan的可雇用Wanderer对话，选择加入Player的company并确认报价 | 通过CompanionLimit与严格`Gold > hiring price`门槛后，先转Gold、再加入Clan与MainParty；报价依Hero装备/等级/Perk模型变化 | v1.4.8源码确认原生Dialogue句、条件和结果Action；Chronicle无此动作；Wanderer出现地点/到达其对话及宿主时间未运行视觉核验 | H05/J08/E10、`LordConversationsCampaignBehavior`、`AddCompanionAction`、`AddHeroToPartyAction`、`DefaultCompanionHiringPriceCalculationModel` |
| ACT-H06-01 | 行为 | Clan Management为MainParty候选成员任命/移除Quartermaster/Scout/Surgeon/Engineer | 按当前Party role条件绑定Hero并改变后续模型效果；Dialog/Data layer另处理Naval roles | Chronicle无role set action；角色候选资格/结果确认未实机 | H06、DefaultClanMemberPartyRoleModel/ClanRoleMemberItemVM |
| ACT-H08-01 | 行为 | Inventory/Equipment槽将适用Item装备或卸下、选择Battle/Civilian mode | InventoryVM检查Hero使用条件/slot/容重；成交/换装分别写Party库存与Hero Equipment | Chronicle交易数据适配不等于当前无损Hero装备动作 | H08、SPInventoryVM/InventoryLogic |
| ACT-H09-01 | 行为 | 在CraftingVM中完成 weapon forging | 需要材料、部件解锁/配方/执行Hero有Stamina；生成武器/XP/Item历史结果 | Chronicle无Forge action | H09、CraftingVM/CraftingCampaignBehavior |
| ACT-H09-02 | 行为 | Smithing Smelting页选择已有Item熔炼并确认 | 消耗装备，产出材料/XP/解锁部件；与Crafting成品结果不同 | Chronicle无Smelt action | H09、SmeltingVM/CraftingCampaignBehavior |
| ACT-H09-03 | 行为 | Smithing Refinement页选择公式/消耗材料并确认 | 付出Energy/材料，依英雄技能Perk产出锻造材料/XP | Chronicle无Refine action | H09、RefinementVM/SmithingModel |

上述H05 companion招募实际Conversation路径、H08装备事务完整确认边界、H12 captivity菜单各结果仍有待核分支。I10 Persuasion观察已与J09同源视图合并；各Task类型的入口/条件/失败恢复仍需逐类确认，不能把“共用PersuasionVM”误报成所有说服行为都已覆盖。


### J-L域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| J01 Issues | `OBS-J01-01`当前Notable/领主Issue提示；Quest接取`ACT-J02-01`；派遣部队的Alternative Solution`ACT-J01-02`、启动Lord Solution`ACT-J01-03`、回应反报价`ACT-J01-04`为不同分支 | 蓝色标记是玩家提供的视觉事实；三种结算入口/副作用不并成通用任务脚本；每种Issue的可用分支仍需逐类盘点 |
| J02 Quests | `OBS-J02-01`任务列表/当前阶段/地图marker；接取/启动`ACT-J02-01` | Quest完成由各Task/真实世界动作达成，不另计“写QuestComplete” |
| J03 Quest Tasks | 移动/交易/对话/战斗步骤映射K/E/I/G已有实际动作ID | TaskBase只是程序对象，具体任务步骤需回到相关原版UI/动作族 |
| J04 Journal | Quest的`JournalLog`记录复用`OBS-J02-01`；Hero历史百科页复用`OBS-A07-01` | JournalLog是Quest状态的回看信息，不等于世界状态或另一独立Journal界面；百科Hero历史是不同LogEntryHistory面 |
| J05 Incident | `OBS-J05-01` MapState当前Incident及条件选项；`ACT-J05-01`选择事件回应 | 每个Incident的Effect/Consequence按具体选项参数读取，不能合并不同事件后果 |
| J06 Rumor | `OBS-J06-01`市场/玩家物品悬停中的异地买卖价格提示 | 同一ItemMenu消费者服务两侧；已有情报、具体物品、时效和价差共同筛选，专长可扩充来源；源码入口已确认，Chronicle尚未适配 |
| J07 Notifications | Campaign Map Notice队列`OBS-J07-01`、QuickInfo瞬时提示`OBS-J07-02`、Scene通知`OBS-J07-03`分别观察 | A07记载LogEntry/百科日志；通知类分属不同存储/时间/宿主，不能与Log或彼此合并 |
| J08 Conversations | `OBS-J08-01`当前Conversation Flow/参与者/选项；`ACT-J08-01`选择当前开放Dialogue option | Relation/Persuasion对话复用I09/I10的真实消费者，不重复文本条目 |
| J09 Persuasion | `OBS-J09-01`当前Persuasion task/进度/风险信息；`ACT-J09-01`提交Persuasion argument | 说服尝试是Conversation option的特殊子族，任务/求偶/政治用相同模型但不同后果 |
| J10 Tournament | `OBS-J10-01`赛事/对手/排行榜；`ACT-J10-01/02`参与或观看 | Join真实Mission与Watch模拟不同；奖励引用G10/H11，不能固定当Renown按钮 |
| J11 Board Games | `OBS-J11-01`对手/棋盘/当前局面；`ACT-J11-01/02`下注开局/棋盘落子 | Tavern dialog下注与Mission中棋盘走子是不同上下文；模型没有Campaign自主控制 |
| J12 Story Mode | `OBS-J12-01`主线阶段/任务提示；Story选择沿J02/J03/J08映射 | Story quest及Sandbox通用任务分开，不能因Story mode存在而计入Sandbox默认行为 |
| K01 World Map | 可见地图对象/附近实体映射`OBS-F01-01/OBS-D01-01`；足迹由`OBS-K03-01` | 地图图标/悬停/ALT/Track是不同信息精度，需保留来源与可见门槛 |
| K02 Navigation | `ACT-K02-01..05`地图移动、目标点移动、追近、Follow modifier、Hold；显式时间控制复用`ACT-A02-01` | move/pursue/hold已有MAINLINE契约；普通点击自然推进，不能重复计隐藏advance |
| K03 Tracking | `OBS-K03-01`已发现Track与技能分级描述 | 未发现的Track不构成Agent可读信息；纪元/追踪技能细项未知 |
| K04 Weather | `OBS-K04-01`地图Atmosphere/雨雪/时节 | 天气生成与环境后果是后台/场景数据，无Weather设置行动 |
| K05 Sea/Port | 当前无直接玩家海航affordance，`N/A-K05-01`按基础1.4.8默认导航模型留证 | 默认PartyNavigationModel无Naval capability；安装/启用模块若替换模型或增加UI，则扩展分母、重新研究该域 |
| K06 Encounter Flow | 遭遇菜单/双方状态映射G01/G02；选项Actions映射G域逐项定义的ACT ID | K地图追近只是接触输入，协商/支援/开战/投降分流至G，不重复一条“Encounter”动作 |
| K07 Hideout | 藏身处地图/Encounter观察映射`OBS-K07-01`；攻/等夜/坐镇映射F/G/J实际行动 | Hideout发现、Campaign Wait和Mission战斗是不同路径 |
| K08 Bandit Density | `OBS-K08-01`可见Bandit Party/Hideout密度线索 | 全图Spawn人口和计时是后台Campaign，玩家无“生成/减少密度”按钮 |
| L01 XML / L02 XSLT | `N/A-L01-01`/`N/A-L02-01`标明无独立玩家动作；实际被加载对象/内容映射到使用它的行为族 | 数据源/转换手段作为证据与版本约束，不能按XML/XSLT文件数计ACT |
| L03 Game Menu/L04 Dialogue | L03菜单与L04对话实际选项映射至所属Issue/Quest/政治/聚落/战斗行为族；通用Menu/Dialogue引擎不另计行为；对话当前项见`OBS-J08-01`/`ACT-J08-01` | 复用相同点击外壳不代表同一原生后果 |
| L05 Encyclopedia/L06 Notifications | 观察面映射A07、B及J的已有OBS ID | 显示页面/通知的技术View不额外算对象动作 |
| L07 Scene/Mission | 场景状态/实时输入映射D/G/J的已有OBS/ACT ID | Scene类型和MissionLogic不是玩家按钮数量 |
| L08 Localization | N/A玩家行动；文本呈现映射相应Menu/Dialogue/通知OBS | 语言字符串本身不改变Campaign状态 |
| L09 Module Loading | N/A战役内玩家动作；Launcher选择模块发生在战役前 | Module存在/排序是产品配置，不计入Campaign动作分母 |
| L10 CampaignBehavior/L11 GameModel | `N/A-L10-01`/`N/A-L11-01`标明没有直接玩家动作；行为/模型输出映射到实际应用规则的ACT/OBS | 事件注册、模型调用数不是行为族 |
| L12 Harmony/BLSE | `N/A-L12-01`标明没有直接游戏动作；仅可能影响外部模块装载/方法执行 | Loader/patch链不计为玩家游戏行为或开发Harness能力 |
| L13 SaveSystem | Save/SaveAs/Load复用`ACT-A05-01..03` | IDataStore/SaveableTypeDefiner是序列化机制，不另计数据字段数量 |

#### J-L域新增行动/观察定义

| ID | 类型 | 玩家入口 / 观察语义 | 原版后果、时间/限制 | Chronicle状态 / 未知 | 来源 |
| --- | --- | --- | --- | --- | --- |
| OBS-J01-01 | 观察 | 聚落Notable/领主上可见的Issue标记/接取提示 | 当前有效Issue与Quest giver/Owner/任务状态决定是否显示 | `talkToIssueOwner`仅限Harness研究流程，跳过真实地图接近/视觉路径 | J01/IssueManager、用户确认蓝色感叹号 |
| ACT-J01-02 | 行为 | 对支持Alternative的Issue，在对话选择替代方案、选定符合条件的Companion，并按需用PartyScreen配置健康部队后确认 | 写入Alternative状态；Companion离开MainParty/变busy，派出Troop延迟返回；Issue子类可配置天数、伤亡、失败风险与奖励；并非所有Issue均支持 | 1.4.8 `IssuesCampaignBehavior` AddDialog/handler与`IssueBase.StartIssueWithAlternativeSolution`确认真实玩家行为；各Issue开放条件/结果、PartyScreen取消回退和视觉流程未全量核验；Chronicle无动作 | J01/J03/F/H、`IssuesCampaignBehavior`、`IssueBase.StartIssueWithAlternativeSolution` |
| ACT-J01-03 | 行为 | 对支持Lord Solution的Issue，在Issue对话检查条件与影响力后选择该方案 | 需Issue自身条件、Issue owner当前聚落属于玩家Clan且Influence余额达到门槛；开始LordSolution状态后可能进入CounterOfferHero对话；余额为门槛，实际扣费取决于后续回应 | 1.4.8 `IssuesCampaignBehavior`玩家选项、clickable condition及`IssueBase.StartIssueWithLordSolution`确认；Issue子类开放类型、视觉门槛提示和无反报价路径未逐类核验；Chronicle无动作 | J01/C/E/I、`IssuesCampaignBehavior.issue_offer_player_accept_lord*`、`IssueBase.StartIssueWithLordSolution` |
| ACT-J01-04 | 行为 | 在Lord Solution第二段Counter Offer对话中选择接受或拒绝 | 拒绝反报价会扣`NeededInfluenceForLordSolution`并走Issue成功/拒绝counter分支；接受会走Betrayal后果且不扣该影响力；若无CounterOfferHero或Issue owner离开Settlement，原版会自动走拒绝counter分支 | 1.4.8通用VM option/callback与`IssueBase.CompleteIssueWithLordSolutionWith*`确认两个互斥结果；实际遇到条件/视觉迁移未运行，各Issue子类后果未穷举；Chronicle无动作 | J01/J08、`IssuesCampaignBehavior.issue_counter_offer_*`、`IssueBase.CompleteIssueWithLordSolutionWith*` |
| OBS-J02-01 | 观察 | Quest Journal/QuestsVM查看当前任务、阶段、期限、目标及对应JournalLog文本/进度 | Quest/QuestTask状态与自由文本JournalLog不同；期限基于Campaign time；日志是该任务回看而非全局Hero历史 | Observer只给当前任务摘要，不列完整JournalLog/隐藏Task目标；A07/J02/J04对同一Quest Journal不重复计数 | A07/J02/J03/J04/L05、`QuestBase`/`JournalLog`/`QuestsVM` |
| ACT-J02-01 | 行为 | 从Issue/Story/NPC提供入口接受并启动一个合法Quest | 依任务内容写Quest state/期限，可能引入Gold/关系/物品前置或失败风险 | Chronicle无通用Quest接取/阶段执行器；每类入口须单独映射 | J01/J02/J03/J12、QuestBase/IssueBase |
| OBS-J05-01 | 观察 | Settlement进出后打开Incident选择界面查看事件/选项 | Incident trigger、cooldown、条件筛选一条事件；Effect列表不等于实际已提交结果 | MAINLINE有Incident modal/state链，仍未所有Incident运行验证 | J05/A02、IncidentsCampaignBehaviour/Incident |
| ACT-J05-01 | 行为 | Incident UI中选择一个条件合法的事件Option并确认/关闭 | 每个Effect和Option Consequence分别调用；可能改变金钱/Party/关系/Settlement状态；直接API跳过VM cleanup | Chronicle对Incident通用流程目前Unsupported/Research；结构化事件返回未全测 | J05/L06、Incident.InvokeOption、MAINLINE |
| OBS-J06-01 | 观察 | Inventory/市场Goods物品悬停详情中的异地买卖地点/记录价格；玩家栏与市场栏为同一观察族的两个入口 | `ItemMenuVM.SetMerchandiseComponentTooltip`按具体ItemObject、未过期记录、异地及价差筛选；来源受城镇访问/每日事件/交易专长影响。读取不改库存/金币，记录随Campaign时间过期；宿主界面时钟待运行核验 | 用户报告商品例子为谷物/贵重品/木材/葡萄酒，确认武器不显示，马匹未核；与本机1.4.8源码Goods筛选相符。Chronicle未适配，Agent未视觉/运行复核；利润/行情颜色另见E09 | J06/E02/E05/E09、`TradeRumorsCampaignBehavior`、`ItemMenuVM`、`SPInventoryVM`；马匹展示、来源/去重边缘未知 |
| OBS-J07-01 | 观察 | Campaign Map Notification/Map Notice队列中的事件、有效期、目标和可点击跳转 | Notice由`CampaignInformationManager`持久保存并由`MapNotificationVM`呈现；过期/对象失效可关闭或跳转失败；不等同LogEntry正文 | Chronicle Observer不读Notice queue/已读/目标点击；各Notice类型筛选及失效后的视觉反馈未实机核验 | A07/J07/L06、`CampaignInformationManager._mapNotices`、`MapNotificationVM` |
| OBS-J07-02 | 观察 | InformationManager QuickInformation/短时消息 | 由LogEntry/事件等消费端即时显示，不作为长期可回看的Notice队列；显示持续时间/宿主状态和持久日志不同 | Chronicle Observer不读取QuickInfo消息/队列；过期时间、被遮挡时是否保留和点击能力未核 | A07/J07/L06、`CampaignInformationManager.NewLogEntryAdded`、`InformationManager.DisplayMessage` |
| OBS-J07-03 | 观察 | Mission/Scene局部通知、提示与可操作反馈 | 依当前Mission/Scene消息消费者显示；不等同Campaign Map Notice或QuickInfo，具体生命周期随Scene/Mission宿主 | Chronicle无Scene notification观察；全部显示入口、关闭/跳转/宿主时间规则未视觉核验 | J07/G03/L06/L07、Scene notification consumers |
| OBS-J08-01 | 观察 | 活跃Conversation的发言人/Flow阶段/当下开放Option，包括由当前Courtship/Romance状态筛选出的开始/重试/Marriage Barter选项 | sentence condition、身份token、Task与关系筛选，不能扫描未开放Option；Romance选项不代表原始Romance数值 | Protocol提供有限Conversation state/option读取；这是J08/I09/I04共享的同一观察面 | I04/J08/I09/L04、ConversationManager/AgentObserver/Protocol、RomanceCampaignBehavior |
| ACT-J08-01 | 行为 | 只选择当前Conversation实际开放且仍然valid的原生对话Option | Consequence可能启动Barter/Quest/Persuasion/Mission或改关系；context变化须重验 | Chronicle `dialogueSelect`仅限当前option列表；不支持全3D谈话接近 | J08/L04、ConversationManager/AgentProtocol |
| OBS-J09-01 | 观察 | 当前PersuasionVM/Task的参与目标、阶段、剩余attempt、可用argument及其成功概率/当前进度 | options/chance依Task类型、Trait/Skill/Relation/difficulty；显示机会不等于最终检定结果 | Chronicle不输出完整PersuasionTask对象；I10/J09为同源信息，不重复计Observation | I10/J09、`PersuasionVM`、`PersuasionTask` |
| ACT-J09-01 | 行为 | 在当前Persuasion task中选择一个真实可用argument | 单次尝试会提交随机/模型概率结果和进度/失败效果；不等于一般`dialogueSelect`不加上下文 | Chronicle没有专用Persuasion观察/回执及重规划 | J09/I10、DefaultPersuasionModel |
| OBS-J10-01 | 观察 | Arena/Tournament菜单或TournamentLeaderboard查看可加入赛事/对手/排名 | 赛事随Town每日模拟生成/结束；观看排名不是参加Mission | Chronicle无Tournament state/list/player visual | J10、TournamentCampaignBehavior/Manager |
| ACT-J10-01 | 行为 | Town Arena选项加入一场Tournament并进入比赛Mission | 进入实时比赛、可获得奖励/排名；Campaign地图时钟在Mission停止 | Chronicle无赛事列表/格斗输入；三维动作未覆盖 | J10/G03、TournamentMissionStarter |
| ACT-J10-02 | 行为 | Arena菜单选择Watch tournament | NPC模拟比赛结算Tournament状态/奖品显示；与玩家参赛不等价 | Chronicle不支持观战/赛事Simulation接口 | J10、TournamentManager |
| OBS-J11-01 | 观察 | Tavern boardgame对手/当前棋盘/先后手/赌注 | 不同棋类有各自棋盘规则与AI难度状态 | Chronicle无BoardGame Mission observe | J11、BoardGameCampaignBehavior/MissionBoardGameLogic |
| ACT-J11-01 | 行为 | Tavern host/lord对话设置赌注/难度/先后并确认开局 | Gold赌注档位与AI难度/对手条件改变；Conversation结束后启动棋局Mission | Chronicle无对话配置/BoardGame Mission入口 | J11、BoardGameCampaignBehavior |
| ACT-J11-02 | 行为 | BoardGame Mission中点选棋盘落子 | 按具体棋类规则更新棋盘与回合；合法棋步/胜负条件由BoardGame类实现 | Chronicle无棋盘格像素/state/actions接口 | J11、BoardGame类/MissionBoardGameLogic |
| OBS-J12-01 | 观察 | Story Mode任务/阶段通知、已完成的教程/主线阶段 | StoryMode阶段状态不同于Sandbox共同Quest集合 | Chronicle仅有限Quest摘要，不读主线StoryModeData | J12、StoryMode/MainStoryLine/StoryMode behaviors |
| N/A-L01-01 | N/A | XML静态对象/内容定义 | XML描述商品、文化、兵种、文本等加载数据；它不是玩家可点击/可执行的独立动作，实际对象交互映射A-K现有ACT/OBS | 排除文件/节点数量；只作为对应原生行为的内容与版本依据 | L01、`Research/L/ContentInterfaceAndModRuntime.md` |
| N/A-L02-01 | N/A | XSLT模块数据覆盖机制 | XSLT在加载期合并/替换数据，不提供战役内玩家操作入口；效果归于使用被覆盖数据的真实行为/观察项 | 排除补丁条目数量；验证数据来源时保留模块/版本上下文 | L02、`Research/L/ContentInterfaceAndModRuntime.md` |
| N/A-L10-01 | N/A | CampaignBehavior注册、事件订阅与生命周期 | 由引擎启动/保存/加载及Campaign事件调度；玩家不能直接调用某个Behavior作为动作 | 排除Behavior/订阅数量；只记录它承载的具体状态效果及其玩家触发入口 | L10、`Research/L/ContentInterfaceAndModRuntime.md` |
| N/A-L11-01 | N/A | GameModel规则公式/评分模型 | 模型由引擎在相关玩法结算时调用，不是可独立执行的玩家动作；结果归于触发/观察该结算的具体ACT/OBS | 排除模型数/方法数，避免把幕后公式当玩家可控行为 | L11、`Research/L/ContentInterfaceAndModRuntime.md` |
| N/A-L12-01 | N/A | Harmony/BLSE补丁与外部加载/调试机制 | 只改变模块装载或代码运行方式，没有战役中玩家交互入口；游戏内结果归属被改变的实际玩法行为 | 排除补丁数/加载器功能；仅作为兼容/证据背景 | L12、`Research/L/ContentInterfaceAndModRuntime.md` |

#### F/G/K跨域补充目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版后果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源 |
| --- | --- | --- | --- | --- | --- |
| OBS-F03-01 | 观察 | 地图MobileParty tooltip在`IsInspected`时呈现当前行为摘要文字 | `GetBehaviorText`按Army长程行为或Default/ShortTerm行为、目标条件组合描述；不是原始AI计划，目标/场景变化可改变文字 | 源码确认tooltip提供该字段；玩家具体悬停/ALT显示条件尚未视觉核实，Chronicle不采集该摘要 | F03/F01、`RefreshMobilePartyTooltip`、`MobileParty.GetBehaviorText`、`PartyBase.UpdateVisibilityAndInspected`；v1.4.8.119303 |
| OBS-G01-01 | 观察 | Map encounter菜单中双方、遭遇类型和当前可用谈判/接战/脱离/投降选项 | 选项由双方Faction、事件类型、装备/兵力、围城及Mission状态筛选；菜单可用项不是已提交战斗结果 | Chronicle未提供通用Encounter菜单观察；各交战类型的选项集合与显示信息未全量验证 | G01/K06、PlayerEncounter、EncounterGameMenuBehavior |
| OBS-G07-01 | 观察 | 战斗中F1等Orders界面的己方Formation士气 | 每个 `OrderTroopItemVM` 用 `BattleMoraleModel.GetAverageMorale(formation)`提供整数Morale；仅 `Mission.Current.PlayerTeam`的formation列表；用户观察到五格呈现，每格约20点 | 用户报告敌军/非己方指挥盟友不可见；Native源将整数绑定到OrderTroopItem，AI可读原始数值；首个战斗接入不要求Mission控制 | G07/G03/G05、`MissionOrderTroopControllerVM`、`OrderTroopItemVM`、Native `OrderTroopItem.xml`、用户观察 |
| OBS-G07-02 | 观察 | BattleSimulation结算面板中攻击方/防守方整侧Morale读数 | `SPScoreboardVM`在Simulation模式约每秒读取双方`MapEventSide.GetSideMorale()`；两边Scoreboard有五段条并提供整数悬停提示；这是Campaign坐镇模拟的侧级值，不是Mission Formation平均值，且不推进Campaign日期 | 本机v1.4.8源码与Native prefab绑定确认；用户记得坐镇页面有整体士气数值；Chronicle协议未返回该读数 | G07/F10、`SPScoreboardVM.CreateSimulation/OnTick`、`SPScoreboardSideVM.GetMoraleHintStr`、Native `SPScoreboard.xml`/`SPScoreboardSideHeader.xml` |
| N/A-F02-01 | N/A | NPC Party AI/Think自动选择和切换地图行为 | AI对NPC队伍自动计算行动，不存在由玩家直接指定“下一项默认行为/思考结果”的统一入口；玩家只能改变其决策环境或通过地图/军团系统交互 | 不计入ACT分母；观察到的结果仍按可见Party、Army、Siege或地图界面分别映射 | F02/F04、AiPartyThinkBehavior、MobilePartyAi、AiMilitaryBehavior |
| N/A-F07-01 | N/A | NPC Party/Army从军事候选中选取战略目标及其内部评分/理由 | 战争状态、聚落归属、战力/距离、军团/围城状态和目标模型形成AI候选；玩家可改变部分环境条件，但没有查看评分或直接替NPC指定目标的通用原版操作 | 不计入ACT分母；玩家可读取的部分结果由地图行为tooltip、军团面板和Siege状态分别观察，不代表全局目标/决策理由可见 | F07/F02/F05/F08、AiMilitaryBehavior、AiPartyThinkBehavior、DefaultTargetScoreCalculatingModel |
| N/A-G06-01 | N/A | Mission战术AI选择目标/阵型行为本身 | 属于部队AI自动计算；玩家通过下令影响其后的执行，不存在直接调用某个AI决策的原版菜单动作 | 不计入ACT分母；玩家Order入口单独映射`ACT-G05-01`，结果按`OBS-G03-01/OBS-G04-01`验证 | G06/G05、OrderController、Mission tactical AI |
| ACT-G04-01 | 行为 | 在Battle Mission的Order of Battle配置Formation类别、兵种Filter和Weight | 共同定义该战斗部署阶段的Troop→Formation分配；类别变动可能清空不兼容设置，Filter/Weight调用OrderController即时重排Mission Agents；不改Campaign Party roster | 源码确认这些参数汇入同一部署分配计划，按配置族计一个行为而非逐字段计数；视觉编辑/重置/完成后配置持久范围未运行核实；Chronicle无动作 | G03/G04、`OrderOfBattleVM`、`OrderOfBattleFormationItemVM`、`OrderController.RearrangeFormationsAccordingToFilters` |
| ACT-G04-02 | 行为 | 在Order of Battle把Hero指派/撤销为Formation Captain | Captain assignment写`Formation.Captain`、Hero Agent所属Formation及Banner关系；非玩家将军上下文还可能选择玩家在本队的角色/Formation | 1.4.8 VM与部署UI绑定链确认独立玩家动作；Captain与Hero Troop效果不同；完整视觉选择/撤销恢复未测试；Chronicle无动作 | G03/G04、`OrderOfBattleVM.OnFormationAcceptCaptain`、`Formation.Captain` |
| ACT-G04-03 | 行为 | 在Order of Battle把Hero加入/移出Formation的Hero Troops | 调整Hero Agent所属Formation并刷新该Formation；不设置Captain/旗帜 | 1.4.8 VM与部署UI绑定链确认独立动作；视觉确认/取消与容量提示未核；Chronicle无动作 | G03/G04、`OrderOfBattleVM.OnFormationAcceptHeroTroops`、`OrderOfBattleFormationItemVM.AddHeroTroop/RemoveHeroTroop` |
| ACT-G04-04 | 行为 | 在Order of Battle选择Auto Deploy formations | 仅玩家将军可执行；Gauntlet callback触发Mission部署回调批量分配Formation/Agent并刷新Captain/Hero分配与troop counts | 1.4.8 VM/UI handler执行链确认，作用是批量自动编组；撤销/重置和非将军提示未视觉/运行核实；Chronicle无动作 | G03/G04、`OrderOfBattleVM.ExecuteAutoDeploy`、`MissionGauntletOrderOfBattleUIHandler` |
| ACT-G04-05 | 行为 | 完成当前Battle Mission部署并继续进入实际战斗；包含野战OOB与Siege deployment结束 | Gauntlet OOB确认经`MissionGauntletSingleplayerOrderUIHandler.OnBeginMission`进入DeploymentController；OOB filter配置提交后，成功路径调用`FinishDeployment`；攻城未放置器械时先询问是否仍要开始 | 1.4.8两个UI路径成功后相同地结束Deployment并进入战斗，按一状态转换族去重；攻城多确认分支；退出/Cancel恢复及实机画面未核；Chronicle无动作 | G03/G04/G08、`MissionGauntletOrderOfBattleUIHandler`、`MissionGauntletSingleplayerOrderUIHandler.OnBeginMission`、`MissionOrderDeploymentControllerVM.ExecuteBeginMission`、`DeploymentHandler.FinishDeployment` |
| ACT-G05-01 | 行为 | 在Mission Orders中对所选Formation下达移动类Order：Move到位置、Follow Me、Charge（可带目标Formation）、Advance、Fall Back、Stop、Retreat | 修改Formation movement Order/目标；Move需世界位置，Follow Me使用Agent目标，部分Mission Provider不提供全部变体 | Native/SandBox provider与OrderSet绑定确认玩家可选项；具体Mission可用条件、目标失效和Agent执行尚未视觉/运行核实；Chronicle无适配 | G03/G05、`VisualOrderFactory`、`DefaultVisualOrderProvider`、`MoveVisualOrder`等 |
| ACT-G05-02 | 行为 | 在Form Order set为所选Formation设置一种队形排列 | 将Formation Arrangement设置为Line/Close/Loose/Circular/Schiltron/V/Column/Scatter之一；各值是同一状态字段的枚举参数 | Native default provider及VM执行链确认玩家动作与八个变体；界面当前可用性依Formation/Mission，Agent队形结果未运行核 | G04/G05、`ArrangementVisualOrder`、`ArrangementOrder` |
| ACT-G05-03 | 行为 | 对所选Formation选择Face Direction并指定位置，或Face Enemy | 写入`LookAtDirection`/`LookAtEnemy`朝向Order；前者需世界位置，后者按敌方方向 | Native default/hideout provider与VM执行链确认两种命令；目标失效提示/实际朝向反馈未核，Chronicle无动作 | G05、`ToggleFacingVisualOrder`、`OrderController` |
| ACT-G05-04 | 行为 | 切换所选Formation的Fire at Will/Hold Fire | 两者写入不同Firing Order状态，改变其后的远程攻击许可；不等于Agent必有弹药/可射目标 | Native provider确认OrderType字段与UI toggle；兵种限制、撤销及实际射击结果未运行核实，Chronicle无动作 | G05/G06、`GenericToggleVisualOrder`、`OrderType.FireAtWill/HoldFire` |
| ACT-G05-05 | 行为 | 对所选Formation切换Mount/Dismount | 写入骑乘模式Order，影响之后Formation Agent骑乘/下马行为；不直接增加/删除坐骑或Party库存 | Native provider确认两个OrderType与UI toggle；可用条件/执行延迟未视觉/运行核实，Chronicle无动作 | G05/G06、`GenericToggleVisualOrder`、`OrderType.Mount/Dismount` |
| ACT-G05-06 | 行为 | 单机Mission中切换Formation AIControl On/Off | 写入Formation AIControl状态，控制由玩家下达Order还是交由AI接管；默认provider只在非Multiplayer提供 | Native provider确认单机UI存在该切换；实际控制交接与执行反馈未运行核实，Chronicle无动作 | G05/G06、`GenericToggleVisualOrder`、`OrderType.AIControlOn/AIControlOff` |
| ACT-G05-07 | 行为 | 在Orders中启动Transfer，选择所选来源Formation、目标Formation与数量后确认 | 确认时调用`SetOrderWithFormationAndNumber(OrderType.Transfer, target, amount)`重新分配Mission Agents；Cancel只关闭Transfer mode，不提交转编 | Native `TransferTroopsVisualOrder`和VM确认/取消调用已确认；来源/目标/数量UI及Agent实际转编反馈未运行核实；Chronicle无动作 | G04/G05、`TransferTroopsVisualOrder`、`MissionOrderVM`、`MissionOrderTroopControllerVM.ExecuteConfirmTransfer/ExecuteCancelTransfer` |
| ACT-K02-01 | 行为 | MapScreen点击Settlement visual请求主队前往；抵达后进入该Settlement的相应GameMenu/Scene条件 | 检查当前PathFace/NavType/访问权限；成功设目标并按地图点击配置自然改变Campaign time；抵达菜单是同一导航命令结果 | Chronicle `move`已有Settlement ID路径/抵达断言；玩家点击和各Settlement实际菜单视觉未全核 | D09/K01/K02、MapScreen、MAINLINE move |
| ACT-K02-02 | 行为 | Campaign Map点击有效NavMesh地形点/空地图位置 | `MapScreen`地形分支→`MapState.ProcessTravel`→导航可达性校验→`SetMoveGoToPoint`；有效点击共用原版time-control点击处理，之后Campaign自然运行 | v1.4.8源码确认真实地图入口/状态转移；Chronicle无自由坐标move动作，NavMesh/鼠标/失败边缘未运行覆盖 | K01/K02、`MapScreen.HandleLeftMouseButtonClick`、`MapState.ProcessTravel`、`NavigationHelper.CanPlayerNavigateToPosition` |
| ACT-K02-03 | 行为 | 普通点击可见/有效移动Party(不按Follow Modifier)下达Engage/Pursue | 主队自动接近；目标丢失/不可达会自然停步或改Hold；点击time mode依用户配置 | Chronicle `pursue`已测自然接敌；不可见丢失时钟/停步边界仍未知 | K01/K02、F01-F04、MAINLINE pursue |
| ACT-K02-04 | 行为 | MapScreen点击可导航Party时按住`MapFollowModifier` | `MobilePartyVisual.OnMapClick(true)`调用`SetMoveEscortParty`；不同于普通点击的`SetMoveEngageParty`。地图点击时钟处理与普通有效点击共用；目标失明/失效后的恢复仍未知 | 原版输入/状态路径由v1.4.8源码确认；Chronicle尚无Follow动作，也无该失效分支运行验证 | K01/K02、`MapScreen.HandleLeftMouseButtonClick`、`MobilePartyVisual.OnMapClick`、`MobileParty.SetMoveEscortParty` |
| ACT-K02-05 | 行为 | MapScreen点击MainParty/玩家队伍Visual停步 | `SetMoveModeHold`清除移动目标，时钟副作用由原版点击时钟配置处理 | Chronicle `hold`已有目标清除断言并映射地图点击时间 | K02、F04、MAINLINE hold contract |
| OBS-K02-01 | 观察 | World map上的主队位置/目标/当前移动状态及路径可达提示 | 路径的整条导航mesh/脚印不等于Observer已见到的地图路线 | Chronicle snapshot有位置/目标/isMoving/MoveMode，不返回导航path节点 | K01/K02、AgentObserver |
| OBS-K03-01 | 观察 | Scouting/MapTrack visual当前已发现足迹的描述信息 | 只对Detected/live/半径内Track有效；信息精度由SkillEffect和Track年龄/距离/尺寸影响 | Chronicle NearbyParty不输出MapTrack | K03、DefaultMapTrackModel/MapTracksCampaignBehavior |
| OBS-K04-01 | 观察 | World Map可见区域的当前雨雪/光照/季节环境与Mission天气 | 天气节点随Campaign周期按地区更新；视觉和战斗效果可能分离 | Chronicle不读天气/Atmosphere字段 | K04、MapWeatherCampaignBehavior/DefaultMapWeatherModel |
| N/A-K05-01 | N/A | Sea/Port/Ship Campaign海航与船只操作 | 基础1.4.8 `DefaultPartyNavigationModel.HasNavalNavigationCapability`返回false且玩家位置导航被限制到Land/NavMesh，因此引擎Ship/PortState/Embark类型不构成当前基础模块集中的可用玩家动作/观察面 | 只对未替换默认导航模型的基础版本排除；有Naval DLC/Mod、Harmony或自定义NavigationModel时必须重开此项并检验新入口，不将安装模块目录误作活动模块清单 | K05、`DefaultPartyNavigationModel`、`NavigationHelper`；当前安装模块无WarSails，实际Active overrides未知 |
| OBS-K07-01 | 观察 | 地图上可见Hideout及其发现/遭遇/Infested线索 | Hideout隐藏/显示与Bandit/Settlement状态分开；队伍不可见不代表消失 | Chronicle无Hideout状态/识别动作 | K07、HideoutCampaignBehavior/HideoutModel |
| OBS-K08-01 | 观察 | 可见Bandit/looter Party、Hideout和可见地区安全现象 | 仅观察到局部地图实体，不能推导全Faction总量/Spawn budget | Chronicle附近Party摘要有视距和12项截断，无全球Bandit计数 | K08/F02、BanditSpawnCampaignBehavior/AgentObserver |

以上J-L动作族仍有大量子类/选项分支未知；目录识别了技术入口与行为种子，但不因此宣称所有XML内容/Quest/Incident/Story分支已穷举。

### 其余类别映射状态

A-L域已有首轮系统到ACT/OBS目录族的交叉映射，但带“候选”标记的观察/动作仍是待证入口，不计入已核实分母。直到每项均映射为有真实入口证据的唯一ACT/OBS族、或以证据判为无直接玩家affordance，并完成重复ID/断链/未知门禁检查前，MAINLINE总分母维持UNKNOWN，Research Gate保持BLOCKED。类别Research段落是证据来源，不是新的分母行；不得因某类别拥有技术分析就推定玩家行为入口已穷举。

## 研究路由

Research 只按系统类别维护事实，不为专题、路线图或阶段重复建档：

| 类别 | 唯一研究文件 |
| --- | --- |
| A | `Research/A/CampaignRuntimeWorldState.md` |
| B | `Research/B/WorldEntitiesIdentity.md` |
| C | `Research/C/PoliticalDiplomacyAndRelationConsumers.md` |
| D | `Research/D/SettlementsAndTerritory.md` |
| E | `Research/E/EconomyAndTrade.md` |
| F | `Research/F/MilitaryPartiesAndCaptivity.md` |
| G | `Research/G/BattleAndTactics.md` |
| H | `Research/H/PlayerPartyAndProgression.md` |
| I | `Research/I/RelationsAndSocialSystems.md` |
| J | `Research/J/TasksEventsAndNarrative.md` |
| K | `Research/K/MapMovementAndEnvironment.md` |
| L | `Research/L/ContentInterfaceAndModRuntime.md` |
| Agent Bridge | `Focus/MAINLINE.md` |

尚未研究的类别不预建空文档。W1首次开始某类别研究且该类别没有Research文件时，在实际研究过程中创建唯一的非空类别文档，并同步更新本表与 `ContextState.json` 路由；这是该域的内容交付，不另立流程事项。拆分已有类别文档才需用户明确批准。

## 开发期验证工具（不计入游戏系统清单）

本机测试夹具、Harness、视频采集、日志与自动断言是开发基础设施，由 `DEVELOPMENT.md` 管理，不作为玩家游戏系统或W1行为分母，也不单独列为GitHub产品任务。将来若产品需要给玩家使用的诊断/遥测界面，再按实际游戏入口与作用研究其玩家价值。

## 研究模板

1. 原版状态对象与生命周期；
2. 输入、计算、输出和事件；
3. 与其他系统的连接点；
4. 玩家可观察结果；
5. 本机代码/API 证据和适用版本；
6. 当前未知项。

评价、候选方案和路线图不属于 Research。共同确认的方案只进入 `DESIGN.md`。

当前上下文不由本清单决定。每次任务先读取 `ContextState.json`，再由 `Get-ContextPack.ps1` 按标签加载目标研究；完成或切换主线时更新 `Focus/MAINLINE.md`，旧主线默认删除或显式归档。
