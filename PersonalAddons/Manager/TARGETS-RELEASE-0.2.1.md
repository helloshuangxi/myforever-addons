# 目标选择接入：公开版 0.2.1 与本机候选 0.3.1

2026-11-11。此记录描述构建和隔离验证结果；外网部署与本机应用替换由发布主任务另行记录。

## 版本边界

- 官网基线：0.2.0。已安装 `/Applications/MyForeverManager.app` 基线：0.3.0 本机候选。
- 公开包：0.2.1，只有插件管理，含聊天、商业技能助手、世界向导、目标选择四项。
- 本机包：0.3.1，保留现有行为统计功能，再加入目标选择。不要把该候选放到公开下载入口。
- 旧版管理器的清单写在程序中，无法仅靠最新插件接口自动出现新插件；需替换管理器。管理器自身不自动升级。已有目录、自动更新偏好和已勾选项继续保留，新插件不替旧用户自动勾选。

## 代码与来源

当前 `Manager/` 为 0.3.1 本机候选。修改 `Core/Models.cs` 的版本和目录白名单；增加目标选择独立接口 `https://afabiaoge.xyz/targets/latest.json`。桌面界面添加名称与第四张卡片，通常以 2×2 排列，超宽窗口可显示四列。安装、更新和恢复引擎未改。

公开源码位于 `artifacts/source/targets-0.2.1/Manager/`。原 0.2.0 的完整源码快照未找到，因此这是从当前源码中明确删除行为统计文件、主界面页签与生命周期钩子后形成的隔离公开副本，不是声称恢复了历史源码。没有 Messaging 文件或引用。

与既存 `artifacts/build-evidence-0.2.0/source-sha256.json` 比较：修改前 23/27 项一致；最终公开副本 22/27 项一致。差异为 Models、MainWindow、Desktop 项目版本、启动 Program 与新增目标选择测试。GamePaths、UpdateService、Core 项目文件、打包脚本及资源均保持与 0.2.0 相同。Program 仅包含 Avalonia 启动、单实例锁与独立测试状态目录支持，没有行为统计或消息功能。

`artifacts/build-evidence-targets-20261111/public-source-provenance.json` 记录逐文件比较；公开与本机源码清单分别为 `public-source-sha256.json`、`local-source-sha256.json`。

## 已验证

- 公开版及本机候选各 **68/68** 核心隔离测试通过。使用真实 `MyForeverTargets-0.1.37-Trial.zip`，SHA-256 为 `6955d72563c0510304798d444ed5cde56b5688a7fa2c18111d38d4c02d4c2366`。
- 目标选择首次安装、旧版本更新、上次备份恢复；另外三个官方插件和 WTF 测试文件保持原样。游戏运行时目标选择安装与恢复均被阻止。
- 旧设置不自动加入目标选择，用户明确勾选后可保存。独立最新版本接口和包地址均被测试核对。
- 本机行为统计既有 **35/35** 合成数据回归通过。未改行为统计实现。
- 三个平台公开包，以及本机 arm64 候选包，均通过 ZIP CRC、严格版本身份、SHA-256、主程序架构和包内文件检查。Mac 包 `codesign --verify --deep --strict` 通过。
- 原生 macOS arm64 启动检查使用 `/private/tmp/myforever-targets-ui-*` 下自建游戏标识目录与独立设置。公开版显示 0.2.1 与四卡，无行为页；本机版显示 0.3.1，行为页保留，切到插件管理可见目标选择。
- UI 检查时目标选择公网接口尚未部署，因此显示 HTTP 404；没有点击安装。测试结束已关闭两次测试进程，隔离游戏目录未产生 Interface。没有对运行中的真实游戏执行安装测试，也没有替换 `/Applications` 中的应用。

Windows x64 与 Intel Mac 尚未在对应原生系统运行。完整 30 分钟自动更新等待未在本次重测。Mac 仍是临时签名、未公证；Windows 仍未 Authenticode 签名。

## 产物

- 公开三平台：`artifacts/releases/0.2.1/MyForeverManager-0.2.1-Trial-{win-x64,osx-arm64,osx-x64}.zip`。
- 本机候选：`artifacts/candidates/targets-0.3.1-local-20261111/MyForeverManager-0.3.1-Trial-osx-arm64.zip`。
- 本机待替换 App：`artifacts/candidates/targets-0.3.1-local-20261111/stage/osx-arm64/MyForeverManager.app`。
- 每个包的大小、SHA-256、架构和检查结果：`artifacts/build-evidence-targets-20261111/package-verification.json`。
- 发版说明输入：`artifacts/build-evidence-targets-20261111/release-notes-0.2.1.json`。
- 构建、68 项回归、35 项行为回归、原生启动日志与 UI 记录均在同一证据目录。

## 复现

```bash
/Users/mashuangxi/.cache/afabiaoge-dotnet/dotnet run --project PersonalAddons/Manager/Tests -- --site-root PersonalAddons/website/public --navigator-zip PersonalAddons/website/public/downloads/MyForeverNavigator-0.3.3-Trial.zip --targets-zip PersonalAddons/dist/MyForeverTargets-0.1.37-Trial.zip
```

公开版将项目路径换为 `PersonalAddons/Manager/artifacts/source/targets-0.2.1/Manager/Tests`。所有安装行为仅在测试程序创建的临时夹具内完成。

## 上线后复核

2026-11-11 官网部署 `20261111T095854Z` 后补测：公开源码 **74/74** 回归通过，包括四插件真实 HTTPS 下载并安装到临时夹具，以及世界向导、目标选择的真实 HTTPS 更新、备份和恢复。

公开 0.2.1 与本机 0.3.1 均使用独立临时设置启动，原生界面明确读到目标选择 **v0.1.37 · 试用版**，状态“可安装”，安装按钮可用。本机行为页仍在。没有点击界面安装、没有触碰真实游戏或用户设置；测试进程已关闭。证据：`artifacts/build-evidence-targets-20261111/public-live-tests.log`、`live-ui-verification.json`、`post-deploy-result.json`。
