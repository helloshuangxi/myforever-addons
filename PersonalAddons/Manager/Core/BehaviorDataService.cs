using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MyForeverManager.Core;

// All game files are read-only inputs. Only anonymous, idempotent summaries are
// written to the manager's own state directory. This service has no HTTP client.
public sealed class BehaviorDataService(string stateDirectory)
{
    private readonly string stateDirectory = PathSafety.Normalize(stateDirectory);
    private readonly SemaphoreSlim gate = new(1, 1);
    private const int MaxInputBytes = 8 * 1024 * 1024, MaxArchiveBytes = 32 * 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private static readonly TimeSpan DayOffset = TimeSpan.FromHours(8);

    public async Task<BehaviorDashboard> RefreshAsync(string gameDirectory, CancellationToken cancellationToken = default)
    {
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { return await Task.Run(() => Refresh(gameDirectory, cancellationToken), cancellationToken).ConfigureAwait(false); }
        finally { gate.Release(); }
    }

    private BehaviorDashboard Refresh(string selection, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = new BehaviorDashboard { RefreshedAt = DateTimeOffset.UtcNow };
        string game;
        try { game = GamePaths.Resolve(selection); }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException)
        { result.Notices.Add("请在插件管理中选择有效的无限客户端目录，再刷新行为统计。"); return result; }
        try { result.IsGameRunning = GameProcesses.IsGameRunning(); }
        catch (IOException) { result.Notices.Add("暂时无法确认游戏是否运行；当前显示最近写盘的数据。"); }
        ReadCollector(game, result);
        var archivePath = Path.Combine(stateDirectory, "behavior", Hash(game) + ".json");
        var archive = new BehaviorArchive(); bool archiveHealthy = true;
        try
        {
            PathSafety.AssertNoLinks(archivePath);
            if (File.Exists(archivePath))
            {
                if (new FileInfo(archivePath).Length > MaxArchiveBytes) throw new InvalidDataException();
                archive = JsonSerializer.Deserialize<BehaviorArchive>(File.ReadAllText(archivePath, Utf8)) ?? throw new InvalidDataException();
                ValidateArchive(archive);
            }
        }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or DecoderFallbackException)
        { archive = new(); archiveHealthy = false; result.Notices.Add("本机历史摘要无法读取，原文件已保留；本次仅显示仍可读取的游戏存档。"); }

        var files = FindCollectorFiles(game, result, cancellationToken);
        foreach (var file in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var before = new FileInfo(file); var size = before.Length; var stamp = before.LastWriteTimeUtc;
                if (size > MaxInputBytes) throw new InvalidDataException();
                PathSafety.AssertNoLinks(file);
                var text = File.ReadAllText(file, Utf8);
                var after = new FileInfo(file);
                if (after.Length != size || after.LastWriteTimeUtc != stamp) throw new InvalidDataException();
                var data = BehaviorLuaReader.Parse(text);
                if (N(data, "schema", 1) != 1) throw new InvalidDataException();
                var id = Hash(Path.GetRelativePath(game, file).Replace('\\', '/'));
                var parsed = ReadCharacter(data, id, cancellationToken);
                var metadata = archive.Characters.SingleOrDefault(x => x.Id == id);
                if (metadata is null)
                {
                    if (archive.Characters.Count >= 256)
                    { Notice(result, "本机角色摘要已达容量上限，新增角色暂未导入，已有历史仍保留。"); continue; }
                    metadata = new BehaviorCharacterMetadata { Id = id, Number = archive.Characters.Count == 0 ? 1 : archive.Characters.Max(c => c.Number) + 1 };
                    archive.Characters.Add(metadata);
                }
                if (parsed.Level > 0) metadata.Level = parsed.Level;
                if (ClassNames.ContainsKey(parsed.Class)) metadata.Class = parsed.Class;
                metadata.LastSavedAt = new DateTimeOffset(stamp, TimeSpan.Zero);
                // Replace snapshots of each contribution; never add a second copy on refresh.
                var byKey = archive.Contributions.Where(c => !parsed.CoveredSessionPrefixes.Any(prefix => c.Key.StartsWith(prefix, StringComparison.Ordinal))).ToDictionary(c => c.Key, StringComparer.Ordinal);
                foreach (var contribution in parsed.Contributions) byKey[contribution.Key] = contribution;
                archive.Contributions = byKey.Values.ToList();
            }
            catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or DecoderFallbackException or FormatException or OverflowException or ArgumentException)
            { Notice(result, "有采集存档暂时无法安全读取，已保留此前成功导入的摘要；可在游戏写盘完成后重试。"); }
        }
        if (archive.Contributions.Count > 50_000)
        {
            archive.Contributions = archive.Contributions.OrderByDescending(c => c.Day.Date, StringComparer.Ordinal).Take(50_000).ToList();
            Notice(result, "本机摘要达到容量上限，现保留最近的统计记录。");
        }
        if (archiveHealthy && (files.Count > 0 || archive.Characters.Count > 0))
        {
            try { Save(archivePath, archive); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
            { Notice(result, "本次分析已完成，但本机历史摘要未能写入；请检查软件状态目录权限。"); }
        }
        foreach (var metadata in archive.Characters.OrderBy(c => c.Number))
        {
            var contributions = archive.Contributions.Where(c => c.CharacterId == metadata.Id).ToList();
            if (contributions.Count == 0) continue;
            var character = new BehaviorCharacter { Id = metadata.Id, Class = metadata.Class, Level = metadata.Level,
                DisplayName = $"角色 {metadata.Number}" + (metadata.Level > 0 ? $" · {metadata.Level}级{ClassNames.GetValueOrDefault(metadata.Class, "未知职业")}" : "") };
            foreach (var days in contributions.GroupBy(c => c.Day.Date).OrderByDescending(g => g.Key, StringComparer.Ordinal))
                character.Days.Add(MergeDay(days.Key, days.Select(c => c.Day)));
            result.Characters.Add(character);
            if (metadata.LastSavedAt is { } saved && (result.LatestSavedAt is null || saved > result.LatestSavedAt)) result.LatestSavedAt = saved;
        }
        if (result.Characters.Any(c => c.Days.Any(d => d.HasLegacyData))) Notice(result, "包含旧版已保存片段，时长为片段估算、次数可能不完整；不代表全部游戏行为。");
        if (result.Characters.Any(c => c.Days.Any(d => d.IsPartial && !d.HasLegacyData))) Notice(result, "部分统计存在采集中断或字段缺口，请结合日期下的不完整提示查看。");
        if (result.IsGameRunning) Notice(result, "游戏运行中：这里显示最近写盘的数据。脱战后输入 /reload 或登出，再刷新可更新统计。");
        return result;
    }

    private static void Notice(BehaviorDashboard report, string message)
    { if (!report.Notices.Contains(message)) report.Notices.Add(message); }
    private static string Hash(string input) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input))).ToLowerInvariant();

    private static void ReadCollector(string game, BehaviorDashboard result)
    {
        var toc = Path.Combine(game, "Interface", "AddOns", "MyForeverCoach", "MyForeverCoach.toc");
        try
        {
            PathSafety.AssertNoLinks(toc);
            result.CollectorInstalled = File.Exists(toc);
            if (result.CollectorInstalled && new FileInfo(toc).Length <= 64 * 1024)
            {
                var match = Regex.Match(File.ReadAllText(toc), @"^## Version:\s*(\d+\.\d+\.\d+)\s*$", RegexOptions.Multiline | RegexOptions.CultureInvariant);
                if (match.Success) result.CollectorVersion = match.Groups[1].Value;
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        { Notice(result, "暂时无法读取行为采集插件的安装状态。"); }
    }

    private static List<string> FindCollectorFiles(string game, BehaviorDashboard result, CancellationToken token)
    {
        var found = new List<string>(); var root = Path.Combine(game, "WTF", "Account");
        if (!Directory.Exists(root)) return found;
        var queue = new Queue<(string Path, int Depth)>(); queue.Enqueue((root, 0)); int examined = 0;
        try
        {
            while (queue.Count > 0)
            {
                token.ThrowIfCancellationRequested(); var (current, depth) = queue.Dequeue();
                if (++examined > 4096 || found.Count >= 256) { Notice(result, "角色目录超过单次读取上限，部分角色尚未导入。"); break; }
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) { Notice(result, "已跳过链接目录，仅读取客户端内的普通采集存档。"); continue; }
                PathSafety.AssertNoLinks(current);
                if (Path.GetFileName(current).Equals("SavedVariables", StringComparison.OrdinalIgnoreCase))
                {
                    var candidate = Path.Combine(current, "MyForeverCoach.lua");
                    if (File.Exists(candidate))
                    {
                        if ((File.GetAttributes(candidate) & FileAttributes.ReparsePoint) == 0) found.Add(candidate);
                        else Notice(result, "已跳过链接存档，仅读取客户端内的普通采集存档。");
                    }
                    continue;
                }
                if (depth >= 4) continue;
                foreach (var child in Directory.EnumerateDirectories(current).Order(StringComparer.Ordinal))
                { if (queue.Count + examined >= 4096) { Notice(result, "角色目录超过单次读取上限，部分角色尚未导入。"); break; } queue.Enqueue((child, depth + 1)); }
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        { Notice(result, "部分角色目录暂时无法读取，其已有摘要仍然保留。"); }
        return found.Order(StringComparer.Ordinal).ToList();
    }

    private sealed class ParsedCharacter
    {
        public int Level { get; set; }
        public string Class { get; set; } = "";
        public List<BehaviorContribution> Contributions { get; } = [];
        public List<string> CoveredSessionPrefixes { get; } = [];
    }
    private static ParsedCharacter ReadCharacter(Dictionary<string, object?> root, string id, CancellationToken token)
    {
        var result = new ParsedCharacter();
        var sessions = Items(D(root, "sessions")).OrderBy(x => N(x, "startedAt")).ToList();
        foreach (var session in sessions)
        {
            var character = D(session, "character");
            var level = N(character, "level"); if (level is >= 1 and <= 1000) result.Level = (int)level;
            var characterClass = S(character, "class"); if (ClassNames.ContainsKey(characterClass)) result.Class = characterClass;
        }
        var behavior = D(root, "behavior"); var hasDaily = behavior.Count > 0;
        if (hasDaily)
        {
            if (N(behavior, "schema") != 1 || S(behavior, "dayBasis") != "UTC+08:00") throw new InvalidDataException();
            var generation = S(behavior, "generation");
            if (generation.Length == 0 && behavior.GetValueOrDefault("generation") is double epoch) generation = epoch.ToString("R", CultureInfo.InvariantCulture);
            if (generation.Length is < 1 or > 128) throw new InvalidDataException();
            var days = D(behavior, "days"); if (days.Count > 100) throw new InvalidDataException();
            foreach (var (date, raw) in days)
            {
                token.ThrowIfCancellationRequested();
                if (!ValidDate(date) || raw is not Dictionary<string, object?> day) throw new InvalidDataException();
                result.Contributions.Add(new() { Key = id + ":day:" + Hash(generation) + ":" + date, CharacterId = id, Day = ReadDay(date, day) });
            }
        }
        foreach (var session in sessions)
        {
            token.ThrowIfCancellationRequested();
            // A modern session is already represented in daily cumulative values.
            if (D(session, "behavior").Count > 0 && hasDaily)
            {
                result.CoveredSessionPrefixes.Add(id + ":session:" + Hash(S(session, "id")) + ":");
                continue;
            }
            foreach (var day in BehaviorLegacyAnalysis.Read(session, token))
            {
                var sessionId = S(session, "id"); if (sessionId.Length is < 1 or > 128) throw new InvalidDataException();
                result.Contributions.Add(new() { Key = id + ":session:" + Hash(sessionId) + ":" + day.Date, CharacterId = id, Day = day });
            }
        }
        foreach (var contribution in result.Contributions) ValidateDay(contribution.Day);
        return result;
    }

    internal static BehaviorDay ReadDay(string date, Dictionary<string, object?> raw)
    {
        var time = D(raw, "time"); var counts = D(raw, "counts");
        if (time.Count == 0 || counts.Count == 0) throw new InvalidDataException();
        foreach (var key in new[] { "observedSeconds", "combatSeconds", "nonCombatSeconds", "pausedSeconds", "unknownCombatSeconds" })
        { if (!time.TryGetValue(key, out var value) || value is null) throw new InvalidDataException(); _ = N(time, key); }
        foreach (var key in new[] { "combatsEntered", "combatsCompleted", "deaths", "castsStarted", "castsSucceeded", "castsFailed", "castsInterrupted", "questsAccepted", "questsTurnedIn", "levelsGained", "xpGained" })
        { if (!counts.TryGetValue(key, out var value) || value is null) throw new InvalidDataException(); _ = L(counts, key); }
        var result = new BehaviorDay { Date = date, Counts = new()
        {
            CollectedSeconds = N(time, "observedSeconds"), CombatSeconds = N(time, "combatSeconds"), NonCombatSeconds = N(time, "nonCombatSeconds"), UnknownCombatSeconds = N(time, "unknownCombatSeconds"),
            CombatEntries = L(counts, "combatsEntered"), CombatsCompleted = L(counts, "combatsCompleted"), Deaths = L(counts, "deaths"),
            CastSuccesses = L(counts, "castsSucceeded"), CastFailures = L(counts, "castsFailed"), CastInterruptions = L(counts, "castsInterrupted"),
            QuestsAccepted = L(counts, "questsAccepted"), QuestsTurnedIn = L(counts, "questsTurnedIn"), XpGained = L(counts, "xpGained"), LevelsGained = L(counts, "levelsGained")
        }};
        if (result.Counts.CollectedSeconds > 86_401 || result.Counts.CombatSeconds + result.Counts.NonCombatSeconds + result.Counts.UnknownCombatSeconds > result.Counts.CollectedSeconds + 2) throw new InvalidDataException();
        ValidateCounts(result.Counts);
        var quality = D(raw, "quality");
        foreach (var key in new[] { "xpGaps", "unknownMapSeconds", "detailDropped" })
        { if (!quality.TryGetValue(key, out var value) || value is null) throw new InvalidDataException(); _ = N(quality, key); }
        result.DetailDropped = L(quality, "detailDropped");
        // Dropped raw details do not make independent cumulative counts partial.
        result.IsPartial = quality.Any(kv => kv.Key != "detailDropped" && ((kv.Value is double n && n > 0) || kv.Value is true));
        foreach (var (key, value) in Limited(D(raw, "spells")))
        {
            var spellId = Id(key); var spell = value as Dictionary<string, object?> ?? throw new InvalidDataException();
            result.Spells.Add(new() { SpellId = spellId, Name = Label(S(spell, "name")), Successes = L(spell, "succeeded"), Failures = L(spell, "failed"), Interrupted = L(spell, "interrupted") });
        }
        foreach (var (key, value) in Limited(D(raw, "maps")))
        {
            var mapId = Id(key); var map = value as Dictionary<string, object?> ?? throw new InvalidDataException();
            // xp/deaths/combats exist from collector 0.2.1; older entries read as 0 and the day is not marked as zone detail.
            result.Zones.Add(new() { MapId = mapId, Name = Label(S(map, "name")), Seconds = N(map, "seconds"), Visits = L(map, "visits"),
                XpGained = L(map, "xp"), Deaths = L(map, "deaths"), CombatEntries = L(map, "combats") });
        }
        result.HasZoneDetail = N(raw, "version", 1) >= 2;
        ValidateDay(result);
        return result;
    }

    internal static Dictionary<string, object?> D(Dictionary<string, object?> obj, string key) => obj.GetValueOrDefault(key) as Dictionary<string, object?> ?? new(StringComparer.Ordinal);
    internal static string S(Dictionary<string, object?> obj, string key) => obj.GetValueOrDefault(key) as string ?? "";
    internal static double N(Dictionary<string, object?> obj, string key, double fallback = 0)
    {
        if (!obj.TryGetValue(key, out var value) || value is null) return fallback;
        if (value is not double number || !double.IsFinite(number) || number < 0 || number > 9_007_199_254_740_991) throw new InvalidDataException();
        return number;
    }
    internal static long L(Dictionary<string, object?> obj, string key)
    { var value = N(obj, key); if (value != Math.Truncate(value)) throw new InvalidDataException(); return (long)value; }
    internal static bool B(Dictionary<string, object?> obj, string key) => obj.GetValueOrDefault(key) is true;
    internal static IEnumerable<Dictionary<string, object?>> Items(Dictionary<string, object?> obj) => obj.OrderBy(kv => long.TryParse(kv.Key, out var n) ? n : long.MaxValue).Select(kv => kv.Value).OfType<Dictionary<string, object?>>();
    private static IEnumerable<KeyValuePair<string, object?>> Limited(Dictionary<string, object?> obj)
    { if (obj.Count > 128) throw new InvalidDataException(); return obj; }
    private static long Id(string key) => long.TryParse(key, NumberStyles.None, CultureInfo.InvariantCulture, out var n) && n is > 0 and < 2_147_483_648 ? n : throw new InvalidDataException();
    internal static bool ValidDate(string value) => DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);
    internal static string Label(string value) => value.Length <= 128 ? Regex.Replace(Regex.Replace(value, @"\|c[0-9a-fA-F]{8}|\|r|\|T.*?\|t|\|A.*?\|a", ""), @"[\p{Cc}\p{Cf}]", "").Trim() : "";
    internal static string DayAt(double epoch)
    { try { return DateTimeOffset.FromUnixTimeMilliseconds(checked((long)(epoch * 1000))).ToOffset(DayOffset).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture); } catch (ArgumentOutOfRangeException) { throw new InvalidDataException(); } }

    internal static BehaviorDay MergeDay(string date, IEnumerable<BehaviorDay> source)
    {
        var result = new BehaviorDay { Date = date };
        var days = source.ToList();
        result.HasZoneDetail = days.Count > 0 && days.All(d => d.HasZoneDetail);
        foreach (var day in days)
        {
            Add(result.Counts, day.Counts); result.IsPartial |= day.IsPartial; result.HasLegacyData |= day.HasLegacyData; result.DetailDropped += day.DetailDropped;
        }
        foreach (var group in days.SelectMany(d => d.Spells).GroupBy(s => s.SpellId))
            result.Spells.Add(new() { SpellId = group.Key, Name = group.Select(s => s.Name).LastOrDefault(n => n.Length > 0) ?? "",
                Successes = group.Sum(s => s.Successes), Failures = group.Sum(s => s.Failures), Interrupted = group.Sum(s => s.Interrupted) });
        foreach (var group in days.SelectMany(d => d.Zones).GroupBy(s => s.MapId))
            result.Zones.Add(new() { MapId = group.Key, Name = group.Select(s => s.Name).LastOrDefault(n => n.Length > 0) ?? "", Seconds = group.Sum(s => s.Seconds), Visits = group.Sum(s => s.Visits),
                XpGained = group.Sum(s => s.XpGained), Deaths = group.Sum(s => s.Deaths), CombatEntries = group.Sum(s => s.CombatEntries) });
        return result;
    }
    internal static void Add(BehaviorCounts a, BehaviorCounts b)
    {
        a.CollectedSeconds += b.CollectedSeconds; a.CombatSeconds += b.CombatSeconds; a.NonCombatSeconds += b.NonCombatSeconds; a.UnknownCombatSeconds += b.UnknownCombatSeconds;
        a.CombatEntries += b.CombatEntries; a.CombatsCompleted += b.CombatsCompleted; a.Deaths += b.Deaths; a.CastSuccesses += b.CastSuccesses; a.CastFailures += b.CastFailures; a.CastInterruptions += b.CastInterruptions;
        a.QuestsAccepted += b.QuestsAccepted; a.QuestsTurnedIn += b.QuestsTurnedIn; a.XpGained += b.XpGained; a.LevelsGained += b.LevelsGained;
    }
    private static void ValidateArchive(BehaviorArchive archive)
    {
        if (archive.Schema != 1 || archive.Characters is null || archive.Contributions is null || archive.Characters.Count > 256 || archive.Contributions.Count > 50_000) throw new InvalidDataException();
        if (archive.Characters.Any(c => c is null || c.Id is null || !Regex.IsMatch(c.Id, "^[a-f0-9]{64}$") || c.Number is <= 0 or > 10000 || c.Level is < 0 or > 1000 || c.Class is null || (c.Class.Length > 0 && !ClassNames.ContainsKey(c.Class))) || archive.Characters.Select(c => c.Id).Distinct().Count() != archive.Characters.Count) throw new InvalidDataException();
        foreach (var c in archive.Contributions)
        {
            if (c is null || c.Key is null || c.CharacterId is null || c.Key.Length > 256 || !c.Key.StartsWith(c.CharacterId + ":", StringComparison.Ordinal) || !archive.Characters.Any(x => x.Id == c.CharacterId) || c.Day is null || c.Day.Date is null || !ValidDate(c.Day.Date) || c.Day.Counts is null || c.Day.Spells is null || c.Day.Zones is null || c.Day.Spells.Count > 1200 || c.Day.Zones.Count > 1200 || c.Day.DetailDropped < 0) throw new InvalidDataException();
            ValidateDay(c.Day);
        }
        if (archive.Contributions.Select(c => c.Key).Distinct().Count() != archive.Contributions.Count) throw new InvalidDataException();
    }
    private static void ValidateDay(BehaviorDay day)
    {
        ValidateCounts(day.Counts);
        if (day.DetailDropped is < 0 or > 1_000_000_000_000 || day.Spells.Count > 1200 || day.Zones.Count > 1200 || day.Spells.Any(s => s is null || s.Name is null || s.Name != Label(s.Name) || s.SpellId is <= 0 or > int.MaxValue || s.Successes is < 0 or > 1_000_000_000_000 || s.Failures is < 0 or > 1_000_000_000_000 || s.Interrupted is < 0 or > 1_000_000_000_000) || day.Zones.Any(z => z is null || z.Name is null || z.Name != Label(z.Name) || z.MapId is <= 0 or > int.MaxValue || !double.IsFinite(z.Seconds) || z.Seconds < 0 || z.Seconds > 86_401 || z.Visits is < 0 or > 1_000_000_000_000 || z.XpGained is < 0 or > 1_000_000_000_000 || z.Deaths is < 0 or > 1_000_000_000_000 || z.CombatEntries is < 0 or > 1_000_000_000_000)) throw new InvalidDataException();
    }
    private static void ValidateCounts(BehaviorCounts counts)
    {
        // Far above possible daily activity, but keeps all retained sums finite.
        foreach (var p in typeof(BehaviorCounts).GetProperties())
        { var n = Convert.ToDouble(p.GetValue(counts), CultureInfo.InvariantCulture); if (!double.IsFinite(n) || n < 0 || n > 1_000_000_000_000) throw new InvalidDataException(); }
        if (counts.CollectedSeconds > 86_401 || counts.CombatSeconds + counts.NonCombatSeconds + counts.UnknownCombatSeconds > counts.CollectedSeconds + 2) throw new InvalidDataException();
    }
    private static void Save(string path, BehaviorArchive archive)
    {
        PathSafety.AssertNoLinks(path); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var json = JsonSerializer.Serialize(archive, JsonOptions); if (Encoding.UTF8.GetByteCount(json) > MaxArchiveBytes) throw new IOException();
        var temp = Path.Combine(Path.GetDirectoryName(path)!, ".behavior-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
            if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            using (var stream = new FileStream(temp, options)) { var bytes = Utf8.GetBytes(json); stream.Write(bytes); stream.Flush(true); }
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    private static readonly Dictionary<string, string> ClassNames = new(StringComparer.Ordinal)
    { ["WARRIOR"]="战士", ["PALADIN"]="圣骑士", ["HUNTER"]="猎人", ["ROGUE"]="潜行者", ["PRIEST"]="牧师", ["SHAMAN"]="萨满祭司", ["MAGE"]="法师", ["WARLOCK"]="术士", ["DRUID"]="德鲁伊", ["DEATHKNIGHT"]="死亡骑士", ["MONK"]="武僧", ["DEMONHUNTER"]="恶魔猎手", ["EVOKER"]="唤魔师" };
}

internal sealed class BehaviorArchive
{
    public int Schema { get; set; } = 1;
    public List<BehaviorCharacterMetadata> Characters { get; set; } = [];
    public List<BehaviorContribution> Contributions { get; set; } = [];
}
internal sealed class BehaviorCharacterMetadata
{
    public string Id { get; set; } = "";
    public int Number { get; set; }
    public string Class { get; set; } = "";
    public int Level { get; set; }
    public DateTimeOffset? LastSavedAt { get; set; }
}
internal sealed class BehaviorContribution
{
    public string Key { get; set; } = "";
    public string CharacterId { get; set; } = "";
    public BehaviorDay Day { get; set; } = new();
}
