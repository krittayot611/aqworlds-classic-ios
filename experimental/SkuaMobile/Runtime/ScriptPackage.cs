using System.Text.RegularExpressions;

namespace Aqw.SkuaMobile;

public sealed record ScriptSource(string Path, string Text);
public sealed record ScriptPackage(string EntryPath, IReadOnlyList<ScriptSource> Sources,
    IReadOnlyList<string> References);

// The imported directory is the package root (normally it contains Scripts/).
// Keep Windows-style includes working on case-sensitive mobile filesystems.
public sealed class ScriptPackageReader
{
    private readonly string root;
    private readonly Dictionary<string, string> files = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Regex Directive = new(@"^\s*//cs_(include|ref)\s+(.+?)\s*$");

    public ScriptPackageReader(string root)
    {
        this.root = System.IO.Path.GetFullPath(root);
        foreach (var path in Directory.EnumerateFiles(this.root, "*", SearchOption.AllDirectories))
        {
            // Imported packages must not escape through symbolic links.
            var info = new FileInfo(path);
            if (info.LinkTarget is not null) throw new IOException($"Symbolic link: {path}");
            for (var parent = info.Directory; parent is not null && parent.FullName != this.root; parent = parent.Parent)
                if (parent.LinkTarget is not null) throw new IOException($"Symbolic link: {parent.FullName}");
            var key = System.IO.Path.GetRelativePath(this.root, path).Replace('\\', '/');
            if (!files.TryAdd(key, path))
                throw new IOException($"Ambiguous case-insensitive package path: {key}");
        }
    }

    public ScriptPackage Read(string entry)
    {
        var sources = new List<ScriptSource>();
        var refs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        string entryPath = Resolve(null, entry);
        void Visit(string path)
        {
            // Include cycles are legal in existing Skua packs: each file is compiled once.
            if (!visited.Add(path)) return;
            var source = File.ReadAllText(path);
            sources.Add(new(path, source));
            using var reader = new StringReader(source);
            while (reader.ReadLine() is { } line)
            {
                var match = Directive.Match(line);
                if (!match.Success) continue;
                var dependency = Resolve(path, match.Groups[2].Value.Trim().Trim('"'));
                if (match.Groups[1].Value == "include") Visit(dependency);
                else refs.Add(dependency);
            }
        }
        Visit(entryPath);
        return new(entryPath, sources, refs.ToArray());
    }

    private string Resolve(string? owner, string requested)
    {
        requested = requested.Replace('\\', '/');
        if (System.IO.Path.IsPathRooted(requested) || requested.Contains(':'))
            throw new IOException($"Absolute paths are not portable: {requested}");
        var candidates = new List<string> { requested };
        if (owner is not null)
            candidates.Add(System.IO.Path.GetRelativePath(root, System.IO.Path.GetDirectoryName(owner)!) + "/" + requested);
        foreach (var candidate in candidates)
        {
            var full = System.IO.Path.GetFullPath(System.IO.Path.Combine(root, candidate));
            if (!full.StartsWith(root + System.IO.Path.DirectorySeparatorChar, StringComparison.Ordinal)) continue;
            var key = System.IO.Path.GetRelativePath(root, full).Replace('\\', '/');
            if (files.TryGetValue(key, out var actual)) return actual;
        }
        throw new FileNotFoundException($"Missing include/reference '{requested}' in {owner ?? "entry"}.");
    }
}
