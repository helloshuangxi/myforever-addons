namespace MyForeverManager.Core;

public sealed record ManagerAppRelease(string Version);

public interface IManagerAppUpdateBackend
{
    bool IsInstalled { get; }
    ManagerAppRelease? PendingRelease { get; }
    Task<ManagerAppRelease?> CheckAsync(CancellationToken cancellationToken);
    Task DownloadAsync(ManagerAppRelease release, IProgress<int> progress, CancellationToken cancellationToken);
    void ApplyAfterExit(ManagerAppRelease release, bool restart);
}

public enum ManagerAppUpdatePhase { Idle, Unavailable, Checking, Downloading, Current, Ready, Failed, Scheduled }

// App replacement is separate from game-addon transactions. The desktop asks
// this coordinator to schedule only after its own file operation has finished.
public sealed class ManagerAppUpdates(IManagerAppUpdateBackend backend)
{
    private readonly SemaphoreSlim gate = new(1, 1);
    public ManagerAppUpdatePhase Phase { get; private set; } = ManagerAppUpdatePhase.Idle;
    public ManagerAppRelease? ReadyRelease { get; private set; } = backend.PendingRelease;
    public string Message { get; private set; } = "启动后会检查管理器自身的新版本。";
    public DateTimeOffset? LastCheckedAt { get; private set; }
    public bool IsWorking => Phase is ManagerAppUpdatePhase.Checking or ManagerAppUpdatePhase.Downloading;
    public bool IsReady => ReadyRelease is not null && Phase != ManagerAppUpdatePhase.Scheduled;
    public event Action? Changed;

    private void Set(ManagerAppUpdatePhase phase, string message)
    { Phase = phase; Message = message; Changed?.Invoke(); }

    public async Task CheckAndDownloadAsync(bool automatic, bool enabled, CancellationToken cancellationToken = default)
    {
        if (automatic && !enabled) return;
        if (!await gate.WaitAsync(0, cancellationToken)) return;
        try
        {
            if (Phase == ManagerAppUpdatePhase.Scheduled) return;
            if (!backend.IsInstalled)
            {
                Set(ManagerAppUpdatePhase.Unavailable, "请先用新版 DMG 或 Windows 安装程序安装管理器，再使用自身更新。");
                return;
            }
            if (ReadyRelease is not null)
            {
                Set(ManagerAppUpdatePhase.Ready, $"管理器 v{ReadyRelease.Version} 已准备好，可重启更新。");
                return;
            }
            Set(ManagerAppUpdatePhase.Checking, "正在检查管理器自身的新版本…");
            var release = await backend.CheckAsync(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            LastCheckedAt = DateTimeOffset.UtcNow;
            if (release is null)
            { Set(ManagerAppUpdatePhase.Current, "管理器已是当前更新源中的最新版本。"); return; }
            Set(ManagerAppUpdatePhase.Downloading, $"正在下载管理器 v{release.Version}…");
            await backend.DownloadAsync(release, new InlineProgress(value =>
            {
                if (Phase == ManagerAppUpdatePhase.Downloading)
                    Set(ManagerAppUpdatePhase.Downloading, $"正在下载管理器 v{release.Version} · {Math.Clamp(value, 0, 100)}%");
            }), cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            ReadyRelease = release;
            Set(ManagerAppUpdatePhase.Ready, $"管理器 v{release.Version} 已准备好。自动更新开启时，退出后安装；也可立即重启更新。");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        { Set(ManagerAppUpdatePhase.Idle, "已停止检查或下载管理器更新，现有程序不受影响。"); }
        catch (Exception)
        { Set(ManagerAppUpdatePhase.Failed, "暂时无法检查或下载管理器更新，可稍后重试；现有程序与数据保留。"); }
        finally { gate.Release(); }
    }

    public bool ApplyAfterExit(bool enabled, bool restart, bool addonOperationBusy)
    {
        if (Phase == ManagerAppUpdatePhase.Scheduled) return true;
        if (ReadyRelease is null || IsWorking || addonOperationBusy || (!enabled && !restart)) return false;
        try
        {
            backend.ApplyAfterExit(ReadyRelease, restart);
            Set(ManagerAppUpdatePhase.Scheduled, restart ? "正在退出并重启新版管理器…" : "退出后将安装已下载的管理器更新。");
            return true;
        }
        catch (Exception)
        {
            Set(ManagerAppUpdatePhase.Failed, "暂时无法安排管理器更新，旧程序和设置保持原样，可重试。");
            return false;
        }
    }

    private sealed class InlineProgress(Action<int> report) : IProgress<int>
    { public void Report(int value) => report(value); }
}
