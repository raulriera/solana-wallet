import Foundation
import Privacy
import Testing
import Transactions

/// Verifies an account's registration instruction against bytes assembled by hand from zolana's
/// Rust layout, with the sender's independent registry record: when the account pays for its record
/// and when another wallet pays.
struct ShieldedAccountRegisterTests {
    /// Verifies the sender's registration: its own keys in the data, its record, itself as the
    /// read-only signing owner, and the payer as a writable signer.
    ///
    /// - Parameter payer: The wallet that pays, the sender itself or the published relayed payer.
    @Test(arguments: [TransferVectors.senderSigningAddress, TransferVectors.transfers[1].payer])
    func `Registrations publish the account's keys`(payer: String) throws {
        let vector = try #require(try RegistryVectors.load().records.first { $0.owner == TransferVectors.senderSigningAddress })
        let sender = try TransferVectors.sender()

        let instruction = try sender.register(paidBy: Address(payer))

        #expect(instruction.program == (try Address(RegistryVectors.load().program)))
        #expect(Array(instruction.data) == (try fixtureBytes("0000" + vector.nullifierPublicKey + vector.viewingPublicKey)))
        #expect(instruction.accounts == [
            .init(address: try Address(vector.record), isSigner: false, isWritable: true),
            .init(address: sender.signingAddress, isSigner: true, isWritable: false),
            .init(address: try Address(payer), isSigner: true, isWritable: true),
            .init(address: try Address("11111111111111111111111111111111"), isSigner: false, isWritable: false),
        ])
    }
}
