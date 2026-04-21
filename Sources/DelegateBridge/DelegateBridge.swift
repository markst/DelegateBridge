/// DelegateBridge
/// ==============
/// Apply `@AsyncStreamBridge` to any `protocol` to automatically generate:
///
/// 1. **`<Protocol>Event`** — a `Sendable` enum with one case per delegate method.
///
/// 2. **`<Protocol>AsyncBridge`** — a `@MainActor` `NSObject` subclass that
///    conforms to the protocol and exposes:
///    - `events: AsyncStream<Event>` — a single unified stream of all events.
///    - A per-method `AsyncStream` for every void-returning method.
///    - `finish()` to tear down the streams.
///
/// 3. **`<Protocol>Witness`** — a lightweight struct (no `NSObject` dependency)
///    that holds closures mirroring each method, conforming to the protocol.
///    Includes:
///    - `init(delegate:)` — wraps any concrete conformer.
///    - `static func streamBacked(_ bridge:)` — wires a bridge into witness closures.
///
/// ### Example
///
/// ```swift
/// @AsyncStreamBridge
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
/// ```
@attached(peer, names: suffixed(Event), suffixed(AsyncBridge), suffixed(Witness))
public macro AsyncStreamBridge() = #externalMacro(
    module: "DelegateBridgeMacros",
    type:   "DelegateBridgeMacrosImpl.AsyncStreamBridgeMacro"
)
