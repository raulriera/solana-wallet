import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies proofless deposits: their data and accounts against an independent implementation,
/// their rejection of zero amounts, and the blindings that the program derives.
///
/// zolana pins one blinding in `deposit_blinding_is_pinned` of
/// `program-libs/interface/src/instruction/instruction_data/deposit.rs` at tag v0.4.0-alpha
/// (Apache-2.0), copied unchanged; `NOTICE.txt` records the source and its
/// digest. The blinding in tree 0 comes from an independent Python implementation.
struct ShieldedPoolDepositTests {
    /// Verifies deposits against an independent implementation: one lamport, the largest amount to
    /// the depositor's own shielded address in the last tree, and a deposit from another wallet.
    ///
    /// - Parameter vector: A deposit and its expected instruction.
    @Test(arguments: try InstructionVectors.load().deposits)
    func `Deposits match the independent reference`(_ vector: InstructionVectors.Deposit) throws {
        let sender = try TransferVectors.sender()
        let owner = vector.toSender ? try sender.recipient : try TransferVectors.recipient()
        let lamports = try #require(UInt64(vector.lamports))

        let instruction = try ShieldedPool.deposit(lamports: lamports, from: Address(vector.depositor), to: owner, treeID: vector.treeID)

        #expect(instruction.program == (try Address(InstructionVectors.load().program)))
        #expect(Array(instruction.data) == (try fixtureBytes(vector.data)))
        #expect(instruction.accounts == (try vector.accounts.map { try $0.account() }))
    }

    /// Verifies that a zero-lamport deposit is rejected.
    @Test
    func `Zero-lamport deposits are rejected`() throws {
        let recipient = try TransferVectors.recipient()
        let depositor = try Address(TransferVectors.senderSigningAddress)

        #expect(throws: ValidationError.invalidAmount) {
            try ShieldedPool.deposit(lamports: 0, from: depositor, to: recipient, treeID: 0)
        }
    }

    /// Verifies deposit blindings: zolana's pinned value for the tree address of 32 bytes of 1 and
    /// leaf 7, and leaf 5 of tree 0.
    ///
    /// - Parameters:
    ///   - tree: The tree's address.
    ///   - leafIndex: The UTXO's position.
    ///   - expected: The blinding.
    @Test(arguments: [
        ("4vJ9JU1bJJE96FWSJKvHsmmFADCg4gpZQff4P3bkLKi", 7, "004d1e40d2142411b39e40c763db9defb6ca70abeaad20674443d33f88be673a"),
        ("33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN", 5, "001ae5cba088c8965c6fb7d328f8c75eebf994553a8793eb054ecc1efd9f1b3c"),
    ] as [(String, UInt64, String)])
    func `Deposit blindings match their values`(tree: String, leafIndex: UInt64, expected: String) throws {
        #expect(ShieldedPool.depositBlinding(tree: try Address(tree), leafIndex: leafIndex).bigEndianBytes == (try fixtureBytes(expected)))
    }
}
