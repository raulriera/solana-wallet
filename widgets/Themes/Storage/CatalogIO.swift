import Foundation
import Synchronization

/// Serializes private catalog filesystem transactions outside the main actor and cooperative pool.
nonisolated enum CatalogIO {
    // Shared by catalog instances so revision checks and commits have no suspension between them.
    private static let queue = DispatchQueue(label: "ThemeCatalog.IO", qos: .background)

    /// Suspends while bounded filesystem work runs on the private background queue.
    /// - Parameter operation: Work that checks cancellation before its commit point.
    /// - Returns: The operation's result, including success when cancellation follows a commit.
    /// - Throws: A storage or cooperative cancellation error.
    static func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (_ checkCancellation: () throws -> Void) throws -> Value
    ) async throws -> Value {
        let cancelled = Mutex(false)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let result = autoreleasepool {
                        Result {
                            let check = { if cancelled.withLock({ $0 }) { throw CancellationError() } }
                            try check()
                            return try operation(check)
                        }
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: { cancelled.withLock { $0 = true } }
    }

    /// Reclaims unreferenced files independently of cancellation after commit or failure.
    /// - Parameter url: An operation's staging directory or obsolete package generation.
    static func discard(_ url: URL) async {
        await withCheckedContinuation { continuation in
            queue.async {
                // Cleanup failure must not turn an already committed mutation into a failure.
                try? FileManager.default.removeItem(at: url)
                continuation.resume()
            }
        }
    }
}
