# 安全选择、GUID 核验与恢复：2026-11-11 只读研究

本轮未修改插件、未执行游戏操作。下列方案为待验证探针，不是已经修通的功能。

## 当前同类插件实际做法

- 已检查当前 AKForeverTargeter **0.2.4**（2026-10-21，Forever 1.60.1），而非只看 0.2.1。最新版累计更新仍保留同名 NPC 仅能由名字解析到最近者的限制；0.2.2–0.2.4 的新增内容没有解除它。[作者最新发布说明](https://www.curseforge.com/wow/addons/akforevertargeter/files/9274391)
- 直接读取[最新版 ZIP](https://edge.forgecdn.net/files/9274/391/AKForeverTargeter-v0.2.4-forever.zip)：`AKForeverTargeter/Panel.lua:123–126` 注释明确没有请求第二近同名 NPC 的方法。`MacroFor` 的 `134–155` 行先清目标，再按不同名字逐项尝试 `/targetexact`；需要优先活怪时，后续名字加 `[noexists]`，死目标用 `/cleartarget [dead]` 放弃。结束时只有没找到目标才 `/targetlasttarget [noexists]`。它没有按 GUID 选怪、同名轮询或设置焦点的实现。`Core.lua:8–12` 说明由原生安全宏执行选择和标记。
- BattleGroundEnemies 确实用 `/targetexact 玩家姓名` → `/focus` → `/targetlasttarget`；其凭据是唯一玩家姓名，不能移植成任意同名 NPC 的身份证明。[固定版本源码 672–675](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/4e96f79ff93953fd012bb147ff9b3b422319f18b/PlayerButton.lua#L672)

## 精确客户端源码支持与不支持什么

核对构建 `9dc84f0d3bbae1768ac3405b3716000bd93eda06`：

- `SlashCommands.lua:489–502`：`/targetexact` 最终调用 `TargetUnit(name, true)`；`/targetenemy` 最终调用 `TargetNearestEnemy(reverse)`。`TargetScriptDocumentation.lua` 的 `TargetUnit` 参数只有名字字符串和 `exactMatch`，没有“第几个同名单位”参数。[源文件](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua#L489)
- `SlashCommands.lua:726–741`：`/click` 查找按钮并调用 `button:Click`；`SecureTemplates.lua:521–523` 的原生 `focus` 动作调用 `FocusUnit(unit)`。因此“安全宏选一只 → 点击原生 focus 按钮”有源码调用路径，但 C 层是否允许同一硬件事件完成组合，仍需要本机实测。[安全按钮动作](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L521)
- `RestrictedEnvironment.lua:82–84` 暴露 `SecureCmdOptionParse`、`UnitExists`、`UnitIsDead` 等受限函数，没有暴露 `UnitGUID`、`UnitIsUnit`。GUID 判断不能直接假装成安全宏条件。脱战普通 `PreClick` 读 GUID、配置随后执行的原生动作，是一个需要验证的边界；战斗中不能依此改保护属性。
- `SecureButton_GetModifiedUnit` 读取 `unit` 属性字符串；把 `unit="target"` 存到另一个按钮里不会冻结那一刻的角色。`SetFrameRef` 保存的是框体引用。已检查的代码中没有发现把任意原目标另存为可执行原生单位句柄的接口。GUID 可核对身份，不能据此假设存在新的可操作单位引用。

## 为什么不直接加二十次循环

Blizzard 开发者 Slouken 的历史说明写明 `/targetenemy` 每宏只执行一次，第二次会被忽略并继续下一行；2015 年插件作者也用按下/抬起两个硬件事件区分两次命令。[Blizzard 开发者原帖镜像](https://www.bluetracker.gg/wow/topic/us-en/48694952-20-changes-continued/)、[作者实测讨论](https://wowinterface.com/forums/archive/index.php/t-51896.html)。这是历史一手证据，**不是 Forever 70862 当前行为的证明**。

即使当前允许循环，A → B → C 后的 `/targetlasttarget` 通常只回 B。记录 A 的 GUID 并没有创造返回 A 的调用入口。临时占用 focus 会破坏“失败不丢旧 focus”的条件。反向循环找 A 也受可达候选集及现场变化限制，不能承诺任意目标恢复。

单次 `/targetexact 名字` 后核验 GUID，只能安全拒绝选错的那只；没有证据表明恢复原目标后再按一次会推进到第二只。同类插件当前作者说明反而指出名字解析重复选择最近者。不能将多次点击包装成同名精确选择。

## 有限且可证伪的最小探针

1. **先只测循环限制，不设焦点。** 原目标为空、现场至少两只可循环敌人。一个硬件宏执行两次 `/targetenemy`，各次后普通 `/run` 仅记录 `UnitGUID("target")`，最后 `/cleartarget`。只有两次 GUID 确实不同才算当前构建允许该次循环；相同还须排除只有一个可循环目标，不能直接下结论。
2. **独立测 GUID 闸门，不依赖循环。** 原目标为空、保存旧 focus GUID，冻结格子的目标 GUID。安全宏先 `/stopmacro [combat]`，再 `/targetexact 名字` → `/click 原生核验按钮` → `/cleartarget`。核验按钮的脱战 `PreClick` 默认禁用，仅当当前 GUID 等于冻结 GUID、格子绑定仍有效且仍脱战时启用原生 `type=focus, unit=target`。分别测试匹配、不匹配、名字已消失；不匹配与消失必须保持旧 focus。即时及延迟读回验证；原目标最终必须仍为空。这里只验证“名字恰好选对”的有限路径。
3. **原目标非空时另测恢复。** 一次确实 A→B 后设焦点再 `/targetlasttarget` 有合理依据；但 `/targetexact` 失败或选中的本来就是 A 时，无条件 `/targetlasttarget` 可能切到历史目标，不能照搬。可单独测试先 `/cleartarget` 的方案，覆盖成功、未找到、重新命中 A；或测试是否可通过核验按钮控制原生恢复动作。需要嵌套宏的实现还须独立确认 C 层允许。所有分支必须读回原 GUID，不能只看“宏跑完”。

不使用普通 `/run TargetUnit/FocusUnit/TargetNearestEnemy`，不把历史限制写成本机构建已确认，也不提出让用户反复 TAB 代替目标格的方案。

## 交付矩阵

| 范围 | 状态 | 准确结论 |
| --- | --- | --- |
| 原生安全宏按名字选择候选 | 已有当前同类插件源码 | 可以尝试一个名字解析结果；没有同名精确性 |
| 读取候选 GUID 和格子 GUID 作身份核验 | 可做只读核验 | 能识别选错，不能让选择 API 接受 GUID |
| 一硬件事件内 `targetexact`→GUID 闸门→原生 focus | 待本机验证 | 最小探针限脱战、原目标为空 |
| 错 GUID 时保留原 focus | 探针必须验证的硬条件 | 先禁用动作，匹配才执行；不能先清 focus |
| 一硬件事件多次 `targetenemy` | 当前未知，有历史限制证据 | 先测两次是否确实换 GUID，未通过前不构建循环 |
| 重复 `targetexact` 精确推进任意同名 NPC | 无支持证据 | 当前同类插件明确仍选最近者，不能交付为解决方案 |
| 任意轮询后恢复任意原目标且失败保留旧焦点 | 无可证明方案 | 目标历史随轮询改变；未找到从原 GUID 构造可执行原生引用的接口 |

