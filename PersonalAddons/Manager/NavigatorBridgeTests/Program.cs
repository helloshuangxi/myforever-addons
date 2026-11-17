using System.Text;
using MyForeverManager.Core;

internal static class Program
{
    private const string EmptyInbox = "MyForeverNavigatorInbox = {version=1,replies={}}\n";
    private const string Steps = "先询问\\\"卫兵\\\"";
    private static int checks;

    private static void Check(bool condition, string name)
    {
        if (!condition) throw new Exception("Failed: " + name);
        checks++;
    }

    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "navigator-bridge-" + Guid.NewGuid().ToString("N"));
        public string Game => Path.Combine(Root,"_forever_");
        public string Addon => Path.Combine(Game,"Interface","AddOns","MyForeverNavigator");
        public string Inbox => Path.Combine(Addon,"ClientInbox.lua");
        public string Toc => Path.Combine(Addon,"MyForeverNavigator.toc");
        public Fixture()
        {
            Directory.CreateDirectory(Addon);
            File.WriteAllText(Path.Combine(Game,"Wow.exe"), "");
            File.WriteAllText(Toc, "## Interface: 30403\nClientInbox.lua\nMain.lua");
            File.WriteAllText(Inbox, EmptyInbox);
        }
        public string SV(string character, string request)
        {
            string directory=Path.Combine(Game,"WTF","Account","TestAccount","TestRealm",character,"SavedVariables");
            Directory.CreateDirectory(directory);
            var path=Path.Combine(directory,"MyForeverNavigator.lua");
            File.WriteAllText(path,request);
            return path;
        }
        public void Dispose() => Directory.Delete(Root,true);
    }

    private static string Request(string id,string question="我要去铁炉堡") => $$"""
        MyForeverNavigatorDB = {
            ["unrelated"] = "MyForeverNavigatorOutbox = {id='decoy'}",
            ["other"] = { "PRIVATE SENTINEL" },
        }
        MyForeverNavigatorOutbox = {
            ["version"] = 1,
            ["id"] = "{{id}}",
            ["question"] = "{{question}}",
            ["locale"] = "zhCN",
            ["mapID"] = 1429,
            ["faction"] = "Alliance",
            ["questID"] = 0,
            ["questTitle"] = "",
            ["choices"] = {
                { ["key"] = "q1", ["name"] = "向卫兵问路", ["kind"] = "objective", ["detail"] = "询问卫兵" }, -- [1]
            },
        }
        """;

    private static Task<NavigatorAnswerResult> Reply(NavigatorQuestion q,CancellationToken token) =>
        Task.FromResult(new NavigatorAnswerResult(new NavigatorAnswer([new("quest","q1",null,"先询问\"卫兵\""),
            new("place",null,"铁炉堡","前往铁炉堡。")],"出发。"),false));

    private static async Task<int> Main(string[] args)
    {
        if (args.FirstOrDefault()=="--live-local") return await Live(args);
        using var world = new Fixture();
        var bridge = new NavigatorBridge();
        var seen = new List<NavigatorQuestion>();
        Task<NavigatorAnswerResult> Solve(NavigatorQuestion q,CancellationToken ct)
        {
            seen.Add(q);
            return Reply(q,ct);
        }
        Task<NavigatorBridgeStatus> Poll(bool force=false) => bridge.PollAsync(world.Game,Solve,default,retryNow:force);
        string alpha=world.SV("Alpha",Request("alpha-1"));
        var beta=world.SV("Beta",Request("beta-1","另一个问题"));
        string privateData = Path.Combine(Path.GetDirectoryName(beta)!, "OtherAddon.lua");
        File.WriteAllText(privateData,Request("other-addon"));
        var wide = Path.Combine(world.Game,"WTF","Account","TestAccount","SavedVariables");
        Directory.CreateDirectory(wide);
        File.WriteAllText(Path.Combine(wide,"MyForeverNavigator.lua"),Request("account-wide"));
        var concurrent=await Task.WhenAll(Poll(),Poll());
        Check(seen.Count==2 && seen.Any(q=>q.Id=="alpha-1") && seen.Any(q=>q.Id=="beta-1"),"concurrent dedup, only per-character dedicated requests");
        Check(concurrent.All(s=>s.Ready==2 && s.Pending==0),"both characters ready");
        Check(seen.All(q=>q.Choices.Count==1 && q.Choices[0].Key=="q1" && !q.Question.Contains("PRIVATE",StringComparison.Ordinal)),"only allowed question data copied");
        string response=File.ReadAllText(world.Inbox);
        Check(response.Contains("[\"alpha-1\"]") && response.Contains("[\"beta-1\"]") && response.Contains(Steps),"per-ID serialized responses and literal escaping");
        Check(!response.Contains("PRIVATE",StringComparison.Ordinal) && File.ReadAllText(alpha)==Request("alpha-1"),"WTF preserved, unrelated input absent");
        bridge=new();
        await Poll();
        Check(seen.Count==2,"persisted delivered request survives client restart");
        world.SV("Alpha",Request("alpha-1","内容已改变"));
        var mismatch=await Poll();
        Check(seen.Count==2 && mismatch.Ready==1 && mismatch.Pending==1 && File.ReadAllText(world.Inbox)==response,"same ID with changed input is not reused");
        world.SV("Alpha","MyForeverNavigatorOutbox = nil");
        world.SV("Beta","MyForeverNavigatorDB={fake=\"MyForeverNavigatorOutbox={}\"}");
        var one=world.SV("One",Request("duplicate"));
        var two=world.SV("Two",Request("duplicate"));
        var duplicates=await Poll();
        Check(seen.Count==2 && duplicates.Ready==0 && duplicates.Pending==2,"duplicate ID across characters ignored");
        File.Delete(one);File.Delete(two);
        var bad=world.SV("Malformed","MyForeverNavigatorOutbox = neverExecute()");
        var badResult=await Poll();
        Check(badResult.Ready==0 && badResult.Status.Contains("不可读") && seen.Count==2,"nonliteral data rejected");
        world.SV("Malformed",Request("invalid").Replace("q1","q25"));
        await Poll();
        Check(seen.Count==2,"unknown choice key rejected");
        using (var file=new FileStream(bad,FileMode.Truncate)) file.SetLength(8*1024*1024+1);
        await Poll();
        Check(seen.Count==2,"oversized saved file rejected");
        File.Delete(bad);
        world.SV("Move",Request("during-call"));
        var raced=await bridge.PollAsync(world.Game,(q,ct)=>{
            world.SV("Move",Request("replacement-id"));
            return Reply(q,ct);
        },default);
        Check(raced.Ready==0 && File.ReadAllText(world.Inbox)==response,"replaced request during model call never published");
        await Poll();
        Check(File.ReadAllText(world.Inbox).Contains("replacement-id"),"replacement processed");
        world.SV("Move",Request("cancelled-id"));
        var previous=File.ReadAllText(world.Inbox);
        using (var cancel = new CancellationTokenSource())
        {
            try
            {
                await bridge.PollAsync(world.Game,(q,ct)=>{cancel.Cancel();return Reply(q,ct);},cancel.Token);
                throw new Exception("Cancelled poll was published");
            }
            catch (OperationCanceledException) { Check(File.ReadAllText(world.Inbox)==previous,"model cancellation does not publish"); }
        }
        var invalid = new NavigatorAnswerResult(new NavigatorAnswer([new("quest","q2",null,"错误")],""),false);
        int failures=0;
        Task<NavigatorAnswerResult> Bad(NavigatorQuestion q,CancellationToken ct){failures++;return Task.FromResult(invalid);}
        var failed=await bridge.PollAsync(world.Game,Bad,default);
        await bridge.PollAsync(world.Game,Bad,default);
        Check(failed.Pending==1 && failures==1 && File.ReadAllText(world.Inbox)==previous,"out-of-context answer withheld, backoff prevents repeated charges");
        var retry=await bridge.PollAsync(world.Game,(q,ct)=>Task.FromResult(new NavigatorAnswerResult(new([],"请选择任务后再问。"),false)),default,retryNow:true);
        Check(retry.Ready==1 && File.ReadAllText(world.Inbox).Contains("请选择任务后再问。"),"manual retry delivers clarification");
        File.WriteAllText(world.Inbox,"MyForeverNavigatorInbox = broken()");
        try { await Poll();throw new Exception("Invalid inbox accepted"); }
        catch (InvalidDataException) { Check(File.ReadAllText(world.Inbox)=="MyForeverNavigatorInbox = broken()","invalid inbox retained"); }
        File.WriteAllText(world.Inbox,EmptyInbox);
        File.WriteAllText(world.Toc,"Main.lua");
        try { await Poll();throw new Exception("Missing TOC accepted"); }
        catch (InvalidDataException) { Check(File.ReadAllText(world.Inbox)==EmptyInbox,"TOC opt-in required"); }
        File.WriteAllText(world.Toc,"ClientInbox.lua");
        File.Delete(world.Inbox);
        try { await Poll();throw new Exception("Missing inbox created"); }
        catch (InvalidDataException) { Check(!File.Exists(world.Inbox),"uninstalled inbox not created"); }
        if (!OperatingSystem.IsWindows())
        {
            var outside=Path.Combine(world.Root,"outside");
            File.WriteAllText(outside,EmptyInbox);
            File.CreateSymbolicLink(world.Inbox,outside);
            try { await Poll();throw new Exception("Symlink accepted"); }
            catch (IOException) { Check(File.ReadAllText(outside)==EmptyInbox,"linked inbox never overwritten"); }
        }
        Console.WriteLine($"Navigator bridge: {checks} checks passed");
        return 0;
    }

    // An optional real proof restricted to a locally running model and
    // synthetic game directory. Supply the fixture to replay a Lua-produced outbox.
    private static async Task<int> Live(string[] args)
    {
        if (args.Length is not (3 or 4) || !Uri.TryCreate(args[1],UriKind.Absolute,out var address)
            || !address.IsLoopback || address.Scheme!="http")
            throw new ArgumentException("--live-local http://127.0.0.1:PORT/v1 MODEL [synthetic _forever_]");
        using var owned = args.Length==3 ? new Fixture() : null;
        string game=owned?.Game ?? GamePaths.Resolve(args[3]);
        if (owned is not null) owned.SV("Fixture",Request("live-fixture"));
        var marker=new FileInfo(Path.Combine(game,"Wow.exe"));
        if (!marker.Exists || marker.Length!=0) throw new ArgumentException("A synthetic _forever_ with an empty Wow.exe is required.");
        var state=Directory.CreateTempSubdirectory("navigator-model-test-");
        try
        {
            var ai=new NavigatorAiService(state.FullName);
            var settings=new BehaviorAiSettings {Provider="custom",Endpoint=address.AbsoluteUri,Model=args[2]};
            int calls=0;
            var bridge=new NavigatorBridge();
            var result=await bridge.PollAsync(game,async (q,ct)=>
            {
                calls++;
                var answer=await ai.AnswerAsync(settings,q,ct);
                Console.WriteLine($"answer {q.Id}: steps={answer.Answer.Steps.Count}, fromCache={answer.FromCache}");
                return answer;
            },default);
            Console.WriteLine(result.Status);
            Console.WriteLine(File.ReadAllText(Path.Combine(game,"Interface","AddOns","MyForeverNavigator","ClientInbox.lua")));
            return result.Ready>0 && result.Pending==0 && calls>0 ? 0 : 1;
        }
        finally { state.Delete(true); }
    }
}
