# 0.2.8 友方施法死亡判断测试

本机候选，尚未发布；本轮不启动或操作游戏。此修正针对session65“脱战、悬停自己、原目标尸体”的失败，不能提前宣称解决全部间歇性或战斗施法问题。

## 操作

1. 脱战`/reload`，`/mytargets log start`。
2. 保留怪物尸体为当前目标，悬停存活友方格（自己也可以），按原普通治疗或增益技能键。每次等待冷却，不连续快速连按；观察受术者和原目标。
3. 输入`/mytargets log mark 尸体目标成功`标注结果；未成功时把末尾改成“尸体目标失败”。可再测原目标活着和为空，分别标注结果。
4. `/mytargets log stop`，脱战`/reload`或正常退出保存。

不需开unitmatch或instanceactions试验。原技能仍受法力、距离、视线、冷却和游戏规则限制。

## 改动与日志

名称动作、当前目标fallback和清键状态驱动的死亡条件均明确为`@player`。真正受术者的help/harm/nodead及身份核验保留，原目标为空恢复为空，有原目标则恢复原目标。玩家自己死亡时仍拒绝准备并归还临时键。

NAME_BRIDGE_PRE保存version、deathGuardUnit=player、configuredCommand/configuredKey1/2、playerDead/targetDead及State、nativePlayerDead/nativeTargetDead及State，以及generatedDeathGuardMatches及State。POST保留这些施法前字段，另记afterPlayerDead/afterTargetDead、afterNativePlayerDead/afterNativeTargetDead、afterGeneratedDeathGuardMatches及各自State。native字段只调用固定的显式@player或@target死亡条件；generated字段只检查当前代理内部命令的固定保护前缀，不保存正文。公开bool只在public状态出现；nil/restricted/error/unavailable/nonboolean/invalid_result分别保留；内部命令另有not_applicable/nonstring状态，不造false。诊断不参与动作授权，不读取用户宏或保存错误堆栈。

继续沿用既有原生SENT/SUCCEEDED/FAILED、SPELL_SENT_DETAIL与PLAYER_TARGET_CHANGED。NAME_BRIDGE的本地attemptID仅关联同次PRE/POST；不新增观察窗或第二套ID。POST前后GUID相同不代表中间确实切过或成功施放。

## 验证

完成结果：29个Lua 5.1语法文件、29套12,916项离线检查全部通过；legacy路径336项，日志最多47字段（含公共附加字段），独立复核无阻断。

离线回归与独立复核完成后，结果和运行哈希写入candidate-validation-0.2.8.json，完整输出full-death-guard-0.2.8-tests.txt。离线宏条件模型不能替代客户端原生执行；真实施法及原目标恢复待用户复测。
