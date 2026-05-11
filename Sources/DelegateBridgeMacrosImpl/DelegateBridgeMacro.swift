import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

// MARK: - Diagnostics

enum DelegateBridgeDiagnostic: DiagnosticMessage {
    case notAProtocol(macroName: String)
    case voidReturnRequired(method: String)
    case noMethods(macroName: String)

    var message: String {
        switch self {
        case .notAProtocol(let name):
            return "@\(name) can only be applied to protocols"
        case .voidReturnRequired(let method):
            return "Delegate method '\(method)' must return Void to be bridged to AsyncStream"
        case .noMethods(let name):
            return "@\(name) requires at least one method in the protocol"
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

private struct ProtocolMethod {
    let syntax: FunctionDeclSyntax
    let rawDeclText: String
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

private func splitTopLevelArrow(in text: String) -> (beforeArrow: String, afterArrow: String?) {
    var parenDepth = 0
    var bracketDepth = 0
    var braceDepth = 0
    var angleDepth = 0

    let chars = Array(text)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        switch c {
        case "(": parenDepth += 1
        case ")": parenDepth = max(0, parenDepth - 1)
        case "[": bracketDepth += 1
        case "]": bracketDepth = max(0, bracketDepth - 1)
        case "{": braceDepth += 1
        case "}": braceDepth = max(0, braceDepth - 1)
        case "<": angleDepth += 1
        case ">": angleDepth = max(0, angleDepth - 1)
        case "-":
            if i + 1 < chars.count,
               chars[i + 1] == ">",
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               angleDepth == 0 {
                let before = String(chars[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
                let after = String(chars[(i + 2)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (before, after.isEmpty ? nil : after)
            }
        default:
            break
        }
        i += 1
    }

    return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
}

private extension FunctionSignatureSyntax {
    var trailingSignatureText: String {
        let full = trimmedDescription
        let params = parameterClause.trimmedDescription
        guard full.hasPrefix(params) else { return full }
        return String(full.dropFirst(params.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var parsedEffectsAndReturn: (effects: String, returnType: String?) {
        let trailing = trailingSignatureText
        let (effects, returnType) = splitTopLevelArrow(in: trailing)
        return (effects, returnType)
    }

    var isVoidReturn: Bool {
        let t = returnTypeText
        return t == "Void" || t == "()"
    }

    var returnTypeText: String {
        if let parsed = parsedEffectsAndReturn.returnType { return parsed }
        if let ret = returnClause { return ret.type.trimmedDescription }
        return "Void"
    }

    var isAsync: Bool {
        effectSpecifiers?.asyncSpecifier != nil || effectSpecifiersText.contains("async")
    }

    var isThrowing: Bool {
        effectSpecifiers?.throwsSpecifier != nil || effectSpecifiersText.contains("throws")
    }

    var effectSpecifiersText: String {
        let parsed = parsedEffectsAndReturn.effects
        if !parsed.isEmpty { return parsed }
        return effectSpecifiers?.trimmedDescription ?? ""
    }
}

private extension ProtocolMethod {
    var fn: FunctionDeclSyntax { syntax }

    var textualTailAfterParameters: String {
        let full = rawDeclText
        let marker = "\(fn.name.text)\(fn.signature.parameterClause.trimmedDescription)"
        guard let markerRange = full.range(of: marker) else { return fn.signature.trailingSignatureText }
        return String(full[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var parsedEffectsAndReturn: (effects: String, returnType: String?) {
        let tail = textualTailAfterParameters
        let (effects, returnType) = splitTopLevelArrow(in: tail)
        return (effects, returnType)
    }

    var resolvedEffectSpecifiersText: String {
        let parsed = parsedEffectsAndReturn.effects
        if !parsed.isEmpty { return parsed }
        return fn.signature.effectSpecifiersText
    }

    var resolvedReturnTypeText: String {
        if let parsed = parsedEffectsAndReturn.returnType { return parsed }
        return fn.signature.returnTypeText
    }

    var isAsyncResolved: Bool {
        resolvedEffectSpecifiersText.contains("async")
    }

    var isThrowingResolved: Bool {
        resolvedEffectSpecifiersText.contains("throws")
    }

    var isVoidReturnResolved: Bool {
        let returnType = resolvedReturnTypeText
        return returnType == "Void" || returnType == "()"
    }
}

// MARK: - Shared Validation

private func validateProtocol(
    macroName: String,
    node: AttributeSyntax,
    declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
    requireVoidReturn: Bool = true
) -> (protoName: String, methods: [ProtocolMethod])? {
    guard let proto = declaration.as(ProtocolDeclSyntax.self) else {
        context.diagnose(Diagnostic(
            node: node,
            message: DelegateBridgeDiagnostic.notAProtocol(macroName: macroName)
        ))
        return nil
    }

    let protoName = proto.name.text

    let allMethods: [ProtocolMethod] = proto.memberBlock.members.compactMap { member in
        guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return nil }
        return ProtocolMethod(syntax: fn, rawDeclText: member.decl.trimmedDescription)
    }

    guard !allMethods.isEmpty else {
        context.diagnose(Diagnostic(
            node: node,
            message: DelegateBridgeDiagnostic.noMethods(macroName: macroName)
        ))
        return nil
    }

    let bridgeable: [ProtocolMethod]
    if requireVoidReturn {
        bridgeable = allMethods.filter { method in
            guard method.fn.signature.isVoidReturn else {
                context.diagnose(Diagnostic(
                    node: method.fn,
                    message: DelegateBridgeDiagnostic.voidReturnRequired(method: method.fn.name.text)
                ))
                return false
            }
            return true
        }
    } else {
        bridgeable = allMethods
    }

    return (protoName, bridgeable)
}

// MARK: - @AsyncStreamBridge (Event enum + AsyncBridge class only)

/// Generates `<Protocol>Event` and `<Protocol>AsyncBridge` for the annotated protocol.
public struct AsyncStreamBridgeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (protoName, methods) = validateProtocol(
            macroName: "AsyncStreamBridge",
            node: node,
            declaration: declaration,
            in: context
        ) else { return [] }

        return [
            DeclSyntax(buildEventEnum(protoName: protoName, methods: methods)),
            DeclSyntax(buildBridgeClass(protoName: protoName, methods: methods)),
        ]
    }
}

// MARK: - @ProtocolWitness (Witness class only)

/// Generates `<Protocol>Witness` for the annotated protocol.
public struct ProtocolWitnessMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (protoName, methods) = validateProtocol(
            macroName: "ProtocolWitness",
            node: node,
            declaration: declaration,
            in: context,
            requireVoidReturn: false
        ) else { return [] }

        return [
            DeclSyntax(buildWitnessStruct(protoName: protoName, methods: methods, includeStreamBacked: false)),
        ]
    }
}

// MARK: - @DelegateBridge (Event enum + AsyncBridge class + Witness class with streamBacked)

/// Generates `<Protocol>Event`, `<Protocol>AsyncBridge`, and `<Protocol>Witness`
/// (with `streamBacked`) for the annotated protocol.
public struct DelegateBridgeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (protoName, methods) = validateProtocol(
            macroName: "DelegateBridge",
            node: node,
            declaration: declaration,
            in: context
        ) else { return [] }

        return [
            DeclSyntax(buildEventEnum(protoName: protoName, methods: methods)),
            DeclSyntax(buildBridgeClass(protoName: protoName, methods: methods)),
            DeclSyntax(buildWitnessStruct(protoName: protoName, methods: methods, includeStreamBacked: true)),
        ]
    }
}



private func buildEventEnum(
    protoName: String,
    methods: [ProtocolMethod]
) -> EnumDeclSyntax {
    let cases = methods.map { method -> String in
        let fn = method.fn
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
    methods: [ProtocolMethod]
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
    for method in methods {
        let fn = method.fn
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
    methods: [ProtocolMethod],
    includeStreamBacked: Bool
) -> ClassDeclSyntax {

    let I1 = "    "        // 1-level indent (inside class body)
    let I2 = I1 + I1       // 2-level indent (inside method body)
    let I3 = I2 + I1       // 3-level indent (arguments in multi-line calls)

    // Private closure storage. Prefixed with `_` to avoid redeclaration
    // conflicts with same-named protocol methods (especially zero-arg ones).
    let closureProps = methods.map { method -> String in
        let fn = method.fn
        let params = fn.signature.parameterClause.parameters
        let paramTypes = params.map(\.typeText).joined(separator: ", ")
        let effectSpecifiers = method.resolvedEffectSpecifiersText
        let effectsStr = effectSpecifiers.isEmpty ? "" : " \(effectSpecifiers)"
        let returnType = method.resolvedReturnTypeText
        return "\(I1)private let _\(fn.name.text): (\(paramTypes))\(effectsStr) -> \(returnType)"
    }.joined(separator: "\n")

    // Designated init: takes one closure per method.
    let initParamList = methods.map { method -> String in
        let fn = method.fn
        let params = fn.signature.parameterClause.parameters
        let types = params.map(\.typeText).joined(separator: ", ")
        let effectSpecifiers = method.resolvedEffectSpecifiersText
        let effectsStr = effectSpecifiers.isEmpty ? "" : " \(effectSpecifiers)"
        let returnType = method.resolvedReturnTypeText
        return "\(fn.name.text): @escaping (\(types))\(effectsStr) -> \(returnType)"
    }.joined(separator: ",\n\(I2)")

    let initAssignments = methods.map { method in
        let fn = method.fn
        return "\(I2)self._\(fn.name.text) = \(fn.name.text)"
    }.joined(separator: "\n")

    let designatedInit = """
    \(I1)init(
    \(I2)\(initParamList)
    \(I1)) {
    \(initAssignments)
    \(I1)}
    """

    // Convenience init wrapping a concrete delegate value.
    let concreteAssignments = methods.map { method -> String in
        let fn = method.fn
        let params = fn.signature.parameterClause.parameters
        let callPrefix = [method.isThrowingResolved ? "try" : nil, method.isAsyncResolved ? "await" : nil]
            .compactMap { $0 }.joined(separator: " ")
        let callPrefixStr = callPrefix.isEmpty ? "" : "\(callPrefix) "
        let closure: String
        if params.isEmpty {
            closure = "{ \(callPrefixStr)delegate.\(fn.name.text)() }"
        } else {
            let argNames = params.map { p in p.secondName?.text ?? p.firstName.text }
            let callArgs = params.map { p -> String in
                let ext = p.firstName.text
                let int = p.secondName?.text ?? ext
                if ext == "_" { return int }
                return "\(ext): \(int)"
            }.joined(separator: ", ")
            closure = "{ \(argNames.joined(separator: ", ")) in \(callPrefixStr)delegate.\(fn.name.text)(\(callArgs)) }"
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

    // Protocol conformance: forward to the underscored stored closure.
    let conformanceImpl = methods.map { method -> String in
        let fn = method.fn
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
        let effectSpecifiersDecl = method.resolvedEffectSpecifiersText
        let effectsDeclStr = effectSpecifiersDecl.isEmpty ? "" : " \(effectSpecifiersDecl)"
        let returnDecl = method.isVoidReturnResolved ? "" : " -> \(method.resolvedReturnTypeText)"
        let callPrefix = [method.isThrowingResolved ? "try" : nil, method.isAsyncResolved ? "await" : nil]
            .compactMap { $0 }.joined(separator: " ")
        let callPrefixStr = callPrefix.isEmpty ? "" : "\(callPrefix) "
        let returnKeyword = method.isVoidReturnResolved ? "" : "return "
        return """
        \(I1)func \(fn.name.text)(\(paramList))\(effectsDeclStr)\(returnDecl) {
        \(I2)\(returnKeyword)\(callPrefixStr)_\(fn.name.text)(\(argList))
        \(I1)}
        """
    }.joined(separator: "\n")

    // Optional streamBacked factory (only when paired with @AsyncStreamBridge or using @DelegateBridge).
    let streamBackedSection: String
    if includeStreamBacked {
        let bridgeAssignments = methods.map { method -> String in
            let fn = method.fn
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

        streamBackedSection = """


        \(I1)static func streamBacked(_ bridge: \(protoName)AsyncBridge) -> Self {
        \(I2).init(
        \(bridgeAssignments)
        \(I2))
        \(I1)}
        """
    } else {
        streamBackedSection = ""
    }

    let docComment: String
    if includeStreamBacked {
        docComment = """
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
        """
    } else {
        docComment = """
        /// Auto-generated protocol-witness struct for `\(protoName)`.
        ///
        /// Allows dependency injection, mocking, and `AsyncStream` interop
        /// without inheriting from `NSObject`.
        ///
        /// Usage:
        /// ```swift
        /// // Wrap a concrete delegate:
        /// let witness = \(protoName)Witness(delegate: myConcreteDelegate)
        /// ```
        """
    }

    let src = """
    \(docComment)
    final class \(protoName)Witness: \(protoName) {
    \(closureProps)

    \(designatedInit)

    \(concreteInit)
    \(streamBackedSection)

    \(I1)// MARK: - \(protoName) conformance
    \(conformanceImpl)
    }
    """
    return try! ClassDeclSyntax("\(raw: src)")
}
