import Testing
import Wallet

/// Verifies private-balance keys from outside the framework's access boundary.
struct PrivateBalanceKeysTests {
    /// Verifies that printing, dumping, and reflecting the keys omit both secrets.
    @Test
    func `Private-balance key diagnostics omit the secrets`() async throws {
        let keys = try await Wallet().privateBalanceKeys(
            using: PublicRecovery.phrase(), expectedAddress: PublicRecovery.addresses[0],
            passphrase: "", path: .solana
        )
        var output = ""
        dump(keys, to: &output)

        #expect(keys.description == "PrivateBalanceKeys")
        #expect(keys.debugDescription == "PrivateBalanceKeys")
        #expect(String(reflecting: keys) == "PrivateBalanceKeys")
        #expect(output == "- PrivateBalanceKeys\n")
        #expect(Mirror(reflecting: keys).children.isEmpty)
    }
}
