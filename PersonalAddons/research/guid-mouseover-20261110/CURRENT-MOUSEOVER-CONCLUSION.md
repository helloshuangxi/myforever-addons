# 固定敌方格原生 mouseover：当前证据与限制

核对日期：2026-11-10（Asia/Shanghai）。本机客户端 wowf 1.60.1.70862；插件代码 0.1.22。本轮只读研究和文档更新，没有重新运行姓名板实验、修改运行中的游戏或进行施法测试。

**结论：固定列表中任意附近怪物的原生 mouseover 仍未实现。** 玩家要求的是悬停格子时游戏本身识别到那个怪物，随后由玩家自己的宏施法。读到不同 GUID、格子绑定 nameplateN、头顶动画或浮层都不足以证明这个条件。没有找到可在本机替代已失败路线的、经过验证的公开 API 实现；这不是关于所有未来客户端的永久不可能性结论。

## 当前第三方证据

EnemyFrames 作者的 [CurseForge 主页面](https://www.curseforge.com/wow/addons/enemyframes) 目前在介绍顶部明确说明：最新 Blizzard 更新后，点击列表条选中目标已经失效，作者无法修复。仍列出的文件为 2026-10-26 的 1.3.0；旧下载页或旧演示不能证明现在仍可用。页面未注明该警告的发布日期或具体构建号。

警告直接说的是“点击选择目标”，不能单独扩大成“所有悬停机制都不可能”。它说明之前参考的旧实现不能作为当前可行性证据；本机原生鼠标身份不匹配和尺寸受限另有独立实测。

已缓存的 EnemyFrames 1.3.0 源码依赖扩大全局原生姓名板边界，再将其命中区域关联到列表。参考包只下载、阅读，没有安装或执行。出处与哈希见 `enemyframes/SOURCE.json`。

## 本机实测

| 记录 | 观测 | 可以得出的结论 |
| --- | --- | --- |
| session12，0.1.19 | 狗头人格绑定的单位和 GUID 正确，但真实 mouseover 仍是狼；狗头人进入 0–5 码范围后仍如此。离格后，真实 mouseover 为狗头人、当前目标仍为狼时，记录到 7 组对狗头人的施法发送与成功事件 | 格子没有建立正确的原生鼠标单位；这次失败不能归因于狗头人太远或宏完全无效 |
| session13，0.1.20 | 正常插件 OnUpdate 中 9 次命中区测量均被 FrameMeasurement 拒绝；CanChangeHitTestPoints 为 true | 能修改不等于可以读取快照；旧快照恢复原型不能通过前置条件 |
| session14，0.1.21 | 扩大请求后的公开读回为 512×256；在设置视觉 box 或命中映射前中止 | 该次跨屏映射方案未建立所需原生边界，尚未进入真实 mouseover 验证 |

原始日志及分析分别为 `PersonalAddons/local-logs/targets-0.1.19-20261110-162724*`、`targets-0.1.20-20261110-165655*`、`targets-0.1.21-20261110-171514*`。session14 的尺寸来自同轮公开控制台读回，保存在分析文件的 supplemental_live_console_evidence；不能冒充原事件日志已采集的字段。

0.1.21 收尾曾把客户端钳制后的自身尺寸误判为外部修改。已完整重载恢复，并在 0.1.22 修复所有权判断、禁用 trial 启动入口。17:19 实际加载 0.1.22 后确认日志关闭、商业技能助手使用 original、原生尺寸为 142.5×53.150001525879；没有临时卡。本轮没有重新启动该试验。

## 为什么复用 HealBot / Cell 仍不能覆盖任意附近怪物

| 游戏已有的单位编号 | 覆盖范围 | 本插件状态 |
| --- | --- | --- |
| target、focus 及其 target 链 | 已有目标、焦点及其选中的对象 | 已收集 |
| partyNtarget、raidNtarget | 队友、团员正在选中的对象 | 已收集 |
| bossN、arenaN | 游戏提供的首领或竞技场槽位 | 已收集 |
| nameplateN | 当前姓名板单位的数据标识 | 已收集；本机格子绑定正确仍未产生匹配的原生 mouseover |
| softenemy、arenapetN、更深的 target 链 | 一个软选中的敌人、竞技场宠物或已有关系链 | 不能补齐任意附近 20 个怪物；未证明可自由指定 GUID 或解决本次野外案例 |

现有 `Units.lua` 优先收集上述 target/focus/队伍/首领/竞技场编号，再收集姓名板并按 GUID 去重；`UI.lua` 将结果设为按钮 unit 属性。重复添加已有编号不是新修复。这里核对的是源码覆盖范围，不是宣称所有这些编号已在本机通过悬停施法实测。

HealBot 的敌方列表使用已有玩家/成员目标、焦点、竞技场和首领编号，最终仍设置 unit 属性；Cell 的 NPC 条绑定 boss1–boss8，其队伍 GUID 查询也只转换到已有编号。源码版本及定位见 `healing/SOURCES.json`；[HealBot 对应版本](https://github.com/davidmarshall15/Healbot/blob/bcaf2db7c678b1841dab8c69bc5e566bb1bc3533/HealBot/HealBot_Panel.lua#L2771)、[Cell 对应版本](https://github.com/enderneko/Cell/blob/2fbdca82e79d22d6ae4c8fb4e9ea2148aeaf0df7/RaidFrames/Groups/NPCFrame.lua#L123)。

## API 证据的边界

Blizzard 导出文档的 Gethe live 镜像包含 [SetHitTestPoints / SetAllHitTestPoints](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPINamePlateDocumentation.lua) 以及标有 HasRestrictions 的 [SetNamePlateSize](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua)。接口存在不保证能够把任意敌人的原生命中范围搬到远离原姓名板的固定列表。

此次没有找到官方公布的 512×256 数值上限。该数值仅为本机此次请求的实际读回；live 镜像也不是已经核实匹配 Forever 70862 的专用快照，不能取代本机实测。UnitTokenFromGUID 查询已有编号，没有提供创建任意 GUID 对应原生鼠标单位的接口。

## 当前处理

保持 0.1.22 与已恢复的游戏状态，敌方固定格原生悬停标为未修复；本轮没有新运行时代码、重载、按键或公开发布。保留原始失败证据，不把模拟断言通过当作原生鼠标命中成功。

后续只有在出现新的公开 API、匹配当前客户端的可用实现，或改变交互范围的明确需求时，才有依据建立新的候选。新候选首先应证明“指针在格内、真实 mouseover GUID 等于该格怪物、当前目标不变”；此前不要求玩家重复按技能。已有失败路线不再作为待距离调整的可用方案。
