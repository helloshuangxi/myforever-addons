using System.Globalization;

namespace MyForeverManager.Core;

// Local, deterministic analysis of already-imported daily summaries. Every rule
// needs a minimum sample, states the numbers it used, and avoids calling a
// failure event a mistake or non-combat time AFK. No network access here.
public enum InsightTone { Attention, Positive, Info }

public sealed class BehaviorInsight
{
    public InsightTone Tone { get; set; }
    public string Title { get; set; } = "";
    public string Evidence { get; set; } = "";
    public string Suggestion { get; set; } = "";
    public bool LowSample { get; set; }
}

public sealed class BehaviorPeriodStats
{
    public int ActiveDays { get; set; }
    public double CollectedSeconds { get; set; }
    public double CombatSeconds { get; set; }
    public double NonCombatSeconds { get; set; }
    public double UnknownCombatSeconds { get; set; }
    public long CombatEntries { get; set; }
    public long CombatsCompleted { get; set; }
    public long Deaths { get; set; }
    public long CastSuccesses { get; set; }
    public long CastFailures { get; set; }
    public long CastInterruptions { get; set; }
    public long QuestsAccepted { get; set; }
    public long QuestsTurnedIn { get; set; }
    public long XpGained { get; set; }
    public long LevelsGained { get; set; }
    public bool HasLegacyData { get; set; }
    public bool IsPartial { get; set; }
    // Derived values are null when the sample is too small to be meaningful.
    public double? XpPerHour { get; set; }
    public double? QuestsPerHour { get; set; }
    public double? CombatShare { get; set; }
    public double? AverageCombatSeconds { get; set; }
    public double? DeathsPer100Combats { get; set; }
    public double? CastFailureRate { get; set; }
    public double? CastInterruptRate { get; set; }
    public double? HoursPerLevel { get; set; }
}

public sealed class BehaviorSpellStat
{
    public long SpellId { get; set; }
    public string Name { get; set; } = "";
    public long Successes { get; set; }
    public long Failures { get; set; }
    public long Interrupted { get; set; }
    public double? FailureRate { get; set; }
    public double? InterruptRate { get; set; }
    public string DisplayName => Name.Length > 0 ? Name : $"技能 #{SpellId}";
}

public sealed class BehaviorZoneStat
{
    public long MapId { get; set; }
    public string Name { get; set; } = "";
    public double Seconds { get; set; }
    public long Visits { get; set; }
    // Only from days whose collector recorded per-zone detail from the start of the day.
    public double DetailSeconds { get; set; }
    public long XpGained { get; set; }
    public long Deaths { get; set; }
    public long CombatEntries { get; set; }
    public double? XpPerHour { get; set; }
    public string DisplayName => Name.Length > 0 ? Name : $"区域 #{MapId}";
}

public sealed class BehaviorAnalysis
{
    public string PeriodLabel { get; set; } = "";
    public string PreviousLabel { get; set; } = "";
    public BehaviorPeriodStats Current { get; set; } = new();
    public BehaviorPeriodStats? Previous { get; set; }
    public List<BehaviorSpellStat> Spells { get; set; } = [];
    public List<BehaviorZoneStat> Zones { get; set; } = [];
    public List<BehaviorInsight> Insights { get; set; } = [];
    /// <summary>Number of days in range with per-zone detail; zone efficiency uses only these days.</summary>
    public int ZoneDetailDays { get; set; }
}

public static class BehaviorInsights
{
    public const double MinimumSeconds = 30 * 60;
    private const double MetricSeconds = 10 * 60, ComparisonSeconds = 60 * 60, ZoneSeconds = 15 * 60;
    private const int MaxInsights = 8;

    public static BehaviorPeriodStats Summarize(IEnumerable<BehaviorDay> source)
    {
        var days = source.ToList();
        var result = new BehaviorPeriodStats { ActiveDays = days.Select(d => d.Date).Distinct(StringComparer.Ordinal).Count() };
        foreach (var day in days)
        {
            var c = day.Counts;
            result.CollectedSeconds += c.CollectedSeconds; result.CombatSeconds += c.CombatSeconds;
            result.NonCombatSeconds += c.NonCombatSeconds; result.UnknownCombatSeconds += c.UnknownCombatSeconds;
            result.CombatEntries += c.CombatEntries; result.CombatsCompleted += c.CombatsCompleted; result.Deaths += c.Deaths;
            result.CastSuccesses += c.CastSuccesses; result.CastFailures += c.CastFailures; result.CastInterruptions += c.CastInterruptions;
            result.QuestsAccepted += c.QuestsAccepted; result.QuestsTurnedIn += c.QuestsTurnedIn;
            result.XpGained += c.XpGained; result.LevelsGained += c.LevelsGained;
            result.HasLegacyData |= day.HasLegacyData; result.IsPartial |= day.IsPartial;
        }
        var hours = result.CollectedSeconds / 3600;
        if (result.CollectedSeconds >= MetricSeconds)
        {
            if (result.XpGained > 0) result.XpPerHour = result.XpGained / hours;
            result.QuestsPerHour = result.QuestsTurnedIn / hours;
        }
        var classified = result.CombatSeconds + result.NonCombatSeconds;
        if (classified >= MetricSeconds) result.CombatShare = result.CombatSeconds / classified;
        if (result.CombatsCompleted >= 3) result.AverageCombatSeconds = result.CombatSeconds / result.CombatsCompleted;
        if (result.CombatEntries >= 10) result.DeathsPer100Combats = result.Deaths * 100.0 / result.CombatEntries;
        var attempts = result.CastSuccesses + result.CastFailures;
        if (attempts >= 20) result.CastFailureRate = (double)result.CastFailures / attempts;
        var casts = result.CastSuccesses + result.CastInterruptions;
        if (casts >= 20) result.CastInterruptRate = (double)result.CastInterruptions / casts;
        if (result.LevelsGained > 0 && result.CollectedSeconds > 0) result.HoursPerLevel = hours / result.LevelsGained;
        return result;
    }

    public static List<BehaviorSpellStat> SummarizeSpells(IEnumerable<BehaviorDay> days) =>
        days.SelectMany(d => d.Spells).GroupBy(s => s.SpellId).Select(g =>
        {
            var stat = new BehaviorSpellStat
            {
                SpellId = g.Key, Name = g.Select(s => s.Name).LastOrDefault(n => !string.IsNullOrWhiteSpace(n)) ?? "",
                Successes = g.Sum(s => s.Successes), Failures = g.Sum(s => s.Failures), Interrupted = g.Sum(s => s.Interrupted)
            };
            var attempts = stat.Successes + stat.Failures;
            if (attempts >= 10) stat.FailureRate = (double)stat.Failures / attempts;
            var casts = stat.Successes + stat.Interrupted;
            if (casts >= 8) stat.InterruptRate = (double)stat.Interrupted / casts;
            return stat;
        }).OrderByDescending(s => s.Successes).ThenByDescending(s => s.Failures).ThenBy(s => s.SpellId).ToList();

    public static List<BehaviorZoneStat> SummarizeZones(IEnumerable<BehaviorDay> source)
    {
        var days = source.ToList();
        var stats = new Dictionary<long, BehaviorZoneStat>();
        foreach (var day in days)
            foreach (var zone in day.Zones)
            {
                if (!stats.TryGetValue(zone.MapId, out var stat)) stats[zone.MapId] = stat = new BehaviorZoneStat { MapId = zone.MapId };
                if (zone.Name.Length > 0) stat.Name = zone.Name;
                stat.Seconds += zone.Seconds; stat.Visits += zone.Visits;
                if (!day.HasZoneDetail) continue;
                stat.DetailSeconds += zone.Seconds; stat.XpGained += zone.XpGained; stat.Deaths += zone.Deaths; stat.CombatEntries += zone.CombatEntries;
            }
        foreach (var stat in stats.Values)
            if (stat.DetailSeconds >= ZoneSeconds && stat.XpGained > 0) stat.XpPerHour = stat.XpGained / (stat.DetailSeconds / 3600);
        return stats.Values.OrderByDescending(z => z.Seconds).ThenBy(z => z.MapId).ToList();
    }

    public static BehaviorAnalysis Analyze(IReadOnlyCollection<BehaviorDay> current, IReadOnlyCollection<BehaviorDay>? previous,
        string periodLabel = "当前范围", string previousLabel = "上一周期")
    {
        var analysis = new BehaviorAnalysis
        {
            PeriodLabel = periodLabel, PreviousLabel = previousLabel,
            Current = Summarize(current), Previous = previous is { Count: > 0 } ? Summarize(previous) : null,
            Spells = SummarizeSpells(current), Zones = SummarizeZones(current),
            ZoneDetailDays = current.Where(d => d.HasZoneDetail).Select(d => d.Date).Distinct(StringComparer.Ordinal).Count()
        };
        var list = new List<BehaviorInsight>();
        var now = analysis.Current;
        if (now.CollectedSeconds < MinimumSeconds)
            list.Add(new()
            {
                Tone = InsightTone.Info, LowSample = true, Title = "记录还比较少",
                Evidence = $"当前范围只有 {Duration(now.CollectedSeconds)} 的采集时长，下面的判断可能不稳定。",
                Suggestion = "正常游戏 30 分钟以上，脱战后 /reload 或登出写盘，再刷新即可得到更可靠的分析。"
            });
        Deaths(analysis, list);
        Spells(analysis, list);
        CombatRhythm(now, list);
        Zones(analysis, list);
        Quests(now, list);
        Compare(analysis, list);
        if (now.LevelsGained > 0 && now.HoursPerLevel is { } perLevel)
            list.Add(new()
            {
                Tone = InsightTone.Info, LowSample = now.CollectedSeconds < MinimumSeconds, Title = "升级节奏",
                Evidence = $"升级 {Number(now.LevelsGained)} 次，平均每级约 {Hours(perLevel)} 采集时长" + (now.XpPerHour is { } xph ? $"，每小时约 {Number(xph)} 经验。" : "。"),
                Suggestion = "可以把这个数字作为下一次的参照：换区域或改变打法后，看看每级用时有没有缩短。"
            });
        // Stable order inside each tone keeps the most specific rules first.
        analysis.Insights = list.Select((insight, index) => (insight, index))
            .OrderBy(x => x.insight.Tone switch { InsightTone.Attention => 0, InsightTone.Positive => 1, _ => 2 })
            .ThenBy(x => x.index).Select(x => x.insight).Take(MaxInsights).ToList();
        return analysis;
    }

    private static void Deaths(BehaviorAnalysis analysis, List<BehaviorInsight> list)
    {
        var now = analysis.Current;
        var fewCombats = now.DeathsPer100Combats is null;
        if (now.Deaths >= 3 && (fewCombats || now.DeathsPer100Combats >= 8))
        {
            var evidence = $"采集期间记录 {Number(now.CombatEntries)} 场战斗、{Number(now.Deaths)} 次死亡" +
                (now.DeathsPer100Combats is { } rate ? $"，约每 100 场 {OneDecimal(rate)} 次。" : "。");
            var detailDeaths = analysis.Zones.Sum(z => z.Deaths);
            var top = analysis.Zones.Where(z => z.Deaths > 0).OrderByDescending(z => z.Deaths).FirstOrDefault();
            if (top is not null && top.Deaths >= 2 && detailDeaths > 0 && top.Deaths * 2 >= detailDeaths)
                evidence += $"有区域明细的死亡中，{Number(top.Deaths)} 次发生在{top.DisplayName}。";
            list.Add(new()
            {
                Tone = InsightTone.Attention, Title = "死亡偏多", Evidence = evidence, LowSample = fewCombats,
                Suggestion = "开怪前把生命和法力恢复到七成以上，一次只拉能稳定处理的数量；如果死亡集中在同一区域，先确认那里的怪物等级是否明显高于角色，必要时换到等级更合适的区域。"
            });
        }
        else if (now.Deaths == 0 && now.CombatEntries >= 30)
            list.Add(new()
            {
                Tone = InsightTone.Positive, Title = "零死亡",
                Evidence = $"{Number(now.CombatEntries)} 场战斗没有死亡记录。",
                Suggestion = "节奏很稳。如果想再快一些，可以在血量充足时尝试多处理一只怪，再根据结果调整。"
            });
    }

    private static void Spells(BehaviorAnalysis analysis, List<BehaviorInsight> list)
    {
        var failing = analysis.Spells.Where(s => s.FailureRate >= 0.2 && s.Failures >= 3)
            .OrderByDescending(s => s.Failures).Take(3).ToList();
        if (failing.Count > 0)
            list.Add(new()
            {
                Tone = InsightTone.Attention, Title = "部分技能失败事件较多",
                Evidence = string.Join("；", failing.Select(s => $"{s.DisplayName} 失败 {Number(s.Failures)}/{Number(s.Successes + s.Failures)}（{Percent(s.FailureRate ?? 0)}）")) + "。",
                Suggestion = "失败事件可能来自冷却或公共冷却未好时重复按键、距离太远、法力不足、未面对目标或移动中施法，插件目前不能区分具体原因。若只是习惯连按可以忽略；若游戏常提示距离或法力不足，可调整站位或战前回蓝。"
            });
        var interrupted = analysis.Spells.Where(s => s.InterruptRate >= 0.15 && s.Interrupted >= 3)
            .OrderByDescending(s => s.Interrupted).Take(3).ToList();
        if (interrupted.Count > 0)
            list.Add(new()
            {
                Tone = InsightTone.Attention, Title = "读条技能经常中断",
                Evidence = string.Join("；", interrupted.Select(s => $"{s.DisplayName} 中断 {Number(s.Interrupted)} 次（占成功与中断记录的 {Percent(s.InterruptRate ?? 0)}）")) + "。",
                Suggestion = "读条时移动、被怪物打断或主动按了别的技能都会记为中断。读条前先停步；怪物贴身时先用瞬发技能或控制，再开始读条。"
            });
    }

    private static void CombatRhythm(BehaviorPeriodStats now, List<BehaviorInsight> list)
    {
        if (now.CombatShare is not { } share || now.CollectedSeconds < ComparisonSeconds) return;
        if (share < 0.25)
            list.Add(new()
            {
                Tone = InsightTone.Info, Title = "大部分时间不在战斗中",
                Evidence = $"战斗约占已分类时间的 {Percent(share)}，非战斗 {Duration(now.NonCombatSeconds)}。",
                Suggestion = "非战斗时间包括跑路、在城里整理、休息回蓝和离开键盘，并不等于浪费。如果目标是练级，可以把顺路的任务一起接、减少往返；世界向导插件可以帮你规划去处。"
            });
        else if (share >= 0.7)
            list.Add(new()
            {
                Tone = InsightTone.Positive, Title = "战斗密度很高",
                Evidence = $"战斗约占已分类时间的 {Percent(share)}。",
                Suggestion = "这种节奏推进很快，注意补给与背包空间，长时间连续战斗时适当休息。"
            });
    }

    private static void Zones(BehaviorAnalysis analysis, List<BehaviorInsight> list)
    {
        var rated = analysis.Zones.Where(z => z.XpPerHour is not null).OrderByDescending(z => z.XpPerHour).ToList();
        if (rated.Count < 2) return;
        var best = rated[0]; var worst = rated[^1];
        if (best.XpPerHour is not { } high || worst.XpPerHour is not { } low || low <= 0 || high < low * 1.5) return;
        list.Add(new()
        {
            Tone = InsightTone.Info, Title = "不同区域的练级效率差别明显",
            Evidence = $"{best.DisplayName} 每小时约 {Number(high)} 经验（停留 {Duration(best.DetailSeconds)}）；{worst.DisplayName} 约 {Number(low)}（停留 {Duration(worst.DetailSeconds)}）。",
            Suggestion = "差异可能来自任务密度、怪物等级和跑路距离。等级合适的话，可以多安排时间在效率更高的区域；跑路较多的区域可以先集中接任务再出发。"
        });
    }

    private static void Quests(BehaviorPeriodStats now, List<BehaviorInsight> list)
    {
        var backlog = now.QuestsAccepted - now.QuestsTurnedIn;
        if (backlog < 10) return;
        list.Add(new()
        {
            Tone = InsightTone.Info, Title = "接的任务比交的多",
            Evidence = $"接受 {Number(now.QuestsAccepted)} 个任务，交付 {Number(now.QuestsTurnedIn)} 个。范围边界前后接交的任务也会造成差额。",
            Suggestion = "任务日志容量有限。可以放弃已经明显低于等级的任务，并按地点把同一区域的任务集中完成、一起交付。"
        });
    }

    private static void Compare(BehaviorAnalysis analysis, List<BehaviorInsight> list)
    {
        var now = analysis.Current; var before = analysis.Previous;
        if (before is null || now.CollectedSeconds < ComparisonSeconds || before.CollectedSeconds < ComparisonSeconds) return;
        var label = analysis.PreviousLabel;
        if (now.XpPerHour is { } xpNow && before.XpPerHour is { } xpBefore && xpBefore > 0)
        {
            var change = xpNow / xpBefore - 1;
            if (change >= 0.2)
                list.Add(new() { Tone = InsightTone.Positive, Title = "练级效率提升",
                    Evidence = $"每小时经验 {Number(xpBefore)} → {Number(xpNow)}（较{label} {Signed(change)}）。",
                    Suggestion = "可以回看这段时间常去的区域和打法，把有效的做法保留下来。" });
            else if (change <= -0.2)
                list.Add(new() { Tone = InsightTone.Attention, Title = "练级效率下降",
                    Evidence = $"每小时经验 {Number(xpBefore)} → {Number(xpNow)}（较{label} {Signed(change)}）。",
                    Suggestion = "对照区域分布看看时间花在了哪里。等级提升后原区域的怪物和任务经验会变少，可能需要换到更高等级的区域。" });
        }
        if (now.DeathsPer100Combats is { } deathNow && before.DeathsPer100Combats is { } deathBefore)
        {
            if (deathNow - deathBefore >= 5 && now.Deaths >= 3)
                list.Add(new() { Tone = InsightTone.Attention, Title = "死亡比之前多",
                    Evidence = $"每 100 场战斗死亡 {OneDecimal(deathBefore)} → {OneDecimal(deathNow)} 次（与{label}相比）。",
                    Suggestion = "如果最近换了区域或开始组队/挑战精英，这是正常的；否则留意怪物等级和开怪前的状态。" });
            else if (deathBefore - deathNow >= 5 && before.Deaths >= 3)
                list.Add(new() { Tone = InsightTone.Positive, Title = "死亡明显减少",
                    Evidence = $"每 100 场战斗死亡 {OneDecimal(deathBefore)} → {OneDecimal(deathNow)} 次（与{label}相比）。",
                    Suggestion = "生存改善了，保持现在的开怪节奏。" });
        }
        if (now.AverageCombatSeconds is { } lengthNow && before.AverageCombatSeconds is { } lengthBefore && lengthBefore > 0
            && now.CombatsCompleted >= 10 && before.CombatsCompleted >= 10)
        {
            var change = lengthNow / lengthBefore - 1;
            if (change >= 0.3)
                list.Add(new() { Tone = InsightTone.Info, Title = "单场战斗变长",
                    Evidence = $"平均每场 {Seconds(lengthBefore)} → {Seconds(lengthNow)}（较{label} {Signed(change)}）。",
                    Suggestion = "可能是怪物等级变高、一次拉得更多，或技能与装备没有跟上等级。可以到训练师处检查是否有新技能等级。" });
            else if (change <= -0.25)
                list.Add(new() { Tone = InsightTone.Positive, Title = "单场战斗更快",
                    Evidence = $"平均每场 {Seconds(lengthBefore)} → {Seconds(lengthNow)}（较{label} {Signed(change)}）。",
                    Suggestion = "记录到的平均战斗用时缩短了，可以继续按相同区域和战斗方式观察。" });
        }
    }

    public static string Number(double value) => Math.Round(value).ToString("N0", CultureInfo.InvariantCulture);
    public static string Number(long value) => value.ToString("N0", CultureInfo.InvariantCulture);
    public static string OneDecimal(double value) => value.ToString("0.#", CultureInfo.InvariantCulture);
    public static string Percent(double value) => Math.Round(value * 100).ToString("0", CultureInfo.InvariantCulture) + "%";
    public static string Signed(double value) => (value >= 0 ? "+" : "−") + Math.Round(Math.Abs(value) * 100).ToString("0", CultureInfo.InvariantCulture) + "%";
    public static string Seconds(double value) => value < 60 ? $"{Math.Round(value).ToString("0", CultureInfo.InvariantCulture)} 秒" : $"{(value / 60).ToString("0.#", CultureInfo.InvariantCulture)} 分钟";
    public static string Hours(double value) => value < 1 ? $"{Math.Max(1, Math.Round(value * 60)).ToString("0", CultureInfo.InvariantCulture)} 分钟" : $"{value.ToString("0.#", CultureInfo.InvariantCulture)} 小时";
    public static string Duration(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0) return "0 分钟";
        if (seconds < 60) return $"{(int)seconds} 秒";
        var minutes = (long)(seconds / 60);
        return minutes < 60 ? $"{minutes} 分钟" : minutes % 60 == 0 ? $"{minutes / 60} 小时" : $"{minutes / 60} 小时 {minutes % 60} 分";
    }
}
