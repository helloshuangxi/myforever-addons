# 0.2.7 单位匹配：连续记录与失效定位

本机测试候选，默认关闭，不公开发布。本轮不操作、启动或重载游戏。原生两只同名怪的正匹配仍待用户确认。

## 测试步骤

1. 进副本脱战，靠近两只同名活怪，确保原生姓名板可见；输入 `/reload`、`/cleartarget`。
2. 输入 `/mytargets unitmatch on`，确认开启提示包含 **0.2.7**。
3. 用原生Tab或场景点击在两只怪之间来回选择，各停一秒。如果提示测试组重置，在新组里再各选一次。
4. 输入 `/mytargets unitmatch off`，再 `/reload` 保存。日志自动开启/结束，不需新宏或测试按钮。

即使提示地址不足、无法匹配，也结束并保存这次记录即可。新增诊断会说明具体哪个地址、在哪一步、以何种读取状态失效。

## 本次修正

0.2.6曾在约0.6秒后因为任一冻结地址校验失败而结束整轮，只留下空目标基线。0.2.7改为该地址永久退出有效集合，其他地址继续观察，日志不因这一个地址而关闭。

每次新失效都增加测试组号并清空本组匹配计数；同一地址重复事件不反复重置。旧epoch不更新、不复活，不会把复用后的地址认成原来的怪。

少于两个有效地址甚至全失效时，仍记录当前原生比较和诊断；已失效地址的原始true也不会计为原怪的有效匹配。只有同组至少两个有效地址，先后各自唯一公开true且其余有效地址公开false，才提示双单位观察完成。

## 失效日志

- `UNIT_MATCH_INVALIDATED`：首次失效，记录unit、测试index、frozenEpoch/tokenEpoch、reason、trigger、triggerEvent、stage、currentEpoch及其状态、worldActive/tombstoned、IsCurrent原始状态与公开bool、exists/attack/player各自状态；记录剩余有效数和前后组号。
- `UNIT_MATCH_LIFECYCLE`：明确before/after阶段的事件元数据，after在EnemyDisplay处理事件后采集，不能把before的旧epoch当成更新后值。
- `UNIT_MATCH_ROW`：继续记录公开的原生比较，明确retired、invalidReason、currentFailureReason、rawComparisonReadable和qualifiedComparison。
- `UNIT_MATCH_SAMPLE`：区分rawTrueCount与qualifiedTrueCount，记录validUnits/invalidUnits/insufficientValidUnits及cohort。跨组和过时target generation不混计。
- `UNIT_MATCH_END`：记录真实reason/stopTrigger，并单列lastInvalidUnit/Index/Reason/Trigger，避免把最后地址失效与整轮停止原因混为一谈。

读取状态保留public、nil、restricted、error、unavailable和格式错误；不保存raw error、名字、GUID或宏正文。首次失效日志最多20条，独立于重复生命周期细节的120条上限；细节到限只记录一次限流标记，诊断仍继续。

手动off、进战、换地图、其他目标动作试验、日志失败/变更、180秒或40个完成样本仍会结束整轮。过时或重入作废的部分ROW可额外保留，由180秒及Diagnostics的5000事件环形缓冲约束，不计为完成样本。只结束本probe拥有的日志会话，不停后来新开的会话。

## 验证范围

本机离线验证通过：29个Lua文件语法、29套12,783项检查；其中单位匹配318项、生命周期显示432项、生产Main名单集成120项。独立复核通过。

保持只读，没有新UI/动作按钮/按键/宏/选中/焦点/施法行为。EnemyDisplay新增接口仅返回已有私有生命周期的公开元数据，不初始化或改变epoch，不读取单位身份。

核心回归包括“3地址baseline后第3地址在0.601秒失效，probe和日志继续，前2地址随后分别形成有效匹配”；这是故障类型的模拟，不表示真实session64已确定是第3地址造成。

完成时的完整语法/模拟、独立复核、运行文件范围及哈希见 `candidate-validation-0.2.7.json`；测试输出 `full-unitmatch-0.2.7-tests.txt`。备份为 `PersonalAddons/backups/MyForeverTargets-0.2.6-before-unitmatch-lifecycle-20261116/`。离线通过不等于游戏已验收，也不扩展为完整焦点或mouseover修复。
