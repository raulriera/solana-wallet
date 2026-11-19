/// The running observations of shared work, which starts with the first observer and ends with the last one.
@MainActor
final class Observers {
    /// The number of running ``observe(starting:ending:)`` calls.
    private var count = 0

    var isEmpty: Bool { count == 0 }

    /// Observes until the calling task is cancelled.
    ///
    /// - Parameters:
    ///   - start: Starts the shared work, for the first observer.
    ///   - end: Ends the shared work, after the last observer.
    func observe(starting start: () -> Void, ending end: () -> Void) async {
        guard !Task.isCancelled else { return }
        count += 1
        if count == 1 { start() }
        let lifetime = AsyncStream<Never> { _ in }
        for await _ in lifetime {}
        count -= 1
        if count == 0 { end() }
    }
}
