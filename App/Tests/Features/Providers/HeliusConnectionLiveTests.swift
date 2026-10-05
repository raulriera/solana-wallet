import Testing
@testable import widgets

/// Verifies Helius's real key check on mainnet with read-only requests.
@Suite(.timeLimit(.minutes(1)))
struct HeliusConnectionLiveTests {
    /// The configured key passes the same check onboarding performs.
    /// - Throws: A missing-credential prerequisite or a connection failure.
    @Test
    func `Helius accepts the configured key`() async throws {
        try await HeliusConnection(keys: SavedKeys()).connect(apiKey: try MainnetClients.heliusAPIKey())
    }

    /// Helius itself rejects an unknown key.
    @Test
    func `Helius rejects an unknown key`() async {
        await #expect(throws: ProviderConnectionError.invalidKey) {
            try await HeliusConnection(keys: SavedKeys()).connect(apiKey: "00000000-0000-0000-0000-000000000000")
        }
    }
}
