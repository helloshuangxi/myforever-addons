namespace MyForeverManager.Core;

public sealed class BehaviorDashboard
{
    public DateTimeOffset RefreshedAt { get; set; }
    public DateTimeOffset? LatestSavedAt { get; set; }
    public bool IsGameRunning { get; set; }
    public bool CollectorInstalled { get; set; }
    public string? CollectorVersion { get; set; }
    public List<BehaviorCharacter> Characters { get; set; } = [];
    public List<string> Notices { get; set; } = [];
}
public sealed class BehaviorCharacter
{
    public string Id { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string Class { get; set; } = "";
    public int Level { get; set; }
    public List<BehaviorDay> Days { get; set; } = [];
}
public sealed class BehaviorDay
{
    public string Date { get; set; } = "";
    public BehaviorCounts Counts { get; set; } = new();
    public List<BehaviorSpell> Spells { get; set; } = [];
    public List<BehaviorZone> Zones { get; set; } = [];
    public bool IsPartial { get; set; }
    public bool HasLegacyData { get; set; }
    public long DetailDropped { get; set; }
}
public sealed class BehaviorCounts
{
    public double CollectedSeconds { get; set; }
    public double CombatSeconds { get; set; }
    public double NonCombatSeconds { get; set; }
    public double UnknownCombatSeconds { get; set; }
    public long CombatEntries { get; set; }
    public long CombatsCompleted { get; set; }
    public long Deaths { get; set; }
    public long CastSuccesses { get; set; }
    public long CastFailures { get; set; }
    public long QuestsAccepted { get; set; }
    public long QuestsTurnedIn { get; set; }
    public long XpGained { get; set; }
    public long LevelsGained { get; set; }
}
public sealed class BehaviorSpell
{
    public long SpellId { get; set; }
    public string Name { get; set; } = "";
    public long Successes { get; set; }
    public long Failures { get; set; }
    public long Interrupted { get; set; }
}
public sealed class BehaviorZone
{
    public long MapId { get; set; }
    public string Name { get; set; } = "";
    public double Seconds { get; set; }
    public long Visits { get; set; }
}
