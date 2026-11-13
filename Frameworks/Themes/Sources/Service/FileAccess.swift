import Foundation
import Synchronization

/// A coordinated file operation that runs on one serial queue.
final class FileAccess: Sendable {
    /// Synchronous work that receives a coordinated URL and the operation's file access.
    typealias Operation<Value: Sendable> = @Sendable (URL, FileAccess) throws -> Value

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Themes.FileAccess"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// The operation's cancellation and coordination state.
    private struct State {
        var cancelled = false
        var finished = false
        var resumeCancellation: (@Sendable () -> Void)?
        var coordinator: NSFileCoordinator?
    }

    private let state = Mutex(State())

    /// Creates the file access for one coordinated operation.
    private init() {}

    /// Runs synchronous work with coordinated access to a file.
    ///
    /// - Parameters:
    ///   - url: The local or security-scoped package location.
    ///   - writing: Whether the work replaces the item at `url` rather than reading it.
    ///   - operation: The synchronous work to run.
    /// - Returns: The work's result.
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

    /// Throws if the operation was cancelled.
    ///
    /// - Throws: `CancellationError` if the operation was cancelled.
    func checkCancellation() throws {
        if state.withLock(\.cancelled) { throw CancellationError() }
    }

    /// Starts coordinated access to a file and runs work once access is granted.
    ///
    /// - Parameters:
    ///   - url: The package location.
    ///   - writing: Whether the work replaces the item at `url`.
    ///   - operation: The synchronous work to run.
    ///   - continuation: The caller's continuation.
    /// - Throws: A validation or cancellation error before coordination starts.
    private func begin<Value: Sendable>(at url: URL, writing: Bool,
                                       operation: @escaping Operation<Value>,
                                       continuation: CheckedContinuation<Value, any Error>) throws {
        try checkCancellation()
        guard url.isFileURL else {
            throw ValidationError(path: "package", kind: .unreadable)
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

    /// Marks the work as started unless the operation was cancelled.
    ///
    /// - Throws: `CancellationError` if the operation was cancelled first.
    private func startWork() throws {
        try state.withLock { state in
            guard !state.cancelled else { throw CancellationError() }
            state.resumeCancellation = nil
        }
    }

    /// Releases the coordinator and resumes the caller unless cancellation already did.
    ///
    /// - Parameters:
    ///   - result: The operation's result.
    ///   - continuation: The caller's continuation.
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

    /// Cancels the operation.
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
