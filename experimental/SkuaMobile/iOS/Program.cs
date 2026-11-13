using Aqw.SkuaMobile;
using Foundation;
using UIKit;
using System.Diagnostics;

RuntimeTrace.Note("Managed Main entered");
AppDomain.CurrentDomain.UnhandledException += (_, e) => RuntimeTrace.Finish("FAIL: unhandled " + e.ExceptionObject);
try { UIApplication.Main(args, null, typeof(AppDelegate)); }
catch (Exception e)
{
    RuntimeTrace.Finish("FAIL: application startup " + e);
    throw;
}

internal static class RuntimeTrace
{
    private static readonly object Gate = new();
    private static readonly Stopwatch Clock = Stopwatch.StartNew();
    // Match the Foundation directory used by the simulator harness.
    internal static readonly string Documents = NSFileManager.DefaultManager
        .GetUrls(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomain.User)[0].Path!;

    internal static void Note(string message)
    {
        var line = $"AQW_RUNTIME {Clock.Elapsed.TotalSeconds:F2}s {message}";
        Console.WriteLine(line);
        lock (Gate)
        {
            Directory.CreateDirectory(Documents);
            File.AppendAllText(Path.Combine(Documents, "runtime-progress.txt"), line + "\n");
        }
    }

    internal static void Finish(string result)
    {
        Note(result);
        lock (Gate)
        {
            var destination = Path.Combine(Documents, "runtime-result.txt");
            File.WriteAllText(destination + ".tmp", result);
            File.Move(destination + ".tmp", destination, overwrite: true);
        }
    }
}

[Register("AppDelegate")]
public sealed class AppDelegate : UIApplicationDelegate
{
    public override UIWindow? Window { get; set; }

    public override bool FinishedLaunching(UIApplication application, NSDictionary? launchOptions)
    {
        RuntimeTrace.Note("FinishedLaunching entered");
        try
        {
            var controller = new UIViewController();
            var label = new UILabel { Lines = 0, Text = "Testing C# script execution…",
                TextAlignment = UITextAlignment.Center, TranslatesAutoresizingMaskIntoConstraints = false };
            controller.View!.BackgroundColor = UIColor.SystemBackground;
            controller.View.AddSubview(label);
            NSLayoutConstraint.ActivateConstraints([
                label.LeadingAnchor.ConstraintEqualTo(controller.View.SafeAreaLayoutGuide.LeadingAnchor, 24),
                label.TrailingAnchor.ConstraintEqualTo(controller.View.SafeAreaLayoutGuide.TrailingAnchor, -24),
                label.CenterYAnchor.ConstraintEqualTo(controller.View.CenterYAnchor)]);
            Window = new UIWindow(UIScreen.MainScreen.Bounds) { RootViewController = controller };
            Window.MakeKeyAndVisible();
            RuntimeTrace.Note("Window visible; scheduling script check");
            var bundlePath = NSBundle.MainBundle.BundlePath;
            _ = Task.Run(() =>
            {
                string result;
                try
                {
                    RuntimeTrace.Note("Worker started");
                    var root = Path.Combine(RuntimeTrace.Documents, "RuntimeCheck");
                    Directory.CreateDirectory(root);
                    File.WriteAllText(Path.Combine(root, "Entry.cs"), """
                        public class Entry {
                            public void ScriptMain(System.Collections.Generic.List<int> bot) {
                                bot.Add(40 + 2);
                            }
                        }
                        """);
                    var references = Directory.GetFiles(Path.Combine(bundlePath, "metadata"), "*.dll");
                    RuntimeTrace.Note($"Metadata files: {references.Length}; documents: {RuntimeTrace.Documents}");
                    if (references.Length == 0) throw new InvalidOperationException("Compiler metadata missing.");
                    var compiler = new ScriptCompiler(RuntimeTrace.Note);
                    var compiled = compiler.Compile(new ScriptPackageReader(root).Read("Entry.cs"), references);
                    if (!compiled.Success) throw new InvalidOperationException(string.Join('\n', compiled.Errors));
                    var output = new List<int>();
                    compiler.Execute(compiled, output);
                    if (!output.SequenceEqual([42])) throw new InvalidOperationException("Unexpected script result.");
                    result = "PASS: compiled and executed imported C# on this iOS runtime.\nGame bridge not included.";
                }
                catch (Exception e) { result = "FAIL: " + e; }
                RuntimeTrace.Finish(result);
                BeginInvokeOnMainThread(() => label.Text = result);
            });
            return true;
        }
        catch (Exception e)
        {
            RuntimeTrace.Finish("FAIL: FinishedLaunching " + e);
            return false;
        }
    }
}
