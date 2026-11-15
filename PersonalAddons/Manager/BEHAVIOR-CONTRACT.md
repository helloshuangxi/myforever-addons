> 当前整合候选以已发布 Manager 0.4.0 / Coach 0.2.1 为基线，未发布新代码。旧编号和旧界面要求为历史过程；本候选保留午夜深色。实际执行结果见 BEHAVIOR-VALIDATION.md，原生 GUI 和真实模型仍未验收。

# 玩家行为统计本机候选接口

本轮目标：MyForeverCoach 兼容升级为玩家行为采集；我的无限管理器在本机导入、去重、保存和展示统计。无 AI 调用、数据上传、公开发布、键位或游戏控制改动。

> 2026-11-15 用户要求“让个人信息统计和分析真的能帮到玩家，如有必要可以接入大模型帮助判断”。下文“分析与可选 AI 复盘（管理器 0.3.2 / 采集器 0.2.1 本机候选）”一节放宽了本页关于 AI 的限制，仅限该节写明的方式；其余约束不变。

## 插件数据

根 `MyForeverCoachDB.schema=1` 继续兼容。旧会话保留，新增 `behavior` 日累计层；新会话写入 `session.behavior={schema=1,daily=true}` 覆盖标记，表示已计入日累计，不能再从原始记录回填。JSON 以 `behaviorCoverage` 导出此标记。

```lua
MyForeverCoachDB.behavior = {
  schema = 1,
  generation = "创建时epoch", -- 首次初始化生成并持久保留
  dayBasis = "UTC+08:00", -- 以 UTC epoch + 8h 的日期分日，不使用宿主时区猜测
  createdAt = 0,
  updatedAt = 0,
  days = {
    ["2026-11-11"] = {
      time = { observedSeconds=0, combatSeconds=0, nonCombatSeconds=0,
               pausedSeconds=0, unknownCombatSeconds=0 },
      counts = { combatsEntered=0, combatsCompleted=0, deaths=0,
                 castsStarted=0, castsSucceeded=0, castsFailed=0, castsInterrupted=0,
                 questsAccepted=0, questsTurnedIn=0, levelsGained=0, xpGained=0 },
      spells = { [639] = { name="圣光术", succeeded=0, failed=0, interrupted=0 } },
      maps = { [1426] = { name="丹莫罗", seconds=0, visits=0 } },
      quality = { xpGaps=0, unknownMapSeconds=0, detailDropped=0, spellOverflow=0, mapOverflow=0 }
    }
  }
}
```

日累计保留最近90天、每个日技能与地图表各最多128项。超出技能/地图上限应标记质量缺口，不能影响总计。姓名、GUID、聊天和按键不存。可用名字仅来自公开技能/地图 API，并经过 secret 和长度校验。字段未知不造零；没有新 behavior 的旧会话只能重建已保存片段。累计更新不受原1200条明细容量限制。暂停期间不累计行为，恢复应重置经验/状态基线，不能补算暂停期行为。跨日正确切分时长。

## C# Core 公共接口（根节点实现）

```csharp
public sealed class BehaviorDataService {
  public BehaviorDataService(string stateDirectory);
  public Task<BehaviorDashboard> RefreshAsync(string gameDirectory, CancellationToken cancellationToken = default);
}
public sealed class BehaviorDashboard {
  public DateTimeOffset RefreshedAt { get; set; }
  public DateTimeOffset? LatestSavedAt { get; set; }
  public bool IsGameRunning { get; set; }
  public bool CollectorInstalled { get; set; }
  public string? CollectorVersion { get; set; }
  public List<BehaviorCharacter> Characters { get; set; } = [];
  public List<string> Notices { get; set; } = [];
}
public sealed class BehaviorCharacter {
  public string Id { get; set; } = "";
  public string DisplayName { get; set; } = ""; // 本机角色序号 + 等级职业，不暴露账号路径
  public string Class { get; set; } = "";
  public int Level { get; set; }
  public List<BehaviorDay> Days { get; set; } = [];
}
public sealed class BehaviorDay {
  public string Date { get; set; } = ""; // yyyy-MM-dd
  public BehaviorCounts Counts { get; set; } = new();
  public List<BehaviorSpell> Spells { get; set; } = [];
  public List<BehaviorZone> Zones { get; set; } = [];
  public bool IsPartial { get; set; }
  public bool HasLegacyData { get; set; }
  public long DetailDropped { get; set; }
}
public sealed class BehaviorCounts {
  public double CollectedSeconds { get; set; }
  public double CombatSeconds { get; set; }
  public double NonCombatSeconds { get; set; }
  public double UnknownCombatSeconds { get; set; }
  public long CombatEntries { get; set; }
  public long CombatsCompleted { get; set; }
  public long Deaths { get; set; }
  public long CastSuccesses { get; set; }
  public long CastFailures { get; set; }
  public long QuestsAccepted { get; set; }
  public long QuestsTurnedIn { get; set; }
  public long XpGained { get; set; }
  public long LevelsGained { get; set; }
}
public sealed class BehaviorSpell {
  public long SpellId { get; set; }
  public string Name { get; set; } = "";
  public long Successes { get; set; }
  public long Failures { get; set; }
  public long Interrupted { get; set; }
}
public sealed class BehaviorZone {
  public long MapId { get; set; }
  public string Name { get; set; } = "";
  public double Seconds { get; set; }
  public long Visits { get; set; }
}
```

本机归档按匿名来源角色 + generation + 日期 upsert；旧版按来源角色 + 会话ID + 日期 upsert。导入后保留历史摘要，重复刷新和程序重启不重复累加。只安全解析 `MyForeverCoachDB` Lua 字面量，不执行 Lua、不读取其它插件存档。遇到坏文件保留此前已成功归档的摘要并提示，避免当作零覆盖。公开异常不得包含账号/角色目录或原始行。

## UI 约束

管理器0.3.0本机候选，采集插件0.2.0本机候选。保留现有三个插件的联网维护目录，不把未发布的采集器加入官网更新清单。插件管理与行为统计作为同窗页签，默认可直接看到统计入口。刷新只读存档，游戏运行不阻止读取；只读操作不触发安装或更新。页面有角色、日期范围、刷新、空状态、错误状态、写盘时间、旧数据/不完整提示。核心指标使用“采集时长”“战斗次数”“施法成功”“获得经验”“完成任务”“死亡”，不把失败事件叫误操作，不把静止叫挂机。

行为页为本地分析，不依赖网络更新成功与否。使用当前午夜深色风格、系统中文字体、足够对比度和可键盘操作控件，趋势与分布同时显示数字，避免只靠颜色。不要将展示中的统计摘要发给外部 AI。

## 分析与可选 AI 复盘（管理器 0.3.2 / 采集器 0.2.1 本机候选）

### 采集器 0.2.1
- 每个地图条目在 `seconds/visits` 之外新增 `xp`、`deaths`、`combats`（进入战斗次数），归到事件发生时最近一次公开观察到的地图；地图未知时只计入日总数，不猜测地点。
- 日记录新增 `version`。新建的日为 2；由旧采集器开始的日迁移后保持 1，桌面不会用它比较区域效率，避免把半天的区域数据当完整数据。
- 不新增事件注册，仍不读取 CLEU、按键、聊天、姓名或 GUID。

### 本机规则分析（Core/BehaviorInsights.cs）
- 纯本地、确定性计算，不联网。派生指标每项有最低样本：时长类 ≥10 分钟，平均战斗时长 ≥3 场已结束战斗，每百场死亡 ≥10 场，施法失败率 ≥20 次尝试，区域效率需该区域在 `version=2` 日内停留 ≥15 分钟。样本不足显示“—”，不出结论。
- “关键发现”每条写明所依据的数字和一条可执行建议，分“需要注意 / 做得好 / 参考”三类文字标签，不只靠颜色。总时长不足 30 分钟时先提示样本少。
- 与上一个同长度周期比较（今日对昨日、7 天对前 7 天、30 天对前 30 天），两段都需 ≥1 小时采集才比较。
- 措辞约束继续：失败事件不叫误操作；非战斗时间不叫挂机；中断说明包括读条时移动。

### 可选 AI 复盘（Core/BehaviorAiCoach.cs）
- 默认关闭。只在玩家勾选启用并点击“生成 AI 复盘”时发送一次请求，不自动、不定时、不在后台发送。
- 使用 OpenAI 兼容 Chat Completions 接口。预设 DeepSeek、通义千问（阿里云百炼）、本机 Ollama 和自定义；模型名称可改。外网接口必须 HTTPS，HTTP 只允许回环地址。
- 发送内容 = 固定规则说明 + `BuildSummary` 生成的匿名汇总：所选范围的汇总数字、上一周期汇总、职业与等级、前 12 个技能和前 10 个区域的公开名称与计数、本机关键发现。不含角色名、账号、服务器、GUID、聊天、按键、日期明细、文件路径或角色哈希。界面“发送前预览”展示完整发送内容。
- API Key 默认只保存在内存；玩家勾选“在本机保存密钥”后才写入软件状态目录 `behavior-ai.json`（明文设置文件，macOS/Linux 权限 600；Windows 位于当前用户 LocalAppData）。错误提示中会遮蔽密钥。
- 回复限制 512 KB 读取、8000 字显示，去掉控制字符、`<think>` 段与 Markdown 标记；界面注明 AI 可能出错、以统计数字为准。
- 行为数据服务 `BehaviorDataService` 仍不含 HTTP 客户端；网络请求只在 AI 复盘类中，且与插件更新服务独立。

### 当前整合的补充边界
- 摘要中的用户自填问题也会发送，自动匿名字段不等于自由文本自动脱敏。
- 不自动跟随 HTTP 重定向；回环请求不走代理。请求和正文共用 120 秒取消期限，512 KiB 上限保留。
- 发送期间冻结消息预览与请求字段，数据或提问改变时取消旧请求，不保留旧上下文的复盘。
- 单独取消密钥保存会立即移除持久化值，供应商切换不复用上一家密钥。
- 本机端点的模型服务仍可能自行调用云端模型，不能仅凭 loopback 地址保证模型服务不联网。
