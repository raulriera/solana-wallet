import Foundation
import Synchronization

/// A monotonic clock advanced explicitly by tests instead of wall-clock delays.
final class ManualClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant
    typealias Duration = Swift.Duration

    let minimumResolution: Duration = .nanoseconds(1)
    let waits: AsyncStream<Instant>
    private let events: AsyncStream<Instant>.Continuation
    private let state = Mutex(State())

    /// Creates a clock with a stream of registered sleep deadlines.
    init() {
        (waits, events) = AsyncStream.makeStream()
    }

    /// The current simulated monotonic instant.
    var now: Instant { state.withLock { $0.now } }

    /// Suspends until the test advances time to the deadline or cancels this task.
    /// - Parameters:
    ///   - deadline: The instant at which to resume.
    ///   - tolerance: The permitted timing tolerance, unused by this exact clock.
    /// - Throws: `CancellationError` when cancelled before or during sleep.
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if deadline <= state.now {
                        continuation.resume()
                    } else {
                        state.waiters[id] = Waiter(deadline: deadline, continuation: continuation)
                        events.yield(deadline)
                    }
                }
            }
        } onCancel: {
            let waiter = self.state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.continuation.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
    }

    /// Advances simulated time and resumes every waiter whose deadline is due.
    /// - Parameter instant: The new instant, at or after the clock's current time.
    func advance(to instant: Instant) {
        let due = state.withLock { state in
            precondition(instant >= state.now)
            state.now = instant
            let due = state.waiters.filter { $0.value.deadline <= instant }
            for id in due.keys { state.waiters.removeValue(forKey: id) }
            return due.values.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }

    /// Finishes deadline observation when the clock is released.
    deinit { events.finish() }

    /// Synchronous state protected by the clock's mutex.
    private struct State {
        var now = ContinuousClock.now
        var waiters: [UUID: Waiter] = [:]
    }

    /// One cancellable clock suspension.
    private struct Waiter {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }
}
