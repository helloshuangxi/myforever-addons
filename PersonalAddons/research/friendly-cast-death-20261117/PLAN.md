# 0.2.8 友方施法死亡判断本机修正

## Goal
修正session65所暴露的原目标尸体误触发死亡保护，添加足以核对玩家/目标死亡、生成命令保护及原生施法事件的诊断，供用户复测。

## Constraints
仅本机候选；不启动、输入或重载游戏，不修改WTF、宏或永久键位，不发布或打公开ZIP。保留真正受术者help/harm/nodead、身份校验及原目标恢复。单位匹配试验和战斗控制器保持。日志仅公开标量/固定状态，不写用户宏或内部完整命令、秘密数据、错误堆栈。

## File changes and ownership
- worker：NearbyCast.lua、tests/targets_legacy_bridge_test.lua。三处死亡条件及该路径日志；执行有意义的遗留路径回归。
- root：Core.lua、TOC、README.md、TARGETS-VALIDATION.md、研究/冻结凭证。仅当worker或review提出必要接入问题再协调其他文件。
- reviewer：全差分只读审查，特别死亡单位作用域、宏/恢复顺序、secret处理、日志重入与字段预算。

## Step-by-step plan
1. 备份冻结0.2.7源码及哈希；保留session65原始证据。
2. NearbyCast.BuildMacro/namedAction、BuildFallback及状态驱动的玩家死亡保护明确为@player；不改受术者nodead条件。
3. NAME_BRIDGE_PRE/POST记录版本、配置按键、玩家/原目标死亡读取状态、原生玩家死亡条件诊断、生成的固定保护规则是否吻合；不记录宏正文。原生日志读取失败只标unknown/error，不影响动作。
4. 方案预审后不新增5秒窗口或第二套尝试ID，沿用NAME_BRIDGE本地attemptID与既有原生技能/目标事件的时间关联，减少日志回调对动作的干扰。配置按键/命令、原生显式死亡条件结果及代理内部保护前缀是否吻合留在PRE/POST。logger关闭/异常不得改变施法；不新增控制器。
5. 回归尸体/活目标/空目标、自己或另一名存活友方、玩家死亡/不可读、原目标恢复命令、状态驱动、日志缺失/抛错/秘密、字段预算；离线宏条件模型只作模型验证，不能称C++实测。
6. root运行全套Lua5.1检查，reviewer独立复核后冻结0.2.8，提供/reload、log start、复现、mark、stop、reload的短测试说明。

## Risks
session65只采到脱战失败没有同轮成功对照，修正后仍需客户端验收，不能保证解释全部间歇性或战斗施法问题。现有窗口连按同技能会ambiguous；原目标恢复读回不能代替中途选人或技能发送证据。死亡接口或宏条件未知不得被日志转换成可施法事实。日志读取和Record回调不得中断/重入修改动作；诊断字段不超过64上限。
