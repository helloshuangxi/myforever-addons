#if SELF_UPDATE_PROBE
using System.Text.Json;
using MyForeverManager.Core;

namespace MyForeverManager.Desktop;

// Compiled only into explicitly requested isolated packaging test fixtures.
internal static class SelfUpdateProbe
{
    internal static async Task RunAsync(string[] args)
    {
        if (args.Length != 2) throw new ArgumentException("Expected isolated fixture directory.");
        var fixture = Path.GetFullPath(args[1]);
        if (!fixture.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.Ordinal) || !File.Exists(Path.Combine(fixture, "fixture.json")))
            throw new ArgumentException("Updater probe requires a temporary fixture.");
        using var backend = new ManagerAppUpdateBackend(Path.Combine(fixture, "feed"));
        if (args[0] == "--self-update-probe-record")
        {
            File.WriteAllText(Path.Combine(fixture, "restarted.json"), JsonSerializer.Serialize(new { backend.IsInstalled, version = backend.InstalledVersion }));
            return;
        }
        var updates = new ManagerAppUpdates(backend);
        await updates.CheckAndDownloadAsync(automatic: true, enabled: true);
        File.WriteAllText(Path.Combine(fixture, "downloaded.json"), JsonSerializer.Serialize(new
        { backend.IsInstalled, version = backend.InstalledVersion, target = updates.ReadyRelease?.Version, phase = updates.Phase.ToString() }));
        if (!updates.IsReady) { Environment.ExitCode = 2; return; }
        backend.ApplyProbe(fixture);
    }
}
#endif
