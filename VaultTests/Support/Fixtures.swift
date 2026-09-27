import Vault
import Wallet

/// Public recovery material used exclusively for offline tests.
enum Fixtures {
    /// Creates a published BIP-39 example with a significant passphrase and nondefault path.
    /// - Returns: Recovery material that must never hold funds.
    /// - Throws: An error if the fixture's phrase or path is invalid.
    static func recovery() throws -> Recovery {
        try Recovery(
            phrase: RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"),
            passphrase: " TREZOR ", path: DerivationPath("m/44'/501'/1'/0'")
        )
    }
}
