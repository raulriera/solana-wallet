import RPC
import Testing

@Suite(.tags(.network))
struct SignatureEventLiveTests {
    @Test(.timeLimit(.minutes(1)), arguments: [true, false], [Network.mainnet, .devnet])
    func `Live clients acknowledge a signature watch and deliver a root`(helius: Bool, network: Network) async throws {
        let source = try LiveClients.client(helius: helius, network: network)
        let events = try await source.events(for: String(repeating: "1", count: 64))
        var iterator = events.makeAsyncIterator()
        let event = try #require(try await iterator.next())
        let isRooted = if case .rooted = event { true } else { false }
        #expect(isRooted, "Expected a root, received \(event)")
    }
}
