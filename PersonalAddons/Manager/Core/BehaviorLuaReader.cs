using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace MyForeverManager.Core;

// A data reader, never a Lua interpreter. Only the collector's literal assignment
// is accepted. In particular function calls, concatenation and other assignments
// cannot execute or be silently skipped.
internal sealed class BehaviorLuaReader(string input)
{
    private readonly string source = input;
    private int position, items;
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private static readonly Regex NumberPattern = new(@"\G[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?", RegexOptions.CultureInvariant);
    private static readonly Regex IdentifierPattern = new(@"\G[A-Za-z_][A-Za-z_0-9]*", RegexOptions.CultureInvariant);
    public static Dictionary<string, object?> Parse(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > 8 * 1024 * 1024) throw Bad();
        var reader = new BehaviorLuaReader(text.TrimStart('\uFEFF'));
        reader.Take("MyForeverCoachDB"); reader.Take("=");
        var result = reader.Value(0) as Dictionary<string, object?> ?? throw Bad();
        reader.Skip(); if (reader.At(';')) reader.position++;
        reader.Skip(); if (reader.position != reader.source.Length) throw Bad();
        return result;
    }
    private static InvalidDataException Bad() => new("采集存档不是受支持的数据格式，原文件未修改。");
    private bool At(char c) => position < source.Length && source[position] == c;
    private void Skip()
    {
        while (position < source.Length)
        {
            if (char.IsWhiteSpace(source[position])) { position++; continue; }
            if (source.AsSpan(position).StartsWith("--"))
            { var next = source.IndexOf('\n', position); position = next < 0 ? source.Length : next + 1; continue; }
            break;
        }
    }
    private void Take(string token)
    {
        Skip(); if (!source.AsSpan(position).StartsWith(token, StringComparison.Ordinal)) throw Bad();
        position += token.Length;
    }
    private object? Value(int depth)
    {
        // Eight retained sessions plus 90 days of bounded cumulative maps can
        // legitimately contain more than 200k scalar keys and values.
        if (depth > 32 || ++items > 1_000_000) throw Bad();
        Skip(); if (position >= source.Length) throw Bad();
        if (At('{')) return Table(depth + 1);
        if (At('"') || At('\'')) return String();
        foreach (var (word, value) in new (string, object?)[] { ("true", true), ("false", false), ("nil", null) })
        {
            if (source.AsSpan(position).StartsWith(word, StringComparison.Ordinal))
            { position += word.Length; return value; }
        }
        var match = NumberPattern.Match(source, position);
        if (!match.Success || !double.TryParse(match.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number)) throw Bad();
        position += match.Length; return number;
    }
    private Dictionary<string, object?> Table(int depth)
    {
        Take("{"); var result = new Dictionary<string, object?>(StringComparer.Ordinal); int implicitIndex = 1;
        while (true)
        {
            Skip(); if (At('}')) { position++; return result; }
            string key; object? value;
            if (At('['))
            {
                position++; var raw = Value(depth); Take("]"); Take("=");
                key = raw switch { string s => s, double n when n >= 0 && n <= 9_007_199_254_740_991 && n == Math.Truncate(n) => n.ToString("0", CultureInfo.InvariantCulture), _ => throw Bad() };
                value = Value(depth);
            }
            else
            {
                var saved = position;
                var id = IdentifierPattern.Match(source, position);
                if (id.Success) { position += id.Length; Skip(); }
                if (id.Success && At('=')) { position++; key = id.Value; value = Value(depth); }
                else { position = saved; key = (implicitIndex++).ToString(CultureInfo.InvariantCulture); value = Value(depth); }
            }
            if (!result.TryAdd(key, value)) throw Bad();
            Skip(); if (At(',') || At(';')) position++;
            else if (!At('}')) throw Bad();
        }
    }
    private string String()
    {
        char quote = source[position++]; using var bytes = new MemoryStream();
        while (position < source.Length)
        {
            if (bytes.Length > 131_072) throw Bad();
            if (At(quote)) { position++; try { return Utf8.GetString(bytes.ToArray()); } catch (DecoderFallbackException) { throw Bad(); } }
            if (!At('\\'))
            {
                var start = position;
                while (position < source.Length && !At(quote) && !At('\\'))
                { if (At('\n') || At('\r')) throw Bad(); position++; }
                bytes.Write(Utf8.GetBytes(source[start..position])); continue;
            }
            position++; if (position >= source.Length) throw Bad();
            char escaped = source[position++];
            if (escaped is >= '0' and <= '9')
            {
                int value = escaped - '0', digits = 1;
                while (digits < 3 && position < source.Length && source[position] is >= '0' and <= '9')
                { value = value * 10 + source[position++] - '0'; digits++; }
                if (value > 255) throw Bad(); bytes.WriteByte((byte)value); continue;
            }
            byte decoded = escaped switch
            {
                'a' => 7, 'b' => 8, 'f' => 12, 'n' => 10, 'r' => 13, 't' => 9, 'v' => 11,
                '\\' => 92, '\'' => 39, '"' => 34, '\n' => 10, _ => throw Bad()
            };
            bytes.WriteByte(decoded);
        }
        throw Bad();
    }
}
