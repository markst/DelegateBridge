import DelegateBridge
import Foundation

// The macro generates:
//
//   enum DownloadDelegateEvent: Sendable {
//       case downloadDidStart(url: URL)
//       case downloadDidProgress(url: URL, bytesReceived: Int64, totalBytes: Int64)
//       case downloadDidFinish(url: URL, localPath: URL)
//       case downloadDidFail(url: URL, error: Error)
//   }
//
//   @MainActor
//   final class DownloadDelegateAsyncBridge: NSObject, DownloadDelegate {
//       let events: AsyncStream<DownloadDelegateEvent>
//       func finish()
//       func downloadDidStart(url: URL) { ... }
//       // etc.
//   }
//
//   struct DownloadDelegateWitness: DownloadDelegate {
//       var downloadDidStart: (URL) -> Void
//       var downloadDidProgress: (URL, Int64, Int64) -> Void
//       var downloadDidFinish: (URL, URL) -> Void
//       var downloadDidFail: (URL, Error) -> Void
//       init(delegate: some DownloadDelegate)
//       static func streamBacked(_ bridge: DownloadDelegateAsyncBridge) -> Self
//   }

// ────────────────────────────────────────────────────────────────────────────
// 2. PATTERN A: AsyncStream (unified event stream)
// ────────────────────────────────────────────────────────────────────────────

func patternA_unifiedStream() async {
    let bridge = await DownloadDelegateAsyncBridge()

    // Hand the bridge to whatever SDK expects a delegate
    // myDownloader.delegate = bridge

    // Simulate some delegate calls
    Task { @MainActor in
        bridge.downloadDidStart(url: URL(string: "https://example.com/file.zip")!)
        bridge.downloadDidProgress(
            url: URL(string: "https://example.com/file.zip")!,
            bytesReceived: 1024,
            totalBytes: 8192
        )
        bridge.downloadDidFinish(
            url: URL(string: "https://example.com/file.zip")!,
            localPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        bridge.finish() // signals stream completion
    }

    for await event in await bridge.events {
        switch event {
        case .downloadDidStart(let url):
            print("▶ Started: \(url)")

        case .downloadDidProgress(let url, let received, let total):
            let pct = Double(received) / Double(total) * 100
            print("⬇ \(url.lastPathComponent): \(String(format: "%.0f", pct))%")

        case .downloadDidFinish(let url, let localPath):
            print("✅ Done: \(url) → \(localPath.path)")

        case .downloadDidFail(let url, let error):
            print("❌ Failed: \(url) — \(error)")
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// 3. PATTERN B: Typed per-method stream (only care about progress)
// ────────────────────────────────────────────────────────────────────────────

// ────────────────────────────────────────────────────────────────────────────
// 3. PATTERN B: Filter events from unified stream
// ────────────────────────────────────────────────────────────────────────────

func patternB_filterEvents() async {
    let bridge = await DownloadDelegateAsyncBridge()

    Task { @MainActor in
        bridge.downloadDidProgress(
            url: URL(string: "https://example.com/large.zip")!,
            bytesReceived: 4096,
            totalBytes: 8192
        )
        bridge.downloadDidProgress(
            url: URL(string: "https://example.com/large.zip")!,
            bytesReceived: 8192,
            totalBytes: 8192
        )
        bridge.finish()
    }

    // Filter progress events from the unified stream
    for await event in await bridge.events {
        if case .downloadDidProgress(_, let received, let total) = event {
            print("Progress: \(received)/\(total)")
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// 4. PATTERN C: Protocol Witness (dependency injection / testing)
// ────────────────────────────────────────────────────────────────────────────

// In production – wrap a real concrete delegate:
// let witness = DownloadDelegateWitness(delegate: realDelegateObject)

// In tests – supply closures directly (no NSObject, no inheritance):
// (mockDelegate is created inside main() to avoid top-level executable code)

// In a TCA / SwiftUI environment – bridge into AsyncStream and wrap as Witness:
func patternC_witnessFromBridge() async {
    let bridge = await DownloadDelegateAsyncBridge()
    let witness = await DownloadDelegateWitness.streamBacked(bridge)
    // Pass `witness` as the delegate — all calls flow into bridge.events
    _ = witness
}

// ────────────────────────────────────────────────────────────────────────────
// 5. PATTERN D: Combine AsyncStreams (Swift structured concurrency)
// ────────────────────────────────────────────────────────────────────────────

func patternD_taskGroup() async {
    let bridge = await DownloadDelegateAsyncBridge()

    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for await event in await bridge.events {
                if case .downloadDidFail(_, let error) = event {
                    print("Error handler: \(error)")
                }
            }
        }
        group.addTask {
            for await event in await bridge.events {
                if case .downloadDidFinish(_, let path) = event {
                    print("Post-process: \(path)")
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Entry point
// ────────────────────────────────────────────────────────────────────────────

@main
struct DelegateBridgeClient {
    static func main() async {
        print("=== Pattern A: Unified AsyncStream ===")
        await patternA_unifiedStream()

        print("\n=== Pattern B: Filter events from unified stream ===")
        await patternB_filterEvents()

        print("\n=== Pattern C: Protocol Witness (mock) ===")
        let mockDelegate = DownloadDelegateWitness(
            downloadDidStart:    { url in print("mock start: \(url)") },
            downloadDidProgress: { _, r, t in print("mock progress: \(r)/\(t)") },
            downloadDidFinish:   { _, path in print("mock done at \(path)") },
            downloadDidFail:     { _, err in print("mock error: \(err)") }
        )
        let url = URL(string: "https://example.com/test")!
        mockDelegate.downloadDidStart(url: url)
        mockDelegate.downloadDidProgress(url: url, bytesReceived: 512, totalBytes: 1024)
    }
}
