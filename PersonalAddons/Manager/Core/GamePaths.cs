using System.Diagnostics;

namespace MyForeverManager.Core;

public static class GamePaths
{
    public static string Resolve(string selection)
    {
        if (string.IsNullOrWhiteSpace(selection)) throw new InvalidDataException("请先选择魔兽世界安装目录。");
        var path = Path.TrimEndingDirectorySeparator(PathSafety.Normalize(selection.Trim().Trim('"')));
        if (!Directory.Exists(path)) throw new DirectoryNotFoundException("选择的目录不存在，请重新选择。");
        if (Path.GetFileName(path).Equals("AddOns", StringComparison.OrdinalIgnoreCase)) path = Directory.GetParent(path)?.FullName ?? path;
        if (Path.GetFileName(path).Equals("Interface", StringComparison.OrdinalIgnoreCase)) path = Directory.GetParent(path)?.FullName ?? path;
        if (!Path.GetFileName(path).Equals("_forever_", StringComparison.OrdinalIgnoreCase)) path = Path.Combine(path, "_forever_");
        if (!Directory.Exists(path) || !Path.GetFileName(path).Equals("_forever_", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("未找到 _forever_。请选择国服《魔兽世界：无限》的游戏目录。");
        PathSafety.AssertNoLinks(path);
        bool hasClient = Directory.EnumerateFileSystemEntries(path).Any(p =>
            File.Exists(p) && new[] { "Wow.exe", "WowClassic.exe", "Wow-64.exe", "WowClassicT.exe", "WowT.exe", "WowB.exe" }.Contains(Path.GetFileName(p), StringComparer.OrdinalIgnoreCase)
            || Directory.Exists(p) && new[] { "World of Warcraft.app", "World of Warcraft Classic.app" }.Contains(Path.GetFileName(p), StringComparer.OrdinalIgnoreCase));
        if (!hasClient) throw new InvalidDataException("该 _forever_ 目录没有找到魔兽世界程序，请选择完整的游戏安装目录。");
        PathSafety.AssertNoLinks(AddonsDirectory(path));
        return path;
    }
    public static string AddonsDirectory(string gameDirectory) => Path.Combine(gameDirectory, "Interface", "AddOns");
}

public static class GameProcesses
{
    private static readonly HashSet<string> Names = new(StringComparer.OrdinalIgnoreCase)
    { "Wow", "Wow-64", "WowClassic", "WowClassicT", "WowT", "WowB", "World of Warcraft", "World of Warcraft Classic" };
    public static bool IsGameRunning()
    {
        try
        {
            foreach (var process in Process.GetProcesses())
            {
                using (process)
                {
                    try { if (Names.Contains(process.ProcessName) || process.ProcessName.StartsWith("World of War", StringComparison.OrdinalIgnoreCase)) return true; }
                    catch (InvalidOperationException) { }
                    catch (System.ComponentModel.Win32Exception) { }
                }
            }
            return false;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or PlatformNotSupportedException)
        { throw new IOException("无法检查游戏进程，暂缓安装。请关闭游戏后重试。", e); }
    }
}

internal static class PathSafety
{
    public static string Normalize(string path)
    {
        var full = Path.GetFullPath(path);
        // macOS supplies these root-owned aliases in system temp paths. Resolve only
        // these known aliases; arbitrary user symlinks and Windows junctions stay forbidden.
        if (OperatingSystem.IsMacOS())
            foreach (var alias in new[] { "/tmp", "/var" })
                if (full == alias || full.StartsWith(alias + "/", StringComparison.Ordinal))
                    return "/private" + full;
        return full;
    }
    public static void AssertNoLinks(string path)
    {
        var current = Normalize(path);
        while (true)
        {
            // GetAttributes also detects dangling symlinks, unlike Exists on some platforms.
            try
            {
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("不支持符号链接或目录联接，请选择普通游戏目录：" + current);
            }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
            var parent = Directory.GetParent(current);
            if (parent is null) break;
            current = parent.FullName;
        }
    }
    public static void AssertTreeSafe(string path)
    {
        AssertNoLinks(path);
        if (!Directory.Exists(path)) return;
        foreach (var entry in Directory.EnumerateFileSystemEntries(path))
        {
            AssertNoLinks(entry);
            if (Directory.Exists(entry)) AssertTreeSafe(entry);
        }
    }
    public static void CopyTree(string source, string destination)
    {
        AssertTreeSafe(source);
        AssertNoLinks(destination);
        Directory.CreateDirectory(destination);
        foreach (var sourceFile in Directory.EnumerateFiles(source)) File.Copy(sourceFile, Path.Combine(destination, Path.GetFileName(sourceFile)), false);
        foreach (var directory in Directory.EnumerateDirectories(source)) CopyTree(directory, Path.Combine(destination, Path.GetFileName(directory)));
    }
}
