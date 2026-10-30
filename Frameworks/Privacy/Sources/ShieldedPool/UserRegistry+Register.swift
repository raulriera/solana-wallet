import CryptoKit
import Foundation
import ModularArithmetic
import Transactions

extension UserRegistry {
    private static let registerTag: UInt8 = 0

    /// Creates the instruction that publishes an Ed25519 owner's shielded address in its record.
    ///
    /// - Parameters:
    ///   - recipient: The owner and the keys to publish.
    ///   - payer: The wallet that pays the record's rent and signs.
    /// - Returns: The registration instruction.
    /// - Throws: A ``Transactions/ValidationError`` if an account's derivation fails.
    static func register(_ recipient: Recipient, paidBy payer: Address) throws -> Instruction {
        let data: [UInt8] = [registerTag] + recipient.nullifierPublicKey.bigEndianBytes
            + Array(recipient.viewingPublicKey.compressedRepresentation)
        return Instruction(program: try program, accounts: [
            .init(address: try record(of: recipient.signingAddress).address, isSigner: false, isWritable: true),
            .init(address: recipient.signingAddress, isSigner: true, isWritable: false),
            .init(address: payer, isSigner: true, isWritable: true),
            .init(address: try ShieldedPool.systemProgram, isSigner: false, isWritable: false),
        ], data: Data(data))
    }
}
