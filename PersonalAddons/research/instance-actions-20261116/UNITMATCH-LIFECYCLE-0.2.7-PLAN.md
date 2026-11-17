# 0.2.7 单位匹配诊断连续性与失效定位

## Goal
修复session64中任一地址失效即在0.6秒结束全轮的问题，完整记录哪个地址失效、事件/定时检查来源以及原始读取状态。仅改只读诊断，不解决/扩展焦点、选中、施法或战斗功能，不操作或启动游戏，不发布。

## Constraints and scope
冻结的unit+epoch不更新、不复活、不把复用地址当原怪。原有单位显示、友方与施法/焦点控制器保持。日志只含公开标量与固定原因；不泄露原始名字、GUID、错误内容。保留180秒/40样本、日志会话所有权及默认无UI/按键/动作的限制。

## Architecture and file ownership
- worker负责UnitMatchProbe.lua及targets_unit_match_probe_test.lua；root负责EnemyDisplay只读元数据接口、Main的after-event转发、版本/TOC/README及元数据/接入测试；reviewer只读复核。
- 新Display.LifecycleState(unit)仅返回validToken、worldActive、epochKnown、currentEpoch（有值时）、tombstoned等内部公开元数据；不读取单位身份、不更新epoch/名单。无效unit不回显原值。
- Main现有probe.OnEvent在Display.OnEvent之前；新增probe.OnAfterEvent紧随Display.OnEvent之后，便于同一事件记录before/after epoch。默认关闭均无新读取。

## Per-address invalidation
生命周期或资格校验失败只永久退役对应冻结地址，记录UNIT_MATCH_INVALIDATED：index、unit、frozenEpoch、来源trigger/event、IsCurrent原始状态/公开bool、元数据读取状态及公开before/currentEpoch、worldActive/tombstone、exists/harm/player各自状态及公开bool、具体固定reason。

区分明确事件removed/added、world inactive、tombstoned、epoch missing/changed、IsCurrent public false无法解释、IsCurrent error/restricted/nil/unavailable/nonboolean，以及单位不存在/不可攻击/玩家/各资格读取失败。元数据不足时只标unknown或read状态，不猜实际移除。

退役一次后不再参与有效匹配；不直接停止probe或Diagnostics。每次新的退役增加cohort并清空本组seen，避免把不同有效集合的结果混成双单位证据。全无可用地址或少于2个也继续只读原始比较、记录insufficientValidUnits，不能计入qualified match，不自动接纳新epoch。聊天说明剩余地址不足或本组重新计数，用户仍可off保存。

所有冻结地址的ROW可继续记录当前原生比较及准确状态，但retired必须qualifiedComparison=false。统计区分raw true与有效true；只有当前组至少2个可用地址、恰好1个有效公开true且其余可用地址全为有效公开false时才计seen。retired地址原始true不构成旧身份匹配。

## Event and delayed safety
相关ADDED/REMOVED在before阶段立即退役，after阶段记录更新后的元数据；重复事件不重复退役/复活。每个公开事件/周期失效记录触发地址、事件、source。定时检查也能捕获漏事件的epoch变化/校验异常，保留两者区别。

失效详细事件最多120条（另加固定一次限流提示），限制日志噪声；最多40个完成样本，每个最多20个地址。过时或重入作废的部分ROW可能另行保留，不计完成样本，由180秒时限及Diagnostics的5000事件环形缓冲约束，不能声称全部ROW硬上限800条。target generation和cohort都参与过时回调/重入判定；跨组样本不能更新seen。必要日志记录返回false/异常或换会话仍终止，保留新日志；不误报双单位已记录。

全轮仍在手动off、进战、离开世界、其他动作试验、超时/采样上限或日志失败时结束；END注明stopTrigger及最后失效地址/原因（若有），与真正stopReason分开。

## Steps / verification
1. 备份0.2.6；固定元数据接口和诊断事件schema。
2. 实现逐地址退役、原因诊断、cohort及before/after事件；保持控制器边界。
3. 模拟session64失败类型：3地址baseline后0.601秒第3地址失效，probe和日志继续，前2地址先后匹配可形成同组双单位证据；这只是故障类型重现，不假定真实session64就是第3地址。
4. 覆盖全部IsCurrent失败状态、明确事件与元数据不一致/缺失、资格变化、全退役继续原始观察但不成功、复用不复活、cohort重置、延迟/日志重入、限流/180秒/40样本、所有fixture零动作/秘密泄漏。
5. root验证Display.LifecycleState不变更私有生命周期和正常显示、Main before/Display/after顺序，完整Lua5.1与Targets回归、独立复核、运行文件差分审计后冻结0.2.7。
6. 用户仍沿用/reload、/cleartarget、unitmatch on、正常选两只、off、/reload；接口提示带0.2.7。此轮不实际操作用户游戏。

## Risks
实际副本仍可能无有效地址或比较受限，只能准确记录，不能保证这次能正匹配。首次失效会改变组号，需在新组里重新各选一次。模拟/审查不替代副本实测；不把原始true当已冻结身份验证。
