# 本次 Git 交接验证 / Handoff validation

日期：2026-11-13（Asia/Shanghai）。这份记录只描述本次为交接新执行的检查，不增加游戏运行、视觉、听感、用户验收或发布授权。

| 检查 | 结果与范围 |
| --- | --- |
| 七个自研插件 | `tools/check_addons.py`：75 个 Lua 文件的 Lua 5.1 语法、七个 TOC 引用文件、67 组 Lua 模拟通过；Coach 导出额外独立 JSON 解码与报告检查通过；战斗日志解析器 19 项合成测试通过 |
| 旧总入口 | 已复现 `run_tests.py` 因第三方 Details 源文件缺失失败；新入口明确排除此一项，原测试和修补 diff 保留，未声称其通过 |
| 管理器行为统计 | 默认合成数据/隔离目录，35 项通过、0 失败 |
| 管理器安装更新 | 传入导航 0.3.3 和目标选择 0.1.46 公开 ZIP，68 项隔离检查通过、0 失败；没有向真实客户端安装 |
| 管理器桌面 | .NET SDK 10.0.403、Release 构建通过，0 警告、0 错误；不是 Windows/Intel Mac 真机运行 |
| 建议服务 | `community/test_server.py`：8 项通过，使用本地测试服务/临时数据 |
| 上传工具 | `ops/test_upload_archive.py`：9 项通过 |
| 官网发行同步 | Chat 7、Professions 12、Navigator 7、Targets 10、Manager 14 项通过；全部是临时站点/构造包回归，不执行发布 |
| 官网素材与隐私规则 | `ops/test_community_assets.py`：5 项通过 |
| 本地官网校验 | `ops/verify_site.py` 通过；使用本机现存的公开历史 ZIP 与管理器运行时包 |
| 公开版本只读核对 | Chat 0.9.3、Professions 0.4.6、Navigator 0.4.0、Targets 0.1.46、Manager 0.2.1 五个 HTTPS latest JSON 与本地一致；没有执行全站历史资源下载或生产写入 |
| 发行包恢复工具 | 对本机既有已发布包执行元数据/大小/SHA-256 检查；完整历史模式明确跳过没有下载字段的旧 changelog 条目，不伪造包 |

## 干净快照与收录审查

从 Git 暂存区导出到全新的临时目录，重新运行七个自研插件的完整入口，通过；导航目录检查为当前 328 项，未沿用早期 326 项结果。干净副本不包含第三方插件、WTF、发行 ZIP 或原机日志。

在该副本实际执行 `tools/restore_release_assets.py`，成功从公开 HTTPS 下载 Chat 0.9.3、Professions 0.4.6、Navigator 0.4.0、Targets 0.1.46 四个包，并核对大小和 SHA-256。没有把候选打包冒充公开版本，也没有安装到真实游戏。

使用上述干净副本与新下载的导航 0.4.0 / 目标 0.1.46 fixture，再运行管理器安装/更新测试，68 项通过、0 失败。由此确认检查入口与 fixture 恢复不依赖原机未提交的文件。

暂存内容已按路径排除个人存档/配置、聊天和会话日志、数据库、密钥、SDK、运行时构建物及第三方整包；高置信度私钥/API key/GitHub token/带凭据 URL 模式扫描没有命中。原有 Lua、CS、官网源码与素材保留原字节，未因这次 Git 收录修改功能或用户设置。历史修补 diff 单独保留原字节；PDF/图片按二进制收录。

8 个 GitHub Issues 已建立，含整体 UI/UX 不满意的用户反馈、技术阻塞、实机待测与复现边界，入口见 `docs/ISSUE_INDEX.md`。

原始终端输出保存在原机被排除的 `PersonalAddons/local-logs/git-handoff-20261113/`；没有把真实玩家日志当作测试 fixture 上传。未将第三方 Details 测试记为通过。

没有运行游戏、重新验收 UI/UX、试听提示音、验证真实战斗焦点或对实际游戏执行管理器更新。用户对整体 UI/UX 的不满意仍是 open 问题，功能/自动化通过不会将它关闭。
