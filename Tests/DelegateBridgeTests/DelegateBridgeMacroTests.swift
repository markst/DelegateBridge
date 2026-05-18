import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import DelegateBridgeMacrosImpl

final class DelegateBridgeMacroTests: XCTestCase {

    let macros: [String: Macro.Type] = [
        "AsyncStreamBridge": AsyncStreamBridgeMacro.self,
        "ProtocolWitness": ProtocolWitnessMacro.self,
        "DelegateBridge": DelegateBridgeMacro.self,
    ]

    // MARK: - @AsyncStreamBridge tests

    // ── Test 1: @AsyncStreamBridge generates Event enum + AsyncBridge class ──
    func testAsyncStreamBridgeSingleMethod() throws {
        assertMacroExpansion(
            """
            @AsyncStreamBridge
            protocol PingDelegate: AnyObject {
                func didPing()
            }
            """,
            expandedSource: """
            protocol PingDelegate: AnyObject {
                func didPing()
            }

            /// Auto-generated event enum for `PingDelegate` delegate bridge.
            enum PingDelegateEvent: Sendable {
                case didPing
            }

            /// Auto-generated bridge class that conforms to `PingDelegate` and exposes
            /// delegate callbacks as `AsyncStream` events.
            ///
            /// Usage:
            /// ```swift
            /// let bridge = PingDelegateAsyncBridge()
            /// myObject.delegate = bridge
            /// for await event in bridge.events {
            ///     switch event { ... }
            /// }
            /// ```
            final class PingDelegateAsyncBridge: NSObject, PingDelegate {
                // MARK: - Unified event stream
                let _continuation: AsyncStream<PingDelegateEvent>.Continuation

                /// A single stream delivering all delegate events as `PingDelegateEvent` cases.
                let events: AsyncStream<PingDelegateEvent>

                override init() {
                    var cont: AsyncStream<PingDelegateEvent>.Continuation!
                    events = AsyncStream {
                        cont = $0
                    }
                    _continuation = cont
                }

                deinit {
                    _continuation.finish()
                }

                /// Finish the stream (call when the delegate owner is torn down).
                func finish() {
                    _continuation.finish()
                }
                // MARK: - PingDelegate conformance

                func didPing() {
                    _continuation.yield(.didPing)
                }

            }
            """,
            macros: macros
        )
    }

    // ── Test 2: @AsyncStreamBridge with multi-parameter method ───────────────
    func testAsyncStreamBridgeMultiParamMethod() throws {
        assertMacroExpansion(
            """
            @AsyncStreamBridge
            protocol ProgressDelegate {
                func didUpdate(progress: Float, label: String)
            }
            """,
            expandedSource: """
            protocol ProgressDelegate {
                func didUpdate(progress: Float, label: String)
            }

            /// Auto-generated event enum for `ProgressDelegate` delegate bridge.
            enum ProgressDelegateEvent: Sendable {
                case didUpdate(progress: Float, label: String)
            }

            /// Auto-generated bridge class that conforms to `ProgressDelegate` and exposes
            /// delegate callbacks as `AsyncStream` events.
            ///
            /// Usage:
            /// ```swift
            /// let bridge = ProgressDelegateAsyncBridge()
            /// myObject.delegate = bridge
            /// for await event in bridge.events {
            ///     switch event { ... }
            /// }
            /// ```
            final class ProgressDelegateAsyncBridge: NSObject, ProgressDelegate {
                // MARK: - Unified event stream
                let _continuation: AsyncStream<ProgressDelegateEvent>.Continuation

                /// A single stream delivering all delegate events as `ProgressDelegateEvent` cases.
                let events: AsyncStream<ProgressDelegateEvent>

                override init() {
                    var cont: AsyncStream<ProgressDelegateEvent>.Continuation!
                    events = AsyncStream {
                        cont = $0
                    }
                    _continuation = cont
                }

                deinit {
                    _continuation.finish()
                }

                /// Finish the stream (call when the delegate owner is torn down).
                func finish() {
                    _continuation.finish()
                }
                // MARK: - ProgressDelegate conformance

                func didUpdate(progress: Float, label: String) {
                    _continuation.yield(.didUpdate(progress: progress, label: label))
                }

            }
            """,
            diagnostics: [],
            macros: macros
        )
    }

    // ── Test 3: @AsyncStreamBridge on a non-protocol emits error ─────────────
    func testAsyncStreamBridgeNonProtocolDiagnostic() throws {
        assertMacroExpansion(
            """
            @AsyncStreamBridge
            struct NotAProtocol {}
            """,
            expandedSource: """
            struct NotAProtocol {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@AsyncStreamBridge can only be applied to protocols",
                    line: 1, column: 1, severity: .error
                )
            ],
            macros: macros
        )
    }

    // ── Test 4: @AsyncStreamBridge skips non-void methods with a diagnostic ──
    func testAsyncStreamBridgeNonVoidMethodDiagnostic() throws {
        assertMacroExpansion(
            """
            @AsyncStreamBridge
            protocol QueryDelegate {
                func shouldProceed() -> Bool
                func didFinish()
            }
            """,
            expandedSource: """
            protocol QueryDelegate {
                func shouldProceed() -> Bool
                func didFinish()
            }

            /// Auto-generated event enum for `QueryDelegate` delegate bridge.
            enum QueryDelegateEvent: Sendable {
                case didFinish
            }

            /// Auto-generated bridge class that conforms to `QueryDelegate` and exposes
            /// delegate callbacks as `AsyncStream` events.
            ///
            /// Usage:
            /// ```swift
            /// let bridge = QueryDelegateAsyncBridge()
            /// myObject.delegate = bridge
            /// for await event in bridge.events {
            ///     switch event { ... }
            /// }
            /// ```
            final class QueryDelegateAsyncBridge: NSObject, QueryDelegate {
                // MARK: - Unified event stream
                let _continuation: AsyncStream<QueryDelegateEvent>.Continuation

                /// A single stream delivering all delegate events as `QueryDelegateEvent` cases.
                let events: AsyncStream<QueryDelegateEvent>

                override init() {
                    var cont: AsyncStream<QueryDelegateEvent>.Continuation!
                    events = AsyncStream {
                        cont = $0
                    }
                    _continuation = cont
                }

                deinit {
                    _continuation.finish()
                }

                /// Finish the stream (call when the delegate owner is torn down).
                func finish() {
                    _continuation.finish()
                }
                // MARK: - QueryDelegate conformance

                func didFinish() {
                    _continuation.yield(.didFinish)
                }

            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Delegate method 'shouldProceed' must return Void to be bridged to AsyncStream",
                    line: 3, column: 5, severity: .error
                )
            ],
            macros: macros
        )
    }

    // ── Test 5: @AsyncStreamBridge event enum uses correct associated values ──
    func testAsyncStreamBridgeEventEnumAssociatedValues() throws {
        assertMacroExpansion(
            """
            @AsyncStreamBridge
            protocol DataDelegate {
                func didReceiveData(_ data: Data)
                func didReceiveItems(_ items: [String], count: Int)
            }
            """,
            expandedSource: """
            protocol DataDelegate {
                func didReceiveData(_ data: Data)
                func didReceiveItems(_ items: [String], count: Int)
            }

            /// Auto-generated event enum for `DataDelegate` delegate bridge.
            enum DataDelegateEvent: Sendable {
                case didReceiveData(Data)
                case didReceiveItems([String], count: Int)
            }

            /// Auto-generated bridge class that conforms to `DataDelegate` and exposes
            /// delegate callbacks as `AsyncStream` events.
            ///
            /// Usage:
            /// ```swift
            /// let bridge = DataDelegateAsyncBridge()
            /// myObject.delegate = bridge
            /// for await event in bridge.events {
            ///     switch event { ... }
            /// }
            /// ```
            final class DataDelegateAsyncBridge: NSObject, DataDelegate {
                // MARK: - Unified event stream
                let _continuation: AsyncStream<DataDelegateEvent>.Continuation

                /// A single stream delivering all delegate events as `DataDelegateEvent` cases.
                let events: AsyncStream<DataDelegateEvent>

                override init() {
                    var cont: AsyncStream<DataDelegateEvent>.Continuation!
                    events = AsyncStream {
                        cont = $0
                    }
                    _continuation = cont
                }

                deinit {
                    _continuation.finish()
                }

                /// Finish the stream (call when the delegate owner is torn down).
                func finish() {
                    _continuation.finish()
                }
                // MARK: - DataDelegate conformance

                func didReceiveData(_ data: Data) {
                    _continuation.yield(.didReceiveData(data))
                }

                func didReceiveItems(_ items: [String], count: Int) {
                    _continuation.yield(.didReceiveItems(items, count: count))
                }

            }
            """,
            diagnostics: [],
            macros: macros
        )
    }

    // MARK: - @ProtocolWitness tests

    // ── Test 6: @ProtocolWitness generates Witness class (no streamBacked) ───
    func testProtocolWitnessSingleMethod() throws {
        assertMacroExpansion(
            """
            @ProtocolWitness
            protocol PingDelegate: AnyObject {
                func didPing()
            }
            """,
            expandedSource: """
            protocol PingDelegate: AnyObject {
                func didPing()
            }

            /// Auto-generated protocol-witness struct for `PingDelegate`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = PingDelegateWitness(delegate: myConcreteDelegate)
            /// ```
            final class PingDelegateWitness: PingDelegate {
                private let _didPing: () -> Void

                init(
                    didPing: @escaping () -> Void
                ) {
                    self._didPing = didPing
                }

                convenience init(delegate: some PingDelegate) {
                    self.init(
                        didPing: {
                            delegate.didPing()
                        }
                    )
                }


                // MARK: - PingDelegate conformance
                func didPing() {
                    _didPing()
                }
            }
            """,
            macros: macros
        )
    }

    // ── Test: @ProtocolWitness with async throws and return type ─────────────
    func testProtocolWitnessAsyncThrowsReturn() throws {
        assertMacroExpansion(
            """
            @ProtocolWitness
            protocol LoginAPIProviding {
                func login(with email: String, password: String) async throws -> LoginResult
            }
            """,
            expandedSource: """
            protocol LoginAPIProviding {
                func login(with email: String, password: String) async throws -> LoginResult
            }

            /// Auto-generated protocol-witness struct for `LoginAPIProviding`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = LoginAPIProvidingWitness(delegate: myConcreteDelegate)
            /// ```
            final class LoginAPIProvidingWitness: LoginAPIProviding {
                private let _login: (String, String) async throws -> LoginResult

                init(
                    login: @escaping (String, String) async throws -> LoginResult
                ) {
                    self._login = login
                }

                convenience init(delegate: some LoginAPIProviding) {
                    self.init(
                        login: { email, password in
                            try await delegate.login(with: email, password: password)
                        }
                    )
                }


                // MARK: - LoginAPIProviding conformance
                func login(with email: String, password: String) async throws -> LoginResult {
                    return try await _login(email, password)
                }
            }
            """,
            macros: macros
        )
    }

    // ── Test: @ProtocolWitness with async typed throws and return type ────────
    func testProtocolWitnessAsyncTypedThrowsReturn() throws {
        assertMacroExpansion(
            """
            @ProtocolWitness
            protocol LoginAPIProviding {
                func login(with email: String, password: String) async throws(MyError) -> LoginResult
            }
            """,
            expandedSource: """
            protocol LoginAPIProviding {
                func login(with email: String, password: String) async throws(MyError) -> LoginResult
            }

            /// Auto-generated protocol-witness struct for `LoginAPIProviding`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = LoginAPIProvidingWitness(delegate: myConcreteDelegate)
            /// ```
            final class LoginAPIProvidingWitness: LoginAPIProviding {
                private let _login: (String, String) async throws(MyError) -> LoginResult

                init(
                    login: @escaping (String, String) async throws(MyError) -> LoginResult
                ) {
                    self._login = login
                }

                convenience init(delegate: some LoginAPIProviding) {
                    self.init(
                        login: { email, password in
                            try await delegate.login(with: email, password: password)
                        }
                    )
                }


                // MARK: - LoginAPIProviding conformance
                func login(with email: String, password: String) async throws(MyError) -> LoginResult {
                    return try await _login(email, password)
                }
            }
            """,
            macros: macros
        )
    }

    // ── Test: @ProtocolWitness with synchronous typed throws ─────────────────
    func testProtocolWitnessSyncTypedThrows() throws {
        assertMacroExpansion(
            """
            @ProtocolWitness
            protocol ParserProviding {
                func parse(_ input: String) throws(ParseError) -> ParsedResult
            }
            """,
            expandedSource: """
            protocol ParserProviding {
                func parse(_ input: String) throws(ParseError) -> ParsedResult
            }

            /// Auto-generated protocol-witness struct for `ParserProviding`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = ParserProvidingWitness(delegate: myConcreteDelegate)
            /// ```
            final class ParserProvidingWitness: ParserProviding {
                private let _parse: (String) throws(ParseError) -> ParsedResult

                init(
                    parse: @escaping (String) throws(ParseError) -> ParsedResult
                ) {
                    self._parse = parse
                }

                convenience init(delegate: some ParserProviding) {
                    self.init(
                        parse: { input in
                            try delegate.parse(input)
                        }
                    )
                }


                // MARK: - ParserProviding conformance
                func parse(_ input: String) throws(ParseError) -> ParsedResult {
                    return try _parse(input)
                }
            }
            """,
            macros: macros
        )
    }


    func testProtocolWitnessNonVoidReturn() throws {
        assertMacroExpansion(
            """
            @ProtocolWitness
            protocol QueryDelegate {
                func shouldProceed() -> Bool
                func didFinish()
            }
            """,
            expandedSource: """
            protocol QueryDelegate {
                func shouldProceed() -> Bool
                func didFinish()
            }

            /// Auto-generated protocol-witness struct for `QueryDelegate`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = QueryDelegateWitness(delegate: myConcreteDelegate)
            /// ```
            final class QueryDelegateWitness: QueryDelegate {
                private let _shouldProceed: () -> Bool
                private let _didFinish: () -> Void

                init(
                    shouldProceed: @escaping () -> Bool,
                    didFinish: @escaping () -> Void
                ) {
                    self._shouldProceed = shouldProceed
                    self._didFinish = didFinish
                }

                convenience init(delegate: some QueryDelegate) {
                    self.init(
                        shouldProceed: {
                            delegate.shouldProceed()
                        },
                        didFinish: {
                            delegate.didFinish()
                        }
                    )
                }


                // MARK: - QueryDelegate conformance
                func shouldProceed() -> Bool {
                    return _shouldProceed()
                }
                func didFinish() {
                    _didFinish()
                }
            }
            """,
            macros: macros
        )
    }

    // ── Test 7: @ProtocolWitness on a non-protocol emits error ────────────────
    func testProtocolWitnessNonProtocolDiagnostic() throws {
        assertMacroExpansion(
            """
            @ProtocolWitness
            struct NotAProtocol {}
            """,
            expandedSource: """
            struct NotAProtocol {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ProtocolWitness can only be applied to protocols",
                    line: 1, column: 1, severity: .error
                )
            ],
            macros: macros
        )
    }

    // MARK: - @DelegateBridge tests

    // ── Test 8: @DelegateBridge generates all three types ─────────────────────
    func testDelegateBridgeSingleMethod() throws {
        assertMacroExpansion(
            """
            @DelegateBridge
            protocol PingDelegate: AnyObject {
                func didPing()
            }
            """,
            expandedSource: """
            protocol PingDelegate: AnyObject {
                func didPing()
            }

            /// Auto-generated event enum for `PingDelegate` delegate bridge.
            enum PingDelegateEvent: Sendable {
                case didPing
            }

            /// Auto-generated bridge class that conforms to `PingDelegate` and exposes
            /// delegate callbacks as `AsyncStream` events.
            ///
            /// Usage:
            /// ```swift
            /// let bridge = PingDelegateAsyncBridge()
            /// myObject.delegate = bridge
            /// for await event in bridge.events {
            ///     switch event { ... }
            /// }
            /// ```
            final class PingDelegateAsyncBridge: NSObject, PingDelegate {
                // MARK: - Unified event stream
                let _continuation: AsyncStream<PingDelegateEvent>.Continuation

                /// A single stream delivering all delegate events as `PingDelegateEvent` cases.
                let events: AsyncStream<PingDelegateEvent>

                override init() {
                    var cont: AsyncStream<PingDelegateEvent>.Continuation!
                    events = AsyncStream {
                        cont = $0
                    }
                    _continuation = cont
                }

                deinit {
                    _continuation.finish()
                }

                /// Finish the stream (call when the delegate owner is torn down).
                func finish() {
                    _continuation.finish()
                }
                // MARK: - PingDelegate conformance

                func didPing() {
                    _continuation.yield(.didPing)
                }

            }

            /// Auto-generated protocol-witness struct for `PingDelegate`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = PingDelegateWitness(delegate: myConcreteDelegate)
            ///
            /// // Or drive from an AsyncStream bridge:
            /// let bridge = PingDelegateAsyncBridge()
            /// let witness = PingDelegateWitness.streamBacked(bridge)
            /// ```
            final class PingDelegateWitness: PingDelegate {
                private let _didPing: () -> Void

                init(
                    didPing: @escaping () -> Void
                ) {
                    self._didPing = didPing
                }

                convenience init(delegate: some PingDelegate) {
                    self.init(
                        didPing: {
                            delegate.didPing()
                        }
                    )
                }


                static func streamBacked(_ bridge: PingDelegateAsyncBridge) -> Self {
                    .init(
                        didPing: {
                            bridge._continuation.yield(.didPing)
                        }
                    )
                }

                // MARK: - PingDelegate conformance
                func didPing() {
                    _didPing()
                }
            }
            """,
            macros: macros
        )
    }

    // ── Test 9: @DelegateBridge on a non-protocol emits error ─────────────────
    func testDelegateBridgeNonProtocolDiagnostic() throws {
        assertMacroExpansion(
            """
            @DelegateBridge
            struct NotAProtocol {}
            """,
            expandedSource: """
            struct NotAProtocol {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@DelegateBridge can only be applied to protocols",
                    line: 1, column: 1, severity: .error
                )
            ],
            macros: macros
        )
    }
}
