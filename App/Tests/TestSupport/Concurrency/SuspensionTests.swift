import Testing

@Suite(.timeLimit(.minutes(1)))
actor SuspensionTests {
    private var didStart = false
    private var didResume = false

    @Test
    func `Waiting for suspension does not return before the operation starts`() async throws {
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

    @Test
    func `A late observer receives the start signal after an already cancelled operation`() async {
        let suspension = Suspension()
        let operation = Task {
            didStart = true
            await suspension.suspend()
        }
        operation.cancel()
        await operation.value

        await suspension.waitUntilStarted()
        #expect(didStart)
        #expect(!Task.isCancelled)
    }

    @Test
    func `Suspension returns only after the operation is cancelled`() async throws {
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

    @Test
    func `A cancelled start observer returns even when no operation starts`() async {
        let suspension = Suspension()
        let observer = Task { @concurrent in
            await suspension.waitUntilStarted()
            return Task.isCancelled
        }
        observer.cancel()

        #expect(await observer.value)
    }
}
