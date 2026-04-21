import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import DelegateBridgeMacrosImpl

final class DelegateBridgeMacroTests: XCTestCase {

    let macros: [String: Macro.Type] = [
        "AsyncStreamBridge": AsyncStreamBridgeMacro.self,
    ]

    // ── Test 1: Simple single-method protocol ────────────────────────────────
    func testSingleMethodProtocol() throws {
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
                var didPing: () -> Void

                init(didPing: @escaping () -> Void) {
                    self.didPing = didPing
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
                    didPing()
                }
            }
            """,
            macros: macros
        )
    }

    // ── Test 2: Multi-parameter method ───────────────────────────────────────
    func testMultiParamMethod() throws {
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

            /// Auto-generated protocol-witness struct for `ProgressDelegate`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = ProgressDelegateWitness(delegate: myConcreteDelegate)
            ///
            /// // Or drive from an AsyncStream bridge:
            /// let bridge = ProgressDelegateAsyncBridge()
            /// let witness = ProgressDelegateWitness.streamBacked(bridge)
            /// ```
            final class ProgressDelegateWitness: ProgressDelegate {
                var didUpdate: (Float, String) -> Void

                init(didUpdate: @escaping (Float, String) -> Void) {
                    self.didUpdate = didUpdate
                }

                    convenience init(delegate: some ProgressDelegate) {
                    self.init(
                    didUpdate: { progress, label in
                        delegate.didUpdate(progress: progress, label: label)
                    }
                    )
                }

                    static func streamBacked(_ bridge: ProgressDelegateAsyncBridge) -> Self {
                    .init(
                    didUpdate: { a0, a1 in
                        bridge._continuation.yield(.didUpdate(progress: a0, label: a1))
                    }
                    )
                }

                // MARK: - ProgressDelegate conformance
                    func didUpdate(progress: Float, label: String) {
                    didUpdate(progress, label)
                }
            }
            """,
            diagnostics: [],
            macros: macros
        )
    }

    // ── Test 3: Non-protocol target emits error ───────────────────────────────
    func testNonProtocolDiagnostic() throws {
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

    // ── Test 4: Non-void method emits error; void methods are still bridged ───
    func testNonVoidMethodDiagnostic() throws {
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

            /// Auto-generated protocol-witness struct for `QueryDelegate`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = QueryDelegateWitness(delegate: myConcreteDelegate)
            ///
            /// // Or drive from an AsyncStream bridge:
            /// let bridge = QueryDelegateAsyncBridge()
            /// let witness = QueryDelegateWitness.streamBacked(bridge)
            /// ```
            final class QueryDelegateWitness: QueryDelegate {
                var didFinish: () -> Void

                init(didFinish: @escaping () -> Void) {
                    self.didFinish = didFinish
                }

                    convenience init(delegate: some QueryDelegate) {
                    self.init(
                    didFinish: {
                        delegate.didFinish()
                    }
                    )
                }

                    static func streamBacked(_ bridge: QueryDelegateAsyncBridge) -> Self {
                    .init(
                    didFinish: {
                        bridge._continuation.yield(.didFinish)
                    }
                    )
                }

                // MARK: - QueryDelegate conformance
                    func didFinish() {
                    didFinish()
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

    // ── Test 5: Event enum uses correct associated values ────────────────────
    func testEventEnumAssociatedValues() throws {
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

            /// Auto-generated protocol-witness struct for `DataDelegate`.
            ///
            /// Allows dependency injection, mocking, and `AsyncStream` interop
            /// without inheriting from `NSObject`.
            ///
            /// Usage:
            /// ```swift
            /// // Wrap a concrete delegate:
            /// let witness = DataDelegateWitness(delegate: myConcreteDelegate)
            ///
            /// // Or drive from an AsyncStream bridge:
            /// let bridge = DataDelegateAsyncBridge()
            /// let witness = DataDelegateWitness.streamBacked(bridge)
            /// ```
            final class DataDelegateWitness: DataDelegate {
                var didReceiveData: (Data) -> Void
                var didReceiveItems: ([String], Int) -> Void

                init(didReceiveData: @escaping (Data) -> Void,
                    didReceiveItems: @escaping ([String], Int) -> Void) {
                    self.didReceiveData = didReceiveData
                    self.didReceiveItems = didReceiveItems
                }

                    convenience init(delegate: some DataDelegate) {
                    self.init(
                    didReceiveData: { data in
                        delegate.didReceiveData(data)
                    },
                    didReceiveItems: { items, count in
                        delegate.didReceiveItems(items, count: count)
                    }
                    )
                }

                    static func streamBacked(_ bridge: DataDelegateAsyncBridge) -> Self {
                    .init(
                    didReceiveData: { a0 in
                        bridge._continuation.yield(.didReceiveData(a0))
                    },
                    didReceiveItems: { a0, a1 in
                        bridge._continuation.yield(.didReceiveItems(a0, count: a1))
                    }
                    )
                }

                // MARK: - DataDelegate conformance
                    func didReceiveData(_ data: Data) {
                    didReceiveData(data)
                }
                    func didReceiveItems(_ items: [String], count: Int) {
                    didReceiveItems(items, count)
                }
            }
            """,
            diagnostics: [],
            macros: macros
        )
    }
}
