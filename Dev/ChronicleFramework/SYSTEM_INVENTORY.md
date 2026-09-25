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

A06预设/设置页目前只定位到界面族；每个选项的写入字段、条件与后续模型结果可能不同，所列 `ACT-A06-*` 仍为候选入口簇，不计入最终动作分母，待按原生Option ID逐项拆分。A03/A04目前映射为系统后台回调而非玩家直接动作；若某个具体事件存在手动玩家入口，应映射到发起该状态变化的ACT，而不是另造一个“触发CampaignEvent”动作。

| 内部系统 / N/A候选 | 分类理由 | 映射来源 / 仍需排除的直接玩家入口 |
| --- | --- | --- |
| A03 周期事件、A04 CampaignEvent总线 | 这些是玩家动作/观察触发后的引擎调度与回调，不直接由玩家按“触发事件”调用；实际消费后果连接到对应行为/观察族 | `Research/A/CampaignRuntimeWorldState.md`；仍要检查是否存在有直接按钮语义的专属事件子系统，并映射到实际ACT ID |

### B域初始交叉映射

此表只复用B/H/I/C已研究的真实入口；一个B系统可映射多个行动族，一个行动族也可能服务多个系统。百科、人物身份字段和关系显示目前多数只有源码路径、未视觉复核。

| 系统ID | 映射到的玩家行动族 / 观察面 | 证据与去重边界 |
| --- | --- | --- |
| B01 Hero生命周期 | `OBS-B01-01` Hero百科/状态页；状态变化映射至导致出生/成年/被俘/释放/死亡的具体行为，不创建“改HeroState”玩家动作 | B01/B02/H12/F12；Hero是事件对象，没有通用生命周期操作面 |
| B02 Hero家庭 | `OBS-B02-01` Hero家庭/配偶/子女百科链；婚姻交涉映射`ACT-I04-01/02/03`，教育通知见`OBS-I06-01` | B02/I04/I05/I06；婚姻、出生、教育后果分开，不把亲属字段读写计为动作 |
| B03 Hero能力 | `OBS-B03-01` Character Developer面板；属性/Focus/Perk变更为`ACT-H10-01` | B03/H10；Character Developer待改→Done提交/Cancel撤销是一类界面事务，获得XP来自其它动作族 |
| B04 Hero身份 | `OBS-B04-01` Hero身份/职业/归属信息；婚姻Clan结果见I04，陪伴/封臣/王国变更见H05/C07 | B04/H05/C07/I04；没有通用“设置职业/归属”入口，转换必须映射具体原生流程 |
| B05 Clan | `OBS-B05-01` Clan Management页；改名、旗帜和财务/领地/成员各是待细分操作 | B05/H02/C；Clan页面本身不等于独立行动，不能将13个Tab/VM方法计入分母 |
| B06 Kingdom | `OBS-B06-01` Kingdom Management页；决议/战争/和平/联盟/政策映射C域独立行动族 | B06/C01-C10；K键/界面入口别名不是额外动作 |
| B07 Culture | 创建新Campaign时文化选择别名至`ACT-A01-01/02` | B07/H01/A01；不建立Campaign中普遍存在的“换文化”动作 |
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
| C02 KingdomElection | `OBS-C02-01`候选、Chooser/Supporter、选票/胜率状态；`ACT-C02-01/02`分别记录Supporter态度和Chooser最终选择 | 角色、权限、费用不同；Decision子类可参数化但其后果需逐类核对 |
| C03 War/Peace | `OBS-B08-01`Faction stance；`ACT-C03-01/02`分别为K页战争提案与议和提案 | 地图敌对/开战是其它攻击/Hostile行为的副作用，不另计“DeclareWar按钮”；提案有决策/投票/Influence步骤 |
| C04 Alliance/Call-to-War | `OBS-C04-01`联盟、援战协议、目标/期限；提议Alliance/Call-to-War分立；决议回应复用`ACT-C02-01/02` | 持续Alliance、一次Call-to-War proposal和Chooser响应分开映射；Call-to-War发起UI尚未定位 |
| C05 Policy | `OBS-C05-01`王国当前政策与决策；`ACT-C05-01`提议政策，Decision支持/选择复用`ACT-C02-01/02` | 政策结果、提出提案与投票支持不能合并 |
| C06 Fief allocation | Settlement/Clan页面观察可映射D10/B05/B06；`ACT-C06-01`提出/争取Claimant主张，Decision选择复用`ACT-C02-01/02` | Preliminary与Final claimant Decision分阶段，不能与最终ChangeOwnerAction重复计数 |
| C07 Clan Kingdom change | `OBS-B04-01/OBS-B06-01`当前Clan/Kingdom身份；`ACT-C07-01..05`区分脱离封臣、保留/归还Fief、君主退位、结束佣兵 | 同一个Kingdom页面按身份/领地状态切换后果，不能合成通用leave；Barter投奔的玩家入口尚未知 |
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
| ACT-C04-02 | 候选行为 | 向盟国提出Call-to-War协议请求 | 接受后可产生援战费用、协议与目标Kingdom开战链；玩家主动提出此请求的精确UI入口尚未找到 | 暂不计入最终分母，待核真实玩家入口和失败/撤回分支 | C04/C01-C02、E08；本机Model/Decision存在，UI调用未追完 |
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

### 其余类别映射状态

A域已有初始交叉映射；C-L类别按同一规则追加到此文档。直到A-L每项均映射为有真实入口证据的唯一ACT/OBS族、或以证据判为无直接affordance，并完成重复ID/断链/未知门禁检查前，MAINLINE总分母维持UNKNOWN，Research Gate保持BLOCKED。类别Research段落是证据来源，不是新的分母行；不得因某类别拥有技术分析就推定玩家行为入口已穷举。

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
