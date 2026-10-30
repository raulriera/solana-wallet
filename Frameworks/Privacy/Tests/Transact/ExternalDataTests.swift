import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

struct ExternalDataTests {
    @Test(arguments: TransferVectors.transfers)
    func `Hashes match the published transfers`(_ transfer: TransferVectors.Transfer) throws {
        let sender = try TransferVectors.sender()
        let recipient = try TransferVectors.recipient()
        let payer = try Address(transfer.payer)
        let firstNullifier = try Poseidon.Element(hex: transfer.firstNullifier)
        let transactionViewingKey = try TransactionViewingKey.derive(viewingKey: sender.viewingKey, firstNullifier: firstNullifier)
        let seed = TransactBlinding.outputBlindingSeed(firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed)
        let slots = [(transfer.recipientAmount, transfer.recipientCommitment)] + transfer.senderOutputs.map { ($0.amount, $0.commitment) }
        let outputs = try slots.enumerated().map { slot, values in
            let owner = slot == 0 ? recipient.viewingPublicKey : sender.viewingKey.publicKey
            let blinding = TransactBlinding.outputBlinding(firstNullifier: firstNullifier, outputBlindingSeed: seed, index: UInt32(slot))
            let note = try ConfidentialOutput.seal(
                ConfidentialPlaintext(asset: .sol, amount: values.0, blinding: blinding), for: owner,
                transactionViewingKey: transactionViewingKey, salt: TransferVectors.salt, slot: UInt32(slot)
            )
            let viewTag = slot == 0 ? recipient.viewTag : sender.signingAddress.bytes
            let ownerTag: TransactOutput.OwnerTag = payer == sender.signingAddress && slot != 0 ? .payer : .inline(viewTag)
            return TransactOutput(utxoHash: try Poseidon.Element(hex: values.1), ownerTag: ownerTag, data: note.encoded)
        }

        let externalData = try ExternalData(
            transactionViewingPublicKey: transactionViewingKey.publicKey, salt: TransferVectors.salt, withdrawal: nil,
            outputs: outputs, payer: payer
        )

        #expect(externalData.hash == (try fixtureBytes(transfer.externalDataHash)))
    }

    @Test
    func `Prefixes without a withdrawal follow zolana's encoding`() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let output = TransactOutput(utxoHash: .one, ownerTag: .payer, data: [7])
        var writer = WincodeWriter()
        try output.write(to: &writer)

        let externalData = try ExternalData(
            transactionViewingPublicKey: key, salt: TransferVectors.salt, withdrawal: nil, outputs: [output],
            payer: Address(TransferVectors.senderSigningAddress)
        )

        #expect(externalData.encoded == Array(repeating: 0xff, count: 8) + key.compressedRepresentation + TransferVectors.salt
            + [0, 0, 0, 1] + writer.bytes + [0])
        #expect(externalData.hash[0] == 0)
    }

    @Test
    func `Prefixes with a withdrawal carry one SOL withdrawal`() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let externalData = try ExternalData(
            transactionViewingPublicKey: key, salt: TransferVectors.salt, withdrawal: PlanFixtures.withdrawal(lamports: 0x0102),
            outputs: [], payer: Address(TransferVectors.senderSigningAddress)
        )

        #expect(externalData.encoded == Array(repeating: 0xff, count: 8) + key.compressedRepresentation + TransferVectors.salt
            + [1, 1, 0x02, 0x01, 0, 0, 0, 0, 0, 0] + [0, 0, 0, 0])
    }

    @Test
    func `Hashes cover the withdrawal recipient`() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let payer = try Address(TransferVectors.senderSigningAddress)
        let toRelayedPayer = try ExternalData(
            transactionViewingPublicKey: key, salt: TransferVectors.salt, withdrawal: PlanFixtures.withdrawal(lamports: 5),
            outputs: [], payer: payer
        )
        let toSender = try ExternalData(
            transactionViewingPublicKey: key, salt: TransferVectors.salt, withdrawal: .init(recipient: payer, lamports: 5),
            outputs: [], payer: payer
        )

        #expect(toRelayedPayer.encoded == toSender.encoded)
        #expect(toRelayedPayer.hash != toSender.hash)
    }

    @Test
    func `Hashes cover the payer only for outputs that refer to it`() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let sender = try Address(TransferVectors.senderSigningAddress)
        let relayed = try Address(TransferVectors.transfers[1].payer)
        let inline = [TransactOutput(utxoHash: .one, ownerTag: .inline(sender.bytes), data: [7])]
        let referring = [TransactOutput(utxoHash: .one, ownerTag: .payer, data: [7])]

        let hash = { (outputs: [TransactOutput], payer: Address) in
            try ExternalData(transactionViewingPublicKey: key, salt: TransferVectors.salt, withdrawal: nil, outputs: outputs, payer: payer).hash
        }

        #expect(try hash(inline, sender) == hash(inline, relayed))
        #expect(try hash(referring, sender) != hash(referring, relayed))
    }
}
