using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace Aqw.SkuaMobile;

// Keep the user's script files unchanged. This adapter disables CoreBots' optional
// seasonal desktop prank, which creates WinForms windows and launches Windows tools.
// Do not provide fake WinForms classes or silently replace gameplay APIs.
internal sealed class MobileSourceAdapter : CSharpSyntaxRewriter
{
    public override SyntaxNode? VisitUsingDirective(UsingDirectiveSyntax node)
        => node.Name?.ToString() == "System.Windows.Forms" ? null : base.VisitUsingDirective(node);

    public override SyntaxNode? VisitMethodDeclaration(MethodDeclarationSyntax node)
    {
        if (node.Parent is ClassDeclarationSyntax { Identifier.ValueText: "CoreBots" }
            && node.Identifier.ValueText == "AprilFools"
            && node.Modifiers.Any(SyntaxKind.PrivateKeyword)
            && node.ReturnType is PredefinedTypeSyntax type && type.Keyword.IsKind(SyntaxKind.VoidKeyword)
            && node.ParameterList.Parameters.Count == 1)
        {
            return node.WithBody(SyntaxFactory.Block())
                .WithExpressionBody(null).WithSemicolonToken(default);
        }
        return base.VisitMethodDeclaration(node);
    }

    public static SyntaxTree Adapt(SyntaxTree tree)
    {
        if (!string.Equals(Path.GetFileName(tree.FilePath), "CoreBots.cs", StringComparison.OrdinalIgnoreCase))
            return tree;
        return tree.WithRootAndOptions(new MobileSourceAdapter().Visit(tree.GetRoot())!, tree.Options);
    }
}
