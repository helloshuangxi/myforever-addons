using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace MyForeverManager.Core;

public static class ManagerVersion
{
    public const string Current = "0.4.0";
}

public record AddonDefinition(string Id, string DisplayName, string Description, string ManifestUrl);

public static class AddonCatalog
{
    public static IReadOnlyList<AddonDefinition> All { get; } = new[]
    {
        new AddonDefinition("MyForeverChat", "微信式聊天", "把私聊、频道和社区群聊整理在熟悉的聊天窗口里。", "https://afabiaoge.xyz/latest.json"),
        new AddonDefinition("MyForeverProfessions", "商业技能助手", "查看专业进度、材料缺口与训练师，调整采集提示。", "https://afabiaoge.xyz/professions/latest.json"),
        new AddonDefinition("MyForeverNavigator", "世界向导", "查找声望军需官、材料商人与特殊 NPC，收藏地点并查看地图方向。", "https://afabiaoge.xyz/navigator/latest.json"),
        new AddonDefinition("MyForeverTargets", "目标选择", "集中查看友方、敌方及敌人的目标，显示血量与自身相关效果。", "https://afabiaoge.xyz/targets/latest.json")
    };

    public static AddonDefinition Require(AddonDefinition addon) =>
        All.FirstOrDefault(x => x == addon) ?? throw new InvalidDataException("不支持的插件或更新来源。");
}

public sealed class ManagerSettings
{
    public string GameDirectory { get; set; } = "";
    public bool AutoUpdate { get; set; } = true;
    public List<string> ManagedAddons { get; set; } = [];
}

public sealed class SettingsStore
{
    public string DirectoryPath { get; }
    public SettingsStore(string? directory = null) => DirectoryPath = PathSafety.Normalize(directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MyForeverManager"));
    public ManagerSettings Load()
    {
        var file = Path.Combine(DirectoryPath, "settings.json");
        if (!File.Exists(file)) return new();
        try
        {
            var value = JsonSerializer.Deserialize<ManagerSettings>(File.ReadAllText(file)) ?? new();
            value.GameDirectory ??= "";
            value.ManagedAddons = (value.ManagedAddons ?? []).Where(id => AddonCatalog.All.Any(a => a.Id == id)).Distinct().ToList();
            return value;
        }
        catch (JsonException) { throw new InvalidDataException("设置文件无法读取，请重新选择游戏目录。原文件保留在 " + file); }
    }
    public void Save(ManagerSettings settings)
    {
        PathSafety.AssertNoLinks(DirectoryPath);
        Directory.CreateDirectory(DirectoryPath);
        var file = Path.Combine(DirectoryPath, "settings.json");
        PathSafety.AssertNoLinks(file);
        var temp = Path.Combine(DirectoryPath, "settings-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, file, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}

public sealed class ReleaseManifest
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; }
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("version")] public string Version { get; set; } = "";
    [JsonPropertyName("channel")] public string Channel { get; set; } = "";
    [JsonPropertyName("published_at")] public string PublishedAt { get; set; } = "";
    [JsonPropertyName("changes")] public List<string> Changes { get; set; } = [];
    [JsonPropertyName("validation")] public List<string> Validation { get; set; } = [];
    [JsonPropertyName("compatibility")] public ReleaseCompatibility Compatibility { get; set; } = new();
    [JsonPropertyName("download")] public ReleaseDownload Download { get; set; } = new();
}
public sealed class ReleaseCompatibility
{
    [JsonPropertyName("product")] public string Product { get; set; } = "";
    [JsonPropertyName("client")] public string Client { get; set; } = "";
    [JsonPropertyName("interface")] public int Interface { get; set; }
}
public sealed class ReleaseDownload
{
    [JsonPropertyName("url")] public string Url { get; set; } = "";
    [JsonPropertyName("filename")] public string Filename { get; set; } = "";
    [JsonPropertyName("size_bytes")] public long SizeBytes { get; set; }
    [JsonPropertyName("sha256")] public string Sha256 { get; set; } = "";
}
public record AddonStatus(AddonDefinition Addon, string? InstalledVersion, ReleaseManifest? Latest, string? Error)
{
    public bool CanInstall => Error is null && Latest is not null && (InstalledVersion is null || Versions.Compare(Latest.Version, InstalledVersion) > 0);
}
public static class Versions
{
    public static Version Parse(string version)
    {
        if (string.IsNullOrWhiteSpace(version) || !Regex.IsMatch(version, @"^\d{1,8}\.\d{1,8}\.\d{1,8}(?:\.\d{1,8})?$", RegexOptions.CultureInvariant) || !Version.TryParse(version, out var result))
            throw new InvalidDataException("无法识别插件版本号：" + version);
        return new Version(result.Major, result.Minor, result.Build, Math.Max(result.Revision, 0));
    }
    public static int Compare(string left, string right) => Parse(left).CompareTo(Parse(right));
}
