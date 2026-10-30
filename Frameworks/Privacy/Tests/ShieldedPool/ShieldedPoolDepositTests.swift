import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

struct ShieldedPoolDepositTests {
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

    @Test
    func `Zero-lamport deposits are rejected`() throws {
        let recipient = try TransferVectors.recipient()
        let depositor = try Address(TransferVectors.senderSigningAddress)

        #expect(throws: ValidationError.invalidAmount) {
            try ShieldedPool.deposit(lamports: 0, from: depositor, to: recipient, treeID: 0)
        }
    }

    @Test(arguments: [
        ("4vJ9JU1bJJE96FWSJKvHsmmFADCg4gpZQff4P3bkLKi", 7, "004d1e40d2142411b39e40c763db9defb6ca70abeaad20674443d33f88be673a"),
        ("33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN", 5, "001ae5cba088c8965c6fb7d328f8c75eebf994553a8793eb054ecc1efd9f1b3c"),
    ] as [(String, UInt64, String)])
    func `Deposit blindings match their values`(tree: String, leafIndex: UInt64, expected: String) throws {
        #expect(ShieldedPool.depositBlinding(tree: try Address(tree), leafIndex: leafIndex).bigEndianBytes == (try fixtureBytes(expected)))
    }
}
