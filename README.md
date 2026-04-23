# DelegateBridge

A Swift macro library that converts any delegate protocol into:

- An **AsyncStream** event pipeline  
- A **protocol-witness struct** for dependency injection and mocking

Choose the granularity that fits your use case — one annotation or two.

---

## The Problem

Delegate protocols are a widely-used pattern in Swift. Events are scattered across multiple protocol methods, making them hard to compose with Swift Concurrency:

```swift
// Old world: scattered callbacks, no composability
class MyVC: UIViewController, CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) { ... }
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) { ... }
}
```

---

## The Solution

Three macros — use whichever combination you need:

| Macro | Generates |
|-------|-----------|
| `@AsyncStreamBridge` | `<P>Event` enum + `<P>AsyncBridge` class |
| `@ProtocolWitness` | `<P>Witness` class |
| `@DelegateBridge` | All three (convenience shorthand for both above) |

---

## `@AsyncStreamBridge`

Generates an event enum and an `NSObject` bridge class that feeds delegate callbacks into an `AsyncStream`.

```swift
@AsyncStreamBridge
protocol LocationDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocation)
    func didFailWithError(_ error: Error)
}
```

### Generated: `LocationDelegateEvent` — Sendable enum

```swift
enum LocationDelegateEvent: Sendable {
    case didUpdateLocation(CLLocation)
    case didFailWithError(Error)
}
```

### Generated: `LocationDelegateAsyncBridge` — `@MainActor` NSObject delegate

```swift
@MainActor
final class LocationDelegateAsyncBridge: NSObject, LocationDelegate {
    let events: AsyncStream<LocationDelegateEvent>  // unified stream

    func finish()  // call when the delegate owner is torn down
}
```

---

## `@ProtocolWitness`

Generates a lightweight closure-based struct that conforms to the protocol without inheriting from `NSObject`. Ideal for testing and dependency injection.

```swift
@ProtocolWitness
protocol LocationDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocation)
    func didFailWithError(_ error: Error)
}
```

### Generated: `LocationDelegateWitness` — closure-based protocol witness

```swift
final class LocationDelegateWitness: LocationDelegate {
    init(
        didUpdateLocation: @escaping (CLLocation) -> Void,
        didFailWithError: @escaping (Error) -> Void
    )
    init(delegate: some LocationDelegate)  // wraps any concrete type
}
```

---

## `@DelegateBridge`

Convenience macro that generates all three types at once. Also adds a `streamBacked` factory to the witness for wiring it to an async bridge.

```swift
@DelegateBridge
protocol LocationDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocation)
    func didFailWithError(_ error: Error)
}

// Generated: LocationDelegateEvent, LocationDelegateAsyncBridge, LocationDelegateWitness
```

The witness gains an additional factory:

```swift
static func streamBacked(_ bridge: LocationDelegateAsyncBridge) -> LocationDelegateWitness
```

---

## Usage Patterns

### Pattern A — Unified AsyncStream (`@AsyncStreamBridge`)

```swift
let bridge = LocationDelegateAsyncBridge()
locationManager.delegate = bridge

Task {
    for await event in bridge.events {
        switch event {
        case .didUpdateLocation(let loc):
            updateUI(loc)
        case .didFailWithError(let err):
            showError(err)
        }
    }
}
```

### Pattern B — Protocol Witness for testing (`@ProtocolWitness`)

```swift
// Testing: supply closures, no NSObject inheritance needed
let mock = LocationDelegateWitness(
    didUpdateLocation: { loc in XCTAssertEqual(loc, expected) },
    didFailWithError:  { _ in XCTFail("Unexpected error") }
)

// Production: wrap a real delegate
let witness = LocationDelegateWitness(delegate: realDelegate)
```

### Pattern C — Bridge + Witness together (`@DelegateBridge`)

```swift
let bridge = LocationDelegateAsyncBridge()
locationManager.delegate = bridge

// TCA / SwiftUI environment: bridge → witness
let witness = LocationDelegateWitness.streamBacked(bridge)
```

### Pattern D — Structured Concurrency + TaskGroup

```swift
let bridge = LocationDelegateAsyncBridge()

await withTaskGroup(of: Void.self) { group in
    group.addTask {
        for await event in bridge.events {
            // error handler
        }
    }
    group.addTask {
        for await event in bridge.events {
            // analytics handler
        }
    }
}
```

---

## Rules & Constraints

| Rule | Detail |
|------|--------|
| Target must be a `protocol` | Applying to struct/class is a compile error |
| Methods must return `Void` | Non-void methods emit a compile-time diagnostic and are skipped |
| Async methods | Pass-through without bridging (use native `async` delegates directly) |
| `@MainActor` | The bridge class is main-actor-isolated; call `finish()` on teardown |

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/markst/DelegateBridge", from: "0.1.0")

// Target dependency
.product(name: "DelegateBridge", package: "DelegateBridge")
```

```swift
import DelegateBridge

// Choose based on your needs:
@AsyncStreamBridge   // stream only
protocol YourDelegate: AnyObject { ... }

@ProtocolWitness     // witness only
protocol YourDelegate: AnyObject { ... }

@DelegateBridge      // both stream + witness
protocol YourDelegate: AnyObject { ... }
```

## License

MIT
