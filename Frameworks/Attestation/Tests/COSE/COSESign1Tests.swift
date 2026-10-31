import CryptoKit
import Encoding
import Testing
@testable import Attestation

struct COSESign1Tests {
    private static let protectedHeader = CBOR.map([.integer(1): .integer(-35)]).encoded

    private static let signature = CBOR.bytes([UInt8](repeating: 0x01, count: 96))

    @Test(arguments: try NitroCBORCases.messages(expected: .accept))
    func `Recorded messages in the strict subset decode and verify`(message: NitroCBORCases.Case) throws {
        let key = try P384.Signing.PrivateKey(rawRepresentation: fixtureBytes(NitroCBORCases.load().leafKey))

        let decoded = try COSESign1(decoding: fixtureBytes(try #require(message.cose)))

        #expect(decoded.isValidSignature(from: key.publicKey))
    }

    @Test(arguments: try NitroCBORCases.messages(expected: .reject))
    func `Recorded messages outside the strict subset are rejected`(message: NitroCBORCases.Case) throws {
        let bytes = try fixtureBytes(try #require(message.cose))

        #expect(throws: CBOR.ValidationError.self) { try COSESign1(decoding: bytes) }
    }

    @Test
    func `Only the signing key verifies a message`() throws {
        let key = P384.Signing.PrivateKey()
        let payload: [UInt8] = [0x01, 0x02]
        let signed = COSESign1.signatureStructure(protectedHeader: Self.protectedHeader, payload: payload)
        let signature = try key.signature(for: signed).rawRepresentation
        let message = CBOR.array([.bytes(Self.protectedHeader), .map([:]), .bytes(payload), .bytes(Array(signature))])

        let decoded = try COSESign1(decoding: message.encoded)

        #expect(decoded.payload == payload)
        #expect(decoded.isValidSignature(from: key.publicKey))
        #expect(!decoded.isValidSignature(from: P384.Signing.PrivateKey().publicKey))
    }

    @Test
    func `A protected header that doesn't name ES384 is rejected`() {
        let header = CBOR.map([.integer(1): .integer(-7)]).encoded
        let message = CBOR.array([.bytes(header), .map([:]), .bytes([]), Self.signature])

        #expect(throws: COSESign1.ValidationError.unsupportedAlgorithm) { try COSESign1(decoding: message.encoded) }
    }

    @Test(arguments: [
        .map([:]),
        .array([.bytes(protectedHeader), .map([:]), .bytes([])]),
        .array([.map([.integer(1): .integer(-35)]), .map([:]), .bytes([]), signature]),
        .array([.bytes(CBOR.array([]).encoded), .map([:]), .bytes([]), signature]),
        .array([.bytes(protectedHeader), .array([]), .bytes([]), signature]),
        .array([.bytes(protectedHeader), .map([:]), .text(""), signature]),
        .array([.bytes(protectedHeader), .map([:]), .bytes([]), .bytes([UInt8](repeating: 0x01, count: 64))]),
    ] as [CBOR])
    func `Structures other than COSE_Sign1 are rejected`(message: CBOR) {
        #expect(throws: COSESign1.ValidationError.malformed) { try COSESign1(decoding: message.encoded) }
    }
}
