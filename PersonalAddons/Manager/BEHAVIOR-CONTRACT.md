# 玩家行为统计本机候选接口

本轮目标：MyForeverCoach 兼容升级为玩家行为采集；我的无限管理器在本机导入、去重、保存和展示统计。无 AI 调用、数据上传、公开发布、键位或游戏控制改动。

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

行为页为本地分析，不依赖网络更新成功与否。使用原应用浅色风格、系统中文字体、足够对比度和可键盘操作控件，趋势与分布同时显示数字，避免只靠颜色。不要将展示中的统计摘要发给外部 AI。
