import Foundation

/// One watch of a pending transaction, which callers can join and which keeps its result after it ends.
///
/// A caller that's cancelled stops waiting at once; the watch itself runs until it ends or is cancelled.
@MainActor
final class TransactionWatch {
    private var task: Task<Void, Never>?
    private var result: Result<Outcome, any Error>?
    private var waiters: [UUID: CheckedContinuation<Outcome, any Error>] = [:]

    var isFinished: Bool { result != nil }

    /// Creates a watch and runs it in its own task.
    ///
    /// - Parameter operation: Watches the transaction until it settles and returns its outcome.
    init(_ operation: @escaping @MainActor () async throws -> Outcome) {
        task = Task {
            let result: Result<Outcome, any Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            finish(with: result)
        }
    }

    /// Waits for the watch's result.
    ///
    /// - Returns: The transaction's settled outcome.
    /// - Throws: `CancellationError` if the caller is cancelled, or the watch's error.
    func value() async throws -> Outcome {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let result {
                    continuation.resume(with: result)
                } else if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop(id) }
        }
    }

    /// Cancels the watch.
    func cancel() {
        task?.cancel()
    }

    /// Keeps the watch's result and hands it to every caller that waits.
    ///
    /// - Parameter result: The transaction's settled outcome, or the watch's error.
    private func finish(with result: Result<Outcome, any Error>) {
        self.result = result
        let waiters = waiters
        self.waiters = [:]
        for waiter in waiters.values { waiter.resume(with: result) }
    }

    /// Ends one caller's wait with a cancellation error.
    ///
    /// - Parameter id: The identifier of the caller's wait.
    private func stop(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
