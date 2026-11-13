# 原生焦点菜单与宏入口补查

本目录四份文本来自Gethe导出的Forever70888精确提交4cd0ab752a77164f654ccbca9d0c1fe8dafceebe。仅保存阅读，未加载或执行；SHA-256见SOURCE.json。

- `UnitPopupSharedButtonMixins.lua:2261–2263`：设置焦点的真实动作是`FocusUnit(contextData.unit)`。
- `UnitPopupSharedUtils.lua:9–16`：菜单可有contextData.guid，也可按unit读取GUID；这个辅助字段没有被上述焦点动作使用。因此不能把“菜单持有GUID”当作“焦点接口接受GUID”。
- `UIMacrosDocumentation.lua:41–60`：RunMacroText和SetMacroExecuteLineCallback都标注HasRestrictions。所查公开C_Macro文件没有任意GUID条件注册器。
- `MacroExecutionManager.lua:16–29`：原生初始化保存回调函数后从全局移除，用私有编辑框派发宏行；这不是插件可接管的安全GUID判定桥。

这些路径解释了原生菜单/宏怎样触发已有单位操作，没有给出任意同名NPC在战斗中的自动GUID焦点方案。未以Lua派发源码推断全部C++内部实现，也没有新的游戏实测。
