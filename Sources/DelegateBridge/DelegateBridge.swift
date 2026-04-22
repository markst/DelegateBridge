/// DelegateBridge
/// ==============
///
/// Apply one of the following macros to a `protocol` to automatically generate
/// bridge and/or witness types:
///
/// - `@AsyncStreamBridge` — generates `<Protocol>Event` and `<Protocol>AsyncBridge`.
/// - `@ProtocolWitness`   — generates `<Protocol>Witness` (closure-based, no `NSObject`).
/// - `@DelegateBridge`    — generates all three (Event, AsyncBridge, and Witness with `streamBacked`).
///
/// ---
///
/// ### `@AsyncStreamBridge`
///
/// Generates:
///
/// 1. **`<Protocol>Event`** — a `Sendable` enum with one case per delegate method.
///
/// 2. **`<Protocol>AsyncBridge`** — a `@MainActor` `NSObject` subclass that
///    conforms to the protocol and exposes:
///    - `events: AsyncStream<Event>` — a single unified stream of all events.
///    - `finish()` to tear down the streams.
///
/// ```swift
/// @AsyncStreamBridge
/// protocol LocationDelegate: AnyObject {
///     func didUpdateLocation(_ location: CLLocation)
///     func didFailWithError(_ error: Error)
/// }
///
/// // Generated: LocationDelegateEvent, LocationDelegateAsyncBridge
///
/// let bridge = LocationDelegateAsyncBridge()
/// locationManager.delegate = bridge
///
/// Task {
///     for await event in bridge.events {
///         switch event {
///         case .didUpdateLocation(let loc): handle(loc)
///         case .didFailWithError(let err):  handle(err)
///         }
///     }
/// }
/// ```
@attached(peer, names: suffixed(Event), suffixed(AsyncBridge))
public macro AsyncStreamBridge() = #externalMacro(
    module: "DelegateBridgeMacros",
    type:   "AsyncStreamBridgeMacro"
)

/// ### `@ProtocolWitness`
///
/// Generates:
///
/// 1. **`<Protocol>Witness`** — a lightweight class (no `NSObject` dependency)
///    that holds closures mirroring each method, conforming to the protocol.
///    Includes:
///    - `init(<method>:)` — memberwise closure init.
///    - `init(delegate:)` — wraps any concrete conformer.
///
/// ```swift
/// @ProtocolWitness
/// protocol LocationDelegate: AnyObject {
///     func didUpdateLocation(_ location: CLLocation)
///     func didFailWithError(_ error: Error)
/// }
///
/// // Generated: LocationDelegateWitness
///
/// // Testing: supply closures, no NSObject inheritance needed
/// let mock = LocationDelegateWitness(
///     didUpdateLocation: { loc in XCTAssertEqual(loc, expected) },
///     didFailWithError:  { _ in XCTFail("Unexpected error") }
/// )
/// ```
@attached(peer, names: suffixed(Witness))
public macro ProtocolWitness() = #externalMacro(
    module: "DelegateBridgeMacros",
    type:   "ProtocolWitnessMacro"
)

/// ### `@DelegateBridge`
///
/// Convenience macro that generates all three types at once:
///
/// 1. **`<Protocol>Event`** — a `Sendable` enum with one case per delegate method.
///
/// 2. **`<Protocol>AsyncBridge`** — a `@MainActor` `NSObject` subclass exposing
///    `events: AsyncStream<Event>` and `finish()`.
///
/// 3. **`<Protocol>Witness`** — a closure-based protocol witness, including:
///    - `init(<method>:)` — memberwise closure init.
///    - `init(delegate:)` — wraps any concrete conformer.
///    - `static func streamBacked(_ bridge:)` — wires a bridge into witness closures.
///
/// ```swift
/// @DelegateBridge
/// protocol LocationDelegate: AnyObject {
///     func didUpdateLocation(_ location: CLLocation)
///     func didFailWithError(_ error: Error)
/// }
///
/// // Generated: LocationDelegateEvent, LocationDelegateAsyncBridge, LocationDelegateWitness
///
/// // Usage – AsyncStream:
/// let bridge = LocationDelegateAsyncBridge()
/// locationManager.delegate = bridge
///
/// Task {
///     for await event in bridge.events {
///         switch event {
///         case .didUpdateLocation(let loc): handle(loc)
///         case .didFailWithError(let err):  handle(err)
///         }
///     }
/// }
///
/// // Usage – Protocol Witness (great for SwiftUI / TCA / testing):
/// let witness = LocationDelegateWitness(delegate: bridge)
/// // Or mock it:
/// let mock = LocationDelegateWitness(
///     didUpdateLocation: { loc in print(loc) },
///     didFailWithError:  { err in print(err) }
/// )
/// // Or wire bridge → witness:
/// let witness = LocationDelegateWitness.streamBacked(bridge)
/// ```
@attached(peer, names: suffixed(Event), suffixed(AsyncBridge), suffixed(Witness))
public macro DelegateBridge() = #externalMacro(
    module: "DelegateBridgeMacros",
    type:   "DelegateBridgeMacro"
)
