# 战斗中自动匹配设焦点：70888研究

2026-11-12。用户明确要求“必须由插件自动匹配并确认”，已经拒绝人工确认模式。该替代方案不实施，也不再次当作可交付修复。下文为最初只读研究记录；用户再次要求继续查其他插件后，已完成[11套源码审查](OTHER-ADDONS-AUDIT.md)，并准备默认关闭的[0.1.45原生缩放/映射探针](SCALE-PROBE.md)。探针24个Lua语法、10284项模拟及独立复核通过，尚无新游戏实测；不是战斗焦点修复，没有改用户设置或发布。自动GUID战斗焦点仍未解决。

## 目标与约束

希望右键指定怪物格子时准确设置其焦点，同名怪按GUID区分，最后恢复原目标；保留左键目标、Ctrl右键标记与已经验收的布局。不能仅删除脱战判断，也不能拿当前目标A冒充所点格子B。之前接受的多次右键是插件自动核验GUID的脱战流程，不等于用户已经接受战斗内人工确认。

## 本机版本与来源

本轮读取本机游戏Info.plist，安装版本为1.60.1.70888。先前缓存源码为70862，已追加核对70888的[精确提交4cd0ab7](https://github.com/Gethe/wow-ui-source/commit/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe)。其六个安全环境、动作派发及单位API文件与70862逐字节一致，逐文件路径与SHA-256见SOURCE.json。本机当前安装版本不等于已从先前日志证明运行中的构建；旧失败也不能仅因Lua源码一致就当作70888原生C++实测。

## 已证实的代码边界

1. [RestrictedEnvironment](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua)提供宏条件、UnitExists等，没有UnitGUID或UnitIsUnit。当前FocusCycle所需的“目标GUID等于指定格子GUID”不能直接移入该安全环境。
2. [RestrictedFrames](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua)允许安全句柄SetAttribute，但CallMethod强制普通环境执行且不返回被调方法结果；也不能在战斗中借普通未保护框的属性充当GUID数据桥。
3. [SecureTemplates](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)的原生宏动作派发到C_Macro.RunMacroText，focus派发到FocusUnit(unit)，没有赋予宏内普通Lua按GUID重写战斗动作的能力。
4. 同类插件[VoidBox的ClickCasting.lua](https://github.com/VoiD911/VoidBox/blob/main/ClickCasting.lua)在已有可操作单位时预设原生focus，没有单位引用时使用真实mouseover；其重新配置入口仍拒绝战斗。不是任意附近NPC的GUID焦点实现，亦非本机实测。

因此，稳定玩家/队伍/团队等可操作引用可以由预配置原生按钮执行；当前插件也已保留此路径。任意附近怪物格子的实时GUID自动判断仍缺少可用前提。静态NPC名称宏不能区分新出现的同名个体，不能当作准确修复交付。只在脱战时发现nameplate与target的GUID相等，也不能把该别名当整场战斗的身份凭据。

现有0.1.44正常游戏日志16742—17130：7次战斗姓名板焦点未成功，2次脱战名称恢复空目标成功，3次保留已有焦点，没有新的FocusCycle流程。它没有覆盖新的战斗候选。

## 可评审的替代操作：由玩家确认

历史提案：用户已拒绝。以下只保留被否决的交互差异，不再作为实施候选；没有实现或游戏验证。

1. 右键怪物格子后，使用提前创建的“下一只”按钮，每次真实点击执行一次选敌。普通Lua冻结所点GUID与原目标，只显示核对结果，不驱动保护动作。
2. 提示“已找到指定怪物”后，由玩家点击独立“将当前目标设焦点”按钮。其动作始终是当前目标，不依据普通Lua的GUID结果自动启用、停用或代点击。提前误按可能给错误个体设焦点，必须在界面及说明中直说，不能包装为插件自动精确匹配。
3. 用独立“恢复”按钮逐次反向选敌，由玩家看到原GUID已恢复的提示后停止。原目标为空时需要预设的明确清空动作，不能把反向选敌当清空。若初次点击安全环境记录了原目标是否存在，可据该允许的宏条件在恢复按钮中选择清空或反向；此细节仍需实现与实测，不能提前视为通过。
4. 窗口与安全按钮在脱战预建；战斗显示、隐藏与点击由预安装安全片段处理。普通Lua只更新非保护文字，不在战斗中创建/重锚安全按钮或改动作。Ctrl右键标记路由保留。关闭不冒充已恢复。

## 用户确认自动要求后的追加核对

追加检查公开的属性桥、状态驱动、原生单位框保护属性和受限句柄方法，没有找到能把普通Lua战斗中的实时GUID判断合法送入焦点动作的桥。普通框可被普通Lua改属性，但安全句柄在战斗中不能按此方式读取；保护框可供安全片段读取，却不能由普通Lua在战斗中按GUID改写。CallMethod不返回结果，仍不能补齐判断器。

还检查了不读GUID、借原生姓名板“当前目标”状态确认个体的候选：[NamePlateUnitFrame](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua)的准确isTarget由UnitIsUnit计算后保存为普通Lua字段，没有对应保护属性或受限HANDLE:IsTarget方法。选中边框与selectionHighlight在NamePlates.xml中是Texture，不是可SetFrameRef并读取的保护Frame；原生边框还有“isTarget或isFocus”的显示语义，不能凭可见性区分当前目标与旧焦点。该候选同样不能用于自动精确确认。

同类实现的有限追加检索亦未提供新入口：HealersMate-Forever仍用既有unit和原生focus，战斗中不重新配置；Sentinel BuffMeThen的附近玩家/完整姓名识别没有任意NPC的GUID焦点提交。仅采集/显示GUID、稳定单位引用、其他客户端扩展和模拟器不算本需求的证据。

结论限于已核对的70888公开代码与同类实现：当前没有可交付的“战斗中插件自动匹配指定GUID、设焦点并恢复原目标”修复。没有以新日志或预建按钮冒充功能实现，没有去掉现有战斗守卫，也没有将按名字或人工确认降级路线写入插件。后续需要新的可操作GUID接口或受限环境内可信实时身份判定器，才有足够前提继续实现。不是宣称穷举了客户端所有C++内部能力；当前状态仍为未解决。
