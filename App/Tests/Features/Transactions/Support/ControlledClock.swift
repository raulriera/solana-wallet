struct ControlledClock: Clock {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    let now = ContinuousClock.now
    let minimumResolution: Duration = .zero
    private let onSleep: Sleep

    init(onSleep: @escaping Sleep) {
        self.onSleep = onSleep
    }

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        try await onSleep(now.duration(to: deadline))
        try Task.checkCancellation()
    }
}
