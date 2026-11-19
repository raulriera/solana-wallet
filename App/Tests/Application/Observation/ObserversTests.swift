import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ObserversTests {
    @MainActor
    private final class Work {
        var starts = 0
        var stops = 0
    }

    @Test
    func `Observers share work, which the first one starts and the last one ends`() async {
        let observers = Observers()
        let work = Work()
        let (entries, entering) = AsyncStream.makeStream(of: Void.self)
        var entered = entries.makeAsyncIterator()
        let observe = {
            Task {
                entering.yield()
                await observers.observe(starting: { work.starts += 1 }, ending: { work.stops += 1 })
            }
        }
        let first = observe()
        let second = observe()
        await entered.next()
        await entered.next()

        first.cancel()
        await first.value
        #expect(work.starts == 1)
        #expect(work.stops == 0)
        #expect(!observers.isEmpty)

        second.cancel()
        await second.value
        #expect(work.stops == 1)
        #expect(observers.isEmpty)
    }
}
