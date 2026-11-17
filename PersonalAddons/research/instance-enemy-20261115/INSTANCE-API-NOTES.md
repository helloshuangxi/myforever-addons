# 副本敌人身份与只读显示：70938 源码核对

核对日期：2026-11-15。此轮只读取本机研究、插件源码、已落盘配置和精确版本的原生 API/FrameXML 导出；没有操作游戏、调用游戏内接口、改 CVar、改候选源码或修改个人配置。用户澄清“进副本就没有出现过”，包括脱战时，因此不能只用战斗名单冻结解释本次问题。

## 版本与来源

本机研究 `friendly-combat-20261115/70938-player-name/SOURCE.json` 标注 forever 分支、`1.60.1 (70938)`、提交 **`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`**。下列本轮线上读取全部固定在这一提交，没有使用持续变化的分支头。GitHub 是客户端导出源码镜像；API 谓词说明是原生生成文档，不是对本次实际副本读值的记录。

| 原生文件 | 本轮读取 SHA-256 |
| --- | --- |
| `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` | `93004ac1b260127741471b7861360cdf7536afcb18d4c1db73b7259faa43e61c` |
| `Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua` | `e4a053e9960da00099f46de2cff25c69d4cb11d051f7c05685d06866ed389815` |
| `Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` | `668a0c15d372a358fbe169465651cdc1ae2e66d0916c81b41eccdd4da92274ae` |
| `Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua` | `156e370421081e6a8ec78afdee8e4306686cecc99f0d2163c1b62ce9a5ddbe96` |
| `Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua` | `8a1adba0e8b921e31b3d537f5a24095a946bb69ea9014db134f2c175245265e0` |
| `Blizzard_UnitFrame/Shared/CompactUnitFrame.lua` | `dd73cda4ae14c5da0346675daf33470a1b8b3434dcb57cd900a038ffc57b58a8` |
| `Blizzard_NamePlates/Blizzard_NamePlates.lua` | `5f868d58a6652fab24c2ad523bc4054deec7c5e1cc2b5b9f493d669ffa2f6ef6` |
| `Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua` | `7f99153da171aeb01d30c021d101fc0697c92cb4f047185bd548f304bbefe500` |
| `Blizzard_NamePlates/Blizzard_NamePlateHealthBar.lua` | `879e7b6928a3c0260e431b4660fb1f157188da2c3bcc61a20333dbe76f4504c2` |
| `Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua` | `1af6fb8f2428211ce696b2af18d09503116a12920d28ca76231bedb72a88292c` |
| `Blizzard_APIDocumentationGenerated/NamePlateManagerDocumentation.lua` | `f578c27a202373b896ae15469e3800dafac55f7e1382ae5a0ab42bd253444c22` |

## 哪些单位查询可能受限

[UnitDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) 的精确标记：

| API | 源码行 | 返回值相关标记 |
| --- | --- | --- |
| `UnitGUID` | 1241–1253 | `SecretWhenUnitIdentityRestricted = true` |
| `UnitName` | 2489–2502 | `SecretWhenUnitNameIdentityRestricted = true` |
| `UnitNameUnmodified` | 2523–2536 | `SecretWhenUnitIdentityRestricted = true`，不能用其绕过身份限制 |
| `UnitHealth` | 1526–1539 | `SecretReturns = true` |
| `UnitHealthMax` | 1472–1484 | `SecretWhenUnitHealthMaxRestricted = true` |
| `UnitExists` | 1192–1203 | 未标记 `SecretReturns` 或 `SecretWhen…`；有 `SecretArguments` |
| `UnitIsPlayer` | 2271–2283 | 未标记 secret 返回；有 `SecretArguments` |
| `UnitCanAttack` | 763–775 | 未标记 secret 返回；有 `SecretArguments` |
| `UnitIsVisible` | 2428–2439 | 未标记 secret 返回；有 `SecretArguments` |

“允许受限参数”与“返回值一定受限”是两回事，不能因为上述布尔 API 有 `SecretArguments` 就断言它们在 party/raid 全变 secret。缺失标记也不代替本次客户端中的读回验证。

[SecretPredicatesDocumentation.lua:130–137](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua#L130) 将单位身份受限规则描述为：非玩家控制／不在小队或团队的单位，其身份查询可能产生受限值；复合 token 的链上任一单位不满足条件，结果也受限。名字规则沿用身份规则，并注明 PvP 玩家名字的例外。对复合 token 而言，最终是友方玩家并不自动证明整条关系链具有公开身份。

同文件 [70–72 行](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua#L70) 另外定义受限地图（举例副本、团队副本）的谓词。但不能自行将 `SecretOnRestrictedMaps` 附加到没声明该标记的 API，也不能仅由静态声明推断本次副本是否已经启用某一 C++ 限制。用户本轮还没有相应已保存的副本样本。

可用的只读核验入口在 [SecretPredicateAPIDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua)：

- 93–99 行 `C_Secrets.HasSecretRestrictions()`：查询该客户端是否启用 secret 限制；若返回 false，标为可能受限的 API 不会因此产生 secret。
- 305–317 行 `C_Secrets.ShouldUnitIdentityBeSecret(unit)`：查询某个真实 unit token 的身份查询是否将产生受限值。
- 272–285 行 `ShouldUnitComparisonBeSecret(unit1, unit2)`：查询单位比较是否受限。这不是 GUID 解密或身份识别入口。

这里只核对接口存在及含义，没有在游戏中调用这些接口，也没有将其加入候选。

## 为什么原生姓名板能显示，插件名单仍可能全空

原生 [CompactUnitFrame.lua:713–734](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua#L713) 把最大血量和当前血量直接交给原生状态条，或交给对应平滑状态条入口；[844–857 行](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua#L844) 将显示名字传给 `FontString:SetText`。

生成文档明确提供这些原生显示入口：

- [SimpleFontStringAPIDocumentation.lua:664–671](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua#L664)：`SetText` 可接 tainted 环境的 secret 参数，并给文字对象增加 Text secret aspect；`SetFormattedText` 在 539–547 行有相应标记。
- [SimpleStatusBarAPIDocumentation.lua:229–238](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua#L229) 和 [355–363 行](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua#L355)：`SetMinMaxValues`／`SetValue` 可接 secret 数值，并增加 BarValue secret aspect。

这种“交给原生显示”不等于普通 Lua 可以比较、拼接、散列、按名字筛选或读回实际内容。

当前我方 `Units.lua` 的 `readAmounts` 已允许受限数值只流入原生血条，不做 Lua 除法。**但 `ReadUnit` 在建立整条 data 之前，仍要求 GUID 是公开非空字符串、名字经 `NS.Text` 后非空。** `Core.Read` 会先将 secret 结果变 nil，`NS.Text` 也拒绝 secret 字符串，因此 GUID 或名字任一受限就会先剔除整个单位。

0.2.3 当前候选只新增“战斗时继续发现公开身份敌人、独立显示”的路径，保留上述过滤。**如果副本中先失败的是 GUID／名字公开性，候选仍可能完全空白。** 这只是已有代码与原生声明能证明的候选原因；尚不能写成“本次日志已确认 GUID 被限制”或“副本问题已修复”。

## 姓名板事件与 CVar

原生 [NamePlates.lua:52–60](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.lua#L52) 处理普通和 forbidden 姓名板事件；[NamePlateDocumentation.lua:11–23](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua#L11) 的单单位查询默认不包含 forbidden 框体。当前我方发现函数也拒绝 forbidden frame，另扫描公开存在的 `nameplate1–40`。没有证据说明本次敌方都成了 forbidden plate；不能把这个机制当已确认原因，也不能通过操作 forbidden 框体绕过限制。

本轮在精确原生 `Blizzard_NamePlates.lua`、`Blizzard_NamePlateUnitFrame.lua` 中，没有找到“进入副本就将 `nameplateShowEnemies` 写成 0”的分支。这是对这两份 Lua 源的有限否定，不能排除客户端内部规则、用户按键或其他插件设置。

本机插件源码有一个明确写入者：`Leatrix_Plus/Leatrix_Plus.lua:14023–14034` 的 `CombatPlates` 选项为 On 时，启动／脱战写 `nameplateShowEnemies=0`，入战写 1。**当前落盘 Leatrix Plus 设置中的 `CombatPlates` 为 `Off`**，所以不能将它认定为本次原因；运行中未落盘的变更没有读回。当前 `Config.wtf` 没有这两个姓名板开关的显式项，缺项不代表值是 0 或 1。没有对 CVar 或该设置作写入。

候选的新日志分别保留 `nameplateShowEnemies`、`nameplateShowAll`、原始 token 数和各拒绝计数，供一次实际副本样本区分：根本没有获得单位、获得单位但身份过滤、还是已经识别但未显示。

## 受限身份的只读显示设计护栏（仅设计，未实现）

若日志确认是身份值受限，可考虑独立于可操作 data 的显示通道，遵守以下边界：

1. **只从真实、客户端公开暴露的 `nameplateN` token 建立候选。** 不使用扫描物体、缓存名字、猜测距离或任意构造 token；不读取或操作 forbidden frame。普通 `target`／`boss`／队友目标别名不能与匿名姓名板合并为“同一 GUID”。
2. 必须先取得公开的 `UnitExists == true`、`UnitIsPlayer` 布尔分类及 `UnitCanAttack("player", unit) == true`。任何必要判定未知、secret、异常或 false 都继续拒绝，不把未知当敌方。仍保留玩家／怪物分类约束。
3. 原始受限名字只能直接交 `FontString:SetText`。不通过 `NS.Text` 清洗后冒充公开内容，不进行拼接、长度比较、模式匹配、排序、散列、日志序列化或再次从 FontString 取文字。布局保持固定尺寸，避免读回受限文字尺寸来计算布局。
4. 原始血量／最大血量只交原生状态条入口，不在普通 Lua 中除法、比较、计算百分比或格式化。资源条也只在资源类型与颜色选择公开可读时显示，不猜资源种类。
5. **token 是临时显示地址，不是 GUID，也不是已验证身份。** `displayGUID` 不能填 token、名字或伪造 ID。可用独立的只读 token／事件代数维护视觉槽位；姓名板移除／重加、地图切换或异常时清空该槽，重新读取同 token 时也不主张同一怪物身份。已知 GUID 的普通通道和受限显示通道不得混作去重依据。
6. 这种格子明确 `actionable=false`，主格和敌人目标小条始终由非保护输入盾拦截，不改变已准备的安全 `unit`／`expectedGUID`／宏／按键，也不把鼠标移入视为正确安全 mouseover。不接左键选人、右键焦点、Ctrl+右键标记、普通技能悬停接管或同名怪匹配。只有另一次正常公开身份核验和脱战准备完成后，才能恢复原有操作。
7. 如旧安全悬停 owner 尚未收到真实离开，保留或清空该视觉槽，不能拿新只读单位替换它而让旧输入继续存在。保持现有 Main/UI 的输入盾与清理所有权规则。
8. 仍最多 20 个显示格，遵循实际已准备的 5／10／20 容量；战斗中不移动、显示／隐藏受保护按钮或调整布局。不提供受限身份的精确距离、目标／焦点匹配框或头顶动画保证。
9. 相关光环、驱散分类和敌人目标关系若无法在公开信息下证明，也不推断。子条不能因为最终显示了友方名字，就继承旧单位的可施法／焦点动作。
10. 日志只保存数量、固定拒绝原因、读取是否受限及可操作状态；不保存原始受限名字、GUID、血量、帧、聊天或宏。`C_Secrets` 只读谓词可作为诊断标志，不能当解密／身份确认。

以上设计能否被真实 70938 客户端接受，仍须在拿到副本样本后做隔离原生显示验证。显示成功也不等于受保护选择、施法或焦点成功。
