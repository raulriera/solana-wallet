/// Coordinates cancellation with a suspended dependency without sleeps or polling.
struct Suspension: Sendable {
    private let started = AsyncStream<Void>.makeStream()
    private let pending = AsyncStream<Void>.makeStream()

    /// Suspends the dependency operation until its task is cancelled.
    func suspend() async {
        started.continuation.yield(())
        started.continuation.finish()
        for await _ in pending.stream {}
    }

    /// Waits until the dependency has entered its cancellable suspension.
    func waitUntilStarted() async {
        for await _ in started.stream {}
    }
}
