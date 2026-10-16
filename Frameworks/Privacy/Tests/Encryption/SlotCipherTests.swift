import CryptoKit
@testable import Privacy
import Testing

/// Verifies the slot cipher against zolana's published vector and independently derived values.
///
/// The vector seals 13 bytes from the ephemeral secret 1 to the recipient secret 2, with a zero
/// salt in slot 0. Its counter block starts at `nonce ‖ 00 00 00 02`; one that started at
/// `nonce ‖ 00 00 00 01` wouldn't reproduce the published ciphertext.
struct SlotCipherTests {
    /// The published slot vector.
    private let vector: EncryptionVectors.Slot

    /// The vector's ephemeral key, which plays the transaction viewing key.
    private let ephemeralKey: P256.KeyAgreement.PrivateKey

    /// The vector's recipient viewing key.
    private let recipientKey: P256.KeyAgreement.PrivateKey

    /// Reads the published slot vector and creates its keys.
    ///
    /// - Throws: A test failure if the fixture is missing or malformed, or an error if it can't be
    ///   read or decoded, or if a secret isn't a P-256 private key.
    init() throws {
        vector = try EncryptionVectors.load().slot
        ephemeralKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.ephemeralSecret))
        recipientKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.recipientSecret))
    }

    /// Verifies that the sender seals the published ciphertext.
    @Test
    func `Senders seal the published ciphertext`() throws {
        let ciphertext = try SlotCipher.applyAsSender(
            to: fixtureBytes(vector.plaintext), transactionViewingKey: ephemeralKey,
            recipientViewingPublicKey: recipientKey.publicKey, salt: fixtureBytes(vector.salt), slot: vector.slotIndex
        )

        #expect(ciphertext == (try fixtureBytes(vector.ciphertext)))
    }

    /// Verifies that the recipient opens the published ciphertext.
    @Test
    func `Recipients open the published ciphertext`() throws {
        let plaintext = try SlotCipher.applyAsRecipient(
            to: fixtureBytes(vector.ciphertext), viewingKey: recipientKey,
            transactionViewingPublicKey: ephemeralKey.publicKey, salt: fixtureBytes(vector.salt), slot: vector.slotIndex
        )

        #expect(plaintext == (try fixtureBytes(vector.plaintext)))
    }

    /// Verifies other salts, slots, and lengths against independently derived ciphertexts, both
    /// ways.
    ///
    /// The expected values come from a separate Python implementation of P-256 and HKDF, with
    /// LibreSSL's AES-256-CTR. Each case uses the vector's keys. The first three change the slot, the
    /// salt, or both, so each ciphertext differs from the vector's; slot 0x01020304 checks the slot's
    /// byte order. The last case seals 40 bytes, so the counter advances past two full blocks.
    ///
    /// - Parameters:
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    ///   - plaintext: The plaintext.
    ///   - ciphertext: The expected ciphertext.
    @Test(arguments: [
        ("00000000000000000000000000000000", 1, "64657465726d696e6973746963", "bde319ba3b1958c3967f108c23"),
        ("00000000000000000000000000000001", 0, "64657465726d696e6973746963", "e7e50cdd7978272d46238ffdec"),
        ("000102030405060708090a0b0c0d0e0f", 0x0102_0304, "64657465726d696e6973746963", "18ad793d17684c75ac83f44ced"),
        (
            "00000000000000000000000000000000", 0,
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021222324252627",
            "6989809d6a440b9c1b4b0a6ae8a7adb00a590a45e386fbad8711ffb9a910ee5d5f138f63974e68cd"
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

    /// Verifies that salts of other lengths than 16 bytes are rejected.
    ///
    /// - Parameter length: A salt length in bytes: none, one fewer, or one more.
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
}
