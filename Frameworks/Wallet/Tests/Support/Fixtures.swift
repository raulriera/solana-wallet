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
