import RPC
import Testing

/// Verifies signature watches on real networks without funding or sending transactions.
@Suite(.tags(.network))
struct SignatureEventLiveTests {
    /// Watches a signature that never lands and waits for a new root on the same connection.
    ///
    /// Sixty-four zero bytes form a well-formed signature that no landed transaction carries,
    /// so the first event must be a root. Devnet already runs Alpenglow, and the Confirmer
    /// schedules its expiry checks from roots, so root subscriptions must keep delivering under Alpenglow.
    /// - Parameters:
    ///   - helius: Whether to verify Helius or public Solana.
    ///   - network: The network whose endpoint to verify.
    /// - Throws: A credential, provider, timeout, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)), arguments: [true, false], [Network.mainnet, .devnet])
    func `Live clients acknowledge a signature watch and deliver a root`(helius: Bool, network: Network) async throws {
        let source = try LiveClients.client(helius: helius, network: network)
        // Returning means both subscriptions were acknowledged; dropping the stream closes its connection.
        let events = try await source.events(for: String(repeating: "1", count: 64))
        var iterator = events.makeAsyncIterator()
        let event = try #require(try await iterator.next())
        guard case .rooted = event else {
            Issue.record("Expected a root, received \(event)")
            return
        }
    }
}
