import Testing
import Wallet

struct AccountDerivationTests {
    @Test
    func `Batch derivation preserves exact paths and independently derived addresses`() async throws {
        let phrase = try PublicRecovery.phrase()
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
    func `Batch derivation applies the original BIP-39 passphrase`() async throws {
        let phrase = try PublicRecovery.phrase()
        let accounts = try await Wallet().accounts(for: phrase, passphrase: "TREZOR", paths: [.solana])
        #expect(accounts.first?.address == "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe")
        #expect(try await Wallet().accounts(for: phrase, passphrase: "", paths: []).isEmpty)
    }

    @Test
    func `Cancelled batch derivation throws CancellationError`() async throws {
        let phrase = try PublicRecovery.phrase()
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
