import Encoding
import Portfolio
import RPC
import Testing

@Suite(.tags(.network))
struct AccountChangeLiveTests {
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Mainnet clients deliver finalized account notifications while watching a full token list`(helius: Bool) async throws {
        let source = try LiveClients.client(helius: helius)
        let tokenAccounts = (1...(2 + TokenList.addedTokenLimit)).map { Base58.encode(Array(repeating: UInt8($0), count: 32)) }
        let slots = try await source.changedSlots(for: ["SysvarC1ock11111111111111111111111111111111"] + tokenAccounts)
        try await withThrowingTaskGroup(of: Void.self) { group in
            let (received, relay) = AsyncThrowingStream<UInt64, any Error>.makeStream(bufferingPolicy: .bufferingNewest(2))
            group.addTask {
                do {
                    for try await slot in slots {
                        try Task.checkCancellation()
                        relay.yield(slot)
                    }
                    relay.finish()
                } catch { relay.finish(throwing: error) }
            }
            defer { group.cancelAll(); relay.finish() }
            var iterator = received.makeAsyncIterator()
            let first = try #require(try await iterator.next())
            let second = try #require(try await iterator.next())
            #expect(second > first)
        }
    }
}
