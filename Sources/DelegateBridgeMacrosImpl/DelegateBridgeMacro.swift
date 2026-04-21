import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

// MARK: - Diagnostics

enum DelegateBridgeDiagnostic: DiagnosticMessage {
    case notAProtocol
    case voidReturnRequired(method: String)
    case noMethods

    var message: String {
        switch self {
        case .notAProtocol:
            return "@AsyncStreamBridge can only be applied to protocols"
        case .voidReturnRequired(let method):
            return "Delegate method '\(method)' must return Void to be bridged to AsyncStream"
        case .noMethods:
            return "@AsyncStreamBridge requires at least one method in the protocol"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAProtocol:       return .init(domain: "DelegateBridge", id: "notAProtocol")
        case .voidReturnRequired: return .init(domain: "DelegateBridge", id: "voidReturnRequired")
        case .noMethods:          return .init(domain: "DelegateBridge", id: "noMethods")
        }
    }

    var severity: DiagnosticSeverity { .error }
}

// MARK: - Helpers

private extension FunctionParameterSyntax {
    /// The label used when calling the function (second name wins, else first name)
    var callLabel: String {
        if let second = secondName { return second.text }
        return firstName.text
    }

    var typeText: String { type.trimmedDescription }
}

private extension FunctionSignatureSyntax {
    var isVoidReturn: Bool {
        guard let ret = returnClause else { return true }
        let t = ret.type.trimmedDescription
        return t == "Void" || t == "()"
    }
}

// MARK: - @AsyncStreamBridge

/// Applied to a protocol. Generates:
///   1. A concrete `<Protocol>AsyncBridge` class that implements the protocol
///      and exposes one `AsyncStream<Event>` per method (or a unified enum stream).
///   2. A protocol-witness struct `<Protocol>Witness` mirroring each method
///      as a closure property, with a static factory that wraps an `AsyncStream` source.
public struct AsyncStreamBridgeMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // ── 1. Validate target ───────────────────────────────────────────────
        guard let proto = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: DelegateBridgeDiagnostic.notAProtocol
            ))
            return []
        }

        let protoName = proto.name.text

        // ── 2. Collect methods ───────────────────────────────────────────────
        let methods: [FunctionDeclSyntax] = proto.memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }

        guard !methods.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: DelegateBridgeDiagnostic.noMethods
            ))
            return []
        }

        // Only bridge void-returning methods; warn on others
        let bridgeable = methods.filter { fn in
            guard fn.signature.isVoidReturn else {
                context.diagnose(Diagnostic(
                    node: fn,
                    message: DelegateBridgeDiagnostic.voidReturnRequired(method: fn.name.text)
                ))
                return false
            }
            return true
        }

        // ── 3. Build Event enum ──────────────────────────────────────────────
        let eventEnum   = buildEventEnum(protoName: protoName, methods: bridgeable)

        // ── 4. Build Bridge class ────────────────────────────────────────────
        let bridgeClass = buildBridgeClass(protoName: protoName, methods: bridgeable)

        // ── 5. Build Witness struct ──────────────────────────────────────────
        let witnessStruct = buildWitnessStruct(protoName: protoName, methods: bridgeable)

        return [
            DeclSyntax(eventEnum),
            DeclSyntax(bridgeClass),
            DeclSyntax(witnessStruct),
        ]
    }
}

// MARK: - Event Enum Builder

private func buildEventEnum(
    protoName: String,
    methods: [FunctionDeclSyntax]
) -> EnumDeclSyntax {
    let cases = methods.map { fn -> String in
        let params = fn.signature.parameterClause.parameters
        if params.isEmpty {
            return "    case \(fn.name.text)"
        } else {
            let assoc = params.map { p in
                let label = p.firstName.text == "_" ? "" : "\(p.firstName.text): "
                return "\(label)\(p.typeText)"
            }.joined(separator: ", ")
            return "    case \(fn.name.text)(\(assoc))"
        }
    }.joined(separator: "\n")

    let src = """
    /// Auto-generated event enum for `\(protoName)` delegate bridge.
    enum \(protoName)Event: Sendable {
    \(cases)
    }
    """
    return try! EnumDeclSyntax("\(raw: src)")
}

// MARK: - Bridge Class Builder

private func buildBridgeClass(
    protoName: String,
    methods: [FunctionDeclSyntax]
) -> ClassDeclSyntax {

    // Build per-method stream properties + method implementations
    var body = """
        // MARK: - Unified event stream
        let _continuation: AsyncStream<\(protoName)Event>.Continuation
        
        /// A single stream delivering all delegate events as `\(protoName)Event` cases.
        let events: AsyncStream<\(protoName)Event>
        
        override init() {
            var cont: AsyncStream<\(protoName)Event>.Continuation!
            events = AsyncStream { cont = $0 }
            _continuation = cont
        }
        
        deinit { _continuation.finish() }
        
        /// Finish the stream (call when the delegate owner is torn down).
        func finish() { _continuation.finish() }

    """

    // Protocol method implementations
    body += "    // MARK: - \(protoName) conformance\n"
    for fn in methods {
        let methodName = fn.name.text
        let params = fn.signature.parameterClause.parameters

        // Signature
        let paramList = params.map { p -> String in
            let ext = p.firstName.text
            let int = p.secondName?.text ?? ext
            if ext == int {
                return "\(ext): \(p.typeText)"
            } else {
                return "\(ext) \(int): \(p.typeText)"
            }
        }.joined(separator: ", ")

        // Event yield
        let eventYield: String
        if params.isEmpty {
            eventYield = "_continuation.yield(.\(methodName))"
        } else {
            let args = params.map { p -> String in
                let label = p.firstName.text == "_" ? "" : p.firstName.text
                let varName = p.secondName?.text ?? p.firstName.text
                if label.isEmpty {
                    return varName
                } else {
                    return "\(label): \(varName)"
                }
            }.joined(separator: ", ")
            eventYield = "_continuation.yield(.\(methodName)(\(args)))"
        }

        body += """
            
            func \(methodName)(\(paramList)) {
                \(eventYield)
            }

        """
    }

    let src = """
    /// Auto-generated bridge class that conforms to `\(protoName)` and exposes
    /// delegate callbacks as `AsyncStream` events.
    ///
    /// Usage:
    /// ```swift
    /// let bridge = \(protoName)AsyncBridge()
    /// myObject.delegate = bridge
    /// for await event in bridge.events {
    ///     switch event { ... }
    /// }
    /// ```
    final class \(protoName)AsyncBridge: NSObject, \(protoName) {
    \(body)
    }
    """
    return try! ClassDeclSyntax("\(raw: src)")
}

// MARK: - Witness Struct Builder

private func buildWitnessStruct(
    protoName: String,
    methods: [FunctionDeclSyntax]
) -> ClassDeclSyntax {

    let I1 = "    "        // 1-level indent (inside class body)
    let I2 = I1 + I1       // 2-level indent (inside method body)
    let I3 = I2 + I1       // 3-level indent (arguments in multi-line calls)

    // Private closure storage. Prefixed with `_` to avoid redeclaration
    // conflicts with same-named protocol methods (especially zero-arg ones).
    let closureProps = methods.map { fn -> String in
        let params = fn.signature.parameterClause.parameters
        let paramTypes = params.map(\.typeText).joined(separator: ", ")
        return "\(I1)private let _\(fn.name.text): (\(paramTypes)) -> Void"
    }.joined(separator: "\n")

    // Designated init: takes one closure per method.
    let initParamList = methods.map { fn -> String in
        let params = fn.signature.parameterClause.parameters
        let types = params.map(\.typeText).joined(separator: ", ")
        return "\(fn.name.text): @escaping (\(types)) -> Void"
    }.joined(separator: ",\n\(I2)")

    let initAssignments = methods.map { fn in
        "\(I2)self._\(fn.name.text) = \(fn.name.text)"
    }.joined(separator: "\n")

    let designatedInit = """
    \(I1)init(
    \(I2)\(initParamList)
    \(I1)) {
    \(initAssignments)
    \(I1)}
    """

    // Convenience init wrapping a concrete delegate value.
    let concreteAssignments = methods.map { fn -> String in
        let params = fn.signature.parameterClause.parameters
        let closure: String
        if params.isEmpty {
            closure = "{ delegate.\(fn.name.text)() }"
        } else {
            let argNames = params.map { p in p.secondName?.text ?? p.firstName.text }
            let callArgs = params.map { p -> String in
                let ext = p.firstName.text
                let int = p.secondName?.text ?? ext
                if ext == "_" { return int }
                return "\(ext): \(int)"
            }.joined(separator: ", ")
            closure = "{ \(argNames.joined(separator: ", ")) in delegate.\(fn.name.text)(\(callArgs)) }"
        }
        return "\(I3)\(fn.name.text): \(closure)"
    }.joined(separator: ",\n")

    let concreteInit = """
    \(I1)convenience init(delegate: some \(protoName)) {
    \(I2)self.init(
    \(concreteAssignments)
    \(I2))
    \(I1)}
    """

    // Static factory building a witness backed by an AsyncStream bridge.
    let bridgeAssignments = methods.map { fn -> String in
        let params = fn.signature.parameterClause.parameters
        let argNames = (0..<params.count).map { "a\($0)" }
        let closure: String
        if argNames.isEmpty {
            closure = "{ bridge._continuation.yield(.\(fn.name.text)) }"
        } else {
            let yieldArgs = params.enumerated().map { (i, p) -> String in
                let label = p.firstName.text == "_" ? "" : p.firstName.text
                let v = argNames[i]
                return label.isEmpty ? v : "\(label): \(v)"
            }.joined(separator: ", ")
            closure = "{ \(argNames.joined(separator: ", ")) in bridge._continuation.yield(.\(fn.name.text)(\(yieldArgs))) }"
        }
        return "\(I3)\(fn.name.text): \(closure)"
    }.joined(separator: ",\n")

    let bridgeFactory = """
    \(I1)static func streamBacked(_ bridge: \(protoName)AsyncBridge) -> Self {
    \(I2).init(
    \(bridgeAssignments)
    \(I2))
    \(I1)}
    """

    // Protocol conformance: forward to the underscored stored closure.
    let conformanceImpl = methods.map { fn -> String in
        let params = fn.signature.parameterClause.parameters
        let paramList = params.map { p -> String in
            let ext = p.firstName.text
            let int = p.secondName?.text ?? ext
            if ext == int {
                return "\(ext): \(p.typeText)"
            } else {
                return "\(ext) \(int): \(p.typeText)"
            }
        }.joined(separator: ", ")
        let argList = params.map { p in
            p.secondName?.text ?? p.firstName.text
        }.joined(separator: ", ")
        return """
        \(I1)func \(fn.name.text)(\(paramList)) {
        \(I2)_\(fn.name.text)(\(argList))
        \(I1)}
        """
    }.joined(separator: "\n")

    let src = """
    /// Auto-generated protocol-witness struct for `\(protoName)`.
    ///
    /// Allows dependency injection, mocking, and `AsyncStream` interop
    /// without inheriting from `NSObject`.
    ///
    /// Usage:
    /// ```swift
    /// // Wrap a concrete delegate:
    /// let witness = \(protoName)Witness(delegate: myConcreteDelegate)
    ///
    /// // Or drive from an AsyncStream bridge:
    /// let bridge = \(protoName)AsyncBridge()
    /// let witness = \(protoName)Witness.streamBacked(bridge)
    /// ```
    final class \(protoName)Witness: \(protoName) {
    \(closureProps)

    \(designatedInit)

    \(concreteInit)

    \(bridgeFactory)

    \(I1)// MARK: - \(protoName) conformance
    \(conformanceImpl)
    }
    """
    return try! ClassDeclSyntax("\(raw: src)")
}
