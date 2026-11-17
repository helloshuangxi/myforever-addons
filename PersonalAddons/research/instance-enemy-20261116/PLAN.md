# 0.2.4 副本受限身份显示计划

## Goal
依据session61确认的GUID/name受限过滤，恢复副本敌人姓名与血量显示。本机候选，不发布或擅自重载游戏。原生显示成功与可操作身份分别核验。

## Evidence
0.2.3，session61，2026-11-16 00:20:56–00:21:38，41事件。party副本且脱战，两姓名板CVar为1。target存在/可攻击/非玩家，name与GUID均restricted。最后2个姓名板+target共3个入口因GUID拒绝，非3只不同怪；public unique/display/action均0。name_unreadable=0是先在GUID退回。原生FontString/StatusBar支持secret显示，不能据此比较/还原/记录secret。

## Constraints
不放宽NS.ReadUnit公开身份/Collect/BindTiles契约；不把token或事件代数当GUID。限定真实NameplateTokens、公开exists/player/attack判定；未知、错误或非敌对继续拒绝。受限名字只在单次绘制中直接交SetText，不缓存/拼接/比较/测宽/日志/GetText。raw血量资源仅native sinks，类型颜色只有公开时使用。尺寸位置/5、10、20保持。所有未知身份主格及子条始终盾拦，row.data=nil，不交给点击、焦点、标记、宏或施法控制器。友方和CombatCast/CombatHover/NearbyCast/Auras/FocusCycle保留字节。

## Architecture and file changes
1. Units.lua新增ReadRestrictedEnemyVisual(unit)与RestrictedEnemyTokens()、SetRestrictedEnemyName(fontString,unit)。只收实际nameplateN，公开确认存在/敌对/玩家类别，并证明GUID或名字确为受限值；missing普通身份不冒充受限。返回public metadata和仅native数值sink可消费的health/power字段，无name/nativeName/guid/targetName字段。SetRestrictedEnemyName仅局部raw UnitName→pcall SetText，不返回原始文字，API失败固定false。资格读取前后再次公开确认存在/分类/敌对。
2. EnemyDisplay.lua Update增加第4参数restrictedTokens，将{unit,restrictedIdentity=true,tokenEpoch}放入剩余视觉slot。public GUID和restricted token分别去重，不跨通道猜同一目标；原prepared和现有public slot优先。OOC也允许restricted视觉补位，永不传入BindTiles。OnEvent/IsCurrent维护ADDED/REMOVED/world生命周期：移除后tombstone直到ADDED；world清理slot并更新代数；代数只做显示地址有效期。现有protected hot-hover行预留原身份或空，不填restricted。
3. UI.lua新增完全独立restricted绘制分支，row.data=nil、displayGUID=nil、displayReadOnly=true、displayActionReady=false。固定name label由SetRestrictedEnemyName绘制；数值nativeAmount；清选中/焦点/任务/标记/castDot/auras/敌人目标小条。主/子盾一直拦，tooltip只静态身份受限说明，不读取label。普通公开分支不回退。统计section.restrictedCount/nameRenderErrors。
4. Main.lua保持公开Collect/Bind/OOC恢复逻辑，OOC绑定后与combat刷新时另外取得restricted tokens并Update显示；world inactive不重建；将生命周期事件转交EnemyDisplay；日志在Refresh后取实际数量。Diagnostics.lua仅增restricted候选token/实际显示/渲染失败计数，不保存raw数据。
5. Core/TOC/README升本机0.2.4并说明只读边界。现有官网/客户端0.2.2不变，无发行ZIP。

## Steps
先独立复核日志与保存源码备份；并行实现数据通道与UI/视觉slot，root负责Main/诊断/版本；定向复现受限GUID导致旧版空与新native sink显示；全套Lua5.1/模拟、独立secret-flow和旧安全动作审查；冻结候选后由用户在同一副本脱战重载并验证名字/血量实际画面及日志。不进行游戏操作或用模型冒充原生显示。

## Risks
匿名nameplate不能保证跨读值是同一GUID，不承诺精确去重、距离排序、目标/焦点匹配或施法。受限值不进row.data和日志；native SetText若被客户端拒绝记录固定错误并清掉该格，不能字符串化异常。原安全hover owner未真实离开时预留格，不能用盾Show冒充已清override。真实副本渲染尚待验收，不能将本轮脱战证据扩大为战斗验证。

## Candidate result
本机0.2.4已冻结：27Lua语法、27套12322模拟及独立7套3721定向复核通过。旧0.2.3实际生产UI对同一受限用例失败已保存；新通道在模型中直达原生sink、无raw名字/GUID缓存或动作通路。5个控制器模块与备份字节一致。OOC宿主必须普通字段与native属性均已清空才接新显示；否则保留原身份或空，覆盖静止入战STATE几何旧绑定风险。候选未由代理重载、未发布，未修改WTF；真实0.2.4副本名字/血条画面待验。

## Native acceptance
用户确认0.2.4姓名/血条均已显示并保存。root只读CUA在暴风城监狱观察到2格姓名与红血条，无游戏输入；最新session62 50事件确认版本0.2.4，party脱战，restrictedDisplayed 0→1→1→2→3、nameRenderErrors0、actionable0，无UI_ERROR_MESSAGE/ADDON_ACTION_BLOCKED/ADDON_ACTION_FORBIDDEN。仅认领本场景初始显示，不等同3独立GUID身份、战斗或动态掉血验证。候选仍未发布。
