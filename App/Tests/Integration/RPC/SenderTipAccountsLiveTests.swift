import Foundation
@testable import RPC
import Testing

/// Compares the bundled Sender tip accounts with the list Helius publishes; there is no endpoint for it.
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct SenderTipAccountsLiveTests {
    /// Every bundled tip account must still appear in Helius's Sender documentation.
    @Test
    func `Bundled Sender tip accounts match the published list`() async throws {
        let url = URL(string: "https://www.helius.dev/docs/sending-transactions/sender.md")!
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        try #require((response as? HTTPURLResponse)?.statusCode == 200)
        let page = String(decoding: data, as: UTF8.self)

        let missing = Sender.tipAccounts.filter { !page.contains($0) }

        #expect(missing.isEmpty, "Helius no longer lists these tip accounts: \(missing)")
        #expect(!Sender.tipAccounts.isEmpty)
    }
}
