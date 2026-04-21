import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros
import DelegateBridgeMacrosImpl

public struct AsyncStreamBridgeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try DelegateBridgeMacrosImpl.AsyncStreamBridgeMacro.expansion(
            of: node,
            providingPeersOf: declaration,
            in: context
        )
    }
}

@main
struct DelegateBridgeMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AsyncStreamBridgeMacro.self,
    ]
}
