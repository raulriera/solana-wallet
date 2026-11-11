import CryptoKit
import Transactions

/// The public part of a transact that its proof commits to, and its hash.
struct ExternalData: Sendable {
    /// A withdrawal from the shielded pool to a public account.
    struct Withdrawal: Sendable, Equatable {
        /// The wallet that receives SOL, or the token account that receives the token.
        let recipient: Address

        /// The amount, in the asset's smallest unit.
        let amount: UInt64

        /// The withdrawn token, or `nil` for SOL.
        var token: PrivateToken?

        /// The withdrawn asset.
        var asset: ConfidentialPlaintext.Asset {
            token?.asset ?? .sol
        }

        /// The accounts that the external data hash commits to.
        var committedAccounts: [Address] {
            get throws { [try token?.mint ?? ShieldedPool.solInterface, recipient] }
        }

        /// The accounts of the withdrawal's settlement, which end the transact instruction's accounts.
        var settlementAccounts: [Transaction.Account] {
            get throws {
                guard let token else {
                    return [
                        .writable(try ShieldedPool.solInterface),
                        .writable(recipient),
                    ]
                }
                let mint = try token.mint
                return [
                    .readonly(try ShieldedPool.cpiAuthority),
                    .readonly(mint),
                    .writable(try ShieldedPool.splInterface(of: mint).address),
                    .writable(recipient),
                    .readonly(try TokenProgram.token.address),
                ]
            }
        }

        /// Writes the withdrawal's interface transfer: its kind, its amount, and a token's interface bump.
        ///
        /// - Parameter writer: The writer of the external data.
        /// - Throws: A ``Transactions/ValidationError`` if the token's interface derivation fails.
        func write(to writer: inout WincodeWriter) throws {
            writer.append(token == nil ? ExternalData.solWithdrawalVariant : ExternalData.splWithdrawalVariant)
            writer.append(amount)
            if let token { writer.append(try ShieldedPool.splInterface(of: token.mint).bump) }
        }
    }

    private static let noExpiry = UInt64.max

    static let solWithdrawalVariant: UInt8 = 1

    static let splWithdrawalVariant: UInt8 = 3

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
    ///   - withdrawal: The withdrawal, if any.
    ///   - outputs: The outputs, padding included, in slot order.
    ///   - payer: The fee payer.
    /// - Throws: ``WincodeWriter/ValidationError/lengthOverflow`` for more than 255 outputs, or a
    ///   ``Transactions/ValidationError`` if a settlement account's derivation fails.
    init(
        transactionViewingPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: [UInt8],
        withdrawal: Withdrawal?,
        outputs: [TransactOutput],
        payer: Address
    ) throws {
        precondition(salt.count == SlotCipher.saltLength, "A transact's salt needs exactly 16 bytes.")
        var writer = WincodeWriter()
        writer.append(Self.noExpiry)
        writer.append(array: Array(transactionViewingPublicKey.taggedRepresentation))
        writer.append(array: salt)
        var accounts: [[UInt8]] = []
        if let withdrawal {
            try writer.appendCount(1)
            try withdrawal.write(to: &writer)
            accounts += try withdrawal.committedAccounts.map(\.bytes)
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
