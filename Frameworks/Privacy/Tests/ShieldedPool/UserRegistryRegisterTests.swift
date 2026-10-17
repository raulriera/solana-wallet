import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies the registry's `register` instruction against bytes assembled by hand from zolana's
/// Rust layout in `program-libs/user-registry-interface/src/instruction.rs`: the tag 0, `None` for
/// the P-256 owner, the nullifier public key, and the compressed viewing public key, with the keys
/// and record addresses of the independent registry vectors.
struct UserRegistryRegisterTests {
    /// Verifies each registered owner's instruction with a separate payer: its 67 data bytes and its
    /// record, owner, payer, and System Program accounts.
    ///
    /// - Parameter vector: A registered owner.
    @Test(arguments: try RegistryVectors.load().records)
    func `Registrations match the hand-assembled layout`(_ vector: RegistryVectors.Record) throws {
        let recipient = try Recipient(
            signingAddress: Address(vector.owner), nullifierPublicKey: Poseidon.Element(hex: vector.nullifierPublicKey),
            viewingPublicKey: P256.KeyAgreement.PublicKey(compressedRepresentation: fixtureBytes(vector.viewingPublicKey))
        )
        let payer = try Address(TransferVectors.transfers[1].payer)

        let instruction = try UserRegistry.register(recipient, paidBy: payer)

        #expect(instruction.program == (try Address(RegistryVectors.load().program)))
        #expect(Array(instruction.data) == (try fixtureBytes("0000" + vector.nullifierPublicKey + vector.viewingPublicKey)))
        #expect(instruction.data.count == 67)
        #expect(instruction.accounts == [
            .init(address: try Address(vector.record), isSigner: false, isWritable: true),
            .init(address: try Address(vector.owner), isSigner: true, isWritable: false),
            .init(address: payer, isSigner: true, isWritable: true),
            .init(address: try Address("11111111111111111111111111111111"), isSigner: false, isWritable: false),
        ])
    }
}
