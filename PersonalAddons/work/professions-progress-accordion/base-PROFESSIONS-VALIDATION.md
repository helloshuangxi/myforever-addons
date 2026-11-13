# MyForeverProfessions v0.1.1 验证记录

日期：2026-11-06（北京时间）。状态：**本机试用版，已完成部分真实角色验收**。

## 本轮实际游戏观察

在当前已登录角色、真实无限服客户端内完成以下对照，没有注入测试配方或虚构背包数据：

- 插件已正常加载并常驻显示；助手采矿点数 **3/75**、距当前上限 **72 点**，与原生采矿窗口 **3/75** 一致。
- 唯一观察到的训练推荐为橙色 **熔炼铜锭**。原生专业窗口显示同名配方，助手识别其为制造配方并显示材料。
- 铜矿石：助手显示 **需要 1／已有 0／缺少 1、材料可做 0 次**，与原生配方材料 **0/1** 一致。未消费材料或购买物品。
- 在真实客户端通过 `/myprof scale 1` 从 75% 改为 100%，面板大小与百分比更新；`/reload` 后 100% 设置恢复。
- `/reload` 后配方仍保留并正确标为「上次记录 · 当前颜色待确认」。专业窗口关闭时助手仍显示。
- 发现 UI 的 `›` 字符在当前游戏字体中显示方框；v0.1.1 改为 ASCII `>`，已重载并观察到顶部排序、专业入口和候选前缀正常显示。

鼠标控制工具多次返回 `noWindowsAvailable`，且工具点击坐标与游戏 `GetCursorPosition()` 不一致，不能将相关点击或拖动尝试算作插件交互通过。已向用户请求手动协助确认拖动和按钮／Ctrl 滚轮缩放。为诊断切换过窗口模式；实际结论以完成后的记录为准。

## 已完成

- 本机 `.build.info`：`wowf 1.60.1.70790`；新插件声明 `Interface: 16001`。
- 4 个 Lua 源文件通过 Lua 5.1 编译检查。
- **448 项独立模拟检查通过**：Core 77 项、API/events 188 项、UI 48 项、真实四模块联动 135 项。
- 12 个当前客户端商业技能识别；GetProfessions 中间 nil、未就绪空结果、无专业、遗忘专业、角色独立存档和缓存恢复。
- 已学可涨点项目严格按橙→黄→绿排序；红色、灰色、未学、不可用和冷却中项目不入推荐；同色材料齐全优先。
- 单次制造材料、背包数量参数、缺口、重复材料合并、可替代材料、明确可选材料排除、缺失材料数据不虚构数量；采集项目不显示制造次数。
- 筛选列表合并缓存，API 返回数组不被修改；逐条检查专业归属；外来链接、公会与 NPC 数据源排除；切换数据源期间禁止扫描。
- 技能变化后缓存失效；背包事件只更新材料；关闭原生窗口后助手仍显示；战斗暂停、脱战恢复、可见时每 5 秒刷新已知冷却与材料。
- 常驻界面、标题拖动、锁定、折叠、滚动、65%–160% 缩放、位置和设置恢复、各命令回调与完整材料布局逻辑。

运行：

```bash
PersonalAddons/.venv/bin/python PersonalAddons/run_professions_tests.py
```

项目统一测试入口 `run_tests.py` 已包含新插件语法检查。首次完整项目回归在另一个插件 `MyForeverMacros/PaladinSeal.lua` 的测试桩缺少 `SetAlpha` 时中断；本次未修改该插件，不能据此声称完整项目回归通过。上述 448 项为商业技能助手的独立验证结果。

## 原生接口依据

研究快照与 URL/SHA-256 清单位于 `research/professions-2026-11-06/`。使用的是暴雪原生 UI 源码的 Gethe 第三方镜像，不把镜像分支等同于本机二进制逐文件一致。

- [Forever 专业总览](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProfessionsBook/Camelot/Blizzard_ProfessionsBook.lua)：角色专业、技能点和上限。
- [专业 API 结构](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua)：真实颜色、采集项目、配方材料槽、项目熟练度字段。
- [原生专业实现](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProfessionsTemplates/Blizzard_Professions.lua)：过滤列表、归属校验、外来数据源、冷却和采集专业分类。

## 尚未覆盖的实际验收

1. 其他角色、其他已学专业；当前只对照了采矿，不能声称 12 个专业均已游戏实测。
2. 多配方、橙黄绿混合排序与纯采集项目；本角色当前仅有单一熔炼推荐，没有实际样本覆盖其他颜色。
3. 获得／消耗材料后核对缺口；成功涨点后检查下一点目标和颜色更新；打开他人专业链接时本角色推荐不受污染。
4. 实际拖动、滚轮、缩放、中文长材料名与小屏幕布局；重新登录和换角色检查设置隔离。

本轮已操作真实客户端并重载 UI；上述没有实际样本的项目仍不能由模拟检查替代。不宣称确定的升点概率、剩余制作次数或客户端不返回的资源难度。

## 交付范围

已安装在本机 `Interface/AddOns/MyForeverProfessions`。v0.1.0 旧包保留，v0.1.1 交付包为 `dist/MyForeverProfessions-0.1.1-Trial.zip`。包只含本插件代码、MIT 许可及说明，不含 WTF、SavedVariables、其他插件或个人游戏数据。本次为商业技能插件本机试用更新，未发布到聊天插件官网。
