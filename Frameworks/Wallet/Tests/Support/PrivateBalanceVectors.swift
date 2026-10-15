import Testing

/// zolana's Solana Rings seed-phrase keys and derivation-input guard vectors.
///
/// `PrivateBalanceVectors.json` transcribes accounts 0 and 1 of the `GOLDEN` array in
/// `sdk-libs/ts/test/seed-based-keypair.test.ts`, and copies `derivation_input_guard` from
/// `test-vectors/key_derivation.json` unchanged, at tag v0.4.0-alpha (Apache-2.0);
/// `PrivateBalanceVectors-LICENSE.txt` records the sources. The accounts are those of
/// `PublicRecovery` with no passphrase. The fixture's cryptographic keys and messages are
/// hexadecimal.
struct PrivateBalanceVectors: Decodable, Sendable {
    /// The golden keys of accounts 0 and 1.
    let accounts: [Account]

    /// Messages and whether signing must refuse them.
    let derivationInputGuard: [GuardVector]

    /// The fixture's JSON keys.
    private enum CodingKeys: String, CodingKey {
        case accounts
        case derivationInputGuard = "derivation_input_guard"
    }

    /// The golden keys of one account index.
    struct Account: Decodable, Sendable, CustomTestStringConvertible {
        /// The account index i of `m/44'/501'/i'/0'`.
        let account: UInt32
        /// The 32-byte Ed25519 public key at `m/44'/501'/i'/0'`.
        let signingPubkey: String
        /// The 31-byte nullifier secret.
        let nullifierSecret: String
        /// The 32-byte big-endian P-256 viewing scalar.
        let viewingSecret: String
        /// The 33-byte compressed P-256 viewing public key.
        let viewingPubkey: String

        /// The account index, in test results.
        var testDescription: String { "Account \(account)" }
    }

    /// A message and whether it's a derivation input.
    struct GuardVector: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// The message bytes.
        let message: String
        /// Whether signing must refuse the message.
        let isDerivationInput: Bool

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case name, message
            case isDerivationInput = "is_derivation_input"
        }

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The golden accounts and guard vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "PrivateBalanceVectors")
    }
}
