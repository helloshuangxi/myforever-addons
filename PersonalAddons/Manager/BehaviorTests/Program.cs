using System.Diagnostics;
using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using MyForeverManager.Core;
using static Fixtures;

var suiteDirectory = Path.Combine(OperatingSystem.IsMacOS() ? "/private/tmp" : Path.GetTempPath(), "myforever-behavior-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(suiteDirectory);
int passed = 0, failed = 0;

async Task Test(string title, Func<Task> run)
{
    try { await run(); passed++; Console.WriteLine("PASS " + title); }
    catch (Exception error) { failed++; Console.WriteLine("FAIL " + title + "\n" + error); }
}
void Assert(bool condition, string message = "Assertion failed") { if (!condition) throw new Exception(message); }
void Equal<T>(T expected, T actual, string? message = null) where T : notnull => Assert(EqualityComparer<T>.Default.Equals(expected, actual), message ?? $"Expected {expected}, got {actual}");
void Close(double expected, double actual, double epsilon = 0.001) => Assert(Math.Abs(expected - actual) < epsilon, $"Expected approximately {expected}, got {actual}");
string Game()
{
    var game = Path.Combine(suiteDirectory, Guid.NewGuid().ToString("N"), "_forever_");
    Directory.CreateDirectory(game);
    File.WriteAllText(Path.Combine(game, "Wow.exe"), "fixture marker; never run");
    return game;
}
string State() => Path.Combine(suiteDirectory, "state-" + Guid.NewGuid().ToString("N"));
string Source(string game, string character = "FixtureCharacter", string account = "FixtureAccount") =>
    Path.Combine(game, "WTF", "Account", account, "FixtureRealm", character, "SavedVariables", "MyForeverCoach.lua");
string Write(string game, object data, string character = "FixtureCharacter", string account = "FixtureAccount")
{
    var path = Source(game, character, account);
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    File.WriteAllText(path, Lua(data));
    return path;
}
BehaviorDay OneDay(BehaviorDashboard dashboard) => dashboard.Characters.Single().Days.Single();
void PrivateNotices(BehaviorDashboard dashboard, params string[] tokens)
{
    foreach (var notice in dashboard.Notices)
        foreach (var token in tokens.Concat(new[] { suiteDirectory, "FixtureAccount", "FixtureRealm", "FixtureCharacter" }))
            Assert(!notice.Contains(token, StringComparison.OrdinalIgnoreCase), "A public notice exposed fixture path or private source text.");
}
Dictionary<string, string> SnapshotFiles(string directory) => Directory.GetFiles(directory, "*", SearchOption.AllDirectories)
    .ToDictionary(path => Path.GetRelativePath(directory, path), path => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path))));

try
{
    await Test("空客户端返回空统计", async () =>
    {
        var result = await new BehaviorDataService(State()).RefreshAsync(Game());
        Equal(0, result.Characters.Count);
        Assert(!result.CollectorInstalled);
        Assert(result.LatestSavedAt is null);
        Assert(result.RefreshedAt > DateTimeOffset.MinValue);
    });

    await Test("无效客户端目录返回净化提示而不抛出异常", async () =>
    {
        var ordinary = Path.Combine(suiteDirectory, "PrivateInvalidDirectory"); Directory.CreateDirectory(ordinary);
        var markerless = Path.Combine(ordinary, "_forever_"); Directory.CreateDirectory(markerless);
        foreach (var selection in new[] { "", ordinary, markerless, Path.Combine(suiteDirectory, "missing-private-directory") })
        {
            var result = await new BehaviorDataService(State()).RefreshAsync(selection);
            Equal(0, result.Characters.Count); Assert(result.Notices.Count > 0); PrivateNotices(result, ordinary, "missing-private-directory", "PrivateInvalidDirectory");
        }
    });

    await Test("只读检测采集器 TOC 版本，不碰其他插件存档", async () =>
    {
        var game = Game();
        var toc = Path.Combine(game, "Interface", "AddOns", "MyForeverCoach", "MyForeverCoach.toc");
        Directory.CreateDirectory(Path.GetDirectoryName(toc)!);
        File.WriteAllText(toc, "## Interface: 11507\n## Title: 我的无限行为采集\n## Version: 0.2.0\nCore.lua\n");
        Write(game, Modern());
        File.WriteAllText(Path.Combine(Path.GetDirectoryName(Source(game))!, "OtherAddon.lua"), "error(\"This must not be read or executed\")\n");
        var before = SnapshotFiles(game);
        var result = await new BehaviorDataService(State()).RefreshAsync(game);
        Assert(result.CollectorInstalled);
        Equal("0.2.0", result.CollectorVersion!);
        var after = SnapshotFiles(game);
        Equal(before.Count, after.Count);
        foreach (var (path, digest) in before) Equal(digest, after[path], "Refresh modified a game file: " + path);
        Assert(!result.Notices.Any(notice => notice.Contains("无法安全读取", StringComparison.Ordinal)), "An unrelated addon was treated as collector input.");
        Equal(1, result.Characters.Count);
    });

    await Test("现代日累计读出核心计数、技能与地区", async () =>
    {
        var game = Game(); Write(game, Modern());
        var result = await new BehaviorDataService(State()).RefreshAsync(game);
        var day = OneDay(result);
        Equal(Day, day.Date); Close(100, day.Counts.CollectedSeconds); Close(40, day.Counts.CombatSeconds); Close(60, day.Counts.NonCombatSeconds);
        Equal(3L, day.Counts.CombatEntries); Equal(2L, day.Counts.CombatsCompleted); Equal(1L, day.Counts.Deaths);
        Equal(5L, day.Counts.CastSuccesses); Equal(2L, day.Counts.CastFailures); Equal(250L, day.Counts.XpGained);
        Equal(4L, day.Counts.QuestsAccepted); Equal(2L, day.Counts.QuestsTurnedIn); Equal(1L, day.Counts.LevelsGained);
        var spell = day.Spells.Single(); Equal(639L, spell.SpellId); Equal("圣光术", spell.Name); Equal(5L, spell.Successes); Equal(1L, spell.Interrupted);
        var zone = day.Zones.Single(); Equal(1426L, zone.MapId); Equal("丹莫罗", zone.Name); Close(100, zone.Seconds); Equal(2L, zone.Visits);
        Assert(!day.HasLegacyData && !day.IsPartial);
        Assert(result.LatestSavedAt.HasValue);
    });

    await Test("重复刷新和服务重启均不重复累加", async () =>
    {
        var game = Game(); var state = State(); Write(game, Modern());
        var service = new BehaviorDataService(state);
        for (var i = 0; i < 3; i++) Equal(5L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
        Equal(5L, OneDay(await new BehaviorDataService(state).RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("同 generation 同日期以最新累计替换，数值降低也不相加", async () =>
    {
        var game = Game(); var service = new BehaviorDataService(State()); Write(game, Modern(5));
        await service.RefreshAsync(game);
        Write(game, Modern(8)); Equal(8L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
        Write(game, Modern(3)); Equal(3L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("新 generation 同日独立归档", async () =>
    {
        var game = Game(); var service = new BehaviorDataService(State()); Write(game, Modern(5, "generation-one"));
        await service.RefreshAsync(game);
        Write(game, Modern(3, "generation-two"));
        Equal(8L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("来源日数据被轮转后历史摘要仍保留", async () =>
    {
        var game = Game(); var state = State(); var service = new BehaviorDataService(state);
        Write(game, Modern(5, date: "2026-11-10")); await service.RefreshAsync(game);
        Write(game, Modern(7));
        var character = (await new BehaviorDataService(state).RefreshAsync(game)).Characters.Single();
        Equal(2, character.Days.Count);
        Equal(5L, character.Days.Single(day => day.Date == "2026-11-10").Counts.CastSuccesses);
        Equal(7L, character.Days.Single(day => day.Date == Day).Counts.CastSuccesses);
    });

    await Test("现代 session 诊断不与日累计或原始 records 双算", async () =>
    {
        var game = Game(); Write(game, Modern(11));
        Equal(11L, OneDay(await new BehaviorDataService(State()).RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("已归档旧会话后续明确由现代日累计覆盖时撤销旧贡献", async () =>
    {
        var game = Game(); var state = State(); var service = new BehaviorDataService(state);
        var session = Session("migrating-session", new object[] { Snapshot(0, 100), Cast(1, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(2, 100) });
        Write(game, Legacy(session)); Equal(1L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
        session["behavior"] = D(("schema", 1), ("daily", true));
        Write(game, Modern(1, "migration-generation", Day, session));
        Equal(1L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
        Equal(1L, OneDay(await new BehaviorDataService(state).RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("跨角色相同 generation、日期及 session ID 不串档且公开角色匿名", async () =>
    {
        var game = Game(); Write(game, Modern(5), "PrivateAlice", "PrivateAccount"); Write(game, Modern(9), "PrivateBob", "PrivateAccount");
        var result = await new BehaviorDataService(State()).RefreshAsync(game);
        Equal(2, result.Characters.Count); Equal(2, result.Characters.Select(c => c.Id).Distinct().Count());
        Assert(result.Characters.Select(c => c.Days.Single().Counts.CastSuccesses).Order().SequenceEqual(new long[] { 5, 9 }));
        foreach (var character in result.Characters)
            foreach (var token in new[] { "PrivateAlice", "PrivateBob", "PrivateAccount", "FixtureRealm", suiteDirectory })
            {
                Assert(!character.Id.Contains(token, StringComparison.OrdinalIgnoreCase));
                Assert(!character.DisplayName.Contains(token, StringComparison.OrdinalIgnoreCase));
            }
    });

    await Test("本机归档只保存匿名摘要，不复制来源路径或原始个人字段", async () =>
    {
        var game = Game(); var state = State(); var root = Modern();
        root["privateRawField"] = "RawPrivatePayloadMarker";
        Write(game, root, "PrivateCharacterMarker", "PrivateAccountMarker");
        await new BehaviorDataService(state).RefreshAsync(game);
        var files = Directory.GetFiles(state, "*.json", SearchOption.AllDirectories);
        Assert(files.Length > 0, "No persistent summary was written.");
        foreach (var file in files)
        {
            var text = await File.ReadAllTextAsync(file);
            foreach (var token in new[] { "RawPrivatePayloadMarker", "PrivateCharacterMarker", "PrivateAccountMarker", "FixtureRealm", game })
                Assert(!text.Contains(token, StringComparison.OrdinalIgnoreCase), "Archive copied a private raw field or source path.");
        }
    });

    await Test("旧版只从真实 records 回填，不把 receivedEvents 和探测计数当行为", async () =>
    {
        var records = new object[] {
            Snapshot(0, 100), Cast(1, "UNIT_SPELLCAST_START"), Cast(2, "UNIT_SPELLCAST_SUCCEEDED"), Cast(3, "UNIT_SPELLCAST_STOP"),
            Cast(4, "UNIT_SPELLCAST_FAILED"), Cast(5, "UNIT_SPELLCAST_INTERRUPTED"),
            Record(6, "combat", D(("phase", "enter"), ("combat", true)), "combat"),
            Record(7, "death", D(("event", "PLAYER_DEAD"), ("dead", true))),
            Record(8, "death", D(("event", "PLAYER_ALIVE"), ("dead", false))),
            Record(9, "death", D(("event", "PLAYER_UNGHOST"), ("dead", false))),
            Record(10, "combat", D(("phase", "leave"), ("combat", false))), Snapshot(12, 125)
        };
        var game = Game(); Write(game, Legacy(Session("legacy-one", records)));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Equal(1L, day.Counts.CastSuccesses); Equal(1L, day.Counts.CastFailures); Equal(1L, day.Counts.Deaths);
        Equal(1L, day.Counts.CombatEntries); Equal(1L, day.Counts.CombatsCompleted); Equal(25L, day.Counts.XpGained);
        Assert(day.HasLegacyData && day.IsPartial); Assert(day.Counts.CollectedSeconds <= 12.001, "Unobserved session tail was treated as collected playtime.");
        Equal(1L, day.Spells.Single().Successes);
    });

    await Test("旧版仅有诊断计数而无行为 records 时不生成虚假施法或死亡", async () =>
    {
        var game = Game(); Write(game, Legacy(Session("diagnostics-only", new object[] { Snapshot(0, 100), Snapshot(10, 100) })));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Equal(0L, day.Counts.CastSuccesses); Equal(0L, day.Counts.Deaths); Equal(0L, day.Counts.CombatEntries); Equal(0L, day.Counts.XpGained);
    });

    await Test("旧版会话重复刷新及重启幂等", async () =>
    {
        var game = Game(); var state = State(); Write(game, Legacy(Session("legacy-idempotent", new object[] { Snapshot(0, 100), Cast(2, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(5, 120) })));
        var service = new BehaviorDataService(state); await service.RefreshAsync(game);
        Equal(1L, OneDay(await service.RefreshAsync(game)).Counts.CastSuccesses);
        Equal(1L, OneDay(await new BehaviorDataService(state).RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("不同角色同旧会话 ID 分别计算", async () =>
    {
        var game = Game(); var session = Session("same-id", new object[] { Snapshot(0, 100), Cast(1, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(2, 120) });
        Write(game, Legacy(session), "CharacterOne"); Write(game, Legacy(session), "CharacterTwo");
        var result = await new BehaviorDataService(State()).RefreshAsync(game);
        Equal(2, result.Characters.Count); Assert(result.Characters.All(c => c.Days.Single().Counts.CastSuccesses == 1));
    });

    await Test("同日现代累计与旧版独立会话合并", async () =>
    {
        var old = Session("before-upgrade", new object[] { Snapshot(0, 100), Cast(1, "UNIT_SPELLCAST_SUCCEEDED"), Cast(2, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(3, 120) }, StartedAt - 3600);
        var game = Game(); Write(game, Modern(5, "mixed-generation", Day, old));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Equal(7L, day.Counts.CastSuccesses); Equal(270L, day.Counts.XpGained); Assert(day.HasLegacyData && day.IsPartial);
    });

    await Test("经验跨一次升级按 xpMax 差额计算，不与任务奖励重复加", async () =>
    {
        var game = Game(); Write(game, Legacy(Session("level-xp", new object[] {
            Snapshot(0, 900), Record(1, "quest", D(("event", "QUEST_TURNED_IN"), ("questID", 102), ("xpReward", 150))),
            Record(2, "level", D(("level", 10))), Snapshot(3, 50, level: 10, xpMax: 1200)
        })));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Equal(150L, day.Counts.XpGained); Equal(1L, day.Counts.LevelsGained); Equal(1L, day.Counts.QuestsTurnedIn);
    });

    await Test("旧版丢弃明细保持不完整提示", async () =>
    {
        var game = Game(); Write(game, Legacy(Session("truncated", new object[] { Snapshot(0, 100), Cast(1, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(5, 120) }, dropped: 47)));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Assert(day.IsPartial && day.HasLegacyData); Equal(47L, day.DetailDropped); Equal(1L, day.Counts.CastSuccesses);
    });

    await Test("旧版暂停不采集行为或补算暂停期经验", async () =>
    {
        var game = Game(); Write(game, Legacy(Session("paused-session", new object[] {
            Snapshot(0, 100), Record(1, "pause", D(("enabled", false))), Cast(5, "UNIT_SPELLCAST_SUCCEEDED"),
            Record(20, "pause", D(("enabled", true))), Snapshot(21, 500), Cast(21.5, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(22, 525)
        })));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Equal(1L, day.Counts.CastSuccesses); Equal(25L, day.Counts.XpGained); Close(3, day.Counts.CollectedSeconds);
    });

    await Test("旧版长期明细缺口不推定为连续采集或战斗时长", async () =>
    {
        var game = Game(); Write(game, Legacy(Session("record-gap", new object[] {
            Snapshot(0, 100, combat: true), Snapshot(3600, 100, combat: true), Cast(3601, "UNIT_SPELLCAST_SUCCEEDED")
        })));
        var day = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Close(1, day.Counts.CollectedSeconds); Close(1, day.Counts.CombatSeconds); Equal(1L, day.Counts.CastSuccesses);
    });

    await Test("UTC+8 午夜以事件时刻划分旧版行为", async () =>
    {
        var start = DateTimeOffset.Parse("2026-11-10T23:59:58+08:00").ToUnixTimeSeconds();
        var game = Game(); Write(game, Legacy(Session("cross-midnight", new object[] { Snapshot(0, 100), Cast(1, "UNIT_SPELLCAST_SUCCEEDED"), Cast(3, "UNIT_SPELLCAST_SUCCEEDED"), Snapshot(4, 100) }, start)));
        var days = (await new BehaviorDataService(State()).RefreshAsync(game)).Characters.Single().Days;
        Equal(2, days.Count); Equal(1L, days.Single(d => d.Date == "2026-11-10").Counts.CastSuccesses); Equal(1L, days.Single(d => d.Date == Day).Counts.CastSuccesses);
    });

    await Test("坏 Lua 和未知赋值拒绝，保留已归档摘要并净化提示", async () =>
    {
        var game = Game(); var state = State(); var source = Write(game, Modern(5)); var service = new BehaviorDataService(state);
        await service.RefreshAsync(game);
        var sentinel = Path.Combine(suiteDirectory, "must-not-be-created");
        foreach (var bad in new[] {
            "MyForeverCoachDB = (function() os.execute('touch " + sentinel + "'); return {} end)()",
            "UnrelatedPrivateVariable = {}\nMyForeverCoachDB = {}",
            "MyForeverCoachDB = { secret = 'private-payload-token', value = 1 + 2 }",
            "MyForeverCoachDB = { [\"unterminated\"] = \"private-payload-token"
        })
        {
            File.WriteAllText(source, bad);
            var result = await service.RefreshAsync(game);
            Equal(5L, OneDay(result).Counts.CastSuccesses); Assert(result.Notices.Count > 0); Assert(!File.Exists(sentinel));
            PrivateNotices(result, "private-payload-token", "UnrelatedPrivateVariable", sentinel);
        }
        Equal(5L, OneDay(await new BehaviorDataService(state).RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("源文件暂缺仍显示已成功导入的历史摘要", async () =>
    {
        var game = Game(); var state = State(); var source = Write(game, Modern()); await new BehaviorDataService(state).RefreshAsync(game);
        File.Move(source, source + ".fixture-hidden");
        Equal(5L, OneDay(await new BehaviorDataService(state).RefreshAsync(game)).Counts.CastSuccesses);
    });

    await Test("本机归档损坏时保留原文件、提示净化、仍能读取合法源", async () =>
    {
        var game = Game(); var state = State(); Write(game, Modern()); await new BehaviorDataService(state).RefreshAsync(game);
        var archive = Directory.GetFiles(state, "*.json", SearchOption.AllDirectories).Single();
        const string badArchive = "{ raw-private-archive-marker";
        File.WriteAllText(archive, badArchive);
        var result = await new BehaviorDataService(state).RefreshAsync(game);
        Equal(5L, OneDay(result).Counts.CastSuccesses); Equal(badArchive, await File.ReadAllTextAsync(archive));
        Assert(result.Notices.Count > 0); PrivateNotices(result, "raw-private-archive-marker", archive);
    });

    await Test("含 null 的本机 JSON 损坏归档不会令刷新崩溃", async () =>
    {
        var game = Game(); var state = State(); Write(game, Modern()); await new BehaviorDataService(state).RefreshAsync(game);
        var archive = Directory.GetFiles(state, "*.json", SearchOption.AllDirectories).Single();
        var original = await File.ReadAllTextAsync(archive);
        Action<JsonObject>[] corruptions = [
            node => node["Characters"]!.AsArray().Add((JsonNode?)null),
            node => node["Contributions"]!.AsArray().Add((JsonNode?)null),
            node => node["Characters"]![0]!["Id"] = null,
            node => node["Characters"]![0]!["Class"] = null,
            node => node["Contributions"]![0]!["Key"] = null,
            node => node["Contributions"]![0]!["CharacterId"] = null,
            node => node["Contributions"]![0]!["Day"]!["Date"] = null,
            node => node["Contributions"]![0]!["Day"]!["Spells"]!.AsArray().Add((JsonNode?)null),
            node => node["Contributions"]![0]!["Day"]!["Spells"]![0]!["Name"] = null,
            node => node["Contributions"]![0]!["Day"]!["Zones"]!.AsArray().Add((JsonNode?)null),
            node => node["Contributions"]![0]!["Day"]!["Zones"]![0]!["Name"] = null
        ];
        foreach (var corrupt in corruptions)
        {
            var node = JsonNode.Parse(original)!.AsObject(); corrupt(node); var bad = node.ToJsonString(); await File.WriteAllTextAsync(archive, bad);
            var result = await new BehaviorDataService(state).RefreshAsync(game);
            Equal(5L, OneDay(result).Counts.CastSuccesses); Equal(bad, await File.ReadAllTextAsync(archive)); Assert(result.Notices.Count > 0); PrivateNotices(result);
        }
    });

    await Test("归档极端整数不造成合并溢出、负数或刷新异常", async () =>
    {
        var game = Game(); var state = State(); Write(game, Modern()); await new BehaviorDataService(state).RefreshAsync(game);
        var archive = Directory.GetFiles(state, "*.json", SearchOption.AllDirectories).Single();
        var node = JsonNode.Parse(await File.ReadAllTextAsync(archive))!.AsObject();
        var contributions = node["Contributions"]!.AsArray(); var extra = contributions[0]!.DeepClone();
        extra["Key"] = extra["Key"]!.GetValue<string>() + ":extreme";
        extra["Day"]!["Spells"]![0]!["Successes"] = long.MaxValue;
        extra["Day"]!["Spells"]![0]!["Failures"] = long.MaxValue;
        extra["Day"]!["Zones"]![0]!["Visits"] = long.MaxValue;
        contributions.Add(extra); await File.WriteAllTextAsync(archive, node.ToJsonString());
        var result = await new BehaviorDataService(state).RefreshAsync(game);
        var day = OneDay(result); Assert(day.Counts.CastSuccesses >= 0); Assert(day.Spells.All(s => s.Successes >= 0 && s.Failures >= 0)); Assert(day.Zones.All(z => z.Visits >= 0));
    });

    await Test("历史角色数量达到容量后不写出下一刷新无法读取的归档", async () =>
    {
        var game = Game(); var state = State(); Write(game, Modern()); await new BehaviorDataService(state).RefreshAsync(game);
        var archive = Directory.GetFiles(state, "*.json", SearchOption.AllDirectories).Single();
        var node = JsonNode.Parse(await File.ReadAllTextAsync(archive))!.AsObject();
        var characterTemplate = node["Characters"]![0]!.DeepClone(); var contributionTemplate = node["Contributions"]![0]!.DeepClone();
        var characters = new JsonArray(); var contributions = new JsonArray();
        for (var i = 0; i < 256; i++)
        {
            var id = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("historical-character-" + i))).ToLowerInvariant();
            var character = characterTemplate.DeepClone(); character["Id"] = id; character["Number"] = i + 1; characters.Add(character);
            var contribution = contributionTemplate.DeepClone(); contribution["CharacterId"] = id; contribution["Key"] = id + ":day:" + new string('a', 64) + ":" + Day; contributions.Add(contribution);
        }
        node["Characters"] = characters; node["Contributions"] = contributions; await File.WriteAllTextAsync(archive, node.ToJsonString());
        var first = await new BehaviorDataService(state).RefreshAsync(game);
        var second = await new BehaviorDataService(state).RefreshAsync(game);
        Equal(first.Characters.Count, second.Characters.Count, "A refresh wrote a character archive rejected on restart.");
        Assert(first.Characters.Count <= 256, "Character history exceeded its supported archive capacity.");
        Equal(first.Characters.Sum(c => c.Days.Sum(d => d.Counts.CastSuccesses)), second.Characters.Sum(c => c.Days.Sum(d => d.Counts.CastSuccesses)));
    });

    await Test("符号链接账号目录不越界读取", async () =>
    {
        var game = Game(); var outsideGame = Game(); Write(outsideGame, Modern(123), "PrivateOutsideCharacter", "OutsideAccount");
        var accountRoot = Path.Combine(game, "WTF", "Account"); Directory.CreateDirectory(accountRoot);
        Directory.CreateSymbolicLink(Path.Combine(accountRoot, "LinkedAccount"), Path.Combine(outsideGame, "WTF", "Account", "OutsideAccount"));
        var result = await new BehaviorDataService(State()).RefreshAsync(game);
        Equal(0, result.Characters.Count); PrivateNotices(result, "OutsideAccount", "PrivateOutsideCharacter", "LinkedAccount", outsideGame);
    });

    await Test("符号链接采集存档不越界读取", async () =>
    {
        var game = Game(); var outside = Path.Combine(suiteDirectory, "outside.lua"); File.WriteAllText(outside, Lua(Modern(456)));
        var source = Source(game); Directory.CreateDirectory(Path.GetDirectoryName(source)!); File.CreateSymbolicLink(source, outside);
        var result = await new BehaviorDataService(State()).RefreshAsync(game);
        Equal(0, result.Characters.Count); PrivateNotices(result, outside);
    });

    await Test("超大源文件受限并保留历史摘要", async () =>
    {
        var game = Game(); var source = Write(game, Modern()); var service = new BehaviorDataService(State()); await service.RefreshAsync(game);
        File.WriteAllText(source, "MyForeverCoachDB = { data = \"" + new string('x', 20 * 1024 * 1024) + "\" }");
        var timer = Stopwatch.StartNew(); var result = await service.RefreshAsync(game); timer.Stop();
        Equal(5L, OneDay(result).Counts.CastSuccesses); Assert(result.Notices.Count > 0); Assert(timer.Elapsed < TimeSpan.FromSeconds(10), "Oversize fixture was not bounded promptly.");
        PrivateNotices(result);
    });

    await Test("深度超限 Lua 受限且不影响已有归档", async () =>
    {
        var game = Game(); var source = Write(game, Modern()); var service = new BehaviorDataService(State()); await service.RefreshAsync(game);
        File.WriteAllText(source, "MyForeverCoachDB = " + new string('{', 2000) + new string('}', 2000));
        var timer = Stopwatch.StartNew(); var result = await service.RefreshAsync(game); timer.Stop();
        Equal(5L, OneDay(result).Counts.CastSuccesses); Assert(result.Notices.Count > 0); Assert(timer.Elapsed < TimeSpan.FromSeconds(10)); PrivateNotices(result);
    });

    await Test("日时长、负计数和技能容量异常不会覆盖历史摘要", async () =>
    {
        var game = Game(); var source = Write(game, Modern()); var service = new BehaviorDataService(State()); await service.RefreshAsync(game);
        var invalidDays = new[] { DayData(observed: 100_000, combat: 0), DayData(successes: -1), DayData() };
        invalidDays[2]["spells"] = Enumerable.Range(1, 129).ToDictionary(n => n.ToString(System.Globalization.CultureInfo.InvariantCulture), n => (object?)D(("name", "测试技能"), ("succeeded", 1)));
        foreach (var invalidDay in invalidDays)
        {
            var root = Modern();
            var behavior = (Dictionary<string, object?>)root["behavior"]!;
            behavior["days"] = D((Day, invalidDay));
            File.WriteAllText(source, Lua(root));
            var result = await service.RefreshAsync(game);
            Equal(5L, OneDay(result).Counts.CastSuccesses); Assert(result.Notices.Count > 0); PrivateNotices(result);
        }
    });

    await Test("现代日累计缺失必需字段时保留缓存，不把未知当完整零", async () =>
    {
        var game = Game(); var source = Write(game, Modern()); var service = new BehaviorDataService(State()); await service.RefreshAsync(game);
        foreach (var groupName in new[] { "time", "counts", "quality" })
        {
            var fieldNames = ((Dictionary<string, object?>)DayData()[groupName]!).Keys.ToArray();
            foreach (var field in fieldNames)
            {
                var day = DayData(); ((Dictionary<string, object?>)day[groupName]!).Remove(field);
                var root = Modern(); ((Dictionary<string, object?>)root["behavior"]!)["days"] = D((Day, day));
                File.WriteAllText(source, Lua(root)); var result = await service.RefreshAsync(game); var kept = OneDay(result);
                Equal(250L, kept.Counts.XpGained, "Missing modern field replaced valid cached statistics: " + groupName + "." + field);
                Equal(5L, kept.Counts.CastSuccesses); Close(100, kept.Counts.CollectedSeconds); Assert(result.Notices.Count > 0); PrivateNotices(result);
            }
        }
    });

    await Test("已取消的刷新及时结束", async () =>
    {
        var game = Game(); Write(game, Modern()); using var token = new CancellationTokenSource(); token.Cancel();
        try { await new BehaviorDataService(State()).RefreshAsync(game, token.Token); throw new Exception("Cancelled refresh unexpectedly completed."); }
        catch (OperationCanceledException) { }
    });


    Dictionary<string, object?> ModernDay(Dictionary<string, object?> root) =>
        (Dictionary<string, object?>)((Dictionary<string, object?>)((Dictionary<string, object?>)root["behavior"]!)["days"]!)[Day]!;
    BehaviorDay Synthetic(string date, double hours, long combats, long deaths, long xp, long successes = 0, long failures = 0, long interrupts = 0,
        bool detail = true, params BehaviorZone[] zones)
    {
        var day = new BehaviorDay { Date = date, HasZoneDetail = detail, Counts = new()
        {
            CollectedSeconds = hours * 3600, CombatSeconds = hours * 1800, NonCombatSeconds = hours * 1800,
            CombatEntries = combats, CombatsCompleted = combats, Deaths = deaths, XpGained = xp,
            CastSuccesses = successes, CastFailures = failures, CastInterruptions = interrupts
        } };
        if (successes + failures + interrupts > 0)
            day.Spells.Add(new() { SpellId = 639, Name = "圣光术", Successes = successes, Failures = failures, Interrupted = interrupts });
        day.Zones.AddRange(zones);
        return day;
    }
    bool Has(BehaviorAnalysis analysis, string title) => analysis.Insights.Any(i => i.Title == title);
    BehaviorInsight Find(BehaviorAnalysis analysis, string title) => analysis.Insights.Single(i => i.Title == title);

    await Test("区域经验/死亡/战斗与中断次数从 0.2.1 日记录导入，旧日记录不标为区域明细", async () =>
    {
        var game = Game(); var data = Modern(); var day = ModernDay(data);
        day["version"] = 2;
        var map = (Dictionary<string, object?>)((Dictionary<string, object?>)day["maps"]!)["1426"]!;
        map["xp"] = 250; map["deaths"] = 1; map["combats"] = 3;
        Write(game, data);
        var imported = OneDay(await new BehaviorDataService(State()).RefreshAsync(game));
        Assert(imported.HasZoneDetail, "version 2 day should carry zone detail");
        var zone = imported.Zones.Single();
        Equal(250L, zone.XpGained); Equal(1L, zone.Deaths); Equal(3L, zone.CombatEntries);
        Equal(1L, imported.Counts.CastInterruptions);
        var older = Game(); Write(older, Modern());
        var old = OneDay(await new BehaviorDataService(State()).RefreshAsync(older));
        Assert(!old.HasZoneDetail, "a day without version must not be treated as complete zone detail");
        Equal(0L, old.Zones.Single().XpGained);
    });

    await Test("规则分析：样本不足只提示积累记录，不给结论", async () =>
    {
        var analysis = BehaviorInsights.Analyze([Synthetic("2026-11-11", 10.0 / 60, 2, 0, 100)], null);
        Assert(Has(analysis, "记录还比较少") && Find(analysis, "记录还比较少").LowSample);
        Assert(!Has(analysis, "死亡偏多") && !Has(analysis, "零死亡"));
        Assert(analysis.Current.DeathsPer100Combats is null, "fewer than 10 combats has no death rate");
        Assert(analysis.Current.CastFailureRate is null, "no casts has no failure rate");
        await Task.CompletedTask;
    });

    await Test("规则分析：死亡偏多和技能失败附带数字并排在前面，不使用误操作或挂机措辞", async () =>
    {
        var analysis = BehaviorInsights.Analyze([Synthetic("2026-11-11", 2, 40, 6, 20000, 30, 15, 1)], null);
        var deaths = Find(analysis, "死亡偏多");
        Equal(InsightTone.Attention, deaths.Tone);
        Assert(deaths.Evidence.Contains("40 场战斗、6 次死亡", StringComparison.Ordinal) && deaths.Evidence.Contains("15", StringComparison.Ordinal), deaths.Evidence);
        var spells = Find(analysis, "部分技能失败事件较多");
        Assert(spells.Evidence.Contains("圣光术 失败 15/45（33%）", StringComparison.Ordinal), spells.Evidence);
        Equal(InsightTone.Attention, analysis.Insights[0].Tone);
        foreach (var insight in analysis.Insights)
            Assert(!(insight.Title + insight.Evidence + insight.Suggestion).Contains("误操作", StringComparison.Ordinal)
                && !(insight.Title + insight.Evidence + insight.Suggestion).Contains("挂机", StringComparison.Ordinal), insight.Title);
        Close(15, analysis.Current.DeathsPer100Combats ?? -1);
        Close(10000, analysis.Current.XpPerHour ?? -1);
        Close(1.0 / 3, analysis.Current.CastFailureRate ?? -1);
        await Task.CompletedTask;
    });

    await Test("规则分析：与上一周期对比和零死亡", async () =>
    {
        var current = new[] { Synthetic("2026-11-11", 2, 40, 0, 30000) };
        var previous = new[] { Synthetic("2026-11-04", 2, 40, 0, 20000) };
        var analysis = BehaviorInsights.Analyze(current, previous, "最近 7 天", "前 7 天");
        var better = Find(analysis, "练级效率提升");
        Assert(better.Evidence.Contains("10,000 → 15,000", StringComparison.Ordinal) && better.Evidence.Contains("+50%", StringComparison.Ordinal), better.Evidence);
        Assert(Has(analysis, "零死亡"));
        Assert(!Has(analysis, "练级效率下降"));
        var worse = BehaviorInsights.Analyze(previous, current, "最近 7 天", "前 7 天");
        Assert(Has(worse, "练级效率下降"));
        var shortPrevious = BehaviorInsights.Analyze(current, [Synthetic("2026-11-04", 0.5, 10, 0, 1000)], "最近 7 天", "前 7 天");
        Assert(!Has(shortPrevious, "练级效率提升"), "a comparison period under one hour is not compared");
        var faster = BehaviorInsights.Analyze([Synthetic("2026-11-11", 2, 40, 0, 20000)], [Synthetic("2026-11-04", 2, 20, 0, 20000)]);
        Assert(!Find(faster, "单场战斗更快").Suggestion.Contains("击杀速度提升", StringComparison.Ordinal), "completed combat is not a kill counter");
        await Task.CompletedTask;
    });

    await Test("规则分析：区域效率只用完整区域明细的日期", async () =>
    {
        BehaviorZone Zone(long id, string name, double hours, long xp, long deaths = 0) =>
            new() { MapId = id, Name = name, Seconds = hours * 3600, Visits = 1, XpGained = xp, Deaths = deaths };
        var detail = Synthetic("2026-11-11", 2, 40, 0, 40000, detail: true, zones: [Zone(1426, "丹莫罗", 1, 30000), Zone(1429, "艾尔文森林", 1, 10000)]);
        var analysis = BehaviorInsights.Analyze([detail], null);
        Equal(1, analysis.ZoneDetailDays);
        Close(30000, analysis.Zones.Single(z => z.MapId == 1426).XpPerHour ?? -1);
        Assert(Find(analysis, "不同区域的练级效率差别明显").Evidence.Contains("丹莫罗 每小时约 30,000 经验", StringComparison.Ordinal));
        var legacy = Synthetic("2026-11-11", 2, 40, 0, 40000, detail: false, zones: [Zone(1426, "丹莫罗", 1, 30000), Zone(1429, "艾尔文森林", 1, 10000)]);
        var old = BehaviorInsights.Analyze([legacy], null);
        Equal(0, old.ZoneDetailDays);
        Assert(old.Zones.All(z => z.XpPerHour is null) && !Has(old, "不同区域的练级效率差别明显"), "zones without detail must not be compared");
        await Task.CompletedTask;
    });

    await Test("AI 摘要只含汇总数字，不含路径、账号、角色目录或哈希标识", async () =>
    {
        var game = Game(); Write(game, Modern());
        var dashboard = await new BehaviorDataService(State()).RefreshAsync(game);
        var character = dashboard.Characters.Single();
        var analysis = BehaviorInsights.Analyze(character.Days, null, "全部日期");
        var question = "为什么\u0007我练级慢" + new string('慢', 400);
        var summary = BehaviorAiCoach.BuildSummary(analysis, dashboard.Characters, question);
        foreach (var token in new[] { suiteDirectory, game, "FixtureAccount", "FixtureRealm", "FixtureCharacter", character.Id, "WTF", "SavedVariables" })
            Assert(!summary.Contains(token, StringComparison.OrdinalIgnoreCase), "AI summary exposed " + token);
        Assert(summary.Contains("圣骑士", StringComparison.Ordinal) && summary.Contains("圣光术", StringComparison.Ordinal) && summary.Contains("丹莫罗", StringComparison.Ordinal));
        Assert(!summary.Contains('\u0007'), "control characters are removed from the question");
        Equal(BehaviorAiCoach.MaxQuestionLength, BehaviorAiCoach.CleanQuestion(question).Length);
        using var json = JsonDocument.Parse(summary[summary.IndexOf('{')..]);
        Equal(9L, json.RootElement.GetProperty("characters")[0].GetProperty("level").GetInt64());
        Equal(5L, json.RootElement.GetProperty("current").GetProperty("castSuccesses").GetInt64());
    });

    await Test("AI 接口地址：外网必须 https，http 只允许本机", async () =>
    {
        Equal("https://api.deepseek.com/chat/completions", BehaviorAiCoach.ChatEndpoint("https://api.deepseek.com").ToString());
        Equal("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", BehaviorAiCoach.ChatEndpoint("https://dashscope.aliyuncs.com/compatible-mode/v1/").ToString());
        Equal("https://example.com/v1/chat/completions", BehaviorAiCoach.ChatEndpoint("https://example.com/v1/chat/completions").ToString());
        Equal("http://127.0.0.1:11434/v1/chat/completions", BehaviorAiCoach.ChatEndpoint("http://127.0.0.1:11434/v1").ToString());
        foreach (var bad in new[] { "", "api.deepseek.com", "http://example.com/v1", "https://user:pass@example.com/v1", "ftp://example.com", "https://example.com/v1?key=1" })
        {
            var rejected = false;
            try { BehaviorAiCoach.ChatEndpoint(bad); } catch (BehaviorAiException) { rejected = true; }
            Assert(rejected, "endpoint should be rejected: " + bad);
        }
        await Task.CompletedTask;
    });

    await Test("AI 请求使用 OpenAI 兼容格式并清理回复（本地桩，不联网）", async () =>
    {
        var stub = new StubHandler(HttpStatusCode.OK, """{"choices":[{"message":{"role":"assistant","content":"<think>内部推理</think>## 【一句话总结】\n**节奏稳定**"}}]}""");
        var settings = new BehaviorAiSettings { Enabled = true, Endpoint = "https://ai.example.test/v1", Model = "fixture-model", ApiKey = "sk-fixture" };
        var answer = await BehaviorAiCoach.AskAsync(settings, "用户摘要", stub);
        Equal("【一句话总结】\n节奏稳定", answer);
        Equal("https://ai.example.test/v1/chat/completions", stub.Url);
        Equal("Bearer sk-fixture", stub.Authorization);
        using var body = JsonDocument.Parse(stub.Body);
        Equal("fixture-model", body.RootElement.GetProperty("model").GetString()!);
        Equal("system", body.RootElement.GetProperty("messages")[0].GetProperty("role").GetString()!);
        Equal("用户摘要", body.RootElement.GetProperty("messages")[1].GetProperty("content").GetString()!);

        var denied = new StubHandler(HttpStatusCode.Unauthorized, """{"error":{"message":"invalid key sk-fixture"}}""");
        var message = "";
        try { await BehaviorAiCoach.AskAsync(settings, "用户摘要", denied); } catch (BehaviorAiException e) { message = e.Message; }
        Assert(message.Contains("API Key 无效", StringComparison.Ordinal) && !message.Contains("sk-fixture", StringComparison.Ordinal), message);

        var garbage = new StubHandler(HttpStatusCode.OK, "<html>not json</html>");
        message = "";
        try { await BehaviorAiCoach.AskAsync(settings, "用户摘要", garbage); } catch (BehaviorAiException e) { message = e.Message; }
        Assert(message.Length > 0, "an unrecognised reply is reported");

        var missingKey = "";
        try { await BehaviorAiCoach.AskAsync(new BehaviorAiSettings { Endpoint = "https://ai.example.test/v1", Model = "m" }, "x", stub); }
        catch (BehaviorAiException e) { missingKey = e.Message; }
        Assert(missingKey.Contains("API Key", StringComparison.Ordinal), "remote endpoints require a key");
    });

    await Test("AI 设置：未勾选保存密钥时不写入磁盘", async () =>
    {
        var state = State(); var store = new BehaviorAiSettingsStore(state);
        store.Save(new BehaviorAiSettings { Enabled = true, Provider = "qwen", Endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1", Model = "qwen-plus", ApiKey = "sk-not-saved" });
        var file = Path.Combine(state, "behavior-ai.json");
        Assert(!File.ReadAllText(file).Contains("sk-not-saved", StringComparison.Ordinal), "key written without consent");
        var loaded = store.Load();
        Assert(loaded.Enabled); Equal("qwen", loaded.Provider); Equal("", loaded.ApiKey);
        store.Save(new BehaviorAiSettings { Enabled = true, Provider = "unknown-provider", Endpoint = "https://x.test/v1", Model = "m", ApiKey = "sk-saved", RememberKey = true });
        loaded = store.Load();
        Equal("sk-saved", loaded.ApiKey); Equal("custom", loaded.Provider);
        File.WriteAllText(file, "{ not json");
        Assert(!store.Load().Enabled, "a damaged settings file falls back to disabled");
        await Task.CompletedTask;
    });

    await Test("AI 本机接口重定向不转发摘要到未选地址", async () =>
    {
        await using var server = new LoopbackAiServer();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var message = "";
        try
        {
            await BehaviorAiCoach.AskAsync(new BehaviorAiSettings
            { Enabled = true, Endpoint = server.BaseUrl + "/v1", Model = "fixture" }, "synthetic summary", cancellationToken: deadline.Token);
        }
        catch (BehaviorAiException e) { message = e.Message; }
        Equal(1, server.Requests, "AI summary followed a redirect away from the selected endpoint");
        Assert(message.Contains("307", StringComparison.Ordinal), "redirect must be reported as a non-success response");
    });

    await Test("AI 预设与 DeepSeek 短复盘参数保持兼容，其他接口不加专用字段", async () =>
    {
        Equal("deepseek-flash", BehaviorAiPresets.Default.Model);
        var stub = new StubHandler(HttpStatusCode.OK, """{"choices":[{"message":{"content":"fixture"}}]}""");
        var settings = new BehaviorAiSettings { Enabled = true, Endpoint = "https://api.deepseek.com", Model = "deepseek-flash", ApiKey = "fixture" };
        await BehaviorAiCoach.AskAsync(settings, "summary", stub);
        using var body = JsonDocument.Parse(stub.Body);
        Equal("disabled", body.RootElement.GetProperty("thinking").GetProperty("type").GetString()!);
        settings.Endpoint = "https://other.example.test/v1";
        await BehaviorAiCoach.AskAsync(settings, "summary", stub);
        using var generic = JsonDocument.Parse(stub.Body);
        Assert(!generic.RootElement.TryGetProperty("thinking", out _), "provider-specific parameters leaked into a generic endpoint");
    });

    await Test("AI 接收回复正文时仍可取消，过大正文停止读取", async () =>
    {
        var settings = new BehaviorAiSettings { Enabled = true, Endpoint = "http://127.0.0.1:11434/v1", Model = "fixture" };
        using var token = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));
        var cancelled = false;
        try { await BehaviorAiCoach.AskAsync(settings, "summary", new StalledBodyHandler(), token.Token); }
        catch (OperationCanceledException) { cancelled = true; }
        Assert(cancelled, "cancellation after response headers must reach the body reader");
        var message = "";
        try { await BehaviorAiCoach.AskAsync(settings, "summary", new StubHandler(HttpStatusCode.OK, new string('x', 512 * 1024 + 1))); }
        catch (BehaviorAiException e) { message = e.Message; }
        Assert(message.Contains("过大", StringComparison.Ordinal), "oversized response must fail safely");
    });

    var sampleIndex = Array.IndexOf(args, "--legacy-sample");
    if (sampleIndex >= 0)
    {
        if (sampleIndex + 1 >= args.Length) throw new ArgumentException("--legacy-sample requires the existing anonymous session JSON path.");
        await Test("既有匿名真实会话只按已保存 records 还原", async () =>
        {
            var sample = Path.GetFullPath(args[sampleIndex + 1]);
            Assert(!sample.Split(Path.DirectorySeparatorChar).Contains("WTF", StringComparer.OrdinalIgnoreCase), "Only anonymous validation JSON may be supplied; never live WTF.");
            using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(sample)); var session = doc.RootElement.Clone();
            var records = session.GetProperty("records").EnumerateArray().ToArray();
            var successes = records.Count(record => record.GetProperty("kind").GetString() == "player_cast" && record.GetProperty("data").TryGetProperty("event", out var ev) && ev.GetString() == "UNIT_SPELLCAST_SUCCEEDED");
            var deaths = records.Count(record => record.GetProperty("kind").GetString() == "death" && record.GetProperty("data").TryGetProperty("event", out var ev) && ev.GetString() == "PLAYER_DEAD");
            var combats = records.Count(record => record.GetProperty("kind").GetString() == "combat" && record.GetProperty("data").TryGetProperty("phase", out var phase) && phase.GetString() == "enter");
            var game = Game(); Write(game, Legacy(session)); var days = (await new BehaviorDataService(State()).RefreshAsync(game)).Characters.Single().Days;
            Equal((long)successes, days.Sum(day => day.Counts.CastSuccesses)); Equal((long)deaths, days.Sum(day => day.Counts.Deaths)); Equal((long)combats, days.Sum(day => day.Counts.CombatEntries));
            if (session.GetProperty("id").GetString() == "1794108823-9") Equal(92L, days.Sum(day => day.Counts.XpGained));
            Assert(days.All(day => day.IsPartial && day.HasLegacyData));
        });
    }

    var currentSampleIndex = Array.IndexOf(args, "--current-sample");
    if (currentSampleIndex >= 0)
    {
        if (currentSampleIndex + 1 >= args.Length) throw new ArgumentException("--current-sample requires the simulated addon Lua path with its adjacent .expected.json.");
        await Test("当前插件真实输出格式端到端导入且1200条明细与session标记不双算", async () =>
        {
            var sample = Path.GetFullPath(args[currentSampleIndex + 1]);
            Assert(!sample.Split(Path.DirectorySeparatorChar).Contains("WTF", StringComparer.OrdinalIgnoreCase), "Only a simulated validation fixture may be supplied; never live WTF.");
            using var expectedDoc = JsonDocument.Parse(await File.ReadAllTextAsync(Path.ChangeExtension(sample, ".expected.json")));
            var expected = expectedDoc.RootElement; var times = expected.GetProperty("time"); var counts = expected.GetProperty("counts");
            Equal(1200, expected.GetProperty("recordCount").GetInt32()); Assert(expected.GetProperty("sessionMarker").GetProperty("daily").GetBoolean());
            var game = Game(); var source = Source(game); Directory.CreateDirectory(Path.GetDirectoryName(source)!); File.Copy(sample, source);
            var before = await File.ReadAllBytesAsync(source); var state = State();
            var result = await new BehaviorDataService(state).RefreshAsync(game); var day = OneDay(result);
            Equal(expected.GetProperty("date").GetString()!, day.Date);
            Close(times.GetProperty("observedSeconds").GetDouble(), day.Counts.CollectedSeconds);
            Close(times.GetProperty("combatSeconds").GetDouble(), day.Counts.CombatSeconds);
            Close(times.GetProperty("nonCombatSeconds").GetDouble(), day.Counts.NonCombatSeconds);
            Close(times.GetProperty("unknownCombatSeconds").GetDouble(), day.Counts.UnknownCombatSeconds);
            Equal(counts.GetProperty("castsSucceeded").GetInt64(), day.Counts.CastSuccesses);
            Equal(counts.GetProperty("castsFailed").GetInt64(), day.Counts.CastFailures);
            Equal(counts.GetProperty("castsInterrupted").GetInt64(), day.Spells.Sum(spell => spell.Interrupted));
            Equal(counts.GetProperty("combatsEntered").GetInt64(), day.Counts.CombatEntries);
            Equal(counts.GetProperty("combatsCompleted").GetInt64(), day.Counts.CombatsCompleted);
            Equal(counts.GetProperty("deaths").GetInt64(), day.Counts.Deaths);
            Equal(counts.GetProperty("questsAccepted").GetInt64(), day.Counts.QuestsAccepted);
            Equal(counts.GetProperty("questsTurnedIn").GetInt64(), day.Counts.QuestsTurnedIn);
            Equal(counts.GetProperty("xpGained").GetInt64(), day.Counts.XpGained);
            Equal(counts.GetProperty("levelsGained").GetInt64(), day.Counts.LevelsGained);
            Equal(expected.GetProperty("quality").GetProperty("detailDropped").GetInt64(), day.DetailDropped);
            Assert(day.IsPartial && !day.HasLegacyData); Close(day.Counts.CollectedSeconds, day.Zones.Sum(zone => zone.Seconds));
            var after = await File.ReadAllBytesAsync(source);
            Assert(before.SequenceEqual(after), "The import changed the current addon fixture.");
            var restarted = OneDay(await new BehaviorDataService(state).RefreshAsync(game));
            Equal(day.Counts.CastSuccesses, restarted.Counts.CastSuccesses); Equal(day.Counts.XpGained, restarted.Counts.XpGained); Close(day.Counts.CollectedSeconds, restarted.Counts.CollectedSeconds);
        });
    }
}
finally
{
    // Remove only this suite's unique temporary fixtures; production files are never read or changed.
    try { Directory.Delete(suiteDirectory, true); } catch (IOException) { }
}
Console.WriteLine($"Behavior tests: {passed} passed, {failed} failed.");
return failed == 0 ? 0 : 1;

internal sealed class StubHandler(HttpStatusCode status, string reply) : HttpMessageHandler
{
    public string Url { get; private set; } = "";
    public string Authorization { get; private set; } = "";
    public string Body { get; private set; } = "";
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Url = request.RequestUri?.ToString() ?? "";
        Authorization = request.Headers.Authorization?.ToString() ?? "";
        Body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
        return new HttpResponseMessage(status) { Content = new StringContent(reply, System.Text.Encoding.UTF8, "application/json") };
    }
}

internal sealed class StalledBodyHandler : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
        Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(new StalledBodyStream()) });
}

internal sealed class StalledBodyStream : Stream
{
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    { await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken); return 0; }
    public override void Flush() => throw new NotSupportedException();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
