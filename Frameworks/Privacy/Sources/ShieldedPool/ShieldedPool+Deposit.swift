import CryptoKit
import Foundation
import ModularArithmetic
public import Transactions

extension ShieldedPool {
    private static let depositTag: UInt8 = 15

    private static let solAssetKind: UInt8 = 0

    private static let depositBlindingDomain = Array("Deposit".utf8)

    /// Creates a proofless deposit of public SOL into one recipient's default-ring UTXO.
    ///
    /// - Parameters:
    ///   - lamports: The positive amount to deposit, excluding fees.
    ///   - depositor: The wallet that pays the lamports and signs.
    ///   - recipient: The owner of the new UTXO.
    ///   - treeID: The ID of the tree that receives the UTXO.
    /// - Returns: The deposit instruction.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for zero lamports, or another
    ///   ``Transactions/ValidationError`` if an account's derivation fails.
    public static func deposit(lamports: UInt64, from depositor: Address, to recipient: Recipient, treeID: UInt16) throws -> Instruction {
        guard lamports > 0 else { throw ValidationError.invalidAmount }
        var writer = WincodeWriter()
        writer.append(depositTag)
        try writer.appendCount(1)
        writer.append(solAssetKind)
        try writer.appendCount(1)
        writer.append(UInt8(0))
        writer.append(array: recipient.viewTag)
        writer.append(array: recipient.owner.bigEndianBytes)
        writer.append(lamports)
        writer.appendNone()
        return Instruction(program: try program, accounts: [
            .init(address: try tree(id: treeID), isSigner: false, isWritable: true),
            .init(address: depositor, isSigner: true, isWritable: true),
            .init(address: try program, isSigner: false, isWritable: false),
            .init(address: try systemProgram, isSigner: false, isWritable: false),
            .init(address: try solInterface, isSigner: false, isWritable: true),
        ], data: Data(writer.bytes))
    }

    /// Derives the blinding that the program gives a deposited UTXO.
    ///
    /// - Parameters:
    ///   - tree: The account of the tree that holds the UTXO.
    ///   - leafIndex: The UTXO's position in the tree.
    /// - Returns: The blinding.
    static func depositBlinding(tree: Address, leafIndex: UInt64) -> Poseidon.Element {
        let preimage = depositBlindingDomain + tree.bytes + Swift.withUnsafeBytes(of: leafIndex.bigEndian, Array.init)
        var digest = Array(SHA256.hash(data: preimage))
        digest[0] = 0
        return Poseidon.Element(reducing: digest)
    }
}
