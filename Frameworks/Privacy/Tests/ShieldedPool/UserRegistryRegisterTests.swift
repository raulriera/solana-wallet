import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

struct UserRegistryRegisterTests {
    @Test(arguments: try RegistryVectors.load().records)
    func `Registrations match the hand-assembled layout`(_ vector: RegistryVectors.Record) throws {
        let recipient = try Recipient(
            signingAddress: Address(vector.owner), nullifierPublicKey: Poseidon.Element(hex: vector.nullifierPublicKey),
            viewingPublicKey: Curve25519.KeyAgreement.PublicKey(taggedRepresentation: fixtureBytes(vector.viewingPublicKey))
        )
        let payer = try Address(TransferVectors.transfers[1].payer)

        let instruction = try UserRegistry.register(recipient, paidBy: payer)

        #expect(instruction.program == (try Address(RegistryVectors.load().program)))
        #expect(Array(instruction.data) == (try fixtureBytes("00" + vector.nullifierPublicKey + vector.viewingPublicKey)))
        #expect(instruction.data.count == 66)
        #expect(instruction.accounts == [
            .writable(try Address(vector.record)),
            .readonly(try Address(vector.owner), isSigner: true),
            .writable(payer, isSigner: true),
            .readonly(try Address("11111111111111111111111111111111")),
        ])
    }
}
