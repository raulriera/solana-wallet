import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies recipients: their owner hashes, their view tags, and their signing-address checks.
struct RecipientTests {
    /// Verifies that the Ed25519 rail as a recipient has the owner hash that its published keys
    /// derive and its signing address as its view tag.
    @Test
    func `Recipients derive the owner hash and use the signing address as the view tag`() throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        let recipient = try Recipient(
            signingAddress: Address(TransferVectors.senderSigningAddress), nullifierPublicKey: Poseidon.Element(hex: rail.nullifierPubkey),
            viewingPublicKey: rail.viewingKey().publicKey
        )

        #expect(recipient.owner == (try rail.ownerHash()))
        #expect(recipient.viewTag == (try fixtureBytes(#require(rail.signerPubkey))))
    }

    /// Verifies the independently derived recipient of zolana's published transfers against both
    /// published slot-0 commitments.
    ///
    /// - Parameter transfer: A published transfer.
    @Test(arguments: TransferVectors.transfers)
    func `The derived recipient reproduces the published recipient commitments`(_ transfer: TransferVectors.Transfer) throws {
        let recipient = try TransferVectors.recipient()
        let firstNullifier = try Poseidon.Element(hex: transfer.firstNullifier)
        let seed = TransactBlinding.outputBlindingSeed(firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed)
        let utxo = UTXO(
            owner: recipient.owner, mint: Array(repeating: 0, count: 32), amount: transfer.recipientAmount,
            blinding: TransactBlinding.outputBlinding(firstNullifier: firstNullifier, outputBlindingSeed: seed, index: 0),
            treeID: transfer.outputTreeID
        )

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(transfer.recipientCommitment)))
    }

    /// Verifies that an off-curve signing address, such as the shielded pool's SOL interface, can't
    /// own UTXOs.
    @Test
    func `Off-curve signing addresses are rejected`() throws {
        let viewingKey = P256.KeyAgreement.PrivateKey()

        #expect(throws: Recipient.ValidationError.offCurveSigningAddress) {
            try Recipient(signingAddress: ShieldedPool.solInterface, nullifierPublicKey: .one, viewingPublicKey: viewingKey.publicKey)
        }
    }
}
