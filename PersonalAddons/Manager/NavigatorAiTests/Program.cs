using System.Net;
using System.Text;
using System.Text.Json;
using MyForeverManager.Core;

var state = Path.Combine(Path.GetTempPath(), "mfn-answers-" + Guid.NewGuid().ToString("N"));
var settings = new BehaviorAiSettings { Model = "navigator-test", Endpoint = "http://127.0.0.1:11434/v1" };
var quest = new NavigatorQuestion("mfn-example-1", "狗头人的蜡烛这个任务怎么做？", "zhCN", 1429, "Alliance", 60, "狗头人的蜡烛",
    [new("q1", "狗头人劳工", "objective", "从狗头人身上收集 8 根大蜡烛。"), new("q2", "威廉·匹斯特", "turnin", "收集完成后，回闪金镇向威廉交付。")]);
var travel = quest with { Id = "mfn-example-2", Question = "我要先去暴风城的银行，再去铁炉堡的拍卖行。", QuestId = 0, QuestTitle = "", Choices = [] };
var count = 0;
void Check(bool ok, string label) { if (!ok) throw new Exception(label); count++; }
async Task MustFail(Func<Task> action, string label) { try { await action(); } catch (BehaviorAiException) { count++; return; } throw new Exception(label); }

try
{
    if (args.Length == 3 && args[0] == "--live-local")
    {
        var uri = new Uri(args[1]); if (!uri.IsLoopback) throw new ArgumentException("The smoke test uses a loopback model.");
        settings.Endpoint = args[1]; settings.Model = args[2]; var ai = new NavigatorAiService(state);
        var first = await ai.AnswerAsync(settings, quest); var second = await ai.AnswerAsync(settings, travel);
        var third = await new NavigatorAiService(state).AnswerAsync(settings, quest with { Id = "mfn-example-3" });
        Console.WriteLine(JsonSerializer.Serialize(new { model = settings.Model, quest = first, travel = second, repeatedQuest = third }, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        Check(first.Answer.Steps.Select(s => s.Key).SequenceEqual(new[] { "q1", "q2" }), "task objective then hand-in");
        Check(second.Answer.Steps.Count == 2 && second.Answer.Steps[0].Term!.Contains("银行") && second.Answer.Steps[1].Term!.Contains("拍卖"), "two named travel services");
        Check(!first.FromCache && !second.FromCache && third.FromCache, "live requests and persisted cache");
        return;
    }
    const string success = """{"message":"完成后回去交付。","steps":[{"kind":"quest","key":"q1","text":"收集大蜡烛。"},{"kind":"quest","key":"q2","text":"向威廉交付。"}]}""";
    const string place = """{"message":"选择每站的实际地点。","steps":[{"kind":"place","term":"暴风城 银行职员","text":"到银行存物品。"},{"kind":"place","term":"铁炉堡 拍卖师","text":"前往拍卖行。"}]}""";
    var h = new Provider { Content = success }; var aiService = new NavigatorAiService(state, h);
    var result = await aiService.AnswerAsync(settings, quest);
    Check(!result.FromCache && result.Answer.Steps.Count == 2, "valid task steps");
    using (var body = JsonDocument.Parse(h.Body))
    {
        var b = body.RootElement;
        Check(b.GetProperty("response_format").GetProperty("type").GetString() == "json_object", "structured response requested");
        Check(b.GetProperty("messages")[0].GetProperty("content").GetString()!.Contains("世界向导"), "dedicated navigation system");
        var msg = b.GetProperty("messages")[1].GetProperty("content").GetString()!;
        Check(!msg.Contains(quest.Id) && !msg.Contains("SavedVariables") && !msg.Contains("GUID"), "omit private and transport data");
        using var j = JsonDocument.Parse(msg); var q = j.RootElement;
        Check(q.EnumerateObject().Select(p => p.Name).ToHashSet().SetEquals(new[] { "question", "locale", "mapID", "faction", "questID", "questTitle", "choices" }), "only explicitly selected question and game context");
        Check(q.GetProperty("choices")[1].GetProperty("key").GetString() == "q2", "candidate grounding");
    }
    var replay = await new NavigatorAiService(state, h).AnswerAsync(settings, quest with { Id = "mfn-example-3" });
    Check(replay.FromCache && h.Calls == 1, "persisted cache with new request ID");
    await aiService.AnswerAsync(settings, quest with { MapId = 1426 });
    await aiService.AnswerAsync(settings, quest with { Choices = [quest.Choices[0] with { Detail = "还差一根蜡烛。" }, quest.Choices[1]] });
    Check(h.Calls == 3, "map and progress distinguish answers");
    h.Content = place;
    var concurrent = await Task.WhenAll(Enumerable.Range(0, 5).Select(i => aiService.AnswerAsync(settings, travel with { Id = "example-" + i })));
    Check(h.Calls == 4 && concurrent.Count(r => r.FromCache) == 4, "in-flight equivalent questions share one request");
    await MustFail(() => aiService.AnswerAsync(settings, quest with { Question = new string('界', 61) }), "question UTF-8 byte bound");
    await MustFail(() => aiService.AnswerAsync(settings, quest with { Choices = [quest.Choices[0], quest.Choices[0]] }), "duplicate keys");
    await MustFail(() => aiService.AnswerAsync(settings, quest with { QuestId = 0 }), "context without task ID");
    h.Content = success.Replace("q1", "temp").Replace("q2", "q1").Replace("temp", "q2");
    await MustFail(() => aiService.AnswerAsync(settings, quest with { Question = "蜡烛任务请带路。" }), "hand-in follows objectives");
    foreach (var bad in new[]{
        success.Replace("\"key\":\"q1\"","\"key\":\"q24\""),
        success.Replace("\"key\":\"q1\"","\"key\":\"q2\""),
        place.Replace("\"kind\":\"place\"","\"x\":0.3,\"kind\":\"place\""),
        place.Replace("暴风城 银行职员","32, 47"),
        place.Replace("到银行存物品。", "访问 https://example.com/"),
        place.Replace("到银行存物品。", new string('界',61)),
        """{"message":"","steps":[]}""", """{"steps":{},"message":"x"}""", "[]", "{", "not json"
    })
    {
        h.Content = bad; await MustFail(() => aiService.AnswerAsync(settings, travel with { Question = "我要去暴风城。" }), "reject malformed or ungrounded answer");
    }
    h.Content = """{"steps":[],"message":"请先选择任务。"}""";
    var missing = travel with { Question = "某某任务怎么做？" };
    Check(!(await aiService.AnswerAsync(settings, missing)).FromCache, "clarification delivered");
    Check(!(await aiService.AnswerAsync(settings, missing)).FromCache, "clarification not persisted");
    h.Status = HttpStatusCode.TooManyRequests;
    await MustFail(() => aiService.AnswerAsync(settings, missing), "upstream status mapped");
    h.Status = HttpStatusCode.OK;
    using (var cancel = new CancellationTokenSource())
    {
        cancel.Cancel(); var old = h.Calls;
        try { await aiService.AnswerAsync(settings, missing, cancel.Token); throw new Exception("cancellation"); }
        catch (OperationCanceledException) { Check(h.Calls == old, "cancellation suppresses model"); }
    }
    var cache = File.ReadAllText(Path.Combine(state, "navigator-answers-v1.json"));
    Check(!cache.Contains(quest.Question) && !cache.Contains(quest.Id) && !cache.Contains(quest.Choices[0].Detail), "cache retains only hash and steps");
    Console.WriteLine($"Navigator AI native transport, validation and persistent-cache checks: {count} passed");
}
finally { if (Directory.Exists(state)) Directory.Delete(state, true); }

sealed class Provider : HttpMessageHandler
{
    public string Content = "", Body = ""; public int Calls; public HttpStatusCode Status = HttpStatusCode.OK;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        Calls++; Body = await request.Content!.ReadAsStringAsync(token);
        var response = JsonSerializer.Serialize(new { choices = new[] { new { message = new { content = Content } } } });
        return new HttpResponseMessage(Status) { Content = new StringContent(response, Encoding.UTF8, "application/json") };
    }
}
