import CryptoKit
@testable import Privacy
import Testing

struct SlotCipherTests {
    private let vector: EncryptionVectors.Slot

    private let ephemeralKey: Curve25519.KeyAgreement.PrivateKey

    private let recipientKey: Curve25519.KeyAgreement.PrivateKey

    init() throws {
        vector = try EncryptionVectors.load().slot
        ephemeralKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.ephemeralSecret))
        recipientKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.recipientSecret))
    }

    @Test
    func `Senders seal the published ciphertext`() throws {
        let ciphertext = try SlotCipher.applyAsSender(
            to: fixtureBytes(vector.plaintext), transactionViewingKey: ephemeralKey,
            recipientViewingPublicKey: recipientKey.publicKey, salt: fixtureBytes(vector.salt), slot: vector.slotIndex
        )

        #expect(ciphertext == (try fixtureBytes(vector.ciphertext)))
    }

    @Test
    func `Recipients open the published ciphertext`() throws {
        let plaintext = try SlotCipher.applyAsRecipient(
            to: fixtureBytes(vector.ciphertext), viewingKey: recipientKey,
            transactionViewingPublicKey: ephemeralKey.publicKey, salt: fixtureBytes(vector.salt), slot: vector.slotIndex
        )

        #expect(plaintext == (try fixtureBytes(vector.plaintext)))
    }

    @Test(arguments: [
        ("00000000000000000000000000000000", 1, "64657465726d696e6973746963", "21dcfa3f147e7867ba91a4ee4d"),
        ("00000000000000000000000000000001", 0, "64657465726d696e6973746963", "65f4823b7736cf7517c7fb7f6a"),
        ("000102030405060708090a0b0c0d0e0f", 0x0102_0304, "64657465726d696e6973746963", "9fa48be4854d638f11cad9af7e"),
        (
            "00000000000000000000000000000000", 0,
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021222324252627",
            "8ee6a9f18723bd2d894131c992110ebd7c050a2a2d94cc812efc0b98620de1a2367ea51e63c51b80"
        ),
    ] as [(String, UInt32, String, String)])
    func `Ciphertexts match independently derived values`(salt: String, slot: UInt32, plaintext: String, ciphertext: String) throws {
        let sealed = try SlotCipher.applyAsSender(
            to: fixtureBytes(plaintext), transactionViewingKey: ephemeralKey,
            recipientViewingPublicKey: recipientKey.publicKey, salt: fixtureBytes(salt), slot: slot
        )
        let opened = try SlotCipher.applyAsRecipient(
            to: sealed, viewingKey: recipientKey, transactionViewingPublicKey: ephemeralKey.publicKey,
            salt: fixtureBytes(salt), slot: slot
        )

        #expect(sealed == (try fixtureBytes(ciphertext)))
        #expect(opened == (try fixtureBytes(plaintext)))
    }

    @Test(arguments: [0, 15, 17])
    func `Salts of other lengths are rejected`(length: Int) throws {
        let plaintext = try fixtureBytes(vector.plaintext)

        #expect(throws: SlotCipher.ValidationError.invalidSaltLength) {
            try SlotCipher.applyAsSender(
                to: plaintext, transactionViewingKey: ephemeralKey, recipientViewingPublicKey: recipientKey.publicKey,
                salt: [UInt8](repeating: 0, count: length), slot: 0
            )
        }
    }

    @Test(arguments: X25519Fixtures.lowOrderCoordinates)
    func `Low-order public keys are rejected`(u: [UInt8]) throws {
        let lowOrderKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: u)
        let plaintext = try fixtureBytes(vector.plaintext)
        let salt = try fixtureBytes(vector.salt)

        #expect(throws: SlotCipher.ValidationError.lowOrderPublicKey) {
            try SlotCipher.applyAsSender(
                to: plaintext, transactionViewingKey: ephemeralKey, recipientViewingPublicKey: lowOrderKey, salt: salt, slot: 0
            )
        }
        #expect(throws: SlotCipher.ValidationError.lowOrderPublicKey) {
            try SlotCipher.applyAsRecipient(
                to: plaintext, viewingKey: recipientKey, transactionViewingPublicKey: lowOrderKey, salt: salt, slot: 0
            )
        }
    }
}
