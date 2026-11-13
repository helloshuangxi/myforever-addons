using MyForeverManager.Core;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

var siteArg = Array.IndexOf(args, "--site-root");
var site = Path.GetFullPath(siteArg >= 0 ? args[siteArg + 1] : "../website/public");
var tempBase = OperatingSystem.IsMacOS() ? "/private/tmp" : Path.GetTempPath();
var suiteDirectory = Path.Combine(tempBase, "myforever-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(suiteDirectory);
int passed = 0, failed = 0;
var addon = AddonCatalog.All[0];
var originalRelease = JsonSerializer.Deserialize<ReleaseManifest>(File.ReadAllText(Path.Combine(site, "latest.json")))!;
var originalBytes = File.ReadAllBytes(Path.Combine(site, "downloads", originalRelease.Download.Filename));
var professionRelease = JsonSerializer.Deserialize<ReleaseManifest>(File.ReadAllText(Path.Combine(site, "professions", "latest.json")))!;
var professionBytes = File.ReadAllBytes(Path.Combine(site, "downloads", professionRelease.Download.Filename));
var navigator = AddonCatalog.All.Single(x => x.Id == "MyForeverNavigator");
var navigatorArg = Array.IndexOf(args, "--navigator-zip");
var navigatorPath = navigatorArg >= 0 ? Path.GetFullPath(args[navigatorArg + 1]) : null;
byte[]? navigatorBytes = navigatorPath is null ? null : File.ReadAllBytes(navigatorPath);
ReleaseManifest? navigatorRelease = null;
if (navigatorBytes is not null)
{
    using var archive = new ZipArchive(new MemoryStream(navigatorBytes));
    using var toc = new StreamReader(archive.GetEntry("MyForeverNavigator/MyForeverNavigator.toc")!.Open());
    var version = Regex.Match(toc.ReadToEnd(), @"^## Version:\s*([\d.]+)\s*$", RegexOptions.Multiline).Groups[1].Value;
    var filename = Path.GetFileName(navigatorPath)!;
    navigatorRelease = new ReleaseManifest
    {
        SchemaVersion = 1, Name = navigator.Id, Version = version, Channel = "trial", PublishedAt = "2026-11-08",
        Compatibility = new() { Product = "国服魔兽世界：无限", Client = "1.60.1", Interface = 16001 },
        Download = new() { Filename = filename, Url = "https://afabiaoge.xyz/downloads/" + filename,
            SizeBytes = navigatorBytes.Length, Sha256 = Convert.ToHexString(SHA256.HashData(navigatorBytes)).ToLowerInvariant() }
    };
}

var targets = AddonCatalog.All.Single(x => x.Id == "MyForeverTargets");
var targetsArg = Array.IndexOf(args, "--targets-zip");
var targetsPath = targetsArg >= 0 ? Path.GetFullPath(args[targetsArg + 1]) : null;
byte[]? targetsBytes = targetsPath is null ? null : File.ReadAllBytes(targetsPath);
ReleaseManifest? targetsRelease = null;
if (targetsBytes is not null)
{
    using var archive = new ZipArchive(new MemoryStream(targetsBytes));
    using var toc = new StreamReader(archive.GetEntry("MyForeverTargets/MyForeverTargets.toc")!.Open());
    var version = Regex.Match(toc.ReadToEnd(), @"^## Version:\s*([\d.]+)\s*$", RegexOptions.Multiline).Groups[1].Value;
    var filename = Path.GetFileName(targetsPath)!;
    targetsRelease = new ReleaseManifest
    {
        SchemaVersion = 1, Name = targets.Id, Version = version, Channel = "trial", PublishedAt = "2026-11-11",
        Compatibility = new() { Product = "国服魔兽世界：无限", Client = "1.60.1", Interface = 16001 },
        Download = new() { Filename = filename, Url = "https://afabiaoge.xyz/downloads/" + filename,
            SizeBytes = targetsBytes.Length, Sha256 = Convert.ToHexString(SHA256.HashData(targetsBytes)).ToLowerInvariant() }
    };
}

async Task Test(string title, Func<Task> run)
{
    try { await run(); passed++; Console.WriteLine("PASS " + title); }
    catch (Exception e) { failed++; Console.WriteLine("FAIL " + title + "\n" + e); }
}
void Assert(bool value, string message = "Assertion failed") { if (!value) throw new Exception(message); }
async Task Fails(Func<Task> run, string? contains = null)
{
    try { await run(); }
    catch (Exception e) { if (contains is not null) Assert(e.Message.Contains(contains), "Unexpected error: " + e.Message); return; }
    throw new Exception("Expected operation to be rejected");
}
string Game()
{
    var game = Path.Combine(suiteDirectory, Guid.NewGuid().ToString("N"), "_forever_");
    Directory.CreateDirectory(game);
    File.WriteAllText(Path.Combine(game, "Wow.exe"), "fixture executable marker; never run");
    return game;
}
void InstallOld(string game, string version = "0.0.1", AddonDefinition? a = null)
{
    a ??= addon;
    var target = Path.Combine(GamePaths.AddonsDirectory(game), a.Id);
    Directory.CreateDirectory(target);
    File.WriteAllText(Path.Combine(target, a.Id + ".toc"), $"## Interface: 16001\n## Version: {version}\nold.lua\n");
    File.WriteAllText(Path.Combine(target, "old.lua"), "old source remains byte-for-byte");
}
ReleaseManifest Clone(ReleaseManifest? input = null) => JsonSerializer.Deserialize<ReleaseManifest>(JsonSerializer.Serialize(input ?? originalRelease))!;
byte[] Zip(params (string Name, string Content, int? Attributes)[] entries)
{
    using var output = new MemoryStream();
    using (var zip = new ZipArchive(output, ZipArchiveMode.Create, true))
        foreach (var (name, content, attrs) in entries)
        {
            var entry = zip.CreateEntry(name);
            if (attrs is not null) entry.ExternalAttributes = attrs.Value;
            using var stream = new StreamWriter(entry.Open(), Encoding.UTF8);
            stream.Write(content);
        }
    return output.ToArray();
}
ReleaseManifest WithBytes(byte[] bytes)
{
    var release = Clone();
    release.Download.SizeBytes = bytes.Length;
    release.Download.Sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    return release;
}
HttpClient Client(ReleaseManifest release, byte[] package, Action<HttpRequestMessage>? onRequest = null)
{
    return new HttpClient(new Handler(req =>
    {
        onRequest?.Invoke(req);
        var content = req.RequestUri!.AbsolutePath.EndsWith(".json") ? JsonSerializer.SerializeToUtf8Bytes(release) : package;
        return new HttpResponseMessage(HttpStatusCode.OK) { RequestMessage = req, Content = new ByteArrayContent(content) };
    }));
}
UpdateService Service(ReleaseManifest? r = null, byte[]? bytes = null, Func<bool>? running = null) => new(client: Client(r ?? originalRelease, bytes ?? originalBytes), isGameRunning: running ?? (() => false));
string Pending(string game) => Path.Combine(game, "Interface", ".MyForeverManager", addon.Id, "pending");
string BackupId() => "20261107T1234561234567Z-" + Guid.NewGuid().ToString("N");
void Journal(string game, bool hadOriginal, bool committed = false)
{
    Directory.CreateDirectory(Pending(game));
    File.WriteAllText(Path.Combine(Pending(game), "journal.json"), JsonSerializer.Serialize(new { HadOriginal = hadOriginal, Committed = committed, BackupId = BackupId() }));
}
try
{
    await Test("four independently managed official addons include Targets", () =>
    {
        Assert(AddonCatalog.All.Count == 4 && AddonCatalog.All.Select(x => x.Id).Distinct().Count() == 4);
        Assert(navigator.ManifestUrl == "https://afabiaoge.xyz/navigator/latest.json");
        Assert(targets.ManifestUrl == "https://afabiaoge.xyz/targets/latest.json");
        return Task.CompletedTask;
    });
    await Test("old manager settings preserve selected addons without enrolling Navigator", () =>
    {
        var store = new SettingsStore(Path.Combine(suiteDirectory, "migration-settings"));
        store.Save(new ManagerSettings { GameDirectory = "fixture", AutoUpdate = true,
            ManagedAddons = ["MyForeverChat", "MyForeverProfessions"] });
        var loaded = store.Load();
        Assert(loaded.AutoUpdate && loaded.ManagedAddons.SequenceEqual(new[] { "MyForeverChat", "MyForeverProfessions" }));
        Assert(!loaded.ManagedAddons.Contains(navigator.Id));
        return Task.CompletedTask;
    });
    await Test("0.2.0 settings retain selected plugins without automatically enrolling Targets", () =>
    {
        var store = new SettingsStore(Path.Combine(suiteDirectory, "targets-migration-settings"));
        var selected = new[] { "MyForeverChat", "MyForeverProfessions", "MyForeverNavigator" };
        store.Save(new ManagerSettings { GameDirectory = "fixture", AutoUpdate = true, ManagedAddons = selected.ToList() });
        var loaded = store.Load();
        Assert(loaded.AutoUpdate && loaded.ManagedAddons.SequenceEqual(selected));
        Assert(!loaded.ManagedAddons.Contains(targets.Id));
        loaded.ManagedAddons.Add(targets.Id); store.Save(loaded);
        Assert(store.Load().ManagedAddons.Contains(targets.Id));
        return Task.CompletedTask;
    });
    if (targetsRelease is not null && targetsBytes is not null)
    {
        await Test("real Targets archive installs from its independent endpoint into isolated fixture", async () =>
        {
            var game = Game(); var requests = new List<string>();
            using var client = Client(targetsRelease, targetsBytes, req => requests.Add(req.RequestUri!.AbsoluteUri));
            using var service = new UpdateService(client: client, isGameRunning: () => false);
            var status = await service.CheckAsync(targets, game);
            Assert(status.CanInstall && status.Error is null && status.InstalledVersion is null);
            await service.InstallAsync(targets, status.Latest!, game);
            Assert(UpdateService.ReadInstalledVersion(targets, game) == targetsRelease.Version);
            Assert(File.Exists(Path.Combine(GamePaths.AddonsDirectory(game), targets.Id, "Core.lua")));
            Assert(requests[0] == targets.ManifestUrl && requests.Contains(targetsRelease.Download.Url));
            Assert(!service.HasBackup(targets, game));
        });
        await Test("Targets update and restore preserve every other official addon and WTF", async () =>
        {
            var game = Game(); InstallOld(game, a: targets);
            foreach (var other in AddonCatalog.All.Where(a => a != targets)) InstallOld(game, "88.0.0", other);
            var wtf = Path.Combine(game, "WTF", "Account", "fixture", "SavedVariables");
            Directory.CreateDirectory(wtf);
            var saved = Path.Combine(wtf, "MyForeverTargets.lua");
            File.WriteAllText(saved, "private fixture panel positions must remain byte-for-byte");
            using var service = Service(targetsRelease, targetsBytes);
            await service.InstallAsync(targets, targetsRelease, game);
            Assert(UpdateService.ReadInstalledVersion(targets, game) == targetsRelease.Version && service.HasBackup(targets, game));
            foreach (var other in AddonCatalog.All.Where(a => a != targets))
            {
                Assert(UpdateService.ReadInstalledVersion(other, game) == "88.0.0");
                Assert(!service.HasBackup(other, game));
            }
            await service.RestoreAsync(targets, game);
            Assert(UpdateService.ReadInstalledVersion(targets, game) == "0.0.1");
            Assert(File.ReadAllText(saved) == "private fixture panel positions must remain byte-for-byte");
            foreach (var other in AddonCatalog.All.Where(a => a != targets))
            {
                Assert(UpdateService.ReadInstalledVersion(other, game) == "88.0.0");
                Assert(File.ReadAllText(Path.Combine(GamePaths.AddonsDirectory(game), other.Id, "old.lua")) == "old source remains byte-for-byte");
            }
        });
        await Test("Targets install and restore both wait while game is running", async () =>
        {
            var game = Game(); InstallOld(game, a: targets);
            using (var service = Service(targetsRelease, targetsBytes)) await service.InstallAsync(targets, targetsRelease, game);
            using var blocked = Service(targetsRelease, targetsBytes, () => true);
            await Fails(() => blocked.RestoreAsync(targets, game), "游戏正在运行");
            Assert(UpdateService.ReadInstalledVersion(targets, game) == targetsRelease.Version);
            var fresh = Game();
            await Fails(() => blocked.InstallAsync(targets, targetsRelease, fresh), "游戏正在运行");
            Assert(!Directory.Exists(Path.Combine(fresh, "Interface")));
        });
    }
    if (navigatorRelease is not null && navigatorBytes is not null)
    {
        await Test("real Navigator archive installs from approved manifest into isolated fixture", async () =>
        {
            var game = Game(); using var service = Service(navigatorRelease, navigatorBytes);
            var status = await service.CheckAsync(navigator, game);
            Assert(status.CanInstall && status.Error is null && status.InstalledVersion is null);
            await service.InstallAsync(navigator, status.Latest!, game);
            Assert(UpdateService.ReadInstalledVersion(navigator, game) == navigatorRelease.Version);
            Assert(File.Exists(Path.Combine(GamePaths.AddonsDirectory(game), navigator.Id, "Data.lua")));
            Assert(!service.HasBackup(navigator, game));
        });
        await Test("real Navigator update and restore preserve private location data and other addons", async () =>
        {
            var game = Game(); InstallOld(game, a: navigator);
            var wtf = Path.Combine(game, "WTF", "Account", "fixture", "SavedVariables");
            Directory.CreateDirectory(wtf);
            var saved = Path.Combine(wtf, "MyForeverNavigator.lua");
            File.WriteAllText(saved, "private fixture favorites and custom locations must remain byte-for-byte");
            var chat = Path.Combine(GamePaths.AddonsDirectory(game), "MyForeverChat");
            Directory.CreateDirectory(chat); File.WriteAllText(Path.Combine(chat, "untouched.lua"), "unchanged fixture");
            using var service = Service(navigatorRelease, navigatorBytes);
            await service.InstallAsync(navigator, navigatorRelease, game);
            Assert(UpdateService.ReadInstalledVersion(navigator, game) == navigatorRelease.Version);
            Assert(service.HasBackup(navigator, game));
            await service.RestoreAsync(navigator, game);
            Assert(UpdateService.ReadInstalledVersion(navigator, game) == "0.0.1");
            Assert(File.ReadAllText(saved) == "private fixture favorites and custom locations must remain byte-for-byte");
            Assert(File.ReadAllText(Path.Combine(chat, "untouched.lua")) == "unchanged fixture");
        });
        await Test("Navigator install waits while game is running", async () =>
        {
            var game = Game(); using var service = Service(navigatorRelease, navigatorBytes, () => true);
            await Fails(() => service.InstallAsync(navigator, navigatorRelease, game));
            Assert(!Directory.Exists(Path.Combine(GamePaths.AddonsDirectory(game), navigator.Id)));
        });
    }
    await Test("numeric versions compare 0.10.0 above 0.9.9", () => { Assert(Versions.Compare("0.10.0", "0.9.9") > 0); Assert(Versions.Compare("1.0.0", "1.0.0.0") == 0); return Task.CompletedTask; });
    foreach (var version in new[] { "v1.2.3", "1.2", "1.2.3-evil", "1.2.3/../4", "999999999.0.0" })
        await Test("reject ambiguous version " + version, () => Fails(() => { Versions.Parse(version); return Task.CompletedTask; }));
    await Test("resolve root, client, Interface and AddOns without writes", () =>
    {
        var game = Game();
        Assert(GamePaths.Resolve(Directory.GetParent(game)!.FullName) == game);
        Assert(GamePaths.Resolve(game) == game);
        Assert(!Directory.Exists(Path.Combine(game, "Interface")));
        Directory.CreateDirectory(GamePaths.AddonsDirectory(game));
        Assert(GamePaths.Resolve(Path.Combine(game, "Interface")) == game);
        Assert(GamePaths.Resolve(GamePaths.AddonsDirectory(game)) == game);
        return Task.CompletedTask;
    });
    if (OperatingSystem.IsMacOS())
        await Test("known macOS temp alias resolves without permitting arbitrary links", () =>
        { var game = Game(); Assert(GamePaths.Resolve(game.Replace("/private/tmp/", "/tmp/")) == game); return Task.CompletedTask; });
    await Test("macOS client bundle recognized", () =>
    {
        var game = Game(); File.Delete(Path.Combine(game, "Wow.exe")); Directory.CreateDirectory(Path.Combine(game, "World of Warcraft.app"));
        Assert(GamePaths.Resolve(game) == game); return Task.CompletedTask;
    });
    await Test("reject incomplete game installation", () =>
    { var game = Game(); File.Delete(Path.Combine(game, "Wow.exe")); return Fails(() => { GamePaths.Resolve(game); return Task.CompletedTask; }); });
    await Test("reject retail target", () =>
    { var game = Game(); var retail = Path.Combine(Directory.GetParent(game)!.FullName, "_retail_"); Directory.CreateDirectory(retail); File.WriteAllText(Path.Combine(retail, "Wow.exe"), ""); return Fails(() => { GamePaths.Resolve(retail); return Task.CompletedTask; }); });
    await Test("settings persist selection and ignore unknown add-ons", () =>
    {
        var store = new SettingsStore(Path.Combine(suiteDirectory, "settings"));
        store.Save(new ManagerSettings { GameDirectory = "D:\\Games\\魔兽", AutoUpdate = false, ManagedAddons = [addon.Id, "OtherAddon", addon.Id] });
        var loaded = store.Load(); Assert(loaded.GameDirectory == "D:\\Games\\魔兽" && !loaded.AutoUpdate && loaded.ManagedAddons.SequenceEqual(new[] { addon.Id })); return Task.CompletedTask;
    });
    await Test("real chat archive install, backup and restore preserves WTF and other add-ons", async () =>
    {
        var game = Game(); InstallOld(game);
        var wtf = Path.Combine(game, "WTF", "Account", "fixture"); Directory.CreateDirectory(wtf); File.WriteAllText(Path.Combine(wtf, "settings.lua"), "preserved private fixture");
        var other = Path.Combine(GamePaths.AddonsDirectory(game), "OtherAddon"); Directory.CreateDirectory(other); File.WriteAllText(Path.Combine(other, "untouched.lua"), "unchanged");
        using var service = Service();
        var status = await service.CheckAsync(addon, game); Assert(status.Error is null && status.CanInstall && status.InstalledVersion == "0.0.1");
        await service.InstallAsync(addon, status.Latest!, game);
        Assert(UpdateService.ReadInstalledVersion(addon, game) == originalRelease.Version && service.HasBackup(addon, game));
        Assert(!File.Exists(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id, "old.lua")));
        Assert(!File.Exists(Path.Combine(GamePaths.AddonsDirectory(game), "安装使用说明.txt")));
        Assert(File.ReadAllText(Path.Combine(wtf, "settings.lua")) == "preserved private fixture");
        Assert(File.ReadAllText(Path.Combine(other, "untouched.lua")) == "unchanged");
        await service.RestoreAsync(addon, game);
        Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
        Assert(File.ReadAllText(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id, "old.lua")) == "old source remains byte-for-byte");
    });
    await Test("real professions archive fresh installation", async () =>
    {
        var game = Game(); using var service = Service(professionRelease, professionBytes);
        await service.InstallAsync(AddonCatalog.All[1], professionRelease, game);
        Assert(UpdateService.ReadInstalledVersion(AddonCatalog.All[1], game) == professionRelease.Version);
        Assert(!service.HasBackup(AddonCatalog.All[1], game));
    });
    await Test("same or newer installed versions are never downgraded", async () =>
    {
        foreach (var version in new[] { originalRelease.Version, "99.0.0" })
        {
            var game = Game(); InstallOld(game, version); using var service = Service();
            Assert(!(await service.CheckAsync(addon, game)).CanInstall);
            await Fails(() => service.InstallAsync(addon, originalRelease, game));
            Assert(UpdateService.ReadInstalledVersion(addon, game) == version);
        }
    });
    await Test("bad download hash leaves existing addon intact", async () =>
    {
        var game = Game(); InstallOld(game); var release = Clone(); release.Download.Sha256 = new string('0', 64);
        using var service = Service(release); await Fails(() => service.InstallAsync(addon, release, game), "SHA-256");
        Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
    });
    await Test("oversized response rejected without replacing addon", async () =>
    {
        var game = Game(); InstallOld(game); var release = Clone(); release.Download.SizeBytes = 3;
        using var service = Service(release); await Fails(() => service.InstallAsync(addon, release, game), "大小"); Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
    });
    await Test("game running blocks all installation writes and download", async () =>
    {
        var game = Game(); int requests = 0; using var client = Client(originalRelease, originalBytes, _ => requests++);
        using var service = new UpdateService(client: client, isGameRunning: () => true);
        await Fails(() => service.InstallAsync(addon, originalRelease, game), "游戏正在运行");
        Assert(requests == 0 && !Directory.Exists(Path.Combine(game, "Interface")));
    });
    await Test("game starting after download defers swap", async () =>
    {
        var game = Game(); InstallOld(game); bool running = false;
        using var client = Client(originalRelease, originalBytes, _ => running = true);
        using var service = new UpdateService(client: client, isGameRunning: () => running);
        await Fails(() => service.InstallAsync(addon, originalRelease, game), "游戏正在运行");
        Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
    });
    await Test("cancellation leaves installed addon intact", async () =>
    { var game = Game(); InstallOld(game); using var service = Service(); using var cancelled = new CancellationTokenSource(); cancelled.Cancel(); await Fails(() => service.InstallAsync(addon, originalRelease, game, ct: cancelled.Token)); Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1"); });
    foreach (var (title, mutate) in new (string, Action<ReleaseManifest>)[]
    {
        ("wrong addon identity", r => r.Name = "OtherAddon"),
        ("HTTP URL", r => r.Download.Url = r.Download.Url.Replace("https:", "http:")),
        ("foreign host", r => r.Download.Url = r.Download.Url.Replace("afabiaoge.xyz", "example.com")),
        ("unknown schema", r => r.SchemaVersion = 5),
        ("unsupported client", r => r.Compatibility.Interface = 99999),
        ("missing checksum", r => r.Download.Sha256 = ""),
        ("oversized declared archive", r => r.Download.SizeBytes = UpdateService.MaximumArchiveBytes + 1),
        ("unknown release channel", r => r.Channel = "unreviewed")
    }) await Test("reject manifest " + title, async () => { var r = Clone(); mutate(r); using var s = Service(r); var status = await s.CheckAsync(addon, Game()); Assert(status.Error is not null && !status.CanInstall); });

    var validToc = $"## Interface: 16001\n## Version: {originalRelease.Version}\n";
    var invalidEntries = new (string Title, (string Name, string Content, int? Attributes)[] Entries)[]
    {
        ("parent traversal", [(addon.Id + "/../../escape.lua", "x", null)]),
        ("backslash traversal", [(addon.Id + "\\..\\escape.lua", "x", null)]),
        ("absolute path", [("/tmp/escape.lua", "x", null)]),
        ("Windows drive", [("C:/escape.lua", "x", null)]),
        ("alternate data stream", [(addon.Id + "/a.lua:evil", "x", null)]),
        ("device filename", [(addon.Id + "/CON.lua", "x", null)]),
        ("trailing dot", [(addon.Id + "/evil.", "x", null)]),
        ("trailing space", [(addon.Id + "/evil ", "x", null)]),
        ("privacy directory", [(addon.Id + "/SavedVariables/private.lua", "x", null)]),
        ("WTF directory", [(addon.Id + "/WTF/private.lua", "x", null)]),
        ("symbolic link", [(addon.Id + "/link", "/tmp", 0xA1FF << 16)]),
        ("another addon", [("OtherAddon/Core.lua", "x", null)]),
        ("unknown top level", [("surprise.exe", "x", null)]),
        ("case duplicate", [(addon.Id + "/A.lua", "x", null), (addon.Id + "/a.lua", "y", null)]),
        ("implicit directory case collision", [(addon.Id + "/Media/a.lua", "x", null), (addon.Id + "/media/b.lua", "y", null)]),
        ("file directory collision", [(addon.Id + "/Media", "x", null), (addon.Id + "/Media/a.lua", "y", null)]),
        ("TOC mismatch", [(addon.Id + "/" + addon.Id + ".toc", "## Interface: 16001\n## Version: 8.8.8\n", null)])
    };
    foreach (var (title, entries) in invalidEntries)
        await Test("reject ZIP " + title + " and preserve old addon", async () =>
        {
            var game = Game(); InstallOld(game);
            var additions = entries.Any(x => x.Name == addon.Id + "/" + addon.Id + ".toc") ? entries : entries.Append((addon.Id + "/" + addon.Id + ".toc", validToc, (int?)null)).ToArray();
            var bytes = Zip(additions); var r = WithBytes(bytes); using var service = Service(r, bytes);
            await Fails(() => service.InstallAsync(addon, r, game)); Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
            Assert(!Directory.Exists(Pending(game)));
        });
    await Test("HTTP redirects rejected", async () =>
    {
        using var client = new HttpClient(new Handler(req => new HttpResponseMessage(HttpStatusCode.Redirect) { RequestMessage = req, Headers = { Location = new Uri("https://example.com/") } }));
        using var service = new UpdateService(client: client, isGameRunning: () => false);
        Assert((await service.CheckAsync(addon, Game())).Error!.Contains("重定向"));
    });
    await Test("unexpected followed redirects rejected", async () =>
    {
        using var client = new HttpClient(new Handler(_ => new HttpResponseMessage(HttpStatusCode.OK) { RequestMessage = new(HttpMethod.Get, "https://example.com/"), Content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(originalRelease)) }));
        using var service = new UpdateService(client: client, isGameRunning: () => false);
        Assert((await service.CheckAsync(addon, Game())).Error!.Contains("地址"));
    });
    await Test("real swap rolls back when committed journal cannot be written", async () =>
    {
        var game = Game(); InstallOld(game); using var service = Service();
        var progress = new ImmediateProgress(message =>
        {
            if (message.StartsWith("保存旧版", StringComparison.Ordinal))
                Directory.CreateDirectory(Path.Combine(Pending(game), "journal.tmp"));
        });
        await Fails(() => service.InstallAsync(addon, originalRelease, game, progress));
        Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
        Assert(File.ReadAllText(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id, "old.lua")) == "old source remains byte-for-byte");
        Assert(!Directory.Exists(Pending(game)));
        Assert(Directory.GetDirectories(Path.Combine(game, "Interface", ".MyForeverManager", addon.Id, "recovered")).Length == 1);
    });
    await Test("interrupted swap after moving original automatically rolls back", async () =>
    {
        var game = Game(); InstallOld(game); Journal(game, true);
        Directory.Move(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id), Path.Combine(Pending(game), "original"));
        using var service = Service(); var status = await service.CheckAsync(addon, game);
        Assert(status.Error is null && status.InstalledVersion == "0.0.1" && !Directory.Exists(Pending(game)));
    });
    await Test("interrupted swap after placing new files restores original and preserves candidate", async () =>
    {
        var game = Game(); InstallOld(game); Journal(game, true);
        Directory.Move(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id), Path.Combine(Pending(game), "original"));
        InstallOld(game, "0.0.2"); using var service = Service();
        Assert((await service.CheckAsync(addon, game)).InstalledVersion == "0.0.1");
        Assert(Directory.GetDirectories(Path.Combine(game, "Interface", ".MyForeverManager", addon.Id, "recovered")).Length == 1);
    });
    await Test("interrupted fresh install returns to uninstalled and preserves candidate", async () =>
    {
        var game = Game(); Journal(game, false); InstallOld(game, "0.0.2"); using var service = Service();
        var status = await service.CheckAsync(addon, game); Assert(status.Error is null && status.InstalledVersion is null);
        Assert(Directory.GetDirectories(Path.Combine(game, "Interface", ".MyForeverManager", addon.Id, "recovered")).Length == 1);
    });
    await Test("committed interrupted cleanup completes backup without reverting new files", async () =>
    {
        var game = Game(); InstallOld(game); Journal(game, true, true);
        Directory.Move(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id), Path.Combine(Pending(game), "original"));
        InstallOld(game, "0.0.2"); using var service = Service();
        var status = await service.CheckAsync(addon, game); Assert(status.Error is null && status.InstalledVersion == "0.0.2" && service.HasBackup(addon, game));
    });
    await Test("stale extraction with no journal cannot affect installed files", async () =>
    {
        var game = Game(); InstallOld(game); Directory.CreateDirectory(Path.Combine(Pending(game), "payload")); File.WriteAllText(Path.Combine(Pending(game), "payload", "unfinished"), "x");
        using var service = Service(); var status = await service.CheckAsync(addon, game); Assert(status.Error is null && status.InstalledVersion == "0.0.1" && !Directory.Exists(Pending(game)));
    });
    await Test("corrupt recovery journal fails closed and preserves files", async () =>
    {
        var game = Game(); InstallOld(game); Journal(game, true); File.WriteAllText(Path.Combine(Pending(game), "journal.json"), "{broken");
        using var service = Service(); var status = await service.CheckAsync(addon, game); Assert(status.Error is not null && Directory.Exists(Pending(game)) && UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
    });
    await Test("recovery deferred while game runs", async () =>
    {
        var game = Game(); InstallOld(game); Journal(game, true); using var service = Service(running: () => true);
        var status = await service.CheckAsync(addon, game); Assert(status.Error is not null && Directory.Exists(Pending(game)));
    });
    await Test("file lock prevents simultaneous installation", async () =>
    {
        var game = Game(); InstallOld(game); var root = Path.Combine(game, "Interface", ".MyForeverManager"); Directory.CreateDirectory(root);
        using var gate = new FileStream(Path.Combine(root, "update.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        using var service = Service(); await Fails(() => service.InstallAsync(addon, originalRelease, game), "另一个管理器");
        Assert(UpdateService.ReadInstalledVersion(addon, game) == "0.0.1");
    });
    if (!OperatingSystem.IsWindows())
    {
        await Test("symlinked addon directory rejected without following link", async () =>
        {
            var game = Game(); Directory.CreateDirectory(GamePaths.AddonsDirectory(game)); var external = Path.Combine(suiteDirectory, "external"); Directory.CreateDirectory(external); File.WriteAllText(Path.Combine(external, "private.txt"), "keep");
            Directory.CreateSymbolicLink(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id), external);
            using var service = Service(); await Fails(() => service.InstallAsync(addon, originalRelease, game), "符号链接"); Assert(File.ReadAllText(Path.Combine(external, "private.txt")) == "keep");
        });
        await Test("symlinked transaction directory cannot create files outside game", async () =>
        {
            var game = Game(); InstallOld(game); var state = Path.Combine(game, "Interface", ".MyForeverManager"); Directory.CreateDirectory(state);
            var external = Path.Combine(suiteDirectory, "external-transaction"); Directory.CreateDirectory(external);
            Directory.CreateSymbolicLink(Path.Combine(state, addon.Id), external);
            using var service = Service(); await Fails(() => service.InstallAsync(addon, originalRelease, game), "符号链接");
            Assert(!Directory.EnumerateFileSystemEntries(external).Any());
        });
        await Test("symlink inside installed addon blocks replacement", async () =>
        {
            var game = Game(); InstallOld(game); File.CreateSymbolicLink(Path.Combine(GamePaths.AddonsDirectory(game), addon.Id, "link"), "/etc/hosts");
            using var service = Service(); await Fails(() => service.InstallAsync(addon, originalRelease, game), "符号链接");
        });
    }
    if (args.Contains("--live"))
    {
        foreach (var a in AddonCatalog.All)
            await Test("live HTTPS check and install official " + a.Id + " into isolated fixture", async () =>
            {
                var game = Game(); using var service = new UpdateService(isGameRunning: () => false);
                var status = await service.CheckAsync(a, game); Assert(status.Error is null, status.Error ?? "");
                await service.InstallAsync(a, status.Latest!, game); Assert(UpdateService.ReadInstalledVersion(a, game) == status.Latest!.Version);
            });
        foreach (var a in new[] { navigator, targets })
            await Test("live HTTPS " + a.Id + " update, backup and restore in isolated fixture", async () =>
            {
                var game = Game(); InstallOld(game, a: a);
                foreach (var other in AddonCatalog.All.Where(other => other != a)) InstallOld(game, "88.0.0", other);
                var wtf = Path.Combine(game, "WTF", "Account", "fixture"); Directory.CreateDirectory(wtf);
                var saved = Path.Combine(wtf, "private-settings.lua"); File.WriteAllText(saved, "preserve fixture settings");
                using var service = new UpdateService(isGameRunning: () => false);
                var status = await service.CheckAsync(a, game);
                Assert(status.Error is null && status.CanInstall && status.InstalledVersion == "0.0.1", status.Error ?? "Update unavailable");
                await service.InstallAsync(a, status.Latest!, game);
                Assert(UpdateService.ReadInstalledVersion(a, game) == status.Latest!.Version && service.HasBackup(a, game));
                await service.RestoreAsync(a, game);
                Assert(UpdateService.ReadInstalledVersion(a, game) == "0.0.1");
                Assert(File.ReadAllText(saved) == "preserve fixture settings");
                foreach (var other in AddonCatalog.All.Where(other => other != a))
                    Assert(UpdateService.ReadInstalledVersion(other, game) == "88.0.0" && !service.HasBackup(other, game));
            });
    }
}
finally
{
    // Delete only this run's fixture tree, never a game installation.
    Directory.Delete(suiteDirectory, true);
}
Console.WriteLine($"RESULT: {passed} passed, {failed} failed");
Environment.ExitCode = failed == 0 ? 0 : 1;

sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    { cancellationToken.ThrowIfCancellationRequested(); return Task.FromResult(respond(request)); }
}

sealed class ImmediateProgress(Action<string> report) : IProgress<string>
{
    public void Report(string value) => report(value);
}
