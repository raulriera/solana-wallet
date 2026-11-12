import Foundation
import Testing
@testable import RPC

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct SenderTipAccountsLiveTests {
    @Test
    func `Bundled Sender tip accounts match the published list`() async throws {
        let url = try #require(URL(string: "https://www.helius.dev/docs/sending-transactions/sender.md"))
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        try #require((response as? HTTPURLResponse)?.statusCode == 200)
        let page = String(decoding: data, as: UTF8.self)

        let missing = SenderSubmissionProvider.tipAccounts.filter { !page.contains($0) }

        #expect(missing.isEmpty, "Helius no longer lists these tip accounts: \(missing)")
        #expect(!SenderSubmissionProvider.tipAccounts.isEmpty)
    }
}
