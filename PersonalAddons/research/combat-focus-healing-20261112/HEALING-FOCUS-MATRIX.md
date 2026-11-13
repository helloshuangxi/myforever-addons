# 三套官方治疗/点击插件：战斗焦点实现核查

核查日期：2026-11-12。仅下载、解压并阅读源码；未加载、执行第三方插件，未改我方插件和游戏设置。版本、下载地址、ZIP SHA-256、关键文件 SHA-256 及行号完整见 [SOURCE.json](SOURCE.json)。

## 实现矩阵

| 插件与固定版本 | 真实焦点动作 | GUID 的位置 | 是否解决任意同名 NPC 战斗自动确认 |
| --- | --- | --- | --- |
| HealBot 26.11.06，官方 master `bcaf2db7c678b1841dab8c69bc5e566bb1bc3533`；TOC 含16001 | 配置 `type=focus`，安全按钮的 `unit` 最终是既有单位 token；专门焦点按钮直接绑定 `target` | GUID 用于按钮数据索引、身份更新和反查已知 unit；焦点动作分支没有实时 GUID 条件 | 未发现。敌方栏来自 player/party/raid 的 target、focus、arena、boss，不是任意姓名板 NPC 注册器 |
| VuhDo 官方稳定版3.220，CF9455799，标签提交 `efce2d253b0c85ada1e93f4fdec432a0560db918`；包内 Camelot TOC16001 | 生成 `/focus [@SECURE_UNIT]`，安全片段以按钮 `unit` 属性填入；另有宠物回退 | `VUHDO_RAID_GUIDS` 把 GUID 映射回已经存在的 raid/boss 等 token；未把 GUID 作为安全焦点条件 | 未发现。既有单位/固定 boss 槽位的焦点可执行，不覆盖任意同名附近 NPC |
| Clique 官方v5.1.5-release，CF9512275；TOC16001 | 代理安全按钮继承父框体 unit/unitsuffix；自定义焦点宏作为字面宏文本执行 | core 没有 UnitGUID/GUID 身份选择路径 | 未发现。它复用已注册单位框体，自动注册还排除 NamePlate；不会创建新的 NPC 单位引用 |

## HealBot：从 GUID 到原生单位属性

- `Healbot/HealBot/HealBot_Action.lua:5931–5935`：用户选择 Focus 时，最终设置的是原生 `type=focus`。
- 同文件`:6589–6593`：`SetHealButton(unit,guid,...)` 最终把 `unit` 写入安全属性，而非 `guid`。
- 同文件`:6968–6973`：专门焦点按钮直接是 `unit=target`，并非 GUID 定焦按钮。
- `Healbot/HealBot/HealBot.lua:1994–2023`：`HealBot_GUIDUnit` 搜索已经存在的按钮表来返回 token，不能为未被原生引用的 NPC 创建 token。
- `HealBot_Panel.lua:2772–2837`、`:2845–2902`：敌人条的来源是现有玩家目标、focus、arena、boss。没有发现向原生安全 header 登记任意 NPC GUID 的路径。

[固定焦点动作代码](https://github.com/davidmarshall15/Healbot/blob/bcaf2db7c678b1841dab8c69bc5e566bb1bc3533/HealBot/HealBot_Action.lua#L5931)；[实际绑定单位](https://github.com/davidmarshall15/Healbot/blob/bcaf2db7c678b1841dab8c69bc5e566bb1bc3533/HealBot/HealBot_Action.lua#L6589)；[GUID反查](https://github.com/davidmarshall15/Healbot/blob/bcaf2db7c678b1841dab8c69bc5e566bb1bc3533/HealBot/HealBot.lua#L1994)。

可复用的是原生单位按钮的焦点动作和数据索引；不能把它的 GUID 表称作战斗中按 GUID 自动放行保护动作。官方同一代码已在 TOC 中列 Forever，本轮没有把一个未证实的“ HealBotForever ”名字另算成实现。

## VuhDo：安全 header 动态装配的是绑定

本轮以作者当前稳定3.220发行包为结论依据。另保存了作者最新 midnight 开发提交084781f（3.221）及旧 forever 分支1499088（3.219）作为旁证，没有用旧分支冒充最新发行版。3.220包的关键源码与标签固定提交逐行一致；部分文件仅换行字节不同。

- `VuhDoRelease/VuhDo/VuhDoKeySetup.lua:269–285` 使用按钮的 `raidid` 单位，Focus 对应预制宏；`:357–376` 选择安全焦点模板。
- `VuhDoMacroFactory.lua:393–400` 的实际宏和`:648–656` 的安全模板都是单位 token 焦点，只有 help/宠物条件，没有 GUID 条件。
- `VuhDoBindingGenerator.lua:125–128`：受限代码读取 `button:GetAttribute('unit')`，再替换模板。
- `VuhDoToolboxUtil.lua:1332–1344` 明确阻止普通 Lua 在战斗中写保护框体属性。
- `VuhDo.lua:1269–1277` 建立 GUID→既有单位表；`:1073–1086` 私人目标反查不到时回退为 `target`。
- `VuhDo.lua:66–73` 的 NPC boss 集合是固定 `bossN`；`VuhDoPanel.xml:31–35` 的安全 header 用来安装绑定代码。它不是把任意 NPC GUID 转换为新单位 token 的原生名单 header。

[当前作者发行包](https://www.curseforge.com/wow/addons/vuhdo/files/9455799)；[固定焦点模板](https://github.com/vuhdo-io/VuhDo/blob/efce2d253b0c85ada1e93f4fdec432a0560db918/VuhDoMacroFactory.lua#L648)；[安全片段输入](https://github.com/vuhdo-io/VuhDo/blob/efce2d253b0c85ada1e93f4fdec432a0560db918/VuhDoBindingGenerator.lua#L125)；[战斗属性写入守卫](https://github.com/vuhdo-io/VuhDo/blob/efce2d253b0c85ada1e93f4fdec432a0560db918/VuhDoToolboxUtil.lua#L1332)。

可复用的是预先安装焦点模板、原生单位与宠物回退；这并没有解决当前插件所需的“读到任意 NPC GUID 后，在战斗中自动确认并改变保护动作”。

## Clique：代理继承原生 unit

[作者当前v5.1.5包](https://www.curseforge.com/wow/addons/clique/files/9512275) 同时支持 Forever1.60.1。按该 ZIP 固定版本及 SHA 核查，不用旧1.12/3.3.5同名仓库作证。

- `Clique/core/proxy_frames.lua:40–60` 创建 `SecureActionButtonTemplate` 代理，设置 `useparent-unit/useparent-unitsuffix`，直接继承原单位框体身份。
- `Clique/core/attributes.lua:92–150` 编译原生动作或字面宏文本；此包未设单独的 GUID 焦点动作分支。用户自建焦点宏也只是宏文本，没有 GUID 识别器。
- `Clique/core/frame_registry.lua:8–28` 在战斗中把新注册排队，而不是临时建代理与修改路由。
- `Clique/modules/blizzard.lua:297–312` 的 Blizzard 框体注册入口排除 `NamePlate`。
- `Clique/core/core.lua:155–177` 的安全 header 保存已注册框体与绑定，不收集任意 NPC GUID。core 中未发现 `UnitGUID` 或 GUID 条件路径。

可复用的是代理隔离点击动作、继承 unit 和战斗前预配；代理本身仍需一个原生可执行单位引用，不能把姓名板的只读 GUID 变成可执行身份。

## 对本需求的判断

三套官方代码都没有给出“战斗中任意同名 NPC 格子→实时 GUID 自动确认→安全 focus”的可移植实现。它们成功的基础是已经存在的原生单位 token（或用户宏使用的原生鼠标单位），而不是 NPC 名称唯一性或自建 GUID 单位。玩家全名机制即使可用，也不能据此认定同名 NPC 已解决。

以上为源码路径结论；没有执行这三套插件的游戏验收，也不把源码存在写成当前客户端已实测成功。
