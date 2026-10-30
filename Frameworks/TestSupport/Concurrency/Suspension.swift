struct Suspension: Sendable {
    private let started = AsyncStream<Void>.makeStream()
    private let pending = AsyncStream<Void>.makeStream()

    func suspend() async {
        started.continuation.yield(())
        started.continuation.finish()
        for await _ in pending.stream {}
    }

    func waitUntilStarted() async {
        for await _ in started.stream {}
    }

    func resume() {
        pending.continuation.finish()
    }
}
