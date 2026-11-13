# 原生战斗日志离线采集

`coach_combat_log.py` 仅用 Python 标准库，读取本地原生日志的显式时间窗，写出匿名 JSON。输出固定为 `postcombat-only`；不联网、不调用 AI、不实时监视、不控制游戏。源日志只读，不应放进安装包或上传。

```bash
python3 PersonalAddons/tools/coach_combat_log.py \
  --log _forever_/Logs/WoWCombatLog-110826_111139.txt \
  --start 2026-11-08T11:28:20+08:00 \
  --end 2026-11-08T11:29:25+08:00 \
  --log-timezone +08:00 \
  --output PersonalAddons/work/coach-validation/native-session-7.json
```

起止边界包含在内，必须写时区。`--log-timezone` 是源文件时间的固定 UTC 偏移。已有报告默认拒绝覆盖；检查路径后可加 `--force`。输出不能替换源日志。新文件权限为 `0600`。本工具按原始时间字面值解析，不修正插件会话整秒起始造成的偏移；比较两套时间线时先用同一次施法对齐。时间窗不等于已识别的战斗边界。

本人识别要求窗口内仅存在一个同时具有 MINE 归属、PLAYER 单位类型和 Player 类型内部标识的身份；没有或出现多个即报错。宠物、守护者和其他玩家的输出不计入本人。只保留直接涉及本人的白名单事件，以及已关联目标的死亡事件。内部标识只在进程内关联，JSON 仅含 `self`、`target_1` 等别名，不含角色名、法术名称、GUID、聊天、源文件路径或原始行。别名对应的玩家/生物/宠物类型可保留。

可记录施法开始/成功/失败、伤害、受击、躲闪/招架等未命中、光环、治疗、打断/驱散、资源和死亡事件；保留白名单数字和固定枚举。法术 853 的施法或光环事件会保留，但不能仅靠光环事件自动推断控制是否生效、持续时间或漏控。不存在的事件表示“未观测/未知”，不表示漏放技能。工具不内置预期循环、装备/天赋建议或升级路线。

已验证格式为 Forever 1.60.1 的 log version 22 / project 18。其头部 `ADVANCED_LOG_ENABLED=0` 时，实际事件仍可带有 19 项高级字段，因此按已验证的事件长度识别布局。可读快照包括生命、资源、攻击/法术强度、护甲、护盾、世界坐标、地图和朝向；未知高级字段与最后一项的玩家物品等级/生物等级不输出。其他版本和不完整布局只保留可识别的事件头，数值省略，并标记 `partial`，不按旧索引猜。

19 项高级块的字段位置也参照解析工具作者的[实测格式说明](https://wowcoach.gg/docs/combat-log/advanced-logging)；本项目以本地实测数据为验收依据，不依赖该网站运行，也不会向其上传日志。

同一时刻、来源、目标与伤害后缀完全一致的 `SWING_DAMAGE` / `SWING_DAMAGE_LANDED` 按一击计数，同时保留两方快照。同类型重复行不会自行合并，避免抹掉真实同时攻击。伤害 `amount` 是已减伤、含过量击杀的数值；`baseAmount` 仅作诊断，不用于总量；`effectiveAmount = amount - max(0, overkill)`。阻挡、抵抗、吸收分开列出，不再加进伤害。`DAMAGE_SPLIT` 不计入本人输出总量。

治疗 `amount` 为实际治疗事件数值（含过量），`baseAmount` 单列；吸收为零时 `effectiveAmount = amount - overhealing`。治疗吸收非零的语义本次尚未实测，保留数字但不推断有效治疗。缺少任何必要字段时对应汇总为 `null`，并标记 `partial`；完全没有该类事件时也是 `null`，标记 `not-observed`，不假装测得零。

模拟回归：

```bash
python3 -m unittest discover -s PersonalAddons/tests -p test_coach_combat_log.py -v
```

这些测试使用合成身份、名称和事件，不读取真实日志。真实采集范围与游戏实测结论需另行说明，不能把模拟通过视为游戏功能已验证。
