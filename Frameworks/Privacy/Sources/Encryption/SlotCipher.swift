import CommonCrypto
import CryptoKit
import Foundation

/// The cipher of one output slot's note, with P-256 ECDH, HKDF-SHA256, and AES-256-CTR.
enum SlotCipher {
    /// An error that rejects a salt.
    enum ValidationError: Error, Equatable {
        case invalidSaltLength
        /// The other party's public key has low order.
        case lowOrderPublicKey
    }

    /// An error from the platform cipher.
    enum CipherError: Error, Equatable {
        case cryptorFailed
    }

    /// The length of a transaction's salt, in bytes.
    static let saltLength = 16

    /// The HKDF info that precedes the salt and the slot.
    private static let infoPrefix = Array("TSPP/hpke/TSPP/tx".utf8)

    /// The length of the AES-256 key, in bytes.
    private static let keyLength = kCCKeySizeAES256

    /// The length of the key and the 12-byte nonce, in bytes.
    private static let keyAndNonceLength = keyLength + 12

    /// The last byte of the initial counter block.
    private static let initialCounter: UInt8 = 2

    /// Applies a slot's cipher as the transaction's sender.
    ///
    /// - Parameters:
    ///   - input: The plaintext or the ciphertext.
    ///   - transactionViewingKey: The transaction viewing key.
    ///   - recipientViewingPublicKey: The output recipient's viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The ciphertext or the plaintext.
    /// - Throws: ``ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``ValidationError/lowOrderPublicKey`` for a low-order public key of the other party, or
    ///   ``CipherError/cryptorFailed`` if CommonCrypto fails.
    static func applyAsSender(
        to input: [UInt8],
        transactionViewingKey: Curve25519.KeyAgreement.PrivateKey,
        recipientViewingPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> [UInt8] {
        try apply(
            to: input, secret: transactionViewingKey, counterparty: recipientViewingPublicKey,
            ephemeralPublicKey: transactionViewingKey.publicKey, recipientPublicKey: recipientViewingPublicKey,
            salt: salt, slot: slot
        )
    }

    /// Applies a slot's cipher as the output's recipient.
    ///
    /// - Parameters:
    ///   - input: The ciphertext or the plaintext.
    ///   - viewingKey: The recipient account's viewing key.
    ///   - transactionViewingPublicKey: The transaction's published viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The plaintext or the ciphertext.
    /// - Throws: ``ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``ValidationError/lowOrderPublicKey`` for a low-order public key of the other party, or
    ///   ``CipherError/cryptorFailed`` if CommonCrypto fails.
    static func applyAsRecipient(
        to input: [UInt8],
        viewingKey: Curve25519.KeyAgreement.PrivateKey,
        transactionViewingPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> [UInt8] {
        try apply(
            to: input, secret: viewingKey, counterparty: transactionViewingPublicKey,
            ephemeralPublicKey: transactionViewingPublicKey, recipientPublicKey: viewingKey.publicKey,
            salt: salt, slot: slot
        )
    }

    /// Derives a slot's key and nonce and applies AES-256-CTR.
    ///
    /// - Parameters:
    ///   - input: The plaintext or the ciphertext.
    ///   - secret: This party's private key.
    ///   - counterparty: The other party's public key.
    ///   - ephemeralPublicKey: The transaction viewing public key.
    ///   - recipientPublicKey: The recipient's viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The input XORed with the slot's key stream.
    /// - Throws: ``ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``ValidationError/lowOrderPublicKey`` for a low-order public key of the other party, or
    ///   ``CipherError/cryptorFailed`` if CommonCrypto fails.
    private static func apply(
        to input: [UInt8],
        secret: Curve25519.KeyAgreement.PrivateKey,
        counterparty: Curve25519.KeyAgreement.PublicKey,
        ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> [UInt8] {
        guard salt.count == saltLength else { throw ValidationError.invalidSaltLength }
        guard let shared = try? secret.sharedSecretFromKeyAgreement(with: counterparty) else {
            throw ValidationError.lowOrderPublicKey
        }
        let ephemeral = ephemeralPublicKey.taggedRepresentation
        let recipient = recipientPublicKey.taggedRepresentation
        var keyMaterial = [UInt8]()
        keyMaterial.reserveCapacity(shared.withUnsafeBytes(\.count) + ephemeral.count + recipient.count)
        defer { keyMaterial.erase() }
        shared.withUnsafeBytes { keyMaterial.append(contentsOf: $0) }
        keyMaterial.append(contentsOf: ephemeral)
        keyMaterial.append(contentsOf: recipient)
        let info = infoPrefix + salt + Swift.withUnsafeBytes(of: slot.bigEndian, Array.init)
        let keyAndNonce = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyMaterial), info: info, outputByteCount: keyAndNonceLength
        )
        return try counterMode(input, keyAndNonce: keyAndNonce)
    }

    /// Applies AES-256-CTR with CommonCrypto.
    ///
    /// - Parameters:
    ///   - input: The bytes to XOR with the key stream.
    ///   - keyAndNonce: The 32-byte key followed by the 12-byte nonce.
    /// - Returns: The input XORed with the key stream.
    /// - Throws: ``CipherError/cryptorFailed`` if CommonCrypto fails or doesn't process every byte.
    private static func counterMode(_ input: [UInt8], keyAndNonce: SymmetricKey) throws -> [UInt8] {
        try keyAndNonce.withUnsafeBytes { keyAndNonce in
            var counterBlock = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
            defer { counterBlock.erase() }
            counterBlock.withUnsafeMutableBytes { block in
                block.copyMemory(from: UnsafeRawBufferPointer(rebasing: keyAndNonce[keyLength...]))
            }
            counterBlock[kCCBlockSizeAES128 - 1] = initialCounter
            var cryptor: CCCryptorRef?
            let created = CCCryptorCreateWithMode(
                CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                counterBlock, keyAndNonce.baseAddress, keyLength, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor
            )
            guard created == CCCryptorStatus(kCCSuccess), let cryptor else { throw CipherError.cryptorFailed }
            var output = [UInt8](repeating: 0, count: input.count)
            var written = 0
            let updated = CCCryptorUpdate(cryptor, input, input.count, &output, input.count, &written)
            let released = CCCryptorRelease(cryptor)
            guard updated == CCCryptorStatus(kCCSuccess), released == CCCryptorStatus(kCCSuccess), written == input.count else {
                throw CipherError.cryptorFailed
            }
            return output
        }
    }
}
