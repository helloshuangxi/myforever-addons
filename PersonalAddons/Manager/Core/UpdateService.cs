using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MyForeverManager.Core;

public sealed class UpdateService : IDisposable
{
    public const long MaximumArchiveBytes = 32 * 1024 * 1024;
    private readonly HttpClient http;
    private readonly bool ownsClient;
    private readonly Func<bool> isGameRunning;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public UpdateService(string? stateDirectory = null, HttpClient? client = null, Func<bool>? isGameRunning = null)
    {
        // Transaction data is deliberately stored beside AddOns, on the same volume.
        _ = stateDirectory;
        ownsClient = client is null;
        http = client ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, AutomaticDecompression = DecompressionMethods.None }) { Timeout = TimeSpan.FromSeconds(90) };
        this.isGameRunning = isGameRunning ?? GameProcesses.IsGameRunning;
    }

    public async Task<AddonStatus> CheckAsync(AddonDefinition addon, string gameDirectory, CancellationToken ct = default)
    {
        string? installed = null;
        try
        {
            AddonCatalog.Require(addon);
            var game = GamePaths.Resolve(gameDirectory);
            if (Directory.Exists(PendingPath(game, addon)))
            {
                RequireGameClosed();
                using var gate = AcquireLock(game);
                Recover(game, addon, null);
            }
            installed = ReadInstalledVersion(addon, game);
            var bytes = await GetBytesAsync(new Uri(addon.ManifestUrl), 1024 * 1024, ct);
            var release = JsonSerializer.Deserialize<ReleaseManifest>(bytes) ?? throw new InvalidDataException("官网返回了空的版本信息。");
            ValidateManifest(addon, release);
            return new(addon, installed, release, null);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception e) when (e is IOException or InvalidDataException or HttpRequestException or JsonException or UnauthorizedAccessException or ArgumentException or OperationCanceledException)
        { return new(addon, installed, null, FriendlyError(e)); }
    }

    public async Task InstallAsync(AddonDefinition addon, ReleaseManifest release, string gameDirectory, IProgress<string>? progress = null, CancellationToken ct = default)
    {
        AddonCatalog.Require(addon);
        ValidateManifest(addon, release);
        var game = GamePaths.Resolve(gameDirectory);
        RequireGameClosed();
        using var gate = AcquireLock(game);
        Recover(game, addon, progress);
        var installed = ReadInstalledVersion(addon, game);
        if (installed is not null && Versions.Compare(release.Version, installed) <= 0)
            throw new InvalidOperationException("已安装相同或更高版本；管理器不会自动降级。");
        progress?.Report("下载 " + addon.DisplayName + " v" + release.Version + "…");
        var archive = await GetBytesAsync(new Uri(release.Download.Url), release.Download.SizeBytes, ct);
        if (archive.LongLength != release.Download.SizeBytes || !Convert.ToHexString(SHA256.HashData(archive)).Equals(release.Download.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("下载包的大小或 SHA-256 校验不符，原插件未改动。请稍后重试。");
        RequireGameClosed();
        ct.ThrowIfCancellationRequested();
        var pending = PendingPath(game, addon);
        PathSafety.AssertNoLinks(pending);
        Directory.CreateDirectory(pending);
        try
        {
            var stage = Path.Combine(pending, "payload");
            progress?.Report("校验安装文件…");
            ExtractArchive(archive, addon, release, stage);
            ct.ThrowIfCancellationRequested();
            Commit(game, addon, progress);
        }
        catch
        {
            // Recovery only performs filesystem moves. Leave the durable journal in place if
            // game starts or a recovery move fails; the next operation will retry it.
            if (!isGameRunning()) Recover(game, addon, progress);
            throw;
        }
    }

    public Task RestoreAsync(AddonDefinition addon, string gameDirectory, IProgress<string>? progress = null, CancellationToken ct = default)
    {
        AddonCatalog.Require(addon);
        var game = GamePaths.Resolve(gameDirectory);
        RequireGameClosed();
        using var gate = AcquireLock(game);
        Recover(game, addon, progress);
        var backup = FindBackup(game, addon) ?? throw new InvalidOperationException("还没有可恢复的旧版本。");
        ct.ThrowIfCancellationRequested();
        var pending = PendingPath(game, addon);
        try
        {
            progress?.Report("准备恢复上一个版本…");
            PathSafety.CopyTree(backup, Path.Combine(pending, "payload", addon.Id));
            ReadToc(Path.Combine(pending, "payload", addon.Id, addon.Id + ".toc"));
            ct.ThrowIfCancellationRequested();
            Commit(game, addon, progress);
        }
        catch
        {
            if (!isGameRunning()) Recover(game, addon, progress);
            throw;
        }
        return Task.CompletedTask;
    }

    public bool HasBackup(AddonDefinition addon, string gameDirectory)
    {
        try { AddonCatalog.Require(addon); return FindBackup(GamePaths.Resolve(gameDirectory), addon) is not null; }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException) { return false; }
    }

    public static string BackupDirectory(string gameDirectory, AddonDefinition addon)
    { AddonCatalog.Require(addon); return Path.Combine(StatePath(gameDirectory, addon), "backups"); }

    public static string? ReadInstalledVersion(AddonDefinition addon, string gameDirectory)
    {
        AddonCatalog.Require(addon);
        var folder = Path.Combine(GamePaths.AddonsDirectory(gameDirectory), addon.Id);
        PathSafety.AssertTreeSafe(folder);
        if (File.Exists(folder)) throw new InvalidDataException("插件路径被同名文件占用：" + folder);
        if (!Directory.Exists(folder)) return null;
        var toc = Path.Combine(folder, addon.Id + ".toc");
        if (!File.Exists(toc)) throw new InvalidDataException("现有插件目录缺少 TOC，已保留文件。请检查后重试：" + folder);
        return ReadToc(toc).Version;
    }

    public static void ValidateManifest(AddonDefinition addon, ReleaseManifest release)
    {
        AddonCatalog.Require(addon);
        if (release.SchemaVersion != 1 || release.Name != addon.Id || release.Channel is not ("trial" or "stable"))
            throw new InvalidDataException("官网版本信息的插件身份或格式不正确。");
        Versions.Parse(release.Version);
        if (release.Compatibility is null || release.Compatibility.Interface != 16001 || release.Compatibility.Product != "国服魔兽世界：无限" || string.IsNullOrWhiteSpace(release.Compatibility.Client))
            throw new InvalidDataException("此版本尚未适配管理器支持的无限客户端（Interface 16001），请查看官网说明。");
        if (release.Changes is null || release.Validation is null) throw new InvalidDataException("版本说明格式不正确。");
        var download = release.Download ?? throw new InvalidDataException("官网没有提供下载信息。");
        var filename = addon.Id + "-" + release.Version + (release.Channel == "trial" ? "-Trial" : "") + ".zip";
        if (download.Filename != filename || download.Url != "https://afabiaoge.xyz/downloads/" + filename)
            throw new InvalidDataException("下载地址不属于官网的版本化插件目录。");
        if (download.SizeBytes <= 0 || download.SizeBytes > MaximumArchiveBytes || download.Sha256 is null || !Regex.IsMatch(download.Sha256, "^[a-fA-F0-9]{64}$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("官网提供的文件大小或 SHA-256 无效。");
    }

    private async Task<byte[]> GetBytesAsync(Uri uri, long maximum, CancellationToken ct)
    {
        if (uri.Scheme != "https" || uri.Host != "afabiaoge.xyz" || !uri.IsDefaultPort || uri.UserInfo.Length != 0)
            throw new InvalidDataException("仅允许通过 HTTPS 从 afabiaoge.xyz 下载。");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.UserAgent.ParseAdd("MyForeverManager/" + ManagerVersion.Current);
        request.Headers.CacheControl = new() { NoCache = true };
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
        if ((int)response.StatusCode is >= 300 and < 400) throw new InvalidDataException("官网返回了重定向，已停止下载。请稍后重试。");
        response.EnsureSuccessStatusCode();
        if (response.RequestMessage?.RequestUri != uri) throw new InvalidDataException("下载地址发生了变化，已停止安装。");
        if (response.Content.Headers.ContentLength > maximum) throw new InvalidDataException("下载内容超过允许的大小。");
        await using var input = await response.Content.ReadAsStreamAsync(timeout.Token);
        using var output = new MemoryStream();
        byte[] buffer = new byte[65536];
        int count;
        while ((count = await input.ReadAsync(buffer, timeout.Token)) != 0)
        {
            if (output.Length + count > maximum) throw new InvalidDataException("下载内容超过允许的大小。");
            output.Write(buffer, 0, count);
        }
        return output.ToArray();
    }

    private static void ExtractArchive(byte[] bytes, AddonDefinition addon, ReleaseManifest release, string destination)
    {
        using var memory = new MemoryStream(bytes, writable: false);
        using var zip = new ZipArchive(memory, ZipArchiveMode.Read);
        if (zip.Entries.Count is 0 or > 4096) throw new InvalidDataException("安装包文件数量无效。");
        var entries = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        var spelling = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var fileEntries = new List<(ZipArchiveEntry Entry, string Name)>();
        long total = 0;
        foreach (var entry in zip.Entries)
        {
            var original = entry.FullName;
            bool isDirectory = original.EndsWith('/');
            var name = isDirectory ? original[..^1] : original;
            if (string.IsNullOrEmpty(name) || name.Length > 220 || name.StartsWith('/') || name.Contains('\\') || name.Contains(':') || name.Contains('\0'))
                throw new InvalidDataException("安装包包含不安全的路径。");
            string[] parts = name.Split('/');
            foreach (var part in parts)
            {
                if (string.IsNullOrWhiteSpace(part) || part is "." or ".." || part.EndsWith(' ') || part.EndsWith('.') || part.Any(c => c < 32 || "<>\"|?*".Contains(c)) ||
                    Regex.IsMatch(part, @"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant) ||
                    part.Equals("WTF", StringComparison.OrdinalIgnoreCase) || part.Equals("SavedVariables", StringComparison.OrdinalIgnoreCase) || part.StartsWith('.'))
                    throw new InvalidDataException("安装包包含系统保留名、隐私目录或不安全路径。");
            }
            for (int i = 1; i <= parts.Length; i++)
            {
                var prefix = string.Join('/', parts.Take(i));
                if (spelling.TryGetValue(prefix, out var previous) && previous != prefix)
                    throw new InvalidDataException("安装包的目录或文件大小写不一致。");
                spelling.TryAdd(prefix, prefix);
            }
            int unixType = (entry.ExternalAttributes >> 16) & 0xF000;
            if (unixType is not (0 or 0x8000 or 0x4000) || unixType == 0x4000 && !isDirectory || unixType == 0x8000 && isDirectory || (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("安装包包含符号链接或特殊文件。");
            if (!entries.TryAdd(name, isDirectory)) throw new InvalidDataException("安装包包含重复文件名（包括大小写重复）。");
            total = checked(total + entry.Length);
            if (total > 128L * 1024 * 1024 || entry.Length > 32L * 1024 * 1024 || isDirectory && entry.Length != 0)
                throw new InvalidDataException("安装包解压后超过大小限制。");
            if (parts[0] != addon.Id)
            {
                // Official archives may carry a license and standalone documentation at top level.
                // Validate them but never install or open them.
                if (parts.Length != 1 || isDirectory || !(name == "LICENSE.txt" || name == "安装使用说明.txt" || name == addon.Id + "-表情包制作器.html"))
                    throw new InvalidDataException("安装包包含另一个插件或未知的顶层内容。");
                continue;
            }
            if (!isDirectory) fileEntries.Add((entry, name));
        }
        foreach (var (name, _) in entries)
        {
            var split = name.Split('/');
            for (int i = 1; i < split.Length; i++)
                if (entries.TryGetValue(string.Join('/', split.Take(i)), out bool parentDirectory) && !parentDirectory)
                    throw new InvalidDataException("安装包中文件与目录发生冲突。");
        }
        if (fileEntries.Count == 0 || !fileEntries.Any(x => x.Name == addon.Id + "/" + addon.Id + ".toc"))
            throw new InvalidDataException("安装包缺少匹配的插件 TOC。");
        Directory.CreateDirectory(destination);
        foreach (var (entry, name) in fileEntries)
        {
            var target = Path.Combine(destination, name.Replace('/', Path.DirectorySeparatorChar));
            PathSafety.AssertNoLinks(target);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            using var input = entry.Open();
            using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            byte[] buffer = new byte[65536]; long written = 0; int n;
            while ((n = input.Read(buffer)) > 0)
            {
                written += n;
                if (written > entry.Length) throw new InvalidDataException("安装包的实际内容大小与目录信息不符。");
                output.Write(buffer, 0, n);
            }
            if (written != entry.Length) throw new InvalidDataException("安装包文件不完整。");
        }
        var toc = ReadToc(Path.Combine(destination, addon.Id, addon.Id + ".toc"));
        if (toc.Version != release.Version || toc.Interface != release.Compatibility.Interface)
            throw new InvalidDataException("安装包内 TOC 版本或客户端与官网信息不符。");
    }

    private static (string Version, int Interface) ReadToc(string path)
    {
        if (new FileInfo(path).Length > 65536) throw new InvalidDataException("TOC 文件过大。");
        var text = File.ReadAllText(path, Encoding.UTF8);
        var versions = Regex.Matches(text, @"^##\s*Version\s*:\s*(\S+)\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
        var interfaces = Regex.Matches(text, @"^##\s*Interface\s*:\s*(\d+)\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
        if (versions.Count != 1 || interfaces.Count != 1 || !int.TryParse(interfaces[0].Groups[1].Value, out int clientInterface))
            throw new InvalidDataException("插件 TOC 缺少唯一有效的版本或客户端标记。");
        var version = versions[0].Groups[1].Value;
        Versions.Parse(version);
        return (version, clientInterface);
    }

    private void RequireGameClosed()
    {
        if (isGameRunning()) throw new IOException("游戏正在运行，已暂缓安装。请完整退出魔兽世界，管理器会在下次检查时重试。");
    }
    private static string RootStatePath(string game) => Path.Combine(game, "Interface", ".MyForeverManager");
    private static string StatePath(string game, AddonDefinition addon) => Path.Combine(RootStatePath(game), addon.Id);
    private static string PendingPath(string game, AddonDefinition addon) => Path.Combine(StatePath(game, addon), "pending");
    private static string TargetPath(string game, AddonDefinition addon) => Path.Combine(GamePaths.AddonsDirectory(game), addon.Id);

    private static FileStream AcquireLock(string game)
    {
        var state = RootStatePath(game);
        PathSafety.AssertNoLinks(state);
        Directory.CreateDirectory(state);
        var path = Path.Combine(state, "update.lock");
        PathSafety.AssertNoLinks(path);
        try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException e) { throw new IOException("另一个管理器正在更新这个游戏目录，请稍后重试。", e); }
    }

    private static string? FindBackup(string game, AddonDefinition addon)
    {
        var backup = BackupDirectory(game, addon);
        PathSafety.AssertNoLinks(backup);
        if (!Directory.Exists(backup)) return null;
        foreach (var directory in Directory.EnumerateDirectories(backup).OrderDescending(StringComparer.Ordinal))
        {
            PathSafety.AssertTreeSafe(directory);
            if (File.Exists(Path.Combine(directory, addon.Id + ".toc"))) return directory;
        }
        return null;
    }

    private sealed class Journal
    {
        public bool HadOriginal { get; set; }
        public string BackupId { get; set; } = "";
        public bool Committed { get; set; }
    }

    private static void WriteJournal(string pending, Journal journal)
    {
        var temp = Path.Combine(pending, "journal.tmp");
        var path = Path.Combine(pending, "journal.json");
        PathSafety.AssertNoLinks(temp);
        using (var stream = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, journal, JsonOptions);
            stream.Flush(true);
        }
        File.Move(temp, path, true);
    }

    private void Commit(string game, AddonDefinition addon, IProgress<string>? progress)
    {
        RequireGameClosed();
        var pending = PendingPath(game, addon);
        var target = TargetPath(game, addon);
        var payload = Path.Combine(pending, "payload", addon.Id);
        var original = Path.Combine(pending, "original");
        PathSafety.AssertTreeSafe(pending);
        PathSafety.AssertTreeSafe(target);
        Directory.CreateDirectory(GamePaths.AddonsDirectory(game));
        var journal = new Journal { HadOriginal = Directory.Exists(target), BackupId = DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffffffZ") + "-" + Guid.NewGuid().ToString("N") };
        WriteJournal(pending, journal);
        RequireGameClosed();
        progress?.Report("保存旧版并安装新文件…");
        if (journal.HadOriginal) Directory.Move(target, original);
        try
        {
            RequireGameClosed();
            Directory.Move(payload, target);
            journal.Committed = true;
            WriteJournal(pending, journal);
        }
        catch
        {
            // Once original was moved, always restore it immediately even if the game started.
            if (Directory.Exists(original) && !Directory.Exists(target)) Directory.Move(original, target);
            throw;
        }
        FinishCommit(game, addon, journal);
        progress?.Report(addon.DisplayName + "已安装。重新启动游戏后生效。");
    }

    private void Recover(string game, AddonDefinition addon, IProgress<string>? progress)
    {
        var pending = PendingPath(game, addon);
        PathSafety.AssertNoLinks(pending);
        if (!Directory.Exists(pending)) return;
        RequireGameClosed();
        PathSafety.AssertTreeSafe(pending);
        var journalFile = Path.Combine(pending, "journal.json");
        if (!File.Exists(journalFile))
        {
            // No target operation starts until the durable journal exists.
            Directory.Delete(pending, true);
            return;
        }
        Journal journal;
        try { journal = JsonSerializer.Deserialize<Journal>(File.ReadAllText(journalFile)) ?? throw new InvalidDataException("恢复记录为空。"); }
        catch (JsonException e) { throw new InvalidDataException("更新恢复记录损坏，已保留所有文件：" + pending, e); }
        if (!Regex.IsMatch(journal.BackupId, @"^\d{8}T\d{13}Z-[a-f0-9]{32}$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("更新恢复记录无效，已保留所有文件：" + pending);
        if (journal.Committed) { FinishCommit(game, addon, journal); return; }
        var target = TargetPath(game, addon);
        var original = Path.Combine(pending, "original");
        var payload = Path.Combine(pending, "payload", addon.Id);
        PathSafety.AssertTreeSafe(target);
        if (Directory.Exists(original))
        {
            PreserveUncommittedTarget(game, addon, target, journal.BackupId);
            Directory.Move(original, target);
        }
        else if (!journal.HadOriginal && !Directory.Exists(payload) && Directory.Exists(target))
        {
            PreserveUncommittedTarget(game, addon, target, journal.BackupId);
        }
        Directory.Delete(pending, true);
        progress?.Report("已恢复上次中断的更新，旧文件保持可用。");
    }

    private static void PreserveUncommittedTarget(string game, AddonDefinition addon, string target, string id)
    {
        if (!Directory.Exists(target)) return;
        var recovery = Path.Combine(StatePath(game, addon), "recovered", id + "-" + Guid.NewGuid().ToString("N"));
        PathSafety.AssertNoLinks(recovery);
        Directory.CreateDirectory(Path.GetDirectoryName(recovery)!);
        Directory.Move(target, recovery);
    }
    private static void FinishCommit(string game, AddonDefinition addon, Journal journal)
    {
        var pending = PendingPath(game, addon);
        var original = Path.Combine(pending, "original");
        if (Directory.Exists(original))
        {
            var backup = Path.Combine(BackupDirectory(game, addon), journal.BackupId);
            PathSafety.AssertNoLinks(backup);
            Directory.CreateDirectory(Path.GetDirectoryName(backup)!);
            Directory.Move(original, backup);
        }
        Directory.Delete(pending, true);
    }

    private static string FriendlyError(Exception error) => error switch
    {
        UnauthorizedAccessException => "没有写入游戏目录的权限。请将游戏放在当前用户可写的位置，或用具有目录权限的账户运行管理器。",
        OperationCanceledException => "官网请求超时，请检查网络后重试。",
        HttpRequestException => "暂时无法连接官网，请检查网络后重试。" + (error is HttpRequestException { StatusCode: { } code } ? "（HTTP " + (int)code + "）" : ""),
        _ => error.Message
    };
    public void Dispose() { if (ownsClient) http.Dispose(); }
}
