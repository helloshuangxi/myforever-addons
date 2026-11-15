# 管理器安装程序与自身更新

本说明对应 0.5.0 本机候选，不是发布记录。基线包含 PR #10/#11 的本机整合；main、官网、公开更新 feed 与已发布 ZIP 均不变。旧 0.4.0 本机验收安装也保持原样。

## 安装与数据

- macOS 14+：Apple Silicon `osx-arm64`、Intel `osx-x64` 各有 DMG，包含最终 `.app` 与指向 `/Applications` 的链接。退出旧管理器后拖入应用程序，再从应用程序启动。不要从只读镜像里运行并尝试更新。
- Windows x64：Setup.exe 为当前用户安装，创建开始菜单入口，可通过系统的已安装应用卸载。程序自带 .NET，无需另装运行时。
- Velopack 包身份为 `MyForeverManagerApp`，Windows 程序目录为 `%LocalAppData%/MyForeverManagerApp`。这刻意不同于旧状态目录 `%LocalAppData%/MyForeverManager`，避免安装与卸载接管设置目录。Mac 状态目录仍为 `~/Library/Application Support/MyForeverManager`。
- 游戏目录/WTF、其他插件、行为归档、AI 配置均不在应用替换范围内。AI 默认关闭；更新不发送行为数据或密钥。
- 包内 `manager-release.json` 保留旧三字段 `name/version/platform`，Velopack 自己维护 `sq.version` 和更新 feed。

## 更新行为

SDK 与 CLI 均固定 Velopack 1.2.161。应用入口先运行 bootstrap，关闭 SDK 的启动时自动应用，保证用户关闭自身自动更新后不会因为缓存包而被自动替换。

自身更新与插件更新使用独立开关。默认启动和每30分钟检查，先完整下载校验，再在正常退出时应用；也可点击重启安装。插件文件操作忙碌时先取消/完成安全收尾，再启动应用替换助手。下载失败、取消、网络不可用时继续使用原程序；下一次可重试。强制结束程序可能延后到下一次正常退出。

固定来源如下，各自读取 `releases.<rid>.json`，没有自定义 URL 输入。只允许同目录纯文件名，拒绝重定向、其他应用身份、越界路径和超限包；不附加玩家、机器或随机分组标识。SDK 校验包摘要后才标记为可安装，升级策略不允许降级。

| RID | 未来公开 feed 目录 |
| --- | --- |
| osx-arm64 | `https://afabiaoge.xyz/manager/updates/osx-arm64/` |
| osx-x64 | `https://afabiaoge.xyz/manager/updates/osx-x64/` |
| win-x64 | `https://afabiaoge.xyz/manager/updates/win-x64/` |

**这些公开 feed 尚未部署。** 本机验证成功不等于线上更新服务已启用。旧 ZIP 0.4.0 不含 bootstrap，需要首次手动换装。系统安装权限、Developer ID 公证和 Windows 签名属于发布前实际验证范围；当前 Mac 仅临时签名，Windows 无 Authenticode。

## 构建

在 Mac 使用 .NET 10 SDK；CLI 安装命令不会发布任何包：

```bash
dotnet tool install vpk --version 1.2.161 --tool-path /path/to/vpk-tools
python3 packaging/build_installers.py --dotnet /path/to/dotnet --vpk /path/to/vpk-tools/vpk --output artifacts/candidates/new-build
```

输出必须是新目录。每个平台先 `dotnet publish --self-contained true` 单文件构建，再 `vpk pack`，Mac 从最终 portable 包制作 DMG。单文件避免把托管 DLL 放在 MacOS 目录而产生不能随更新包保留的扩展属性签名；仅显式签 Mach-O，vpk 使用 `--signDisableDeep` 签入自身助手和外层包。本机临时签名的 hardened runtime 配置允许 JIT 与加载打包的运行库。

输出有 DMG、Windows Setup.exe、SHA-256、INSTALLERS.json，以及 `updates/<rid>` 下的 feed/full.nupkg/portable。发布前保留旧的版本化安装器和更新包，禁止覆盖同版本包。

旧 `build.py` 继续输出兼容 ZIP，新脚本不调用部署或官网同步。`--update-probe --fixture-version x.y.z` 只用于构建隔离测试，含诊断入口，不得交付；常规安装器不包含此入口。

## 验证

```bash
dotnet run --project SelfUpdateTests/MyForeverManager.SelfUpdateTests.csproj -c Release
# 分别构建 osx-arm64 测试版 A=0.5.0/B=0.5.1 后：
python3 packaging/test_macos_update.py --old artifacts/candidates/probe-A --new artifacts/candidates/probe-B --receipt /path/to/receipt.json
```

隔离测试只允许明确编译的 probe 包，使用系统临时目录及合成设置/游戏文件。A/B 构建须传同一个全新 `--probe-id MyForeverManagerAppProbe<唯一后缀>`，与真实安装的包身份、bundle ID 和更新缓存隔离；若测试缓存已经存在，测试会拒绝复用。先改坏包内容但保持长度，验证摘要错误时不替换；再恢复包，执行真实下载/助手替换/重启，核对版本、更新后的签名与保护文件哈希。0.5.1 仅为同源码的测试版本，不是产品发行版。

Mac DMG 另做只读挂载，检查 Applications 链接、最终 app 元数据/架构/签名及包内无个人数据。Windows 在 Mac 上交叉编译、检查 PE 和 nupkg 内容；不能据此声称 Windows 安装/卸载/重启更新真机通过。最新实际结果以本批交接文档和本机日志为准。

## 获得发布授权后的顺序

1. 先完成 Windows 和 Intel Mac 真机验收及公开签名/公证选择；确认 PR #10/#11 与管理器候选可发布。
2. 从确认提交重建新版本，将版本化 DMG/Setup/兼容 ZIP 及对应 SHA 上传到新路径，保留旧下载。
3. 上传各 RID 的 full.nupkg，公网回读校验后再原子替换各自 `releases.<rid>.json`。先包后索引，避免客户端获取尚不存在的包。不上传测试 probe 包。
4. 扩展官网管理器发布元数据及页面，让 DMG/Setup 成为各平台安装入口，准确保留旧 ZIP/历史信息。现有 `sync_manager_release.py` 只认 ZIP，不能直接用于此步。
5. 从公网 feed 再做 Mac/Windows 安装与跨版本更新，核对 SHA-256、数据保留和回滚处理，然后记录真实已上线状态。

参考：[C# 接入](https://docs.velopack.io/getting-started/csharp)、[跨系统打包](https://docs.velopack.io/packaging/cross-compiling)、[Mac 打包](https://docs.velopack.io/packaging/operating-systems/macos)、[Windows 打包](https://docs.velopack.io/packaging/operating-systems/windows)。
