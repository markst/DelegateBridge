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

public struct ProtocolWitnessMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try DelegateBridgeMacrosImpl.ProtocolWitnessMacro.expansion(
            of: node,
            providingPeersOf: declaration,
            in: context
        )
    }
}

public struct DelegateBridgeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try DelegateBridgeMacrosImpl.DelegateBridgeMacro.expansion(
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
        ProtocolWitnessMacro.self,
        DelegateBridgeMacro.self,
    ]
}
