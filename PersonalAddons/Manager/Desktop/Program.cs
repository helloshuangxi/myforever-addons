using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Media;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using MyForeverManager.Core;

namespace MyForeverManager.Desktop;

internal static class Program
{
    internal static string? StartupMessage { get; private set; }
    internal static bool AlreadyRunning { get; private set; }
    internal static SettingsStore Store { get; private set; } = null!;

    [STAThread]
    public static void Main(string[] args)
    {
        var stateDirectory = Environment.GetEnvironmentVariable("MYFOREVER_MANAGER_STATE_DIR");
        Store = new SettingsStore(string.IsNullOrWhiteSpace(stateDirectory) ? null : stateDirectory);
        FileStream? instanceLock = null;
        try
        {
            Directory.CreateDirectory(Store.DirectoryPath);
            instanceLock = new FileStream(Path.Combine(Store.DirectoryPath, "desktop.lock"), FileMode.OpenOrCreate,
                FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException)
        {
            AlreadyRunning = true;
            StartupMessage = "程序可能已经运行，或设置目录暂时无法访问。请先检查任务栏 / Dock；若没有运行中的管理器，请检查磁盘空间和设置目录权限。";
        }
        catch (Exception ex)
        {
            StartupMessage = "无法打开程序设置目录。请确认当前账户有写入权限。\n" + ex.Message;
        }

        try { BuildAvaloniaApp().StartWithClassicDesktopLifetime(args); }
        finally { instanceLock?.Dispose(); }
    }

    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<ManagerApp>().UsePlatformDetect();
}

public sealed class ManagerApp : Application
{
    public override void Initialize()
    {
        RequestedThemeVariant = ThemeVariant.Light;
        Styles.Add(new FluentTheme());
        Resources["SystemAccentColor"] = Color.Parse("#2864B3");
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnMainWindowClose;
            desktop.MainWindow = new MainWindow(Program.Store, Program.StartupMessage, Program.AlreadyRunning);
        }
        base.OnFrameworkInitializationCompleted();
    }
}
