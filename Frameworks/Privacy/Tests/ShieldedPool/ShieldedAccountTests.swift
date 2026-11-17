import CryptoKit
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy

struct ShieldedAccountTests {
    @Test
    func `Accounts derive their shielded address`() throws {
        let rail = try CommitmentVectors.load().ed25519Rail

        let recipient = try TransferVectors.sender().recipient

        #expect(recipient.signingAddress.value == TransferVectors.senderSigningAddress)
        #expect(recipient.nullifierPublicKey == (try rail.nullifierKey().publicKey))
        #expect(recipient.owner == (try rail.ownerHash()))
    }

    @Test(arguments: [30, 32])
    func `Nullifier secrets of another length are rejected`(length: Int) throws {
        let signingAddress = try Address(TransferVectors.senderSigningAddress)

        #expect(throws: NullifierKey.ValidationError.invalidSecretLength) {
            try ShieldedAccount(
                signingAddress: signingAddress, nullifierSecret: SymmetricKey(data: [UInt8](repeating: 1, count: length)),
                viewingKey: Curve25519.KeyAgreement.PrivateKey()
            )
        }
    }
}
