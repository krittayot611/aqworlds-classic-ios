using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.Reflection;
using System.Runtime.Loader;

namespace Aqw.SkuaMobile;

public sealed record CompilationResult(byte[]? Assembly, string? EntryType, IReadOnlyList<string> Errors)
{
    public bool Success => Assembly is not null && EntryType is not null && Errors.Count == 0;
}

public sealed class ScriptCompiler
{
    private readonly Action<string>? report;

    public ScriptCompiler(Action<string>? report = null) => this.report = report;

    // References are supplied explicitly. iOS must bundle metadata: Assembly.Location
    // and the desktop TRUSTED_PLATFORM_ASSEMBLIES list are not portable reference sources.
    public CompilationResult Compile(ScriptPackage package, IEnumerable<string> referencePaths,
        CancellationToken cancellationToken = default)
    {
        report?.Invoke("Parsing script sources");
        var options = CSharpParseOptions.Default.WithLanguageVersion(LanguageVersion.Preview);
        var trees = package.Sources.Select(s => CSharpSyntaxTree.ParseText(s.Text, options,
            s.Path, cancellationToken: cancellationToken)).Select(MobileSourceAdapter.Adapt).ToList();
        trees.Add(CSharpSyntaxTree.ParseText("""
            global using System;
            global using System.Collections.Generic;
            global using System.Linq;
            global using System.Threading;
            global using System.Threading.Tasks;
            """, options));
        report?.Invoke("Reading compiler metadata");
        var refs = referencePaths.Concat(package.References).Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(path => MetadataReference.CreateFromFile(path)).ToArray();
        report?.Invoke($"Creating compilation with {refs.Length} references");
        var compilation = CSharpCompilation.Create("MobileScript_" + Guid.NewGuid().ToString("N"),
            trees, refs, new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary,
                optimizationLevel: OptimizationLevel.Release, allowUnsafe: false));
        using var output = new MemoryStream();
        report?.Invoke("Emitting managed IL");
        var emitted = compilation.Emit(output, cancellationToken: cancellationToken);
        if (!emitted.Success)
            return new(null, null, emitted.Diagnostics.Where(d => d.Severity == DiagnosticSeverity.Error)
                .Select(d => d.ToString()).ToArray());

        // Select only ScriptMain declared in the requested entry file; included helper
        // scripts can also declare ScriptMain and must never be run by accident.
        report?.Invoke("Resolving ScriptMain");
        var entryTree = trees.Single(t => t.FilePath == package.EntryPath);
        var model = compilation.GetSemanticModel(entryTree);
        var entries = entryTree.GetRoot(cancellationToken).DescendantNodes()
            .OfType<MethodDeclarationSyntax>()
            .Select(m => model.GetDeclaredSymbol(m, cancellationToken))
            .OfType<IMethodSymbol>()
            .Where(m => m.Name == "ScriptMain" && m.DeclaredAccessibility == Accessibility.Public
                && !m.IsStatic && m.ReturnsVoid && !m.IsAsync && m.Parameters.Length == 1
                && m.ContainingType.ContainingType is null && !m.ContainingType.IsGenericType)
            .Select(m => m.ContainingType.ToDisplayString()).Distinct().ToArray();
        if (entries.Length != 1)
            return new(null, null, ["Entry file must define exactly one public synchronous void ScriptMain(bot)."]);
        return new(output.ToArray(), entries[0], []);
    }

    // This executes managed IL on the host runtime. Passing on desktop is not proof
    // of execution on iOS: the release iOS interpreter must be tested separately.
    public void Execute(CompilationResult result, object bot)
    {
        if (!result.Success) throw new InvalidOperationException(string.Join('\n', result.Errors));
        report?.Invoke("Creating script load context");
        var context = new AssemblyLoadContext("MobileScript", isCollectible: true);
        try
        {
            using var input = new MemoryStream(result.Assembly!);
            report?.Invoke("Loading managed IL");
            var assembly = context.LoadFromStream(input);
            report?.Invoke("Resolving script entry type");
            var type = assembly.GetType(result.EntryType!, throwOnError: true)!;
            var methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
                .Where(m => m.Name == "ScriptMain" && m.ReturnType == typeof(void)
                    && m.GetParameters().Length == 1 && m.GetParameters()[0].ParameterType.IsInstanceOfType(bot))
                .ToArray();
            if (methods.Length != 1) throw new InvalidOperationException("ScriptMain does not match the supplied bot interface.");
            var instance = Activator.CreateInstance(type)!;
            report?.Invoke("Invoking ScriptMain");
            methods[0].Invoke(instance, [bot]);
            report?.Invoke("ScriptMain returned");
        }
        finally
        {
            report?.Invoke("Unloading script context");
            context.Unload();
        }
    }
}
