/// Coordinates cancellation with a suspended dependency without sleeps or polling.
/// Create one instance per operation, with one start observer and one suspended task.
struct Suspension: Sendable {
    private let started = AsyncStream<Void>.makeStream()
    private let pending = AsyncStream<Void>.makeStream()

    /// Suspends the dependency operation until its task is cancelled.
    func suspend() async {
        started.continuation.yield(())
        started.continuation.finish()
        for await _ in pending.stream {}
    }

    /// Waits for the dependency to start, or returns when the observing task is cancelled.
    func waitUntilStarted() async {
        for await _ in started.stream {}
    }
}
