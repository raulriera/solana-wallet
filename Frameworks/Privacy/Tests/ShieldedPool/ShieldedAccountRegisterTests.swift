import Foundation
import Privacy
import Testing
import Transactions

struct ShieldedAccountRegisterTests {
    @Test(arguments: [TransferVectors.senderSigningAddress, TransferVectors.transfers[1].payer])
    func `Registrations publish the account's keys`(payer: String) throws {
        let vector = try #require(try RegistryVectors.load().records.first { $0.owner == TransferVectors.senderSigningAddress })
        let sender = try TransferVectors.sender()

        let instruction = try sender.register(paidBy: Address(payer))

        #expect(instruction.program == (try Address(RegistryVectors.load().program)))
        #expect(Array(instruction.data) == (try fixtureBytes("00" + vector.nullifierPublicKey + vector.viewingPublicKey)))
        #expect(instruction.accounts == [
            .writable(try Address(vector.record)),
            .readonly(sender.signingAddress, isSigner: true),
            .writable(try Address(payer), isSigner: true),
            .readonly(try Address("11111111111111111111111111111111")),
        ])
    }
}
