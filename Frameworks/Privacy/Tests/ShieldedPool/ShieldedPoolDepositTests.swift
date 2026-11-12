import CryptoKit
import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy

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
    func `Token deposits match a devnet deposit`() throws {
        let recipient = try TransferVectors.recipient()
        let depositor = try Address("9Vrvyr8YURu79z4sTrgcL9aYXARxfuNgrhZpJnJTrAPD")

        let instruction = try ShieldedPool.deposit(1_000_000, of: .devnetUSDC, from: depositor, to: recipient, treeID: 0)

        #expect(instruction.accounts.map(\.address.value) == [
            try ShieldedPool.tree(id: 0).value, depositor.value, "ring1GaLCuJnkUMVkX2JeZLTTX17wKsV4fZmPVzXANW",
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU",
            "H2gYgZ72JHp2UyJAuvLZm9cayVqLy1LnuLENXpYjjrRq", "DG6W5q9LyFgy6oPAePqh9CXyh4JgqzWqVTEBqGiHpdz",
        ])
        #expect(instruction.accounts.map(\.isSigner) == [false, true, false, false, false, false, false])
        #expect(instruction.accounts.map(\.isWritable) == [true, true, false, false, false, true, true])
        #expect(Array(instruction.data) == [0x0f, 1, 1, 0xff, 1, 0] + recipient.viewTag + recipient.owner.bigEndianBytes
            + [0x40, 0x42, 0x0f, 0, 0, 0, 0, 0, 0])
    }

    @Test
    func `Zero-amount token deposits are rejected`() throws {
        let recipient = try TransferVectors.recipient()
        let depositor = try Address(TransferVectors.senderSigningAddress)

        #expect(throws: ValidationError.invalidAmount) {
            try ShieldedPool.deposit(0, of: .usdc, from: depositor, to: recipient, treeID: 0)
        }
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
