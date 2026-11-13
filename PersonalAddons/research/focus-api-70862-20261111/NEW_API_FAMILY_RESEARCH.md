# 70862 新原生入口检索：GUID、软目标与姓名板

记录日期：2026-11-11。此报告只检索公开 Lua 接口与第一手问题报告，没有修改插件或游戏状态，没有新的游戏实测。

## 当前结论与边界

在本报告列出的精确构建 API 家族中，未找到把任意已知 NPC GUID 写入硬目标、焦点或 `mouseover` 的公开函数，也未找到创建任意单位别名的公开函数。这里的“未找到”只表示已检索文件和函数声明的结果，不能据此证明客户端内部不存在其他入口。

`softenemy`、Gamepad targeting、地图上的 UnitPositionFrame、`SetPreferredGamepadInteractTarget` 均没有给出一个接收任意 GUID 并提交硬目标/焦点的声明。它们目前不能作为“同名怪直接右键格子设焦点”已经可行的新方案。尤其不能把模拟器实现或接口名称的推测当作客户端实测。

本次没有重复已失败的 `FocusUnit(nameplateN)`、原始 GUID、`TargetUnit(nameplateN)` 或原生姓名板命中区搬移测试。既有测试以同目录 `PLAN.md` 为准。

## 精确来源与检索范围

使用 Gethe 的 Blizzard 导出界面源码镜像，固定提交：

- [`9dc84f0d3bbae1768ac3405b3716000bd93eda06`](https://github.com/Gethe/wow-ui-source/commit/9dc84f0d3bbae1768ac3405b3716000bd93eda06)，版本为 1.60.1 (70862)。
- 文档目录：`Interface/AddOns/Blizzard_APIDocumentationGenerated/`。
- 通过该提交 Git tree recursive API 检索文件路径，响应 `truncated=false`；筛选 target / soft / plate / interact / guid / unit 相关文档。没有发现 `TargetInfoDocumentation.lua`、`SoftTargetDocumentation.lua` 这些独立文件名；这项路径检索不能排除别的文件里出现同名标识。
- 读取下表各文件的函数声明。`UnitDocumentation.lua` 还筛选了名称中带 soft / guid / token / target / set 的全部函数；`UnitSharedDocumentation.lua` 与 `SharedScriptObjectUnitPositionFrameDocumentation.lua` 没有函数声明。
- 未完成整仓源码正文的穷举检索：整包网络下载耗时较长而中止，没有把未完成下载计入证据。

| 已读取的精确构建文件 | 实际公开内容 | 对所需操作的含义 |
| --- | --- | --- |
| [`TargetScriptDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/TargetScriptDocumentation.lua) | `FocusUnit(name)`、`TargetUnit(name, exactMatch)`、最近/上一目标、方向选敌、`SetPreferredGamepadInteractTarget(unit)` 等 | 未声明 `SetFocusByGUID`、`SetTargetByGUID` 或 GUID 参数的硬目标提交入口。 |
| [`GamepadTargetingDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/GamepadTargetingDocumentation.lua) | `C_GamepadTargeting.Enable()`、`Disable()`、`SetFilter(filter)`；过滤器为 Hostile / Friendly / All | 该构建的函数没有单位或 GUID 入参。`Disable()` 返回 `targetAlreadySelected`，并没有声明一个指定单位的选中操作。 |
| [`SoftTargetConstantsDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SoftTargetConstantsDocumentation.lua) | 只有 `SoftTargetEnableFlags` 枚举 None / Gamepad / Kbm / Any | 没有 setter，也没有 GUID 到软目标的映射函数。 |
| [`NamePlateManagerDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateManagerDocumentation.lua) | Get/SetNamePlateHitTestInsets、IsNamePlateUnitBehindCamera、SetNamePlateSimplified；姓名板事件 | 设置函数操作命中区域或外观，不接收 GUID 以设目标。文档还明确命中区域被限制在姓名板边界内。 |
| [`NamePlateDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua) | GetNamePlateForUnit、GetNamePlateSize、GetNamePlates、SetNamePlateSize | 查对象和改尺寸，没有焦点或目标 setter。 |
| [`FrameAPINamePlateDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPINamePlateDocumentation.lua) / [`SharedScriptObjectNamePlateFrameDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedScriptObjectNamePlateFrameDocumentation.lua) | 姓名板脚本对象/命中区域相关声明 | 没有发现新的 GUID 选中或焦点接口。 |
| [`UnitDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) | `UnitGUID`、`UnitTokenFromGUID`、若干 FromGUID 读取；SetPortraitTexture、SetPortraitTextureFromCreatureDisplayID、SetUnitCursorTexture 等显示函数 | `UnitTokenFromGUID` 是读取 token；文档没有“创建新 token / 注册任意 GUID 别名”的函数。画像和光标纹理 setter 不能被等同于单位选择。 |
| [`UnitSharedDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitSharedDocumentation.lua) | 共享类型，无函数声明 | 未提供新的目标操作入口。 |
| [`FrameAPIUnitPositionFrameDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPIUnitPositionFrameDocumentation.lua) | AddUnit(unitTokenString, asset, ...)、GetMouseOverUnits()、地图/颜色/ping 函数 | `GetMouseOverUnits` 返回此绘图对象中的单位 token，不是写入全局 `mouseover` 的 setter。没有在此文件发现硬目标/焦点操作。后一句是声明范围结论，不是对新 frame 的运行测试。 |
| [`SharedScriptObjectUnitPositionFrameDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedScriptObjectUnitPositionFrameDocumentation.lua) | 脚本对象共享声明，无函数 | 未提供新的目标操作入口。 |
| [`ImmersiveInteractionManagerDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ImmersiveInteractionManagerDocumentation.lua) | `HasImmersiveInteraction()` | 查询功能是否可用，没有指定对象或 GUID 的操作。 |

## 看似相关但不足以构成方案的入口

### SetPreferredGamepadInteractTarget

精确构建 `TargetScriptDocumentation.lua` 的参数是可为空的 `UnitToken`，并标注 `HasRestrictions = true`、`SecretArguments = AllowedWhenUntainted`。它没有 GUID 参数，文档也没有承诺该调用设置硬目标、焦点或普通鼠标悬停单位。因此，不建议把它接到右键焦点功能里并让用户重复验证。

同时找到两个 Forever 开发者/玩家的第一手问题报告：

- [2026-10-01：空插件斜杠指令也触发原生 gamepad blocked-action 循环，构建 70124](https://us.forums.blizzard.com/en/wow/t/game-crashes-native-gamepad-ui-empty-addon-triggers-blocked-action-popup-loop/2367777)。作者给出最小插件和 `ClearChat → Hide → SmartNavigation → UpdateInteractIcons → SetPreferredGamepadInteractTarget` 调用链。
- [2026-10-02：Forever gamepad UI 问题，构建 70170](https://us.forums.blizzard.com/en/wow/t/wow-forever-gamepad-ui-bugs-build-160170170/2370253)。报告同一保护调用的污染循环；有其他用户复现回复。

这些是较早构建的第一手用户报告，能说明该路径曾有受保护调用与污染问题，**不是 Blizzard 官方 API 政策声明，也不是 70862 当前仍存在同一 bug 的实测**。

### 方向选敌与软目标

`TargetDirectionEnemy(facing, coneAngle)` 接收方向和夹角，没有 GUID 参数。即使已知怪物位置，方向选择也没有声明在同方位、多只重叠怪物间按某个 GUID 选中的保证。单独调用它不能满足“这个格子一定对应这一只同名怪”的精确性要求。

本报告没有找到可将一个指定 GUID 写入 `softenemy` / `softinteract` 的公开函数声明。已经由引擎选定的软目标 token 可以是候选引用，但不等于插件可以为任意格子创建那个引用；后者仍缺少已证实入口。

## 同构建其他作者的情况对照

[Aegur，2026-11-08：Can addons securely target enemies from a custom combat list?](https://us.forums.blizzard.com/en/wow/t/can-addons-securely-target-enemies-from-a-custom-combat-list/2405883)

作者做的是按 GUID 跟踪敌人的自定义列表，尝试 `nameplateN` 安全按钮及 Enemy Frames 1.3.0 的原生命中区重定向；他明确写出 Forever 1.60.1 build 70862，表示没有获得可靠点击选敌。其后续认为战斗中把新发现的敌人动态分配到安全框体存在问题，并暂停了战斗操作部分。

这是一位独立作者在同构建的第一手情况，能作为本机结果的交叉参照。帖子没有 Blizzard 蓝帖确认，Discord 讨论也是该作者转述。它讨论的主要范围是战斗，**不能把它升级为“70862 脱战也必定不支持”的官方结论**。

## 后续研发判断

当前没有足够证据宣布找到新入口，不能将本报告里的接口直接当成修复交付。最有价值的新证据应当是：公开、安全、由真实点击触发的操作，接受一个能区分同名 NPC 的引用，且在游戏读回中实际把 focus GUID 设为那一只怪。仅有 `UnitExists=true`、可读 GUID、函数不报错或模拟器 PASS 均不满足这项证据。

若继续做别名方案，应把“已有别名恰好指向此 GUID”的机会路径与“任意附近 NPC 都可操作”的承诺分开。若没有这种精确可操作引用，仍应保持拒绝误设同名怪的现有保护。
