import SwiftCompilerPlugin
import SwiftSyntaxMacros
import DelegateBridgeMacrosImpl

public typealias AsyncStreamBridgeMacro = DelegateBridgeMacrosImpl.AsyncStreamBridgeMacro

@main
struct DelegateBridgeMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AsyncStreamBridgeMacro.self,
    ]
}
