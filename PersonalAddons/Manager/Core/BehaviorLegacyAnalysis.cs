using static MyForeverManager.Core.BehaviorDataService;

namespace MyForeverManager.Core;

// Old diagnostic sessions are fragments, not complete histories. Count literal
// player records only, and estimate time only between nearby observed records.
internal static class BehaviorLegacyAnalysis
{
    internal static List<BehaviorDay> Read(Dictionary<string, object?> session, CancellationToken token)
    {
        var raw = D(session, "records");
        if (raw.Count > 20_000) throw new InvalidDataException();
        var records = Items(raw).ToList();
        if (records.Count == 0) return [];
        var epoch = N(session, "startedAt");
        _ = DayAt(epoch);
        var days = new Dictionary<string, BehaviorDay>(StringComparer.Ordinal);
        BehaviorDay Day(double elapsed)
        {
            var date = DayAt(epoch + elapsed);
            if (!days.TryGetValue(date, out var day))
                days[date] = day = new() { Date = date, HasLegacyData = true, IsPartial = true };
            return day;
        }
        bool active = true, dead = false;
        bool? combat = null;
        double? previousTime = null;
        long? mapId = null, xp = null, xpMax = null, xpLevel = null, countedLevel = null;
        BehaviorZone Zone(BehaviorDay day, long id)
        {
            var zone = day.Zones.Find(z => z.MapId == id);
            if (zone is null) day.Zones.Add(zone = new() { MapId = id });
            return zone;
        }
        void Interval(double start, double end)
        {
            while (start < end)
            {
                var day = Day(start);
                var boundary = DateTimeOffset.ParseExact(day.Date + "T00:00:00+08:00", "yyyy-MM-dd'T'HH:mm:sszzz", System.Globalization.CultureInfo.InvariantCulture).AddDays(1).ToUnixTimeSeconds() - epoch;
                var next = Math.Min(end, boundary);
                var seconds = next - start;
                if (seconds <= 0) throw new InvalidDataException();
                day.Counts.CollectedSeconds += seconds;
                if (combat is true) day.Counts.CombatSeconds += seconds;
                else if (combat is false) day.Counts.NonCombatSeconds += seconds;
                else day.Counts.UnknownCombatSeconds += seconds;
                if (mapId is { } id) Zone(day, id).Seconds += seconds;
                start = next;
            }
        }
        foreach (var record in records)
        {
            token.ThrowIfCancellationRequested();
            var elapsed = N(record, "t");
            if (elapsed > 30 * 86_400 || (previousTime.HasValue && elapsed < previousTime.Value)) throw new InvalidDataException();
            if (previousTime is { } prior && active && elapsed - prior <= 15) Interval(prior, elapsed);
            var day = Day(elapsed); var counts = day.Counts;
            var data = D(record, "data"); var kind = S(record, "kind");
            previousTime = elapsed;
            if (kind == "pause")
            {
                active = data.GetValueOrDefault("enabled") is true;
                xp = xpMax = xpLevel = countedLevel = null; mapId = null; combat = null;
                continue;
            }
            if (!active) continue;
            if (kind == "combat")
            {
                var phase = S(data, "phase");
                if (phase == "enter" && combat is not true) counts.CombatEntries++;
                if (phase == "leave" && combat is true) counts.CombatsCompleted++;
                if (phase == "enter") combat = true;
                if (phase == "leave") combat = false;
            }
            // Only explicit public state gives a noncombat classification;
            // instance/PvP context strings alone do not imply either state.
            if (data.GetValueOrDefault("combat") is bool state) combat = state;
            else if (S(record, "context") == "combat") combat = true;
            if (kind == "player_cast")
            {
                var eventName = S(data, "event");
                var id = L(data, "spellID");
                if (id <= 0 || id > int.MaxValue) continue;
                if (eventName is not ("UNIT_SPELLCAST_SUCCEEDED" or "UNIT_SPELLCAST_FAILED" or "UNIT_SPELLCAST_INTERRUPTED")) continue;
                var spell = day.Spells.Find(s => s.SpellId == id);
                if (spell is null) day.Spells.Add(spell = new() { SpellId = id });
                if (eventName == "UNIT_SPELLCAST_SUCCEEDED") { counts.CastSuccesses++; spell.Successes++; }
                if (eventName == "UNIT_SPELLCAST_FAILED") { counts.CastFailures++; spell.Failures++; }
                if (eventName == "UNIT_SPELLCAST_INTERRUPTED") spell.Interrupted++;
            }
            else if (kind == "death")
            {
                var eventName = S(data, "event");
                if (eventName == "PLAYER_DEAD" && !dead) { counts.Deaths++; dead = true; }
                if (eventName is "PLAYER_ALIVE" or "PLAYER_UNGHOST") dead = false;
            }
            else if (kind == "quest")
            {
                if (S(data, "event") == "QUEST_ACCEPTED") counts.QuestsAccepted++;
                if (S(data, "event") == "QUEST_TURNED_IN") counts.QuestsTurnedIn++;
            }
            else if (kind == "level")
            {
                var level = L(data, "level");
                if (level is > 0 and <= 1000)
                {
                    if (countedLevel is { } previousLevel && level > previousLevel) counts.LevelsGained += level - previousLevel;
                    else if (countedLevel is null) counts.LevelsGained++;
                    countedLevel = level;
                }
            }
            else if (kind == "snapshot")
            {
                var newMap = L(data, "mapID");
                if (newMap is > 0 and <= int.MaxValue)
                {
                    if (mapId != newMap) Zone(day, newMap).Visits++;
                    mapId = newMap;
                }
                else mapId = null;
                if (data.ContainsKey("level") && data.ContainsKey("xp") && data.ContainsKey("xpMax"))
                {
                    var level = L(data, "level"); var value = L(data, "xp"); var maximum = L(data, "xpMax");
                    if (level is > 0 and <= 1000 && value <= maximum && maximum > 0)
                    {
                        if (xp is { } oldXp && xpLevel is { } oldLevel && xpMax is { } oldMax)
                        {
                            if (level == oldLevel && value >= oldXp) counts.XpGained += value - oldXp;
                            else if (level == oldLevel + 1) counts.XpGained += oldMax - oldXp + value;
                        }
                        if (countedLevel is { } oldCounted && level > oldCounted) counts.LevelsGained += level - oldCounted;
                        countedLevel = level;
                        xp = value; xpMax = maximum; xpLevel = level;
                    }
                    else xp = xpMax = xpLevel = null;
                }
                else xp = xpMax = xpLevel = null;
            }
        }
        days.Values.Last().DetailDropped = L(session, "dropped");
        return days.Values.OrderBy(d => d.Date, StringComparer.Ordinal).ToList();
    }
}
