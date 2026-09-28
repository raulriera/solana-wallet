/// A clock whose suspensions are controlled by the test rather than elapsed time.
struct ControlledClock: Clock {
    /// A fixed origin used to express requested delays without measuring wall time.
    let now = ContinuousClock.now
    /// The test clock's exact duration resolution.
    let minimumResolution: Duration = .zero
    private let onSleep: @Sendable (Duration) async throws -> Void

    /// Creates a clock with a test-controlled suspension operation.
    ///
    /// - Parameter onSleep: The operation receiving each requested delay.
    init(onSleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.onSleep = onSleep
    }

    /// Suspends through the injected operation, preserving task cancellation.
    ///
    /// - Parameters:
    ///   - deadline: The target instant relative to the fixed origin.
    ///   - tolerance: The permitted scheduling tolerance; the test doesn't use wall time.
    /// - Throws: A scripted error or `CancellationError`.
    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        try await onSleep(now.duration(to: deadline))
        try Task.checkCancellation()
    }
}
