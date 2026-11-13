# 我的无限 · 插件与行为统计

面向 afabiaoge.xyz 的 Windows / macOS 桌面程序。管理 MyForeverChat、MyForeverProfessions、MyForeverNavigator 与 MyForeverTargets，读取官网各自的最新版本接口。

当前源码为 **0.3.1 本机候选**，保留“行为统计”页并加入“目标选择”；公开渠道独立维护不含行为统计的 0.2.1 试用版。本候选未同步官网，不能通过旧管理器自动升级获得。

## 本机行为统计

采集插件 MyForeverCoach 0.2.0 使用“玩家行为”名称，保留旧目录和存档。游戏内 `/mybehavior` 查看采集状态，`/mybehavior pause` 暂停，`/mybehavior resume` 恢复；`/mycoach` 继续兼容。采集器只记录公开游戏事件，不读取按键、聊天、姓名或 GUID，不自动操作角色，不调用 AI。

打开我的无限的“行为统计”页，按角色和今日、7天、30天或全部日期筛选。可查看采集时长、战斗次数、施法成功/失败、经验、任务和死亡，以及每日趋势、常用技能、区域停留。静止不等于挂机，施法失败不等于误操作；采集时长包括观察到的非战斗时间。角色以本机序号和等级职业显示。

游戏通常在 `/reload` 或退出角色时写入 SavedVariables。请脱战后写盘，再点击“刷新本机数据”；行为页可见时每30秒自动检查。页面显示最近写盘时间，游戏尚未写盘的行为暂不显示。旧版0.1.x只有有限会话片段，会明确标注不完整；旧诊断事件量不作为玩家操作量。

新版以 UTC+08:00 分日，采集器保留最近90天日累计；1200条明细满后总计继续累计。管理器按角色、数据代次和日期去重归档，重复刷新不会相加。已导入历史保留在软件状态目录的 `behavior/` 中，文件名与角色标识使用哈希；只读取采集器自己的存档，原游戏文件保持只读。本机统计不上传，也不依赖外部 AI 或更新服务。采集器仍为本机候选，未加入官网的插件下载清单。

## 玩家使用

1. 下载与电脑匹配的 ZIP 并解压。Windows 运行 MyForeverManager.exe；Mac 将 MyForeverManager.app 拖入“应用程序”后打开。
2. 第一次启动，选择 World of Warcraft 总目录、其中的 _forever_ 目录，或它的 Interface/AddOns 目录。程序只接受国服《魔兽世界：无限》目录。
3. 勾选要管理的插件，选择是否自动更新，然后保存。之后不必重复选择目录。
4. 程序运行时每 30 分钟检查更新。自动更新开启时安装所选插件；退出程序后停止。游戏运行期间暂缓安装，退出游戏后自动重试。
5. 可手动检查、安装/更新和恢复上次备份。恢复后关闭自动更新，避免立刻重新升级。

仅替换已勾选的受管理插件自己的目录；不改动 WTF、SavedVariables 或其他插件。更新前校验 HTTPS 来源、下载大小、SHA-256 与 TOC 版本，先完整下载并校验，再替换旧文件。备份位于对应游戏目录 Interface/.MyForeverManager，保留一次恢复入口及中断恢复信息。

公开版与本机候选的游戏插件管理机制一致。Windows 包未做 Authenticode 签名；Mac 包为本地临时签名，未做 Apple Developer ID 签名及公证。请从官网核对来源与校验值；系统仍可能提示未知开发者。Mac 确认来源与校验值后，可按 Apple 官方说明，在尝试打开后进入“系统设置 → 隐私与安全性 → 仍要打开”，只为这个程序确认例外（https://support.apple.com/zh-cn/102445）。程序自身的新版本通过官网下载替换，自动更新功能管理的是游戏插件。

## 升级并加入目标选择

0.1.0 / 0.2.0 的插件清单固定在程序内，不会自动出现目标选择。请退出旧管理器，从官网下载 0.2.1 对应平台包，解压后替换应用。已有游戏目录、勾选项和自动更新选择继续保留；新加入的插件不会替旧用户自动勾选。在主界面勾选“目标选择”下的“由管理器维护此插件”，即可下载、安装和接收后续更新。游戏运行时，安装会等待游戏退出。

目标选择读取 `https://afabiaoge.xyz/targets/latest.json`，独立安装、更新和恢复。已有框体位置与插件设置所在的 WTF / SavedVariables 保持原样。本机行为统计用户使用单独的 0.3.1 候选，不应用公开版覆盖该功能。

世界向导的版本接口为 `https://afabiaoge.xyz/navigator/latest.json`。它与聊天和商业技能助手独立发版；更新时收藏、自定义地点和按钮位置所在的 WTF / SavedVariables 保持原样。

## 项目结构

- Core/：跨平台版本查询、设置、安装、备份和恢复。
- Desktop/：Avalonia 桌面界面。
- Tests/：使用临时目录和构造包的更新回归，以及隔离的真实官网包检查。
- packaging/：跨平台编译、Mac 应用打包和签名脚本。
- artifacts/：本地构建产物，不混入游戏安装或个人数据。

## 编译

需要 .NET 10 SDK。在 macOS 构建三平台：

```bash
python3 packaging/build.py --dotnet /path/to/dotnet
```

脚本按 win-x64、osx-arm64、osx-x64 构建自带运行时的软件包，玩家无需安装 .NET。macOS 打包使用系统 codesign 做临时签名，未申请任何付费证书。发布已存在文件不会被覆盖，候选构建使用 artifacts/candidates 下的独立目录。

官网发布入口为 ../website/ops/sync_manager_release.py；管理器版本独立于四个插件。公开包仅包含程序、运行时、许可证和说明。测试结论见 VALIDATION.md。

技术参考：[Avalonia macOS 打包](https://docs.avaloniaui.net/docs/deployment/macos/)、[.NET 单文件发布](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)。
