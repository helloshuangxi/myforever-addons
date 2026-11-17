using System.Net;
using System.Text;
using MyForeverManager.Core;
using MyForeverManager.Desktop;
using Velopack;
using Velopack.Logging;

int passed = 0, failed = 0;
void Assert(bool condition) { if (!condition) throw new Exception("Assertion failed"); }
async Task Test(string name, Func<Task> action)
{
    try { await action(); passed++; Console.WriteLine("PASS " + name); }
    catch (Exception ex) { failed++; Console.WriteLine("FAIL " + name + " " + ex); }
}
async Task Reject(Func<Task> action)
{ try { await action(); } catch { return; } throw new Exception("Expected rejection"); }

await Test("automatic disabled never contacts feed", async () =>
{
    var b = new Backend(); var u = new ManagerAppUpdates(b);
    await u.CheckAndDownloadAsync(true, false);
    Assert(b.Checks == 0 && b.Downloads == 0);
});
await Test("manual check works with automatic disabled but cannot auto apply", async () =>
{
    var b = new Backend(); var u = new ManagerAppUpdates(b);
    await u.CheckAndDownloadAsync(false, false);
    Assert(u.IsReady && !u.ApplyAfterExit(false, false, false) && b.Applies == 0);
    Assert(u.ApplyAfterExit(false, true, false) && b.Applies == 1 && b.Restart);
});
await Test("uninstalled zip build cannot replace itself", async () =>
{
    var b = new Backend { IsInstalled = false }; var u = new ManagerAppUpdates(b);
    await u.CheckAndDownloadAsync(false, true);
    Assert(u.Phase == ManagerAppUpdatePhase.Unavailable && b.Checks == 0);
});
await Test("current version does not schedule replacement", async () =>
{
    var b = new Backend { Release = null }; var u = new ManagerAppUpdates(b);
    await u.CheckAndDownloadAsync(true, true);
    Assert(u.Phase == ManagerAppUpdatePhase.Current && u.LastCheckedAt is not null && !u.IsReady && b.Downloads == 0);
    Assert(!u.ApplyAfterExit(true, false, false));
});
await Test("ready only after completed download; addon transaction blocks replacement", async () =>
{
    var finish = new TaskCompletionSource();
    var b = new Backend { Download = async token => await finish.Task.WaitAsync(token) };
    var u = new ManagerAppUpdates(b); var task = u.CheckAndDownloadAsync(true, true);
    Assert(u.IsWorking && !u.IsReady && !u.ApplyAfterExit(true, true, false));
    finish.SetResult(); await task;
    Assert(u.IsReady && !u.ApplyAfterExit(true, true, true) && b.Applies == 0);
    Assert(u.ApplyAfterExit(true, false, false) && !b.Restart && b.Applies == 1);
    Assert(u.ApplyAfterExit(true, true, false) && b.Applies == 1);
});
await Test("concurrent checks are single flight", async () =>
{
    var finish = new TaskCompletionSource();
    var b = new Backend { Download = async token => await finish.Task.WaitAsync(token) };
    var u = new ManagerAppUpdates(b); var first = u.CheckAndDownloadAsync(true, true);
    await u.CheckAndDownloadAsync(false, true); Assert(b.Checks == 1 && b.Downloads == 1);
    finish.SetResult(); await first;
});
await Test("cancelled download cannot schedule and can retry", async () =>
{
    var b = new Backend { Download = token => Task.Delay(Timeout.Infinite, token) };
    var u = new ManagerAppUpdates(b); using var cancel = new CancellationTokenSource();
    var task = u.CheckAndDownloadAsync(true, true, cancel.Token); cancel.Cancel(); await task;
    Assert(!u.IsReady && !u.ApplyAfterExit(true, false, false));
    b.Download = _ => Task.CompletedTask; await u.CheckAndDownloadAsync(false, true); Assert(u.IsReady);
});
await Test("network or corrupt package failure leaves old app usable and retryable", async () =>
{
    var b = new Backend { Download = _ => throw new InvalidDataException("bad digest") };
    var u = new ManagerAppUpdates(b); await u.CheckAndDownloadAsync(true, true);
    Assert(u.Phase == ManagerAppUpdatePhase.Failed && !u.IsReady && b.Applies == 0);
    b.Download = _ => Task.CompletedTask; await u.CheckAndDownloadAsync(false, true); Assert(u.IsReady);
});
await Test("cached pending release survives restart without network", async () =>
{
    var b = new Backend { PendingRelease = new("0.5.1") }; var u = new ManagerAppUpdates(b);
    Assert(u.IsReady); await u.CheckAndDownloadAsync(true, true);
    Assert(b.Checks == 0 && b.Downloads == 0 && u.ApplyAfterExit(true, false, false));
});
await Test("helper start failure can retry without losing ready package", async () =>
{
    var b = new Backend { ApplyFailure = true }; var u = new ManagerAppUpdates(b);
    await u.CheckAndDownloadAsync(true, true);
    Assert(!u.ApplyAfterExit(true, true, false) && u.IsReady);
    b.ApplyFailure = false; Assert(u.ApplyAfterExit(true, true, false));
});
await Test("old settings migrate with independent default and preserve user choices", () =>
{
    var path = Path.Combine(Path.GetTempPath(), "manager-settings-test-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(path);
    try
    {
        File.WriteAllText(Path.Combine(path, "settings.json"), "{\"GameDirectory\":\"/fixture/game\",\"AutoUpdate\":false,\"ManagedAddons\":[\"MyForeverChat\"]}");
        File.WriteAllText(Path.Combine(path, "behavior-ai-settings.json"), "sentinel-ai");
        var store = new SettingsStore(path); var settings = store.Load();
        Assert(settings.AutoUpdateManager && !settings.AutoUpdate && settings.ManagedAddons.Single() == "MyForeverChat");
        settings.AutoUpdateManager = false; store.Save(settings); var restored = store.Load();
        Assert(!restored.AutoUpdateManager && restored.GameDirectory == "/fixture/game" && !restored.AutoUpdate);
        Assert(File.ReadAllText(Path.Combine(path, "behavior-ai-settings.json")) == "sentinel-ai");
    }
    finally { Directory.Delete(path, true); }
    return Task.CompletedTask;
});

foreach (var rid in new[] { "osx-arm64", "osx-x64", "win-x64" })
await Test("feed pins platform and sends no user identifier: " + rid, async () =>
{
    var handler = new Handler(_ => new(HttpStatusCode.OK) { Content = new StringContent("{\"Assets\":[]}") });
    using var source = new ManagerUpdateSource(rid, handler);
    var feed = await source.GetReleaseFeed(new NullVelopackLogger(), "MyForeverManager", rid, Guid.NewGuid());
    Assert(feed.Assets.Length == 0 && handler.Uri?.AbsoluteUri == $"https://afabiaoge.xyz/manager/updates/{rid}/releases.{rid}.json");
    await Reject(() => source.GetReleaseFeed(new NullVelopackLogger(), null, "wrong-channel"));
});
await Test("redirects and moved final URLs rejected", async () =>
{
    foreach (var response in new[] {
        new HttpResponseMessage(HttpStatusCode.Redirect),
        new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"Assets\":[]}"), RequestMessage = new(HttpMethod.Get, "https://other.example/feed") } })
    {
        using var source = new ManagerUpdateSource("osx-arm64", new Handler(_ => response));
        await Reject(() => source.GetReleaseFeed(new NullVelopackLogger(), null, "osx-arm64"));
    }
});
await Test("valid app feed and complete package use the same pinned directory", async () =>
{
    var handler = new Handler(request => new(HttpStatusCode.OK)
    {
        Content = request.RequestUri!.AbsolutePath.EndsWith(".json")
            ? new StringContent("{\"Assets\":[{\"PackageId\":\"MyForeverManagerApp\",\"Version\":\"0.5.1\",\"Type\":\"Full\",\"FileName\":\"MyForeverManagerApp-0.5.1-win-x64-full.nupkg\",\"Size\":3}]}")
            : new ByteArrayContent([1,2,3])
    });
    using var source = new ManagerUpdateSource("win-x64", handler);
    var feed = await source.GetReleaseFeed(new NullVelopackLogger(), null, "win-x64");
    var path = Path.GetTempFileName();
    try
    {
        await source.DownloadReleaseEntry(new NullVelopackLogger(), feed.Assets.Single(), path, _ => {}, CancellationToken.None);
        Assert(File.ReadAllBytes(path).SequenceEqual(new byte[] { 1,2,3 }));
        Assert(handler.Uri!.AbsoluteUri == "https://afabiaoge.xyz/manager/updates/win-x64/MyForeverManagerApp-0.5.1-win-x64-full.nupkg");
    }
    finally { File.Delete(path); }
});
await Test("foreign app, URL, traversal, excessive size rejected before download", async () =>
{
    foreach (var (id, name, size) in new[] { ("ForeignApp", "MyForeverManagerApp-full.nupkg", 20L),
        ("MyForeverManagerApp", "https://evil.test/a.nupkg", 20L), ("MyForeverManagerApp", "../a.nupkg", 20L),
        ("MyForeverManagerApp", "MyForeverManagerApp-full.nupkg", 600L * 1024 * 1024) })
    {
        var json = $$"""{"Assets":[{"PackageId":"{{id}}","Version":"0.5.1","Type":"Full","FileName":"{{name}}","Size":{{size}}}]}""";
        using var source = new ManagerUpdateSource("win-x64", new Handler(_ => new(HttpStatusCode.OK) { Content = new StringContent(json) }));
        await Reject(() => source.GetReleaseFeed(new NullVelopackLogger(), null, "win-x64"));
    }
});
await Test("truncated package deleted instead of becoming ready", async () =>
{
    var path = Path.GetTempFileName();
    try
    {
        using var source = new ManagerUpdateSource("win-x64", new Handler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent([1,2,3]) }));
        var asset = VelopackAssetFeed.FromJson("{\"Assets\":[{\"PackageId\":\"MyForeverManagerApp\",\"Version\":\"0.5.1\",\"Type\":\"Full\",\"FileName\":\"MyForeverManagerApp-full.nupkg\",\"Size\":4}]}").Assets.Single();
        await Reject(() => source.DownloadReleaseEntry(new NullVelopackLogger(), asset, path, _ => {}, CancellationToken.None));
        Assert(!File.Exists(path));
    }
    finally { File.Delete(path); }
});
Console.WriteLine($"Self-update: {passed} passed, {failed} failed");
return failed == 0 ? 0 : 1;

sealed class Backend : IManagerAppUpdateBackend
{
    public bool IsInstalled { get; set; } = true;
    public ManagerAppRelease? PendingRelease { get; set; }
    public ManagerAppRelease? Release { get; set; } = new("0.5.1");
    public Func<CancellationToken, Task> Download { get; set; } = _ => Task.CompletedTask;
    public int Checks, Downloads, Applies;
    public bool Restart, ApplyFailure;
    public Task<ManagerAppRelease?> CheckAsync(CancellationToken token) { Checks++; return Task.FromResult(Release); }
    public async Task DownloadAsync(ManagerAppRelease release, IProgress<int> progress, CancellationToken token)
    { Downloads++; progress.Report(50); await Download(token); progress.Report(100); }
    public void ApplyAfterExit(ManagerAppRelease release, bool restart)
    { if (ApplyFailure) throw new IOException("busy"); Applies++; Restart = restart; }
}
sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
{
    public Uri? Uri;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    { Uri = request.RequestUri; var response = respond(request); response.RequestMessage ??= request; return Task.FromResult(response); }
}
