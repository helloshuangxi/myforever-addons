# 管理器 0.5.0 试用发行

用户于 2026-11-15 使用 M 芯片 DMG 安装验收后授权合并 main、打包上线与官网开源入口。本批仅整合已验收管理器及发布/官网支持；PR #10 游戏功能与 PR #11 采集器保持单独验收。

应用 Core/Desktop 与 `5289440` 的已验收源码相同，包说明和发布脚本已更新。Mac Apple Silicon/Intel 使用 DMG，Windows x64 使用 Setup.exe，自带运行时；设置和行为档案保留，管理器自身独立自动下载并在退出时安装。AI 复盘默认关闭，只在用户启用并点击生成时发送汇总；旧采集器字段不足时会说明。

发布状态：准备中，尚未部署。最终构建提交、哈希与实际公网核验在发布完成后补记。

已知限制：用户完成 M 芯片安装验收；Windows、Intel Mac 未做真机安装/卸载/更新；Mac 仅临时签名、未 Developer ID 公证，Windows 无 Authenticode。旧 0.4.0 需手动换装一次。

官网 https://afabiaoge.xyz/manager/ ，公开源码 https://github.com/helloshuangxi/myforever-addons ，欢迎 Issue、Pull Request、文档和兼容性反馈。
