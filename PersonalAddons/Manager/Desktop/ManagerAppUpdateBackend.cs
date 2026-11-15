using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using MyForeverManager.Core;
using Velopack;
using Velopack.Logging;
using Velopack.Sources;

namespace MyForeverManager.Desktop;

// App packages are executable code. Only this host and a flat, RID-specific
// directory are trusted; never follow a feed-provided URL or HTTP redirect.
public sealed class ManagerUpdateSource : IUpdateSource, IDisposable
{
    private readonly HttpClient client;
    private readonly Uri root;
    private readonly string channel;
    internal CancellationToken CheckCancellation { get; set; }
    private const long MaxPackageBytes = 512L * 1024 * 1024;

    public ManagerUpdateSource(string rid, HttpMessageHandler? handler = null)
    {
        if (rid is not ("osx-arm64" or "osx-x64" or "win-x64"))
            throw new PlatformNotSupportedException("此平台尚无管理器安装程序。");
        channel = rid;
        root = new Uri($"https://afabiaoge.xyz/manager/updates/{rid}/");
        client = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false })
        { Timeout = TimeSpan.FromMinutes(10) };
    }

    public async Task<VelopackAssetFeed> GetReleaseFeed(IVelopackLogger logger, string? appId,
        string requestedChannel, Guid? stagingId = null, VelopackAsset? latestLocalRelease = null)
    {
        if (requestedChannel != channel) throw new InvalidDataException("更新平台不匹配。");
        using var body = new MemoryStream();
        await FetchAsync($"releases.{channel}.json", body, 2 * 1024 * 1024, null, CheckCancellation);
        var feed = VelopackAssetFeed.FromJson(Encoding.UTF8.GetString(body.ToArray()));
        foreach (var asset in feed.Assets)
        {
            ValidateAsset(asset);
            if (asset.PackageId != "MyForeverManagerApp") throw new InvalidDataException("更新程序身份不匹配。");
        }
        return feed;
    }

    public async Task DownloadReleaseEntry(IVelopackLogger logger, VelopackAsset releaseEntry,
        string localFile, Action<int> progress, CancellationToken cancelToken)
    {
        ValidateAsset(releaseEntry);
        try
        {
            await using var file = new FileStream(localFile, FileMode.Create, FileAccess.Write, FileShare.None);
            var count = await FetchAsync(releaseEntry.FileName, file, releaseEntry.Size, progress, cancelToken);
            if (count != releaseEntry.Size) throw new InvalidDataException("更新包长度不符。");
            // Velopack verifies the package digest before marking it downloaded.
        }
        catch { File.Delete(localFile); throw; }
    }

    private static void ValidateAsset(VelopackAsset asset)
    {
        if (!Regex.IsMatch(asset.FileName ?? "", @"\AMyForeverManagerApp[-.A-Za-z0-9_]*\.nupkg\z") ||
            asset.Size <= 0 || asset.Size > MaxPackageBytes)
            throw new InvalidDataException("更新包名称或大小无效。");
    }

    private async Task<long> FetchAsync(string name, Stream target, long limit, Action<int>? progress, CancellationToken token)
    {
        using var response = await client.GetAsync(new Uri(root, name), HttpCompletionOption.ResponseHeadersRead, token);
        // EnsureSuccessStatusCode alone would accept an automatic redirect if
        // a different handler were ever supplied. Assert the final URI as well.
        var uri = response.RequestMessage?.RequestUri;
        if (response.StatusCode != HttpStatusCode.OK || uri is null || uri != new Uri(root, name))
            throw new HttpRequestException("更新源未返回预期文件。");
        if (response.Content.Headers.ContentLength > limit) throw new InvalidDataException("更新文件过大。");
        await using var input = await response.Content.ReadAsStreamAsync(token);
        var buffer = new byte[65536];
        long total = 0;
        int read;
        while ((read = await input.ReadAsync(buffer, token)) > 0)
        {
            total += read;
            if (total > limit) throw new InvalidDataException("更新文件过大。");
            await target.WriteAsync(buffer.AsMemory(0, read), token);
            progress?.Invoke((int)(total * 100 / limit));
        }
        return total;
    }

    public void Dispose() => client.Dispose();
}

public sealed class ManagerAppUpdateBackend : IManagerAppUpdateBackend, IDisposable
{
    private readonly UpdateManager manager;
    private readonly ManagerUpdateSource? webSource;
    private UpdateInfo? available;

    public static string Platform => (OperatingSystem.IsMacOS(), OperatingSystem.IsWindows(), RuntimeInformation.ProcessArchitecture) switch
    {
        (true, _, Architecture.Arm64) => "osx-arm64",
        (true, _, Architecture.X64) => "osx-x64",
        (_, true, Architecture.X64) => "win-x64",
        _ => throw new PlatformNotSupportedException("此平台尚无管理器安装程序。")
    };

    public ManagerAppUpdateBackend()
    {
        webSource = new ManagerUpdateSource(Platform);
        manager = new UpdateManager(webSource, new UpdateOptions { ExplicitChannel = Platform });
    }

#if SELF_UPDATE_PROBE
    internal ManagerAppUpdateBackend(string localFeed)
    { manager = new UpdateManager(localFeed, new UpdateOptions { ExplicitChannel = Platform }); }
    internal string? InstalledVersion => manager.CurrentVersion?.ToString();
#endif

    public bool IsInstalled => manager.IsInstalled;
    public ManagerAppRelease? PendingRelease => manager.UpdatePendingRestart is { } pending ? new(pending.Version.ToString()) : null;

    public async Task<ManagerAppRelease?> CheckAsync(CancellationToken cancellationToken)
    {
        if (webSource is not null) webSource.CheckCancellation = cancellationToken;
        available = await manager.CheckForUpdatesAsync();
        cancellationToken.ThrowIfCancellationRequested();
        return available is null ? null : new(available.TargetFullRelease.Version.ToString());
    }

    public Task DownloadAsync(ManagerAppRelease release, IProgress<int> progress, CancellationToken cancellationToken)
    {
        if (available is null || available.TargetFullRelease.Version.ToString() != release.Version)
            throw new InvalidOperationException("请重新检查更新。");
        return manager.DownloadUpdatesAsync(available, progress.Report, cancellationToken);
    }

    public void ApplyAfterExit(ManagerAppRelease release, bool restart)
    {
        var asset = manager.UpdatePendingRestart;
        if (asset is null || asset.Version.ToString() != release.Version)
            throw new InvalidOperationException("更新包尚未准备好。");
        manager.WaitExitThenApplyUpdates(asset, silent: false, restart: restart);
    }

#if SELF_UPDATE_PROBE
    internal void ApplyProbe(string fixture)
    { manager.WaitExitThenApplyUpdates(manager.UpdatePendingRestart, silent: true, restart: true, restartArgs: ["--self-update-probe-record", fixture]); }
#endif
    public void Dispose() => webSource?.Dispose();
}
