import CryptoKit
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy

struct RecipientTests {
    @Test(arguments: TransferVectors.transfers)
    func `The derived recipient reproduces the published recipient commitments`(_ transfer: TransferVectors.Transfer) throws {
        let recipient = try TransferVectors.recipient()
        let firstNullifier = try Poseidon.Element(hex: transfer.firstNullifier)
        let seed = TransactBlinding.outputBlindingSeed(firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed)
        let utxo = UTXO(
            owner: recipient.owner, asset: .nativeSOL, amount: transfer.recipientAmount,
            blinding: TransactBlinding.outputBlinding(firstNullifier: firstNullifier, outputBlindingSeed: seed, index: 0),
            treeID: transfer.outputTreeID
        )

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(transfer.recipientCommitment)))
    }

    @Test
    func `Off-curve signing addresses are rejected`() throws {
        let viewingKey = Curve25519.KeyAgreement.PrivateKey()

        #expect(throws: Recipient.ValidationError.offCurveSigningAddress) {
            try Recipient(signingAddress: ShieldedPool.solInterface, nullifierPublicKey: .one, viewingPublicKey: viewingKey.publicKey)
        }
    }
}
