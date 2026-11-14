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
    private static readonly IBrush Warn = WarnText;
    private static readonly IBrush Positive = Brush.Parse("#70DDB0");
    private static readonly IBrush PositiveFill = Brush.Parse("#102C26");
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
    private readonly BehaviorAiSettingsStore aiStore;
    private BehaviorAiSettings aiSettings;
    private readonly CheckBox aiEnabled = new() { Content = "启用 AI 复盘（默认关闭）" };
    private readonly StackPanel aiSettingsPanel = new() { Spacing = 10 };
    private readonly ComboBox aiProvider = new() { MinHeight = 38, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly TextBox aiEndpoint = new() { MinHeight = 38, Watermark = "https://…/v1" };
    private readonly TextBox aiModel = new() { MinHeight = 38, Watermark = "模型名称" };
    private readonly TextBox aiKey = new() { MinHeight = 38, PasswordChar = '•', Watermark = "API Key（本机模型可留空）" };
    private readonly CheckBox aiRemember = new() { Content = "在本机保存密钥（明文设置文件）" };
    private readonly TextBlock aiPresetNote = Label("", 12, color: Muted);
    private readonly TextBox aiQuestion = new() { MinHeight = 38, MaxLength = BehaviorAiCoach.MaxQuestionLength, Watermark = "想重点问什么？例如：为什么我最近练级变慢了（可选）" };
    private readonly Button aiGenerate;
    private readonly Button aiCancel;
    private readonly TextBox aiPreview = new() { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 320, FontFamily = new FontFamily("Consolas, Menlo, monospace"), FontSize = 12 };
    private readonly TextBlock aiStatus = Label("", 12, color: Muted);
    private readonly SelectableTextBlock aiResult = new() { FontSize = 14, Foreground = Ink, TextWrapping = TextWrapping.Wrap, LineHeight = 23 };
    private readonly Border aiResultHost;
    private CancellationTokenSource? aiCancellation;
    private BehaviorAnalysis? currentAnalysis;
    private List<BehaviorCharacter> currentCharacters = [];
    private string aiContext = "";
    private string aiSentPreview = "";
    private bool aiRunning, changingAi;
    private string gameDirectory;
    private BehaviorDashboard? data;
    private CancellationTokenSource? refreshCancellation;
    private bool attached, active, disposed, refreshing, refreshRequested, changingFilters;
    private List<BehaviorCharacter> characterOptions = [];

    public BehaviorStatisticsView(BehaviorDataService service, string gameDirectory, BehaviorAiSettingsStore aiStore)
    {
        this.service = service;
        this.gameDirectory = gameDirectory;
        this.aiStore = aiStore;
        aiSettings = aiStore.Load();
        aiGenerate = new Button
        {
            Content = "生成 AI 复盘", MinHeight = 40, Padding = new Thickness(18, 9),
            CornerRadius = new CornerRadius(7), Background = Blue, Foreground = OnAccent, FontWeight = FontWeight.SemiBold
        };
        aiCancel = new Button { Content = "停止", MinHeight = 40, Padding = new Thickness(16, 9), CornerRadius = new CornerRadius(7), IsVisible = false };
        aiResultHost = new Border { Background = Soft, CornerRadius = new CornerRadius(9), Padding = new Thickness(18, 14), Child = aiResult, IsVisible = false };
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
        column.Children.Add(BuildAiPanel());
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
                ? $"玩家行为采集插件：v{next.CollectorVersion ?? "未知"} 试用版"
                : "当前目录未检测到玩家行为采集插件。已归档的历史仍可查看。";
            saveHint.Text = next.IsGameRunning
                ? "游戏运行中，仅显示最近写盘的记录。脱战后 /reload 或登出，再刷新；页面可见时每 30 秒检查。"
                : "这里展示最近一次写盘的记录。游戏中 /reload 或退出角色后刷新；页面可见时每 30 秒检查。";
            RenderResults();
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (Exception)
        {
            currentAnalysis = null;
            currentCharacters = [];
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
        finally { UpdateAiContext(); UpdateAiState(); }
    }

    private void RenderResultsCore()
    {
        notices.Children.Clear();
        metricsHost.Children.Clear();
        results.Children.Clear();
        currentAnalysis = null;
        currentCharacters = [];
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
        // The comparison window has the same length and ends the day before the selected range starts.
        (DateOnly From, DateOnly To, string Label)? earlier = range.SelectedIndex switch
        {
            0 => (today.AddDays(-1), today.AddDays(-1), "昨日"),
            1 => (today.AddDays(-13), today.AddDays(-7), "前 7 天"),
            2 => (today.AddDays(-59), today.AddDays(-30), "前 30 天"),
            _ => null
        };
        var previousDays = earlier is { } window
            ? chosen.SelectMany(x => x.Days).Where(x => DateOnly.TryParseExact(x.Date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day) && day >= window.From && day <= window.To).ToList()
            : null;
        var periodLabel = range.SelectedIndex switch { 0 => "今日", 1 => "最近 7 天", 2 => "最近 30 天", _ => "全部日期" };
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
        var analysis = BehaviorInsights.Analyze(days, previousDays, periodLabel, earlier?.Label ?? "上一周期");
        currentAnalysis = analysis;
        currentCharacters = chosen.ToList();
        results.Children.Add(BuildInsights(analysis, chosen.Length > 1));
        results.Children.Add(BuildEfficiency(analysis));
        results.Children.Add(BuildTrend(days));
        results.Children.Add(BuildSpells(analysis));
        results.Children.Add(BuildZones(analysis));
    }

    private static Control BuildInsights(BehaviorAnalysis analysis, bool mixedCharacters)
    {
        var description = "根据本机统计自动生成，只在样本足够时给出判断；每条都附上所依据的数字。" + (mixedCharacters ? "当前为多个角色合并，选择单个角色可得到更准确的建议。" : "");
        var panel = Section("关键发现", description);
        if (analysis.Insights.Count == 0)
            panel.Children.Add(Label("当前范围没有明显需要注意的地方。继续游戏积累更多记录后，这里会给出对比与建议。", 13, color: Muted));
        foreach (var insight in analysis.Insights)
        {
            var (tag, accent, tint) = insight.Tone switch
            {
                InsightTone.Attention => ("需要注意", WarnText, WarnFill),
                InsightTone.Positive => ("做得好", Positive, PositiveFill),
                _ => ("参考", Blue, Soft)
            };
            var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            header.Children.Add(new Border
            {
                Background = accent, CornerRadius = new CornerRadius(5), Padding = new Thickness(8, 2),
                Child = Label(tag, 12, true, OnAccent), VerticalAlignment = VerticalAlignment.Center
            });
            header.Children.Add(Label(insight.Title + (insight.LowSample ? "（样本较少）" : ""), 15, true));
            var body = new StackPanel { Spacing = 7, Children = { header, Label(insight.Evidence, 13) } };
            if (insight.Suggestion.Length > 0) body.Children.Add(Label("建议：" + insight.Suggestion, 13, color: Muted));
            panel.Children.Add(new Border
            {
                Background = tint, BorderBrush = accent, BorderThickness = new Thickness(4, 0, 0, 0),
                CornerRadius = new CornerRadius(6), Padding = new Thickness(16, 12), Child = body
            });
        }
        return Surface(panel);
    }

    private static Control BuildEfficiency(BehaviorAnalysis analysis)
    {
        var now = analysis.Current; var before = analysis.Previous;
        var panel = Section("效率指标", before is null
            ? "样本不足的指标显示为“—”。选择今日、7 天或 30 天时会与上一个同长度周期对比。"
            : $"与{analysis.PreviousLabel}对比 · 样本不足的指标显示为“—”");
        // better: +1 higher is better, -1 lower is better, 0 neutral. Percent rates compare in percentage points.
        var rows = new (string Name, Func<BehaviorPeriodStats, double?> Value, Func<double, string> Format, int Better, bool Points)[]
        {
            ("每小时经验", x => x.XpPerHour, BehaviorInsights.Number, 1, false),
            ("每小时完成任务", x => x.QuestsPerHour, BehaviorInsights.OneDecimal, 1, false),
            ("平均每级用时", x => x.HoursPerLevel, BehaviorInsights.Hours, -1, false),
            ("战斗时间占比", x => x.CombatShare, BehaviorInsights.Percent, 0, true),
            ("平均每场战斗", x => x.AverageCombatSeconds, BehaviorInsights.Seconds, -1, false),
            ("每百场战斗死亡", x => x.DeathsPer100Combats, BehaviorInsights.OneDecimal, -1, false),
            ("施法失败事件率", x => x.CastFailureRate, BehaviorInsights.Percent, -1, true),
            ("施法中断事件率", x => x.CastInterruptRate, BehaviorInsights.Percent, -1, true)
        };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("2*,*,*,*"), ColumnSpacing = 12 };
        var titles = new[] { "指标", analysis.PeriodLabel, before is null ? "" : analysis.PreviousLabel, before is null ? "" : "变化" };
        for (var i = 0; i < titles.Length; i++) { var t = Label(titles[i], 12, true, Muted); if (i > 0) t.TextAlignment = TextAlignment.Right; Grid.SetColumn(t, i); header.Children.Add(t); }
        panel.Children.Add(header);
        foreach (var row in rows)
        {
            var current = row.Value(now); var previous = before is null ? null : row.Value(before);
            var line = new Grid { ColumnDefinitions = new ColumnDefinitions("2*,*,*,*"), ColumnSpacing = 12 };
            line.Children.Add(Label(row.Name, 13, true));
            var currentText = Label(current is { } c ? row.Format(c) : "—", 13, true, Blue); currentText.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(currentText, 1); line.Children.Add(currentText);
            if (before is not null)
            {
                var previousText = Label(previous is { } p ? row.Format(p) : "—", 13, color: Muted); previousText.TextAlignment = TextAlignment.Right;
                Grid.SetColumn(previousText, 2); line.Children.Add(previousText);
                var (change, tone) = Change(current, previous, row.Better, row.Points);
                var changeText = Label(change, 12, tone != 0, tone > 0 ? Positive : tone < 0 ? WarnText : Muted); changeText.TextAlignment = TextAlignment.Right;
                Grid.SetColumn(changeText, 3); line.Children.Add(changeText);
            }
            panel.Children.Add(line);
        }
        return Surface(panel);
    }

    private static (string Text, int Tone) Change(double? current, double? previous, int better, bool points)
    {
        if (current is not { } c || previous is not { } p) return ("—", 0);
        var delta = points ? (c - p) * 100 : p == 0 ? double.NaN : c / p - 1;
        if (!double.IsFinite(delta)) return ("—", 0);
        var small = points ? Math.Abs(delta) < 1 : Math.Abs(delta) < 0.05;
        if (small) return ("持平", 0);
        var text = points ? (delta > 0 ? "+" : "−") + Math.Abs(delta).ToString("0", CultureInfo.InvariantCulture) + " 个百分点" : BehaviorInsights.Signed(delta);
        var tone = better == 0 ? 0 : Math.Sign(delta) == better ? 1 : -1;
        return (text + (tone > 0 ? " 改善" : tone < 0 ? " 变差" : ""), tone);
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

    private static Control BuildSpells(BehaviorAnalysis analysis)
    {
        var panel = Section("常用技能", "按施法成功次数排序 · 显示前 12 项 · 失败事件含冷却中重复按键等情况");
        var spells = analysis.Spells.Take(12).ToList();
        if (spells.Count == 0) panel.Children.Add(Label("当前范围没有技能明细。总施法次数仍以上方累计为准。", 13, color: Muted));
        foreach (var spell in spells)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,2*"), ColumnSpacing = 20 };
            row.Children.Add(Label(spell.DisplayName, 14, true));
            var failure = spell.FailureRate is { } rate ? $"（{BehaviorInsights.Percent(rate)}）" : "";
            var detail = Label($"成功 {Number(spell.Successes)}  ·  失败 {Number(spell.Failures)}{failure}  ·  中断 {Number(spell.Interrupted)}", 12, color: Muted);
            detail.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(detail, 1); row.Children.Add(detail); panel.Children.Add(row);
        }
        return Surface(panel);
    }

    private static Control BuildZones(BehaviorAnalysis analysis)
    {
        var panel = Section("区域分布", analysis.ZoneDetailDays > 0
            ? "按停留时长排序 · 显示前 10 项 · 经验效率只用采集器 0.2.1 起完整记录的日期，停留不足 15 分钟不计算"
            : "按停留时长排序 · 显示前 10 项 · 将游戏内采集插件更新到 0.2.1 后，可按区域比较每小时经验和死亡");
        var zones = analysis.Zones.Take(10).ToList();
        if (zones.Count == 0) panel.Children.Add(Label("当前范围没有区域明细。未识别区域的时长不会被编造为某个地点。", 13, color: Muted));
        var max = Math.Max(1, zones.Select(x => x.Seconds).DefaultIfEmpty().Max());
        foreach (var zone in zones)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*"), ColumnSpacing = 20, RowDefinitions = new RowDefinitions("Auto,Auto"), RowSpacing = 8 };
            row.Children.Add(Label(zone.DisplayName, 14, true));
            var extra = (zone.XpPerHour is { } xph ? $"  ·  每小时 {BehaviorInsights.Number(xph)} 经验" : "")
                + (zone.DetailSeconds > 0 && zone.Deaths > 0 ? $"  ·  死亡 {Number(zone.Deaths)}" : "");
            var detail = Label($"{Duration(zone.Seconds)}  ·  进入 {Number(zone.Visits)} 次{extra}", 12, color: Muted);
            detail.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(detail, 1); row.Children.Add(detail);
            var bar = new ProgressBar { Height = 5, Minimum = 0, Maximum = max, Value = Math.Max(0, zone.Seconds), Foreground = Blue, Background = Soft };
            AutomationProperties.SetName(bar, $"{zone.DisplayName} 停留时长 {Duration(zone.Seconds)}");
            Grid.SetRow(bar, 1); Grid.SetColumnSpan(bar, 2); row.Children.Add(bar); panel.Children.Add(row);
        }
        return Surface(panel);
    }

    private Control BuildAiPanel()
    {
        changingAi = true;
        aiEnabled.IsChecked = aiSettings.Enabled;
        aiProvider.ItemsSource = BehaviorAiPresets.All.Select(p => p.Label).ToArray();
        aiProvider.SelectedIndex = Math.Max(0, BehaviorAiPresets.All.ToList().FindIndex(p => p.Id == aiSettings.Provider));
        aiEndpoint.Text = aiSettings.Endpoint;
        aiModel.Text = aiSettings.Model;
        aiKey.Text = aiSettings.ApiKey;
        aiRemember.IsChecked = aiSettings.RememberKey;
        aiPresetNote.Text = BehaviorAiPresets.Find(aiSettings.Provider).Note;
        changingAi = false;
        AutomationProperties.SetName(aiEnabled, "启用 AI 复盘");
        AutomationProperties.SetName(aiProvider, "模型服务");
        AutomationProperties.SetName(aiEndpoint, "接口地址");
        AutomationProperties.SetName(aiModel, "模型名称");
        AutomationProperties.SetName(aiKey, "API Key");
        AutomationProperties.SetName(aiQuestion, "想重点问的问题");
        AutomationProperties.SetName(aiGenerate, "生成 AI 复盘");

        aiEnabled.Click += (_, _) =>
        {
            if (aiEnabled.IsChecked != true) aiCancellation?.Cancel();
            SaveAi(false);
            UpdateAiState();
        };
        aiProvider.SelectionChanged += (_, _) =>
        {
            if (changingAi || aiProvider.SelectedIndex < 0) return;
            var preset = BehaviorAiPresets.All[Math.Min(aiProvider.SelectedIndex, BehaviorAiPresets.All.Count - 1)];
            aiKey.Text = "";
            aiRemember.IsChecked = false;
            if (preset.Id != "custom") { aiEndpoint.Text = preset.Endpoint; aiModel.Text = preset.Model; }
            aiPresetNote.Text = preset.Note;
        };
        aiQuestion.TextChanged += (_, _) => { UpdateAiContext(); UpdateAiState(); };
        aiRemember.Click += (_, _) => SaveAi(false);
        aiGenerate.Click += async (_, _) => await GenerateAiAsync();
        aiCancel.Click += (_, _) => aiCancellation?.Cancel();
        var save = new Button { Content = "保存设置", MinHeight = 38, Padding = new Thickness(16, 8), CornerRadius = new CornerRadius(7) };
        save.Click += (_, _) => SaveAi(true);

        Control Field(string title, Control input) => new StackPanel { Spacing = 5, Children = { Label(title, 12, true, Muted), input } };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*"), RowDefinitions = new RowDefinitions("Auto,Auto"), ColumnSpacing = 14, RowSpacing = 10 };
        var cells = new[] { Field("模型服务", aiProvider), Field("接口地址", aiEndpoint), Field("模型名称", aiModel), Field("API Key", aiKey) };
        for (var i = 0; i < cells.Length; i++) { Grid.SetColumn(cells[i], i % 2); Grid.SetRow(cells[i], i / 2); grid.Children.Add(cells[i]); }
        var settingsRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14, Children = { save, aiRemember } };
        aiRemember.VerticalAlignment = VerticalAlignment.Center;
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Children = { aiGenerate, aiCancel } };
        var preview = new Expander
        {
            Header = "发送前预览：这次会发给模型的全部内容", Content = aiPreview, IsExpanded = false,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
        };
        aiSettingsPanel.Children.Add(grid);
        aiSettingsPanel.Children.Add(aiPresetNote);
        aiSettingsPanel.Children.Add(settingsRow);
        aiSettingsPanel.Children.Add(new Border { Height = 1, Background = Line, Margin = new Thickness(0, 4) });
        aiSettingsPanel.Children.Add(Field("这次想重点问什么", aiQuestion));
        aiSettingsPanel.Children.Add(actions);
        aiSettingsPanel.Children.Add(aiStatus);
        aiSettingsPanel.Children.Add(aiResultHost);
        aiSettingsPanel.Children.Add(preview);
        aiSettingsPanel.Children.Add(Label("AI 内容由你选择的第三方或本机模型生成，可能出错，请以上方统计数字为准；云端模型按服务商规则计费。自动摘要包含汇总数字、职业等级、技能和区域名称，不含角色名、账号、聊天、按键或文件路径。你填写的问题也会发送，请检查预览。", 12, color: Muted));

        var panel = Section("AI 复盘（可选）", "让大模型根据上面的统计像教练一样复盘：指出最值得改进的地方，并给出下次可以怎么做。默认关闭，只在你点击生成时发送。");
        panel.Children.Add(aiEnabled);
        panel.Children.Add(aiSettingsPanel);
        UpdateAiState();
        return Surface(panel);
    }

    private BehaviorAiSettings ReadAiFields()
    {
        var preset = BehaviorAiPresets.All[Math.Clamp(aiProvider.SelectedIndex, 0, BehaviorAiPresets.All.Count - 1)];
        aiSettings = new BehaviorAiSettings
        {
            Enabled = aiEnabled.IsChecked == true, Provider = preset.Id,
            Endpoint = (aiEndpoint.Text ?? "").Trim(), Model = (aiModel.Text ?? "").Trim(),
            ApiKey = (aiKey.Text ?? "").Trim(), RememberKey = aiRemember.IsChecked == true
        };
        return aiSettings;
    }

    private void SaveAi(bool announce)
    {
        try
        {
            aiStore.Save(ReadAiFields());
            if (announce) { aiStatus.Text = aiSettings.RememberKey || aiSettings.ApiKey.Length == 0 ? "设置已保存。" : "设置已保存；密钥只保留到关闭软件。"; aiStatus.Foreground = Muted; }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        { aiStatus.Text = "设置未能保存，请检查软件状态目录权限。本次仍可使用当前填写的内容。"; aiStatus.Foreground = Warn; }
    }

    private void UpdateAiContext()
    {
        var selected = character.SelectedIndex > 0 && character.SelectedIndex <= characterOptions.Count ? characterOptions[character.SelectedIndex - 1].Id : "all";
        var next = selected + "|" + range.SelectedIndex.ToString(CultureInfo.InvariantCulture) + "|" +
            (currentAnalysis is null ? "" : BehaviorAiCoach.BuildSummary(currentAnalysis, currentCharacters, aiQuestion.Text));
        if (next == aiContext) return;
        aiContext = next;
        aiCancellation?.Cancel();
        aiResult.Text = "";
        aiResultHost.IsVisible = false;
        aiStatus.Text = "";
    }

    private void UpdateAiState()
    {
        var enabled = aiEnabled.IsChecked == true;
        aiSettingsPanel.IsVisible = enabled;
        aiGenerate.IsEnabled = enabled && currentAnalysis is not null && !aiRunning;
        foreach (var field in new Control[] { aiProvider, aiEndpoint, aiModel, aiKey, aiRemember, aiQuestion })
            field.IsEnabled = !aiRunning;
        aiCancel.IsVisible = aiRunning;
        const string noData = "当前范围还没有可复盘的统计。";
        if (enabled && currentAnalysis is null && !aiRunning && string.IsNullOrEmpty(aiStatus.Text)) aiStatus.Text = noData;
        else if (currentAnalysis is not null && aiStatus.Text == noData) aiStatus.Text = "";
        UpdateAiPreview();
    }

    private void UpdateAiPreview()
    {
        if (aiEnabled.IsChecked != true) return;
        if (aiRunning) { aiPreview.Text = aiSentPreview; return; }
        aiPreview.Text = currentAnalysis is null
            ? "当前范围没有可发送的统计。"
            : "【固定规则说明】\n" + BehaviorAiCoach.SystemPrompt + "\n\n【统计摘要】\n" + BehaviorAiCoach.BuildSummary(currentAnalysis, currentCharacters, aiQuestion.Text);
    }

    private async Task GenerateAiAsync()
    {
        if (aiRunning || disposed || currentAnalysis is null || aiEnabled.IsChecked != true) return;
        var settings = ReadAiFields();
        var message = BehaviorAiCoach.BuildSummary(currentAnalysis, currentCharacters, aiQuestion.Text);
        aiSentPreview = "【固定规则说明】\n" + BehaviorAiCoach.SystemPrompt + "\n\n【统计摘要】\n" + message;
        var context = aiContext;
        var cancellation = new CancellationTokenSource();
        aiCancellation = cancellation;
        aiRunning = true;
        aiStatus.Text = "正在请求模型，通常需要 10～60 秒…";
        aiStatus.Foreground = Muted;
        UpdateAiState();
        try
        {
            try { aiStore.Save(settings); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            var answer = await BehaviorAiCoach.AskAsync(settings, message, null, cancellation.Token);
            if (disposed || context != aiContext || cancellation.IsCancellationRequested) return;
            aiResult.Text = answer;
            aiResultHost.IsVisible = true;
            aiStatus.Text = $"已生成 · {DateTimeOffset.Now:HH:mm} · {BehaviorAiPresets.Find(settings.Provider).Label} / {settings.Model}。AI 可能出错，请以上方统计数字为准。";
        }
        catch (OperationCanceledException) { if (!disposed && context == aiContext) aiStatus.Text = "已停止。"; }
        catch (BehaviorAiException e) { if (!disposed && context == aiContext) { aiStatus.Text = e.Message; aiStatus.Foreground = Warn; } }
        catch (Exception) { if (!disposed && context == aiContext) { aiStatus.Text = "生成失败，请稍后重试。"; aiStatus.Foreground = Warn; } }
        finally
        {
            if (ReferenceEquals(aiCancellation, cancellation)) aiCancellation = null;
            cancellation.Dispose();
            aiRunning = false;
            if (!disposed) UpdateAiState();
        }
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
        aiCancellation?.Cancel();
    }
}
