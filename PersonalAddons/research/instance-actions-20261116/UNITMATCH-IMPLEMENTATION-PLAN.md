# 0.2.6 单位匹配只读诊断计划

## Goal
让用户在副本找两只同名怪，用正常Tab或场景点击切换，验证plain nameplateN与target的公开等价比较能否分别得到true/false，并保存本机日志。只做这一关，不加入焦点、施法或自动选敌。

## Constraints
默认关闭、不持久化、不创建新UI/安全按钮/全局hook/键位/宏。不启动游戏、不改变当前游戏现场、不发布。保持既有友方、焦点、施法、格子与位置。新probe不直接读取或记录GUID/名字；旧单位资格管线的受限读取仍保持原行为，原始值不交给probe。受限结果和raw error不得泄漏。明确区分public bool、nil、restricted、error、unavailable与非布尔。

## Approach / file ownership
新UnitMatchProbe.lua，NS.UnitMatchProbe，入口 /mytargets unitmatch on|off|sample|status。Main只转发命令、事件、Tick；Core/TOC本机0.2.6；README和验证说明更新。新模块/独立模块测试由一位worker负责，root负责Main/版本/TOC/说明/整体验证，独立review复核。其他未提交工作按文件保留。

on要求副本party/raid脱战、原target明确为空、无待施法/物品光标、其他目标试验未活动，至少两个当前受限敌方NPC姓名板。通过RestrictedEnemyTokens/RestrictedEntry取得最多20个plain地址和冻结tokenEpoch；不读名字验证同名，由用户在场景选两只同名怪。存在/可攻击/非玩家均须公开资格。启动新的Diagnostics会话，记录probeID和logSession，自动采样baseline。

用户手动Tab或场景选中后，PLAYER_TARGET_CHANGED即时采样、0.15秒同target generation延迟采样；sample命令手动补采。所有读值先pcall+secrecy检查，日志记录CanCompareUnitTokens、ShouldUnitComparisonBeSecret及UnitIsUnit的各自状态和公开bool。只有当前生命周期有效、单位/target存在为公开true、两guard分别为公开true/false且等价为公开true才算qualified match。单次恰好一个匹配且其余地址均得到允许的公开false才能把该地址记入seen；不把unknown算false。跨采样至少两个冻结地址各自唯一公开匹配，日志仅记twoUnitsObserved，不冒充焦点/施法/鼠标/战斗通过。

身份为冻结地址+epoch；REMOVED/ADDED涉及该地址、换地图、进战立即结束，直接处理事件，不依赖Main稍后更新EnemyDisplay。延迟采样以active session+target generation取消过时回调。总时长180秒、最多40次样本（各最多20行），聊天仅输出汇总。默认无活动时event/Tick/status均不做单位API读取或动作。

off/超时/失效记录END；只停止本probe启动且会话ID仍相同的Diagnostics。若用户或其他模块开启新日志会话，不向其追加probe记录、不停止它。日志关闭、同会话日志失效或读取异常时结束，不能继续给成功提示。不会自动清target/focus，用户正常选择保留。

## Steps
1. 备份当前0.2.5，冻结计划和模块API。
2. 实现只读模块、严格原始值判别、日志会话所有权和生命周期终止；独立模拟真实事件与延迟。
3. 最小Main/TOC/版本接入，补命令/事件/定时转发测试，更新说明。
4. 独立审查并修正，运行完整Lua5.1/Targets回归、版本/TOC与文件边界审计，冻结0.2.6候选。
5. 给用户步骤：/reload；副本脱战清空target，两个敌方姓名板在范围内；unitmatch on；正常Tab选择两怪、等提示；unitmatch off；/reload保存。无需手写宏或输入测试按钮命令。

## Risks / native acceptance
比较许可和secrecy API可能缺失/返回受限，UnitIsUnit正匹配也可能受限，均如实记录unknown，不能宣称修复。姓名板范围变化可能终止测试，需要保持两怪可见。普通Lua公开比较若通过，也只为后续脱战逐次焦点方案提供依据，不实现原生mouseover或战斗安全身份分支。模拟不代替用户真实同名怪测试。
