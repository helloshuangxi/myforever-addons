# 管理器 0.5.0 试用发行

用户于 2026-11-15 使用 M 芯片 DMG 安装验收后授权合并 main、打包上线与官网开源入口。本批仅整合已验收管理器及发布/官网支持；PR #10 游戏功能与 PR #11 采集器保持单独验收。

应用 Core/Desktop 与 `5289440` 的已验收源码相同，包说明和发布脚本已更新。Mac Apple Silicon/Intel 使用 DMG，Windows x64 使用 Setup.exe，自带运行时；设置和行为档案保留，管理器自身独立自动下载并在退出时安装。AI 复盘默认关闭，只在用户启用并点击生成时发送汇总；旧采集器字段不足时会说明。

发布状态：**已合并 main、官网和 GitHub 试用发行已上线。** PR #12 合并提交 `2238b906292d50a2fa8f98c3956131a694a07314`；干净构建源码 `08764eaa04a1256dc15aaf094fd3c57e85b437ba`；官网部署 `20261115T073529Z`。GitHub 发行：[manager-v0.5.0](https://github.com/helloshuangxi/myforever-addons/releases/tag/manager-v0.5.0)。

已知限制：用户完成 M 芯片安装验收；Windows、Intel Mac 未做真机安装/卸载/更新；Mac 仅临时签名、未 Developer ID 公证，Windows 无 Authenticode。旧 0.4.0 需手动换装一次。

官网 https://afabiaoge.xyz/manager/ ，公开源码 https://github.com/helloshuangxi/myforever-addons ，欢迎 Issue、Pull Request、文档和兼容性反馈。

## 实际验证与保留范围

18 项自身更新、47 项行为分析、68 项插件更新/恢复回归通过；23 项新旧安装包发布回归、4 项源码下载路径、36 项其余插件发布回归、9 项分块上传和8项社区服务检查通过。两个真实 DMG 只读挂载、架构与签名校验通过；Windows Setup 与 nupkg 内容检查通过。

服务器通过真实公网 HTTPS 核对 144 个资源，版本化包使用 immutable 缓存，三个架构更新索引 no-cache。另在本机以实际生产下载类读取并校验三个架构的线上更新包，真实浏览器下载 M 芯片 DMG 的 SHA-256 与本地构建一致。GitHub 三个安装包和校验文件上传完成，资产摘要核对通过。

43 个既有 ZIP 保留原字节，其他插件版本/元数据不变；既有 chat/studio 健康与登录保护、社区只读接口通过。网站块以外 Caddy 和社区后端源代码哈希不变，建议数据库仍用原持久卷。本批未启动真实管理器、改写本机游戏目录、发送真实 AI 请求或写入测试建议。

官网首页、管理器页及页脚已提供公开仓库、贡献指南与参与邀请。源码包与更新源只含程序、说明、运行时及许可；不含 WTF、个人设置、行为数据、密钥或 probe 诊断入口。

公开回执：`PersonalAddons/website/ops/manager-0.5.0-publication.json`；完整私有测试/下载日志在 `PersonalAddons/local-logs/manager-050-release-20261115/`。
