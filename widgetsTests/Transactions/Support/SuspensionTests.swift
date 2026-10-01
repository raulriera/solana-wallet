import Testing

/// Uses isolated flags to check ordering without sleeps or main-actor scheduling.
@Suite(.timeLimit(.minutes(1)))
actor SuspensionTests {
    private var didStart = false
    private var didResume = false

    /// An observer registered first cannot finish before the dependency starts.
    @Test("waiting for suspension does not return before the operation starts")
    func observerWaitsForStart() async throws {
        let suspension = Suspension()
        let observing = AsyncStream<Void>.makeStream()
        let observer = Task {
            #expect(!didStart)
            observing.continuation.finish()
            await suspension.waitUntilStarted()
            #expect(didStart)
        }
        defer { observer.cancel() }
        for await _ in observing.stream {}
        try Task.checkCancellation()

        let operation = Task {
            didStart = true
            await suspension.suspend()
        }
        defer { operation.cancel() }
        await withTaskCancellationHandler {
            await observer.value
        } onCancel: {
            observer.cancel()
            operation.cancel()
        }
        operation.cancel()
        await operation.value
    }

    /// A completed start notification remains observable after the operation ends.
    @Test("a late observer receives the start signal after an already cancelled operation")
    func lateObserverReceivesStart() async {
        let suspension = Suspension()
        let operation = Task {
            didStart = true
            await suspension.suspend()
        }
        // Actor isolation keeps the operation from starting before this cancellation.
        operation.cancel()
        await operation.value

        await suspension.waitUntilStarted()
        #expect(didStart)
        #expect(!Task.isCancelled)
    }

    /// Publishing the start signal must leave the dependency suspended until cancellation.
    @Test("suspension returns only after the operation is cancelled")
    func cancellationReleasesSuspension() async throws {
        let suspension = Suspension()
        let operation = Task {
            didStart = true
            await suspension.suspend()
            didResume = true
            return Task.isCancelled
        }
        defer { operation.cancel() }
        await suspension.waitUntilStarted()
        try Task.checkCancellation()
        #expect(didStart)
        #expect(!didResume)

        operation.cancel()
        #expect(await operation.value)
        #expect(didResume)
    }

    /// Cancelling the observer must not require an operation to publish a start signal.
    @Test("a cancelled start observer returns even when no operation starts")
    func cancelledObserverDoesNotRequireStart() async {
        let suspension = Suspension()
        let observer = Task { @concurrent in
            await suspension.waitUntilStarted()
            return Task.isCancelled
        }
        observer.cancel()

        #expect(await observer.value)
    }
}
