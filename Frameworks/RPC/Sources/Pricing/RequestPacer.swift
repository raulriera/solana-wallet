/// A type that spaces the start of requests.
protocol RequestPacing: Sendable {
    /// Waits until one request may start.
    ///
    /// - Throws: A cancellation or clock error.
    func wait() async throws
}

/// A pacer that spaces requests by a minimum interval.
actor RequestPacer<C: Clock>: RequestPacing where C.Duration == Duration {
    private let clock: C
    private let interval: Duration
    private var lastRequest: C.Instant?

    /// Creates a pacer with a minimum interval between requests.
    ///
    /// - Parameters:
    ///   - interval: The minimum duration between requests.
    ///   - clock: The clock used for waiting.
    init(interval: Duration, clock: C) {
        self.interval = interval
        self.clock = clock
    }

    func wait() async throws {
        while let lastRequest {
            try Task.checkCancellation()
            let deadline = lastRequest.advanced(by: interval)
            guard clock.now < deadline else { break }
            try await clock.sleep(until: deadline, tolerance: .zero)
        }
        try Task.checkCancellation()
        lastRequest = clock.now
    }
}
