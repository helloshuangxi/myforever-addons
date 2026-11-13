# 其他插件的战斗焦点：11套实际源码路径复核

2026-11-12。本轮按用户要求继续查别人如何在战斗中设焦点，保留硬性条件：同名NPC必须自动匹配并确认GUID，不能降为人工确认或按名字碰运气。审查了11套插件/分支的动作路径，另核对Cursive作者当前说明、原生焦点菜单和宏派发；第三方代码只作为研究文本，没有安装或执行。

## 实现与所需前提

| 插件/分支 | 实际焦点或目标操作 | GUID的作用 | 是否提供所需实现 |
| --- | --- | --- | --- |
| HealBot 26.11.06 | 安全按钮type=focus，unit是既有单位；专门焦点按钮为target | 索引和反查已有按钮unit | 未发现任意NPC的战斗GUID闸门 |
| VuhDo 3.220稳定 | 安全模板`/focus [@SECURE_UNIT]`，从按钮unit属性填入 | raid/boss等已有单位的GUID表 | 没有创建任意野怪引用 |
| Clique 5.1.5 | 安全代理继承父框体unit/unitsuffix | 核心无GUID选焦点路径 | 自动物件注册还排除NamePlate |
| BattleGroundEnemies | 预配置玩家完整名字的目标→focus→lasttarget宏 | GetPlayerInfoByGUID识别玩家，NPC直接排除 | 玩家姓名不是同名NPC身份 |
| GladiusEx、原版Gladius、Gladius2026fork、sArena Updated2 | 预设arenaN/partyN等原生单位，右键原生focus | DR/显示数据定位到已有单位行 | 精确性来自原生单位索引，不生成野怪token |
| Enemy Frames 1.3.0 | 放大原生姓名板并把命中区映射到列表 | focus判断只绘制已有焦点边框 | 当前包无focus setter，作者报告新版点击失效 |
| Enemy Grid 9.1.5.055 | 旧版预建nameplateN按钮和mouseover宏 | 普通Lua缓存、过滤和任务显示 | Interface90105，无Forever70888适配/阳性 |
| AKForeverTargeter 0.3.0 | 仍按名字targetexact；右键安全动作为空，仅做列表操作 | 所查Lua未用GUID作焦点条件 | 比旧0.2.4更新，但没有同名GUID选择或焦点实现 |

上述源码没有提供可以直接迁移的“战斗中逐只Tab、自动核验指定GUID后才focus”的实现。GUID数据表存在、焦点黄框存在或原生焦点动作存在，不能互相替代。

三条完整审查链与固定源文件：

- [治疗/点击插件矩阵](../combat-focus-healing-20261112/HEALING-FOCUS-MATRIX.md)，官方包/提交及关键文件哈希见同目录SOURCE.json。
- [竞技场/战场插件矩阵](../combat-focus-pvp-20261112/README.md)，五套固定提交、原始行号和21份文本哈希见同目录SOURCE.json。
- [敌人列表插件矩阵](../combat-focus-enemies-20261112/REPORT.md)，包括EnemyFrames实际命中区、EnemyGrid旧版动作和AK0.3.0右键空操作；原文件及许可信息见同目录。

## 另查的第一手路径

[Cursive Forever 1.15.0作者说明](https://www.curseforge.com/wow/addons/cursive-forever)明确区分：Focus/Target行可点击施法，其他敌人仅显示；宠物目标按钮使用pettarget。它没有声明其他同名怪行能自动GUID定焦。本项仅核对作者说明，没有把它计入11套源码审查。

70888原生焦点菜单也未提供隐藏的GUID setter：`UnitPopupSetFocusButtonMixin:OnClick(contextData)`最终为`FocusUnit(contextData.unit)`。虽然`UnitPopupSharedUtil.GetGUID(contextData)`能读取contextData.guid或UnitGUID(unit)，焦点动作没有使用该GUID。不能因菜单上下文有guid字段就视为动作接受GUID。

原生C_Macro公开文档含RunMacroText和受限的SetMacroExecuteLineCallback，没有在所查文件找到注册任意GUID宏条件的入口。MacroExecutionManager在初始化时保存该回调注册函数后从全局清除，只用私有编辑框分派宏文本；这不是可供插件战斗注入GUID判断的接口。四份70888固定原始UI源码、来源和哈希保存在[原生补充审查](../combat-focus-native-20261112/SOURCE.json)。

## 剩余的几何假设：独立最小探针

EnemyFrames实际需要原生命中区，旧实验被C_NamePlate.SetNamePlateSize的512×256读回限制挡住。本轮另查原生base frame缩放是否能改变C++实际命中边界；公开源码不足以确认。[当前Plater](https://github.com/Tercioo/Plater-Nameplates/blob/e2d7ed66b3733e511a9ad4340e8c99bafc91dd65/Plater.lua#L7198)仍通过相同尺寸接口提交点击区，unitFrame/healthBar缩放仅说明视觉处理。不能将Frame:GetScale成功或视觉变大计作鼠标身份通过。

因此准备默认关闭、最长15秒的NativeScaleProbe，只在显式命令后临时调整单个原生姓名板base与视觉子层的缩放、映射到非交互验证区，记录该区外于原始矩形但位于扩大后矩形时实际mouseover GUID。无目标、焦点、施法或绑定操作；不改全局姓名板尺寸和CVar。结束恢复本次拥有的原值；外部较新写入不覆盖，进战时暂停采样并等待脱战恢复。

这只是检验未知原生几何行为，不是已经找到战斗焦点方案。只有真实鼠标在扩大边界外区域读到预期GUID，才值得继续检验原生焦点动作及战斗身份保持；即使几何通过，也不能直接算自动GUID焦点需求通过。

所有第三方源文件均在PersonalAddons/research隔离目录中，不进入发行包。未将旧客户端源码、模拟器或下载包版本标签当成70888真实游戏验证。
