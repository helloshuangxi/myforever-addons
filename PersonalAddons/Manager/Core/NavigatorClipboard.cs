using System.Globalization;

namespace MyForeverManager.Core;

public static class NavigatorClipboard
{
    private static BehaviorAiException Invalid() => new("请先在世界向导的问路页复制完整的问题码。");

    public static NavigatorQuestion ReadQuestion(string? code)
    {
        if (string.IsNullOrEmpty(code) || code.Length > 36 * 1024 || !code.StartsWith("MFNQ1~", StringComparison.Ordinal))
            throw Invalid();
        var fields = code.Split('~', 107);
        if (fields.Length < 10 || fields[^1] != "END") throw Invalid();
        string Field(int index)
        {
            var field = fields[index];
            if (field.Replace("%25", "").Replace("%7E", "").Contains('%')) throw Invalid();
            return field.Replace("%7E", "~").Replace("%25", "%");
        }
        int Number(int index)
        {
            if (!int.TryParse(fields[index], NumberStyles.None, CultureInfo.InvariantCulture, out int value)) throw Invalid();
            return value;
        }
        int count = Number(8);
        if (count > 24 || fields.Length != 10 + count * 4) throw Invalid();
        var choices = new List<NavigatorChoice>(count);
        for (int i = 0; i < count; i++)
        {
            int pos = 9 + i * 4;
            choices.Add(new(Field(pos), Field(pos + 2), Field(pos + 1), Field(pos + 3)));
        }
        var question = new NavigatorQuestion(Field(1), Field(2), Field(3), Number(4), Field(5), Number(6), Field(7), choices);
        NavigatorAiService.RequestPayload(question);
        return question;
    }

    public static string WriteReply(NavigatorQuestion question, NavigatorAnswer answer)
    {
        var fields = new List<string> { "MFNA1", question.Id, answer.Message, answer.Steps.Count.ToString(CultureInfo.InvariantCulture) };
        foreach (var step in answer.Steps)
        {
            fields.Add(step.Kind);
            fields.Add(step.Key ?? step.Term ?? "");
            fields.Add(step.Text);
        }
        fields.Add("END");
        return string.Join("~", fields.Select(field => field.Replace("%", "%25").Replace("~", "%7E")));
    }
}
