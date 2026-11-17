import Testing
import Wallet

struct WalletTests {
    @Test(arguments: [
        ("m/44'/501'/0'/0'", "", "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"),
        ("m/44'/501'/1'/0'", "", "Hh8QwFUA6MtVu1qAoq12ucvFHNwCcVTV7hpWjeY1Hztb"),
        ("m/44'/501'/0'", "", "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL"),
        ("m/44'/501'/0'/0'", "TREZOR", "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"),
    ])
    func `Imported recovery phrases derive expected Solana addresses`(path: String, passphrase: String, expected: String) async throws {
        let wallet: any WalletProviding = Wallet()
        let phrase = try RecoveryPhrase("  " + Array(repeating: "ABANDON", count: 11).joined(separator: " \n\t") + " ABOUT  ")

        let accounts = try await wallet.accounts(for: phrase, passphrase: passphrase, paths: [DerivationPath(path)])

        #expect(accounts.map(\.address) == [expected])
    }
}
