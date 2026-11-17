# session63 后的解决方向：原生目标等价比较

日期：2026-11-16。本轮为研究和源码审计，未改插件运行代码、键位或宏，未发布。只读查看游戏时，用户已离开副本、正在城里制作物品，因此没有执行任何游戏输入或新原生试验。现有0.2.5候选仍默认关闭。

## 新线索与假说

session63已证实原生target/focus按钮确实调用正确nameplate地址，但目标/焦点未建立；同地址的原生SetRaidTarget能给两只同名怪独立设置并清除标记。不同操作接受单位地址的范围不同，不能从标记成功推出可选择、可焦点或可建立mouseover。

新的候选是沿用用户已接受的**脱战逐次真实点击选敌**，把原来依赖公开GUID的身份判断，增加为**生命周期冻结的plain nameplate地址 + UnitIsUnit(nameplateN, target)公开布尔**。它比较的是单位等价关系，不是名字或标记，也不读取/解析受限GUID。

这不是已经修好的方案。session63只有原target为空时的公开false；仍缺一次副本里“真正选中对应怪物后返回公开true”的正对照。

## 当前构建的依据

固定70938 UI源提交：`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`。

- `UnitDocumentation.lua:2278–2292`：UnitIsUnit标有RequiresComparableUnitTokens及SecretWhenUnitComparisonRestricted。
- `SecretPredicatesDocumentation.lua:8–17`：包含player或target的单位对可比较；可比较本身不保证所有结果公开。
- 同文件118–120：compound token（如boss1target、party1target）在受限地图比较结果总是secret，不能用这种链式别名兜底。
- `SecretPredicateAPIDocumentation.lua:11–24`：C_Secrets.CanCompareUnitTokens查询是否允许比较。
- 同文件252–265：C_Secrets.ShouldUnitComparisonBeSecret查询比较是否产生secret。
- 现有RestrictedEnvironment没有UnitIsUnit/GUID/C_Secrets身份比较器；普通Lua的公开比较不能直接变成战斗中的安全动作分支。

三个精确源文件及SHA-256保存于 `comparison-native/SOURCE.json`；只读取，没有在游戏中执行这些下载文件。

## 第一关：最小原生正对照

先要求副本脱战、原目标与原焦点均空、无施法/物品光标、没有其他目标试验或用户操作。

1. 冻结当前有效的plain nameplateN地址与tokenEpoch，记录比较许可/保密状态及当前公开false。
2. 一个真实硬件点击运行一次原生 `/targetenemy`。被动观察原生选敌返回后、清空前的各地址比较结果，不在observer中选择、施法或设焦点。
3. 同一原生宏随后 `/cleartarget`，恢复已确认的原空目标。记录即时及延迟目标为空，不使用targetlasttarget。
4. 必须至少看到一个仍处于原生命周期内的地址：许可为公开true、比较保密为公开false，且实际UnitIsUnit为公开true。其他仍存在的不同怪物地址应为公开false。任何guard缺失、nil、secret、异常或非布尔均记unknown，不推进。

日志只保存固定事件/地址/epoch/公开布尔及public、nil、restricted、error等状态，不输出secret或raw error。不能沿用NS.Read把读取异常/secret/真实nil合并后误说“没有匹配”。

这关通过只证明普通Lua能准确比较选中的怪物，不证明焦点、恢复、鼠标输入、普通技能代理、玩家宏或战斗功能已完成。

## 第二关：脱战精确选中与焦点候选

必须在第一关原生正对照通过后才实施：

1. 给FocusCycle增加独立身份类型：guid、plate+epoch、empty。原公开GUID路径保留；不能只替换goalGUID一次而放过ownedTarget/恢复/干预判断。
2. 指定格子的目标地址与epoch冻结。每次真实右键只推进一次原生Tab；公开UnitIsUnit(goal, target)==true且生命周期未变，才记为找到。
3. 下一次真实确认点击通过原生 `FocusUnit("target")` 设置焦点。以公开UnitIsUnit(target, focus)==true核验，不再向FocusUnit传nameplate地址。这个设置和原目标恢复仍须单独实测。
4. 原目标空时原生cleartarget。原目标A非空时，开始前必须找到能公开等价比较的独立plain地址A并冻结epoch；完成后逐次原生Tab找回A，公开比较true才记恢复完成。无法捕获稳定独立地址则拒绝开始恢复事务。
5. 每次新选中目标也须建立独立可比较地址以判断目标所有权。选到未暴露单位、比较未知、用户换目标/焦点、移除/重加/世界变化或进战时中止；不能清掉不再属于本次事务的目标。

NAME_PLATE_UNIT_REMOVED/ADDED事件应直接使相关冻结会话失效；Main目前先处理FocusCycle再处理EnemyDisplay，不能依赖稍后更新的epoch。InstanceActions.VisualEntry会更新token生命周期，它的动态entry不能直接充当被冻结怪物身份。

不能把target字符串本身保存为原目标身份；它会跟着每次Tab改变。多次Tab后targetlasttarget也不代表最初A。目标选择若也需要逐次输入，会改变左键体验；用户之前接受的是多次右键焦点，不能自动扩展成多次输入的悬停施法。

## 全需求的状态

| 需求 | 当前状态与下一步 |
| --- | --- |
| 副本格子打标记 | 当前脱战场景已证实原生标记动作；实际Ctrl右键菜单、鼠标与战斗仍未验收 |
| 副本同名怪精确焦点 | 新的plain-token等价比较逐次点击候选，第一关尚未实测 |
| 副本精确选中 | 同一新比较器有研究价值，但不等于已经支持一次左键完成 |
| 任意敌人格子原生mouseover/玩家宏 | 仍未找到创建原生mouseover的受支持入口；Tab比较不会创建mouseover |
| 悬停按一次普通技能键 | 不因多次右键焦点候选而自动得到；未实现 |
| 战斗自动匹配后设焦点/悬停施法 | 安全环境身份比较缺口仍在，尚未解决 |

## 其他作者的新增交叉核对

[Threat Board1.1.0作者项目页](https://www.curseforge.com/wow/addons/threat-board)（11月14日）明确要求用正常/Tab选敌，敌人行不支持点击选择。这是作者的兼容性说明，不是Blizzard官方政策，不能夸大成所有可能入口均不存在的证明。

[EnemyFrames1.4.0作者更新](https://www.curseforge.com/wow/addons/enemyframes/files/9580727)移除了已失效的Click to Target；[AKForeverTargeter0.3.1](https://github.com/ajkatz/AKForeverTargeter/releases/tag/v0.3.1)仍走名字选择，不能精确指定另一只同名怪。本轮未找到“先写标记，再按标记创建target/focus/mouseover”的可移植实现。

## 审计结论

没有找到0.2.5派发配置错误足以解释TargetUnit/FocusUnit失败：原生调用与正确参数已观察到，UseOnKeyDown、重映射、模板早退不是本轮失败原因。换模板或重复GUID直传不构成新方案。

当前最有信息量的工作是第一关原生正对照。它通过后再扩展身份状态机；它失败则保留真实阴性，不交付又一套未经证实的焦点或施法承诺。
