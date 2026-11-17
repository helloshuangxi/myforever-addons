# 副本原生操作离线候选计划

## Goal
在已可显示的受限敌人格子上提供左键选中、右键焦点、Ctrl右键标记和普通技能悬停的原生动作试验，捕获真实执行读回。用户明确要求不启动游戏：只离线代码/模拟，当前无游戏进程。不发布，0.2.4默认路径保留，显式on才接入试验。

## Constraints
名字/GUID受限，不能解码、拼成宏或造GUID；不重复已失效的巨型姓名板/命中区方案，不改CVar、原生姓名板、个人宏/永久键位/面板位置。不能把70938 Lua原生按钮派发定义当C++接受证明：旧70862 nameplate TargetUnit曾失败，EnemyFrames1.4也关闭点击。现候选是验证当前70938副本四动作入口，不宣称已修通。

## Approach and files
新增InstanceActions.lua：默认不创建/启用，/mytargets instanceactions on在脱战时为当前受限格子准备透明SecureUnitButton覆盖层，固定unit=nameplateN、left type=target/right type=focus，Ctrl右键由安全click打开本行8标记按钮。覆盖层锚定现有格，无新大面板。原0.2.4输入盾和原安全row.unit/GUID保留，新透明原生层独立持有unit。
悬停仅接已有普通敌方技能（DiscoverActions），不接宏、物品、其他插件拥有按键或永久绑定。每行固定unit的type=spell代理，安全Enter/Leave+combat状态驱动管理临时键。施法前安全环境用显式exists/harm/nodead宏条件确认unit；失败设type=nil吞掉测试键，禁止回退当前目标/自己。技能/动作条状态变化或离开清理，目标/焦点/标记动作无名称/targetlasttarget回退。
启用时只接真实、可读资格的受限姓名板当前格。每格在试验期间固定原生unit地址；UI通过专用live entry显示该地址当前数据，不能换成别的unit却留下旧动作。地址是native引用，不当GUID或跨生命周期同一怪物承诺；新出现但未准备的其他地址继续0.2.4只读。off脱战清自己临时绑定/覆盖层，战斗off由预建安全停止按钮执行。自动世界/生命周期错误先挡输入并清晰记录，不能普通Lua冒充清安全bindings。
UI.lua增加按行native live entry选择。提示由新覆盖层提供，不改变原0.2.4身份边框；UnitIsUnit仅作日志核验。EnemyDisplay.lua只公开现有restrictedSnapshot读取接口，不改原排序。Main.lua增加显式命令、事件转发及试验期间敌方原绑定名单保持；Core/TOC本机0.2.5；README说明实验范围和未证实项。
日志仅标量：token/动作/按键/guard结果、UnitIsUnit与target/focus比较的公开bool或unknown、标记读回、前后目标/焦点公开存在状态。独立PRE/POST/延迟读回，不把pCall成功或调用发生视为效果成功；原有SPELL事件保持受限脱敏。不记录raw名字/GUID/宏正文。

## Steps
1. 固定70938原生源和最新作者说明，备份0.2.4，确认游戏关闭。
2. 独立实验模块+最小接入，默认保留已验收显示，完善安全停止/清理。
3. 离线测试原生action配置、同名不同地址、secret flow、接受/拒绝/unknown读回、宏guard失败无fallback、hover Enter/Leave/战斗状态、分页/键位变化、生命周期换地址与退出恢复、默认不启用/不创建；全套语法与回归。
4. 冻结候选交用户在副本同名怪测试，先脱战左键/焦点/标记，再固定目标和朝向测试普通技能；只有日志与游戏效果匹配才接入正式默认行为。游戏不由代理启动。

## Risks
nameplate直接target/focus/cast可能继续被C++拒绝，离线无法证明其接受；不能据此说已经完全满足四功能。宏条件也可能拒绝nameplate，必须吞掉该测试技能而不攻击原目标。该候选仅脱战验证，原生状态驱动在进入战斗时停止试验并清除临时绑定，不提供战斗功能。完整任意战斗新增目标仍需后续原生验证/机制。UnitIsUnit若受限/不可用只记unknown，不造匹配证明。无新可验证入口时如实报告，不把失败当成功。
