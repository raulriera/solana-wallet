import Foundation
import Synchronization

/// Bridges coordinated file work onto one serial queue, outside the main thread and Swift's shared executor.
final class FileAccess: Sendable {
    /// Synchronous work that receives a coordinated URL and access to cancellation checks.
    typealias Operation<Value: Sendable> = @Sendable (URL, FileAccess) throws -> Value

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Themes.FileAccess"
        // A person waits for every import and export, so the work runs at user-initiated priority.
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private struct State {
        var cancelled = false
        var finished = false
        var resumeCancellation: (@Sendable () -> Void)?
        var coordinator: NSFileCoordinator?
    }

    // Coordinator creation and registration happen on the queue. The mutex protects
    // registration against cancellation; only cancel(), documented as thread-safe by
    // Foundation, is called from another thread. No file work runs under this lock.
    private let state = Mutex(State())

    /// Creates cancellation state for one coordinated operation.
    private init() {}

    /// Suspends the caller while coordinated work runs at user-initiated priority.
    /// - Parameters:
    ///   - url: The local or security-scoped package location.
    ///   - writing: Whether access replaces the destination rather than reading it.
    ///   - operation: Synchronous work that must finish within the coordinated accessor.
    /// - Returns: The owned result after security-scoped access ends.
    /// - Throws: An access, operation, or cancellation error.
    static func perform<Value: Sendable>(at url: URL, writing: Bool = false,
                                        operation: @escaping Operation<Value>) async throws -> Value {
        let access = FileAccess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let enqueue = access.state.withLock { state in
                    guard !state.cancelled else { return false }
                    state.resumeCancellation = { continuation.resume(throwing: CancellationError()) }
                    return true
                }
                guard enqueue else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                queue.addOperation {
                    do {
                        try access.begin(at: url, writing: writing, operation: operation, continuation: continuation)
                    } catch {
                        access.finish(.failure(error), continuation: continuation)
                    }
                }
            }
        } onCancel: {
            access.cancel()
        }
    }

    /// Checks the originating task's cancellation from a callback without Swift task context.
    /// - Throws: `CancellationError` if the caller cancelled the operation.
    func checkCancellation() throws {
        if state.withLock(\.cancelled) { throw CancellationError() }
    }

    /// Registers asynchronous coordination without occupying a worker while waiting for access.
    /// - Parameters:
    ///   - url: The caller's package location.
    ///   - writing: Whether access replaces the destination.
    ///   - operation: Work confined to the accessor's lifetime.
    ///   - continuation: The suspended caller, resumed once after cleanup.
    /// - Throws: A validation or cancellation error before coordination is registered.
    private func begin<Value: Sendable>(at url: URL, writing: Bool,
                                       operation: @escaping Operation<Value>,
                                       continuation: CheckedContinuation<Value, any Error>) throws {
        try checkCancellation()
        guard url.isFileURL else {
            throw ValidationError(path: "package", reason: "Expected a local file URL.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let intent = writing ? NSFileAccessIntent.writingIntent(with: url, options: .forReplacing)
                                 : NSFileAccessIntent.readingIntent(with: url, options: [])
            try state.withLock { state in
                guard !state.cancelled else { throw CancellationError() }
                let coordinator = NSFileCoordinator()
                state.coordinator = coordinator
                coordinator.coordinate(with: [intent], queue: Self.queue) { error in
                    let result = autoreleasepool {
                        Result {
                            try self.startWork()
                            if let error { throw error }
                            return try operation(intent.url, self)
                        }
                    }
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    self.finish(result, continuation: continuation)
                }
            }
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Claims active work so cancellation cannot report failure after an atomic write starts.
    /// - Throws: `CancellationError` when cancellation won before the accessor began.
    private func startWork() throws {
        try state.withLock { state in
            guard !state.cancelled else { throw CancellationError() }
            state.resumeCancellation = nil
        }
    }

    /// Releases coordination state and resumes a caller only if pending cancellation did not win.
    /// - Parameters:
    ///   - result: The final accessor or setup outcome.
    ///   - continuation: The caller's continuation, resumed outside the state lock.
    private func finish<Value: Sendable>(_ result: Result<Value, any Error>,
                                         continuation: CheckedContinuation<Value, any Error>) {
        let resume = state.withLock { state in
            state.coordinator = nil
            guard !state.finished else { return false }
            state.finished = true
            state.resumeCancellation = nil
            return true
        }
        if resume { continuation.resume(with: result) }
    }

    /// Cancels a pending request and signals cooperative cancellation inside active file work.
    private func cancel() {
        let resume = state.withLock { state in
            state.cancelled = true
            state.coordinator?.cancel()
            let resume = state.resumeCancellation
            if resume != nil { state.finished = true }
            state.resumeCancellation = nil
            return resume
        }
        resume?()
    }
}
