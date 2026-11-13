# 同名怪直接右键焦点验证

2026-11-11；本机当前客户端 1.60.1 / 70862。用户明确要求无需先在世界选中，同名怪也能直接右键格子设焦点。

已核对固定构建源码（SOURCE.json）：FocusUnit 使用字符串参数；原生安全按钮先检查 UnitExists(unit)，之后 focus 动作调用 FocusUnit(unit)。UnitTokenFromGUID 查询既有引用，未发现创建任意 GUID 单位或专用 FocusByGUID 接口。历史 GUID 探针测试的是施法，不能用其失败替代本次焦点测试；旧姓名板原生焦点的结构化失败仅见战斗中。

本机 0.1.39 加入默认不启动的临时 FocusAPIProbe。命令 `/mytargets focusprobe native 1`、`guid 1`、`macro 1` 分别准备第1敌方格的原生单位、原始GUID安全focus按钮、无unit属性的GUID宏按钮；右键中央测试按钮才触发。`off`关闭。原格右键暂保持0.1.38逻辑。

验证需要两只同名怪在列表同时存在且脱战；无需先选中或攻击。每轮冻结格子身份，点击前重验，读回焦点GUID、当前目标GUID、原始GUID是否被UnitExists接受。切换到不同怪并确认点击前焦点不同，再按真实焦点GUID判断；准备成功或已有相同焦点不算执行成功。记录FOCUS_API_PROBE_PRE/POST/READBACK，原目标必须保持。测试后关闭临时按钮并reload保存。若原生单位路径成功，再改正式右键；未成功不得仅删除同名拦截而继续按名字选。

验证状态：独立48项探针模拟已合入全套7082项检查；本机已执行原生单位、GUID按钮、GUID宏共4次有效硬件测试，均未建立怪物焦点；同一按钮player阳性对照成功。焦点功能未修通，测试UI和临时绑定已清理。详细实测见 TARGETS-VALIDATION.md 与 local-logs/targets-0.1.39-focus-api-analysis-20261111.json。未发布，官网仍0.1.37。

## 快速切目标方案的上游核对（2026-11-11）

用户追加要求核对“快速切目标 → 设置焦点 → 恢复原目标”。当前唯一姓名兼容路径已经采用该顺序；它不能单凭姓名辨认同名 NPC。

- BattleGroundEnemies 确实使用 `/targetexact 玩家姓名` → `/focus` → `/targetlasttarget`，场景为玩家姓名。不能从此推导任意同名 NPC 可精确选择：[固定提交 PlayerButton.lua:672](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/4e96f79ff93953fd012bb147ff9b3b422319f18b/PlayerButton.lua#L672)。
- HealBot 从既有 target、focus、队员目标、arena、boss 单位建立敌方框，并绑定单位 token；GUID 用于记录和反查既有 token：[名单](https://github.com/davidmarshall15/Healbot/blob/bcaf2db7c678b1841dab8c69bc5e566bb1bc3533/HealBot/HealBot_Panel.lua#L2771)、[单位绑定](https://github.com/davidmarshall15/Healbot/blob/bcaf2db7c678b1841dab8c69bc5e566bb1bc3533/HealBot/HealBot_Action.lua#L6589)。
- EnemyGrid 旧源码绑定 `nameplateN`，目标动作使用 `@mouseover`，没有发现按 GUID 循环选择的实现；该旧源码不是 Forever 70862 的运行验证：[单位绑定](https://github.com/Tercioo/EnemyGrid/blob/aed42946c1307b11df1c537a41bf84788e58e6fb/EnemyGrid.lua#L1441)、[目标动作](https://github.com/Tercioo/EnemyGrid/blob/aed42946c1307b11df1c537a41bf84788e58e6fb/EnemyGrid.lua#L2243)。

70862 的 `/target`、`/focus` 是安全斜杠命令，`/run` 则执行普通脚本；硬件按键并不让任意脚本变成安全动作：[SlashCommands.lua](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua#L479)。本机19:32脱战、原目标为空时，硬件提交 `/run pcall(TargetUnit,"player")` 出现 ForceTaint_Strong 拦截，目标未选中。19:36在怪物格有名字、没有旧弹窗时，单独 `/run pcall(TargetNearestEnemy)` 同样弹出限制提示，目标仍为空。pcall 返回 true 不代表执行成功。没有将这些受限脚本加入正式右键逻辑。

多次 `/targetenemy` 会改变目标历史；最后一次 `/targetlasttarget` 不能保证回到整个操作开始前的目标。原 GUID 可供核验，但未找到根据该 GUID 创建可操作单位引用的接口。因此没有将盲目循环方案作为修复。

补充的本机 target 探针只在原目标明确为空、没有待施法光标或携带物品时执行一次原生 `type=target`，不设置焦点；增加安全环境 UnitExists、OnClick 解析和 TargetUnit/FocusUnit 被动调用追踪，用于区分按钮预检与接口执行无效。默认关闭、不创建帧或 hook。最终独立探针99项、全套7133项模拟通过。

19:44:14有效本机测试（seq12543—12547）：按钮已实际调用TargetUnit("nameplate1")，实时GUID等于候选迪菲亚强盗GUID，普通/受限UnitExists均true，但即时及0.1秒读回目标仍为空；焦点未变。第一次尝试因binding_changed拒绝，不计API失败。此单跳未成功，所以未尝试焦点和恢复组合；详情与输入范围见 TARGETS-VALIDATION.md。临时按钮和F12已清理，最终诊断守卫代码经重载加载，未发布。
