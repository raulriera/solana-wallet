import CommonCrypto
import CryptoKit
import Foundation

/// The cipher of one output slot's note: P-256 ECDH, HKDF-SHA256, and AES-256-CTR, as zolana's
/// `applyTransferCipher` applies it.
///
/// - The shared secret is the x-coordinate of the ECDH point of one party's secret and the other
///   party's public key.
/// - The key material is `shared ‖ ephemeral public key ‖ recipient public key`, both keys SEC1
///   compressed; the ephemeral key is the transaction viewing key.
/// - `HKDF(salt: empty, key material, "TSPP/hpke/" ‖ "TSPP/tx" ‖ salt ‖ slot, 44)`, with the slot as
///   a big-endian 32-bit integer, gives the 32-byte AES key and a 12-byte nonce.
/// - The AES-256-CTR counter block starts at `nonce ‖ 00 00 00 02`, as in AES-GCM, and increments
///   as a big-endian 128-bit integer. A counter that started at 1 would give another ciphertext.
///
/// CTR mode XORs the input with a key stream, so encryption and decryption are the same operation,
/// for an input of any length. The slot binds each note to its output, so no key and nonce repeat
/// within a transaction. The buffers that hold the key material and the counter block are zeroed
/// before they're released. CryptoKit holds the shared secret and the derived key and nonce, and
/// CommonCrypto holds its copy of the key until the cryptor is released.
enum SlotCipher {
    /// A salt that can't key a slot.
    enum ValidationError: Error, Equatable {
        /// A transaction's salt has exactly 16 bytes.
        case invalidSaltLength
    }

    /// A failure of the platform cipher.
    enum CipherError: Error, Equatable {
        /// CommonCrypto couldn't apply AES-256-CTR.
        case cryptorFailed
    }

    /// The number of bytes in a transaction's salt.
    static let saltLength = 16

    /// The HKDF info that precedes the salt and slot, `TSPP/hpke/` followed by the transfer label
    /// `TSPP/tx`.
    private static let infoPrefix = Array("TSPP/hpke/TSPP/tx".utf8)

    /// The number of bytes in the AES-256 key, which precedes the nonce in the HKDF output.
    private static let keyLength = kCCKeySizeAES256

    /// The number of bytes in the HKDF output: the key and a 12-byte nonce.
    private static let keyAndNonceLength = keyLength + 12

    /// The last byte of the initial counter block, whose last four bytes are `00 00 00 02`.
    private static let initialCounter: UInt8 = 2

    /// Applies a slot's cipher as the transaction's sender, who seals each output's note.
    ///
    /// Applying it to a ciphertext opens a note that the sender sealed, as zolana's
    /// `decryptSlotEphemeral` does.
    ///
    /// - Parameters:
    ///   - input: The plaintext or the ciphertext.
    ///   - transactionViewingKey: The transaction viewing key, the ephemeral key.
    ///   - recipientViewingPublicKey: The output recipient's viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The ciphertext or the plaintext, as long as `input`.
    /// - Throws: ``ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the key
    ///   agreement fails.
    static func applyAsSender(
        to input: [UInt8],
        transactionViewingKey: P256.KeyAgreement.PrivateKey,
        recipientViewingPublicKey: P256.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> [UInt8] {
        try apply(
            to: input, secret: transactionViewingKey, counterparty: recipientViewingPublicKey,
            ephemeralPublicKey: transactionViewingKey.publicKey, recipientPublicKey: recipientViewingPublicKey,
            salt: salt, slot: slot
        )
    }

    /// Applies a slot's cipher as the output's recipient, who opens its note.
    ///
    /// - Parameters:
    ///   - input: The ciphertext or the plaintext.
    ///   - viewingKey: The recipient account's viewing key.
    ///   - transactionViewingPublicKey: The transaction's published viewing public key.
    ///   - salt: The transaction's 16-byte salt.
    ///   - slot: The output's position in the transaction.
    /// - Returns: The plaintext or the ciphertext, as long as `input`.
    /// - Throws: ``ValidationError/invalidSaltLength`` for a salt of another length,
    ///   ``CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the key
    ///   agreement fails.
    static func applyAsRecipient(
        to input: [UInt8],
        viewingKey: P256.KeyAgreement.PrivateKey,
        transactionViewingPublicKey: P256.KeyAgreement.PublicKey,
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
    ///   ``CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit error if the key
    ///   agreement fails.
    private static func apply(
        to input: [UInt8],
        secret: P256.KeyAgreement.PrivateKey,
        counterparty: P256.KeyAgreement.PublicKey,
        ephemeralPublicKey: P256.KeyAgreement.PublicKey,
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        salt: [UInt8],
        slot: UInt32
    ) throws -> [UInt8] {
        guard salt.count == saltLength else { throw ValidationError.invalidSaltLength }
        let shared = try secret.sharedSecretFromKeyAgreement(with: counterparty)
        let ephemeral = ephemeralPublicKey.compressedRepresentation
        let recipient = recipientPublicKey.compressedRepresentation
        var keyMaterial = [UInt8]()
        // Reserving the whole length keeps appends from leaving unerased copies behind.
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
    /// - Returns: The input XORed with the key stream of the counter blocks from
    ///   `nonce ‖ 00 00 00 02`.
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
