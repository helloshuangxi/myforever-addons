# PR #10 + #11 本机验收安装计划

## Goal
将 PR #10 (`d7cd2d7`) 与 #11 (`c86b9a4`) 的功能一起安装到本机 MyForeverTargets、MyForeverCoach 与 /Applications/MyForeverManager.app。

## Constraints
用户已明确授权本机安装，并要求不合并 main、不发布。使用独立本机整合分支；保留其他插件、WTF 和管理器设置。只在游戏与管理器均关闭时写安装目录。AI 默认关闭，不配置密钥或调用模型，不做角色操作。保留当前版本标识，使用本机候选来源记录区分，不覆盖公开 ZIP。

## Step-by-step plan
1. 整合两个 PR，保留双方交接与当前授权；只在本机分支提交。
2. 运行组合后的七插件检查和 Manager 行为/更新隔离检查；构建 Apple Silicon 自包含 .app，不生成 ZIP。
3. 备份两插件、原应用与相关配置/存档，记录原哈希和进程状态。
4. 使用同卷暂存与改名安装，安装后核对每个文件、codesign、配置和其他插件未变；失败恢复本次目录。
5. 记录可回退位置与验收命令，交给用户进入游戏和管理器测试；不宣称实测通过。

## File changes
本机只替换 MyForeverTargets、MyForeverCoach 与 MyForeverManager.app。整合分支如有冲突仅合并 AGENTS/交接/当前问题文档。私有安装记录和配置备份不提交。

## Risks
两个 PR 分别验证，不代表组合后已实测；旧应用设置和游戏布局必须保留。运行时原生安全施法、游戏数据、桌面操作和真实模型仍由用户验收；安装时再次检查进程，避免用户已启动软件。
