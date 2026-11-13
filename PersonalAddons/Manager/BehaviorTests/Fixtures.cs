using System.Globalization;
using System.Text.Json;

internal static class Fixtures
{
    public const string Day = "2026-11-11";
    public static readonly long StartedAt = DateTimeOffset.Parse("2026-11-11T10:00:00+08:00", CultureInfo.InvariantCulture).ToUnixTimeSeconds();
    public static Dictionary<string, object?> D(params (string Key, object? Value)[] pairs) => pairs.ToDictionary(p => p.Key, p => p.Value);

    public static object Character(string className = "PALADIN", int level = 9) => D(("class", className), ("level", level), ("race", "Dwarf"));

    public static Dictionary<string, object?> DayData(long successes = 5, double observed = 100, double combat = 40, long xp = 250) => D(
        ("time", D(("observedSeconds", observed), ("combatSeconds", combat), ("nonCombatSeconds", observed - combat), ("pausedSeconds", 0), ("unknownCombatSeconds", 0))),
        ("counts", D(("combatsEntered", 3), ("combatsCompleted", 2), ("deaths", 1), ("castsStarted", successes + 3), ("castsSucceeded", successes),
            ("castsFailed", 2), ("castsInterrupted", 1), ("questsAccepted", 4), ("questsTurnedIn", 2), ("levelsGained", 1), ("xpGained", xp))),
        ("spells", D(("639", D(("name", "圣光术"), ("succeeded", successes), ("failed", 2), ("interrupted", 1))))),
        ("maps", D(("1426", D(("name", "丹莫罗"), ("seconds", observed), ("visits", 2))))),
        ("quality", D(("xpGaps", 0), ("unknownMapSeconds", 0), ("detailDropped", 0))));

    public static Dictionary<string, object?> Modern(long successes = 5, string generation = "fixture-generation", string date = Day, params object[] legacySessions)
    {
        var day = DayData(successes);
        var modernSession = D(("id", "modern-diagnostic-session"), ("schema", 1), ("version", "0.2.0"), ("startedAt", StartedAt),
            ("duration", 100), ("character", Character()), ("behavior", day),
            ("records", new[] { Record(1, "player_cast", D(("event", "UNIT_SPELLCAST_SUCCEEDED"), ("spellID", 639))) }));
        return D(("schema", 1), ("sessions", legacySessions.Append(modernSession).ToArray()),
            ("behavior", D(("schema", 1), ("generation", generation), ("dayBasis", "UTC+08:00"),
                ("createdAt", StartedAt), ("updatedAt", StartedAt + 100), ("days", D((date, day))))));
    }

    public static Dictionary<string, object?> Record(double time, string kind, object data, string context = "idle") =>
        D(("t", time), ("kind", kind), ("context", context), ("data", data));

    public static Dictionary<string, object?> Cast(double time, string eventName, int spell = 639) =>
        Record(time, "player_cast", D(("event", eventName), ("spellID", spell)));

    public static Dictionary<string, object?> Snapshot(double time, int xp, int level = 9, int xpMax = 1000, bool? combat = null)
    {
        var data = D(("level", level), ("xp", xp), ("xpMax", xpMax), ("mapID", 1426));
        if (combat.HasValue) data["combat"] = combat.Value;
        return Record(time, "snapshot", data, combat == true ? "combat" : "idle");
    }

    public static Dictionary<string, object?> Session(string id, object[] records, long? startedAt = null, double duration = 3600, long dropped = 0) => D(
        ("id", id), ("schema", 1), ("version", "0.1.2"), ("startedAt", startedAt ?? StartedAt), ("duration", duration),
        ("endedAt", (startedAt ?? StartedAt) + duration), ("character", Character()), ("records", records), ("dropped", dropped),
        ("receivedEvents", D(("UNIT_SPELLCAST_SUCCEEDED", 99999), ("PLAYER_DEAD", 99999), ("PLAYER_REGEN_DISABLED", 99999))),
        ("eventCounts", D(("UNIT_SPELLCAST_SUCCEEDED", 88888))),
        ("capabilities", D(("spellID", D(("available", 77777), ("restricted", 222))))));

    public static object Legacy(params object[] sessions) => D(("schema", 1), ("sessions", sessions));

    public static string Lua(object data) => "MyForeverCoachDB = " + Encode(JsonSerializer.SerializeToElement(data)) + "\n";

    private static string Encode(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Object => "{\n" + string.Join(",\n", value.EnumerateObject().Select(p =>
            "[" + (long.TryParse(p.Name, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n.ToString(CultureInfo.InvariantCulture) : Quote(p.Name)) + "] = " + Encode(p.Value))) + "\n}",
        JsonValueKind.Array => "{\n" + string.Join(",\n", value.EnumerateArray().Select(Encode)) + "\n}",
        JsonValueKind.String => Quote(value.GetString()!),
        JsonValueKind.Number => value.GetRawText(),
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        JsonValueKind.Null => "nil",
        _ => throw new InvalidOperationException("Fixture cannot serialize this JSON value.")
    };

    private static string Quote(string value) => "\"" + value.Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("\"", "\\\"", StringComparison.Ordinal).Replace("\n", "\\n", StringComparison.Ordinal)
        .Replace("\r", "\\r", StringComparison.Ordinal).Replace("\t", "\\t", StringComparison.Ordinal) + "\"";
}
