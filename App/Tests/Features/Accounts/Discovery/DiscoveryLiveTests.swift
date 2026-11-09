import RPC
import Testing
import Wallet
@testable import widgets

@Suite(.tags(.network))
struct DiscoveryLiveTests {
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Mainnet discovery matches observed SOL balances for a public phrase`(helius: Bool) async throws {
        let transport = LiveResponses<GetMultipleAccounts>()
        let rpc = try LiveClients.client(helius: helius, transport: transport)
        let phrase = try RecoveryPhrase(PublicWallet.words)

        let accounts = try await AccountDiscovery(rpc: rpc).discover(for: phrase, passphrase: "")

        let responses = await transport.responses
        try #require(responses.count == 1)
        let observed = responses[0]
        #expect(observed.value.count == 20)
        #expect(accounts.count == observed.value.count { ($0?.lamports ?? 0) > 0 })
        #expect(Set(accounts.map(\.address)).count == accounts.count)
    }
}
