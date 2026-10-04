import RPC
import Testing
import Wallet
@testable import widgets

/// Checks discovery against real mainnet observations using published recovery input.
struct DiscoveryLiveTests {
    /// Compares ordered discovery with the balances returned by its single live lookup.
    ///
    /// The public fixture may have any balance; this test never accesses Vault or requests funding.
    /// - Parameter helius: Whether to query Helius or the public Solana endpoint.
    /// - Throws: A derivation, provider, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Mainnet discovery matches observed SOL balances for a public phrase`(helius: Bool) async throws {
        let transport = LiveResponses<GetMultipleAccounts>()
        let rpc = try MainnetClients.client(helius: helius, transport: transport)
        let phrase = try RecoveryPhrase(PublicWallet.words)
        let paths = try (0..<10).flatMap { index in
            try [DerivationPath("m/44'/501'/\(index)'/0'"), DerivationPath("m/44'/501'/\(index)'")]
        }
        let candidates = try await Wallet().accounts(for: phrase, passphrase: "", paths: paths)
        let result = try await AccountDiscovery(rpc: rpc).discover(for: phrase)
        let responses = await transport.responses
        try #require(responses.count == 1)
        let observed = try #require(responses.first)
        try #require(observed.value.count == candidates.count)
        let expected = zip(candidates, observed.value).compactMap { candidate, account in
            (account?.lamports ?? 0) > 0 ? candidate : nil
        }

        #expect(result.network == .mainnet)
        #expect(result.indices == 0..<10)
        #expect(result.nextIndices == 10..<20)
        #expect(result.accounts == expected)
    }
}
