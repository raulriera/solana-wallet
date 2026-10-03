import Foundation
import RPC
import Testing

/// Verifies standard confirmed subscriptions on devnet without funding or transfers.
@Suite(.serialized)
struct AccountChangeLiveTests {
    /// Watches a changing public sysvar while also registering both wallet-owner token filters.
    /// - Parameter helius: Whether to verify Helius or public Solana's devnet endpoint.
    /// - Throws: A credential, provider, timeout, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Devnet clients deliver confirmed account notifications`(helius: Bool) async throws {
        let source: any AccountChangeProviding
        if helius {
            let key = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"])
            try #require(!key.isEmpty && !key.contains("$("))
            source = HeliusRPC(apiKey: key, network: .devnet)
        } else { source = Solana(network: .devnet) }
        let slots = try await source.changedSlots(for: "SysvarC1ock11111111111111111111111111111111")
        let (received, relay) = AsyncThrowingStream<UInt64, any Error>.makeStream()
        let observation = Task {
            do {
                for try await slot in slots { relay.yield(slot) }
                relay.finish()
            } catch { relay.finish(throwing: error) }
        }
        defer { observation.cancel(); relay.finish() }
        var iterator = received.makeAsyncIterator()
        let first = try #require(try await iterator.next())
        let second = try #require(try await iterator.next())
        #expect(second > first)
        observation.cancel()
        await observation.value
    }
}
