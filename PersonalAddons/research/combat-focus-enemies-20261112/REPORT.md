# 敌人列表插件的战斗焦点与 GUID 核验：源码复核

2026-11-12。目标客户端是 Forever 1.60.1 build 70888；需求是玩家点击指定怪物格子后，插件自动核验 GUID，准确设置焦点，同名怪也必须区分。本报告没有把人工确认方案算作满足需求。

只审查第三方源码，不安装、加载或执行。游戏 AddOns、SavedVariables 和运行状态未修改。关键源码按原始字节复制，文件名、换行与行号不变；精确版本、来源 URL、SHA-256 见 [SOURCE.json](SOURCE.json)。其中两个 All Rights Reserved 项目只作本机研究资料，不得随插件公开发行。

## 结论矩阵

| 项目与固定版本 | 实际目标/焦点派发 | 身份或 GUID 判断位置 | 对 70888 自动精确焦点的结论 |
|---|---|---|---|
| Enemy Frames 1.3.0，CurseForge file 9335612，2026-10-26 | `Clicking.lua:38–45` 脱战放大真实姓名板；`:169–179` 将原生姓名板的命中区钉到列表代理区，点击最终交给游戏的真实姓名板。 | `Frames.lua:768–775` 的 `UnitIsUnit` 只画当前目标/焦点边框；完整发行包静态检索没有 `UnitGUID`、`FocusUnit` 或 `/focus` 设焦点实现。 | 作者当前主页仍报告新版更新后点击失效。1.3.0 没有新增派发路线，更没有右键焦点的 GUID 闸门；不能复用为已验证的战斗焦点修复。 |
| Enemy Grid v9.1.5.055，commit `aed42946c1307b11df1c537a41bf84788e58e6fb`，2022-01-15 | `EnemyGrid.lua:1428–1446` 预建固定 `nameplate1…40` 安全按钮；`:2243–2248` 预置 `/target [@mouseover]`，其他技能也依赖 `@mouseover`。 | `:1851–1854` 普通 Lua 保存 GUID；`:1719` 用于宠物过滤，`:2593–2597` 用于任务 tooltip。没有将 GUID 比较结果输入安全动作，没有自动 GUID 焦点状态机。 | TOC 为 90105，发行页只列旧 Retail 版本。没有 Forever/70888 适配或原生实测证据；旧姓名板 token 和 mouseover 行为不能直接作为当前方案。 |
| AKForeverTargeter v0.3.0，commit `3ff16128fd87f7072c4addb59c4e3697d5244a27`，GitHub release 2026-11-08 | `Panel.lua:134–155` 是清目标、按名字 `/targetexact`、标记、没找到时返回上一目标；`:169–196` 逐个尝试不同名字。`:735–739` 右键安全动作是 `ATTRIBUTE_NOOP`，`:766–773` 右键只交给普通 Lua 隐藏/降序。 | 下载审查全部九个 Lua 模块后，没有发现 `UnitGUID`、`UnitIsUnit`、`FocusUnit` 或 `/focus`。同名选择局限直接写在 `Panel.lua:123–126`。 | 比此前的 0.2.4 更新，但新版本仍按名字选择，未添加焦点或 GUID 自动确认。TOC16001 不等于 70888 已验证，发行时间早于 70888 源码提交。 |

**本轮没有找到这三个项目中可满足要求的新实现。** 它们的安全动作配置、名单显示、焦点高亮与实际设置焦点是不同能力，不可相互代替。未把下载、模拟或作者支持版本标签当作 70888 原生验收。

## Enemy Frames：原生命中区上下文

- [Core.lua](EnemyFrames/Core.lua):23 将 `GIANT` 定为六倍屏幕较大边。它依赖改变真实姓名板尺寸，而不是为 GUID 创建安全单位别名。
- [Clicking.lua](EnemyFrames/Clicking.lua):38–45 的尺寸设置在战斗中直接返回；`:102–115` 创建属于真实姓名板的 proxy/box，`:140–147` 保持原生条及堆叠框。
- `Clicking.lua:169–179` 查询 `C_NamePlate.GetNamePlateForUnit(unit)`，检查 `CanChangeHitTestPoints()`，然后以 `SetAllHitTestPoints(parts.proxy)` 重定向原生命中区。
- [EnemyFrames.lua](EnemyFrames/EnemyFrames.lua):70–72 挂到 Blizzard 的姓名板添加、选项与尺寸更新回调。`Clicking.lua:213–222` 在姓名板加入后重新附着；这没有新增安全 GUID 读取函数。
- [Frames.lua](EnemyFrames/Frames.lua):774–775 的 `UpdateFocus` 仅决定金色边框是否可见。名字叫 focus 的纹理和更新函数，不是焦点 setter。
- [当前作者页面](https://www.curseforge.com/wow/addons/enemyframes)与 [1.3.0 发行页](https://www.curseforge.com/wow/addons/enemyframes/files/9335612)提供版本及现有故障说明。作者页面的“新版更新”未注明精确 build，不能扩大为 70888 的官方结论。

## Enemy Grid：单位引用与宏

- [EnemyGrid.lua](EnemyGrid/EnemyGrid.lua):1428–1446 使用 `SecureUnitButtonTemplate`，每个按钮在创建时固定 `unit=nameplateN` 并注册单位观察。
- `:2195–2200` 在战斗中只安排以后更新键位。`:2231–2248` 生成宏动作和 mouseover 目标宏，`:2352–2357` 在脱战配置阶段写入安全属性及进入事件的绑定片段。
- 原文件的 `UnitGUID` 读取不在安全片段里，保存的 GUID 不控制是否允许设焦点。用户可自填宏，但仍依赖客户端实际提供的 mouseover。
- [固定源码](https://github.com/Tercioo/EnemyGrid/blob/aed42946c1307b11df1c537a41bf84788e58e6fb/EnemyGrid.lua)和 [发行页](https://www.curseforge.com/wow/addons/enemy-grid)可复核；本目录 [TOC](EnemyGrid/EnemyGrid.toc) 保留 Interface 90105。

## AKForeverTargeter：名字目标与右键的实际含义

- [Panel.lua](AKForeverTargeter/Panel.lua):123–126 明确说明名称选择不能要求第二只同名个体。`:134–155` 的宏只接受名字与标记参数，没有 GUID 参数。
- `:735–739` 将右键安全动作设为空操作；`:766–773` 的右键逻辑是列表操作。不能因它在战斗中能点目标/标记，就推断它实现了战斗设焦点。
- `:953–959` 战斗只跑显示更新，`:869–895` 生成并写入安全宏的工作留到完整同步阶段。
- [v0.3.0 发布](https://github.com/ajkatz/AKForeverTargeter/releases/tag/v0.3.0)与 [固定 Panel.lua](https://github.com/ajkatz/AKForeverTargeter/blob/3ff16128fd87f7072c4addb59c4e3697d5244a27/Panel.lua)可复核；[MIT 许可](AKForeverTargeter/LICENSE) 从同一提交的原始 LICENSE 复制。

## 复核方法和资料边界

1. 按 SOURCE.json 核对逐文件 SHA-256，不以本报告改写或截取第三方源码，因此上述行号可直接复核。
2. 用文本检索定位 `SetAttribute`、`macrotext`、`FocusUnit`、`/focus`、`UnitGUID`、`UnitIsUnit`、`SetAllHitTestPoints` 与 `InCombatLockdown`，再读派发及调用上下文。
3. Enemy Frames 保存了原生命中区实现、调用回调、常量和显示焦点的区分；Enemy Grid 保存完整主文件；AK 保存实际派发主文件及原许可。未将源代码复制到游戏 AddOns。
4. 这里没有新的真实游戏操作，没有宣称能够从导出的 Lua 源码排除一切未公开引擎能力。结论是所列当前版本未提供所需实现，而不是证明任何未来客户端都不可能支持。
