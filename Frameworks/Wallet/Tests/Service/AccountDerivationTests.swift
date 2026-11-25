import Testing
import Wallet

struct AccountDerivationTests {
    @Test
    func `Batch derivation preserves exact paths and independently derived addresses`() async throws {
        let phrase = try ThrowawayWallet.phrase()
        let paths = try ["m/44'/501'/1'/0'", "m/44'/501'/0'", "m/44'/501'/0'/0'", "m/44'/501'/0'"]
            .map(DerivationPath.init)
        let wallet: any WalletProviding = Wallet()

        let accounts = try await wallet.accounts(for: phrase, passphrase: "", paths: paths)

        #expect(accounts.map(\.path) == paths)
        #expect(accounts.map(\.address) == [
            "Hh8QwFUA6MtVu1qAoq12ucvFHNwCcVTV7hpWjeY1Hztb", "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL",
            "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk", "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL",
        ])
    }

    @Test
    func `Cancelled batch derivation throws CancellationError`() async throws {
        let phrase = try ThrowawayWallet.phrase()
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task { @concurrent in
            for await _ in gate {}
            return try await Wallet().accounts(for: phrase, passphrase: "", paths: [.solana])
        }
        task.cancel()
        continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
