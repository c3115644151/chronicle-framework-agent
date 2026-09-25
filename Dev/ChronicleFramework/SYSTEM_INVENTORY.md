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
| ACT-A01-01 | 行为 | 初始菜单→Sandbox新战役 | 建立普通Campaign后进入角色创建；没有既有Campaign时间 | Harness能创建新Campaign，但不通过初始菜单点击端到端验证；新档创建夹具已结构化验证 | A01、L09；`Research/A/CampaignRuntimeWorldState.md` |
| ACT-A01-02 | 行为 | 初始菜单→Story Mode新战役 | 建立`CampaignStoryMode`并进入StoryMode专属开局 | Chronicle未操控StoryMode菜单/主线初始化 | A01、J12、L09 |
| ACT-A01-03 | 行为 | 初始菜单→Continue latest，或已存档游戏→选择slot→Load | 两入口最终均读取一个Campaign存档且跳过角色创建；默认slot选择与手动slot选择作为参数变体保留 | Protocol可指定存档并新进程加载；菜单自身未视觉/自动点击验证 | A01、A05、L13 |
| ACT-A02-01 | 行为 | 地图底部Pause/Normal/Fast-forward时间控件 | 修改`CampaignTimeControlMode`；世界是否实际推进还受MapState、等待、Mission等上下文限制 | Observer读当前timeControlMode；Protocol可暂停/恢复/独立推进，显式`advance`仅Harness用 | A02、K02；MAINLINE原版机制契约 |
| ACT-A05-01 | 行为 | 地图ESC/F5 QuickSave | 排队快速保存；只有保存完成回执后结果成立，F5与ESC别名最终落同入口 | Protocol `save`完成存档往返；没有ESC/F5真实输入测试 | A05、L13；MAINLINE Save验收 |
| ACT-A05-02 | 行为 | Save As→新建slot或覆盖→确认 | 选择名称/覆盖后排队保存；错误/取消不得误报完成 | Protocol使用唯一测试名SaveAs，UI确认流程未验证 | A05、L13 |
| ACT-A06-01 | 行为 | 新战役Character Creation→Options/Difficulty | 选择初始难度/战役选项影响新Campaign初态 | Chronicle不适配角色创建选项控件；自动夹具会跳过/选择预设，不代表模型能力 | A01、A06、H01、L09 |
| ACT-A06-02 | 行为 | Campaign Options界面更改当前存档选项 | 选项由Provider/身份/周期条件启用；会写入Campaign配置或触发模式变化 | Chronicle不观察/不操作Campaign Options VM；逐项门槛未在L域展开 | A06、L03/L08 |
| ACT-A08-01 | 行为 | 新战役开场动画按ESC跳过 | 结束视频播放并进入创建阶段；不应反复空等数分钟 | Harness FreshCampaign设跳过路径；ESC具体 handler 未定位，用户视觉确认可跳 | A01、A08；FreshCampaign验收 |
| OBS-A02-01 | 观察 | 地图时间/日期/速度档 | HUD显示Campaign时钟与当前时间控制档；Mission暂停和战役快进分开 | Observer输出campaignDay/timeControlMode；UI图标/标题尚未实机对照 | A02、L06；MAINLINE |
| OBS-A07-01 | 观察 | Encyclopedia(Hero history)/日志 | 从全局历史条目按页面可见条件筛出角色历史；不等于实时全世界快照 | Chronicle不输出LogEntryHistory或百科历史列表 | A07、L05；用户确认N百科入口 |
| OBS-A07-02 | 观察 | Quest Journal/`JournalLog` | 按当前任务/日志状态显示文本、时间/进度；不是Hero永久历史 | Chronicle未提供完整Quest日志列表/筛选 | A07、J04、L05 |
| OBS-A07-03 | 观察 | Map Notification/QuickInfo | 事件通知、短提示和持久日志分属不同数据/交互 | Chronicle没有Notification队列/已读状态观察 | A07、J07、L06 |
| OBS-A08-01 | 观察 | Tutorial提示 | 按Campaign类型/行为状态显示并可完成/关闭；StoryMode提示与Sandbox提示源不同 | Chronicle不读教程提示/完成状态 | A08、J12、L06 |
| OBS-A08-02 | 观察 | Concept百科页 | 按概念分类/页面显示帮助文本与链接；N百科入口UI细节以实测为准 | Chronicle不读Concept数据或页面当前项 | A08、L05、用户确认N百科入口 |

A06预设/设置页目前只定位到界面族；每个选项的写入字段、条件与后续模型结果可能不同，候选设置操作不计入最终动作分母，待按原生Option ID逐项拆分。A03/A04目前映射为系统后台回调而非玩家直接动作；若某个具体事件存在手动玩家入口，应映射到发起该状态变化的ACT，而不是另造一个“触发CampaignEvent”动作。

| 内部系统 / N/A候选 | 分类理由 | 映射来源 / 仍需排除的直接玩家入口 |
| --- | --- | --- |
| A03 周期事件、A04 CampaignEvent总线 | 这些是玩家动作/观察触发后的引擎调度与回调，不直接由玩家按“触发事件”调用；实际消费后果连接到对应行为/观察族 | `Research/A/CampaignRuntimeWorldState.md`；仍要检查是否存在有直接按钮语义的专属事件子系统，并映射到实际ACT ID |

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
| B10 Trait/Crime | `OBS-B10-01` Character Developer特征展示；Faction犯罪赎罪选项另映射I08动作 | B10/I07/I08/L；Trait和Crime Rating是不同观察面/状态族 |

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
| OBS-B08-01 | 观察 | Kingdom外交页面或地图附近Party Hostile摘要 | Stance是Faction对关系，不是Hero personal Relation；地图摘要仅回答敌对 | Chronicle只给附近Party Hostile；B08/C03/L05；全Faction/联盟历史未接入 |
| OBS-B09-01 | 观察 | 对当前对话Hero显示/推导出的相处状态、称呼或选项提示 | 关系可能经过有效关系模型/身份映射，不等于原始整数或完整历史 | Chronicle不输出Hero relation；B09/I01/J08；是否给出数值取决于具体UI/页面 |
| OBS-I06-01 | 观察 | EducationMapNotification→EducationState课程页面 | 显示玩家子女待选年龄阶段/教育选项；逾期阶段可能先自动随机处理 | Chronicle不读取教育状态/选项；I06/H02/A08；通知打开/关闭与时钟需视觉复核 |
| OBS-B10-01 | 观察 | Character Developer的Trait条目；Crime Rating在相关Faction/执法上下文中触发的提示 | Trait与Faction Crime Rating是不同对象，不把Trait文字当Crime值 | Chronicle均不提供；B10/I07/I08；Crime专属面板与显示范围未验证 |
| ACT-H10-01 | 行为 | C→Character Developer调整适用Hero的Skill Focus/Attribute/Perk后Done；Cancel撤销暂改 | 消耗未用成长点/要求Perk条件；Done才提交，Cancel不改变Hero成长 | Chronicle未实现；B03/H10/L05；子VM逐项前置未全测 |
| ACT-H02-01 | 行为 | L→Clan Management改Clan名称并确认 | 写入名称、触发页面/展示刷新；取消不提交 | Chronicle未实现；B05/H02/L05；当前身份/命名校验待视觉验证 |
| ACT-H02-02 | 行为 | L→Clan Management打开Banner Editor并确认 | 写入Clan Banner；不是单纯展示/百科编辑 | Chronicle未实现；B05/H02/L05；每种画面/确认取消未视觉验证 |
| ACT-I04-01 | 行为 | 与可结婚Hero对话后选择开启Courtship | 仅当对话选项条件开放；写入Romance状态，不直接等于结婚 | Chronicle无Courtship专用动作；B02/I04/J08；目标/兼容性完整门禁见I04 |
| ACT-I04-02 | 行为 | Courtship对话中选择Persuasion argument | 执行一次与当前Persuasion状态匹配的检定并推进/失败Romance阶段；不等于提交婚姻 | Chronicle无求偶说服动作；B02/I04/J09；各argument独立条件/概率仍需逐项映射 |
| ACT-I04-03 | 行为 | 双方同意后向Clan leader提交Marriage Barter并确认 | Barter条款通过后才触发`MarriageAction`、关系/Clan后果；拒绝/Cancel不应计为结婚 | Chronicle无婚姻Barter动作；B02/I04/E10；跨Clan费用、条件、取消后UI恢复未知 |
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
| C04 Alliance/Call-to-War | `OBS-C04-01`联盟、援战协议、目标/期限；提议Alliance`ACT-C04-01`、援战提案候选`ACT-C04-02`，Decision回应复用`ACT-C02-01/ACT-C02-02` | 持续Alliance、援战提案和Chooser响应分开；Call-to-War发起UI尚未定位 |
| C05 Policy | `OBS-C05-01`王国当前政策与决策；`ACT-C05-01`提议政策，Decision支持/选择复用`ACT-C02-01/ACT-C02-02` | 政策结果、提出提案与投票支持不能合并 |
| C06 Fief allocation | Settlement/Clan页面观察映射D10/B05/B06；Claimant主张`ACT-C06-01`为候选，Decision选择复用`ACT-C02-01/ACT-C02-02` | Preliminary与Final claimant Decision分阶段，不能与最终ChangeOwnerAction重复计数 |
| C07 Clan Kingdom change | `OBS-B04-01/OBS-B06-01`当前Clan/Kingdom身份；`ACT-C07-01`至`ACT-C07-05`区分离开封臣/退位/佣兵；Barter候选`ACT-C07-06/ACT-C07-07` | 同一Kingdom页面按身份/领地状态切换后果，不能合成通用leave；Barter玩家入口未知 |
| C08 Kingdom create/destroy | `OBS-C08-01`Story/Kingdom创建任务阶段与Faction状态；`ACT-C08-01`在门槛满足后创建玩家王国 | 玩家创建有叙事/聚落/兵力等条件；Kingdom毁灭和AI灭国没有直接玩家按钮，战争/领地行为映射到F/G/C实际动作 |
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
| ACT-C04-02 | 候选行为 | 通过Alliance/Diplomacy流程向盟国提出Call-to-War请求 | 被接受可产生援战协议、费用和目标Kingdom开战链；玩家主动发起入口尚未定位 | 暂不计入最终分母，待核真实入口、前置/费用和失败/撤回提示 | C04/C01-C02、E08；Model/Decision源码有定义，UI调用未追通 |
| ACT-C05-01 | 行为 | K→Policies提出增/废Policy提案 | 提案条件/成本通过才进入Election；非直接写Policy集合 | Chronicle不支持Policy提案 | C01/C05、B06/L03 |
| ACT-C06-01 | 候选行为 | Settlement Claimant Preliminary/Claimant流程中提出候选主张 | 受Settlement、Clan/Hero身份与决策阶段限制；Preliminary与Final Claimant不是同一个菜单结果 | Chronicle无领地决策动作；暂不计入最终分母，待确认该Proposal是否有真实玩家入口及具体Supporter/Chooser调用 | C06/C01-C02、B05/B06、D10/L03 |
| ACT-C07-01 | 行为 | 普通Vassal在K→Leave Kingdom，且无Fief | 改Clan Kingdom/关系/阵营状态；需确认菜单合法条件 | Chronicle无身份变更动作 | C07、B05/B06/L03 |
| ACT-C07-02 | 行为 | 有Fief的Vassal选择保留领地并离开 | 可能立即走叛乱离境及与旧王国战争链，区别于归还Fief | Chronicle无身份变更动作 | C07/C09、B05/B06/L03 |
| ACT-C07-03 | 行为 | 有Fief的Vassal选择归还领地再离开 | Clan离境且领地归还；后果不同于保留领地路线 | Chronicle无身份变更动作 | C07/C06、D10/L03 |
| ACT-C07-04 | 行为 | RulingClan Leader在K→Abdicate the Throne | 转移统治权/召集选举；极端Faction条件下可能毁灭王国 | Chronicle无退位动作 | C07/C08、B06/L03 |
| ACT-C07-05 | 行为 | 玩家Mercenary在K页End service | 结束雇佣关系并改变Clan/Kingdom身份 | Chronicle无此动作 | C07、B05/B06/L03 |
| ACT-C07-06 | 候选行为 | 与其它Clan/Kingdom通过Barter改变封臣身份 | Barter成功后ChangeKingdomAction处理Clan/领地/战争后果；玩家主动Offer入口未从对话库定位 | 暂不计入最终分母，待确认玩家能否主动触发、权限条件与失败提示 | C07/C01、E10/B04；Barterable模型/Apply已找到，对话调用方未追完 |
| ACT-C07-07 | 候选行为 | 与Kingdom谈判开始/结束Mercenary service | Mercenary Barterable与Vassal转换分离；实际玩家Offer/回应入口及确认路径需进一步核实 | 暂不计入最终分母，待完成Conversation/Barter UI调用链 | C07/C01、E10/B04；Barterable模型已找到，玩家入口未知 |
| ACT-C08-01 | 候选行为 | 满足建国条件后从Sandbox或Story Mode入口创建Player Kingdom | 创建Faction、转换Founder Clan、初始化政策/战争关系；入口/条件是否在两种Campaign中一致未确认 | Chronicle没有建国流程；暂不计入最终分母，等待通用Sandbox入口与Story quest入口分支核验 | C08/J12、B06/D09/C03、L03 |
| ACT-C10-01 | 行为 | 对非敌对Kingdom提出Trade Agreement proposal | 进入KingdomDecision/Election，并检查权限/Influence | Chronicle不支持 | C10/C01-C02、B06/E08/L03 |
| N/A-C10-01 | N/A | 佣兵玩家收到贸易协定的自动接受分支 | 源码分支自动处理，不是玩家按键/对话行动；一般玩家决议支持仍映射`ACT-C02-01/02` | 不计入ACT分母；Chronicle未观察完整协议状态 | C10、B04/B06/L06 |
| N/A-C08-01 | N/A | AI王国被消灭/玩家看到王国毁灭通知 | 王国消灭是Campaign结算，不存在通用玩家“摧毁王国”按钮；玩家能做的是引发战争/攻城等其它动作 | 不计入ACT分母；相关战争/战斗映射C03/F/G，通知见L06 | C08/C03、B06/L06 |

上述ACT行含部分“决策族候选”：C02/C03/C05/C06仍需通过每种Decision的Chooser/Supporter/Barter/Result差异进一步判定是否拆分。表里已将N/A自动系统留在观察或真实导致它的玩家动作映射，不把后台CampaignEvent计入玩家行动族。未知/候选项不计入最终分母。

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
| D08 Crime/Alley | `OBS-D08-01`Alley控制/犯罪状态；行动与B10/I08 Crime Rating区分 | Clan/Alley运营不是逐个雇佣/战斗按钮的合并入口；地下犯罪内容需核模块 |
| D09 Settlement visit | `ACT-D09-01/02`地图进入Settlement、菜单离开Settlement | 等待/访问/对话/入场Scene是不同动作；Menu列数不等于行为族数 |
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
| ACT-D09-01 | 行为 | 在地图点击Settlement视觉实体并抵达 | `OnMapClick`设导航目标；路途自然推进Campaign，抵达后进入相应Settlement menu/Scene条件 | Chronicle `move`支持目标Settlement与抵达断言；具体菜单 UI未全视觉 | D09/K02、MAINLINE move contract |
| ACT-D09-02 | 行为 | 在当前Settlement GameMenu选择对应Leave选项 | 按Settlement类型/当前State离开Town/Castle/Village回地图；可能触发Incident/事件，不等同点击地图移动 | Chronicle通用menuSelect需以当前Menu/Option ID重验，leave测试为菜单原语 | D09/J05/L03、MAINLINE menu contract |
| ACT-D05-01 | 行为 | Fief管理VM选择/替换一个Building Queue条目并确认 | 消耗建设资源/时间槽，后续Construction由Settlement每日逻辑推进；只有拥有/有资格才可操作 | Chronicle无Building Queue动作；UI权限/确认未运行 | D05/D06、L03 |
| ACT-D06-01 | 行为 | Fief管理VM选择当日项目/自动项目 | 变更聚落日常项目并影响后续日tick；不是立刻完成该项目 | Chronicle无daily project action；Town/Castle允许项矩阵未测 | D06、L03 |
| ACT-D07-01 | 行为 | Fief管理页给当前Settlement任命/移除Governor | 改Hero Governor身份/角色及聚落模型后果；Hero忙碌/囚禁/军团等状态会限制 | Chronicle无Governor assign/remove action | D07、B04/H05-H06、L03 |
| ACT-D07-02 | 行为 | Manage Garrison/PartyScreen在PlayerParty与Settlement Garrison转移成员 | Roster/双方容量/可转移对象决定成败；Done提交，Cancel保留前值 | Chronicle只在有限PartyState/Loot或已实现交易条件下读取Roster，未覆盖一般Garrison UI | D07/F11/H04、L03 |
| ACT-D08-01 | 候选行为 | Clan/Alley管理中改变Alley投资/扩张/守卫 | 相关金额/角色/帮派控制与战斗风险需按各Option分开；不能从Faction Crime Rating推导 | Chronicle无Alley动作；当前玩家真实入口和每Option效果需视觉/源码逐项映射 | D08/H02/I08、L03 |

D域当前初步覆盖全部D01-D10系统条目；建设/每日项目、州内可视页面和Alley候选行为仍有未展开子族，尚不能把这些行数当最终D域动作分母。Town菜单、Army管理、交易与战斗路径交叉引用E/F/C/H/J，而不是重复创建同一Action ID。

### E域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| E01 Items/商品 | `OBS-E01-01`Inventory容器与市场列表中的具名物品/价格/重量 | Item定义、库存实例、市场状态不同；定义XML不单计玩家观察 |
| E02 Market | `OBS-E02-01`当前Town交易双方库存/报价；买入`ACT-E02-01`、卖出`ACT-E02-02` | 买入和卖出造成的资金/库存/价格改变不同；与Barter分开 |
| E03 Village supply | 村庄资源/绑定城镇状态映射D04/D09，贸易运输见`OBS-E05-01` | 生产、TradeBound和Villager运输是自动Campaign运行，不是玩家直接“制造货物”动作 |
| E04 Workshop | `OBS-E04-01`Clan工坊清单/Owner/生产状态；购买`ACT-E04-01`、改产`ACT-E04-02`、出售`ACT-E04-03` | 买入、改产、出售为不同交易/所有权结果 |
| E05 Caravan | `OBS-E05-01`附近Caravan摘要/主人与贸易路径（常驻快照缺失细项）；创建`ACT-E05-01`、设置偏好候选`ACT-E05-02` | NPC Caravan日常跑商与玩家创建/对话配置不是同一动作 |
| E06 Party economics | `OBS-E06-01`主队粮食、工资、负重/roster；补粮映射`ACT-E02-01` | 日工资/食物消耗/逃兵为自动结算，不另建玩家直接“调账”按钮 |
| E07 Clan finance | `OBS-E07-01`Clan财务页的Gold、收入/支出预测/资产说明 | Finance预估与每日实扣分开；已有层级/财产页面映射H02/D域 |
| E08 Kingdom budget | 钱包/协议财务大部分没有确认的玩家直接UI字段；政治信息跨B06/C | 预算注资/分摊为后台模型，不构造“取王国钱”动作 |
| E09 Trade XP/Perk | 交易行为后角色开发页/技能反馈映射`OBS-B03-01` | XP是市场收益动作的后果，不计成单独经验领取动作 |
| E10 Barter | 婚姻/政治/俘虏/商旅议价按I04/C/F各上下文映射 | 各上下文使用不同Barterable/结果模型，避免复制专属ACT |

#### E域目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-E01-01 | 观察 | Inventory/Trade屏幕中当前角色与容器的具名ItemObject、数量/价格/重量 | 仅显示当前InventoryMode左右容器，不能从市场视图得知全球库存/村庄在途货物 | Chronicle按需返回Town报价，常驻Party快照只有itemCount | E01/E02、H07/L05 |
| OBS-E02-01 | 观察 | Town `trade`打开InventoryLogic后的当前报价、库存与Gold/容量条件 | 报价由Town MarketData/交易方向/商品/Perk计算；提交后改变市场/双方Roster/Gold | `tradeOptions`可按需读，渲染UI未验证；交易具有限原生接口 | E02、AgentProvisioning、D09/L07 |
| OBS-E04-01 | 观察 | Clan Finance页→工坊资产/收入及工坊Owner/生产状态 | 财务预测与Workshop库存、资本、Daily income分属不同数据 | Observer不列OwnedWorkshop/资本/生产配方 | E04/E07、H02/L05 |
| OBS-E05-01 | 观察 | 地图附近可见Caravan图标及有限Party摘要 | Owner/Leader/Home/TradeBound/货物/PartyTradeGold通常不在NearbyParty摘要中 | Observer只给附近Party摘要，不给商队货载/利润 | E05、F01、AgentObserver/K03 |
| OBS-E06-01 | 观察 | 主队结构化Party摘要/Party页面查看粮食、FoodChange、Wage、负重/队伍容量/士气 | 数值来源不同，不足以推断完整收入/支出或Troop逐项构成 | Observer输出有限汇总字段，不枚举全部付款人/物品 | E06、H03、F01、AgentObserver |
| OBS-E07-01 | 观察 | L→Clan Income/Finance查看Gold与预测日收支、资产收入 | UI forecast为预览计算，不是已结算每日账单；真实日Tick另按ClanFinanceModel记账 | Observer只有玩家Gold/Clan基础数值，无Income/Expense分项 | E07、H02、AgentObserver |
| ACT-E02-01 | 行为 | Town `trade`中从市场买Item/指定数量并按Done确认 | 检查价格、市场库存、Gold、载重；提交使Player ItemRoster增、Town库存减、Gold扣除 | Chronicle AgentProvisioning/InventoryLogic支持有限商品购买并验收库存/Gold；可视UI未验证 | E01/E02、AgentProvisioning、D09 |
| ACT-E02-02 | 行为 | Town `trade`中从Player Inventory卖Item/指定数量并按Done确认 | 玩家库存减、Town市场和Gold变化；出售方向单价重新计算 | Chronicle有有限出售适配；Modifier/全部Item/特殊模式未全覆盖 | E01/E02、AgentProvisioning |
| ACT-E04-01 | 行为 | Town Center与Workshop owner/merchant notable交谈购买工坊 | 检查Gold、Clan Tier/上限、战争/Owner条件；改Workshop Owner并影响后续财务 | Chronicle无Town 3D交互/Workshop购买 | E04、B05/H02、D09/J08 |
| ACT-E04-02 | 行为 | 与自有工坊经营者交谈切换生产类型 | 可能支付改产成本并改变之后每日输入/产出，不是立即给Gold | Chronicle无改产动作；源码路径存在、未视觉运行 | E04/E02/D09 |
| ACT-E04-03 | 行为 | 通过Notable/Clan经营交互出售Workshop | 转移Owner并结算关联资产/库存；与改产不同 | Chronicle没有Workshop出售动作 | E04/E07、H02/D09 |
| ACT-E05-01 | 行为 | Town Center与商人对话创建Caravan并配置领队/质量 | 支付创建成本；Companion离队成为Leader并创建WarParty/流动资金 | Chronicle无地图3D接近/Caravan创建动作 | E05、H05/F06/J08 |
| ACT-E05-02 | 候选行为 | Caravan商人与领队对话设置HomeSettlement或禁贸目标 | 修改贸易偏好但不等于逐步指定路线；对话入口和确认/撤销UI未核实 | 暂不计入最终分母，待追通Conversation和状态结果 | E05/F01/J08 |

E03、E06、E08、E09、E10的大量变化由每日模型、其它玩家动作或跨域Barter驱动，不按Campaign模型调用数计成新玩家动作。市场、Settlement管理与Barter以其实际入口/确认结果为准，不从报价、预估财务或API方法名推断交易已完成。

### F-G域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| F01 MobileParty | `OBS-F01-01`附近可见队伍摘要/玩家队伍状态；地图移动/追击/停步映射`ACT-K02-01`、`ACT-K02-03`、`ACT-K02-05` | 同一Party的对象/AI/roster字段不应拆成每个属性一个观察族 |
| F02-F04 Party AI/行为/Think | NPC行动结果在地图/Army/Siege显示；无通用玩家“指定NPC想法”按钮 | `AiPartyThinkBehavior`/分数模型是后台，不单独计玩家ACT；玩家可通过Army/War动作间接影响 |
| F05 Army | `OBS-F05-01`Kingdom Army管理视图；管理己方Army `ACT-F05-01`、解散`ACT-F05-02` | 调整cohesion/邀请party/取消属于一个VM事务还是多族，按结果提交边界核实 |
| F06 Clan War Party | 家族Party/Leader/上限可见于Clan面板，创建行为候选`ACT-F06-01` | NPC War Party自动生成不是玩家按钮；与Army附属关系分开 |
| F07-F08 战争目标/围城周期 | Siege/War状态观察映射`OBS-F08-01`；K地图移动/Army和G战斗入口承担玩家动作 | 战略目标评分/工程进度自动tick不当成直接玩家指令 |
| F09 Raid/Defense | 村庄遭遇中`ACT-F09-01..03`劫掠/强征志愿兵/强征物资；防守进入G战斗路径 | 三类村庄Hostile action后果不同，不能只按Encounter菜单共用一个行为ID |
| F10 BattleSimulation | `OBS-F10-01`模拟状态/胜负；坐镇动作映射`ACT-G01-02` | Campaign战斗simulation不等于Mission实时操作 |
| F11 troop training/recovery | Party Screen roster观察映射`OBS-B03-01`、`OBS-E06-01`；玩家升级映射`ACT-H04-01` | 自动NPC升级/治疗/逃兵不是玩家动作 |
| F12 prisoners | Prisoner roster映射H04/F12；Hero释放/Barter交互映射I03/I04等 | capture/release action effect需跟触发入口分开 |
| F13 Army decisions | 领主自动组军/加入/解散映射`OBS-F05-01`；玩家邀请`ACT-F05-01`/解散`ACT-F05-02` | NPC“意愿”不等于独立谈判确认 |
| G01 Encounter | `OBS-G02-01`当前MapEvent双方上下文；Attack`ACT-G01-01`、SendTroops`ACT-G01-02`、escape`ACT-G01-03`、surrender`ACT-G01-04`、join/help/leave`ACT-G01-05` | 选项的玩家行为、BattleSimulation与Mission入口须分开 |
| G02 MapEvent | 双方Party、参战/胜负状态映射`OBS-G02-01` | 增援/战斗结算是参与/事件过程，不再复制为每个Party action |
| G03 BattleMission | `OBS-G03-01`实际Mission状态；真实玩家3D输入族目前是待覆盖范围 | mission retreat映射`ACT-G03-01`；自动send troops不是实时Mission |
| G04 Formation/G05 Orders | 编队/当前命令映射`OBS-G04-01`；部署候选`ACT-G04-01`、Mission Order候选`ACT-G05-01` | 不按F键/按钮个数计动作，需按command target与结果拆分 |
| G06 Tactics/G07 Morale/G09 Resolution | Mission AI/士气/伤亡/击倒属于观察结果族，敌方AI内部Tactic没有玩家直接控制入口 | 没有直接玩家affordance的不做虚构ACT；投降/撤退依具体战斗上下文区分 |
| G08 Siege Mission/G10 Battle Rewards | Siege mission status/奖励流映射`OBS-G08-01/OBS-G10-01`；真实指令依`ACT-G05-01`或遭遇G01选项 | Siege Campaign/Event和Siege Mission上下文分开；奖励属于结果，不是玩家按键action |

#### F-G域首轮行动/观察定义

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-F01-01 | 观察 | Map上附近/可见MobileParty摘要 | 受主队视距、可见状态和观察半径过滤；Leader/roster/AI目标不是默认可见 | Observer最多12项摘要，字段有限，不是全图清单 | F01/K01、AgentObserver |
| OBS-F05-01 | 观察 | Kingdom→Armies/Army Management列表查看Army leader/成员/目标/cohesion | 管理权限及Kingdom身份过滤；地图Overlay和Panel有不同字段 | Chronicle没有完整Army/ArmyVM状态 | F05/F13、L03 |
| OBS-F08-01 | 观察 | Siege menu/地图Army overlay观察Camp、Siege、进攻/防守状态 | Campaign siege campaign state不是Mission战场实时状态 | Observer只返回有限Settlement/Encounter信息 | F08/G08、D01、AgentObserver |
| OBS-F10-01 | 观察 | Battle Simulation界面/Native map event的胜负、回合/finish状态 | 模拟推进不等于玩家Mission局部战斗 | Chronicle observer支持Simulation finished/retreated/state字段 | F10/G02、MAINLINE autoresolve |
| OBS-G02-01 | 观察 | Encounter/MapEvent双方与持续战斗状态 | Participants/Side/round/campaign event may have hidden detail; nearby Party entry不等于参战 | Chronicle现有快照不列完整MapEvent parties/contribution | G02/F10、AgentObserver |
| OBS-G03-01 | 观察 | 活跃Battle Mission的主角/队伍/场景/胜负/Agent状态 | 实时Mission与Campaign MapState不同；世界时钟暂停 | Observer当前无完整战术/Agent Mission state；仅missionRetreat查部分状态 | G03/G09、AgentProtocol |
| OBS-G04-01 | 观察 | Deployment/Order UI当前Formation类别、单位、Captain和队形/目标 | 信息随Mission、阶段、选中Formation改变 | Chronicle无Deployment/Formation详情 | G04/G05、AgentObserver |
| OBS-G08-01 | 观察 | Siege Mission攻防方、城门/墙/器械状态 | 场景对象与Campaign siege machine列表是两层 | Chronicle无实时siegeMission物件状态 | G08、AgentObserver |
| OBS-G10-01 | 观察 | Battle end/Post-battle party/Inventory结果 | 贡献/战斗模型决定XP、Renown/Influence、loot和capture；领奖屏幕与Campaign state提交分开 | Chronicle对Simulation PostBattle有有限结构化验收，不覆盖所有自然Mission | G10/F10、MAINLINE PostBattle |
| ACT-F05-01 | 行为 | K→Kingdom Armies打开ArmyManagement，创建己方Army/选择邀请Party并Done | 检查Kingdom成员/佣兵/Leader与参加Party条件，收取Influence并设置Army/Party关联；Cancel不提交 | Chronicle无Army Management交互 | F05/F13、KingdomArmyVM/ArmyManagementVM |
| ACT-F05-02 | 行为 | Kingdom Army panel/战后上下文主动解散玩家Army | 玩家解散消耗Influence并可能扣参与者关系；自动解散不是同一action | Chronicle无解散Army命令 | F05/F13、DisbandArmyAction |
| ACT-F06-01 | 候选行为 | Clan页创建Player Clan War Party | Clan Tier/队伍上限/Leader/兵力等限制；新Party获得独立库存/AI/目标 | Chronicle无创建家族Party动作；具体玩家UI流程需运行核实 | F06/H05、ClanPartiesVM |
| ACT-F09-01 | 行为 | 在有效Village encounter选择Raid/Plunder | 进入RaidEvent并造成物资/繁荣/安全与关系等不同后果 | Chronicle无Raid选择动作 | F09/J05、EncounterGameMenuBehavior |
| ACT-F09-02 | 行为 | Village encounter中强征Volunteers | 进入ForceVolunteersEvent，潜在获得部队并触发村庄/政治后果 | Chronicle无强征新兵动作 | F09/J05/G02 |
| ACT-F09-03 | 行为 | Village encounter中强征Supplies | 进入ForceSuppliesEvent，物资获得及Village损害路径不同于Raid/Volunteers | Chronicle无强征物资动作 | F09/J05/G02 |
| ACT-G01-01 | 行为 | 遭遇菜单选择 Attack/Lead an assault等进入实时Mission | 创建对应MapEvent并打开Mission，受类型/装备/围城/兵力条件限制 | Chronicle未实现通用Mission进入/战斗控制 | G01/G03、PlayerEncounter |
| ACT-G01-02 | 行为 | Encounter选择Send Troops/坐镇指挥 | 初始化BattleSimulation并结算Campaign MapEvent；与实时Mission伤亡/交互不同 | Chronicle确定性BattleSimulation可测试，非模型Provider不计自主能力 | G01/F10/G02、MAINLINE BattleSimulation |
| ACT-G01-03 | 行为 | Encounter选择Try to get away/撤离遭遇 | 依据追击/队伍/实力条件进行原生脱离尝试；失败可继续遇战，不等于Mission TAB retreat | Chronicle只处理已启动的战役Simulation retreat；通用逃脱未覆盖 | G01、EncounterGameMenuBehavior |
| ACT-G01-04 | 行为 | Encounter选择Surrender | 触发PlayerSurrender/captivity并改变MainParty/英雄状态，非普通Leave | Chronicle无Surrender动作 | G01/H12/F12、PlayerEncounter |
| ACT-G01-05 | 行为 | JoinEncounter菜单选择帮助攻击/防守一方、放弃Army或离开 | 变更参战方/Army membership或结束Encounter；权限依阵营/Army/当前双方 | Chronicle无支援参战/脱离Army菜单动作 | G01/F13、EncounterGameMenuBehavior |
| ACT-G03-01 | 行为 | Mission的TAB菜单选择Exit/撤退并确认 | `BattleEndLogic.TryExit`返回不同结果；围城守方可能变为SurrenderSiege，不能误报安全撤退 | Chronicle有有限missionRetreat adapter并检查TryExit；未覆盖键盘HUD视觉确认 | G03/G09、BattleEndLogic |

F/G域行动族仍有候选项：真实Mission主角连续移动/攻击与Formation orders目前没有原生Agent动作，因此只建目录/能力缺口，不计作已支持行为；Battle/Campaign结果源同时由F/G多项研究映射，去重时按唯一玩家入口和结果提交点核对。

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
| I04 Marriage/Romance | `OBS-I04-01`当前Courtship选项/阶段；`ACT-I04-01/02/03`已定义 | NPC每日婚姻算法不是玩家动作 |
| I05 Family/Kinship | `OBS-B02-01`亲属图/百科；家庭产生/婚姻/死亡等结果由A/B/I类实际行为触发 | 无直接修改家族关系菜单 |
| I06 Education | `OBS-I06-01`教育通知与选择面板 | 每个成长年龄选择是玩家可见事项；错过前段会自动随机补选 |
| I07 Traits | `OBS-B10-01`Character Developer Trait展示；行为写入来自其它Action结果 | 玩家通常不能直接编辑Trait |
| I08 Crime/Reputation | `OBS-B10-01`Crime/处罚上下文；`ACT-I08-01..06`既有初始处罚分支 | 处罚类型和自动Crime decay分开 |
| I09 Dialogue Relation | 对话/Barter选项反馈映射`OBS-B09-01/OBS-I09-01`；选择动作共用J08的Sentence family | 不能把每个string/关系文本条件单独计行为 |
| I10 Persuasion | `OBS-I10-01`Persuasion progress/attempt/选项；行动为当前Dialogue options，后果映射J09/I04 | Persuasion参数/分支待按实际Task类型去重 |

#### H-I新增目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版结果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源映射 |
| --- | --- | --- | --- | --- | --- |
| OBS-H04-01 | 观察 | PartyScreen查看当前成员/伤员/俘虏Roster及升级/招募控件 | 列表按PartyScreen mode/roster side和容量过滤；UI显示不是全Campaign人口表 | Chronicle常驻只报MainParty总量；战后 PartyState 有有限Roster读取 | H04/F11/H12、PartyVM |
| OBS-H05-01 | 观察 | Clan/Party成员页读取Hero同伴身份/所属Party/可用成员 | 任务/囚禁/领队/忙碌状态会影响能否入队或担任Party职位 | Observer不列完整同伴列表/技能/位置 | H05/B04、AgentObserver |
| OBS-H06-01 | 观察 | Clan管理Party角色区查看每个职责的当前Hero/技能效果 | 角色资格基于Model及目标MobileParty；角色持有人变化后模型效果更新 | Chronicle不报角色Holder ID | H06、ClanRoleItemVM、AgentObserver |
| OBS-H08-01 | 观察 | Inventory/Character Equipment显示Battle与Civilian装备槽/选中Hero | 装备候选受物品用途、装备模式、槽位和Hero资格筛选 | Chronicle无Hero装备槽快照；InventoryItem transaction不是穿戴状态证明 | H08/H07、SPInventoryVM |
| OBS-H09-01 | 观察 | SmithingState显示执行Hero、Stamina、模板/已解锁组件、材料成本/预览 | 当前模式与选中Hero改变可执行Smithing actions | Chronicle无Crafting State/配方观察 | H09/L07、CraftingVM |
| OBS-H11-01 | 观察 | MainParty/Clan状态栏显示Renown、Influence、Tier及下一门槛 | 仅为当前数值，不包含完整来源历史/未决政治支出 | Chronicle identity/economy Snapshot提供有限数值，无变化原因 | H11/B05/AgentObserver |
| OBS-H12-01 | 观察 | MainHero俘虏GameMenu/赎金事件与Captor上下文 | 菜单会根据Captor类型、战争和计时检查分支动态切换 | Observer可见PlayerCaptivity State但没有当前菜单细项/处置报价 | H12/F12/PlayerCaptivity |
| ACT-H12-01 | 行为 | Wilderness/Prison ransom offer菜单选择Accept | 检查当前Ransom Amount/主角金币；扣款后经`EndCaptivityAction.ApplyByRansom`解囚 | Chronicle无Captivity菜单/赎金支付动作；源码路径确认、UI未跑 | H12/F12、PlayerCaptivityCampaignBehavior |
| ACT-H12-02 | 行为 | Ransom offer选择Refuse and wait for a better offer | 不支付本次赎金，接入原生`settlement_wait`并恢复LastTimeControlMode继续时间检查 | Chronicle没有囚禁Wait动作；等待推进依原版当前TimeMode | H12/A02、PlayerCaptivityCampaignBehavior |
| N/A-H12-01 | N/A | Captor败退、盟友支付、时限随机逃脱等自动释放 | Campaign/MapEvent状态触发EndCaptivityAction，无可选择的玩家按钮 | 不计入ACT分母；后果观察映射F12/OBS-H12-01 | H12/F12、PlayerCaptivityCampaignBehavior |
| OBS-I04-01 | 观察 | 与目标Hero对话时显示当前Romantic/courtship阶段相关选项 | 当前状态可隐藏/开放开始/重试/婚姻Barter选项；不等同完整爱慕数值 | Chronicle只读当前对话可选句，不读Romance state | I04、RomanceCampaignBehavior/J08 |
| OBS-I09-01 | 观察 | 当前Conversation参与者、阶段和原生开放选项 | 条件句集合随身份/任务/关系/输入token变化 | Protocol可读当前Menu/Conversation选项，不穷举全树 | I09/J08、AgentObserver/Protocol |
| OBS-I10-01 | 观察 | 当前Persuasion target/progress/剩余attempt/argument概率 | PersuasionTask类型、对话阶段和模型决定可用信息与风险 | Chronicle未输出PersuasionTask；仅当前开放句可能可观察 | I10/J09、PersuasionVM |
| ACT-H04-01 | 行为 | PartyScreen选兵种可用Upgrade target、支付对应upgrade cost并Done | 消耗兵种升级费用/候选路径及roster变化；取消不提交 | Chronicle有个别招募测试，未提供通用升级动作 | H04/F11/PartyVM |
| ACT-H04-02 | 行为 | PartyScreen从俘虏列表选普通Troop Recruit并确认 | 受是否可招募、忠诚/容量/招募时间/风险模型限制；不是卖俘虏/释放Hero | Chronicle未实现通用Prisoner recruitment | H04/F12/PrisonerRecruitmentModel |
| ACT-H05-01 | 候选行为 | 找到Wanderer Hero后完成交谈/支付雇佣价格并加入Player Clan | price受Equipment/Level/Perks影响；同伴身份和入Party是后续Roster结果 | Chronicle无Wanderer寻访/招募动作；实际Dialogue UI需要确认 | H05、DefaultCompanionHiringPriceCalculationModel/J08 |
| ACT-H06-01 | 行为 | Clan Management为MainParty候选成员任命/移除Quartermaster/Scout/Surgeon/Engineer | 按当前Party role条件绑定Hero并改变后续模型效果；Dialog/Data layer另处理Naval roles | Chronicle无role set action；角色候选资格/结果确认未实机 | H06、DefaultClanMemberPartyRoleModel/ClanRoleMemberItemVM |
| ACT-H08-01 | 行为 | Inventory/Equipment槽将适用Item装备或卸下、选择Battle/Civilian mode | InventoryVM检查Hero使用条件/slot/容重；成交/换装分别写Party库存与Hero Equipment | Chronicle交易数据适配不等于当前无损Hero装备动作 | H08、SPInventoryVM/InventoryLogic |
| ACT-H09-01 | 行为 | 在CraftingVM中完成 weapon forging | 需要材料、部件解锁/配方/执行Hero有Stamina；生成武器/XP/Item历史结果 | Chronicle无Forge action | H09、CraftingVM/CraftingCampaignBehavior |
| ACT-H09-02 | 行为 | Smithing Smelting页选择已有Item熔炼并确认 | 消耗装备，产出材料/XP/解锁部件；与Crafting成品结果不同 | Chronicle无Smelt action | H09、SmeltingVM/CraftingCampaignBehavior |
| ACT-H09-03 | 行为 | Smithing Refinement页选择公式/消耗材料并确认 | 付出Energy/材料，依英雄技能Perk产出锻造材料/XP | Chronicle无Refine action | H09、RefinementVM/SmithingModel |

上述H05 companion招募实际Conversation路径、H08装备事务的完整确认边界、H12 captivity菜单各结果和I10 Persuasion的当前统计面均仍是候选映射；相关ID可以追溯，但在入口/条件/失败恢复验证前不能把“映射存在”当成覆盖或最终穷举。

### F域系统与目录族映射

| 系统ID | 已发现入口/观察族 | 去重与未决 |
| --- | --- | --- |
| F03 AI行为类型 | 附近Party概要复用`OBS-F01-01`；地图提示/行为标记暂列`OBS-F03-01`候选 | `AiBehavior`枚举是引擎地图状态，不是玩家可逐项下达的NPC命令。当前资料证明了行为对象与AI路径，尚未证明原版UI会直接展示具体行为类型；候选观察不计入最终OBS分母 |
| F07 战争目标 | 军团目标复用`OBS-F05-01`，围城状态复用`OBS-F08-01`；非Army Party的战略目标暂列`OBS-F07-01`候选 | 玩家可通过外交、阵营转换和实际战争行动改变AI候选的环境，但无通用菜单替NPC指定下一目标。当前Observer不返回NPC目标评分/完整目标；是否有可见原版目标提示仍待核 |

### G域系统与目录族映射

| 系统ID | 已发现入口/观察族 | 去重与未决 |
| --- | --- | --- |
| G01 Encounter | `OBS-G01-01`遭遇界面中的双方/可用选项；战斗、坐镇、脱离、投降及援助分别映射`ACT-G01-01`至`ACT-G01-05` | 接触地图Party只是进入遭遇的前置；接战后是否进入Mission或BattleSimulation取决于玩家选择，不能合并成一个“遭遇动作” |
| G02 Map Event | 战斗持续状态复用`OBS-G02-01`；创建遭遇/战斗映射G01及F09等真实发起动作 | `MapEvent`是Campaign战斗容器；有事件对象不代表每个参战Party或伤亡贡献都能由当前玩家界面/Observer观察 |
| G03 Battle Mission | Mission状态复用`OBS-G03-01`；进入Mission映射`ACT-G01-01`，TAB退出映射`ACT-G03-01` | Battle Mission与坐镇模拟是不同分支；Chronicle无一般实时作战控制闭环 |
| G04 Formation | 部署/编队观察复用`OBS-G04-01`；部署配置为候选`ACT-G04-01` | 编队类别与Mission类型、阶段和兵种相关；部署/确认入口未完成玩家UI核实 |
| G05 Orders | 编队指挥状态观察复用`OBS-G04-01`；下达战术命令为候选`ACT-G05-01` | 同一Order菜单可产生移动、阵型、朝向、骑乘/射击及器械目标等不同状态；指令录入与部队执行到位必须分别核验 |
| G06 Tactics与战术AI | AI执行结果可能反映在`OBS-G04-01`/`OBS-G03-01`；AI选择/执行战术本身记为`N/A-G06-01` | 战术AI是Mission自动决策机制，不是玩家可点选的独立动作；玩家显式下令归`ACT-G05-01`，不能把AI内部决策重复计数 |
| G07 Morale | 战斗士气状态暂列`OBS-G07-01`候选；士气变化由Mission遭遇、战果和士兵行为等真实动作产生 | 目前Research覆盖了士气机制，但没有完成玩家HUD/提示可见字段核对；候选观察不计入最终分母，不将幕后morale数值等同玩家可读信息 |
| G08 Siege Mission | 实时器械/城墙/攻守观察复用`OBS-G08-01`；进入攻城战按`ACT-G01-01`，Mission指挥复用候选`ACT-G05-01` | 战略SiegeEvent、围城菜单和Siege Mission是三个层次；不可用`OBS-F08-01`代替实时场景观察 |
| G09 Combat Resolution | 战后伤亡/俘虏/战利品画面复用`OBS-G10-01`，俘虏处理另映射F12/H12；玩家主动Mission撤退为`ACT-G03-01` | 战斗结算是遭遇/坐镇/Mission的结果阶段，不计成直接“结算”动作；各入口伤亡模型与战后界面仍需区分核验 |
| G10 Battle Rewards | 领奖结果观察复用`OBS-G10-01`；获得经验/声望/影响力/物品均是其它真实行为的后果 | 奖励计算不是独立玩家菜单动作；自然战斗结算与当前确定性模拟夹具证据不可互相代替 |

### J-L域初始交叉映射与目录族

| 系统ID | 映射到的观察面/行动族 | 去重/未决 |
| --- | --- | --- |
| J01 Issues | `OBS-J01-01`当前Notable/领主Issue提示；接取转入`ACT-J02-01`，Alternative/Lord Solution独立为`ACT-J01-02` | 蓝色标记是玩家提供的视觉事实；每种Issue的奖励/Brief不同，不并成通用任务脚本 |
| J02 Quests | `OBS-J02-01`任务列表/当前阶段/地图marker；接取/启动`ACT-J02-01` | Quest完成由各Task/真实世界动作达成，不另计“写QuestComplete” |
| J03 Quest Tasks | 移动/交易/对话/战斗步骤映射K/E/I/G已有实际动作ID | TaskBase只是程序对象，具体任务步骤需回到相关原版UI/动作族 |
| J04 Journal | `OBS-J04-01` Quest Journal/时间与进度记录 | JournalLog是回看信息，不等于世界状态或Action |
| J05 Incident | `OBS-J05-01` MapState当前Incident及条件选项；`ACT-J05-01`选择事件回应 | 每个Incident的Effect/Consequence按具体选项参数读取，不能合并不同事件后果 |
| J06 Rumor | `OBS-J06-01` trade rumors候选数据/信息 | 创建者/实际玩家呈现尚未知；不能把TradeRumor对象计成观察已支持 |
| J07 Notifications | `OBS-J07-01` MapNotification/QuickInfo/Scene通知 | 可点击通知若改变输入或位置则另映射所触发操作 |
| J08 Conversations | `OBS-J08-01`当前Conversation Flow/参与者/选项；`ACT-J08-01`选择当前开放Dialogue option | Relation/Persuasion对话复用I09/I10的真实消费者，不重复文本条目 |
| J09 Persuasion | `OBS-J09-01`当前Persuasion task/进度/风险信息；`ACT-J09-01`提交Persuasion argument | 说服尝试是Conversation option的特殊子族，任务/求偶/政治用相同模型但不同后果 |
| J10 Tournament | `OBS-J10-01`赛事/对手/排行榜；`ACT-J10-01/02`参与或观看 | Join真实Mission与Watch模拟不同；奖励引用G10/H11，不能固定当Renown按钮 |
| J11 Board Games | `OBS-J11-01`对手/棋盘/当前局面；`ACT-J11-01/02`下注开局/棋盘落子 | Tavern dialog下注与Mission中棋盘走子是不同上下文；模型没有Campaign自主控制 |
| J12 Story Mode | `OBS-J12-01`主线阶段/任务提示；Story选择沿J02/J03/J08映射 | Story quest及Sandbox通用任务分开，不能因Story mode存在而计入Sandbox默认行为 |
| K01 World Map | 可见地图对象/附近实体映射`OBS-F01-01/OBS-D01-01`；足迹由`OBS-K03-01` | 地图图标/悬停/ALT/Track是不同信息精度，需保留来源与可见门槛 |
| K02 Navigation | `ACT-K02-01..05`地图移动、目标点移动、追近、Follow modifier、Hold；显式时间控制复用`ACT-A02-01` | move/pursue/hold已有MAINLINE契约；普通点击自然推进，不能重复计隐藏advance |
| K03 Tracking | `OBS-K03-01`已发现Track与技能分级描述 | 未发现的Track不构成Agent可读信息；纪元/追踪技能细项未知 |
| K04 Weather | `OBS-K04-01`地图Atmosphere/雨雪/时节 | 天气生成与环境后果是后台/场景数据，无Weather设置行动 |
| K05 Sea/Port | 船只/港口模型候选观察`OBS-K05-01` | 默认PartyNavigationModel不开放naval capability；先映射为未决/模块依赖，不声称玩家能默认海上旅行 |
| K06 Encounter Flow | 遭遇菜单/双方状态映射G01/G02；选项Actions映射G域逐项定义的ACT ID | K地图追近只是接触输入，协商/支援/开战/投降分流至G，不重复一条“Encounter”动作 |
| K07 Hideout | 藏身处地图/Encounter观察映射`OBS-K07-01`；攻/等夜/坐镇映射F/G/J实际行动 | Hideout发现、Campaign Wait和Mission战斗是不同路径 |
| K08 Bandit Density | `OBS-K08-01`可见Bandit Party/Hideout密度线索 | 全图Spawn人口和计时是后台Campaign，玩家无“生成/减少密度”按钮 |
| L01 XML / L02 XSLT | 仅影响被加载对象/内容；无独立玩家动作ID | L01数据源与L02转换手段作为相关行为族的证据/版本约束，不能按XML/XSLT文件数计ACT |
| L03 Game Menu/L04 Dialogue | 每个选项映射至其所属的Issue/Quest/政治/聚落/战斗等具体行为族；通用Menu/Dialogue引擎不另计玩家行为 | 复用相同点击外壳不代表同一原生后果 |
| L05 Encyclopedia/L06 Notifications | 观察面映射A07、B及J的已有OBS ID | 显示页面/通知的技术View不额外算对象动作 |
| L07 Scene/Mission | 场景状态/实时输入映射D/G/J的已有OBS/ACT ID | Scene类型和MissionLogic不是玩家按钮数量 |
| L08 Localization | N/A玩家行动；文本呈现映射相应Menu/Dialogue/通知OBS | 语言字符串本身不改变Campaign状态 |
| L09 Module Loading | N/A战役内玩家动作；Launcher选择模块发生在战役前 | Module存在/排序是产品配置，不计入Campaign动作分母 |
| L10 CampaignBehavior/L11 GameModel | N/A直接玩家动作；行为/模型输出映射到实际应用这些规则的ACT/OBS | 事件注册、模型调用数不是行为族 |
| L12 Harmony/BLSE | N/A直接游戏动作；仅可能影响外部模块装载/方法执行 | Loader/patch链不计为玩家游戏行为或开发Harness能力 |
| L13 SaveSystem | Save/SaveAs/Load复用`ACT-A05-01..03` | IDataStore/SaveableTypeDefiner是序列化机制，不另计数据字段数量 |

#### J-L域新增行动/观察定义

| ID | 类型 | 玩家入口 / 观察语义 | 原版后果、时间/限制 | Chronicle状态 / 未知 | 来源 |
| --- | --- | --- | --- | --- | --- |
| OBS-J01-01 | 观察 | 聚落Notable/领主上可见的Issue标记/接取提示 | 当前有效Issue与Quest giver/Owner/任务状态决定是否显示 | `talkToIssueOwner`仅限Harness研究流程，跳过真实地图接近/视觉路径 | J01/IssueManager、用户确认蓝色感叹号 |
| ACT-J01-02 | 候选行为 | Issue对话选择Alternative Solution或Lord Solution，而非Quest路线 | 可能派兵、花天数/资源并有伤亡/失败风险；每类Issue效果不同 | 未实现；不与接Quest合并，未穷举各Issue子类 | J01、IssueBase、DefaultIssueModel |
| OBS-J02-01 | 观察 | Quest/Journal页面查看进行中阶段、期限、目标和日志 | Quest/QuestTask状态与自由文本记录不同；期限基于Campaign time | Observer只给当前任务摘要，不列完整日志/隐藏Task目标 | J02-J04、QuestBase/QuestsVM |
| ACT-J02-01 | 行为 | 从Issue/Story/NPC提供入口接受并启动一个合法Quest | 依任务内容写Quest state/期限，可能引入Gold/关系/物品前置或失败风险 | Chronicle无通用Quest接取/阶段执行器；每类入口须单独映射 | J01/J02/J12、QuestBase/IssueBase |
| OBS-J04-01 | 观察 | Journal/LogEntry浏览任务/角色记录 | 日志过期、隐藏信息与当前状态不同步；不自动推进Campaign | Chronicle未输出完整LogEntryHistory/Quest Journal | A07/J04/L05、LogEntryHistory/QuestsVM |
| OBS-J05-01 | 观察 | Settlement进出后打开Incident选择界面查看事件/选项 | Incident trigger、cooldown、条件筛选一条事件；Effect列表不等于实际已提交结果 | MAINLINE有Incident modal/state链，仍未所有Incident运行验证 | J05/A02、IncidentsCampaignBehaviour/Incident |
| ACT-J05-01 | 行为 | Incident UI中选择一个条件合法的事件Option并确认/关闭 | 每个Effect和Option Consequence分别调用；可能改变金钱/Party/关系/Settlement状态；直接API跳过VM cleanup | Chronicle对Incident通用流程目前Unsupported/Research；结构化事件返回未全测 | J05/L06、Incident.InvokeOption、MAINLINE |
| OBS-J06-01 | 候选观察 | TradeRumor data对象所表达的Settlement/商品/参考价/寿命信息 | 已确认数据结构，但玩家是否在市场/对话中看到此类信息尚未追到 | 暂不计入最终OBS分母；需要证明真实原版玩家UI入口和可见时点 | J06、TradeRumor、E02/E05；玩家消费者调用方未知 |
| OBS-J07-01 | 观察 | 地图通知/QuickInfo/Scene notification | 队列可过期/关闭/跳转；Notice、Log与世界对象值分开 | Observer不读Notification queue/已读/点击目标 | J07/A07/L06、MapNotificationVM |
| OBS-J08-01 | 观察 | 活跃Conversation的发言人/Flow阶段/当下开放Option | sentence condition、身份token、Task与关系筛选，不能扫描未开放Option | Protocol提供有限Conversation state/option读取 | J08/I09、ConversationManager/AgentObserver |
| ACT-J08-01 | 行为 | 只选择当前Conversation实际开放且仍然valid的原生对话Option | Consequence可能启动Barter/Quest/Persuasion/Mission或改关系；context变化须重验 | Chronicle `dialogueSelect`仅限当前option列表；不支持全3D谈话接近 | J08、ConversationManager/AgentProtocol |
| OBS-J09-01 | 观察 | PersuasionVM展示当前task阶段、可用argument与进度/机会 | chance依Trait/Skill/Relation/difficulty，和最终成功不是一回事 | Chronicle不输出完整PersuasionTask对象 | J09/I10、PersuasionVM/PersuasionTask |
| ACT-J09-01 | 行为 | 在当前Persuasion task中选择一个真实可用argument | 单次尝试会提交随机/模型概率结果和进度/失败效果；不等于一般`dialogueSelect`不加上下文 | Chronicle没有专用Persuasion观察/回执及重规划 | J09/I10、DefaultPersuasionModel |
| OBS-J10-01 | 观察 | Arena/Tournament菜单或TournamentLeaderboard查看可加入赛事/对手/排名 | 赛事随Town每日模拟生成/结束；观看排名不是参加Mission | Chronicle无Tournament state/list/player visual | J10、TournamentCampaignBehavior/Manager |
| ACT-J10-01 | 行为 | Town Arena选项加入一场Tournament并进入比赛Mission | 进入实时比赛、可获得奖励/排名；Campaign地图时钟在Mission停止 | Chronicle无赛事列表/格斗输入；三维动作未覆盖 | J10/G03、TournamentMissionStarter |
| ACT-J10-02 | 行为 | Arena菜单选择Watch tournament | NPC模拟比赛结算Tournament状态/奖品显示；与玩家参赛不等价 | Chronicle不支持观战/赛事Simulation接口 | J10、TournamentManager |
| OBS-J11-01 | 观察 | Tavern boardgame对手/当前棋盘/先后手/赌注 | 不同棋类有各自棋盘规则与AI难度状态 | Chronicle无BoardGame Mission observe | J11、BoardGameCampaignBehavior/MissionBoardGameLogic |
| ACT-J11-01 | 行为 | Tavern host/lord对话设置赌注/难度/先后并确认开局 | Gold赌注档位与AI难度/对手条件改变；Conversation结束后启动棋局Mission | Chronicle无对话配置/BoardGame Mission入口 | J11、BoardGameCampaignBehavior |
| ACT-J11-02 | 行为 | BoardGame Mission中点选棋盘落子 | 按具体棋类规则更新棋盘与回合；合法棋步/胜负条件由BoardGame类实现 | Chronicle无棋盘格像素/state/actions接口 | J11、BoardGame类/MissionBoardGameLogic |
| OBS-J12-01 | 观察 | Story Mode任务/阶段通知、已完成的教程/主线阶段 | StoryMode阶段状态不同于Sandbox共同Quest集合 | Chronicle仅有限Quest摘要，不读主线StoryModeData | J12、StoryMode/MainStoryLine/StoryMode behaviors |

#### F/G/K跨域补充目录项

| ID | 类型 | 玩家入口 / 观察语义 | 原版后果、前置/时间 | Chronicle覆盖 / 证据 / 未知 | 来源 |
| --- | --- | --- | --- | --- | --- |
| OBS-F03-01 | 候选观察 | 地图上可见Party的悬停信息/行为图标若显示其当前地图行为 | AI行为对象可能由Default/ShortTermBehavior、目标实体和地图事件派生；图标/悬停可见字段尚未以当前1.4.8界面核实 | 暂不计入最终OBS分母；需追当前MapEntity tooltip/marker调用链并核对玩家画面；不得从`AiBehavior`字段名推断玩家可见性 | F03/F01、MobilePartyAi、MapEntityVisual；UI消费者未知 |
| OBS-F07-01 | 候选观察 | 地图/军团/围城原生界面显示NPC Party或Army当前战略目标的状态 | AI军事目标是候选评分与行为执行结果；宣战关系、聚落归属、Army目标和短期导航目标不是同一字段 | 暂不计入最终OBS分母；需核实非Army Lord Party目标是否可通过玩家界面稳定观察，以及可见/过期条件 | F07/F02/F05/F08、AiMilitaryBehavior、AgentObserver；玩家UI字段未知 |
| OBS-G01-01 | 观察 | Map encounter菜单中双方、遭遇类型和当前可用谈判/接战/脱离/投降选项 | 选项由双方Faction、事件类型、装备/兵力、围城及Mission状态筛选；菜单可用项不是已提交战斗结果 | Chronicle未提供通用Encounter菜单观察；各交战类型的选项集合与显示信息未全量验证 | G01、PlayerEncounter、EncounterGameMenuBehavior |
| OBS-G07-01 | 候选观察 | Mission HUD/战斗提示若显示双方或部队士气、动摇/溃败状态 | 士气数值会受参战规模、伤亡、领导与场景行为改变；公开模型字段不代表HUD可见 | 暂不计入最终OBS分母；需核当前Mission HUD和提示的实际字段、粒度与刷新条件 | G07/G03、BattleMoraleModel、Mission morale logic；玩家UI消费者未知 |
| N/A-G06-01 | N/A | Mission战术AI选择目标/阵型行为本身 | 属于部队AI自动计算；玩家通过下令影响其后的执行，不存在直接调用某个AI决策的原版菜单动作 | 不计入ACT分母；玩家Order入口单独映射`ACT-G05-01`，结果按`OBS-G03-01/OBS-G04-01`验证 | G06/G05、OrderController、Mission tactical AI |
| ACT-G04-01 | 候选行为 | Battle Mission开战部署时配置Formation分类/队长/自动部署后Begin Mission | 改变任务内Formation分配和spawn安排；不同Mission类型部署选项有差异 | Chronicle未实现；各部署面操作/确认未知，暂不计最终分母 | G03/G04、OrderOfBattleVM/BattleDeploymentMissionController |
| ACT-G05-01 | 候选行为 | Mission中选择Formation/兵种组并下达Movement/Arrangement/Facing/Riding/Firing/UsableMachine order | 只有适用Order与目标有效时才改变formation order；收到UI命令不等于Agent执行到位 | Chronicle没有BattleOrder动作/mission state反馈；快捷键/订单类型全量未列 | G04/G05/G06、MissionOrderVM/OrderController |
| ACT-K02-01 | 行为 | MapScreen点击settlement visual请求主队自动移动至聚落 | 检查当前PathFace/NavType/访问权限；成功设目标并按地图点击配置自然改变Campaign time | Chronicle `move`已有Settlement ID路径/抵达断言，玩家完整视觉UI未完成 | K01/K02、MapScreen、MAINLINE move |
| ACT-K02-02 | 候选行为 | MapScreen点击可导航地形点/空地图位置移动主队 | 设置位置目标/自动路径；不能把控制权/坐标直接设置冒充地图鼠标交互 | 当前move契约未确认自由坐标是否为玩家可用入口；暂不计最终分母，需检查API与NavMesh点击失败条件 | K02、MapScreen.HandleLeftMouseButtonClick/MAINLINE |
| ACT-K02-03 | 行为 | 普通点击可见/有效移动Party(不按Follow Modifier)下达Engage/Pursue | 主队自动接近；目标丢失/不可达会自然停步或改Hold；点击time mode依用户配置 | Chronicle `pursue`已测自然接敌；不可见丢失时钟/停步边界仍未知 | K01/K02、F01-F04、MAINLINE pursue |
| ACT-K02-04 | 候选行为 | 点击移动Party并使用MapFollowModifier跟随 | 设置Follow而不是敌对接近目标；退出视野/目标失效后的结果需与pursue区分 | Chronicle无Follow modifier行为动作 | K02/F02、MapScreen/MapEntityVisual.OnMapClick |
| ACT-K02-05 | 行为 | MapScreen点击MainParty/玩家队伍Visual停步 | `SetMoveModeHold`清除移动目标，时钟副作用由原版点击时钟配置处理 | Chronicle `hold`已有目标清除断言并映射地图点击时间 | K02、F04、MAINLINE hold contract |
| OBS-K02-01 | 观察 | World map上的主队位置/目标/当前移动状态及路径可达提示 | 路径的整条导航mesh/脚印不等于Observer已见到的地图路线 | Chronicle snapshot有位置/目标/isMoving/MoveMode，不返回导航path节点 | K01/K02、AgentObserver |
| OBS-K03-01 | 观察 | Scouting/MapTrack visual当前已发现足迹的描述信息 | 只对Detected/live/半径内Track有效；信息精度由SkillEffect和Track年龄/距离/尺寸影响 | Chronicle NearbyParty不输出MapTrack | K03、DefaultMapTrackModel/MapTracksCampaignBehavior |
| OBS-K04-01 | 观察 | World Map可见区域的当前雨雪/光照/季节环境与Mission天气 | 天气节点随Campaign周期按地区更新；视觉和战斗效果可能分离 | Chronicle不读天气/Atmosphere字段 | K04、MapWeatherCampaignBehavior/DefaultMapWeatherModel |
| OBS-K05-01 | 观察 | Sea/Port/Ship状态及可导航能力 | Naval数据模型存在，但当前DefaultPartyNavigationModel返回无Naval能力，玩家航海入口未确认 | Chronicle无船队、海上移动或PortState Observation | K05、Ship/NavigationHelper；Active model replacement unknown |
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
