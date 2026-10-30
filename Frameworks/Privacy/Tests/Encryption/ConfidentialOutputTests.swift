import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

struct ConfidentialOutputTests {
    private static let payloadHex = """
        0154000000030299cff79e0e9e5a109e998f3868a1c358eb82e30ee4737ce8271c1e3a473ea0f658586f6ab7254704\
        531d88b97a02449955861b69a9595a07a5dbcf55b2f8983afc2bbd7a731cb45b4fe74a7a909073fbc3ed
        """

    private static let amountPosition = 47

    private let output: TransferVectors.Output

    private let payload: [UInt8]

    private let decodedPayload: ConfidentialOutput

    private let utxoHash: Poseidon.Element

    private let viewingKey: P256.KeyAgreement.PrivateKey

    private let owner: Poseidon.Element

    private let note: ConfidentialPlaintext

    private let transactionViewingKey: P256.KeyAgreement.PrivateKey

    private let salt = [UInt8](0..<16)

    init() throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        output = try #require(TransferVectors.outputs.first)
        payload = try fixtureBytes(Self.payloadHex)
        decodedPayload = try ConfidentialOutput(decoding: payload)
        utxoHash = try Poseidon.Element(hex: output.commitment)
        viewingKey = try rail.viewingKey()
        try #require(Array(viewingKey.publicKey.compressedRepresentation) == (try fixtureBytes(rail.viewingPubkey)))
        owner = try rail.ownerHash()
        note = ConfidentialPlaintext(asset: .sol, amount: output.amount, blinding: try output.blinding())
        transactionViewingKey = try TransactionViewingKey.derive(
            viewingKey: viewingKey, firstNullifier: Poseidon.Element(hex: output.firstNullifier)
        )
    }

    @Test
    func `Sealed payloads match the independently derived payload`() throws {
        let sealed = try ConfidentialOutput.seal(
            note, for: viewingKey.publicKey, transactionViewingKey: transactionViewingKey, salt: salt, slot: output.index
        )

        #expect(sealed.encoded == payload)
    }

    @Test
    func `Payloads decode and encode unchanged`() throws {
        let decoded = try ConfidentialOutput(decoding: payload)

        #expect(decoded.recipientViewingPublicKey.compressedRepresentation == viewingKey.publicKey.compressedRepresentation)
        #expect(decoded.encoded == payload)
    }

    @Test
    func `Recipients open the notes that senders seal`() throws {
        let sealed = try ConfidentialOutput.seal(
            note, for: viewingKey.publicKey, transactionViewingKey: transactionViewingKey, salt: salt, slot: output.index
        )

        let opened = try ConfidentialOutput(decoding: sealed.encoded).openAsRecipient(
            viewingKey: viewingKey, transactionViewingPublicKey: transactionViewingKey.publicKey, salt: salt, slot: output.index
        )

        #expect(opened == note)
    }

    @Test
    func `Senders reopen their own payloads`() throws {
        let opened = try decodedPayload.openAsSender(transactionViewingKey: transactionViewingKey, salt: salt, slot: output.index)

        #expect(opened == note)
    }

    @Test
    func `Recipients receive the published UTXO`() throws {
        let utxo = try decodedPayload.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: utxoHash
        )

        #expect(utxo == UTXO(owner: owner, mint: [UInt8](repeating: 0, count: 32), amount: 6, blinding: note.blinding, treeID: 0))
    }

    @Test
    func `Payloads for another viewing key aren't addressed to it`() throws {
        let otherKey = try CommitmentVectors.load().p256Rail.viewingKey()

        let opened = try decodedPayload.openAsRecipient(
            viewingKey: otherKey, transactionViewingPublicKey: transactionViewingKey.publicKey, salt: salt, slot: output.index
        )
        let received = try decodedPayload.receive(
            viewingKey: otherKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: utxoHash
        )

        #expect(opened == nil)
        #expect(received == nil)
    }

    @Test
    func `Tampered ciphertexts fail the UTXO hash check`() throws {
        var bytes = payload
        bytes[Self.amountPosition] ^= 1
        let tampered = try ConfidentialOutput(decoding: bytes)

        let opened = try #require(try tampered.openAsRecipient(
            viewingKey: viewingKey, transactionViewingPublicKey: transactionViewingKey.publicKey, salt: salt, slot: output.index
        ))
        let received = try tampered.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: utxoHash
        )

        #expect(opened.amount == 7)
        #expect(received == nil)
    }

    @Test(arguments: [(0, [UInt8](0..<16)), (1, [UInt8](1...16))] as [(UInt32, [UInt8])])
    func `Notes that don't decode aren't received`(slot: UInt32, salt: [UInt8]) throws {
        let received = try decodedPayload.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: slot, treeID: output.treeID, utxoHash: utxoHash
        )

        #expect(throws: ConfidentialPlaintext.ValidationError.self) {
            try decodedPayload.openAsRecipient(viewingKey: viewingKey, transactionViewingPublicKey: transactionViewingKey.publicKey, salt: salt, slot: slot)
        }
        #expect(received == nil)
    }

    @Test(arguments: try ConfidentialOutputTests.unsupportedPayloads())
    func `Unsupported payloads are rejected`(bytes: [UInt8], error: ConfidentialOutput.ValidationError) {
        #expect(throws: error) {
            try ConfidentialOutput(decoding: bytes)
        }
    }

    private static func unsupportedPayloads() throws -> [([UInt8], ConfidentialOutput.ValidationError)] {
        let bytes = try fixtureBytes(Self.payloadHex)
        return [
            ([], .invalidLength),
            (Array(bytes.prefix(5)), .invalidLength),
            (bytes.replacingSubrange(0..<1, with: [0]), .unsupportedEncoding),
            (bytes.replacingSubrange(0..<1, with: [2]), .unsupportedEncoding),
            (bytes.replacingSubrange(1..<5, with: [83, 0, 0, 0]), .invalidLength),
            (bytes.replacingSubrange(1..<5, with: [85, 0, 0, 0]), .invalidLength),
            (bytes.replacingSubrange(1..<5, with: [85, 0, 0, 0]) + [0], .invalidLength),
            (Array(bytes.dropLast()), .invalidLength),
            (bytes + [0], .invalidLength),
            (bytes.replacingSubrange(5..<6, with: [1]), .unsupportedScheme),
            (bytes.replacingSubrange(5..<6, with: [4]), .unsupportedScheme),
            (bytes.replacingSubrange(6..<7, with: [4]), .invalidRecipientKey),
            (bytes.replacingSubrange(6..<39, with: [2] + [UInt8](repeating: 0, count: 31) + [1]), .invalidRecipientKey),
        ]
    }
}
