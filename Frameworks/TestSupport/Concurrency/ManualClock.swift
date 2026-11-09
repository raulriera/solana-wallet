import Foundation
import Synchronization
import Testing

final class ManualClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant
    typealias Duration = Swift.Duration

    let minimumResolution: Duration = .nanoseconds(1)
    let waits: AsyncStream<Wait>
    private let events: AsyncStream<Wait>.Continuation
    private let state = Mutex(State())

    init() {
        (waits, events) = AsyncStream.makeStream()
    }

    var now: Instant { state.withLock(\.now) }
    var startedWaitCount: Int { state.withLock(\.startedWaitCount) }

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
                        state.startedWaitCount += 1
                        events.yield(Wait(id: id, deadline: deadline))
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
            state.now = max(state.now, instant)
            let due = state.waiters.filter { $0.value.deadline <= state.now }
            for id in due.keys { state.waiters.removeValue(forKey: id) }
            return due.values.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }

    func durationToNextWait(_ waits: inout AsyncStream<Wait>.AsyncIterator) async throws -> Duration {
        now.duration(to: try #require(await nextDeadline(&waits)))
    }

    @discardableResult
    func advanceToNextWait(_ waits: inout AsyncStream<Wait>.AsyncIterator) async throws -> Duration {
        let deadline = try #require(await nextDeadline(&waits))
        let duration = now.duration(to: deadline)
        advance(to: deadline)
        return duration
    }

    @discardableResult
    func advanceWaits(_ waits: inout AsyncStream<Wait>.AsyncIterator, count: Int = .max,
                      except held: (Duration) async throws -> Bool = { _ in false }) async throws -> [Duration] {
        var advanced: [Duration] = []
        while advanced.count < count, let deadline = await nextDeadline(&waits) {
            let duration = now.duration(to: deadline)
            if try await held(duration) { continue }
            advance(to: deadline)
            advanced.append(duration)
        }
        return advanced
    }

    func nextDeadline(_ waits: inout AsyncStream<Wait>.AsyncIterator) async -> Instant? {
        while let wait = await waits.next(isolation: #isolation) {
            if state.withLock({ $0.waiters[wait.id] != nil }) { return wait.deadline }
        }
        return nil
    }

    deinit { events.finish() }

    struct Wait: Sendable {
        fileprivate let id: UUID
        fileprivate let deadline: Instant
    }

    private struct State {
        var now = ContinuousClock.now
        var waiters: [UUID: Waiter] = [:]
        var startedWaitCount = 0
    }

    private struct Waiter {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }
}
