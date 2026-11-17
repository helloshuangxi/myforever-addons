using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace MyForeverManager.Core;

internal sealed record NavigatorReply(string Stamp, NavigatorAnswer Answer);

internal static class NavigatorMailbox
{
    private const int MaxSnapshot = 8 * 1024 * 1024, MaxInbox = 512 * 1024;
    internal const int MaxReplies = 64;
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private static readonly Regex Id = new(@"\A[a-z0-9-]{1,64}\z", RegexOptions.CultureInvariant);
    private static readonly Regex ChoiceKey = new(@"\Aq(?:[1-9]|1[0-9]|2[0-4])\z", RegexOptions.CultureInvariant);

    internal static string LocateInbox(string game)
    {
        string directory = Path.Combine(GamePaths.AddonsDirectory(game), "MyForeverNavigator");
        string inbox = Path.Combine(directory, "ClientInbox.lua");
        string toc = Path.Combine(directory, "MyForeverNavigator.toc");
        PathSafety.AssertNoLinks(inbox);
        PathSafety.AssertNoLinks(toc);
        if (!File.Exists(inbox) || !File.Exists(toc)
            || !ReadText(toc, 64 * 1024).Split('\n').Any(line => line.Trim() == "ClientInbox.lua"))
            throw new InvalidDataException("请先安装支持客户端问路的世界向导。");
        return inbox;
    }

    internal static string ReadText(string path, int limit)
    {
        PathSafety.AssertNoLinks(path);
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (file.Length > limit) throw new InvalidDataException("问路文件超过读取上限。");
        var bytes = new byte[checked((int)file.Length)];
        file.ReadExactly(bytes);
        if (file.ReadByte() != -1) throw new IOException("游戏正在保存问路信息。");
        try { return Utf8.GetString(bytes); }
        catch (DecoderFallbackException) { throw new InvalidDataException("问路文件编码不完整。"); }
    }

    private static Dictionary<string, object?> Table(object? value) =>
        value as Dictionary<string, object?> ?? throw new InvalidDataException("问路数据表格式不正确。");
    private static int Number(Dictionary<string, object?> d, string key, int max = int.MaxValue)
    {
        if (d.GetValueOrDefault(key) is double n && n >= 0 && n <= max && n == Math.Truncate(n)) return (int)n;
        throw new InvalidDataException("问路编号格式不正确。");
    }
    private static string TextField(Dictionary<string, object?> d, string key, int max, bool optional = false)
    {
        if (optional && d.GetValueOrDefault(key) is null) return "";
        if (d.GetValueOrDefault(key) is string text && (optional || !string.IsNullOrWhiteSpace(text))
            && Utf8.GetByteCount(text) <= max && !text.Any(char.IsControl)) return text;
        throw new InvalidDataException("问路文字格式不正确。");
    }
    private static IEnumerable<Dictionary<string, object?>> Array(Dictionary<string, object?> d, string key, int limit)
    {
        var array = Table(d.GetValueOrDefault(key));
        if (array.Count > limit) throw new InvalidDataException("问路步骤或候选过多。");
        for (int i = 1; i <= array.Count; i++)
            yield return Table(array.GetValueOrDefault(i.ToString(CultureInfo.InvariantCulture)));
    }
    internal static NavigatorQuestion? ReadQuestion(string path)
    {
        var d = BehaviorLuaReader.ReadVariable(ReadText(path, MaxSnapshot), "MyForeverNavigatorOutbox");
        if (d is null || d.Count == 0 || !d.ContainsKey("id")) return null;
        if (Number(d,"version") != 1) throw new InvalidDataException("世界向导问路协议版本不同。");
        var id = TextField(d,"id",64);
        if (!Id.IsMatch(id)) throw new InvalidDataException("问题标识无效。");
        var choices = new List<NavigatorChoice>();
        foreach (var c in Array(d,"choices",24))
        {
            var key = TextField(c,"key",3);
            var kind = TextField(c,"kind",16);
            if (!ChoiceKey.IsMatch(key) || choices.Any(x=>x.Key == key) || kind is not ("objective" or "turnin" or "native"))
                throw new InvalidDataException("任务候选标识无效。");
            choices.Add(new(key,TextField(c,"name",120),kind,TextField(c,"detail",240,true)));
        }
        return new(id,TextField(d,"question",180),TextField(d,"locale",12),Number(d,"mapID"),
            TextField(d,"faction",16,true),Number(d,"questID"),TextField(d,"questTitle",120,true),choices);
    }

    internal static Dictionary<string, NavigatorReply> ReadReplies(string inbox)
    {
        var d = BehaviorLuaReader.ReadVariable(ReadText(inbox, MaxInbox), "MyForeverNavigatorInbox");
        if (d is null || Number(d,"version") != 1) throw new InvalidDataException("世界向导回包文件不兼容。");
        var rows = Table(d.GetValueOrDefault("replies"));
        if (rows.Count > MaxReplies) throw new InvalidDataException("已保存的问路应答过多。");
        var result = new Dictionary<string,NavigatorReply>(StringComparer.Ordinal);
        foreach (var (id,row) in rows)
        {
            var t = Table(row);
            if (!Id.IsMatch(id) || TextField(t,"id",64) != id) throw new InvalidDataException("问路应答标识不匹配。");
            var answer = new NavigatorAnswer(Array(t,"steps",6).Select(step => new NavigatorStep(
                TextField(step,"kind",16),step.ContainsKey("key") ? TextField(step,"key",3) : null,
                step.ContainsKey("term") ? TextField(step,"term",120) : null, TextField(step,"text",180,true))).ToList(),
                TextField(t,"message",360,true));
            result.Add(id,new(TextField(t,"stamp",64,true),answer));
        }
        return result;
    }

    // Escape every string as a single Lua literal. The incoming model never
    // supplies Lua, coordinates, code fragments or filesystem paths.
    private static string Quote(string value) => "\"" + value.Replace("\\","\\\\").Replace("\"","\\\"")
        .Replace("\r","\\r").Replace("\n","\\n").Replace("\t","\\t") + "\"";

    internal static void Write(string inbox, Dictionary<string, NavigatorReply> replies)
    {
        var data = new StringBuilder("MyForeverNavigatorInbox = {version=1,replies={\n");
        foreach (var (id, reply) in replies)
        {
            data.Append('[').Append(Quote(id)).Append("]={id=").Append(Quote(id)).Append(",stamp=")
                .Append(Quote(reply.Stamp)).Append(",message=").Append(Quote(reply.Answer.Message)).Append(",steps={");
            foreach (var step in reply.Answer.Steps)
            {
                data.Append("{kind=").Append(Quote(step.Kind)).Append(",text=").Append(Quote(step.Text));
                if (step.Key is not null) data.Append(",key=").Append(Quote(step.Key));
                if (step.Term is not null) data.Append(",term=").Append(Quote(step.Term));
                data.Append("},");
            }
            data.Append("}},\n");
        }
        var bytes = Utf8.GetBytes(data.Append("}}\n").ToString());
        if (bytes.Length > MaxInbox) throw new InvalidDataException("问路回包文件超过容量。");
        PathSafety.AssertNoLinks(inbox);
        var temp = Path.Combine(Path.GetDirectoryName(inbox)!, ".inbox-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            var opts = new FileStreamOptions {Mode=FileMode.CreateNew, Access=FileAccess.Write, Share=FileShare.None};
            if (!OperatingSystem.IsWindows()) opts.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            using (var stream = new FileStream(temp, opts)) { stream.Write(bytes); stream.Flush(true); }
            PathSafety.AssertNoLinks(inbox);
            // Refuse to create a new addon or revive one concurrently removed by an updater.
            if (!File.Exists(inbox)) throw new IOException("世界向导目录已变化，将重新检测。");
            File.Move(temp, inbox, overwrite:true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
