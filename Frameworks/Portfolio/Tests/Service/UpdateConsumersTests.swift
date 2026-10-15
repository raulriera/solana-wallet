import Foundation
import Testing
@testable import Portfolio

/// Verifies the update streams that a refresh or an observation shares between its consumers.
struct UpdateConsumersTests {
    /// Verifies that a new consumer receives its first update before any update sent to everyone.
    @Test
    func `A consumer receives its first update before later ones`() async {
        var consumers = UpdateConsumers()
        let stream = consumers.add(first: update(1)) { _ in }

        consumers.send(update(2))
        consumers.finish()

        #expect(await stream.map(\.revision).reduce(into: [UInt64]()) { $0.append($1) } == [1, 2])
    }

    /// Verifies that every consumer receives an update sent to everyone, and that finishing ends every stream.
    @Test
    func `Every consumer receives each update until the streams finish`() async {
        var consumers = UpdateConsumers()
        let first = consumers.add { _ in }
        let second = consumers.add { _ in }

        consumers.send(update(1))
        consumers.finish()

        #expect(await first.map(\.revision).reduce(into: [UInt64]()) { $0.append($1) } == [1])
        #expect(await second.map(\.revision).reduce(into: [UInt64]()) { $0.append($1) } == [1])
    }

    /// Verifies that a stream that ends reports its consumer, so the owner can remove it.
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

    /// Creates an update without a snapshot.
    /// - Parameter revision: The update's order.
    /// - Returns: A refreshing update with that order.
    private func update(_ revision: UInt64) -> Update {
        Update(snapshot: nil, phase: .refreshing, revision: revision)
    }
}
