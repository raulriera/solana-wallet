import CryptoKit
import Foundation
import ModularArithmetic
public import Transactions

extension ShieldedPool {
    private static let depositTag: UInt8 = 15

    private static let solAssetKind: UInt8 = 0

    private static let splAssetKind: UInt8 = 1

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
        try deposit(lamports, kind: [solAssetKind], from: depositor, to: recipient, treeID: treeID, settlement: [
            .init(address: try systemProgram, isSigner: false, isWritable: false),
            .init(address: try solInterface, isSigner: false, isWritable: true),
        ])
    }

    /// Creates a proofless deposit of public tokens from a wallet's associated token account into one recipient's
    /// default-ring UTXO.
    ///
    /// - Parameters:
    ///   - amount: The positive amount to deposit, in the token's smallest unit.
    ///   - token: The token.
    ///   - depositor: The wallet that owns the token account and signs.
    ///   - recipient: The owner of the new UTXO.
    ///   - treeID: The ID of the tree that receives the UTXO.
    /// - Returns: The deposit instruction.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for a zero amount, or another
    ///   ``Transactions/ValidationError`` if an account's derivation fails.
    public static func deposit(
        _ amount: UInt64, of token: PrivateToken, from depositor: Address, to recipient: Recipient, treeID: UInt16
    ) throws -> Instruction {
        let mint = try token.mint
        let interface = try splInterface(of: mint)
        return try deposit(amount, kind: [splAssetKind, interface.bump], from: depositor, to: recipient, treeID: treeID, settlement: [
            .init(address: try TokenProgram.token.address, isSigner: false, isWritable: false),
            .init(address: mint, isSigner: false, isWritable: false),
            .init(address: try TokenProgram.token.associatedAccount(owner: depositor, mint: mint), isSigner: false, isWritable: true),
            .init(address: interface.address, isSigner: false, isWritable: true),
        ])
    }

    /// Creates a proofless deposit of one asset into one recipient's default-ring UTXO.
    ///
    /// - Parameters:
    ///   - amount: The positive amount to deposit.
    ///   - kind: The encoded asset kind of the deposit's settlement.
    ///   - depositor: The wallet that pays the amount and signs.
    ///   - recipient: The owner of the new UTXO.
    ///   - treeID: The ID of the tree that receives the UTXO.
    ///   - settlement: The accounts that the asset kind names, in order.
    /// - Returns: The deposit instruction.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for a zero amount, or another
    ///   ``Transactions/ValidationError`` if an account's derivation fails.
    private static func deposit(
        _ amount: UInt64,
        kind: [UInt8],
        from depositor: Address,
        to recipient: Recipient,
        treeID: UInt16,
        settlement: [Transaction.Account]
    ) throws -> Instruction {
        guard amount > 0 else { throw ValidationError.invalidAmount }
        var writer = WincodeWriter()
        writer.append(depositTag)
        try writer.appendCount(1)
        writer.append(array: kind)
        try writer.appendCount(1)
        writer.append(UInt8(0))
        writer.append(array: recipient.viewTag)
        writer.append(array: recipient.owner.bigEndianBytes)
        writer.append(amount)
        writer.appendNone()
        return Instruction(program: try program, accounts: [
            .init(address: try tree(id: treeID), isSigner: false, isWritable: true),
            .init(address: depositor, isSigner: true, isWritable: true),
            .init(address: try program, isSigner: false, isWritable: false),
        ] + settlement, data: Data(writer.bytes))
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
