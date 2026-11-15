using System.Diagnostics;
using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using MyForeverManager.Core;

namespace MyForeverManager.Desktop;

public sealed class MainWindow : Window
{
    // Suite palette, direction B "Midnight". Names kept from the light theme.
    private static readonly IBrush Ink = Brush.Parse("#EEF1FF");
    private static readonly IBrush Muted = Brush.Parse("#A3ABCB");
    private static readonly IBrush Cream = Brush.Parse("#0A0E19");
    private static readonly IBrush Line = Brush.Parse("#232B48");
    private static readonly IBrush Card = Brush.Parse("#121830");
    private static readonly IBrush Raised = Brush.Parse("#1B2242");
    private static readonly IBrush Well = Brush.Parse("#0D1222");
    private static readonly IBrush Accent = Brush.Parse("#7C93FF");
    private static readonly IBrush OnAccent = Brush.Parse("#0B1030");
    private static readonly IBrush Warning = Brush.Parse("#FF9A7A");
    private readonly SettingsStore store;
    private readonly UpdateService service;
    private ManagerSettings settings = new();
    private readonly Dictionary<string, AddonCard> cards = new();
    private readonly HashSet<string> pending = new(StringComparer.Ordinal);
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(60) };
    private readonly List<Control> mutationControls = [];
    private CancellationTokenSource? operationCancellation;
    private DateTimeOffset lastCheck = DateTimeOffset.MinValue;
    private TextBlock statusText = new();
    private TextBlock lastCheckedText = new();
    private ProgressBar progressBar = new();
    private CheckBox automatic = new();
    private BehaviorStatisticsView? behaviorView;
    private bool busy, exitRequested, changingControls, dashboard, dialogOpen, behaviorTabSelected;

    public MainWindow(SettingsStore store, string? startupMessage, bool alreadyRunning)
    {
        this.store = store;
        service = new UpdateService(store.DirectoryPath);
        Title = "我的无限 · 插件与行为统计";
        Width = 1080;
        Height = 840;
        MinWidth = 760;
        MinHeight = 640;
        Background = Cream;
        Foreground = Ink;
        FontSize = 14;
        FontFamily = new FontFamily("PingFang SC, Microsoft YaHei, Noto Sans CJK SC, sans-serif");
        using (var icon = typeof(MainWindow).Assembly.GetManifestResourceStream("Manager.Icon"))
            if (icon is not null) Icon = new WindowIcon(icon);
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Closing += OnClosing;
        Closed += (_, _) => { timer.Stop(); behaviorView?.Dispose(); service.Dispose(); operationCancellation?.Dispose(); };
        PropertyChanged += (_, change) =>
        {
            if (change.Property == WindowStateProperty)
                behaviorView?.SetActive(behaviorTabSelected && WindowState != WindowState.Minimized);
        };
        timer.Tick += async (_, _) =>
        {
            if (busy || dialogOpen || !dashboard || exitRequested) return;
            if (pending.Count > 0 || DateTimeOffset.UtcNow - lastCheck >= TimeSpan.FromMinutes(30))
                await RunAsync(() => CheckAndUpdateAsync(settings.AutoUpdate));
        };

        if (alreadyRunning || startupMessage is not null)
        {
            var close = MakeButton("关闭", () => { Close(); return Task.CompletedTask; }, true);
            Content = new StackPanel { Margin = new Thickness(42), Spacing = 24, Children =
                { Text("我的无限", 30, true), Text(startupMessage ?? "程序已经在运行。"), close } };
            return;
        }

        try { settings = store.Load(); }
        catch (Exception ex) { startupMessage = "原有设置无法读取，请重新选择目录。" + FriendlyError(ex); }
        if (string.IsNullOrWhiteSpace(settings.GameDirectory)) ShowSetup(startupMessage);
        else
        {
            try { settings.GameDirectory = GamePaths.Resolve(settings.GameDirectory); ShowDashboard(); }
            catch (Exception ex) { ShowSetup("之前的游戏目录暂时不可用，请重新选择。\n" + FriendlyError(ex)); }
        }

        Opened += async (_, _) =>
        {
            timer.Start();
            if (dashboard) await RunAsync(() => CheckAndUpdateAsync(settings.AutoUpdate));
        };
    }

    private static TextBlock Text(string value, double size = 14, bool bold = false, IBrush? color = null) => new()
    {
        Text = value, FontSize = size, FontWeight = bold ? FontWeight.SemiBold : FontWeight.Normal,
        Foreground = color ?? Ink, TextWrapping = TextWrapping.Wrap
    };

    private static Button MakeButton(string label, Func<Task> action, bool primary = false)
    {
        var button = new Button
        {
            Content = label, Padding = new Thickness(18, 11), MinHeight = 42,
            CornerRadius = new CornerRadius(10), FontWeight = FontWeight.SemiBold,
            Background = primary ? Accent : Raised, Foreground = primary ? OnAccent : Ink,
            BorderBrush = primary ? Accent : Raised, BorderThickness = new Thickness(1)
        };
        button.Click += async (_, _) => await action();
        return button;
    }

    private static Border Surface(Control child, Thickness? padding = null) => new()
    {
        Background = Card, BorderBrush = Line, BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(16), Padding = padding ?? new Thickness(24), Child = child
    };

    private StackPanel Shell(string eyebrow, string title, string subtitle)
    {
        var column = new StackPanel { Margin = new Thickness(36, 28, 36, 30), Spacing = 22 };
        column.Children.Add(Text(eyebrow, 12, true, Muted));
        column.Children.Add(new StackPanel { Spacing = 8, Children = { Text(title, 31, true), Text(subtitle, 14, false, Muted) } });
        Content = new ScrollViewer { Content = column, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        return column;
    }

    private void ShowSetup(string? message = null)
    {
        var canCancel = dashboard;
        dashboard = false;
        behaviorTabSelected = false;
        behaviorView?.Dispose();
        behaviorView = null;
        mutationControls.Clear();
        cards.Clear();
        var column = Shell($"AFABIAOGE.XYZ  /  v{ManagerVersion.Current} 试用版", "先找到你的魔兽世界", "目录只需设置一次。之后在这里管理聊天、商业技能助手、世界向导和目标选择。");
        var panel = new StackPanel { Spacing = 18 };
        panel.Children.Add(Text("1  选择游戏安装目录", 18, true));
        panel.Children.Add(Text("可选择 World of Warcraft、_forever_，或其中的 Interface / AddOns 文件夹。仅适用于国服《魔兽世界：无限》。", 14, false, Muted));
        var directory = new TextBox
        {
            Text = settings.GameDirectory, Watermark = OperatingSystem.IsWindows() ? @"例如 D:\World of Warcraft" : "例如 /Applications/World of Warcraft",
            MinHeight = 44, VerticalContentAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Stretch
        };
        AutomationProperties.SetName(directory, "魔兽世界安装目录");
        var choose = MakeButton("浏览文件夹", async () =>
        {
            try
            {
                var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "选择魔兽世界安装目录", AllowMultiple = false });
                if (folders.Count > 0) directory.Text = folders[0].TryGetLocalPath();
            }
            catch (Exception ex) { await NoticeAsync("无法打开文件夹选择器", FriendlyError(ex) + "\n也可以直接在输入框填写目录。"); }
        });
        var pathRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), ColumnSpacing = 10 };
        pathRow.Children.Add(directory); Grid.SetColumn(choose, 1); pathRow.Children.Add(choose);
        panel.Children.Add(pathRow);
        panel.Children.Add(Text("2  选择要管理的插件", 18, true));
        var selections = new Dictionary<string, CheckBox>();
        foreach (var addon in AddonCatalog.All)
        {
            var selected = new CheckBox { Content = addon.DisplayName, IsChecked = string.IsNullOrEmpty(settings.GameDirectory) || settings.ManagedAddons.Contains(addon.Id), FontSize = 16 };
            selections[addon.Id] = selected;
            panel.Children.Add(new StackPanel { Spacing = 3, Children = { selected, Text(addon.Description, 13, false, Muted) } });
        }
        var auto = new CheckBox { Content = "自动安装所选插件，并在有新版本时自动更新", IsChecked = settings.AutoUpdate };
        panel.Children.Add(auto);
        panel.Children.Add(Text("程序运行期间每 30 分钟检查一次；游戏运行时等待退出后再安装。可以最小化程序继续管理，关闭窗口即退出。", 13, false, Muted));
        var error = Text(message ?? "", 13, false, Warning);
        panel.Children.Add(error);
        var start = MakeButton("保存并开始管理", async () =>
        {
            try
            {
                var resolved = GamePaths.Resolve(directory.Text?.Trim() ?? "");
                var selectedIds = selections.Where(x => x.Value.IsChecked == true).Select(x => x.Key).ToList();
                if (selectedIds.Count == 0) { error.Text = "请至少选择一个要管理的插件。"; return; }
                var next = new ManagerSettings { GameDirectory = resolved, ManagedAddons = selectedIds, AutoUpdate = auto.IsChecked == true };
                store.Save(next);
                settings = next;
                pending.Clear();
                ShowDashboard();
                await RunAsync(() => CheckAndUpdateAsync(settings.AutoUpdate));
            }
            catch (Exception ex) { error.Text = FriendlyError(ex); }
        }, true);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Children = { start } };
        if (canCancel)
            actions.Children.Add(MakeButton("取消", async () => { ShowDashboard(); await RunAsync(() => CheckAndUpdateAsync(settings.AutoUpdate)); }));
        panel.Children.Add(actions);
        column.Children.Add(Surface(panel));
        column.Children.Add(Text("更新时校验 SHA-256，并保留上一版插件备份。个人设置和聊天记录所在的 WTF 目录保持原样。", 13, false, Muted));
    }

    private void ShowDashboard()
    {
        behaviorView?.Dispose();
        dashboard = true;
        cards.Clear();
        mutationControls.Clear();
        var column = new StackPanel { Margin = new Thickness(36, 24, 36, 30), Spacing = 22 };
        column.Children.Add(new StackPanel { Spacing = 8, Children =
        {
            Text("你的插件，一处管理。", 28, true),
            Text("从作者官网检查与安装更新。聊天、商业技能助手、世界向导和目标选择，分别维护。", 14, false, Muted)
        } });
        var location = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), ColumnSpacing = 20 };
        var directoryText = Text(settings.GameDirectory, 14, true);
        ToolTip.SetTip(directoryText, GamePaths.AddonsDirectory(settings.GameDirectory));
        location.Children.Add(new StackPanel { Spacing = 5, Children = { Text("游戏目录", 12, false, Muted), directoryText } });
        var changeDirectory = MakeButton("更换目录", () => { ShowSetup(); return Task.CompletedTask; });
        Grid.SetColumn(changeDirectory, 1); location.Children.Add(changeDirectory); mutationControls.Add(changeDirectory);
        column.Children.Add(Surface(location, new Thickness(20, 16)));
        automatic = new CheckBox { Content = "自动安装 / 更新已勾选插件", IsChecked = settings.AutoUpdate };
        automatic.IsCheckedChanged += async (_, _) =>
        {
            if (changingControls || busy) return;
            var nextValue = automatic.IsChecked == true;
            var old = settings.AutoUpdate;
            settings.AutoUpdate = nextValue;
            if (!TrySave()) { settings.AutoUpdate = old; changingControls = true; automatic.IsChecked = old; changingControls = false; return; }
            if (!nextValue) { pending.Clear(); SetStatus("自动更新已关闭，可手动检查和安装。"); }
            else await RunAsync(() => CheckAndUpdateAsync(true));
        };
        var check = MakeButton("立即检查更新", () => RunAsync(() => CheckAndUpdateAsync(settings.AutoUpdate)), true);
        mutationControls.Add(automatic); mutationControls.Add(check);
        var controls = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        controls.Children.Add(new StackPanel { Spacing = 4, Children = { automatic, Text("运行期间每 30 分钟检查；游戏中暂缓安装。", 12, false, Muted) } });
        Grid.SetColumn(check, 1); controls.Children.Add(check); column.Children.Add(controls);

        var cardGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*,*"), ColumnSpacing = 18, RowSpacing = 18 };
        var cardSurfaces = new List<Border>();
        foreach (var addon in AddonCatalog.All)
        {
            var card = new AddonCard(addon, this);
            cards.Add(addon.Id, card);
            cardSurfaces.Add(card.Surface); cardGrid.Children.Add(card.Surface);
        }
        void ArrangeCards()
        {
            var columns = cardGrid.Bounds.Width >= 1280 ? 4 : 2;
            cardGrid.ColumnDefinitions = new ColumnDefinitions(string.Join(",", Enumerable.Repeat("*", columns)));
            cardGrid.RowDefinitions = new RowDefinitions(string.Join(",", Enumerable.Repeat("Auto", (cardSurfaces.Count + columns - 1) / columns)));
            for (var index = 0; index < cardSurfaces.Count; index++)
            {
                Grid.SetColumn(cardSurfaces[index], index % columns);
                Grid.SetRow(cardSurfaces[index], index / columns);
            }
        }
        cardGrid.SizeChanged += (_, _) => ArrangeCards();
        ArrangeCards();
        column.Children.Add(cardGrid);
        statusText = Text("准备检查插件版本…", 14, false, Muted);
        lastCheckedText = Text("", 12, false, Muted);
        progressBar = new ProgressBar { Height = 3, IsVisible = false, IsIndeterminate = true };
        column.Children.Add(new StackPanel { Spacing = 9, Children = { progressBar, statusText, lastCheckedText } });

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        footer.Children.Add(MakeButton("访问官网", () => OpenLinkAsync("https://afabiaoge.xyz/manager/")));
        footer.Children.Add(MakeButton("最小化继续运行", () => { WindowState = WindowState.Minimized; return Task.CompletedTask; }));
        footer.Children.Add(MakeButton("退出程序", () => { Close(); return Task.CompletedTask; }));
        column.Children.Add(footer);
        column.Children.Add(Text("更新只管理所选插件目录，保留 WTF。关闭窗口会退出程序；当前试用版不设置开机启动。", 12, false, Muted));

        behaviorView = new BehaviorStatisticsView(new BehaviorDataService(store.DirectoryPath), settings.GameDirectory, new BehaviorAiSettingsStore(store.DirectoryPath));
        var tabs = new TabControl
        {
            Items =
            {
                new TabItem { Header = "插件管理", Content = new ScrollViewer { Content = column, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled } },
                new TabItem { Header = "行为统计", Content = behaviorView }
            },
            SelectedIndex = 1
        };
        AutomationProperties.SetName(tabs, "我的无限功能页");
        var statistics = behaviorView;
        behaviorTabSelected = true;
        tabs.SelectionChanged += (_, _) =>
        {
            behaviorTabSelected = tabs.SelectedIndex == 1;
            statistics.SetActive(behaviorTabSelected && WindowState != WindowState.Minimized);
        };
        statistics.SetActive(WindowState != WindowState.Minimized);
        var root = new Grid { RowDefinitions = new RowDefinitions("Auto,*") };
        root.Children.Add(new StackPanel
        {
            Margin = new Thickness(36, 24, 36, 18), Spacing = 5, Children =
            {
                Text("我的无限", 23, true),
                Text($"v{ManagerVersion.Current} 试用版  ·  插件管理与玩家行为统计", 12, false, Muted)
            }
        });
        Grid.SetRow(tabs, 1); root.Children.Add(tabs);
        Content = root;
        ApplyEnabledState();
    }

    private async Task RunAsync(Func<Task> action)
    {
        if (busy || exitRequested) return;
        busy = true;
        operationCancellation = new CancellationTokenSource();
        ApplyEnabledState();
        progressBar.IsVisible = true;
        try { await action(); }
        catch (OperationCanceledException) { SetStatus(exitRequested ? "正在安全退出…" : "操作已取消。"); }
        catch (Exception ex) { SetStatus(FriendlyError(ex), true); }
        finally
        {
            busy = false;
            operationCancellation.Dispose(); operationCancellation = null;
            progressBar.IsVisible = false;
            ApplyEnabledState();
            if (exitRequested) Close();
        }
    }

    private CancellationToken Token => operationCancellation?.Token ?? CancellationToken.None;

    private async Task CheckAndUpdateAsync(bool allowAutomatic)
    {
        var failures = 0;
        var updates = 0;
        SetStatus("正在连接 afabiaoge.xyz，检查最新版本…");
        foreach (var addon in AddonCatalog.All)
        {
            Token.ThrowIfCancellationRequested();
            try
            {
                var status = await Task.Run(() => service.CheckAsync(addon, settings.GameDirectory, Token), Token);
                cards[addon.Id].Update(status);
                if (status.Error is not null) { failures++; continue; }
                var managed = settings.ManagedAddons.Contains(addon.Id);
                if (!managed || !status.CanInstall) { pending.Remove(addon.Id); continue; }
                updates++;
                if (allowAutomatic || pending.Contains(addon.Id))
                {
                    if (GameProcesses.IsGameRunning()) { pending.Add(addon.Id); cards[addon.Id].SetNotice("等待游戏退出后安装"); }
                    else
                    {
                        try { await InstallOneAsync(addon, status); }
                        catch (OperationCanceledException) { throw; }
                        catch (Exception ex)
                        {
                            if (GameProcesses.IsGameRunning()) { pending.Add(addon.Id); cards[addon.Id].SetNotice("等待游戏退出后安装"); }
                            else { failures++; pending.Remove(addon.Id); cards[addon.Id].SetNotice(FriendlyError(ex), true); }
                        }
                    }
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { failures++; cards[addon.Id].SetNotice(FriendlyError(ex), true); }
        }
        lastCheck = DateTimeOffset.UtcNow;
        lastCheckedText.Text = $"上次检查：{DateTime.Now:MM-dd HH:mm}  ·  来源：afabiaoge.xyz";
        if (pending.Count > 0) SetStatus($"有 {pending.Count} 个插件等待游戏退出，程序将每分钟重试。");
        else if (failures > 0) SetStatus($"{failures} 个插件未能完成检查或更新，请查看卡片提示后重试。", true);
        else if (updates > 0 && !allowAutomatic) SetStatus("发现可安装的版本，点击对应插件的安装 / 更新按钮。");
        else SetStatus("检查完成，已管理插件的版本状态见上方。");
    }

    private async Task InstallOneAsync(AddonDefinition addon, AddonStatus status)
    {
        if (status.Latest is null || !status.CanInstall) return;
        var reporter = new Progress<string>(message => { SetStatus(message); cards[addon.Id].SetNotice(message); });
        await Task.Run(() => service.InstallAsync(addon, status.Latest, settings.GameDirectory, reporter, Token), Token);
        pending.Remove(addon.Id);
        cards[addon.Id].Update(await Task.Run(() => service.CheckAsync(addon, settings.GameDirectory, Token), Token));
        cards[addon.Id].SetNotice("安装完成，启动游戏后生效");
        SetStatus($"{addon.DisplayName} 已更新。可以启动游戏了。");
    }

    private Task InstallRequestedAsync(AddonCard card) => RunAsync(async () =>
    {
        var status = await Task.Run(() => service.CheckAsync(card.Addon, settings.GameDirectory, Token), Token);
        card.Update(status);
        if (status.Error is not null) { SetStatus(status.Error, true); return; }
        if (!status.CanInstall) { SetStatus("当前无需更新。"); return; }
        if (GameProcesses.IsGameRunning())
        {
            pending.Add(card.Addon.Id); card.SetNotice("等待游戏退出后安装");
            SetStatus("游戏正在运行。退出游戏后，管理器将自动继续安装。"); return;
        }
        try { await InstallOneAsync(card.Addon, status); }
        catch (Exception) when (!Token.IsCancellationRequested && GameProcesses.IsGameRunning())
        {
            pending.Add(card.Addon.Id); card.SetNotice("等待游戏退出后安装");
            SetStatus("检测到游戏启动，安装已暂缓。退出游戏后将继续。");
        }
    });

    private async Task RestoreRequestedAsync(AddonCard card)
    {
        if (busy) return;
        bool yes;
        dialogOpen = true;
        try { yes = await ConfirmAsync("恢复上一版", $"将恢复「{card.Addon.DisplayName}」的上一版备份。\n\n恢复成功后会关闭自动更新，以保留恢复后的版本。个人设置和聊天记录不受影响。"); }
        finally { dialogOpen = false; }
        if (!yes) return;
        await RunAsync(async () =>
        {
            // Save the opt-out before restoring; a failed save must not lead to an automatic re-upgrade.
            var wasAutomatic = settings.AutoUpdate;
            settings.AutoUpdate = false;
            try { store.Save(settings); }
            catch { settings.AutoUpdate = wasAutomatic; throw; }
            changingControls = true; automatic.IsChecked = false; changingControls = false;
            pending.Clear();
            var reporter = new Progress<string>(message => SetStatus(message));
            await Task.Run(() => service.RestoreAsync(card.Addon, settings.GameDirectory, reporter, Token), Token);
            card.Update(await Task.Run(() => service.CheckAsync(card.Addon, settings.GameDirectory, Token), Token));
            SetStatus($"{card.Addon.DisplayName} 已恢复。自动更新已关闭，可在需要时重新开启。");
        });
    }

    private void ApplyEnabledState()
    {
        foreach (var control in mutationControls) control.IsEnabled = !busy && !exitRequested;
        foreach (var card in cards.Values) card.ApplyEnabledState(!busy && !exitRequested);
    }

    private bool TrySave()
    {
        try { store.Save(settings); return true; }
        catch (Exception ex) { SetStatus("设置未保存。" + FriendlyError(ex), true); return false; }
    }

    private void SetStatus(string value, bool error = false)
    {
        statusText.Text = value;
        statusText.Foreground = error ? Warning : Muted;
    }

    private static string FriendlyError(Exception ex) => ex switch
    {
        UnauthorizedAccessException => "无法写入该目录。请检查文件夹权限，或将游戏放在当前账户可写入的位置。",
        HttpRequestException => "暂时无法连接官网，请检查网络后重试。现有插件保持不变。",
        TaskCanceledException => "请求超时，请稍后重试。",
        IOException => "文件操作未完成，请退出游戏并检查磁盘空间、目录权限后重试。\n" + ex.Message,
        _ => ex.Message
    };

    private async Task OpenLinkAsync(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) { await NoticeAsync("无法打开浏览器", FriendlyError(ex) + "\n请手动访问 https://afabiaoge.xyz/"); }
    }

    private async Task<bool> ConfirmAsync(string title, string message)
    {
        var dialog = new Window
        {
            Title = title, Width = 490, SizeToContent = SizeToContent.Height, CanResize = false,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = Cream
        };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(MakeButton("取消", () => { dialog.Close(false); return Task.CompletedTask; }));
        buttons.Children.Add(MakeButton("确认恢复", () => { dialog.Close(true); return Task.CompletedTask; }, true));
        dialog.Content = new StackPanel { Margin = new Thickness(28), Spacing = 22, Children = { Text(title, 23, true), Text(message), buttons } };
        return await dialog.ShowDialog<bool>(this);
    }

    private async Task NoticeAsync(string title, string message)
    {
        var dialog = new Window { Title = title, Width = 490, SizeToContent = SizeToContent.Height, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = Cream };
        dialog.Content = new StackPanel { Margin = new Thickness(28), Spacing = 22, Children = { Text(title, 23, true), Text(message), MakeButton("知道了", () => { dialog.Close(); return Task.CompletedTask; }, true) } };
        await dialog.ShowDialog(this);
    }

    private void OnClosing(object? sender, WindowClosingEventArgs args)
    {
        behaviorView?.Dispose();
        if (!busy) return;
        args.Cancel = true;
        exitRequested = true;
        timer.Stop();
        operationCancellation?.Cancel();
        ApplyEnabledState();
        SetStatus("正在完成当前文件操作并安全退出，请稍候…");
    }

    private sealed class AddonCard
    {
        private readonly MainWindow owner;
        private readonly CheckBox managed;
        private readonly TextBlock installed, latest, notice, compatibility;
        private readonly TextBox notes;
        private readonly Button install, restore;
        private AddonStatus? status;
        public AddonDefinition Addon { get; }
        public Border Surface { get; }

        public AddonCard(AddonDefinition addon, MainWindow owner)
        {
            Addon = addon;
            this.owner = owner;
            var content = new StackPanel { Spacing = 13 };
            content.Children.Add(Text(addon.Id switch { "MyForeverChat" => "01  /  CHAT", "MyForeverProfessions" => "02  /  PROFESSIONS", "MyForeverNavigator" => "03  /  NAVIGATOR", "MyForeverTargets" => "04  /  TARGETS", _ => addon.Id }, 11, true, Muted));
            content.Children.Add(Text(addon.DisplayName, 23, true));
            content.Children.Add(new TextBlock { Text = addon.Description, TextWrapping = TextWrapping.Wrap, Foreground = Muted, MinHeight = 42, FontSize = 13 });
            managed = new CheckBox { Content = "由管理器维护此插件", IsChecked = owner.settings.ManagedAddons.Contains(addon.Id) };
            managed.IsCheckedChanged += async (_, _) =>
            {
                if (owner.busy || owner.changingControls) return;
                var previous = owner.settings.ManagedAddons.ToList();
                if (managed.IsChecked == true && !owner.settings.ManagedAddons.Contains(addon.Id)) owner.settings.ManagedAddons.Add(addon.Id);
                if (managed.IsChecked != true) { owner.settings.ManagedAddons.Remove(addon.Id); owner.pending.Remove(addon.Id); }
                if (!owner.TrySave())
                {
                    owner.settings.ManagedAddons = previous; owner.changingControls = true;
                    managed.IsChecked = previous.Contains(addon.Id); owner.changingControls = false;
                }
                ApplyEnabledState(true);
                if (managed.IsChecked == true && owner.settings.AutoUpdate) await owner.RunAsync(() => owner.CheckAndUpdateAsync(true));
            };
            content.Children.Add(managed);
            installed = Text("本地版本    等待检查", 14, true);
            latest = Text("官网版本    等待检查", 14, false, Muted);
            compatibility = Text("适配：国服魔兽世界 · 无限", 12, false, Muted);
            content.Children.Add(installed); content.Children.Add(latest); content.Children.Add(compatibility);
            notes = new TextBox
            {
                IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap,
                Height = 145, Background = Well, BorderThickness = new Thickness(0),
                Padding = new Thickness(12), FontSize = 12, Foreground = Muted,
                Text = "检查更新后，在这里查看作者的更新说明与验证范围。"
            };
            ScrollViewer.SetVerticalScrollBarVisibility(notes, ScrollBarVisibility.Auto);
            content.Children.Add(notes);
            notice = Text("尚未检查", 12, false, Muted); notice.MinHeight = 36;
            content.Children.Add(notice);
            install = MakeButton("安装 / 更新", () => owner.InstallRequestedAsync(this), true);
            restore = MakeButton("恢复上一版", () => owner.RestoreRequestedAsync(this));
            var actions = new WrapPanel { Orientation = Orientation.Horizontal };
            install.Margin = new Thickness(0, 0, 9, 6); restore.Margin = new Thickness(0, 0, 0, 6);
            actions.Children.Add(install); actions.Children.Add(restore); content.Children.Add(actions);
            Surface = MainWindow.Surface(content, new Thickness(23));
        }

        public void Update(AddonStatus value)
        {
            status = value;
            installed.Text = "本地版本    " + (value.InstalledVersion is null ? "未安装" : "v" + value.InstalledVersion);
            if (value.Latest is not null)
            {
                latest.Text = $"官网版本    v{value.Latest.Version} · {(value.Latest.Channel == "trial" ? "试用版" : "正式版")}";
                compatibility.Text = $"适配：{value.Latest.Compatibility.Product} · {value.Latest.Compatibility.Client}";
                notes.Text = "本版变化\n" + string.Join("\n", value.Latest.Changes.Select(x => "• " + x)) + "\n\n验证范围\n" + string.Join("\n", value.Latest.Validation.Select(x => "• " + x));
            }
            else latest.Text = "官网版本    暂时无法获取";
            install.Content = value.InstalledVersion is null ? "安装插件" : value.CanInstall ? "更新插件" : "无需更新";
            SetNotice(value.Error ?? (value.CanInstall ? value.InstalledVersion is null ? "可安装" : "发现新版本" : "当前无需更新"), value.Error is not null);
            ApplyEnabledState(!owner.busy);
        }

        public void SetNotice(string message, bool error = false)
        {
            notice.Text = message;
            notice.Foreground = error ? Warning : Muted;
        }

        public void ApplyEnabledState(bool enabled)
        {
            managed.IsEnabled = enabled;
            install.IsEnabled = enabled && managed.IsChecked == true && status?.CanInstall == true;
            try { restore.IsEnabled = enabled && managed.IsChecked == true && owner.service.HasBackup(Addon, owner.settings.GameDirectory); }
            catch { restore.IsEnabled = false; }
        }
    }
}
