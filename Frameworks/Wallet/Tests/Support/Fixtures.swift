import Wallet

/// Public BIP-39 reference data; none of these phrases may secure real funds.
struct BIP39Vector: Decodable, Sendable {
    let entropy: String
    let phrase: String
    let seed: String

    /// Reads published English vectors and two supplemental standard phrase lengths.
    ///
    /// The first 24 records come from Trezor's python-mnemonic vectors.json (MIT).
    /// The last two use zero entropy and Python hashlib for the 15- and 21-word cases.
    ///
    /// - Returns: Entropy, phrase, and seed examples using the passphrase `TREZOR`.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func examples() throws -> [Self] {
        try fixture(named: "BIP39")
    }
}

/// The public BIP-39 zero-entropy phrase `abandon` × 11 + `about` and its first Solana accounts;
/// it must never hold real funds.
enum PublicRecovery {
    /// The phrase's addresses at `m/44'/501'/i'/0'` with no passphrase, by account index i.
    static let addresses = [
        "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk", "Hh8QwFUA6MtVu1qAoq12ucvFHNwCcVTV7hpWjeY1Hztb",
    ]

    /// Restores the public phrase.
    ///
    /// - Returns: A public twelve-word fixture that must never hold real funds.
    /// - Throws: An error if the fixture violates BIP-39.
    static func phrase() throws -> RecoveryPhrase {
        try RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about")
    }
}
