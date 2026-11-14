> 2026-11-14：用户已验收星辉候选并授权本批合并/试用发行。当前源码版本见 `PersonalAddons/releases/ui-20261114-RELEASE.md`；下文涉及0.1.45/0.1.46的双线说明仅作历史参考，不能覆盖当前0.2.0。

# 协作开发

1. 接受私有 GitHub 仓库邀请，使用自己的 GitHub 账号与 SSH key / PAT 克隆。不要共享主账号或部署私钥。
2. 阅读根目录 `AGENTS.md`、`CURRENT_ISSUES.md`，从 `main` 建立 `feature/<topic>` 或 `fix/<topic>` 分支；一个分支尽量只改一个模块，通过 Pull Request 合并。
3. 按根 README 安装 Python 依赖和 .NET SDK。先跑相关模拟，再跑 `tools/check_addons.py`；管理器使用临时游戏目录与合成存档。
4. 测试游戏行为时，记录插件版本、真实客户端 build、角色环境、重现步骤、预期/实际结果、恢复结果。区分 API 调用、模拟通过、真实硬件点击、听感和用户验收。
5. 提交前执行 `git diff --check`、`git diff --cached --stat`。只暂存自己的路径，检查没有 WTF、账号、聊天内容、日志、密钥和原始截图。
6. PR 说明写清问题、实现、验证与待验收项。候选代码进入 Git 不会解除本机验收或发布限制；不要因上传 Git 自动运行官网 `--publish`。

## 两位开发者的工作方式

可同时开发不同插件；需要共同修改 `Main.lua`、`UI.lua`、目录/版本元数据时，先在 PR 中约定负责人，避免覆盖。当前 `work/*-site` 是旧发行时冻结的副本，已排除；日常修改官网主目录，不从历史冻结副本覆盖活动源码。

`main` 的目标选择是本机 0.1.45 探针候选。公开 0.1.46 的独立源码与测试保留在 `PersonalAddons/work/targets-0.1.46-release-root`；版本号更大不表示包含探针。不要直接拿本机目录重新打包成已有公开版本。

澳洲本地系统时区可以不同。行为统计目前按固定 UTC+08:00 分日；测试本地午夜和跨日时必须保留该语义，不改用电脑本地时区。

## 检查命令

```bash
# 根目录；使用已安装 lupa 的 Python
python tools/check_addons.py
python PersonalAddons/website/community/test_server.py
python PersonalAddons/website/ops/test_upload_archive.py

# 先按 README 恢复所有发行包，再执行以下官网回归。
python PersonalAddons/website/ops/test_sync_release.py
python PersonalAddons/website/ops/test_sync_professions_release.py
python PersonalAddons/website/ops/test_sync_navigator_release.py
python PersonalAddons/website/ops/test_sync_targets_release.py
python PersonalAddons/website/ops/test_sync_manager_release.py
python PersonalAddons/website/ops/test_community_assets.py
python PersonalAddons/website/ops/verify_site.py
```

管理器基础测试从 `PersonalAddons/Manager` 执行，恢复最新插件发行包后：

```bash
dotnet run --project Tests/MyForeverManager.Tests.csproj -- --site-root ../website/public
dotnet run --project BehaviorTests/MyForeverManager.BehaviorTests.csproj
dotnet build Desktop/MyForeverManager.Desktop.csproj -c Release
```

不传 `--live` 的管理器测试使用隔离目录；它需要本地官网 ZIP fixture。可选 `--navigator-zip`、`--targets-zip` 能扩展对应模块更新覆盖。行为统计默认测试完全使用合成数据。

旧 `PersonalAddons/run_tests.py` 还包含第三方 Details 补丁测试，干净克隆中缺少 Details 会失败；新的 `tools/check_addons.py` 明确检查七个自研插件并排除这一个旧第三方测试，仍保留原测试源码与修补记录。

## 发布与环境

本次不提供 CI 自动部署。正式发布入口见 `PersonalAddons/website/README.md` 与 `ops/DEPLOYMENT.md`；需使用准确的模块版本、全新 ZIP、真实 notes 及旧包哈希校验。部署脚本含现有服务器及 SSH key 路径，属于现有运维环境，不能在同事机器直接照抄执行；私钥不入 Git。

根 `AGENTS.md` 中提到的小爱通知是原开发机可选服务；其他开发机器没有该路径时无需安装通知服务。它不是程序或测试依赖。
