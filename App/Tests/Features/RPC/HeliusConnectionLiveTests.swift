import Testing
@testable import widgets

@MainActor
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct HeliusConnectionLiveTests {
    @Test
    func `Helius accepts the configured key`() async throws {
        try await HeliusConnection(rpcStore: .inMemory())
            .connect(try LiveClients.heliusAPIKey())
    }

    @Test
    func `Helius rejects an unknown key`() async {
        await #expect(throws: RPCConnectionError.invalidKey) {
            try await HeliusConnection(rpcStore: .inMemory())
                .connect("00000000-0000-0000-0000-000000000000")
        }
    }
}
