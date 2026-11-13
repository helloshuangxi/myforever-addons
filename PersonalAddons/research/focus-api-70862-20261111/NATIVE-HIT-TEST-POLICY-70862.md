# 70862 姓名板原生命中与按钮转发核查

本记录只核查公开源码与作者发布说明；没有修改插件、移动姓名板或操作游戏。固定客户端构建 `1.60.1 (70862)`，Gethe 导出提交 `9dc84f0d3bbae1768ac3405b3716000bd93eda06`。校验记录见同名 JSON。

## 结论

`CanChangeHitTestPoints`、`SetHitTestPoints`、`SetAllHitTestPoints` 均不是本次新发现的替代机制。固定构建导出文档和上一轮原生命中实验缓存逐字节相同；包含它们的 FrameAPINamePlate、全局 NamePlate、NamePlateManager，以及 NamePlateUnitFrame 四份文件都相同。上一轮已经调用该套接口，不能因名称看似新增而再当成未试过的新方案。

`CanChangeHitTestPoints` 是修改许可谓词：有污点代码通常在战斗中不能修改，单位首次分配的 tick、同 tick 原生安全代码修改时有例外。它不代表可以越过原生空间命中范围，更不创建可用于 target/focus 的单位。`SetHitTestPoints` 相比 `SetAllHitTestPoints` 只允许给出单独 AnchorBinding 列表，两者受相同许可前置条件；没有文档中的任意 GUID 或单位 ID 输入。

[固定构建 FrameAPINamePlateDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPINamePlateDocumentation.lua#L10)

原生 NamePlateManager 文档明确所有命中仍夹在姓名板本体边界内。全局 `C_NamePlate.SetNamePlateSize` 另标有 HasRestrictions。per-plate AnchorBinding 不等于有一个独立的可搬动原生命中区，没有发现另一个忽略本体边界的公开参数。

[固定构建 NamePlateManagerDocumentation.lua:48](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateManagerDocumentation.lua#L48)；[NamePlateDocumentation.lua:46](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua#L46)

## 为什么普通按钮转发不是点击原生姓名板

原生 `NamePlateUnitFrameMixin:OnLoad` 注释明确说明，鼠标命中在 C++ 内部 hit-test frame 上完成，Lua 姓名板内容不接收点击，并执行 `EnableMouse(false)`。对应 XML 的 BaseNamePlateUnitFrameTemplate 是普通 Button，只有 OnLoad/OnEvent 脚本，没有 Lua OnClick target handler，也没有继承 SecureUnitButtonTemplate。CompactUnitFrame 绑定单位用于显示，并不把它变成另一个原生空间命中入口。

[NamePlateUnitFrame.lua:31](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua#L31)；[Blizzard_NamePlates.xml:93](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.xml#L93)；[XML scripts:361](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.xml#L361)

公开 `SECURE_ACTIONS.click` 仅在 delegate 无访问限制、无 ScriptedInput 禁止方面时执行 `delegate:Click(button)`；SimpleButton API 同样检查 ScriptedInput。该动作是调用 Button 点击处理，公开代码没有把它转成 C++ 姓名板空间命中的途径。不能从 UnitFrame 是 Button、或 Click() 可调用，推断能按原生单位身份选中怪物。目前没有找到可供安全按钮委托的另一只原生 target/focus 按钮。

[SecureTemplates.lua:557](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L557)；[SimpleButtonAPIDocumentation.lua:42](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleButtonAPIDocumentation.lua#L42)

## 其他插件当前如何处理

EnemyFrames 1.3.0 发行页面仍列 Forever 1.60.1，但当前作者描述开头已经说明新版更新后点击目标功能失效。作者在其发布帖解释，旧方案是扩大全部真实姓名板，再把各自命中锚放到插件条上，所以插件列表需要放在怪物屏幕位置之上；其后续跟帖明确说 newest build 使点击失效。这是作者自己的实现与失效报告，不是以旧宣传功能当成当前可用方案。

[EnemyFrames 作者当前说明](https://www.curseforge.com/wow/addons/enemyframes)；[原实现解释](https://www.reddit.com/r/WowUI/comments/1x0vw2v/comment/peofiv9/)；[作者后续失效报告](https://www.reddit.com/r/WowUI/comments/1x0vw2v/comment/19s6ufln3dko5/)

后续跟帖的绝对时间戳未核实：网页渲染只暴露 relative age，直接 HTML 请求被403阻止，故不推算确日，也不将 newest build 擅自等同于70862。该报告与本机既有失败现象相符，但本机实测才是当前客户端判据。

## 保留的证据边界

2016年 Blizzard 7.1 旧蓝帖只明确禁止 nameplate token 施法，原文还说可以 target，不能用它证明2026年70862无法TargetUnit。当前 exact token target/focus 失败以项目19:44硬件实测为准；C++实现本身不在导出Lua源码中。本调查没有找到新的公开精确选择接口，但没有把有限API族的查找写成对所有潜在客户端入口的数学证明。
