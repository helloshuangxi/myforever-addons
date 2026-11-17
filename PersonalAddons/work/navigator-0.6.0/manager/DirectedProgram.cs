using MyForeverManager.Core;
using System.Net;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;

var site = Path.GetFullPath(args[0]);
var live = args.Contains("--live");
var oldRelease = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(site,"navigator","releases.json"))).RootElement
    .GetProperty("releases").EnumerateArray().Single(row=>row.GetProperty("version").GetString()=="0.5.0").Deserialize<ReleaseManifest>()!;
var desired = JsonSerializer.Deserialize<ReleaseManifest>(File.ReadAllBytes(Path.Combine(site,"navigator","latest.json")))!;
if (desired.Version!="0.6.0") throw new Exception("Frozen manifest must be 0.6.0");
var oldBytes = File.ReadAllBytes(Path.Combine(site,"downloads",oldRelease.Download.Filename));
var desiredBytes = File.ReadAllBytes(Path.Combine(site,"downloads",desired.Download.Filename));
var nav = AddonCatalog.All.Single(a=>a.Id=="MyForeverNavigator");
var fixture=Directory.CreateDirectory(Path.Combine("/private/tmp","navigator-060-manager-050-"+Guid.NewGuid().ToString("N"))).FullName;
var checks=0;
void Verify(bool ok,string text) { if (!ok) throw new Exception(text); Console.WriteLine("PASS "+text); checks++; }
string Game(string key) {
    string game=Path.Combine(fixture,key,"_forever_");
    Directory.CreateDirectory(game);
    File.WriteAllText(Path.Combine(game,"Wow.exe"),"fixture only");
    return game;
}
void VerifyTree(string game, byte[] bytes, string message) {
    string dir = Path.Combine(GamePaths.AddonsDirectory(game),nav.Id);
    using var zip=new ZipArchive(new MemoryStream(bytes));
    var actual=Directory.EnumerateFiles(dir,"*",SearchOption.AllDirectories).ToDictionary(p=>nav.Id+"/"+Path.GetRelativePath(dir,p));
    var expected=zip.Entries.Where(e=>e.Name!="").ToDictionary(e=>e.FullName);
    Verify(actual.Keys.ToHashSet().SetEquals(expected.Keys),message+" file list matches the ZIP");
    foreach (var (name,file) in actual) {
        using var fileInput=File.OpenRead(file); using var zipInput=expected[name].Open();
        if (!SHA256.HashData(fileInput).SequenceEqual(SHA256.HashData(zipInput))) throw new Exception("Mismatched file "+name);
    }
    Verify(true,message+" every file matches SHA-256 ("+actual.Count+" entries)");
}
HttpClient FileEndpoint(ReleaseManifest manifest,byte[] bytes) => new(new FixtureHttp(message=>{
    string url=message.RequestUri?.AbsoluteUri??"";
    byte[] body = url==nav.ManifestUrl ? JsonSerializer.SerializeToUtf8Bytes(manifest):
        url==manifest.Download.Url ? bytes : throw new InvalidOperationException("Unexpected request");
    return new HttpResponseMessage(HttpStatusCode.OK){RequestMessage=message, Content=new ByteArrayContent(body)};
}));
try {
    Verify(oldRelease.Download.Sha256.Equals(Convert.ToHexString(SHA256.HashData(oldBytes)),StringComparison.OrdinalIgnoreCase),"official 0.5.0 archive hash matches release record");
    Verify(desired.Download.Sha256.Equals(Convert.ToHexString(SHA256.HashData(desiredBytes)),StringComparison.OrdinalIgnoreCase),"0.6.0 archive hash matches frozen release");
    using var client=live ? null : FileEndpoint(desired,desiredBytes);
    using var service=new UpdateService(client:client,isGameRunning:()=>false);
    var newGame=Game("fresh");
    var status=await service.CheckAsync(nav,newGame);
    if(status.Error!=null)throw new Exception(status.Error);
    Verify(status.Error==null && status.CanInstall && status.Latest?.Version=="0.6.0" && status.InstalledVersion==null,"0.6.0 is offered to a clean fake game");
    Verify(status.Latest!.Download.Sha256==desired.Download.Sha256 && status.Latest.Download.SizeBytes==desired.Download.SizeBytes,"retrieved latest manifest matches frozen hash and size");
    await service.InstallAsync(nav,status.Latest,newGame);
    Verify(UpdateService.ReadInstalledVersion(nav,newGame)=="0.6.0" && !service.HasBackup(nav,newGame),"fresh install records 0.6.0 without creating backup");
    VerifyTree(newGame,desiredBytes,"fresh install");
    var game=Game("update");
    using var oldClient=FileEndpoint(oldRelease,oldBytes);
    using var oldService=new UpdateService(client:oldClient,isGameRunning:()=>false);
    await oldService.InstallAsync(nav,oldRelease,game);
    VerifyTree(game,oldBytes,"actual older install");
    var settings=Path.Combine(game,"WTF","Account","fixture","SavedVariables","MyForeverNavigator.lua");
    var sibling=Path.Combine(GamePaths.AddonsDirectory(game),"AnotherFixtureAddon","untouched.txt");
    Directory.CreateDirectory(Path.GetDirectoryName(settings)!);Directory.CreateDirectory(Path.GetDirectoryName(sibling)!);
    File.WriteAllText(settings,"synthetic settings marker");File.WriteAllText(sibling,"synthetic sibling marker");
    status=await service.CheckAsync(nav,game);
    Verify(status.CanInstall && status.Error==null && status.InstalledVersion=="0.5.0" && status.Latest?.Version=="0.6.0","manager offers update from actual 0.5.0 to 0.6.0");
    await service.InstallAsync(nav,status.Latest!,game);
    Verify(UpdateService.ReadInstalledVersion(nav,game)=="0.6.0" && service.HasBackup(nav,game),"selected addon updates and has backup");
    VerifyTree(game,desiredBytes,"updated install");
    Verify(File.ReadAllText(settings)=="synthetic settings marker" && File.ReadAllText(sibling)=="synthetic sibling marker","update preserves fake game settings and other addon");
    using var active=new UpdateService(client:client,isGameRunning:()=>true);
    bool blocked=false;
    try { await active.RestoreAsync(nav,game); } catch (IOException ex) when (ex.Message.Contains("游戏正在运行")) { blocked=true; }
    Verify(blocked && UpdateService.ReadInstalledVersion(nav,game)=="0.6.0","running-game guard defers restore");
    blocked=false;
    try { await active.InstallAsync(nav,desired,game); } catch (IOException ex) when (ex.Message.Contains("游戏正在运行")) { blocked=true; }
    Verify(blocked && UpdateService.ReadInstalledVersion(nav,game)=="0.6.0","running-game guard defers install");
    await service.RestoreAsync(nav,game);
    Verify(UpdateService.ReadInstalledVersion(nav,game)=="0.5.0","manager restores previous official 0.5.0");
    VerifyTree(game,oldBytes,"restored install");
    Verify(File.ReadAllText(settings)=="synthetic settings marker" && File.ReadAllText(sibling)=="synthetic sibling marker","restore preserves fake game settings and other addon");
    Console.WriteLine($"RESULT: {checks} passed, 0 failed ({(live?"live HTTPS":"frozen manifest and archives")}; selected Navigator only)");
} finally { Directory.Delete(fixture,true); }
sealed class FixtureHttp(Func<HttpRequestMessage,HttpResponseMessage> respond):HttpMessageHandler {
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage req,CancellationToken t) { t.ThrowIfCancellationRequested();return Task.FromResult(respond(req));}
}
