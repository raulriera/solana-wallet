import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies proofless deposits: their data and accounts against an independent implementation, and
/// their rejection of zero amounts.
struct ShieldedPoolDepositTests {
    /// Verifies deposits against an independent implementation: one lamport, the largest amount to
    /// the depositor's own shielded address in the last tree, and a deposit from another wallet.
    ///
    /// - Parameter vector: A deposit and its expected instruction.
    @Test(arguments: try InstructionVectors.load().deposits)
    func `Deposits match the independent reference`(_ vector: InstructionVectors.Deposit) throws {
        let sender = try TransferVectors.sender()
        let owner = vector.toSender ? try Recipient(
            signingAddress: sender.signingAddress, nullifierPublicKey: sender.nullifierKey.publicKey,
            viewingPublicKey: sender.viewingKey.publicKey
        ) : try TransferVectors.recipient()
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
}
