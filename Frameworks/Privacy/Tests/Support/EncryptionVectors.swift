import Testing

/// zolana's Solana Rings encryption vectors.
///
/// `EncryptionVectors.json` copies, unchanged at tag v0.4.0-alpha (Apache-2.0), the `tx_viewing`
/// and `hpke_utxo` sections of `test-vectors/key_derivation.json`.
/// `EncryptionVectors-LICENSE.txt` records the source and its digest. Byte strings are hexadecimal;
/// the slot is a JSON number.
struct EncryptionVectors: Decodable, Sendable {
    /// The transaction viewing key of one account and first nullifier.
    let transactionViewing: TransactionViewing

    /// One slot that an ephemeral key seals for a recipient.
    let slot: Slot

    /// The fixture's JSON keys.
    private enum CodingKeys: String, CodingKey {
        case transactionViewing = "tx_viewing"
        case slot = "hpke_utxo"
    }

    /// An account's viewing secret, a first nullifier, and the transaction viewing key they derive.
    struct TransactionViewing: Decodable, Sendable {
        /// The account's 32-byte P-256 viewing secret.
        let viewingSecret: String
        /// The transaction's 32-byte first nullifier.
        let firstNullifier: String
        /// The 32-byte scalar of the transaction viewing key.
        let transactionViewingScalar: String
        /// The transaction viewing key's SEC1 compressed public key.
        let transactionViewingPublicKey: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case viewingSecret = "viewing_secret"
            case firstNullifier = "first_nullifier"
            case transactionViewingScalar = "tx_viewing_secret"
            case transactionViewingPublicKey = "tx_viewing_pubkey"
        }
    }

    /// The keys, salt, and slot of one sealed plaintext.
    struct Slot: Decodable, Sendable {
        /// The recipient's 32-byte P-256 viewing secret.
        let recipientSecret: String
        /// The 32-byte scalar of the ephemeral key, which plays the transaction viewing key.
        let ephemeralSecret: String
        /// The transaction's 16-byte salt.
        let salt: String
        /// The output's position in the transaction.
        let slotIndex: UInt32
        /// The plaintext.
        let plaintext: String
        /// The ciphertext, as long as the plaintext.
        let ciphertext: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case recipientSecret = "recipient_secret"
            case ephemeralSecret = "ephemeral_secret"
            case salt
            case slotIndex = "slot_index"
            case plaintext, ciphertext
        }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The encryption vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "EncryptionVectors")
    }
}
