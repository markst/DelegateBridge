# DelegateBridge

A Swift macro that converts any delegate protocol into:

- An **AsyncStream** event pipeline  
- A **protocol-witness struct** for dependency injection and mocking

No boilerplate. One annotation.

---

## The Problem

Cocoa and UIKit delegate patterns are callback-based and hard to integrate with Swift Concurrency:

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

```swift
@AsyncStreamBridge
protocol LocationDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocation)
    func didFailWithError(_ error: Error)
}
```

The macro generates **three types** automatically.

---

## Generated Types

### 1. `LocationDelegateEvent` — Sendable enum

```swift
enum LocationDelegateEvent: Sendable {
    case didUpdateLocation(CLLocation)
    case didFailWithError(Error)
}
```

### 2. `LocationDelegateAsyncBridge` — `@MainActor` NSObject delegate

```swift
@MainActor
final class LocationDelegateAsyncBridge: NSObject, LocationDelegate {
    let events: AsyncStream<LocationDelegateEvent>  // unified stream
    let didUpdateLocationStream: AsyncStream<CLLocation>  // per-method stream
    let didFailWithErrorStream: AsyncStream<Error>

    func finish()  // call when the delegate owner is torn down
}
```

### 3. `LocationDelegateWitness` — closure-based protocol witness

```swift
struct LocationDelegateWitness: LocationDelegate {
    var didUpdateLocation: (CLLocation) -> Void
    var didFailWithError: (Error) -> Void

    init(delegate: some LocationDelegate)           // wraps any concrete type
    static func streamBacked(_ bridge: ...) -> Self // wires into a bridge
}
```

---

## Usage Patterns

### Pattern A — Unified AsyncStream

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

### Pattern B — Typed per-method stream

```swift
let bridge = LocationDelegateAsyncBridge.makeFull()
locationManager.delegate = bridge

// Only care about location updates
for await location in bridge.didUpdateLocationStream {
    process(location)
}
```

### Pattern C — Protocol Witness (testing / DI)

```swift
// Production: wrap a real delegate
let witness = LocationDelegateWitness(delegate: realDelegate)

// Testing: supply closures, no NSObject inheritance needed
let mock = LocationDelegateWitness(
    didUpdateLocation: { loc in XCTAssertEqual(loc, expected) },
    didFailWithError:  { _ in XCTFail("Unexpected error") }
)

// TCA / SwiftUI environment: bridge → witness
let bridge = LocationDelegateAsyncBridge()
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
.package(url: "https://github.com/your-org/DelegateBridge", from: "1.0.0")

// Target dependency
.product(name: "DelegateBridge", package: "DelegateBridge")
```

```swift
import DelegateBridge

@AsyncStreamBridge
protocol YourDelegate: AnyObject { ... }
```

---

## Architecture

```
DelegateBridge (library)
└─ @AsyncStreamBridge macro declaration

DelegateBridgeMacros (compiler plugin)
├─ AsyncStreamBridgeMacro      — PeerMacro implementation
├─ buildEventEnum()            — generates <P>Event enum
├─ buildBridgeClass()          — generates <P>AsyncBridge
└─ buildWitnessStruct()        — generates <P>Witness
```

The macro is a `@attached(peer)` macro, meaning it generates new top-level
declarations alongside the annotated protocol without modifying it.

---

## License

MIT
