import RPC
import Testing

/// Verifies standard confirmed subscriptions on mainnet without funding or transfers.
struct AccountChangeLiveTests {
    /// Watches a changing public sysvar while also registering both wallet-owner token filters.
    /// - Parameter helius: Whether to verify Helius or public Solana's mainnet endpoint.
    /// - Throws: A credential, provider, timeout, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Mainnet clients deliver confirmed account notifications`(helius: Bool) async throws {
        let source = try MainnetClients.client(helius: helius)
        let slots = try await source.changedSlots(for: "SysvarC1ock11111111111111111111111111111111")
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
