## Codex 当前整合记录（2026-11-14）

来源 `jnfx962/myforever-addons:fix/targets-combat-hover-cast` / `0cf2b1e`；该提交以旧 main `3c8ba32` 为基础。整合基线为已发布 main `5392bd7`，候选分支 `codex/targets-combat-hover-20261114`。原作者的 0.1.47 是旧分支编号，整合源码保留现有 0.2.0；后续公开代码若改变必须另升版本，不覆盖 0.2.0 ZIP。

合并时保留七插件星辉样式、MyForeverStyleDB、已发布敌方唯一名称战斗桥及说明；解决 AGENTS、问题清单、版本、TOC 和 UI 的五个旧基线冲突。新的固定单位路径优先，姓名板仍只沿用已有战前唯一名称路线；新出现或无法确认唯一的怪物仍不接管。当前版本的 MFT-002 继续 open。

补充审查先复现再修复三类缺陷：

1. 停在格上翻页时未清旧主条绑定：新增安全状态回调即时重算；形态分别编号，未知形态不接管主条。
2. 原生 OnLeave 共用 `_wrapentered`，外层新包装会抑制内层清理：由新外层统一清理自身、脱战名称桥、敌方名称控制器各自拥有的绑定，并在新 Enter 先交还旧控制器的绑定，保留旧格延迟 Leave 不清新格的规则。
3. 同一固定敌方格可能同时由新直施与旧名称桥绑定：旧控制器在 enter 与战斗状态回调中均让出固定单位格，姓名板路径保持原样；单独关闭新模块时也会归还该资格给旧控制器。

同时补充 ActionButtonUseKeyDown/覆盖动作条更新事件、战斗中安装延期和实际可用键数状态。没有改另外六个插件、共享星辉样式、官网或管理器。未生成任何 ZIP、未合并 main、未部署、未改游戏目录或设置。

**实际验证：** `/Users/mashuangxi/World of Warcraft/PersonalAddons/.venv/bin/python tools/check_addons.py`：83 个 Lua 文件语法、7 TOC、73 组自研 Lua 模拟、19 项 Python 解析检查全部通过。新 combat-hover 测试从作者原 107 项扩展到 141 项，包含上述失败顺序与实际旧 CombatCast 模块交互。模拟仍不是原生引擎、实际施法或键位的游戏验收。Manager 和官网本次无源码变化。

**主要接口依据：** 核对 Blizzard 编写、Gethe 镜像的 build 70888 提交 `4cd0ab7`：[SecureHandlers.lua](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureHandlers.lua)、[RestrictedFrames.lua](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua)、[SecureStateDriver.lua](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua)。保留来源哈希，不将镜像源码审查当成当前客户端运行证明。

验证清单、来源哈希见 `PersonalAddons/work/targets-combat-hover-20261114/VALIDATION.json` 与 `OFFICIAL-SOURCES.json`。失败前日志和完整运行日志留在本机忽略目录 `PersonalAddons/local-logs/targets-combat-hover-20261114/`。

**游戏待测：** 小队治疗受术者与当前目标不变；已悬停入战；移开/隐藏还键；脱战名称桥接回；停在格上切动作条/换形态；按下/抬起及修饰键；关闭施法后无覆盖；敌方固定单位直施及旧唯一名称格的独立验证。附近任意同名怪精确焦点仍不在本模块能力范围。

---

以下是 Claude 在旧基线上的原始交接，版本号与“公开 0.1.46”等描述仅为当时记录，不覆盖上方当前状态。

# 交接：目标选择 0.1.47 战斗中固定单位格悬停施法（2026-11-14）

写给接手的 Codex。本轮由 Claude 在**没有安装游戏的维护机**上完成，用户明确要求“按官方文档和其他开发者的经验做”。所有结论只有模拟证据，**没有游戏实测，没有发布**。分支：`fix/targets-combat-hover-cast`。

## 用户反馈

1. 目标插件的敌方面板不支持鼠标悬停施法。
2. 友方悬停施法脱战正常，进入战斗后失效。

## 原因

- 现有普通技能悬停走 `NearbyCast.lua` 的名称桥：按键时 `/targetexact 名字` → 施法 → 恢复原目标。它设计上只在脱战工作（`legacyContext` 返回 `out_of_combat_only`，owner 的 `[combat]` 状态驱动清绑定），入战交还原键，普通技能于是落到当前目标。这是友方“进战失效”的直接原因。
- 敌方附近怪物格绑定 `nameplateN`。历史实测（见 `PersonalAddons/TARGETS-VALIDATION.md` 0.1.12–0.1.22）：本客户端不把插件格上的姓名板单位当作原生 mouseover；`/cast [@GUID]` 未发起技能；原生姓名板放大被夹到 512×256、`GetHitTestPoints` 触发 taint。本轮没有新证据推翻这些限制。

## 改了什么

| 文件 | 改动 |
| --- | --- |
| `_forever_/Interface/AddOns/MyForeverTargets/CombatHover.lua` | **新增**模块，Clique 式战斗悬停施法 |
| `MyForeverTargets.toc` | 在 `NearbyCast.lua` 后加载 `CombatHover.lua`；版本 0.1.47；Notes 说明战斗范围 |
| `Core.lua` | `NS.VERSION = "0.1.47"` |
| `UI.lua` | `createTile` 末尾 `CombatHover.Install(row)`（仅 legacyBridge 侧）；`BindTiles` 每格 `CombatHover.BindRow(row)`；战斗中格子提示、面板提示、“施法”按钮提示改为说明固定单位格可用、姓名板格不可用 |
| `Main.lua` | 新命令 `/mytargets combatcast`（显示准备的技能/键数）；`legacycast` 与登录提示文字更新；help 加入 combatcast |
| `PersonalAddons/tests/targets_combat_hover_test.lua` | **新增** 107 项模拟，含自建的受限环境句柄模型 |
| `PersonalAddons/TARGETS-VALIDATION.md`、`CURRENT_ISSUES.md` | 记录本轮实现与未验证范围 |

没有改 `NearbyCast.lua`、`CombatCast.lua`、`FocusCycle.lua`、探针模块或其他插件。

## 怎么实现的

参照 Clique/HealBot/VuhDo 的点击施法模式，以及 warcraft.wiki.gg「Bindings.xml」所述：战斗中只能通过受限环境里的框体句柄方法改覆盖绑定。

1. **脱战准备（`Hover.Sync`，每 0.5 秒检查 dirty）**：复用 `NearbyCast.DiscoverActions(side, true)` 读动作条上的普通有益/有害 spell（宏、物品、其他插件占用的键本来就被它排除；`allowOwn=true` 容忍名称桥自己的临时覆盖）。每个技能建一个离屏 `SecureActionButtonTemplate` 代理 `MyForeverTargetsCombatHover<side><n>`，`type=macro`，属性 `mfch-spell` 存带等级的技能名，按 `useOnKeyDown` 注册 AnyDown/AnyUp。owner（`MyForeverTargetsCombatHoverOwner`，`SecureHandlerStateTemplate`）上发布 `<side>-key<i>`、`<side>-keyproxy<i>`、`<side>-keypaged<i>`、`<side>-proxyname<n>`、FrameRef `<side>-proxy<n>`、`<side>-keys`、`<side>-bar`。触发 dirty 的事件：登录、REGEN_ENABLED、UPDATE_BINDINGS、动作条/翻页/形态、SPELLS_CHANGED、UPDATE_MACROS、GROUP_ROSTER_UPDATE，以及“施法”开关变化。
2. **格子资格（`Hover.BindRow`，仅脱战，由 `BindTiles` 调用）**：只有固定单位 `player`、`pet`、`party1–4`、`partypet1–4`、`raid1–40`、`raidpet1–40`、`target`、`focus`、`boss1–8`、`arena1–5`，并且 `row.unit` 等于安全属性 `unit` 时，才设 `mfch-ready=true`、`mfch-unit=<unit>`。`nameplateN` 和 `…target` 链式别名不接入：战斗中格子不会重绑，这些令牌可能被复用。
3. **受限包装（`Hover.Install`）**：每格 `SecureHandlerWrapScript` 包 OnEnter/OnLeave/OnHide。Enter 先记 `mfch-hover`；只有 owner 的 `mfch-combat` 为真才 `ClearBindings` 并执行共享 BIND 片段：对每个键设代理 `macrotext = "/cast [@<unit>,exists,help|harm] <spell>"`，再 `SetBindingClick(true, key, proxyName, "LeftButton")`。Leave/Hide 只在 `mfch-hover` 仍是本格时清除，格间移动时旧格的 Leave 不会清掉新格。
4. **状态驱动**：`mfchcombat` = `[combat] combat; idle`。入战时若鼠标已在已准备的格上（`IsUnderMouse`）立即绑定；回到 idle 就 `ClearBindings`，交回 NearbyCast 名称桥（它在 REGEN_ENABLED 时 Reconcile）。`mfchbar` 记录主动作条翻页（vehicleui/overridebar/possessbar/shapeshift/bonusbar/actionbar）；来自 `ACTIONBUTTON*` 的键只在当前翻页状态等于准备时的状态才绑定，副动作条不受影响。读不到翻页状态时主条键不绑，宁可不接管也不放错技能。
5. **边界**：不切换、清空或恢复目标；不 `SaveBindings`，不建、不改宏；战斗中不做任何非受限的保护操作，`Sync`/`BindRow` 遇战斗只标 dirty。总开关沿用 `NS.DB.legacyNameBridgeEnabled`（面板“施法”按钮），也可以用 `NS.CombatHoverEnabled=false` 整体停用。只有 `NearbyCast.legacyName==true`（当前 Core 策略）时模块才安装。

## 检查结果

- 维护机没有 lupa/Lua 5.1。用 `luatex --luaonly` 自带的 Lua 5.3，加一个 5.1 兼容垫片（loadstring/unpack/setfenv/getfenv，垫片在仓库外）逐个运行 `PersonalAddons/tests/targets_*_test.lua`。原有 20 套全部通过，数量与改动前一致（UI 2221、nearby 484、legacy bridge 203 等）。新增 combat_hover 107 项通过。**请在有 lupa 的环境用 `PersonalAddons/run_targets_tests.py` 复跑**，确认 5.1 下一致。
- 新测试的受限环境是自建模型（句柄可读写属性、`SetBindingClick`/`ClearBindings`；非受限代码在战斗中写属性会断言失败），不代表原生安全引擎的全部行为。

## 待你在游戏中验证（按优先级）

1. 进战斗后悬停小队/团队格，按普通治疗键：受术者是否为该格单位，当前目标是否不变。
2. 已在格上时开怪（状态驱动立即绑定）；移开后按键是否回到原动作。
3. 脱战后名称桥是否照常接管（友方脱战路径用户已确认正常，不能回退）。
4. 按下触发（ActionButtonUseKeyDown）与抬起触发的键都要试；带修饰键的键（SHIFT-1 等）。
5. 姿态/形态职业战斗中翻页后，主条键是否正确不接管。
6. 有条件时测首领、竞技场、焦点敌方格的 harm 技能。
7. `/mytargets combatcast` 输出；`施法` 开关关闭后战斗中不再接管。

可能的风险：本客户端（1.60.1）受限环境若缺少 `SetBindingClick`、`IsUnderMouse` 或对句柄 `SetAttribute("macrotext")` 有额外限制，片段会静默失败，表现为“战斗中仍无效”而不是报错。请开日志并留意 ADDON_ACTION_BLOCKED。

## 没做 / 不能宣称

- 敌方附近怪物格（nameplateN）战斗中仍不支持，脱战同名怪仍按原名称桥规则拒绝。MFT-002 的敌方部分没有关闭。
- 未生成发行 ZIP，未改官网/管理器元数据，未部署。公开版仍是 0.1.46。0.1.47 本机线包含 0.1.45 的默认关闭探针。上线前需要游戏实测和用户授权。
- 用户收到的本机测试包 `MyForeverTargets-0.1.47-dev.zip` 只是源码打包，不是发行包。
