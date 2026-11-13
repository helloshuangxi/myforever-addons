using System.Globalization;
using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using MyForeverManager.Core;

namespace MyForeverManager.Desktop;

/// <summary>Read-only local statistics. Its refresh lifecycle is independent of plugin updates.</summary>
public sealed class BehaviorStatisticsView : UserControl, IDisposable
{
    // Suite palette, direction B "Midnight". Names kept from the light theme.
    private static readonly IBrush Ink = Brush.Parse("#EEF1FF");
    private static readonly IBrush Muted = Brush.Parse("#A3ABCB");
    private static readonly IBrush Blue = Brush.Parse("#7C93FF");
    private static readonly IBrush Line = Brush.Parse("#232B48");
    private static readonly IBrush Soft = Brush.Parse("#1B2242");
    private static readonly IBrush Card = Brush.Parse("#121830");
    private static readonly IBrush OnAccent = Brush.Parse("#0B1030");
    private static readonly IBrush WarnText = Brush.Parse("#F2B35C");
    private static readonly IBrush WarnFill = Brush.Parse("#2A2316");
    private static readonly TimeSpan DayOffset = TimeSpan.FromHours(8);
    private readonly BehaviorDataService service;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly ComboBox character = new() { MinHeight = 42, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox range = new() { MinHeight = 42, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly Button refresh;
    private readonly TextBlock status = Label("等待读取本机存档…", 13, color: Muted);
    private readonly TextBlock saved = Label("最近写盘：尚未读取", 13, color: Muted);
    private readonly TextBlock source = Label("", 12, color: Muted);
    private readonly TextBlock saveHint = Label("这里展示最近一次写盘的记录。游戏中 /reload 或退出角色后刷新；页面可见时每 30 秒检查。", 13, color: Ink);
    private readonly ProgressBar loading = new() { Height = 3, IsIndeterminate = true, IsVisible = false };
    private readonly StackPanel metricsHost = new() { Spacing = 12 };
    private readonly StackPanel notices = new() { Spacing = 7 };
    private readonly StackPanel results = new() { Spacing = 20 };
    private string gameDirectory;
    private BehaviorDashboard? data;
    private CancellationTokenSource? refreshCancellation;
    private bool attached, active, disposed, refreshing, refreshRequested, changingFilters;
    private List<BehaviorCharacter> characterOptions = [];

    public BehaviorStatisticsView(BehaviorDataService service, string gameDirectory)
    {
        this.service = service;
        this.gameDirectory = gameDirectory;
        refresh = new Button
        {
            Content = "刷新本机数据", MinHeight = 42, Padding = new Thickness(18, 10),
            CornerRadius = new CornerRadius(10), Background = Blue, Foreground = OnAccent,
            FontWeight = FontWeight.SemiBold
        };
        AutomationProperties.SetName(character, "统计角色");
        AutomationProperties.SetName(range, "统计日期范围");
        AutomationProperties.SetName(refresh, "刷新本机行为数据");
        character.ItemsSource = new[] { "全部角色" };
        character.SelectedIndex = 0;
        range.ItemsSource = new[] { "今日", "最近 7 天", "最近 30 天", "全部日期" };
        range.SelectedIndex = 1;
        character.SelectionChanged += (_, _) => { if (!changingFilters) RenderResults(); };
        range.SelectionChanged += (_, _) => RenderResults();
        refresh.Click += async (_, _) => await RefreshAsync();
        timer.Tick += async (_, _) => await RefreshAsync();
        AttachedToVisualTree += (_, _) => { attached = true; UpdatePolling(); };
        DetachedFromVisualTree += (_, _) => { attached = false; UpdatePolling(); };

        var filters = new Grid { ColumnDefinitions = new ColumnDefinitions("3*,2*,Auto"), ColumnSpacing = 14 };
        filters.Children.Add(new StackPanel { Spacing = 6, Children = { Label("角色", 12, true, Muted), character } });
        var dateFilter = new StackPanel { Spacing = 6, Children = { Label("日期范围 · UTC+08:00", 12, true, Muted), range } };
        Grid.SetColumn(dateFilter, 1); filters.Children.Add(dateFilter);
        refresh.VerticalAlignment = VerticalAlignment.Bottom;
        Grid.SetColumn(refresh, 2); filters.Children.Add(refresh);
        var column = new StackPanel { Margin = new Thickness(36, 20, 36, 32), Spacing = 16 };
        column.Children.Add(new StackPanel { Spacing = 5, Children =
        {
            Label("了解你在游戏里做了什么。", 25, true),
            Label("按角色与日期查看游戏行为。存档在本机读取、分析与保存。", 13, color: Muted)
        } });
        column.Children.Add(Surface(new StackPanel { Spacing = 8, Children = { filters, loading, status, saved, source } }, new Thickness(18)));
        column.Children.Add(metricsHost);
        column.Children.Add(new Border
        {
            Background = Soft, CornerRadius = new CornerRadius(9), Padding = new Thickness(18, 12), Child = saveHint
        });
        column.Children.Add(notices);
        column.Children.Add(results);
        column.Children.Add(Label("采集时长包含插件观察到的战斗与非战斗时间；战斗次数按进入战斗计算。施法失败只是事件记录，不代表误操作。", 12, color: Muted));
        Content = new ScrollViewer { Content = column, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        RenderResults();
    }

    public void SetActive(bool value)
    {
        if (disposed || active == value) return;
        active = value;
        UpdatePolling();
    }

    public void SetGameDirectory(string value)
    {
        if (disposed || gameDirectory == value) return;
        gameDirectory = value;
        refreshCancellation?.Cancel();
        data = null;
        RenderResults();
        if (active && attached) _ = RefreshAsync();
    }

    private void UpdatePolling()
    {
        timer.Stop();
        if (disposed || !active || !attached)
        {
            refreshCancellation?.Cancel();
            return;
        }
        timer.Start();
        _ = RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        if (disposed || !active || !attached) return;
        if (refreshing) { refreshRequested = true; return; }
        refreshing = true;
        refreshRequested = false;
        var cancellation = new CancellationTokenSource();
        refreshCancellation = cancellation;
        var directory = gameDirectory;
        refresh.IsEnabled = false;
        loading.IsVisible = true;
        status.Text = "正在读取并分析本机存档…";
        status.Foreground = Muted;
        try
        {
            var next = await Task.Run(() => service.RefreshAsync(directory, cancellation.Token), cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            if (disposed || directory != gameDirectory) return;
            data = next;
            UpdateCharacters();
            status.Text = $"已刷新 · {next.RefreshedAt.ToOffset(DayOffset):MM-dd HH:mm:ss} · 仅本机分析";
            saved.Text = next.LatestSavedAt is { } time
                ? $"最近写盘：{time.ToOffset(DayOffset):yyyy-MM-dd HH:mm:ss}（UTC+08:00）"
                : "最近写盘：尚无可读取的记录";
            source.Text = next.CollectorInstalled
                ? $"玩家行为采集插件：v{next.CollectorVersion ?? "未知"} 本机候选"
                : "当前目录未检测到玩家行为采集插件。已归档的历史仍可查看。";
            saveHint.Text = next.IsGameRunning
                ? "游戏运行中，仅显示最近写盘的记录。脱战后 /reload 或登出，再刷新；页面可见时每 30 秒检查。"
                : "这里展示最近一次写盘的记录。游戏中 /reload 或退出角色后刷新；页面可见时每 30 秒检查。";
            RenderResults();
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (Exception)
        {
            if (!disposed)
            {
                status.Text = "本机数据暂时无法读取。请检查游戏目录是否可访问，再点击刷新。已显示的历史统计仍然保留。";
                status.Foreground = WarnText;
            }
        }
        finally
        {
            if (ReferenceEquals(refreshCancellation, cancellation)) refreshCancellation = null;
            cancellation.Dispose();
            refreshing = false;
            if (!disposed)
            {
                refresh.IsEnabled = true;
                loading.IsVisible = false;
                if (refreshRequested && active && attached) _ = RefreshAsync();
            }
        }
    }

    private void UpdateCharacters()
    {
        var selectedId = character.SelectedIndex > 0 && character.SelectedIndex <= characterOptions.Count
            ? characterOptions[character.SelectedIndex - 1].Id : null;
        characterOptions = data?.Characters ?? [];
        changingFilters = true;
        character.ItemsSource = new[] { "全部角色" }.Concat(characterOptions.Select(x => x.DisplayName)).ToArray();
        character.SelectedIndex = selectedId is null ? 0 : Math.Max(0, characterOptions.FindIndex(x => x.Id == selectedId) + 1);
        changingFilters = false;
    }

    private void RenderResults()
    {
        if (disposed) return;
        try { RenderResultsCore(); }
        catch (Exception)
        {
            metricsHost.Children.Clear();
            results.Children.Clear();
            metricsHost.Children.Add(Empty("这份记录暂时无法生成统计", "请刷新重读，或切换角色与日期范围后再试。本机归档的历史不会被清除。"));
        }
    }

    private void RenderResultsCore()
    {
        notices.Children.Clear();
        metricsHost.Children.Clear();
        results.Children.Clear();
        if (data is null)
        {
            metricsHost.Children.Add(Empty("准备读取你的游戏记录", "选择行为统计页后会读取当前游戏目录。首次使用需要先加载采集插件，再 /reload 或退出角色写入存档。"));
            return;
        }
        var chosen = character.SelectedIndex > 0 && character.SelectedIndex <= characterOptions.Count
            ? new[] { characterOptions[character.SelectedIndex - 1] } : characterOptions.ToArray();
        var today = DateOnly.FromDateTime(DateTimeOffset.UtcNow.ToOffset(DayOffset).DateTime);
        DateOnly? first = range.SelectedIndex switch { 0 => today, 1 => today.AddDays(-6), 2 => today.AddDays(-29), _ => null };
        var days = chosen.SelectMany(x => x.Days).Where(x => DateOnly.TryParseExact(x.Date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day) && day <= today && (first is null || day >= first)).ToList();
        RenderNotices(days);
        if (data.Characters.Count == 0)
        {
            metricsHost.Children.Add(Empty("还没有可统计的游戏记录", "加载玩家行为采集插件后正常游戏，再输入 /reload 或退出角色。点击“刷新本机数据”即可查看；无需连接网络。"));
            return;
        }
        if (days.Count == 0)
        {
            metricsHost.Children.Add(Empty("这个日期范围还没有记录", "可以切换“全部日期”查看已归档的历史；刚完成的行为需要先在游戏中 /reload 或退出角色写盘。"));
            return;
        }
        var counts = days.Select(x => x.Counts).ToList();
        var collected = counts.Sum(x => x.CollectedSeconds);
        var combat = counts.Sum(x => x.CombatSeconds);
        var nonCombat = counts.Sum(x => x.NonCombatSeconds);
        var unknown = counts.Sum(x => x.UnknownCombatSeconds);
        var entries = counts.Sum(x => x.CombatEntries);
        var successes = counts.Sum(x => x.CastSuccesses);
        var failures = counts.Sum(x => x.CastFailures);
        var levels = counts.Sum(x => x.LevelsGained);
        var metrics = new (string Label, string Value, string Detail)[]
        {
            ("采集时长", Duration(collected), $"战斗 {Duration(combat)} · 非战斗 {Duration(nonCombat)}"),
            ("战斗次数", Number(entries), $"已脱战 {Number(counts.Sum(x => x.CombatsCompleted))} 次"),
            ("施法成功", Number(successes), $"失败事件 {Number(failures)} 次"),
            ("获得经验", Number(counts.Sum(x => x.XpGained)), $"升级 {Number(levels)} 次"),
            ("完成任务", Number(counts.Sum(x => x.QuestsTurnedIn)), $"接受任务 {Number(counts.Sum(x => x.QuestsAccepted))} 次"),
            ("死亡", Number(counts.Sum(x => x.Deaths)), "已记录的角色死亡事件")
        };
        var metricGrid = new Grid { ColumnSpacing = 14, RowSpacing = 14 };
        foreach (var metric in metrics)
        {
            metricGrid.Children.Add(Surface(new StackPanel { Spacing = 9, Children =
            {
                Label(metric.Label, 13, true, Muted), Label(metric.Value, 27, true, Blue), Label(metric.Detail, 12, color: Muted)
            } }, new Thickness(16)));
        }
        void ArrangeMetrics()
        {
            var columns = metricGrid.Bounds.Width > 0 && metricGrid.Bounds.Width < 820 ? 2 : 3;
            metricGrid.ColumnDefinitions = new ColumnDefinitions(string.Join(",", Enumerable.Repeat("*", columns)));
            metricGrid.RowDefinitions = new RowDefinitions(string.Join(",", Enumerable.Repeat("Auto", (metrics.Length + columns - 1) / columns)));
            for (var i = 0; i < metricGrid.Children.Count; i++) { Grid.SetColumn(metricGrid.Children[i], i % columns); Grid.SetRow(metricGrid.Children[i], i / columns); }
        }
        metricGrid.SizeChanged += (_, _) => ArrangeMetrics();
        ArrangeMetrics();
        metricsHost.Children.Add(metricGrid);
        if (unknown > 0) metricsHost.Children.Add(Label($"另有 {Duration(unknown)} 的记录无法确定战斗状态，已计入采集时长。", 12, color: Muted));
        results.Children.Add(BuildTrend(days));
        results.Children.Add(BuildSpells(days));
        results.Children.Add(BuildZones(days));
    }

    private void RenderNotices(List<BehaviorDay> days)
    {
        if (data is null) return;
        const string legacyNotice = "包含旧版已保存片段，时长为片段估算、次数可能不完整；不代表全部游戏行为。";
        const string runningNotice = "游戏运行中：这里显示最近写盘的数据。脱战后输入 /reload 或登出，再刷新可更新统计。";
        var messages = data.Notices.Where(x => !string.IsNullOrWhiteSpace(x) && x != legacyNotice && (!data.IsGameRunning || x != runningNotice)).ToList();
        if (days.Any(x => x.HasLegacyData))
            messages.Add(days.Any(x => x.IsPartial)
                ? "含旧版片段与不完整记录：时长为估算、次数可能遗漏，不能代表全部游戏行为。"
                : "含旧版已保存片段：时长为估算、次数可能不完整，不能代表全部游戏行为。");
        else
        {
            if (data.Notices.Contains(legacyNotice)) messages.Add("历史归档含旧版片段：时长为估算、次数可能不完整，不能代表全部游戏行为。");
            if (days.Any(x => x.IsPartial)) messages.Add("当前范围记录不完整，部分行为或时长可能未被采集。");
        }
        if (days.Any(x => x.DetailDropped > 0))
            messages.Add("部分原始事件明细已达容量上限；新版日累计继续统计。");
        if (data.LatestSavedAt is { } latestSave && DateTimeOffset.UtcNow - latestSave > TimeSpan.FromDays(1))
            messages.Add("最近写盘已超过 24 小时，当前显示历史记录。请在游戏写盘后刷新。");
        var unique = messages.Distinct().ToList();
        if (unique.Count == 0) return;
        var details = new StackPanel { Spacing = 8 };
        details.Children.Add(Label("记录说明", 13, true, WarnText));
        foreach (var message in unique) details.Children.Add(Label("• " + message, 12, color: WarnText));
        notices.Children.Add(new Border
        {
            Padding = new Thickness(18, 14), CornerRadius = new CornerRadius(9),
            Background = WarnFill, Child = details
        });
    }

    private static Control BuildTrend(List<BehaviorDay> days)
    {
        var daily = days.GroupBy(x => x.Date).OrderByDescending(x => x.Key).Select(x => new
        {
            Date = x.Key, Seconds = x.Sum(d => d.Counts.CollectedSeconds), Combat = x.Sum(d => d.Counts.CombatEntries), Casts = x.Sum(d => d.Counts.CastSuccesses)
        }).ToList();
        var panel = Section("每日趋势", $"{daily.Count} 个有记录的日期 · 按采集时长显示条形，数字为实际统计");
        var max = Math.Max(1, daily.Max(x => x.Seconds));
        foreach (var day in daily)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("104,*,2*"), ColumnSpacing = 16 };
            row.Children.Add(Label(day.Date, 13, true));
            var bar = new ProgressBar { Minimum = 0, Maximum = max, Value = Math.Max(0, day.Seconds), Height = 7, Foreground = Blue, Background = Soft, VerticalAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(bar, $"{day.Date} 采集时长 {Duration(day.Seconds)}");
            Grid.SetColumn(bar, 1); row.Children.Add(bar);
            var value = Label($"{Duration(day.Seconds)}  ·  {Number(day.Combat)} 战斗  ·  {Number(day.Casts)} 施法", 12, color: Muted);
            value.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(value, 2); row.Children.Add(value);
            panel.Children.Add(row);
        }
        return Surface(panel);
    }

    private static Control BuildSpells(List<BehaviorDay> days)
    {
        var panel = Section("常用技能", "按施法成功次数排序 · 显示前 12 项");
        var spells = days.SelectMany(x => x.Spells).GroupBy(x => x.SpellId).Select(x => new
        {
            Id = x.Key, Name = x.Select(v => v.Name).FirstOrDefault(n => !string.IsNullOrWhiteSpace(n)),
            Successes = x.Sum(v => v.Successes), Failures = x.Sum(v => v.Failures), Interrupted = x.Sum(v => v.Interrupted)
        }).OrderByDescending(x => x.Successes).ThenByDescending(x => x.Failures).Take(12).ToList();
        if (spells.Count == 0) panel.Children.Add(Label("当前范围没有技能明细。总施法次数仍以上方累计为准。", 13, color: Muted));
        foreach (var spell in spells)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,2*"), ColumnSpacing = 20 };
            row.Children.Add(Label(spell.Name ?? $"技能 #{spell.Id}", 14, true));
            var detail = Label($"成功 {Number(spell.Successes)}  ·  失败 {Number(spell.Failures)}  ·  中断 {Number(spell.Interrupted)}", 12, color: Muted);
            detail.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(detail, 1); row.Children.Add(detail); panel.Children.Add(row);
        }
        return Surface(panel);
    }

    private static Control BuildZones(List<BehaviorDay> days)
    {
        var panel = Section("区域分布", "按已观察的停留时长排序 · 显示前 10 项");
        var zones = days.SelectMany(x => x.Zones).GroupBy(x => x.MapId).Select(x => new
        {
            Id = x.Key, Name = x.Select(v => v.Name).FirstOrDefault(n => !string.IsNullOrWhiteSpace(n)),
            Seconds = x.Sum(v => v.Seconds), Visits = x.Sum(v => v.Visits)
        }).OrderByDescending(x => x.Seconds).Take(10).ToList();
        if (zones.Count == 0) panel.Children.Add(Label("当前范围没有区域明细。未识别区域的时长不会被编造为某个地点。", 13, color: Muted));
        var max = Math.Max(1, zones.Select(x => x.Seconds).DefaultIfEmpty().Max());
        foreach (var zone in zones)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*"), ColumnSpacing = 20, RowDefinitions = new RowDefinitions("Auto,Auto"), RowSpacing = 8 };
            row.Children.Add(Label(zone.Name ?? $"区域 #{zone.Id}", 14, true));
            var detail = Label($"{Duration(zone.Seconds)}  ·  进入 {Number(zone.Visits)} 次", 12, color: Muted);
            detail.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(detail, 1); row.Children.Add(detail);
            var bar = new ProgressBar { Height = 5, Minimum = 0, Maximum = max, Value = Math.Max(0, zone.Seconds), Foreground = Blue, Background = Soft };
            AutomationProperties.SetName(bar, $"{zone.Name ?? $"区域 #{zone.Id}"} 停留时长 {Duration(zone.Seconds)}");
            Grid.SetRow(bar, 1); Grid.SetColumnSpan(bar, 2); row.Children.Add(bar); panel.Children.Add(row);
        }
        return Surface(panel);
    }

    private static StackPanel Section(string title, string description) => new()
    {
        Spacing = 16, Children = { new StackPanel { Spacing = 5, Children = { Label(title, 19, true), Label(description, 12, color: Muted) } } }
    };

    private static Control Empty(string title, string description) => Surface(new StackPanel
    {
        Spacing = 12, Children = { Label(title, 21, true), Label(description, 14, color: Muted) }
    }, new Thickness(28));

    private static Border Surface(Control content, Thickness? padding = null) => new()
    {
        Background = Card, BorderBrush = Line, BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(16), Padding = padding ?? new Thickness(22), Child = content
    };

    private static TextBlock Label(string text, double size = 14, bool bold = false, IBrush? color = null) => new()
    {
        Text = text, FontSize = size, FontWeight = bold ? FontWeight.SemiBold : FontWeight.Normal,
        Foreground = color ?? Ink, TextWrapping = TextWrapping.Wrap
    };

    private static string Number(long value) => value.ToString("N0", CultureInfo.InvariantCulture);

    private static string Duration(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0) return "0 分钟";
        if (seconds < 60) return $"{(int)seconds} 秒";
        var minutes = (long)(seconds / 60);
        return minutes < 60 ? $"{minutes} 分钟" : minutes % 60 == 0 ? $"{minutes / 60} 小时" : $"{minutes / 60} 小时 {minutes % 60} 分";
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        timer.Stop();
        refreshCancellation?.Cancel();
    }
}
