# 副本敌方面板空白修复计划

## Goal
修复战前名单为空、战斗中新敌人加入或姓名板槽复用时，整个敌方面板保持空白的问题。先交付本机0.2.3候选与被动诊断；官网0.2.2保持现状，未验证候选不当作游戏已修复。

## Constraints
当前0.2.2已发布；友方施法和所有已准备的目标/焦点/标记/子目标安全动作必须保留。战斗内不得修改安全按钮unit/expectedGUID或安全属性、布局、按键、宏和CVar；不绕过身份复用检查。最多20格，保持5/10/20和紧凑尺寸。只有公开可读单位身份进入显示；不把受限身份当已识别。不得干扰真实游戏操作、改动其他插件或个人SavedVariables。

## Evidence and assumptions
Main.RequestRefresh与周期名单刷新均在战斗停止，UI.BindTiles也拒绝战斗重绑；RefreshTiles会隐藏与战前GUID不符的单位。这是确定可复现的空白路径。已有boss/队友目标兜底，没有显式副本禁用；副本中受限API值可能另外过滤单位。目前磁盘诊断止于session60，未覆盖用户本次副本。先修已知冻结缺口，同时增加识别拒绝/显示/可操作数量日志，待真实副本定位其他原因。当前只读画面角色已在野外，没有副本现场证据。

## Approach and file changes
- 新增EnemyDisplay.lua（Units之后、UI之前）：仅普通Lua显示名单。Update(tokens,limit,rows)以GUID去重，优先保留当前显示slot与对应战前slot的仍存活身份，填补空slot；Get(index)返回{unit,guid}，Reset清空。无frame/API写入或安全操作。
- Main.lua：战斗依旧不BindTiles，但收集敌人并更新EnemyDisplay；事件与0.5秒周期都触发，脱战清除显示名单并恢复原绑定。友方路径保持。
- UI.lua：战斗敌方读取独立displayUnit/displayGUID刷新姓名、血量、资源、相关效果、选中/焦点框与目标小条。受保护row.unit/expectedGUID不变。只有显示GUID、战前GUID及原unit实时GUID均吻合时放行原动作，其余主格与子条盾拦截并清理旧悬停状态。只读浮层准确提示战斗中发现、脱战后准备操作；不显示误导可施法圆点。
- EnemyTargetHover.lua：视觉与安全button分开，display使用父显示身份读取；usable及Bind仍核验战前身份，父为只读时不交还子条输入。
- Units.lua、Diagnostics.lua：提供有界收集统计/拒绝原因和INSTANCE_ENEMY_ROSTER日志，记录战斗、instanceType、姓名板CVar、发现/显示/可操作数。仅既有日志开启时记录，变化或有限心跳，禁止原始受限值、聊天、宏正文和任意表序列化。
- Core.lua、TOC：本机版本0.2.3，加载新模块；公开发行包不更换。
- 对应测试：先以真实0.2.2复现战前空名单→战斗新增不显示，再证明新视觉显示且旧动作不被放行；补日志与拒绝统计。

## Step-by-step plan
1. 备份当前源码和hash，保存日志只读快照，核对70938原生安全动作来源。
2. 并行实现纯视觉名单/UI与Main/诊断接入，各自限定文件所有权。
3. 定向模拟覆盖空名单、连续换怪、同名不同GUID、槽复用且旧怪从另一别名存在、5/10/20、主/子条盾、光环与tooltip身份一致、脱战重绑、友方0.2.2路由不回退。
4. 全部Lua5.1语法、目标插件全套模拟与独立安全审查；只做有必要的回归。
5. 由用户脱战重载并开启日志，在副本验证是否显示。真实施法/焦点/受法者效果不凭显示或模拟宣称成功。

## Risks
新怪战斗显示不代表获得新的受保护动作；当前客户端nameplate直接target/focus此前实测失败，预建40按钮并不能据此承诺修复。新/替换只读格子拦截旧输入，脱战后恢复常规准备。受限name/GUID/attackable仍拒绝，需要本轮副本日志确认是否还有独立问题。不可读值及跨读取GUID变化必须继续失败关闭。真实鼠标转焦点/受保护框运行与副本API表现不能由模型证明。没有本次实际副本验收时，结论只到本机候选。

## Clarification and current status
用户随后澄清“进副本就没有出现过”，且原生怪物头顶血条能看到；因此不能只按战斗冻结认领修复。已完成已知冻结缺口修补及拒绝诊断，27 Lua语法/26套11723模拟与独立UI审查通过；当前0.2.3冻结待真实日志。原生UnitGUID/UnitName可在身份受限时为secret，而native FontString/StatusBar可显示secret；候选仍拒绝未知身份，若新日志证实此分支则需另作只读secret显示设计，不得绕过安全动作核验。
