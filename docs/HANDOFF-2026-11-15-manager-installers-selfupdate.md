> 后续状态：用户于 2026-11-15 验收 M 芯片版并授权管理器发布。下面保留最初候选记录；本批仅合并管理器，最新结果见 `PersonalAddons/releases/manager-0.5.0-RELEASE.md` 与官网元数据。

# 管理器 0.5.0 安装器与自身更新候选

本机候选已完成，源码构建提交为 `86edf038ef5963d27c48c18b0b7a02f74f9b6d5b`，基于本机 PR #10/#11 组合 `3c71a11`，分支 `codex/manager-installers-selfupdate-20261115`。未合并 main，未发布、部署官网或公开更新 feed，未覆盖旧发行包。系统已安装的 0.4.0 PR 测试应用仍保留。

## 交付

- Apple Silicon Mac：`MyForeverManager-0.5.0-Trial-osx-arm64.dmg`，50,334,053 字节，SHA-256 `2993ae475881cf3dc69f466050d75bc068ff5fac9f59c64cc8e254679107c3be`。
- Intel Mac：`MyForeverManager-0.5.0-Trial-osx-x64.dmg`，52,354,422 字节，SHA-256 `bcbb633ac7e16d0adc57dbaebd26a4010428067389e49c985e99b03773c8a5fe`。
- Windows x64：`MyForeverManager-0.5.0-Trial-win-x64-Setup.exe`，53,926,320 字节，SHA-256 `29dce1346e1e8f3b58e724fffb6ff39f27236aaad6393a8d980de453d05dc39a`。

本机副本位于用户“下载”目录 `MyForeverManager-0.5.0-Candidate-20261115`，附校验值、安装说明、INSTALLERS.json 和 VALIDATION.json。完整 feed 与更新包在本工作树 `PersonalAddons/Manager/artifacts/candidates/manager-050-final/updates/<rid>/`，不入 Git、不公开。所有最终产物从干净的上述提交构建，不含 probe 诊断入口或个人配置。

Mac 打开 DMG 后拖进 Applications；Windows Setup 安装到当前用户并提供开始菜单入口，自带 .NET。新版管理器自身更新默认开启，与游戏插件自动更新分开：启动/每30分钟检查、下载校验、正常退出时安装，也可立即重启更新。设置与行为档案继续使用原用户数据目录；Windows 安装 ID 使用 `MyForeverManagerApp`，与旧设置目录分离。

## 实际验证

| 项目 | 结果与范围 |
| --- | --- |
| Desktop Release 构建 | 0 警告、0 错误 |
| 自身更新回归 | 18 通过：关闭自动更新、手动更新、忙碌事务、单次检查、取消、重试、待重启缓存、设置迁移、来源/路径/大小/重定向限制 |
| 既有行为与可选 AI 回归 | 47 通过，合成数据/假服务，无真实模型调用 |
| 既有插件更新与恢复回归 | 68 通过，隔离目录与真实发行包 fixtures |
| 全部自有插件静态/模拟检查 | 83 Lua 文件、七个 TOC 及模拟套件通过；19 项 Python 测试通过，游戏实测独立 |
| Mac arm64 真实更新助手 | 测试专用隔离 A=0.5.0 → B=0.5.1；同长度坏包被摘要检查拒绝，恢复好包后下载、退出替换和重启成功；更新后代码签名完整；五份设置/行为/游戏 sentinel 哈希不变 |
| 最终 Mac arm64 GUI | 成功启动；隔离设置中独立更新开关可关闭并保存，关闭自动后仍可手动检查；公网 feed 未启用，错误提示后应用继续可用 |
| 两个最终 DMG | 镜像校验、只读挂载、Applications 链接、版本、架构、严格深度签名校验通过 |
| 最终 Windows 包 | 交叉构建成功；Setup PE、程序 x64、包身份和 feed 哈希校验通过；未做 Windows 真机安装/卸载/更新 |
| 内容 | 三平台包、SHA-256 和平台 feed 一致；不含 WTF、设置、密钥或 probe 入口 |

测试版 0.5.1 是相同源码重打包，仅用于证明更新，不是下一产品发行。probe 使用独立 App ID、bundle ID 和缓存，避免污染真实更新缓存。脚本和重现步骤见 [INSTALLERS.md](../PersonalAddons/Manager/packaging/INSTALLERS.md)。本机详细日志与 JSON 回执在 `PersonalAddons/local-logs/manager-installers-20261115/`，不含进公开 Git 的个人数据。

## GUI 探测偏差及恢复

关闭隔离 GUI 后，探测工具读取窗口时重新打开默认配置实例，触发了原设置中允许的聊天插件自动更新。已关闭实例，并从该次更新前的管理器备份恢复 MyForeverChat 0.9.3；34 文件哈希与本批开始前的安装回执一致，恢复前后核对 164 个 WTF 文件保持不变。意外下载的 0.10.0 留在本机恢复备份，未删除。PR #10/#11 插件和系统应用另做哈希核对，用户设置未改动。行为页面曾只读导入一次当前存档到既有本机缓存，源存档未修改。

本次没有替换 `/Applications` 中的管理器，交付文件由用户按需安装。以后隔离 GUI 检查退出后只查进程/应用库存，不再通过可能重启应用的窗口读取确认退出。

## 待验收与上线边界

- Windows 与 Intel Mac 真机安装、首次替换旧 ZIP、正常退出应用/立即重启更新、卸载仍待验收。
- Mac 当前为 ad-hoc 临时签名，未 Developer ID 签名/公证；Windows 无 Authenticode。不能声称通过系统发行认证。
- 固定 HTTPS 更新 feed 的代码与本机包已就绪，**公开 feed 尚未部署，因此线上管理器自动更新尚未启用**。旧 0.4.0 需手动换装一次。
- 仍遵守用户“不合并 main、不发布”。后续发布须先取得明确授权，更新官网安装入口、上传匹配版本的包后再切换 feed，完成公网回读和两端实测；不能直接把现有只认 ZIP 的官网同步脚本用于 DMG。
