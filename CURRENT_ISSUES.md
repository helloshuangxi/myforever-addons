> 2026-11-14 更新：用户已进游戏接受本批界面并授权合并发布。UX-001 的用户界面验收为 approved；矿名直显、战斗名称桥接、跨平台等专项仍保留 open。本批版本与范围见 `PersonalAddons/releases/ui-20261114-RELEASE.md`，下方旧日期/版本事实按历史保留。

# 目前的问题与接手清单

整理日期：**2026-11-14，Asia/Shanghai**。本批星辉界面已由用户在本机验收，并获合并与试用发行授权。专项功能的真实游戏覆盖仍分别记录；下方历史测试不会因界面通过而自动转为通过。

## 先分清版本

| 模块 | 当前开发源码 | 本地元数据记录的公开版 | 当前边界 |
| --- | --- | --- | --- |
| 微信式聊天 MyForeverChat | 0.10.0 | 0.10.0 | 本批界面获用户验收；实际消息流程仍按验证记录 |
| 商业技能助手 MyForeverProfessions | **0.5.0** | **0.5.0** | 本批授权试用发行；矿名等专项仍待实测 |
| 世界向导 MyForeverNavigator | **0.5.0** | **0.5.0** | 本批界面获用户验收；NPC流程仍待专项实测 |
| 目标选择 MyForeverTargets | **0.2.0** | **0.2.0** | 星辉UI与唯一名称战斗桥接候选；探针默认关闭 |
| 玩家行为采集 MyForeverCoach | 0.2.1 | 同批GitHub发行 | 本机采集；手动安装 |
| 宏工坊 MyForeverMacros | 0.2.3 | 同批GitHub发行 | 手动安装 |
| 随身手册 MyForeverFieldKit | 0.1.1 | 同批GitHub发行 | 手动安装 |
| 桌面管理器 | **0.4.0** | **0.4.0** | 午夜深色、四插件管理及本机行为统计 |

本表为本批发行版本。实际部署标识与公网校验见 `PersonalAddons/releases/ui-20261114-RELEASE.md`；更早版本及模拟/实机记录按日期保留，不能覆盖当前版本或扩大验证范围。

## 已验收 / UX-001：星辉 UI 与统一布局

**2026-11-14 用户结论：** 安装 `4d91623` 候选并进入游戏后，用户明确回复“没问题，合并到main，并发布吧。官网和app一起更新了”。本批 UI 验收通过，允许合并与试用发布，GitHub #1 关闭为 completed。

七插件统一星辉样式，`/myui` 提供布局网格、吸附与微调；聊天有午夜主题，官网和管理器统一深色视觉。保留已有位置与设置。此前“不满意”、阶段候选与未编译记录是历史过程，详见 `docs/UX-001-UNIFIED-STYLE.md`、`docs/UX-002-GAME-UI-LESSONS.md`、`docs/UX-003-XINGHUI.md`。

用户界面接受不代表所有窗口/分辨率已由 Codex 独立实看，也不代表矿点、战斗焦点、社区消息或跨平台专项通过。以后发现的具体布局问题按实际截图与操作另开，继续保持主画面干净、正文优先，并保留已验收的拉伸与技能书能力。

## P1 / MFP-001：新客户端小地图资源读名仍未修通

**现象：** 专业技能、训练师等功能和采集实验是不同模块。全小地图范围自动报矿在 dev.22 当前会话仍未通过；真实客户端 tooltip 文本触发保护，不能把空值、旧悬停缓存或 secret 值当作新发现。

**最后一轮记录：** dev.22 已真实重载，客户端 `1.60.1 / 70938 / Interface 16001`。debug 为 `restricted / restricted-text`；10 次读取：Nil 1、Empty 8、Invalid 1，raw/accepted 均空。它只证明本次 tooltip 文本受保护，不证明所有客户端 API 或所有矿点都不可读。进入限制后应归还地图与输入状态，并保持本会话暂停读名。

**已经修过：** 替身自有 Frame 的 alpha 实际读回存在 8 bit 量化；dev.22 将预期值先量化到 1/255，再校验，0/1 端点仍严格检查。修复后确实到达采样阶段，但没有解决受保护矿名。dev.21 的真实近处铜矿 HUD/闪光可见、提示音调用两次，不能继承为 dev.22 的实际听感或发现验收。

**仍待验收：** dev.22 新矿近处弹窗和提示音、实际听感、右键转视角、持续消闪、黄点连续性、提醒/声音/闪光开关保持。旧矿当时已被其他人采走，没有用旧缓存补通过。当时记录状态为 `NOT_ACCEPTED / userApproval=pending / release=false`。2026-11-14 用户另行授权本批 UI 试用发行，未验收专项继续 open。

**2026-11-14 0.5.0 随批试用（功能未实测）：** 不再要求读出矿名，改为把受保护的名称直接交给字体串显示。官方接口文档（70888）标注 `FontString:SetText` 接受受保护参数。实现、取舍与两分钟实机确认步骤见 [加密矿名直显](docs/MFP-001-SECRET-NAME-PASSTHROUGH.md)。本问题保持 open。

**代码入口：** `MyForeverProfessions/GatherCursorScan.lua`、`GatherScan.lua`、`GatherStandIn.lua`、`GatherAlerts.lua`、`Main.lua`；模拟见 `professions_cursor_scan_test.lua`、`professions_standin_test.lua`、`professions_scan_router_test.lua`。

**下一步与通过条件：** 先证明当前 build 存在公开且新鲜的名称来源；没有来源就保持明确降级，不反复搬图重试。矿点、点击、战斗/死亡/地图变化/异常中的原地图和输入恢复必须真实测试。替身要有真实可绘制地形和玩家箭头，无可用画面不得以黑框启动。只提醒资源名称与声音，不做资源方位或导航。保留已验收的窗口拉伸、顶部技能书及原设置。本批 UI 试用发行已有授权；后续若宣称本专项修复，仍需新增真实验收证据。

**证据：** `PersonalAddons/PROFESSIONS-VALIDATION.md`、`work/professions-upstream-20261113/PLAN.md`、`UPSTREAM.json` 与该目录的 dev.22 哈希清单。原机 runtime JSON 保持私有，未随 Git 发送。NodeSight 上游 3.0.0 移除了扫描/声音，并非现成修复；上游判断与本机事实分别保留。

## P1 / MFT-001：战斗中任意同名怪物自动精确设焦点尚未解决

**要求：** 玩家对列表里的怪物操作后，由插件自动匹配并确认对应 GUID，不能误选另一只同名怪，也不能改为让玩家人工确认。

**现状：** 脱战多次右键的逐次选择、普通 Lua GUID 核验及原目标恢复已有真实阳性，是公开 0.1.46 的有限功能基线。战斗中的安全执行环境缺少已证实可用的任意 NPC 实时身份判定/操作路径。预建按钮、普通 Lua 能读 GUID、姓名板视觉高亮，均不能单独补齐这个边界。已审查的其他插件没有给出满足完整需求的可迁移实现。

**本机 0.1.45：** 新增默认关闭的 `NativeScaleProbe`，仅显式命令启动；研究缩放是否能扩展真正的 C++ 命中范围。模拟已通过，但尚无游戏内命中、恢复及同点对照验收。它不设目标/焦点、不施法，不能写成战斗修复。不要默认打开探针或重复旧的巨大姓名板映射方案。

**代码入口：** `MyForeverTargets/FocusCycle.lua`、`FocusAPIProbe.lua`、`NativeScaleProbe.lua`、`Mouseover.lua`、`NearbyCast.lua`、`CombatCast.lua`。

**通过条件：** 先拿到当前客户端中真实鼠标身份/安全身份判定证据，再研究实际战斗内焦点。必须证明具体 GUID 一致、原目标正确恢复、硬件操作可达且无错误同名选择。模拟通过不能关闭此问题。

**证据：** `TARGETS-VALIDATION.md` 开头、`research/combat-focus-70888-20261112/PLAN.md`、`SCALE-PROBE.md`、`OTHER-ADDONS-AUDIT.md`、`research/focus-api-70862-20261111/CURRENT-FOCUS-CONCLUSION.md`。

## P2 / MFT-002：悬停施法与焦点恢复的实测覆盖有限

附近友方“脱战悬停格子、按原普通技能键、恢复原目标”有用户实测成功，但采用临时选中方案，不能宣称通用原生 `@mouseover` 已修复。敌方与敌人目标条的实际施法/恢复、战斗悬停、原目标为空的合并流程以及更多步完整恢复仍未完整验收。原生队伍等已支持单位与任意附近 NPC 不能混为一类。

历史公开 0.1.46 从 0.1.44 功能基线冻结，排除了本机 0.1.45 探针。本批 0.2.0 加入统一界面与唯一名称桥接候选，专项实测状态未因此改变。公开源码及独立测试位于 `work/targets-0.1.46-release-root`；该目录是明确保留的生产基线，不覆盖当前本机源码。进一步开发需分别记录初始目标为空/非空、同名多个单位、战斗中断、恢复失败、第三方插件接管等场景。

## P2 / MFN-001：世界向导 0.5.0 的 NPC 与专业训练师流程待专项实机验收

当前增加 `QuestieCatalog.lua`，从已安装 Questie/QuestieDB 只读、分批建立 NPC 目录。保留原有 427 点、收藏 ID、任务导航与 300×84 HUD；无 Questie 时降级为原目录。不能分发整个 Questie 数据库，也不能把参考坐标称为 NPC 实时追踪。

0.4.1 新增独立“专业训练师”，按 12 个专业细分并提供搜索别名；根据训练功能标记与完整中英文头衔共同识别，材料/技能书商人不混入。6 位原精选专业 NPC 以副成员加入专业分组，保留旧 ID 和特殊主分类。模型地图的真实库集成返回 305 个专业训练师点位（299 个专业主分类和 6 个精选副成员），每专业一个样例覆盖搜索、收藏和开始导航；这不是游戏实际站位、可教技能或角色专业条件的验收。本次 UI 验收不关闭 MFN-001。

当前离线实际库集成记录：读取 QuestieDB 1.1.0 的 50 个 Lua 文件，建得 9,902 个参考记录 / 9,006 个不同 NPC / 50 个模型地图 ID；地图 API 为建模值，角色相位/策略未完整加载，不能写作实机覆盖数或性能保证。早期预检曾得到更高的计数，不能覆盖当前过滤后的结果。现有模拟覆盖延迟就绪、分类、去重、收藏与降级。

**仍待做：** 当前角色加载后的目录就绪、专业入口实际显示、原生地图有效性、动态相位、目标 NPC 搜索与收藏重载、真实按钮点击/方向/实际行程，以及专业 NPC 的实际站位、可教技能和专业条件。实际数据库结果可能随来源版本与角色改变。核心入口 `QuestieCatalog.lua`、`Provider.lua`、`Classification.lua`、`UI.lua`、`Main.lua`；工具 `audit_navigator_questie.py`、`verify_navigator_questie.py`。见 `work/navigator-0.4.1/PLAN.md`、`actual-db-integration.json` 与 `profession-title-audit.json`。

## P2 / MFM-001：管理器跨平台与自动周期未完整真机验证

本批源码和公开试用包均为 0.4.0，包含午夜深色界面、四插件管理与本机行为统计。管理器自身不会自动升级，旧用户需从官网重新下载替换；本机应用已更新，用户设置保留。

**未完成：** Windows x64、Intel Mac 原生界面/目录权限/安装运行；完整 30 分钟检查及退出游戏后 60 秒重试等待；Windows Authenticode、Apple Developer ID 和公证。Mac 当前为本地临时签名。跨平台编译和隔离测试不代表对应真机验收。

**行为统计边界：** SavedVariables 通常 `/reload` 或退出才写盘；桌面不能读取尚未写盘的事件。分日固定 UTC+08:00，保留 90 天日累计，旧采集片段有缺失；静止不是挂机，施法失败不是误操作。采集器与自动本机分析不采集按键/聊天/姓名/GUID，不上传行为数据；新候选可选 AI 的发送范围另见 MFM-002。跨日、战斗、死亡、任务、容量等需要对应真实场景，不可从一次自疗及导入测试推定全部通过。

**入口：** `Manager/Core/UpdateService.cs`、`GamePaths.cs`、`BehaviorDataService.cs`、`BehaviorLuaReader.cs`、`Desktop/BehaviorStatisticsView.cs`；测试使用隔离目录。见 `Manager/README.md`、`BEHAVIOR-CONTRACT.md`、`BEHAVIOR-VALIDATION.md`。

## P2 / MFM-002：行为洞察与可选 AI 复盘候选待实际验收

来源 Claude `7214d62`，当前候选在 `codex/behavior-insights-ai-20261115`，基于已发布 `5392bd7` 整合，Manager 0.4.0 / Coach 0.2.1 仅为当前源码标识。新功能尚未包含在同号公开包，后续公开需另升版本。与 PR #10 独立。

已复现并修复区域经验错记旧地图、默认 HTTP 307 转发摘要；另补齐正文期限、预览快照与旧请求取消、供应商密钥交接和深色对比。Manager Release 0 警告/错误，47 行为/AI、68 隔离更新及七插件 72 组 Lua/19 Python 检查通过。首次作者 44 项也曾独立通过。

仍需游戏区域/跨日、新旧数据、桌面 AI 启用/停止/刷新/过滤切换、真实本机或远端模型、完整超时、Windows/Intel Mac 真机。CUA 未能绑定命令行候选窗口，因此无本轮原生视觉/点击通过记录；模拟启动后已停止，没有向真实模型发送数据。保留数据少、不完整、非战斗死亡和施法事件口径，不能把战斗结束说成击杀。

见 [完整交接](docs/HANDOFF-2026-11-15-behavior-insights-ai.md) 与 `PersonalAddons/work/behavior-insights-ai-20261115/VALIDATION.json`。未改已安装应用、游戏目录、公开包或官网。

## P2 / MFC-001：真实聊天交互和社区收发仍需专项实测

聊天 0.10.0 的本批 UI 已由用户接受，旧紧凑泡泡保留正文优先方向。真实前后翻组按钮、硬件点击与社区收发仍需专项验收；历史实机图和离线预览不能替代当前功能覆盖。

普通角色好友离线私聊留言没有实现；现有角色社区与战网历史不能表述为通用离线消息服务。入口 `MyForeverChat/UI.lua`、`Notifications.lua`、`Communities.lua`、`History.lua`；见 `CHAT-VALIDATION.md`。用户持续要求主画面干净、正文突出，继续修界面时保持这个方向。

## P2 / DEV-001：历史入口、外部依赖和发行资料的复现边界

- 旧 `PersonalAddons/run_tests.py` 会执行 `details_truncation_test.lua`，缺少未收录的第三方 Details 就报错。本次已复现。新入口 `tools/check_addons.py` 覆盖七个自研插件，明确排除此旧第三方测试；原测试和自研修补 diff 仍保留。不要把旧入口失败说成七个插件都失败，也不要把缺失测试假记为通过。
- 发行 ZIP、桌面运行时和 SDK 不入 Git。运行管理器安装回归、官网校验/发版回归前，按 README 恢复对应公开包，校验大小与 SHA-256。新加 `tools/restore_release_assets.py` 只做这件事；早期仅有 changelog、没有包元数据的条目会明确列为 `HISTORY ONLY`。
- 导航数据生成器和真实库审计依赖外部参考资料/已安装 QuestieDB；本仓库保留生成器、来源和已生成数据，不收录整套下载来的第三方插件/资料实现。按 `NAVIGATOR-SOURCES.md` 的固定来源恢复输入后才能重新生成，不能把缺输入叫作代码已坏。
- 原始截图、角色存档、会话日志、数据库与账号配置留在原机。历史文档可能引用未共享的路径，交接以本次整理的结论和可提交源码/模拟为准；需要复查现场时另行生成脱敏证据。
- 现有部署脚本依赖原维护环境的服务器路径与 SSH 身份；本仓库不提供私钥，不自动部署。官网每个模块独立版本、旧 ZIP 不覆盖、四张插件卡片保持同步。

本次新执行的检查及明确排除项见 [HANDOFF_VALIDATION.md](docs/HANDOFF_VALIDATION.md)。UX-001 本批已验收；当前优先补齐 MFP-001、MFT-001 的能力可行性证据，其次是 MFN-001 与 Windows 真机验证；不要用重复无效探针或放宽身份准确性来关闭 P1 问题。
