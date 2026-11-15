# 行为洞察与可选 AI 复盘：整合候选

来源为 Claude `7214d62`，分支 `jnfx962/myforever-addons:feat/behavior-insights-ai`，原基线 `3c8ba32`。当前候选以已发布 main `5392bd7` 为基础，保留午夜深色界面、Manager 0.4.0 与 Coach 0.2.1 标识；原作者 0.3.2 编号不覆盖当前公开版本。没有包含 PR #10 的战斗悬停改动。后续公开代码需要新版本号，不能覆盖现有 ZIP。

候选提供区域经验/死亡/战斗累计、样本门槛下的本机洞察与同长度周期比较，以及默认关闭、手动发送的 AI 复盘。预设为 DeepSeek、Qwen、Ollama 与自定义兼容接口。游戏采集器不调用模型；只读数据导入服务也不联网。

## 本轮核对与修复

- 解决七个旧基线冲突，保留现有版本、MyForeverStyleDB、深色样式与当前问题清单。
- 先复现区域归属错误：同一快照同时更新地图和经验时，经验被记到旧地图；先更新当前公开地图再记经验。地图未知时只加日总计，不复用旧区域。
- 使用真实回环 HTTP 服务复现默认客户端自动跟随 307，将模拟摘要发送到未选路径。现在不自动跟随重定向，本机端点也不走代理。测试未连接任何外部模型。
- 响应头模式下另用取消期限覆盖正文读取；保留 512 KiB 上限。补测正文阶段取消和过大回复；没有等待完整 120 秒超时周期。
- 发送期间固定预览、禁改请求字段，统计或问题变化时清理旧复盘并取消旧请求。停止或切换范围后的旧结果不得覆盖新上下文。此项完成代码审查与编译，原生点击流程仍未验收。
- 切换供应商清空旧密钥，取消保存密钥时立即保存移除结果；勾选保存明确说明是明文设置文件，Unix 写入仍为 600。只用假密钥测试，没有使用真实凭据。
- 新增洞察卡片使用午夜深色颜色，九组新文本/底色组合对比度均超过 4.5:1。没有把颜色计算写作原生窗口实看。
- 默认 DeepSeek 模型改为当前官方名称 `deepseek-flash`；仅 DeepSeek 官方主机发送关闭思考参数，短回复预算用于可见复盘。其他兼容接口不附加该专用参数。Ollama 说明区分本机请求与本机服务可能继续使用云端模型。

## 已执行

在本机缓存的 .NET 10 与 Lua 5.1 下：

- Manager Release 编译：0 警告、0 错误。
- BehaviorTests：原 44 项通过，补充后 47 项通过。
- 管理器安装/更新/恢复等隔离回归：68 项通过，使用已校验的现有发行包作为 fixture。
- 七插件统一入口：82 个 Lua 语法文件、7 TOC、72 组自研模拟及 19 项 Python 解析检查通过；行为专项 109 项。
- 另六个插件、共享样式、官网与发行包不变。没有修改已安装应用、游戏目录或用户存档。

规范入口为 `tools/check_addons.py`；缺少第三方 Details 时的历史测试明确排除，未记作通过。构建与模拟日志留在本机忽略目录 `PersonalAddons/local-logs/behavior-insights-ai-20261115/`，摘要及日志哈希在 `PersonalAddons/work/behavior-insights-ai-20261115/VALIDATION.json`。

## 尚未验收

尝试以独立状态目录与全模拟角色启动管理器进程；CUA 无法绑定命令行 dotnet 窗口，因此不声称有原生视觉或点击验收。测试进程已关闭，模拟窗口没有发送模型请求。应用安装目录与真实玩家数据没有用于该尝试。

仍需：真实游戏区域/跨日数据；桌面布局和 AI 启用/停止/刷新/切换角色流程；真实供应商或真实本机模型的响应、费用及质量；完整 120 秒超时和旧数据升级体验；Windows/Intel Mac 真机。AI 自由提问也会发送，只有自动摘要排除账号、角色名、路径、GUID、聊天与按键；用户应检查完整消息预览。

本候选未合并 main、未安装、未生成 ZIP、未同步官网或部署。MFM-002 继续待验收。

## 一手文档

来源与查阅日期见 `PersonalAddons/work/behavior-insights-ai-20261115/SOURCES.json`。主要依据：

- [Microsoft HttpCompletionOption](https://learn.microsoft.com/en-us/dotnet/api/system.net.http.httpcompletionoption?view=net-10.0)：响应头模式的超时范围。
- [Microsoft AllowAutoRedirect](https://learn.microsoft.com/en-us/dotnet/api/system.net.http.httpclienthandler.allowautoredirect?view=net-10.0)：默认重定向行为。
- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/) 与 [更新记录](https://api-docs.deepseek.com/updates/)：当前模型名和思考参数。
- [Qwen 兼容接口](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions) 与 [Ollama 兼容说明](https://docs.ollama.com/api/openai-compatibility)：兼容端点与本机/云端边界。
