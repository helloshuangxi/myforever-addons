# PvP 框体的战斗焦点与 GUID：代码审查

日期：2026-11-12。只读取和保存第三方文本源码，未加载、未执行；未修改我方插件。`SOURCE.json` 记录此次读取的仓库 HEAD、版本/Interface、每个文件的固定 URL 与 SHA-256。仓库 HEAD 不等于已核实的最新发行包，所列插件也未在 Forever 70888 运行验证。

## 可复现矩阵

| 项目与固定提交 | GUID 如何对应到显示行 | 实际保护动作 | 能复用的机制与边界 |
| --- | --- | --- | --- |
| BattleGroundEnemies，`4e96f79ff93953fd012bb147ff9b3b422319f18b`，2025-08-18；TOC 版本为打包占位符、Interface 110200 | `Main.lua:1760–1785` 用 `GetPlayerInfoByGUID` 得到玩家姓名/服务器，存 `PlayerGUIDs[GUID].name`；`:1638–1642` 再按姓名查找行。不能识别为玩家的 GUID 在 `:1773` 直接返回。 | `PlayerButton.lua:660–675` 为右键预置 `/targetexact 玩家名`、`/focus`、`/targetlasttarget`。`:697–704` 战斗中需要修改绑定时排队，脱战才 `SetAttribute`。arena 场景还保存原生 `arenaN` 单位。 | 可借鉴预置安全宏的配置与战斗延期更新；该名字路径明确面向玩家，不提供同名 NPC 的 GUID 精确选择。 |
| GladiusEx，`085cefb71926172730330131f4c8dca409960c16`，2025-12-17；TOC 无 Version、Interface 110005/110007/110100/110200 | `GladiusEx.lua:957–980` 只把已知 `arena1..5`、`player/party1..4` 的 GUID 反查到现有 token；`modules/drtracker.lua:288–295` 用它把战斗日志减益事件交给对应 DR 显示行。 | `GladiusEx.lua:1207–1209` 创建 `SecureActionButtonTemplate`、`unit=unit`。`modules/clicks.lua:8–10` 默认右键 `focus`，`:48–56` 配置点击类型。`GladiusEx.lua:1427–1435` 战斗中不重建/修改单位布局。 | 可复用原生 arena/party token 的直接焦点；GUID 表没有生成新 token，也没有控制一次 Tab 后是否执行 focus。 |
| 原版 Gladius 8.2.0，`ae82b29e40d6d31a361d043f97beb14aa33e0ba7`，2025-04-21；Interface 110100/40402 | `Modules/DRTracker.lua:190–195` 遍历既有行，用 `UnitGUID(arenaN)==destGUID` 给 DR 事件找单位；不写焦点保护属性。 | `Gladius.lua:881–886` 创建安全动作按钮；`Modules/Clicks.lua:16–18` 默认右键 `focus`，`:79–86` 写 `unit=arenaN` 与按钮类型。`Gladius.lua:594–600` 在战斗中跳过单位更新/创建。 | 精确性由客户端的 arena 单位索引承担；不能将自建 GUID 表中的任意怪物变成 arena 单位。 |
| sArena Updated2 4.0.1，`f7306d90a55ca8ba7d9092ead2b93a62bd24c848`，2026-03-22；Interface 120001/120000 | 点击行直接按原生竞技场索引建立；这条动作链不经 GUID 反查。 | `Frames.lua:38–45` 建 3 个安全动作按钮并设置 ID；`Events.lua:335–355` 令 `unitID="arena"..GetID()`，配置 `*type2=focus`、`*typerelease2=focus` 与 `unit=unitID`。 | 可复用固定 arena token 的预设安全动作；不是任意怪物识别或自动 GUID 匹配方案。 |
| Gladius Updated by Sammers 2026.1.1，`a7b95e5745d5124031ce0b6276fd89a79369a335`，2026-03-22；Interface 120001/120000 | `Modules/DRTracker.lua:435–440` 仍为战斗日志 GUID 找既有单位行。 | `Modules/Clicks.lua:16–18、79–86` 仍为原生单位 token 加右键 focus；`Gladius.lua:1088–1093` 创建安全动作按钮。 | 新版 fork 没有增加“任意 GUID 在安全片段内决定 focus”的入口。12.0 兼容声明不能当作 Forever 兼容证据。 |

## 关键调用链与固定源链接

### BattleGroundEnemies

数据：`战斗日志 GUID → GetPlayerInfoByGUID → 玩家全名 → Players[name]`。

动作：`脱战配置 macrotext2 → 真实硬件右键 → 原生 /targetexact → /focus → /targetlasttarget`。

- [GUID 找行](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/4e96f79ff93953fd012bb147ff9b3b422319f18b/Main.lua#L1638)
- [GUID 仅识别玩家](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/4e96f79ff93953fd012bb147ff9b3b422319f18b/Main.lua#L1760)
- [焦点宏及战斗延期配置](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/4e96f79ff93953fd012bb147ff9b3b422319f18b/PlayerButton.lua#L618)
- [arenaN 来源](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/4e96f79ff93953fd012bb147ff9b3b422319f18b/Mainframe.lua#L1288)

注意：`PlayerButton.lua:642–646` 的 `type=target/focus` 原生 arena 分支是注释；它保留 `unit=arenaN`，之后默认动作仍走 `:660` 开始的宏分支。不能把注释当成实际执行路径。原名宏也没有我方 GUID 核验、空目标或原目标相同等分支保证，不能整段照搬成安全事务。

### GladiusEx

数据：`已有 arena/party token → UnitGUID(token) → guid_to_unitid[GUID]`；DR 模块拿 GUID 反查 token 后更新显示。

动作：`创建 frame(unit=arenaN) → 配置右键 type=focus → 原生安全动作`。点击时不进入上述 GUID 表来作真假分支。

- [GUID/token 表](https://github.com/vendethiel/GladiusEx/blob/085cefb71926172730330131f4c8dca409960c16/GladiusEx.lua#L957)
- [战斗日志实际使用](https://github.com/vendethiel/GladiusEx/blob/085cefb71926172730330131f4c8dca409960c16/modules/drtracker.lua#L288)
- [安全按钮单位绑定](https://github.com/vendethiel/GladiusEx/blob/085cefb71926172730330131f4c8dca409960c16/GladiusEx.lua#L1206)
- [右键 focus 配置](https://github.com/vendethiel/GladiusEx/blob/085cefb71926172730330131f4c8dca409960c16/modules/clicks.lua#L7)

### Gladius 与 sArena

- [Gladius 原版 GUID 只为 DR 找单位](https://github.com/Resike/Gladius/blob/ae82b29e40d6d31a361d043f97beb14aa33e0ba7/Modules/DRTracker.lua#L190)
- [Gladius 原版保护属性](https://github.com/Resike/Gladius/blob/ae82b29e40d6d31a361d043f97beb14aa33e0ba7/Modules/Clicks.lua#L79)
- [sArena 原生 arenaN/focus 绑定](https://github.com/Sammers21/sArena_Updated2_by_sammers/blob/f7306d90a55ca8ba7d9092ead2b93a62bd24c848/Events.lua#L335)
- [Gladius 新 fork 保护属性](https://github.com/Sammers21/Gladius_Updated_by_sammers/blob/a7b95e5745d5124031ce0b6276fd89a79369a335/Modules/Clicks.lua#L79)

## 对我方的实用结论

在这些已审查路径中，GUID 负责数据归属；战斗焦点使用预置原生单位 token 或玩家姓名宏。未发现安全片段在战斗中读取“Tab 后是否吻合任意目标 GUID”并据此决定 focus 的实现。

能直接借鉴的最小机制是：**客户端已提供、且实际接受一个指向该单位的原生 token 时，脱战预配安全按钮的 `unit` 与右键 `focus`。** 若 NPC 自身有客户端提供的 `bossN` 等可靠引用，可研究同样做法；自行给野怪编 `arenaN`、`bossN` 或把 GUID 填进 `unit` 不会创建原生引用。

这些结论不替代 Forever 70888 的实际安全动作测试，也没有新增可让任意同名野怪在战斗中自动 GUID 确认的可执行前提。

## 文件完整性复核

可用标准 Python 仅计算 `SOURCE.json` 中各保存文件的 SHA-256，与记录逐项比较；不要将保存的 `.lua` 载入游戏或 Lua 运行时。下载的文件全部位于本研究目录，不属于游戏 `Interface/AddOns`。
