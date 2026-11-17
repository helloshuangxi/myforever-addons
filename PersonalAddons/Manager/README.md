# 我的无限 · 插件与行为统计

面向 afabiaoge.xyz 的 Windows / macOS 桌面程序。管理 MyForeverChat、MyForeverProfessions、MyForeverNavigator 与 MyForeverTargets，读取官网各自的最新版本接口。

当前为 **0.6.0 试用版**，支持管理器自身更新、行为统计，以及世界向导的游戏问路。

## 游戏问路

安装世界向导 0.7.0，在客户端「游戏问路」页选择模型服务，勾选「接收游戏中的问路」并保存。首次打开会带入已有的模型配置，可单独修改。保持客户端运行，在游戏点「导 → 问路」输入任务或目的地，例如「林中的群狼这个任务怎么做」。点「重载发送」后客户端读取该问题与相关游戏目标，生成分步答复；客户端显示「回答已返回」后在游戏点「重载接收」，选择地点并开始导航。

模型接收玩家主动提交的问题、语言、地图、阵营和该任务的目标摘要。通过角色提问编号关联答复；聊天、角色名、账号、个人位置坐标和其他插件存档不参与模型输入。客户端缓存通过结构检查的答复，角色在游戏内确认后可复用路线。位置与进度来自游戏自身与导航目录。若模型连接失败，可在客户端检查设置并「立即检查」。

## 本机行为统计

采集插件 MyForeverCoach 0.2.1 使用“玩家行为”名称，保留旧目录和存档。游戏内 `/mybehavior` 查看采集状态，`/mybehavior pause` 暂停，`/mybehavior resume` 恢复；`/mycoach` 继续兼容。采集器只记录公开游戏事件，不读取按键、聊天、姓名或 GUID，不自动操作角色，不调用 AI。

打开我的无限的“行为统计”页，按角色和今日、7天、30天或全部日期筛选。可查看采集时长、战斗次数、施法成功/失败、经验、任务和死亡，以及每日趋势、常用技能、区域停留。静止不等于挂机，施法失败不等于误操作；采集时长包括观察到的非战斗时间。角色以本机序号和等级职业显示。

本版的“关键发现”在样本足够时给出带数字依据的建议，“效率指标”列出每小时经验、每级用时、每百场死亡、施法失败事件率等。区域效率只使用由新版采集器实际完整记录的日期；已发布的同号 Coach 0.2.1 包没有这些新区域字段，不按版本字符串推定数据完整。

本版的“AI 复盘（可选）”默认关闭。勾选启用并填写模型服务后，点击“生成 AI 复盘”才发送汇总与自填问题；预览显示完整消息，发送时冻结。密钥默认只留在内存，勾选后以明文设置文件保存。AI 可能出错，以统计数字为准；云端模型按服务商计费。选择 Ollama 时应用只请求本机地址，本机服务若选择云端模型仍会联网。

游戏通常在 `/reload` 或退出角色时写入 SavedVariables。请脱战后写盘，再点击“刷新本机数据”；行为页可见时每30秒自动检查。页面显示最近写盘时间，游戏尚未写盘的行为暂不显示。旧版0.1.x只有有限会话片段，会明确标注不完整；旧诊断事件量不作为玩家操作量。

新版以 UTC+08:00 分日，采集器保留最近90天日累计；1200条明细满后总计继续累计。管理器按角色、数据代次和日期去重归档，重复刷新不会相加。已导入历史保留在软件状态目录的 `behavior/` 中，文件名与角色标识使用哈希；只读取采集器自己的存档，原游戏文件保持只读。本机分析不依赖外部 AI 或更新服务，只有明确启用并点击 AI 生成才发送摘要。采集器从同批 GitHub 试用发行手动下载，官网管理器页提供入口；不属于管理器的四个自动维护插件。

## 玩家使用

1. 0.5.0：Mac 打开匹配 Apple Silicon / Intel 的 DMG，将 MyForeverManager.app 拖入“应用程序”，再从那里启动。Windows 运行 x64 Setup.exe，安装后从开始菜单启动。首次替换前退出旧管理器。旧公开版仍以 ZIP 提供。
2. 第一次启动，选择 World of Warcraft 总目录、其中的 _forever_ 目录，或它的 Interface/AddOns 目录。程序只接受国服《魔兽世界：无限》目录。
3. 勾选要管理的插件，选择是否自动更新，然后保存。之后不必重复选择目录。
4. 程序运行时每 30 分钟检查更新。自动更新开启时安装所选插件；退出程序后停止。游戏运行期间暂缓安装，退出游戏后自动重试。
5. 可手动检查、安装/更新和恢复上次备份。恢复后关闭自动更新，避免立刻重新升级。

仅替换已勾选的受管理插件自己的目录；不改动 WTF、SavedVariables 或其他插件。更新前校验 HTTPS 来源、下载大小、SHA-256 与 TOC 版本，先完整下载并校验，再替换旧文件。备份位于对应游戏目录 Interface/.MyForeverManager，保留一次恢复入口及中断恢复信息。

本版与旧公开版的游戏插件管理机制一致。Windows 包未做 Authenticode 签名；Mac 包为本地临时签名，未做 Apple Developer ID 签名及公证。系统仍可能提示未知开发者。Mac 确认来源与校验值后，可按 Apple 官方说明，在尝试打开后进入“系统设置 → 隐私与安全性 → 仍要打开”，只为这个程序确认例外（https://support.apple.com/zh-cn/102445）。

### 管理器自身更新（0.5.0）

“自动更新管理器”与“自动更新插件”分别设置。自身更新默认开启，启动及运行中每30分钟检查，只下载当前操作系统/架构的新版本；正常退出时安装，也可点“重启并更新管理器”。正在安装/恢复插件时先安全结束操作。下载失败或取消不会替换程序；关闭自动更新后仍可手动检查和重启安装。

自身更新源位于官网 `/manager/updates/<rid>/`，分别服务当前系统与架构；服务中断时旧程序仍可用，不应把暂时无法检查理解为安装失败。0.4.0 及更早版本需要手动换装一次，之后才具备自身更新能力。

Windows 安装到当前用户 `%LocalAppData%/MyForeverManagerApp`，无需把设置放进程序目录。原设置继续在 `%LocalAppData%/MyForeverManager`；Mac 继续使用 `~/Library/Application Support/MyForeverManager`。游戏目录、WTF、行为归档和可选 AI 设置不属于程序替换范围。

## 升级并加入目标选择

0.1.0 / 0.2.0 的插件清单固定在程序内，不会自动出现目标选择。请退出旧管理器，从官网下载 0.2.1 对应平台包，解压后替换应用。已有游戏目录、勾选项和自动更新选择继续保留；新加入的插件不会替旧用户自动勾选。在主界面勾选“目标选择”下的“由管理器维护此插件”，即可下载、安装和接收后续更新。游戏运行时，安装会等待游戏退出。

目标选择读取 `https://afabiaoge.xyz/targets/latest.json`，独立安装、更新和恢复。已有框体位置与插件设置所在的 WTF / SavedVariables 保持原样。0.4.0 公开版已包含行为统计；旧候选用户替换应用前可保留原程序副本，统计数据留在原状态目录。

世界向导的版本接口为 `https://afabiaoge.xyz/navigator/latest.json`。它与聊天和商业技能助手独立发版；更新时收藏、自定义地点和按钮位置所在的 WTF / SavedVariables 保持原样。

## 项目结构

- Core/：跨平台版本查询、设置、安装、备份和恢复。
- Desktop/：Avalonia 桌面界面。
- Tests/：使用临时目录和构造包的更新回归，以及隔离的真实官网包检查。
- SelfUpdateTests/：管理器自身更新的状态、失败、取消、数据迁移和更新来源测试。
- packaging/：跨平台编译、Mac 应用打包和签名脚本。
- artifacts/：本地构建产物，不混入游戏安装或个人数据。

## 编译

需要 .NET 10 SDK。在 macOS 构建三平台：

```bash
python3 packaging/build.py --dotnet /path/to/dotnet
```

脚本按 win-x64、osx-arm64、osx-x64 构建自带运行时的软件包，玩家无需安装 .NET。macOS 打包使用系统 codesign 做临时签名，未申请任何付费证书。发布已存在文件不会被覆盖，候选构建使用 artifacts/candidates 下的独立目录。

新版安装器另用 Velopack 1.2.161（SDK 与 CLI 固定同版），Mac 打包需在 Mac 上运行：

```bash
dotnet tool install vpk --version 1.2.161 --tool-path /path/to/vpk-tools
python3 packaging/build_installers.py --dotnet /path/to/dotnet --vpk /path/to/vpk-tools/vpk
dotnet run --project SelfUpdateTests/MyForeverManager.SelfUpdateTests.csproj -c Release
```

新脚本输出 DMG、Windows Setup.exe、各平台 `updates/<rid>/releases.<rid>.json` 与更新包，只写新的本地产物目录，不会部署。旧 `build.py` 继续提供兼容 ZIP。完整验证与后续发布顺序见 [安装器与自身更新说明](packaging/INSTALLERS.md)。

安装器/自身更新源使用 ../website/ops/sync_manager_installers.py，旧 ZIP 维护继续使用 sync_manager_release.py。管理器版本独立于四个插件。公开包仅包含程序、运行时、许可证和说明。历史测试见 VALIDATION.md，本版另有发布记录。

技术参考：[Avalonia macOS 打包](https://docs.avaloniaui.net/docs/deployment/macos/)、[.NET 单文件发布](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)。
