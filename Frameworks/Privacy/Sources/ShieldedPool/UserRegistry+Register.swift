import CryptoKit
import Foundation
import ModularArithmetic
import Transactions

extension UserRegistry {
    /// The tag of the registry's `register` instruction.
    private static let registerTag: UInt8 = 0

    /// The Borsh tag of an absent P-256 owner.
    private static let noP256Owner: UInt8 = 0

    /// Creates the registry's `register` instruction, which publishes an Ed25519 owner's shielded
    /// address in its record.
    ///
    /// The data is the tag 0 and zolana's Borsh `RegisterArgs`: no P-256 owner, the nullifier public
    /// key as 32 big-endian bytes, and the 33-byte compressed viewing public key. The accounts are
    /// the writable record, the owner as a read-only signer, the payer as a writable signer, and the
    /// System Program. The payer funds the record's rent and may be the owner. The program rejects a
    /// record that already exists, and no instruction removes one.
    ///
    /// - Parameters:
    ///   - recipient: The owner and the keys to publish.
    ///   - payer: The wallet that pays the record's rent and signs.
    /// - Returns: The instruction, which the owner and the payer sign.
    /// - Throws: A ``Transactions/ValidationError`` if an account's derivation fails, which doesn't
    ///   happen.
    static func register(_ recipient: Recipient, paidBy payer: Address) throws -> Instruction {
        let data: [UInt8] = [registerTag, noP256Owner] + recipient.nullifierPublicKey.bigEndianBytes
            + Array(recipient.viewingPublicKey.compressedRepresentation)
        return Instruction(program: try program, accounts: [
            .init(address: try record(of: recipient.signingAddress).address, isSigner: false, isWritable: true),
            .init(address: recipient.signingAddress, isSigner: true, isWritable: false),
            .init(address: payer, isSigner: true, isWritable: true),
            .init(address: try ShieldedPool.systemProgram, isSigner: false, isWritable: false),
        ], data: Data(data))
    }
}
