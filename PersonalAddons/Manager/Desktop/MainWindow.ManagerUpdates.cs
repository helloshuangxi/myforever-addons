using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Threading;
using MyForeverManager.Core;

namespace MyForeverManager.Desktop;

public sealed partial class MainWindow
{
    private ManagerAppUpdateBackend? managerBackend;
    private ManagerAppUpdates? managerUpdates;
    private CancellationTokenSource? managerCancellation;
    private DateTimeOffset lastManagerAttempt = DateTimeOffset.MinValue;
    private TextBlock managerNotice = new();
    private Button managerCheck = new(), managerRestart = new();
    private bool managerClosed, restartManager;

    private void InitializeManagerUpdates()
    {
        managerBackend = new ManagerAppUpdateBackend();
        managerUpdates = new ManagerAppUpdates(managerBackend);
        managerUpdates.Changed += () => Dispatcher.UIThread.Post(() =>
        { if (!managerClosed) RefreshManagerUpdates(); });
    }

    private Control ManagerUpdatesPanel()
    {
        var automaticManager = new CheckBox
        {
            Content = "自动更新管理器（退出时安装）", IsChecked = settings.AutoUpdateManager,
            FontSize = 12, MinHeight = 28
        };
        AutomationProperties.SetName(automaticManager, "自动更新管理器自身");
        automaticManager.IsCheckedChanged += async (_, _) =>
        {
            var previous = settings.AutoUpdateManager;
            if (previous == (automaticManager.IsChecked == true)) return;
            settings.AutoUpdateManager = automaticManager.IsChecked == true;
            try { store.Save(settings); }
            catch
            {
                settings.AutoUpdateManager = previous;
                automaticManager.IsChecked = previous;
                managerNotice.Text = "管理器自动更新选项未保存，请检查设置目录权限。";
                return;
            }
            if (!settings.AutoUpdateManager) managerCancellation?.Cancel();
            else await CheckManagerAsync(automatic: true);
            RefreshManagerUpdates();
        };
        managerNotice = Text("", 12, false, Muted);
        managerCheck = MakeButton("检查管理器更新", () => CheckManagerAsync(automatic: false));
        managerRestart = MakeButton("重启并更新管理器", () =>
        {
            restartManager = true;
            Close(); // OnClosing first finishes/cancels any game-addon transaction.
            return Task.CompletedTask;
        });
        managerCheck.FontSize = managerRestart.FontSize = 12;
        managerCheck.MinHeight = managerRestart.MinHeight = 30;
        managerCheck.Padding = managerRestart.Padding = new Thickness(12, 5);
        var actions = new WrapPanel { Orientation = Orientation.Horizontal };
        managerCheck.Margin = new Thickness(0, 0, 8, 0);
        actions.Children.Add(managerCheck);
        actions.Children.Add(managerRestart);
        var panel = new StackPanel { Spacing = 4, Children = { automaticManager, managerNotice, actions } };
        RefreshManagerUpdates();
        return panel;
    }

    private void RefreshManagerUpdates()
    {
        if (managerUpdates is null) return;
        managerNotice.Text = managerUpdates.ReadyRelease is { } ready && managerUpdates.Phase == ManagerAppUpdatePhase.Idle
            ? $"管理器 v{ready.Version} 已下载，可重启更新。" : managerUpdates.Message;
        managerNotice.Foreground = managerUpdates.Phase == ManagerAppUpdatePhase.Failed ? Warning : Muted;
        managerCheck.IsEnabled = !managerUpdates.IsWorking && !exitRequested;
        managerRestart.IsVisible = managerUpdates.IsReady;
        managerRestart.IsEnabled = !exitRequested;
    }

    private async Task CheckManagerAsync(bool automatic)
    {
        if (managerUpdates is null || managerUpdates.IsWorking || managerClosed || exitRequested) return;
        if (automatic && !settings.AutoUpdateManager) return;
        lastManagerAttempt = DateTimeOffset.UtcNow;
        using var cancellation = new CancellationTokenSource();
        managerCancellation = cancellation;
        try { await managerUpdates.CheckAndDownloadAsync(automatic, settings.AutoUpdateManager, cancellation.Token); }
        finally
        {
            managerCancellation = null;
            if (!managerClosed) RefreshManagerUpdates();
        }
    }

    private void CloseManagerUpdates()
    {
        managerClosed = true;
        managerCancellation?.Cancel();
        managerBackend?.Dispose();
    }
}
