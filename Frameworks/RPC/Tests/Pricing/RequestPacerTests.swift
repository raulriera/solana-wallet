import Testing
@testable import RPC

/// Exercises admission timing without arbitrary sleeps or external traffic.
struct RequestPacerTests {
    /// Verifies simultaneous waiters recheck admission after actor reentrancy.
    @Test(.timeLimit(.minutes(1)))
    func `Concurrent price requests share slots instead of waking into a burst`() async throws {
        let clock = ManualClock()
        let startedAt = clock.now
        let pacer = RequestPacer(interval: .seconds(3), clock: clock)
        try await pacer.wait()
        let first = Task { try await pacer.wait() }
        let second = Task { try await pacer.wait() }
        defer { first.cancel(); second.cancel() }
        var waits = clock.waits.makeAsyncIterator()
        let deadline = try #require(await waits.next())
        #expect(deadline == startedAt.advanced(by: .seconds(3)))
        #expect(await waits.next() == deadline)

        clock.advance(to: deadline)
        let next = try #require(await waits.next())
        #expect(next == deadline.advanced(by: .seconds(3)))
        clock.advance(to: next)

        try await first.value
        try await second.value
    }

    /// Verifies an idle provider admits one immediate request without saving unused slots.
    @Test(.timeLimit(.minutes(1)))
    func `Idle time does not accumulate price request bursts`() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(interval: .seconds(3), clock: clock)
        try await pacer.wait()
        clock.advance(to: clock.now.advanced(by: .seconds(600)))
        try await pacer.wait()
        let resumedAt = clock.now
        let next = Task { try await pacer.wait() }
        defer { next.cancel() }
        var waits = clock.waits.makeAsyncIterator()
        let deadline = try #require(await waits.next())
        #expect(deadline == resumedAt.advanced(by: .seconds(3)))
        clock.advance(to: deadline)
        try await next.value
    }

    /// Verifies cancelled waiters exit promptly and leave the next slot available.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling queued prices does not consume a request slot`() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(interval: .seconds(3), clock: clock)
        try await pacer.wait()
        let cancelled = Task { try await pacer.wait() }
        defer { cancelled.cancel() }
        var waits = clock.waits.makeAsyncIterator()
        let deadline = try #require(await waits.next())
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        let replacement = Task { try await pacer.wait() }
        defer { replacement.cancel() }
        #expect(await waits.next() == deadline)
        clock.advance(to: deadline)
        try await replacement.value
    }
}
