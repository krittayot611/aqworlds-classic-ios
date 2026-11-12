using Aqw.SkuaMobile;
using System.Reflection;
using System.Text.Json;

var platformRefs = ((string?)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES"))!
    .Split(Path.PathSeparator);
var compiler = new ScriptCompiler();
if (args.Length > 0)
{
    if (args.Length != 3) throw new ArgumentException("Expected: package-root assembly-directory entry-path");
    var package = new ScriptPackageReader(args[0]).Read(args[2]);
    var references = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    foreach (var path in platformRefs.Concat(Directory.EnumerateFiles(args[1], "*.dll")))
    {
        try
        {
            var name = AssemblyName.GetAssemblyName(path).Name!;
            // Retain host framework assemblies, then add only new library identities.
            references.TryAdd(name, path);
        }
        catch (BadImageFormatException) { }
    }
    var result = compiler.Compile(package, references.Values);
    Console.WriteLine(JsonSerializer.Serialize(new
    {
        entry = args[2], sources = package.Sources.Count,
        compiled = result.Success, executed = false,
        adaptations = package.Sources.Any(s => Path.GetFileName(s.Path) == "CoreBots.cs")
            ? new[] { "CoreBots seasonal desktop prank disabled in memory; original files unchanged." } : [],
        errors = result.Errors
    }, new JsonSerializerOptions { WriteIndented = true }));
    return result.Success ? 0 : 1;
}

var root = Path.Combine(Path.GetTempPath(), "aqw-check-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(Path.Combine(root, "Scripts", "Shared"));
int passed = 0;
void Check(bool condition, string label)
{
    if (!condition) throw new Exception("FAIL: " + label);
    passed++;
    Console.WriteLine("PASS: " + label);
}
void Write(string path, string text) => File.WriteAllText(Path.Combine(root, path), text);
try
{
    Write("Scripts/Shared/Helper.cs", """
        //cs_include Scripts/Main.cs
        public class Helper { public static int Value => 41; public void ScriptMain(object bot) { throw new System.Exception("Wrong entry"); } }
        """);
    Write("Scripts/Main.cs", """
        //cs_include scripts\shared\helper.cs
        //cs_include Scripts/Shared/Helper.cs
        public class Entry { public void ScriptMain(System.Collections.Generic.List<int> bot) { bot.Add(Helper.Value + 1); } }
        """);
    var reader = new ScriptPackageReader(root);
    var package = reader.Read("scripts/main.cs");
    Check(package.Sources.Count == 2, "case-insensitive Windows paths, duplicate includes and cycles");
    var result = compiler.Compile(package, platformRefs);
    Check(result.Success, "compile unchanged entry and included source: " + string.Join('\n', result.Errors));
    var output = new List<int>();
    compiler.Execute(result, output);
    Check(output.SequenceEqual([42]), "execute entry, not included helper ScriptMain");
    Write("Scripts/Main.cs", "//cs_include Missing.cs\npublic class Entry {}\n");
    try { reader.Read("Scripts/Main.cs"); Check(false, "missing include rejected"); }
    catch (FileNotFoundException) { Check(true, "missing include rejected before execution"); }
    Write("Scripts/Main.cs", "//cs_include ../../outside.cs\n");
    try { reader.Read("Scripts/Main.cs"); Check(false, "path escape rejected"); }
    catch (FileNotFoundException) { Check(true, "path escape rejected"); }
    Write("Scripts/Main.cs", "public class Broken { public void ScriptMain(object bot) { no_such_api(); } }");
    result = compiler.Compile(reader.Read("Scripts/Main.cs"), platformRefs);
    Check(!result.Success && result.Errors.Any(e => e.Contains("Main.cs")), "compiler errors retain source filename");
    Write("Scripts/Main.cs", "public class AsyncEntry { public async void ScriptMain(object bot) { await System.Threading.Tasks.Task.Delay(1); } }");
    Check(!compiler.Compile(reader.Read("Scripts/Main.cs"), platformRefs).Success, "async void entry rejected, never report completion early");
    Write("Scripts/Main.cs", "public class A { public void ScriptMain(object bot) {} } public class B { public void ScriptMain(object bot) {} }");
    Check(!compiler.Compile(reader.Read("Scripts/Main.cs"), platformRefs).Success, "ambiguous entry rejected");
    Write("Scripts/CoreBots.cs", """
        using System.Windows.Forms;
        public class CoreBots {
            private void AprilFools(int Case = -1) { using Form form = new(); }
            public void ScriptMain(System.Collections.Generic.List<int> bot) { AprilFools(); bot.Add(7); }
        }
        """);
    var original = File.ReadAllText(Path.Combine(root, "Scripts/CoreBots.cs"));
    result = compiler.Compile(new ScriptPackageReader(root).Read("Scripts/CoreBots.cs"), platformRefs);
    Check(result.Success, "mobile adapter removes only desktop seasonal prank");
    output.Clear();
    compiler.Execute(result, output);
    Check(output.SequenceEqual([7]) && File.ReadAllText(Path.Combine(root, "Scripts/CoreBots.cs")) == original,
        "adapted script executes and imported file is unchanged");
    Write("Scripts/main.cs", "");
    try { _ = new ScriptPackageReader(root); Check(false, "case collision rejected"); }
    catch (IOException) { Check(true, "case collision rejected"); }
    Console.WriteLine($"{passed} checks passed. Host execution only; not an iOS or game integration test.");
}
finally { Directory.Delete(root, recursive: true); }
return 0;
