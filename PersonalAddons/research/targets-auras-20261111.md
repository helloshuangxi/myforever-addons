# 目标选择光环显示：接口核对

2026-11-11，只读研究；未安装或执行第三方代码，未操作游戏。客户端为本机 `_forever_`，下述源码示例不是本机运行验收。

## 采用原生容器显示

采用 `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`，以 `SetUnit(unit)`、`SetEnabled(true)` 驱动。光环图标、层数、冷却由原生容器填充；不把受限光环数据读回 Lua 后自行比较。

固定少量图标可用 `AddAuraSlot(key, filter, options)`：每槽从该过滤结果按原生排序选一个，`initializeFrame` 设置大小与锚点；它不参与动态布局。`AddAuraGroup` 支持每组 `maxFrameCount` 和流式布局，但没有查到跨组共享的显示上限。过滤条件中的 `|` 是组合约束，不可当作任意 OR。不能读取受限图标数、显隐或尺寸来模拟跨组优先级。

推荐固定分类位置：友方一槽可驱散减益、一槽自己的增益；敌方显示自己的减益及增益。若另外展示自己受到的所有减益，需要单独明确该类槽位。槽为空时原生自动隐藏。显示数量、排序和分类须与最终说明保持一致，不宣称展示所有光环。

- [CustomAuraContainer 实现](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua)：`AddAuraSlot`、`AddAuraGroup`、`SetAuraSlotFilterString`、`SetAuraGroupMaxFrameCount`。
- [容器常量与默认项](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua)：固定单槽、每组上限、原生 `Default` / `UnitFrameDebuff` / `ExpirationOnly` 等排序。
- [图标显示接口](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua)：`SetIcon(texture)`、`SetApplicationCount(fontString)`、`AddDispelTypeTexture(texture)`、`SetDurationCooldown(cooldown)`。

## 自己施加与自己可驱散

[客户端 AuraUtil 的过滤常量](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua) 明确区分：

| 过滤串 | 范围 |
| --- | --- |
| `HELPFUL\|PLAYER` | 玩家本人、本人宠物或载具施加的增益 |
| `HARMFUL\|PLAYER` | 玩家本人、本人宠物或载具施加的减益 |
| `HARMFUL\|RAID` | 玩家自己能驱散的减益 |
| `HARMFUL\|RAID_PLAYER_DISPELLABLE` | 团队成员能够驱散的减益，不等于自己能驱散 |

因此用 `HARMFUL|RAID` 完成“我能清除”的过滤，不按职业固定猜测。旧版 Cell Vanilla 的职业表甚至包含圣骑士 Bleed，且没有逐个检查是否学会，不适合直接移植。`isFromPlayerOrPlayerPet` 也不能代替 `PLAYER` 的本人范围。

若未来确实需要自行判断已学技能，应优先 `C_SpellBook.IsSpellKnown` 的公开布尔结果；`IsSpellInSpellBook` 可能对未学会但显示在技能书的替代技能返回 true，不能单独作为能力依据。当前原生过滤方案无需维护等级、技能等级、天赋或专精驱散表。

## 受限读取与刷新

[UnitAura 文档](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua) 为 `GetAuraDataByIndex` / `GetAuraDataBySlot` 标注光环访问限制；本机缓存 HealBot Forever 补丁也针对战斗期间抛错及 secret 结果使用 `pcall` 和字段检查。Lua 公共读取可以补充格子浮层，但失败时应清除旧明细，不能将旧缓存当作当前状态；战斗图标由原生容器负责。

[AuraContainer 生命周期](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainer.lua) 在可见且 enabled 时注册 `UNIT_AURA`，`SetUnit`、显隐或启用状态变化会更新注册并重建光环。无需每帧重新枚举。学习技能或切换专精后可额外调用 `UpdateAllAuras()`，确保能力过滤重新评估。

原生 AuraButton 支持自己的光环浮层，但启用它的鼠标感应会改变格子原有悬停路径。为保留已有悬停技能、左键目标、右键焦点及 Ctrl+右键标记，容器及图标应关闭鼠标点击和鼠标移动感应；可读详细信息追加到已有格子浮层，不覆盖已有单位提示载荷。

## 已有本机示例

- `PersonalAddons/research/guid-mouseover-20261110/enemyframes/source/EnemyFrames/Auras.lua`：20–43 行为图标、层数、类型边框与冷却；207–239 行为原生容器及 `HARMFUL|PLAYER` 组；EnemyFrames 1.3.0 的离线参考，不能当作本插件已实测。
- `PersonalAddons/research/guid-mouseover-20261110/healing/Healbot/HealBot/HealBot_ForeverFrames.lua`：104–140 行创建穿透输入的原生光环容器；174–180 行建立 `HARMFUL|RAID` 驱散覆盖层。
- 同目录 `Healbot_Aura.lua`：约 2500–2590 行拒绝 secret 字段并保护索引读取。其旧 `RAID_PLAYER_DISPELLABLE` 缓存不适合作为“本人可驱散”的判定移植。
- `PersonalAddons/research/guid-mouseover-20261110/healing/SOURCES.json` 保存 HealBot、Cell 的来源提交信息。

实施后仍须本机验证容器存在、正常/受限战斗显示、输入穿透、单位复用清理和学习驱散技能后的变化。当前研究没有替代这些实测。

## 0.1.32 全来源显示修订

用户明确改为全部buff/debuff，替代上文的本人过滤和固定两项推荐。使用HELPFUL/HARMFUL无PLAYER条件、无追踪排除；完整原生组maxFrameCount默认math.huge。原生SetFlowLayoutMaximumLineSize可限制行宽并换行，但动态容器尺寸为secret，不应读回用于重排安全格。完整显示采用共享独立展开层；背景若随动态容器伸展，需使用DisableUntrustedLayoutScriptsTemplate。友方本人可驱散提示使用HARMFUL|RAID，非本人可驱散组使用HARMFUL|!RAID，两组互斥。

原生布局参考：[Blizzard_AuraContainerFlowLayout.lua](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerFlowLayout.lua)。常驻摘要显示上限与完整展开范围须在用户说明中明确区分，不能把四枚摘要称为全部同时可见。实际显示仍受客户端向目标单位提供的光环数据范围限制。

## 0.1.33 常驻大卡片与溢出边界

用户选择扩大格子而非悬停显示。原生完整组保留全部来源，固定卡片改为136×140，每类5列12像素、1像素间隔，103像素视口能同时显示40项。40仅为本版几何容量，UnitAura接口没有每类40的已证实硬上限，不能据此截断列表。

FlowLayout没有最大高度自动fit选项，不能把secretwrap高度读回后重排安全按钮。采用UIParent下独立未保护ScrollFrame作视觉裁剪，所有图标输入穿透，原单位按钮仅将滚轮公共delta转发；仅传入插件自己维护的公开数值偏移。公开原生范围可用于钳制；范围受限时，仅脱战枚举公开光环来确认范围，战斗不读取/推断秘密数量。战斗中超出此前公开范围的新光环，不外推滚动可达性。

[ScrollFrame API](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleScrollFrameAPIDocumentation.lua)的SetVerticalScroll为受保护接口，secret参数只允许未污染环境；[Slider API](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleSliderAPIDocumentation.lua)的SetMinMaxValues也有同类限制。因此不把secret范围转交自定义Slider冒充可用方案，滚动须保留真实客户端实测边界。

## 0.1.35 相关来源与排除常驻增益

用户恢复相关来源并明确排除虔诚光环等常驻效果。增益使用HELPFUL|PLAYER及candidateFilters.maxDuration=math.huge；原生[参数校验](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua)允许非负数，[实际谓词](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua)在maxDuration非nil时排除duration==0，没有对math.huge特殊忽略。故只隐藏永久增益，不设有限时长上限，不依赖Lua读取受限时长。减益不应用永久筛选，以免遗漏可驱散减益；友方用RAID及PLAYER|!RAID互斥组。独立子目标条完全移除光环。
