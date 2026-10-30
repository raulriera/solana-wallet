import Foundation
import Synchronization

final class ManualClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant
    typealias Duration = Swift.Duration

    let minimumResolution: Duration = .nanoseconds(1)
    let waits: AsyncStream<Instant>
    private let events: AsyncStream<Instant>.Continuation
    private let state = Mutex(State())

    init() {
        (waits, events) = AsyncStream.makeStream()
    }

    var now: Instant { state.withLock(\.now) }

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

    deinit { events.finish() }

    private struct State {
        var now = ContinuousClock.now
        var waiters: [UUID: Waiter] = [:]
    }

    private struct Waiter {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }
}
