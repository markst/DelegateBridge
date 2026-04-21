import SwiftCompilerPlugin
import SwiftSyntaxMacros
import DelegateBridgeMacrosImpl

@main
struct DelegateBridgeMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AsyncStreamBridgeMacro.self,
    ]
}
