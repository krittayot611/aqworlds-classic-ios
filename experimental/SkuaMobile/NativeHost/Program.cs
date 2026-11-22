using System.Runtime.InteropServices;
using Aqw.SkuaMobile;

internal static class Program
{
    public static void Main(string[] args) { }

    // Called by a native worker. UIKit and AIR keep ownership of their main loop.
    // This is a developer integration gate, not a production bot API.
    [UnmanagedCallersOnly(EntryPoint = "aqw_host_run_check")]
    public static int RunCheck(nint metadataUtf8, nint documentsUtf8)
    {
        string? documents = null;
        try
        {
            var metadata = Marshal.PtrToStringUTF8(metadataUtf8) ?? throw new ArgumentException("Metadata path missing.");
            documents = Marshal.PtrToStringUTF8(documentsUtf8) ?? throw new ArgumentException("Documents path missing.");
            Directory.CreateDirectory(documents);
            void Note(string line) => File.AppendAllText(Path.Combine(documents, "runtime-progress.txt"), line + "\n");
            Note("Native host entered managed export; no managed UIApplicationMain.");
            var culture = System.Globalization.CultureInfo.GetCultureInfo("th-TH");
            if (culture.Name != "th-TH") throw new InvalidOperationException("Native culture lookup failed.");
            Note("Native file and globalization calls passed.");
            BridgeChecks.Run().GetAwaiter().GetResult();
            Note("Bridge mailbox checks passed in native host.");
            var root = Path.Combine(documents, "NativeHostCheck");
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, "Entry.cs"), """
                public class Entry {
                    public void ScriptMain(System.Collections.Generic.List<int> bot) { bot.Add(40 + 2); }
                }
                """);
            var references = Directory.GetFiles(metadata, "*.dll");
            if (references.Length == 0) throw new InvalidOperationException("Compiler metadata missing.");
            var compiler = new ScriptCompiler(Note);
            var compiled = compiler.Compile(new ScriptPackageReader(root).Read("Entry.cs"), references);
            if (!compiled.Success) throw new InvalidOperationException(string.Join('\n', compiled.Errors));
            var output = new List<int>();
            compiler.Execute(compiled, output);
            if (!output.SequenceEqual([42])) throw new InvalidOperationException("Unexpected native host script result.");
            File.WriteAllText(Path.Combine(documents, "runtime-result.txt"),
                "PASS: native app hosted Mono, executed imported C# and passed bridge mailbox checks. AIR not connected.");
            return 0;
        }
        catch (Exception error)
        {
            try
            {
                if (documents is not null) File.WriteAllText(Path.Combine(documents, "runtime-result.txt"), "FAIL: native host " + error);
            }
            catch { /* Never unwind a managed exception across the native ABI. */ }
            Console.Error.WriteLine(error);
            return 1;
        }
    }
}
