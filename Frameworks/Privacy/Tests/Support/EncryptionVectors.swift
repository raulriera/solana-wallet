import Testing

struct EncryptionVectors: Decodable, Sendable {
    let transactionViewing: TransactionViewing

    let slot: Slot

    private enum CodingKeys: String, CodingKey {
        case transactionViewing = "tx_viewing"
        case slot = "hpke_utxo"
    }

    struct TransactionViewing: Decodable, Sendable {
        let viewingSecret: String
        let firstNullifier: String
        let transactionViewingScalar: String
        let transactionViewingPublicKey: String

        private enum CodingKeys: String, CodingKey {
            case viewingSecret = "viewing_secret"
            case firstNullifier = "first_nullifier"
            case transactionViewingScalar = "tx_viewing_secret"
            case transactionViewingPublicKey = "tx_viewing_pubkey"
        }
    }

    struct Slot: Decodable, Sendable {
        let recipientSecret: String
        let ephemeralSecret: String
        let salt: String
        let slotIndex: UInt32
        let plaintext: String
        let ciphertext: String

        private enum CodingKeys: String, CodingKey {
            case recipientSecret = "recipient_secret"
            case ephemeralSecret = "ephemeral_secret"
            case salt
            case slotIndex = "slot_index"
            case plaintext, ciphertext
        }
    }

    static func load() throws -> Self {
        try fixture(named: "EncryptionVectors")
    }
}
