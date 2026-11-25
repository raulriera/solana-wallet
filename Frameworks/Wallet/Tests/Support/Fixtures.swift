import Wallet

struct BIP39Vector: Decodable, Sendable {
    let entropy: String
    let phrase: String
    let seed: String

    static func examples() throws -> [Self] {
        try fixture(named: "BIP39")
    }
}

enum ThrowawayWallet {
    static let addresses = [
        "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk", "Hh8QwFUA6MtVu1qAoq12ucvFHNwCcVTV7hpWjeY1Hztb",
    ]

    static func phrase() throws -> RecoveryPhrase {
        try RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about")
    }
}
