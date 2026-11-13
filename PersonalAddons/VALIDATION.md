# 验证记录

日期：2026-11-05。目标：本机无限服 1.60.1.70790 / Interface 16001。

## 2026-11-06：本机 v0.2.2 圣印提醒样式与淡出

按用户反馈，将680×118常驻黑底提醒改为340×70的窄条、40像素图标、24号暖金标题、14号快捷键提示，背景两端渐隐。0.2秒淡入、保持2秒、1.3秒淡出，3.5秒自动隐藏；一次缺失只提醒一次，不被无关UNIT_AURA、UNIT_FLAGS、SPELLS_CHANGED或重复on刷新。补上后再次消失才重新触发；死亡、飞行、载入、off取消动画并清理OnUpdate。

已在当前骑士客户端执行安全脱战重载，实看中文样式与 `/myseal test`。客户端定时读取帧：0.1秒显示/alpha约0.3725，0.3秒显示/alpha=1，2.8秒显示/alpha约0.5725，3.6秒隐藏/alpha=0/OnUpdate=nil；预览结束后没有常驻缺失提示。未在此次验收中施放或取消真实圣印，真实增益事件的反复触发仍为模拟覆盖范围。

`paladin_seal_test` 更新为150项检查；宏工坊64项与牧师61项检查保留。完整 `run_tests.py` 通过。v0.2.1文件保留于 `backups/MyForeverMacros-0.2.1-before-fade-alert`。本次仍为本机更新，宏正文和其他插件源码未改。

## 2026-11-06：本机 v0.2.1 骑士圣印提醒

已在安装目录加入 `PaladinSeal.lua`，TOC 引用与 `MyForeverSealDB` 每角色设置声明检查通过。当前骑士的 `AddOns.txt` 中 MyForeverMacros 已启用。旧宏工坊文件备份于 `backups/MyForeverMacros-0.2.0-before-seal-alert`；此次未生成或覆盖分发 ZIP，未修改游戏内宏、动作条或快捷键。

执行 `PersonalAddons/.venv/bin/python PersonalAddons/run_tests.py`：20 个 Lua 文件语法检查通过，现有全部模拟检查通过。其中 `paladin_seal_test` 49 项、宏工坊 64 项、牧师 61 项。圣印检查覆盖初始缺失、不同等级及同名增益、其他单位事件过滤、消失/补回、死亡/复活、飞行/落地、载入/返回世界、每角色开关、5秒预览、缺失API保守隐藏及非骑士/未学技能不提示。

已做独立代码检查：提醒不拦截鼠标，不调用施法或改写安全动作的接口。当前游戏停在登录前提示页，尚未完成本版的角色内加载、中文字体与尺寸、真实圣印消失/补上时序验收。此前角色内验证的技能说明为圣印持续30秒、审判不会消耗圣印；该观察不代表新增提醒已实测。

## v0.2.0 牧师版

执行 `PersonalAddons/.venv/bin/python PersonalAddons/run_tests.py`，5 个 Lua 文件语法检查及 **161 项模拟检查通过**：

```text
Lua 5.1 syntax: 5 files passed
fieldkit_test: 36 checks passed
MyForeverMacros: 64 checks passed (Lua Lua 5.1)
priest_test: 61 checks passed
All simulated checks passed. In-game acceptance remains required.
```

新增检查覆盖 11 条牧师预设、不同技能等级的同名匹配、本地化名称、未学技能拒绝、非牧师拒绝自动填写、治疗技能优先次序、友敌驱散分离、复活死亡条件、牧师页跳转、真实 UI 回调创建流程和切换到未学技能后清除旧宏拾取状态。

## v0.1.0 初版记录

执行：`PersonalAddons/.venv/bin/python PersonalAddons/run_tests.py`

```text
Lua 5.1 syntax: 4 files passed
fieldkit_test: 36 checks passed
MyForeverMacros: 54 checks passed (Lua Lua 5.1)
All simulated checks passed. In-game acceptance remains required.
```

运行时：Lupa 2.6 的 Lua 5.1。测试模拟 WoW API 与 UI 事件，不启动游戏。

已修复测试／审查发现的问题：Lua 5.1 `%c` 在本机 locale 下误判 UTF-8 中文字节；改为显式 ASCII 控制字符范围，并让 trim 使用 ASCII 空白。宏预览或名称变化后取消旧宏拾取资格，避免拿到上一条宏。

打包检查：两个已安装 TOC 均为 16001，引用文件存在；ZIP 完整性检查通过；文件 SHA256 清单在 `dist/SHA256.json`。

未验证：真实客户端加载、UI 渲染、技能施法、角色宏同步、地图可用性、重登后位置恢复。现有插件和账号配置未修改。
