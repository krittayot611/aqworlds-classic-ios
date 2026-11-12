using Aqw.SkuaMobile;
using Foundation;
using UIKit;

UIApplication.Main(args, null, typeof(AppDelegate));

[Register("AppDelegate")]
public sealed class AppDelegate : UIApplicationDelegate
{
    public override UIWindow? Window { get; set; }
    public override bool FinishedLaunching(UIApplication application, NSDictionary launchOptions)
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
        _ = Task.Run(() =>
        {
            string result;
            try
            {
                var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "RuntimeCheck");
                Directory.CreateDirectory(root);
                File.WriteAllText(Path.Combine(root, "Entry.cs"), """
                    public class Entry {
                        public void ScriptMain(System.Collections.Generic.List<int> bot) {
                            bot.Add(40 + 2);
                        }
                    }
                    """);
                var references = Directory.GetFiles(Path.Combine(NSBundle.MainBundle.BundlePath, "metadata"), "*.dll");
                if (references.Length == 0) throw new InvalidOperationException("Compiler metadata missing.");
                var compiler = new ScriptCompiler();
                var compiled = compiler.Compile(new ScriptPackageReader(root).Read("Entry.cs"), references);
                if (!compiled.Success) throw new InvalidOperationException(string.Join('\n', compiled.Errors));
                var output = new List<int>();
                compiler.Execute(compiled, output);
                if (!output.SequenceEqual([42])) throw new InvalidOperationException("Unexpected script result.");
                result = "PASS: compiled and executed imported C# on this iOS runtime.\nGame bridge not included.";
            }
            catch (Exception e) { result = "FAIL: " + e; }
            File.WriteAllText(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "runtime-result.txt"), result);
            BeginInvokeOnMainThread(() => label.Text = result);
        });
        return true;
    }
}
