import CryptoKit
import Foundation
import ModularArithmetic

/// The published payload of a confidential output, with its recipient's viewing public key and sealed note.
struct ConfidentialOutput: Sendable {
    /// An error that rejects bytes as a confidential output's payload.
    enum ValidationError: Error, Equatable {
        case invalidLength
        case unsupportedEncoding
        case unsupportedScheme
        case invalidRecipientKey
    }

    private static let encryptedEncoding: UInt8 = 1

    private static let confidentialScheme: UInt8 = 3

    /// The length of the encoding tag and the declared length, in bytes.
    private static let headerLength = 5

    /// The length of a compressed P-256 public key, in bytes.
    private static let publicKeyLength = 33

    /// The length of the scheme, the recipient key, and the ciphertext, in bytes.
    private static let bodyLength = 1 + publicKeyLength + ConfidentialPlaintext.length

    /// The length of a SOL output's payload, in bytes.
    static let payloadLength = headerLength + bodyLength

    let recipientViewingPublicKey: P256.KeyAgreement.PublicKey

    /// The sealed note.
    let ciphertext: [UInt8]

    var encoded: [UInt8] {
        var bytes = [Self.encryptedEncoding]
        bytes.reserveCapacity(Self.payloadLength)
        bytes.appendLittleEndian(UInt32(Self.bodyLength))
        bytes.append(Self.confidentialScheme)
        bytes += recipientViewingPublicKey.compressedRepresentation
        bytes += ciphertext
        return bytes
    }

    /// Creates a payload.
    ///
    /// - Parameters:
    ///   - recipientViewingPublicKey: The recipient's viewing public key.
    ///   - ciphertext: The sealed note.
    private init(recipientViewingPublicKey: P256.KeyAgreement.PublicKey, ciphertext: [UInt8]) {
        self.recipientViewingPublicKey = recipientViewingPublicKey
        self.ciphertext = ciphertext
    }

    /// Creates a payload by decoding an output's published bytes.
    ///
    /// - Parameter payload: The output's data slot.
    /// - Throws: ``ValidationError/invalidLength`` for another length, ``ValidationError/unsupportedEncoding``
    ///   or ``ValidationError/unsupportedScheme`` for another encoding or scheme, or
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
    ///   - recipientViewingPublicKey: The recipient's viewing public key.
    ///   - transactionViewingKey: The transaction viewing key.
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
    /// - Parameters:
    ///   - viewingKey: The account's viewing key.
    ///   - transactionViewingPublicKey: The transaction's published viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The note, or `nil` if the payload names another recipient's viewing key.
    /// - Throws: ``SlotCipher/ValidationError/invalidSaltLength`` for a salt of another length, a
    ///   ``ConfidentialPlaintext/ValidationError`` if the opened note isn't a supported note,
    ///   ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the
    ///   key agreement fails.
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

    /// Opens the note as the sender who sealed it.
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
    /// - Parameters:
    ///   - viewingKey: The account's viewing key.
    ///   - owner: The account's owner hash.
    ///   - transactionViewingPublicKey: The transaction's published viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    ///   - treeID: The ID of the output tree.
    ///   - utxoHash: The output's published UTXO hash.
    /// - Returns: The UTXO, or `nil` if the note isn't the account's or the UTXO's hash isn't `utxoHash`.
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
