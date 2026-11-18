using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Input.Platform;
using Avalonia.Threading;
using MyForeverManager.Core;

namespace MyForeverManager.Desktop;

public sealed partial class MainWindow
{
    private readonly NavigatorBridge navigatorBridge = new();
    private readonly DispatcherTimer navigatorTimer = new() { Interval=TimeSpan.FromSeconds(5) };
    private BehaviorAiSettings? navigatorSettings;
    private BehaviorAiSettingsStore? navigatorStore;
    private NavigatorAiService? navigatorModel;
    private CancellationTokenSource? navigatorPoll;
    private TextBlock? navigatorStatus, navigatorQuestion;
    private int navigatorGeneration;
    private NavigatorQuestion? visibleQuestion;
    private string visibleAnswer = "", replyCode = "";
    private CancellationTokenSource? manualRequest;

    private void ConfigureNavigator()
    {
        string path=Path.Combine(store.DirectoryPath,"navigator");
        navigatorStore=new BehaviorAiSettingsStore(path);
        if (File.Exists(Path.Combine(path,"behavior-ai.json"))) navigatorSettings=navigatorStore.Load();
        else
        {
            navigatorSettings=new BehaviorAiSettingsStore(store.DirectoryPath).Load();
            navigatorSettings.Enabled=false;
        }
        navigatorModel=new NavigatorAiService(store.DirectoryPath);
        navigatorTimer.Tick+=async (_,_)=>await CheckNavigatorAsync();
    }

    private void SuspendNavigator()
    {
        navigatorGeneration++;
        navigatorTimer.Stop();
        manualRequest?.Cancel();
        manualRequest = null;
        navigatorPoll?.Cancel();
        navigatorStatus=null;
        navigatorQuestion=null;
    }

    private async Task CheckNavigatorAsync(bool retry=false)
    {
        if (navigatorStatus is null || navigatorSettings?.Enabled!=true || navigatorModel is null
            || navigatorPoll is not null || !dashboard || exitRequested || busy) return;
        var generation=navigatorGeneration;
        var config=navigatorSettings;
        var game=settings.GameDirectory;
        using var cancellation=new CancellationTokenSource();
        navigatorPoll=cancellation;
        void ShowQuestion(string value)
        {
            if (cancellation.IsCancellationRequested || generation!=navigatorGeneration || navigatorStatus is null) return;
            navigatorQuestion!.Text=value;
            navigatorQuestion.IsVisible=true;
            navigatorStatus.Text="客户端正在解析问题…";
        }
        try
        {
            // The file scan and bounded parser run away from the Avalonia UI thread.
            var state=await Task.Run(()=>navigatorBridge.PollAsync(game,
                (q,ct)=>navigatorModel.AnswerAsync(config,q,ct),cancellation.Token,
                q=>Dispatcher.UIThread.Post(()=>ShowQuestion(q)),retry),cancellation.Token);
            if (cancellation.IsCancellationRequested || generation!=navigatorGeneration || navigatorStatus is null) return;
            navigatorStatus.Text=state.Pending>0 ? $"{state.Status} 待处理 {state.Pending} 条。" : state.Status;
            if (state.Question is { } question)
            {
                navigatorQuestion!.Text=question;
                navigatorQuestion.IsVisible=true;
            }
        }
        catch (OperationCanceledException) when(cancellation.IsCancellationRequested) { }
        catch (Exception e)
        {
            if (generation==navigatorGeneration && navigatorStatus is not null)
                navigatorStatus.Text=e is InvalidDataException or BehaviorAiException ? e.Message :
                    "暂时无法读写问路文件。请检查游戏目录和权限，客户端将重新检测。";
        }
        finally { navigatorPoll=null; }
    }

    private Control BuildNavigatorPage()
    {
        if (navigatorSettings is null) ConfigureNavigator();
        var initial=navigatorSettings!;
        var enabled=new CheckBox{Content="自动接收旧版插件存档中的问题",IsChecked=initial.Enabled};
        var provider=new ComboBox{ItemsSource=BehaviorAiPresets.All.Select(p=>p.Label).ToArray(),
            SelectedIndex=Math.Max(0,BehaviorAiPresets.All.ToList().FindIndex(p=>p.Id==initial.Provider)),
            HorizontalAlignment=HorizontalAlignment.Stretch};
        var endpoint=new TextBox{Text=initial.Endpoint};
        var model=new TextBox{Text=initial.Model};
        var key=new TextBox{Text=initial.ApiKey,PasswordChar='●',Watermark="本机模型可留空"};
        var remember=new CheckBox{Content="在本机记住密钥",IsChecked=initial.RememberKey};
        var presetNote=Text(BehaviorAiPresets.Find(initial.Provider).Note,12,false,Muted);
        AutomationProperties.SetName(provider,"问路模型服务");
        AutomationProperties.SetName(endpoint,"问路接口地址");
        AutomationProperties.SetName(model,"问路模型名称");
        AutomationProperties.SetName(key,"问路 API Key");
        static string Origin(string? address) => Uri.TryCreate(address,UriKind.Absolute,out var u) ?
            u.GetLeftPart(UriPartial.Authority) : "";
        var lastOrigin=Origin(endpoint.Text);
        endpoint.TextChanged+=(_,_)=>
        {
            var next=Origin(endpoint.Text);
            if (lastOrigin!=next) { key.Text="";remember.IsChecked=false; }
            lastOrigin=next;
        };
        provider.SelectionChanged+=(_,_) =>
        {
            if (provider.SelectedIndex<0) return;
            var preset=BehaviorAiPresets.All[provider.SelectedIndex];
            key.Text="";remember.IsChecked=false;
            endpoint.Text=preset.Endpoint;model.Text=preset.Model;presetNote.Text=preset.Note;
        };
        navigatorStatus=Text(initial.Enabled ? "正在监听游戏问路…" : "需要接收 0.7.0 存档提问时可开启。",15,true);
        navigatorQuestion=Text("",14,false,Muted);
        navigatorQuestion.IsVisible=false;
        var check=MakeButton("立即检查",()=>CheckNavigatorAsync(true));
        check.IsEnabled=initial.Enabled;
        async Task Save()
        {
            if (provider.SelectedIndex<0) return;
            var preset=BehaviorAiPresets.All[provider.SelectedIndex];
            var next=new BehaviorAiSettings{Provider=preset.Id,Endpoint=endpoint.Text?.Trim() ?? "",Model=model.Text?.Trim() ?? "",
                ApiKey=key.Text?.Trim() ?? "",RememberKey=remember.IsChecked==true,Enabled=enabled.IsChecked==true};
            try { navigatorStore!.Save(next); }
            catch (Exception e) when(e is IOException or UnauthorizedAccessException)
            { enabled.IsChecked=navigatorSettings!.Enabled;navigatorStatus.Text="问路设置保存失败，请检查客户端设置目录权限。";return; }
            manualRequest?.Cancel();
            navigatorPoll?.Cancel();
            navigatorSettings=next;
            check.IsEnabled=next.Enabled;
            if (next.Enabled)
            {
                navigatorStatus.Text="已保存，正在检查游戏问路。";
                navigatorTimer.Start();await CheckNavigatorAsync(true);
            }
            else {navigatorTimer.Stop();navigatorQuestion.Text="";navigatorQuestion.IsVisible=false;navigatorStatus.Text="已停止接收游戏问路。";}
        }
        enabled.Click+=async (_,_)=>await Save();
        var fields=new Grid{ColumnDefinitions=new ColumnDefinitions("*,*"),RowDefinitions=new RowDefinitions("Auto,Auto"),ColumnSpacing=16,RowSpacing=12};
        Control Field(string title,Control child)=>new StackPanel{Spacing=5,Children={Text(title,12,true,Muted),child}};
        var items=new[]{Field("模型服务",provider),Field("接口地址",endpoint),Field("模型名称",model),Field("API Key",key)};
        for(int i=0;i<items.Length;i++){Grid.SetColumn(items[i],i%2);Grid.SetRow(items[i],i/2);fields.Children.Add(items[i]);}
        var modelPanel=new StackPanel {Spacing=12,Children={fields,presetNote,new StackPanel{Orientation=Orientation.Horizontal,
            Spacing=12,Children={MakeButton("保存模型设置",Save,true),remember}}}};
        var livePanel=BuildLiveQuestionPanel();
        var content=new StackPanel{Margin=new Thickness(36,24,36,30),Spacing=18,Children={
            Text("游戏问路",28,true),
            Text("在世界向导复制问题码，点「粘贴问题并询问」。答复可复制回游戏，立即查看分段导航。",14,false,Muted),
            Surface(livePanel),
            Surface(new StackPanel{Spacing=10,Children={Text("问路模型",18,true),modelPanel}}),
            new Expander{Header="旧版插件接收",Content=new StackPanel{Spacing=8,Children={enabled,navigatorStatus,navigatorQuestion,check}}},
            Text("仅发送问路框里的问题、匹配的任务候选、区域和阵营。云端模型按服务商规则计费。相同问题与游戏上下文可复用本机答案。",12,false,Muted)
        }};
        if (initial.Enabled) navigatorTimer.Start();
        return new ScrollViewer{Content=content,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};
    }
    private Control BuildLiveQuestionPanel()
    {
        int generation = navigatorGeneration;
        var question = Text(visibleQuestion?.Question ?? "", 18, true);
        var answer = Text(visibleAnswer);
        var status = Text("", 13, false, Muted);
        Button paste = null!, retry = null!;
        var copy = MakeButton("复制答复", async () =>
        {
            try
            {
                var clipboard = Clipboard ?? throw new InvalidOperationException();
                await clipboard.SetTextAsync(replyCode);
                status.Text = "答复已复制。回到游戏，在问路页的答复框粘贴。";
            }
            catch (Exception) { status.Text = "无法写入剪贴板，请再点一次「复制答复」。"; }
        });
        paste = MakeButton("粘贴问题并询问", () => Ask(true), true);
        retry = MakeButton("询问这个问题", () => Ask(false));
        void Render()
        {
            question.Text = visibleQuestion?.Question ?? "";
            answer.Text = visibleAnswer;
            question.IsVisible = visibleQuestion is not null;
            answer.IsVisible = visibleAnswer.Length > 0;
            copy.IsVisible = replyCode.Length > 0;
            paste.IsEnabled = manualRequest is null;
            retry.IsVisible = visibleQuestion is not null && replyCode.Length == 0;
            retry.IsEnabled = manualRequest is null;
        }
        async Task Ask(bool fromClipboard)
        {
            if (manualRequest is not null || navigatorModel is null || navigatorSettings is null) return;
            using var stop = new CancellationTokenSource();
            manualRequest = stop;
            Render();
            try
            {
                if (fromClipboard)
                {
                    var clipboard = Clipboard ?? throw new InvalidOperationException();
                    var incoming = NavigatorClipboard.ReadQuestion(await clipboard.TryGetTextAsync());
                    stop.Token.ThrowIfCancellationRequested();
                    visibleQuestion = incoming;
                }
                if (visibleQuestion is not { } target) return;
                visibleAnswer = replyCode = "";
                Render();
                status.Text = "正在查询…";
                var result = await navigatorModel.AnswerAsync(navigatorSettings, target, stop.Token);
                stop.Token.ThrowIfCancellationRequested();
                visibleAnswer = string.Join("\n", new[] { result.Answer.Message }
                    .Concat(result.Answer.Steps.Select((step, i) => $"{i + 1}. {step.Text}"))
                    .Where(line => line.Length > 0));
                replyCode = NavigatorClipboard.WriteReply(target, result.Answer);
                status.Text = result.FromCache ? "已找到本机保存的答复。" : "客户端已收到答复。";
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
            catch (BehaviorAiException e) { status.Text = e.Message; }
            catch (Exception) { status.Text = "无法完成查询，请检查剪贴板权限、网络和模型设置。"; }
            finally { if (manualRequest == stop) manualRequest = null; if (navigatorGeneration == generation) Render(); }
        }
        async Task RestoreSaved()
        {
            var selection = settings.GameDirectory;
            try
            {
                var saved = await Task.Run(() => navigatorBridge.LatestSavedQuestion(selection, CancellationToken.None));
                if (navigatorGeneration != generation || visibleQuestion is not null || manualRequest is not null || saved is null) return;
                visibleQuestion = saved;
                status.Text = "上次保存在游戏中的问题。";
                Render();
            }
            catch (Exception) { /* Manual transfer also works without a readable save. */ }
        }
        Render();
        if (visibleQuestion is null) _ = RestoreSaved();
        return new StackPanel {Spacing=10,Children={question, answer, status,
            new WrapPanel {Children={paste, retry, copy}}}};
    }

}
