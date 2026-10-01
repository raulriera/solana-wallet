/// Admission control shared by one price provider's requests.
protocol RequestPacing: Sendable {
    /// Waits for permission to start one request without reserving slots for cancelled work.
    /// - Throws: A cancellation or clock error while waiting.
    func wait() async throws
}

/// Spaces requests using monotonic time, including callers waiting concurrently.
actor RequestPacer<C: Clock>: RequestPacing where C.Duration == Duration {
    private let clock: C
    private let interval: Duration
    private var lastRequest: C.Instant?

    /// Creates admission control for one shared request budget.
    /// - Parameters:
    ///   - interval: The minimum duration between admitted requests.
    ///   - clock: The monotonic clock used for waiting.
    init(interval: Duration, clock: C) {
        self.interval = interval
        self.clock = clock
    }

    /// Admits the first request immediately and spaces subsequent requests without accumulating bursts.
    /// - Throws: A cancellation or clock error; cancelled waiters do not consume a slot.
    func wait() async throws {
        while let lastRequest {
            try Task.checkCancellation()
            let deadline = lastRequest.advanced(by: interval)
            guard clock.now < deadline else { break }
            try await clock.sleep(until: deadline, tolerance: .zero)
            // Sleeping releases actor isolation. Another caller may have taken the slot.
        }
        try Task.checkCancellation()
        lastRequest = clock.now
    }
}
