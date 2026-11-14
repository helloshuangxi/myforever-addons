# 本机行为统计 Core 测试

独立控制台测试，无测试框架或额外 NuGet。所有客户端、账号、角色、Lua 与状态目录均在独立临时目录构造；不读取真实 WTF，不访问官网，不运行游戏。

```bash
/Users/mashuangxi/.cache/afabiaoge-dotnet/dotnet run --project PersonalAddons/Manager/BehaviorTests/MyForeverManager.BehaviorTests.csproj
```

可额外读取已存在的匿名采集验证 JSON，转成临时 Lua 验证实际旧版结构（明确拒绝 WTF 路径）：

```bash
/Users/mashuangxi/.cache/afabiaoge-dotnet/dotnet run --project PersonalAddons/Manager/BehaviorTests/MyForeverManager.BehaviorTests.csproj -- --legacy-sample PersonalAddons/work/coach-validation/session-1794108823-9.json
```

可同时验证由当前插件模拟导出的 Lua 及相邻 `.expected.json`，包括 1200 条明细容量后日累计、session 日覆盖标记和重启不双算：

```bash
/Users/mashuangxi/.cache/afabiaoge-dotnet/dotnet run --project PersonalAddons/Manager/BehaviorTests/MyForeverManager.BehaviorTests.csproj -- --legacy-sample PersonalAddons/work/coach-validation/session-1794108823-9.json --current-sample PersonalAddons/work/behavior-validation/simulated-current.lua
```

覆盖 0.2.1 区域经验/死亡/战斗与日记录版本导入、规则分析（样本门槛、死亡/技能失败/周期对比/区域效率、禁用措辞）、AI 摘要隐私（不含路径/账号/角色哈希）、AI 接口地址校验、本地桩模拟的 OpenAI 兼容请求与回复清理、密钥默认不落盘，以及每日统计映射、幂等/替换/迁移/历史归档、跨角色隔离、旧版真实 records 回填、现代与旧版混合、暂停/跨日/经验升级、必需字段缺失、损坏/null/极端整数归档、只读采集器检测、坏 Lua、路径隐私、符号链接、文件/深度/角色容量限制与取消。默认使用合成数据；可选旧样本为既有匿名验证片段，当前 Lua 样本为插件模拟导出。测试通过不代表当前游戏实测。
