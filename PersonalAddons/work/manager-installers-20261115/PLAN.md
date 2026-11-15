# 管理器安装程序与自身更新候选

## Goal
Mac arm64/x64 生成可拖入 Applications 的 DMG，Windows x64 生成可安装的 Setup.exe；两端管理器可检查、下载并在安全退出后更新自身，保留用户设置与行为数据。

## Constraints
沿用用户“先不要合并 main，也不要发布”的边界，以本机 PR10+11 组合候选为基线。只构建和隔离验证，不更新官网、公开更新源或已发布 ZIP，不使用真实 AI 凭据。现有游戏插件更新机制及安装目录保持原样。

## Architecture and file changes
- Desktop 引用固定版本 Velopack 1.2.161，在 Main 最前运行 bootstrap；通过适配器连接自身更新流程。
- Core 独立自身更新状态机与可测试后端接口，设置新增管理器自动更新选项，默认开启；后台检查/下载，正常退出应用，或用户点重启时安装，避免和插件文件事务冲突。
- 每平台固定 HTTPS 更新源与 channel，沿用 Velopack 包校验和原生替换，不自制跨平台覆盖脚本；状态数据仍留在既有用户目录。
- 新打包入口生成 Windows Setup、Mac 自带更新组件的 .app/DMG 与每平台更新 feed，全部写入独立 artifacts/candidates 目录。保留旧 ZIP 构建入口，官网适配留待正式授权发布。

## Step-by-step plan
1. 核对官方文档、实际工具帮助与 NuGet API；固定库和 CLI 版本。
2. 实现管理器自身更新状态、设置和 UI，先加隔离回归覆盖失败、取消、退出和插件忙碌状态。
3. 打包 Mac arm64/x64、Windows x64，不覆盖旧产物；DMG 含 Applications 链接。
4. 验证安装包身份/签名/内容与更新源；在隔离 Mac .app 做 A→B 更新，保护设置及游戏目录 sentinel；Windows 无真机时如实记录只完成交叉构建与内容检查。
5. 重跑行为、更新、安装包检查，记录交接并提供本机候选文件。先不部署、不合并。

## Risks
应用自身更新会替换程序目录，必须保留设置并等待插件事务结束；旧 ZIP 版需要首次换装新安装器。Mac 为本地临时签名、未 Developer ID 公证，Windows 暂无 Authenticode；不能声称系统验证或跨平台真机通过。公开 feed 尚未部署，自动更新代码的隔离通过不等于线上服务已启用。
