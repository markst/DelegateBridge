import DelegateBridge
import Foundation

// ────────────────────────────────────────────────────────────────────────────
// 1. DECLARE YOUR DELEGATE PROTOCOL – just add @AsyncStreamBridge
// ────────────────────────────────────────────────────────────────────────────

@AsyncStreamBridge
protocol DownloadDelegate {
    func downloadDidStart(url: URL)
    func downloadDidProgress(url: URL, bytesReceived: Int64, totalBytes: Int64)
    func downloadDidFinish(url: URL, localPath: URL)
    func downloadDidFail(url: URL, error: Error)
}
