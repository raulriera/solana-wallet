import CryptoKit
import ModularArithmetic
import Testing
@testable import Privacy

struct ConfidentialOutputTests {
    private static let payloadHex = """
        0154000000030419078976c68ba992eb10aae97df1e453731a022d6c46eb8a0a4f1c976a0cc20abf2715a575e535cc\
        d901ae5d80c0b60b088d998281a9271eb0163177b6752c8f5e984fd9b12db27536feb60a12b3bd70b015
        """

    private static let amountPosition = 47

    private let output: TransferVectors.Output

    private let payload: [UInt8]

    private let decodedPayload: ConfidentialOutput

    private let utxoHash: Poseidon.Element

    private let viewingKey: Curve25519.KeyAgreement.PrivateKey

    private let owner: Poseidon.Element

    private let note: ConfidentialPlaintext

    private let transactionViewingKey: Curve25519.KeyAgreement.PrivateKey

    private let salt = [UInt8](0..<16)

    init() throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        output = try #require(TransferVectors.outputs.first)
        payload = try fixtureBytes(Self.payloadHex)
        decodedPayload = try ConfidentialOutput(decoding: payload)
        utxoHash = try Poseidon.Element(hex: output.commitment)
        viewingKey = try rail.viewingKey()
        try #require([UInt8](viewingKey.publicKey.taggedRepresentation) == (try fixtureBytes(rail.viewingPubkey)))
        owner = try rail.ownerHash()
        note = ConfidentialPlaintext(asset: .nativeSOL, amount: output.amount, blinding: try output.blinding())
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

        #expect(decoded.recipientViewingPublicKey.rawRepresentation == viewingKey.publicKey.rawRepresentation)
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
    func `Recipients receive the published UTXO`() throws {
        let utxo = try decodedPayload.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: utxoHash
        )

        #expect(utxo == UTXO(owner: owner, mint: [UInt8](repeating: 0, count: 32), amount: 6, blinding: note.blinding, treeID: 0))
    }

    @Test(arguments: PrivateToken.supported.map(PrivateAsset.token))
    func `Recipients receive token notes only under their asset's mint`(asset: PrivateAsset) throws {
        let token = ConfidentialPlaintext(asset: asset, amount: 6, blinding: note.blinding)
        let expected = UTXO(owner: owner, mint: asset.mintBytes, amount: 6, blinding: note.blinding, treeID: output.treeID)
        let sealed = try ConfidentialOutput(decoding: ConfidentialOutput.seal(
            token, for: viewingKey.publicKey, transactionViewingKey: transactionViewingKey, salt: salt, slot: output.index
        ).encoded)

        let received = try sealed.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: expected.hash
        )
        let otherMint = UTXO(owner: owner, mint: PrivateAsset.nativeSOL.mintBytes, amount: 6, blinding: note.blinding,
                             treeID: output.treeID)
        let mismatched = try sealed.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingKey.publicKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: otherMint.hash
        )

        #expect(received == expected)
        #expect(mismatched == nil)
    }

    @Test
    func `Payloads for another viewing key aren't addressed to it`() throws {
        let otherKey = try TransferVectors.recipientViewingKey()

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

    @Test(arguments: X25519Fixtures.lowOrderCoordinates)
    func `Notes under a low-order transaction viewing key aren't received`(u: [UInt8]) throws {
        let lowOrderKey = try Curve25519.KeyAgreement.PublicKey(taggedRepresentation: [4] + u)

        let received = try decodedPayload.receive(
            viewingKey: viewingKey, owner: owner, transactionViewingPublicKey: lowOrderKey,
            salt: salt, slot: output.index, treeID: output.treeID, utxoHash: utxoHash
        )

        #expect(throws: SlotCipher.ValidationError.lowOrderPublicKey) {
            try decodedPayload.openAsRecipient(viewingKey: viewingKey, transactionViewingPublicKey: lowOrderKey, salt: salt, slot: output.index)
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
            (bytes.replacingSubrange(6..<7, with: [2]), .invalidRecipientKey),
            (bytes.replacingSubrange(7..<39, with: X25519Fixtures.modulus), .invalidRecipientKey),
        ]
    }
}
