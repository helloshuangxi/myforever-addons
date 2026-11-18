using System.Security.Cryptography;
using System.Text.Json;

namespace MyForeverManager.Core;

public sealed record NavigatorBridgeStatus(string Status, string? Question, int Pending, int Ready);

public sealed class NavigatorBridge
{
    private readonly SemaphoreSlim gate = new(1);
    private sealed record Snapshot(long Length, DateTime Stamp, NavigatorQuestion? Request);
    private sealed record Pending(string Path, NavigatorQuestion Request, string Stamp);
    private sealed record Failure(int Count, DateTimeOffset RetryAt, string Reason);
    private readonly Dictionary<string,Snapshot> parsed = new(StringComparer.Ordinal);
    private readonly Dictionary<string,Failure> failures = new(StringComparer.Ordinal);
    private static bool FileProblem(Exception e) => e is IOException or UnauthorizedAccessException or InvalidDataException;
    private static string Fingerprint(NavigatorQuestion q) => Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(q)));
    private static bool Plain(string? value, int bytes) => value is not null && !value.Any(char.IsControl)
        && System.Text.Encoding.UTF8.GetByteCount(value) <= bytes;

    private static bool ValidAnswer(NavigatorQuestion request, NavigatorAnswer a)
    {
        if (a is null || a.Steps is null || a.Steps.Count > 6 || !Plain(a.Message,360)
            || (a.Steps.Count == 0 && string.IsNullOrWhiteSpace(a.Message))) return false;
        return a.Steps.All(s => s is not null && Plain(s.Text,180) && (s.Kind switch
        {
            "quest" => s.Term is null && request.Choices.Any(c => c.Key == s.Key),
            "place" => s.Key is null && Plain(s.Term,120) && !string.IsNullOrWhiteSpace(s.Term),
            _ => false
        }));
    }

    private List<string> FindCharacterFiles(string game, CancellationToken token)
    {
        var files = new List<string>();
        var root = Path.Combine(game,"WTF","Account");
        PathSafety.AssertNoLinks(root);
        if (!Directory.Exists(root)) return files;
        // Account/realm/character only. Never open account-wide settings,
        // another addon's data, chats, backups or arbitrary descendant files.
        var dirs = new Queue<(string Dir,int Depth)>();
        dirs.Enqueue((root,0));
        int visited=0;
        while (dirs.TryDequeue(out var entry))
        {
            token.ThrowIfCancellationRequested();
            if (entry.Depth == 3)
            {
                var path=Path.Combine(entry.Dir,"SavedVariables","MyForeverNavigator.lua");
                if (File.Exists(path))
                {
                    if ((File.GetAttributes(Path.GetDirectoryName(path)!) & FileAttributes.ReparsePoint) != 0
                        || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) continue;
                    PathSafety.AssertNoLinks(path);
                    if (files.Count >= 256) throw new InvalidDataException("问路角色存档超过单次扫描上限。");
                    files.Add(path);
                }
                continue;
            }
            foreach (var next in Directory.EnumerateDirectories(entry.Dir))
            {
                if (++visited > 4096) throw new InvalidDataException("游戏账号目录超过单次扫描上限。");
                if ((File.GetAttributes(next) & FileAttributes.ReparsePoint) != 0
                    || Path.GetFileName(next).Equals("SavedVariables",StringComparison.OrdinalIgnoreCase)) continue;
                dirs.Enqueue((next,entry.Depth+1));
            }
        }
        return files;
    }

    public NavigatorQuestion? LatestSavedQuestion(string selection, CancellationToken token)
    {
        var game = GamePaths.Resolve(selection);
        var paths = FindCharacterFiles(game, token).OrderByDescending(File.GetLastWriteTimeUtc);
        foreach (var path in paths)
        {
            token.ThrowIfCancellationRequested();
            try
            {
                if (NavigatorMailbox.ReadQuestion(path, includeClipboard: true) is { } question)
                    return question;
            }
            catch (Exception e) when (FileProblem(e)) { continue; }
        }
        return null;
    }

    private NavigatorQuestion? ReadSnapshot(string path)
    {
        var file = new FileInfo(path);
        var size=file.Length; var stamp=file.LastWriteTimeUtc;
        if (parsed.TryGetValue(path,out var prior) && prior.Length == size && prior.Stamp == stamp) return prior.Request;
        var request=NavigatorMailbox.ReadQuestion(path);
        file.Refresh();
        if (!file.Exists || size!=file.Length || stamp!=file.LastWriteTimeUtc) throw new IOException("游戏正在保存问路信息。");
        parsed[path] = new(size,stamp,request);
        return request;
    }

    public async Task<NavigatorBridgeStatus> PollAsync(string selection,
        Func<NavigatorQuestion,CancellationToken,Task<NavigatorAnswerResult>> solve, CancellationToken token,
        Action<string>? processing = null, bool retryNow = false)
    {
        await gate.WaitAsync(token).ConfigureAwait(false);
        try { return await PollOnce(selection, solve, token, processing, retryNow).ConfigureAwait(false); }
        finally { gate.Release(); }
    }

    private async Task<NavigatorBridgeStatus> PollOnce(string selection,
        Func<NavigatorQuestion,CancellationToken,Task<NavigatorAnswerResult>> solve, CancellationToken token,
        Action<string>? processing, bool retryNow)
    {
        var game=GamePaths.Resolve(selection);
        var inbox=NavigatorMailbox.LocateInbox(game);
        var replies=NavigatorMailbox.ReadReplies(inbox);
        var files=FindCharacterFiles(game,token);
        foreach (var path in parsed.Keys.Except(files,StringComparer.Ordinal).ToList()) parsed.Remove(path);
        var pending=new List<Pending>(); int errors=0;
        foreach (var path in files)
        {
            try
            {
                if (ReadSnapshot(path) is { } q) pending.Add(new(path,q,Fingerprint(q)));
            }
            catch (Exception e) when (FileProblem(e)) { errors++; }
        }
        // Each request belongs to exactly one character. Ignore collisions
        // instead of giving one character another character's response.
        var duplicates = pending.GroupBy(p=>p.Request.Id).Where(g=>g.Count()>1).Select(g=>g.Key).ToHashSet();
        var active = pending.Select(p=>p.Request.Id).ToHashSet(StringComparer.Ordinal);
        var fingerprints = pending.Select(p=>p.Stamp).ToHashSet(StringComparer.Ordinal);
        foreach(var stamp in failures.Keys.Except(fingerprints).ToList()) failures.Remove(stamp);
        if (retryNow) failures.Clear();
        string? last=null, note=null;
        int ready=0, attempts=0;
        foreach (var item in pending)
        {
            token.ThrowIfCancellationRequested();
            var q=item.Request;
            if (duplicates.Contains(q.Id)) { note="问题编号冲突，请在游戏中重新提问。"; continue; }
            if (replies.TryGetValue(q.Id,out var prior))
            {
                if (prior.Stamp == item.Stamp) { ready++; last=q.Question; }
                else note="问题内容与既有编号不一致，请在游戏中重新提问。";
                continue;
            }
            if (replies.Count >= NavigatorMailbox.MaxReplies && replies.Keys.All(active.Contains))
            {
                note="稍候再试：请先在游戏中读取已有回答。";
                continue;
            }
            if (attempts >= 3) continue;
            if (failures.TryGetValue(item.Stamp,out var failure) && failure.RetryAt>DateTimeOffset.UtcNow)
            { note=failure.Reason; continue; }
            attempts++;
            last=q.Question;
            processing?.Invoke(q.Question);
            NavigatorAnswer answer;
            try
            {
                answer=(await solve(q,token).ConfigureAwait(false)).Answer;
                if (!ValidAnswer(q,answer)) throw new BehaviorAiException("模型回复格式不适用于当前问题。");
            }
            catch (Exception e) when (e is BehaviorAiException or HttpRequestException or IOException or OperationCanceledException)
            {
                token.ThrowIfCancellationRequested();
                var reason=e is BehaviorAiException ? e.Message : "模型连接暂不可用。";
                int count=(failure?.Count ?? 0)+1;
                if (count<3)
                {
                    note=reason+" 客户端稍后重试，也可以调整设置后立即重试。";
                    failures[item.Stamp]=new(count,DateTimeOffset.UtcNow.AddSeconds(count*30),note);
                    continue;
                }
                note=reason;
                answer=new([], "客户端暂未能取得可用回答。请查看客户端问路页，检查模型设置后重新提问。");
            }
            token.ThrowIfCancellationRequested();
            // The user may have cancelled/switched questions during inference.
            // Re-read the actual file, independent of cached mtime/size.
            var current = File.Exists(item.Path) ? NavigatorMailbox.ReadQuestion(item.Path) : null;
            if (current is null || Fingerprint(current) != item.Stamp) continue;
            inbox=NavigatorMailbox.LocateInbox(game);
            replies=NavigatorMailbox.ReadReplies(inbox);
            if (replies.TryGetValue(q.Id,out var existing) && existing.Stamp!=item.Stamp)
            { note="同编号的应答已存在，请重新提问。"; continue; }
            if (replies.Count >= NavigatorMailbox.MaxReplies && !replies.ContainsKey(q.Id))
            {
                var stale = replies.Keys.FirstOrDefault(id=>!active.Contains(id));
                if (stale is null) {note="稍候再试：请先在游戏中读取已有回答。";continue;}
                replies.Remove(stale);
            }
            replies[q.Id]=new(item.Stamp,answer);
            NavigatorMailbox.Write(inbox,replies);
            failures.Remove(item.Stamp);
            ready++;
        }
        if (note is null && errors>0) note="部分角色的问路存档暂不可读，将重新检测。";
        note ??= ready>0 ? "回答已返回。在游戏中重载界面即可查看。"
            : pending.Count>0 ? "正在等待处理游戏中的问题。" : "正在监听。请在游戏「世界向导 → 问路」中发送问题。";
        return new(note,last,pending.Count-ready,ready);
    }
}
