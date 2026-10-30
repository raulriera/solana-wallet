import CryptoKit
import Transactions

/// The public part of a transact that its proof commits to, and its hash.
struct ExternalData: Sendable {
    /// A withdrawal of SOL from the shielded pool to a public account.
    struct Withdrawal: Sendable, Equatable {
        let recipient: Address
        let lamports: UInt64
    }

    private static let noExpiry = UInt64.max

    private static let solWithdrawalVariant: UInt8 = 1

    /// The encoded prefix of the transact instruction's data, after its tag.
    let encoded: [UInt8]

    /// The 32-byte external data hash, whose first byte is zero.
    let hash: [UInt8]

    /// Creates the external data by encoding and hashing the public part of a transact.
    ///
    /// - Parameters:
    ///   - transactionViewingPublicKey: The public key of the transaction viewing key that sealed
    ///     the outputs' notes.
    ///   - salt: The 16-byte salt of the outputs' notes.
    ///   - withdrawal: The SOL withdrawal, if any.
    ///   - outputs: The outputs, padding included, in slot order.
    ///   - payer: The fee payer.
    /// - Throws: ``WincodeWriter/ValidationError/lengthOverflow`` for more than 255 outputs, or a
    ///   ``Transactions/ValidationError`` if the SOL interface's derivation fails.
    init(
        transactionViewingPublicKey: P256.KeyAgreement.PublicKey,
        salt: [UInt8],
        withdrawal: Withdrawal?,
        outputs: [TransactOutput],
        payer: Address
    ) throws {
        precondition(salt.count == SlotCipher.saltLength, "A transact's salt needs exactly 16 bytes.")
        var writer = WincodeWriter()
        writer.append(Self.noExpiry)
        writer.append(array: Array(transactionViewingPublicKey.compressedRepresentation))
        writer.append(array: salt)
        var accounts = [[UInt8]]()
        if let withdrawal {
            try writer.appendCount(1)
            writer.append(Self.solWithdrawalVariant)
            writer.append(withdrawal.lamports)
            accounts += [try ShieldedPool.solInterface.bytes, withdrawal.recipient.bytes]
        } else {
            try writer.appendCount(0)
        }
        writer.appendNone()
        writer.appendNone()
        try writer.appendCount(outputs.count)
        for output in outputs {
            try output.write(to: &writer)
            if output.ownerTag == .payer { accounts.append(payer.bytes) }
        }
        try writer.appendCount(0)
        encoded = writer.bytes
        var digest = Array(SHA256.hash(data: [ShieldedPool.transactTag] + encoded + accounts.flatMap(\.self)))
        digest[0] = 0
        hash = digest
    }
}
