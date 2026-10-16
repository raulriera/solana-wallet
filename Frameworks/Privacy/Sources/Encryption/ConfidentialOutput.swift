import CryptoKit
import Foundation
import ModularArithmetic

/// The published payload of a confidential default-ring output: its recipient's viewing public key
/// and its sealed note.
///
/// The payload fills a transact output's data slot, as zolana's `encodeOutputData` and
/// `encryptConfidential` write it: the encoding tag 1, encrypted; the length of the rest as a
/// little-endian 32-bit integer; the scheme 3, confidential; the recipient's SEC1 compressed viewing
/// public key; and the ``SlotCipher`` ciphertext of the 50-byte ``ConfidentialPlaintext``. That's
/// 89 bytes for a SOL output. The transaction publishes its viewing public key and 16-byte salt once
/// for all of its outputs, and each output's slot is its position in the transaction.
struct ConfidentialOutput: Sendable {
    /// Bytes that aren't a supported payload.
    enum ValidationError: Error, Equatable {
        /// The payload's length, or the length that it declares, isn't a confidential SOL output's.
        case invalidLength
        /// The payload's encoding tag isn't 1, encrypted.
        case unsupportedEncoding
        /// The payload's scheme isn't 3, confidential.
        case unsupportedScheme
        /// The embedded recipient key isn't a SEC1 compressed P-256 point.
        case invalidRecipientKey
    }

    /// The encoding tag of an encrypted payload.
    private static let encryptedEncoding: UInt8 = 1

    /// The scheme of a confidential output.
    private static let confidentialScheme: UInt8 = 3

    /// The number of bytes before the scheme: the encoding tag and the declared length.
    private static let headerLength = 5

    /// The number of bytes in a SEC1 compressed P-256 public key.
    private static let publicKeyLength = 33

    /// The number of bytes after the header: the scheme, the recipient key, and the ciphertext.
    private static let bodyLength = 1 + publicKeyLength + ConfidentialPlaintext.length

    /// The number of bytes in a confidential SOL output's payload.
    static let payloadLength = headerLength + bodyLength

    /// The recipient's viewing public key, which the payload names in the clear.
    let recipientViewingPublicKey: P256.KeyAgreement.PublicKey

    /// The sealed note.
    let ciphertext: [UInt8]

    /// The 89-byte payload.
    var encoded: [UInt8] {
        var bytes = [Self.encryptedEncoding]
        bytes.reserveCapacity(Self.payloadLength)
        bytes.appendLittleEndian(UInt32(Self.bodyLength))
        bytes.append(Self.confidentialScheme)
        bytes += recipientViewingPublicKey.compressedRepresentation
        bytes += ciphertext
        return bytes
    }

    /// Creates a payload from its parts.
    ///
    /// - Parameters:
    ///   - recipientViewingPublicKey: The recipient's viewing public key.
    ///   - ciphertext: The sealed 50-byte note.
    private init(recipientViewingPublicKey: P256.KeyAgreement.PublicKey, ciphertext: [UInt8]) {
        self.recipientViewingPublicKey = recipientViewingPublicKey
        self.ciphertext = ciphertext
    }

    /// Decodes a published payload.
    ///
    /// - Parameter payload: The output's data slot.
    /// - Throws: ``ValidationError/invalidLength`` if the payload or its declared length isn't a
    ///   confidential SOL output's, ``ValidationError/unsupportedEncoding`` for an encoding tag other
    ///   than 1, ``ValidationError/unsupportedScheme`` for a scheme other than 3, or
    ///   ``ValidationError/invalidRecipientKey`` if the recipient key isn't a compressed P-256 point.
    init(decoding payload: [UInt8]) throws {
        guard payload.count > Self.headerLength else { throw ValidationError.invalidLength }
        guard payload[0] == Self.encryptedEncoding else { throw ValidationError.unsupportedEncoding }
        let declaredLength: UInt32 = payload.littleEndian(at: 1)
        guard Int(declaredLength) == payload.count - Self.headerLength else { throw ValidationError.invalidLength }
        guard payload[Self.headerLength] == Self.confidentialScheme else { throw ValidationError.unsupportedScheme }
        guard payload.count == Self.payloadLength else { throw ValidationError.invalidLength }
        let keyStart = Self.headerLength + 1
        do {
            recipientViewingPublicKey = try P256.KeyAgreement.PublicKey(
                compressedRepresentation: payload[keyStart..<keyStart + Self.publicKeyLength]
            )
        } catch {
            throw ValidationError.invalidRecipientKey
        }
        ciphertext = Array(payload[(keyStart + Self.publicKeyLength)...])
    }

    /// Seals a note for an output's recipient.
    ///
    /// - Parameters:
    ///   - plaintext: The output's note.
    ///   - recipientViewingPublicKey: The recipient's viewing public key, from their shielded address.
    ///   - transactionViewingKey: The transaction viewing key, from ``TransactionViewingKey``.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The output's payload.
    /// - Throws: ``SlotCipher/ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the
    ///   key agreement fails.
    static func seal(
        _ plaintext: ConfidentialPlaintext,
        for recipientViewingPublicKey: P256.KeyAgreement.PublicKey,
        transactionViewingKey: P256.KeyAgreement.PrivateKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> Self {
        let ciphertext = try SlotCipher.applyAsSender(
            to: plaintext.encoded, transactionViewingKey: transactionViewingKey,
            recipientViewingPublicKey: recipientViewingPublicKey, salt: salt, slot: slot
        )
        return Self(recipientViewingPublicKey: recipientViewingPublicKey, ciphertext: ciphertext)
    }

    /// Opens the note as its recipient.
    ///
    /// The account opens only payloads that name its viewing key. zolana's sync ignores the named
    /// key, which its senders always set to the recipient key that the cipher used.
    ///
    /// - Parameters:
    ///   - viewingKey: The account's viewing key.
    ///   - transactionViewingPublicKey: The transaction's published viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The note, or `nil` if the payload names another recipient's viewing key.
    /// - Throws: ``SlotCipher/ValidationError/invalidSaltLength`` for a salt of another length, a
    ///   ``ConfidentialPlaintext/ValidationError`` if the opened note isn't a supported note, which
    ///   the wrong transaction key, salt, or slot also causes, ``SlotCipher/CipherError/cryptorFailed``
    ///   if CommonCrypto fails, or a CryptoKit error if the key agreement fails.
    func openAsRecipient(
        viewingKey: P256.KeyAgreement.PrivateKey,
        transactionViewingPublicKey: P256.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> ConfidentialPlaintext? {
        guard recipientViewingPublicKey.compressedRepresentation == viewingKey.publicKey.compressedRepresentation else { return nil }
        return try ConfidentialPlaintext(decoding: SlotCipher.applyAsRecipient(
            to: ciphertext, viewingKey: viewingKey, transactionViewingPublicKey: transactionViewingPublicKey,
            salt: salt, slot: slot
        ))
    }

    /// Opens the note as the sender who sealed it, under the recipient key that the payload names.
    ///
    /// - Parameters:
    ///   - transactionViewingKey: The transaction viewing key that sealed the note.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The note.
    /// - Throws: ``SlotCipher/ValidationError/invalidSaltLength`` for a salt of another length, a
    ///   ``ConfidentialPlaintext/ValidationError`` if the opened note isn't a supported note,
    ///   ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the
    ///   key agreement fails.
    func openAsSender(transactionViewingKey: P256.KeyAgreement.PrivateKey, salt: [UInt8], slot: UInt32) throws -> ConfidentialPlaintext {
        try ConfidentialPlaintext(decoding: SlotCipher.applyAsSender(
            to: ciphertext, transactionViewingKey: transactionViewingKey,
            recipientViewingPublicKey: recipientViewingPublicKey, salt: salt, slot: slot
        ))
    }

    /// Receives the output's UTXO if it belongs to an account.
    ///
    /// The account opens the note and rebuilds the UTXO with its own owner hash and the output's
    /// tree. The UTXO is the account's only if the note is a supported note and the UTXO's hash is
    /// the one that the output published. Anyone can name the account's viewing key, so a note that
    /// doesn't decode isn't an error.
    ///
    /// - Parameters:
    ///   - viewingKey: The account's viewing key.
    ///   - owner: The account's owner hash, from ``OwnerIdentity/ownerHash(signingPublicKey:nullifierPublicKey:)``.
    ///   - transactionViewingPublicKey: The transaction's published viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    ///   - treeID: The ID of the output tree.
    ///   - utxoHash: The output's published UTXO hash.
    /// - Returns: The UTXO, or `nil` if the payload names another recipient, the opened note isn't a
    ///   supported note, or the rebuilt UTXO's hash differs from `utxoHash`.
    /// - Throws: ``SlotCipher/ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the
    ///   key agreement fails.
    func receive(
        viewingKey: P256.KeyAgreement.PrivateKey,
        owner: Poseidon.Element,
        transactionViewingPublicKey: P256.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32,
        treeID: UInt16,
        utxoHash: Poseidon.Element
    ) throws -> UTXO? {
        let opened: ConfidentialPlaintext?
        do {
            opened = try openAsRecipient(viewingKey: viewingKey, transactionViewingPublicKey: transactionViewingPublicKey, salt: salt, slot: slot)
        } catch is ConfidentialPlaintext.ValidationError {
            return nil
        }
        guard let plaintext = opened else { return nil }
        let utxo = UTXO(owner: owner, mint: plaintext.asset.mint, amount: plaintext.amount, blinding: plaintext.blinding, treeID: treeID)
        return utxo.hash == utxoHash ? utxo : nil
    }
}
