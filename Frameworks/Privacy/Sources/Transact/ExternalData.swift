import CryptoKit
import Transactions

/// The public part of a transact that its proof commits to, and the external data hash that does.
///
/// The encoded prefix is the start of the transact instruction's data, after its tag, as zolana's
/// `TransactIxData` writes it: no expiry, `u64::MAX`; the transaction viewing public key; the salt;
/// the interface transfers, at most one SOL withdrawal; no data hash and no ring data hash; the
/// outputs; and no messages. The hash is SHA-256 of the tag 16, the prefix, the SOL interface and
/// the recipient of the withdrawal, and the fee payer's address once for each output that refers to
/// it, with its first byte set to zero so it's a field element. The proof binds the payer and
/// these accounts, not the blockhash, so the instruction can be signed with any recent blockhash.
struct ExternalData: Sendable {
    /// A withdrawal of SOL from the shielded pool to a public account, `SolWithdrawal`.
    struct Withdrawal: Sendable, Equatable {
        /// The account that receives the lamports.
        let recipient: Address
        /// The positive amount, in lamports.
        let lamports: UInt64
    }

    /// The expiry of a transact that doesn't expire, as zolana's clients set it.
    private static let noExpiry = UInt64.max

    /// The variant of a SOL withdrawal among the interface transfers.
    private static let solWithdrawalVariant: UInt8 = 1

    /// The encoded prefix of the instruction data, from the expiry through the messages.
    let encoded: [UInt8]

    /// The 32-byte external data hash, whose first byte is zero.
    let hash: [UInt8]

    /// Encodes the public part of a transact and hashes it.
    ///
    /// - Parameters:
    ///   - transactionViewingPublicKey: The public key of the transaction viewing key that sealed
    ///     the outputs' notes.
    ///   - salt: The 16-byte salt of the outputs' notes.
    ///   - withdrawal: The SOL withdrawal, if any.
    ///   - outputs: The outputs, padding included, in slot order.
    ///   - payer: The fee payer, which outputs with a ``TransactOutput/OwnerTag/payer`` tag refer to.
    /// - Throws: ``WincodeWriter/ValidationError/lengthOverflow`` for more than 255 outputs, or a
    ///   ``ValidationError`` if the SOL interface's derivation fails, which doesn't happen.
    /// - Precondition: `salt` contains exactly 16 bytes.
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
        // No data hash and no ring data hash.
        writer.appendNone()
        writer.appendNone()
        try writer.appendCount(outputs.count)
        for output in outputs {
            try output.write(to: &writer)
            if output.ownerTag == .payer { accounts.append(payer.bytes) }
        }
        // No messages.
        try writer.appendCount(0)
        encoded = writer.bytes
        var digest = Array(SHA256.hash(data: [ShieldedPool.transactTag] + encoded + accounts.flatMap(\.self)))
        digest[0] = 0
        hash = digest
    }
}
