# 我的无限 / MyForever development

七个自研魔兽插件、跨平台管理器、官网与建议服务的协作源码仓库。面向国服《魔兽世界：无限》，插件 TOC Interface 为 **16001**。源码包含已发布试用功能与仍待专项实测的候选路径；当前发行范围见 `PersonalAddons/releases/ui-20261114-RELEASE.md`。

本批星辉 UI 已获得用户界面验收及明确发布授权；[同批安装包](https://github.com/helloshuangxi/myforever-addons/releases/tag/suite-2026.11.14)，官网与管理器独立版本。

**先读 [目前的问题](CURRENT_ISSUES.md)，再读 [协作开发](CONTRIBUTING.md)。** [8 个协作 Issues](docs/ISSUE_INDEX.md) 包含整体 UI/UX 重设计这一优先问题。English onboarding: [Development handoff](docs/DEVELOPMENT_HANDOFF_EN.md).

| 目录 | 内容 |
| --- | --- |
| `_forever_/Interface/AddOns/MyForever*` | 7 个自研插件的当前源码与运行必需素材 |
| `PersonalAddons/Manager` | .NET 10 / Avalonia 管理器，含更新与行为统计测试 |
| `PersonalAddons/website/public` | 官网 HTML/CSS/JS、公开素材、版本与发行元数据 |
| `PersonalAddons/website/community` | Python/SQLite 建议服务及测试；没有生产数据库 |
| `PersonalAddons/website/ops` | 发布同步、验证、部署工具与发行记录 |
| `PersonalAddons/tests`、`tools` | Lua 5.1 模拟、解析测试、构建及交接工具 |
| `PersonalAddons/work`、`research`、`design` | 自研实验、调查结论、来源与界面设计；历史内容有各自版本边界 |

## 本地检查

在仓库根目录执行（Windows 的虚拟环境 Python 位于 `.venv/Scripts/python.exe`）：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python tools/check_addons.py
python3 PersonalAddons/website/community/test_server.py
python3 PersonalAddons/website/ops/test_upload_archive.py
```

管理器需要 `PersonalAddons/Manager/global.json` 指定的 .NET SDK：

```bash
cd PersonalAddons/Manager
dotnet run --project BehaviorTests/MyForeverManager.BehaviorTests.csproj
dotnet build Desktop/MyForeverManager.Desktop.csproj -c Release
```

## 安装与公开发行资料

克隆到独立开发目录，然后在游戏退出时，仅将要测试的 `MyForever*` 目录复制到对应客户端的 `Interface/AddOns`。保留本机 WTF，不向仓库提交个人存档。澳洲同事需使用匹配的 Forever 客户端；在其他 WoW 分支通过 Lua 模拟不代表兼容。

游戏文件、第三方插件整包、虚拟环境、SDK、构建物、原始截图/日志、账号配置和发行 ZIP 不入 Git。现有文件留在原机器。已发布 ZIP 可按仓库中的大小和 SHA-256 安全恢复：

```bash
# 四个游戏插件的最新公开包，供管理器隔离测试使用。
python3 tools/restore_release_assets.py
# 完整官网校验/发行测试需所有历史包，包含较大的管理器运行时包。
python3 tools/restore_release_assets.py --all --include-manager
python3 PersonalAddons/website/ops/verify_site.py
```

恢复只下载已经发布的包，不安装插件、不部署网站。网站静态预览：

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory PersonalAddons/website/public
```

当前代码与公开版的逐项差异、已知故障、后续验收及检查结果见 [CURRENT_ISSUES.md](CURRENT_ISSUES.md) 与 [交接验证记录](docs/HANDOFF_VALIDATION.md)。现有子目录 README 中的旧版本和本机绝对路径属于历史记录，以本次入口说明为准。

## 发布约束与许可

遵守 [AGENTS.md](AGENTS.md)。2026-11-14 用户明确授权本批星辉升级合并与发布；商业技能助手0.5.0与管理器0.4.0进入本批试用发行，未完成的专项实机事项仍按验证说明保留。现有公开版本的 ZIP 不得覆盖；部署凭据不随协作仓库提供。

现有 MIT 许可及第三方声明保留在各自模块；本仓库没有新增覆盖全部模块的统一开源授权。Questie/QuestieDB 等参考插件由开发者另行安装，调查来源与许可证见各模块 `SOURCES` 和 `LICENSE` 文件。
