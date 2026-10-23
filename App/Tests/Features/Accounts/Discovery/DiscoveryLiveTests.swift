import RPC
import Testing
import Wallet
@testable import widgets

/// Checks discovery against real mainnet observations using published recovery input.
@Suite(.tags(.network))
struct DiscoveryLiveTests {
    /// Compares discovery with the balances returned by its single live lookup: one twenty-address
    /// request, and one distinct account for each funded address in it.
    ///
    /// The public fixture may have any balance; this test never accesses Vault or requests funding.
    /// - Parameter helius: Whether to query Helius or the public Solana endpoint.
    /// - Throws: A derivation, provider, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Mainnet discovery matches observed SOL balances for a public phrase`(helius: Bool) async throws {
        let transport = LiveResponses<GetMultipleAccounts>()
        let rpc = try LiveClients.client(helius: helius, transport: transport)
        let phrase = try RecoveryPhrase(PublicWallet.words)

        let accounts = try await AccountDiscovery(rpc: rpc).discover(for: phrase, passphrase: "")

        let responses = await transport.responses
        try #require(responses.count == 1)
        let observed = try #require(responses.first)
        #expect(observed.value.count == 20)
        #expect(accounts.count == observed.value.filter { ($0?.lamports ?? 0) > 0 }.count)
        #expect(Set(accounts.map(\.address)).count == accounts.count)
    }
}
