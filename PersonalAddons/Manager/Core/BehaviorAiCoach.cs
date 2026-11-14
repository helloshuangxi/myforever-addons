using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Text.Unicode;

namespace MyForeverManager.Core;

// Optional large-model review. Off by default and only runs when the player
// presses the button. The request carries the anonymous summary returned by
// BuildSummary (shown to the player first): no account, realm, character name,
// GUID, chat, key presses, file paths or raw SavedVariables.
public sealed class BehaviorAiSettings
{
    public bool Enabled { get; set; }
    public string Provider { get; set; } = BehaviorAiPresets.DefaultId;
    public string Endpoint { get; set; } = BehaviorAiPresets.Default.Endpoint;
    public string Model { get; set; } = BehaviorAiPresets.Default.Model;
    public bool RememberKey { get; set; }
    public string ApiKey { get; set; } = "";
}

public sealed record BehaviorAiPreset(string Id, string Label, string Endpoint, string Model, bool NeedsKey, string Note);

public static class BehaviorAiPresets
{
    public const string DefaultId = "deepseek";
    // Model names change over time; players can edit them. Values checked against provider docs 2026-11.
    public static readonly IReadOnlyList<BehaviorAiPreset> All =
    [
        new("deepseek", "DeepSeek", "https://api.deepseek.com", "deepseek-flash", true, "需要在 DeepSeek 开放平台创建 API Key，按用量计费。"),
        new("qwen", "通义千问（阿里云百炼）", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus", true, "需要在阿里云百炼创建 API Key，按用量计费。"),
        new("ollama", "本机模型（Ollama）", "http://127.0.0.1:11434/v1", "qwen3", false, "请求发到本机 Ollama；请使用已下载的本地模型，云端模型仍会联网。"),
        new("custom", "其他 OpenAI 兼容接口", "", "", true, "填写服务商提供的接口地址（通常以 /v1 结尾）、模型名称和密钥。")
    ];
    public static BehaviorAiPreset Default => All[0];
    public static BehaviorAiPreset Find(string id) => All.FirstOrDefault(p => p.Id == id) ?? All[All.Count - 1];
}

public sealed class BehaviorAiException(string message) : Exception(message);

public sealed class BehaviorAiSettingsStore(string stateDirectory)
{
    private const int MaxBytes = 64 * 1024;
    private readonly string path = Path.Combine(PathSafety.Normalize(stateDirectory), "behavior-ai.json");
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public BehaviorAiSettings Load()
    {
        try
        {
            PathSafety.AssertNoLinks(path);
            if (!File.Exists(path) || new FileInfo(path).Length > MaxBytes) return new();
            var value = JsonSerializer.Deserialize<BehaviorAiSettings>(File.ReadAllText(path, Encoding.UTF8)) ?? new();
            return Clean(value);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }

    public void Save(BehaviorAiSettings settings)
    {
        var clean = Clean(settings);
        var stored = new BehaviorAiSettings
        {
            Enabled = clean.Enabled, Provider = clean.Provider, Endpoint = clean.Endpoint, Model = clean.Model,
            RememberKey = clean.RememberKey, ApiKey = clean.RememberKey ? clean.ApiKey : ""
        };
        var directory = Path.GetDirectoryName(path)!;
        PathSafety.AssertNoLinks(path); Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, ".behavior-ai-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
            if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            using (var stream = new FileStream(temp, options))
            { var bytes = new UTF8Encoding(false).GetBytes(JsonSerializer.Serialize(stored, JsonOptions)); stream.Write(bytes); stream.Flush(true); }
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    private static BehaviorAiSettings Clean(BehaviorAiSettings value) => new()
    {
        Enabled = value.Enabled,
        Provider = BehaviorAiPresets.Find(value.Provider ?? "").Id,
        Endpoint = Limit(value.Endpoint, 512), Model = Limit(value.Model, 128),
        RememberKey = value.RememberKey, ApiKey = Limit(value.ApiKey, 512)
    };
    private static string Limit(string? value, int length)
    {
        var text = Regex.Replace(value ?? "", @"[\p{Cc}\p{Cf}]", "").Trim();
        return text.Length <= length ? text : text[..length];
    }
}

public static class BehaviorAiCoach
{
    public const int MaxQuestionLength = 200;
    private const int MaxResponseBytes = 512 * 1024, MaxAnswerLength = 8000;
    private static readonly JsonSerializerOptions SummaryJson = new()
    { WriteIndented = true, Encoder = JavaScriptEncoder.Create(UnicodeRanges.All) };

    public const string SystemPrompt = """
        你是国服《魔兽世界：无限》客户端玩家的游戏复盘教练。玩家会给你一份由本机插件统计出的匿名行为摘要（JSON）。请据此帮玩家找到最值得改进的地方。

        规则：
        1. 只依据摘要里的数字推理，不编造击杀数、输出量、装备、天赋或摘要里没有的事件。引用数字时与摘要保持一致。
        2. 口径：施法“失败”事件也包含冷却中重复按键等情况，不等于操作失误；“非战斗时间”包括跑路、在城里、休息和离开键盘，不等于挂机；“中断”包括读条时移动。
        3. lowSample 为 true、采集时长不足 30 分钟或 hasLegacyData/isPartial 为 true 时，要明确说明结论参考性有限。
        4. 该客户端的版本和机制可能与其他魔兽版本不同。不确定是否存在的技能、天赋或物品不要点名，给通用、稳妥、可操作的建议。
        5. 区域效率只对 zones 中有 xpPerHour 的区域比较；没有的不要推算。
        6. 若玩家提出了关注的问题，优先回答它。

        输出中文纯文本，不用 Markdown 符号或表格，严格按以下结构，总共不超过 600 字：
        【一句话总结】
        【做得好的】1～2 条
        【最值得改进】最多 3 条，每条写：现象（引用数据）→ 可能原因（标明是推测）→ 下次具体怎么做
        【下次可以试试】1 个可以用这些统计衡量的小目标
        【数据看不出的】一句话说明这份数据的局限
        """;

    /// <summary>The exact user message that would be sent. Show it to the player before sending.</summary>
    public static string BuildSummary(BehaviorAnalysis analysis, IEnumerable<BehaviorCharacter> characters, string? question = null)
    {
        static JsonObject Period(BehaviorPeriodStats p) => new()
        {
            ["activeDays"] = p.ActiveDays,
            ["collectedMinutes"] = Round(p.CollectedSeconds / 60), ["combatMinutes"] = Round(p.CombatSeconds / 60),
            ["nonCombatMinutes"] = Round(p.NonCombatSeconds / 60), ["unknownStateMinutes"] = Round(p.UnknownCombatSeconds / 60),
            ["combatsEntered"] = p.CombatEntries, ["combatsCompleted"] = p.CombatsCompleted, ["deaths"] = p.Deaths,
            ["castSuccesses"] = p.CastSuccesses, ["castFailureEvents"] = p.CastFailures, ["castInterruptions"] = p.CastInterruptions,
            ["questsAccepted"] = p.QuestsAccepted, ["questsTurnedIn"] = p.QuestsTurnedIn,
            ["xpGained"] = p.XpGained, ["levelsGained"] = p.LevelsGained,
            ["xpPerHour"] = Round(p.XpPerHour), ["questsPerHour"] = Round(p.QuestsPerHour, 1),
            ["combatShare"] = Round(p.CombatShare, 2), ["averageCombatSeconds"] = Round(p.AverageCombatSeconds),
            ["deathsPer100Combats"] = Round(p.DeathsPer100Combats, 1), ["castFailureRate"] = Round(p.CastFailureRate, 2),
            ["castInterruptRate"] = Round(p.CastInterruptRate, 2), ["hoursPerLevel"] = Round(p.HoursPerLevel, 1),
            ["hasLegacyData"] = p.HasLegacyData, ["isPartial"] = p.IsPartial,
            ["lowSample"] = p.CollectedSeconds < BehaviorInsights.MinimumSeconds
        };
        var root = new JsonObject
        {
            ["game"] = "魔兽世界：无限（国服）",
            ["characters"] = new JsonArray(characters.Select(c => (JsonNode)new JsonObject
            { ["class"] = ClassLabel(c.Class), ["level"] = c.Level > 0 ? c.Level : null }).ToArray()),
            ["period"] = analysis.PeriodLabel,
            ["current"] = Period(analysis.Current),
            ["previousPeriod"] = analysis.Previous is null ? null : new JsonObject { ["label"] = analysis.PreviousLabel, ["stats"] = Period(analysis.Previous) },
            ["spells"] = new JsonArray(analysis.Spells.Take(12).Select(s => (JsonNode)new JsonObject
            {
                ["name"] = s.DisplayName, ["successes"] = s.Successes, ["failureEvents"] = s.Failures, ["interruptions"] = s.Interrupted,
                ["failureRate"] = Round(s.FailureRate, 2), ["interruptRate"] = Round(s.InterruptRate, 2)
            }).ToArray()),
            ["zoneDetailDays"] = analysis.ZoneDetailDays,
            ["zones"] = new JsonArray(analysis.Zones.Take(10).Select(z => (JsonNode)new JsonObject
            {
                ["name"] = z.DisplayName, ["minutes"] = Round(z.Seconds / 60), ["visits"] = z.Visits,
                ["xpGained"] = z.DetailSeconds > 0 ? z.XpGained : null, ["deaths"] = z.DetailSeconds > 0 ? z.Deaths : null,
                ["combatsEntered"] = z.DetailSeconds > 0 ? z.CombatEntries : null, ["xpPerHour"] = Round(z.XpPerHour)
            }).ToArray()),
            ["localFindings"] = new JsonArray(analysis.Insights.Select(i => (JsonNode)new JsonObject
            {
                ["type"] = i.Tone switch { InsightTone.Attention => "需要注意", InsightTone.Positive => "做得好", _ => "参考" },
                ["title"] = i.Title, ["evidence"] = i.Evidence, ["lowSample"] = i.LowSample
            }).ToArray())
        };
        var text = new StringBuilder("以下是我在《魔兽世界：无限》中的本机行为统计摘要，请帮我复盘。\n");
        var focus = CleanQuestion(question);
        if (focus.Length > 0) text.Append("我最想知道：").Append(focus).Append('\n');
        text.Append('\n').Append(root.ToJsonString(SummaryJson));
        return text.ToString();
    }

    public static string CleanQuestion(string? question)
    {
        var text = Regex.Replace(question ?? "", @"[\p{Cc}\p{Cf}]", " ").Trim();
        return text.Length <= MaxQuestionLength ? text : text[..MaxQuestionLength];
    }

    /// <summary>Validated chat-completions URL: HTTPS anywhere, plain HTTP only to this computer.</summary>
    public static Uri ChatEndpoint(string endpoint)
    {
        if (!Uri.TryCreate((endpoint ?? "").Trim(), UriKind.Absolute, out var uri) || uri.UserInfo.Length > 0 || uri.Query.Length > 0 || uri.Fragment.Length > 0)
            throw new BehaviorAiException("接口地址格式不正确，请填写完整网址，例如 https://api.deepseek.com");
        var local = uri.IsLoopback;
        if (uri.Scheme != Uri.UriSchemeHttps && !(uri.Scheme == Uri.UriSchemeHttp && local))
            throw new BehaviorAiException("为保护密钥与数据，外网接口必须使用 https://；http:// 只允许本机地址（如 Ollama）。");
        var basePath = uri.AbsolutePath.TrimEnd('/');
        var full = basePath.EndsWith("/chat/completions", StringComparison.OrdinalIgnoreCase) ? basePath : basePath + "/chat/completions";
        return new UriBuilder(uri) { Path = full }.Uri;
    }

    public static async Task<string> AskAsync(BehaviorAiSettings settings, string userMessage, HttpMessageHandler? handler = null, CancellationToken cancellationToken = default)
    {
        var url = ChatEndpoint(settings.Endpoint);
        var model = (settings.Model ?? "").Trim();
        if (model.Length is 0 or > 128) throw new BehaviorAiException("请填写模型名称。");
        var key = (settings.ApiKey ?? "").Trim();
        if (key.Length == 0 && !url.IsLoopback) throw new BehaviorAiException("请填写 API Key。");
        if (key.Any(ch => ch < 0x21 || ch > 0x7E)) throw new BehaviorAiException("API Key 含有无效字符，请重新粘贴。");
        var body = new JsonObject
        {
            ["model"] = model, ["temperature"] = 0.4, ["max_tokens"] = 1500, ["stream"] = false,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = SystemPrompt },
                new JsonObject { ["role"] = "user", ["content"] = userMessage })
        };
        // DeepSeek Flash currently defaults to thinking; reserve the short
        // answer budget for the visible review rather than hidden reasoning.
        if (url.Host.Equals("api.deepseek.com", StringComparison.OrdinalIgnoreCase))
            body["thinking"] = new JsonObject { ["type"] = "disabled" };
        // A local endpoint may redirect to an external host. Send the reviewed
        // payload only to the chosen endpoint, and never proxy loopback traffic.
        using var client = handler is null
            ? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseProxy = !url.IsLoopback })
            : new HttpClient(handler, false);
        client.Timeout = TimeSpan.FromSeconds(120);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(120));
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        { Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json") };
        if (key.Length > 0) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Headers.UserAgent.ParseAdd("MyForeverManager/" + ManagerVersion.Current);
        string text; HttpStatusCode status;
        try
        {
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token).ConfigureAwait(false);
            status = response.StatusCode;
            text = await ReadLimitedAsync(response, deadline.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        { throw new BehaviorAiException("模型服务响应超时，请稍后再试，或换一个更快的模型。"); }
        catch (Exception e) when (e is HttpRequestException or IOException)
        { throw new BehaviorAiException(url.IsLoopback ? "无法连接本机模型服务，请确认 Ollama 已启动并已下载所填模型。" : "无法连接模型服务，请检查网络和接口地址。"); }
        if ((int)status is < 200 or > 299)
        {
            var reason = status switch
            {
                HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden => "API Key 无效或没有权限",
                HttpStatusCode.NotFound => "接口地址或模型名称不正确",
                HttpStatusCode.PaymentRequired or HttpStatusCode.TooManyRequests => "额度不足或请求过于频繁",
                HttpStatusCode.BadRequest => "请求被服务拒绝，请检查模型名称",
                _ when (int)status >= 500 => "模型服务暂时不可用",
                _ => "模型服务返回错误"
            };
            var detail = ProviderMessage(text, key);
            throw new BehaviorAiException($"{reason}（HTTP {(int)status}）" + (detail.Length > 0 ? "：" + detail : "。"));
        }
        string? content;
        try { content = JsonNode.Parse(text)?["choices"]?[0]?["message"]?["content"]?.GetValue<string>(); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException or ArgumentOutOfRangeException)
        { throw new BehaviorAiException("模型服务返回的内容无法识别，请确认它兼容 OpenAI Chat Completions 接口。"); }
        var answer = CleanAnswer(content);
        if (answer.Length == 0) throw new BehaviorAiException("模型没有返回复盘内容，请重试或更换模型。");
        return answer;
    }

    internal static string CleanAnswer(string? content)
    {
        // Some reasoning models inline their thinking; the player only needs the result.
        var text = Regex.Replace(content ?? "", @"<think>[\s\S]*?</think>", "", RegexOptions.IgnoreCase);
        text = Regex.Replace(text.Replace("\r\n", "\n"), @"[\p{Cc}\p{Cf}-[\n]]", "");
        text = Regex.Replace(text, @"^\s{0,3}#{1,6}\s*", "", RegexOptions.Multiline).Replace("**", "").Trim();
        return text.Length <= MaxAnswerLength ? text : text[..MaxAnswerLength] + "…";
    }

    private static async Task<string> ReadLimitedAsync(HttpResponseMessage response, CancellationToken token)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
        using var buffer = new MemoryStream();
        var chunk = new byte[16 * 1024];
        int read;
        while ((read = await stream.ReadAsync(chunk, token).ConfigureAwait(false)) > 0)
        {
            if (buffer.Length + read > MaxResponseBytes) throw new BehaviorAiException("模型服务返回内容过大，已停止读取。");
            buffer.Write(chunk, 0, read);
        }
        try { return new UTF8Encoding(false, true).GetString(buffer.ToArray()); }
        catch (DecoderFallbackException) { throw new BehaviorAiException("模型服务返回内容的编码无法识别。"); }
    }

    private static string ProviderMessage(string text, string key)
    {
        string message;
        try { message = JsonNode.Parse(text)?["error"]?["message"]?.GetValue<string>() ?? ""; }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException) { return ""; }
        if (key.Length > 0) message = message.Replace(key, "***", StringComparison.Ordinal);
        message = Regex.Replace(message, @"[\p{Cc}\p{Cf}]", " ").Trim();
        return message.Length <= 160 ? message : message[..160] + "…";
    }

    private static JsonNode? Round(double? value, int digits = 0) =>
        value is { } v && double.IsFinite(v) ? JsonValue.Create(Math.Round(v, digits)) : null;

    private static string ClassLabel(string id) => id switch
    {
        "WARRIOR" => "战士", "PALADIN" => "圣骑士", "HUNTER" => "猎人", "ROGUE" => "潜行者", "PRIEST" => "牧师",
        "SHAMAN" => "萨满祭司", "MAGE" => "法师", "WARLOCK" => "术士", "DRUID" => "德鲁伊", "DEATHKNIGHT" => "死亡骑士",
        "MONK" => "武僧", "DEMONHUNTER" => "恶魔猎手", "EVOKER" => "唤魔师", _ => "未知职业"
    };
}
