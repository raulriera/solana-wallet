import Foundation
import Synchronization

/// Runs theme catalog file operations one at a time on a background queue.
nonisolated enum CatalogIO {
    /// Synchronous file work that receives a cancellation check.
    typealias Operation<Value: Sendable> = @Sendable (_ checkCancellation: () throws -> Void) throws -> Value

    private static let queue = DispatchQueue(label: "ThemeCatalog.IO", qos: .background)

    /// Runs file work on the catalog's queue.
    ///
    /// - Parameter operation: The work to run.
    /// - Returns: The work's result.
    /// - Throws: The work's error or a cancellation error.
    static func perform<Value: Sendable>(
        _ operation: @escaping Operation<Value>
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

    /// Deletes a file or folder on the catalog's queue, ignoring errors.
    ///
    /// - Parameter url: The file or folder to delete.
    static func discard(_ url: URL) async {
        await withCheckedContinuation { continuation in
            queue.async {
                try? FileManager.default.removeItem(at: url)
                continuation.resume()
            }
        }
    }
}
