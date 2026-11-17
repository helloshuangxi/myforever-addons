# 0.2.6 副本两只同名怪测试

本机候选已写入；未启动、操作或重载游戏，未发布。29 Lua文件语法、29套12571项离线检查通过，独立代码复核通过。真实副本的公开正匹配仍待用户实测。

## 操作

进入副本，保持脱战，靠近两只同名活怪，让原生姓名板同时可见，然后分别输入：

```text
/reload
/cleartarget
/mytargets unitmatch on
```

看到带0.2.6版本的开启提示后，用正常Tab或点击场景选中第一只，停一秒；再选另一只，停一秒。可以再来回选一次。聊天会给出测试编号和是否唯一公开匹配的汇总；测试编号是开始时固定的地址，不是动态重排的当前格号。

完成后分别输入：

```text
/mytargets unitmatch off
/reload
```

回复实际现象和“已保存”即可。没有匹配、接口受限或自动结束也保留日志，不必反复重新测试。无需新宏、测试按钮、`instanceactions on`或额外`log start/stop`。

## 实际记录

- 最多20个冻结姓名板地址与tokenEpoch，不直接读取/记录名字或GUID；旧资格管线保持原行为。
- `UNIT_MATCH_START` 开始、`UNIT_MATCH_ROW`逐地址三类读取、`UNIT_MATCH_SAMPLE`样本汇总、`UNIT_MATCH_END`结束。
- `CanCompareUnitTokens`、`ShouldUnitComparisonBeSecret`、`UnitIsUnit`各自记录状态和可公开布尔；nil、受限、异常、接口缺失与非布尔分别标注。
- 只有该样本里恰好一个合格公开true、其余全部合格公开false，才记录一个匹配地址；两个不同地址先后分别唯一匹配才出现twoUnitsObserved。
- 目标改变即时和0.15秒后采样；快速切换目标会取消过时延迟结果。
- 进战、姓名板移除/重加、换地图、日志失败/换会话、180秒或40样本结束。off只停止本测试拥有的原日志会话，不停止后来新开的其他日志。

测试器只观察，由用户执行正常原生选择。不创建UI/按键/宏，不自动切或清目标，不设焦点、不施法。它不会确认同名（由用户确认场景两只怪的名字相同），也不会把本测试通过扩大为原生mouseover或战斗焦点已经解决。

## 本机冻结与验证

修改限新UnitMatchProbe.lua、Core/TOC版本、Main命令/事件/Tick接入、README与说明；原单位读值、显示、UI、焦点和全部施法控制器与0.2.5备份字节相同。

新增模块146项行为模拟覆盖默认无副作用、准确值状态、两地址独立正匹配、延迟过期、生命周期、日志实际返回/所有权、重入与上限；Main追加10项命令/事件顺序/计时接入回归。完整输出 `full-unitmatch-0.2.6-tests.txt`。没有游戏原生引擎验收。

备份：`PersonalAddons/backups/MyForeverTargets-0.2.5-before-unitmatch-20261116/`。冻结哈希与范围见 `candidate-validation-0.2.6.json`。未生成发行ZIP或同步官网/软件客户端。
