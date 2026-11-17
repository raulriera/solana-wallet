import Foundation
import Testing
@testable import Portfolio

struct UpdateConsumersTests {
    @Test
    func `A consumer receives its first update before later ones`() async {
        var consumers = UpdateConsumers()
        let stream = consumers.add(first: update(1)) { _ in }

        consumers.send(update(2))
        consumers.finish()

        #expect(await stream.map(\.revision).reduce(into: [UInt64]()) { $0.append($1) } == [1, 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func `An ended stream reports its consumer for removal`() async {
        let (ended, endings) = AsyncStream<UUID>.makeStream()
        var consumers = UpdateConsumers()
        _ = consumers.add { endings.yield($0) }

        consumers.finish()
        var reported = ended.makeAsyncIterator()
        let id = await reported.next()

        #expect(id != nil)
        consumers.remove(id ?? UUID())
        #expect(consumers.isEmpty)
    }

    private func update(_ revision: UInt64) -> Update {
        Update(snapshot: nil, phase: .refreshing, revision: revision)
    }
}
