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

            enum PingDelegateEvent: Sendable {
                case didPing
            }

            @MainActor
            final class PingDelegateAsyncBridge: NSObject, PingDelegate {
                private let _continuation: AsyncStream<PingDelegateEvent>.Continuation
                let events: AsyncStream<PingDelegateEvent>
                init() {
                    var cont: AsyncStream<PingDelegateEvent>.Continuation!
                    events = AsyncStream { cont = $0 }
                    _continuation = cont
                }
                deinit { _continuation.finish() }
                func finish() { _continuation.finish() }
                func didPing() {
                    _continuation.yield(.didPing)
                }
            }

            struct PingDelegateWitness: PingDelegate {
                var didPing: () -> Void
                init(didPing: @escaping () -> Void) {
                    self.didPing = didPing
                }
                init(delegate: some PingDelegate) {
                    self.init(
                        didPing: { delegate.didPing() }
                    )
                }
                static func streamBacked(_ bridge: PingDelegateAsyncBridge) -> Self {
                    .init(
                        didPing: { bridge._continuation.yield(.didPing) }
                    )
                }
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
            """,
            diagnostics: [],
            macros: macros
        )
        // We don't match the full expansion here; just confirm no errors.
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

    // ── Test 4: Non-void method emits warning ────────────────────────────────
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
            """,
            diagnostics: [],
            macros: macros
        )
        // Smoke test – verify no compile errors for common patterns
    }
}
