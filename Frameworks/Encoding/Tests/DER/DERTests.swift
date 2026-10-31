import Encoding
import Foundation
import Testing

struct DERTests {
    @Test(arguments: DERVectors.canonical)
    func `Values decode into their tags and contents`(bytes: [UInt8], expected: DER) throws {
        #expect(try DER(decoding: bytes) == expected)
    }

    @Test(arguments: DERVectors.canonical.map(\.0))
    func `Decoded values encode to the bytes they came from`(bytes: [UInt8]) throws {
        #expect(try DER(decoding: bytes).encoded == bytes)
    }

    @Test(arguments: [DERVectors.certificate, DERVectors.rsaPublicKey])
    func `Certificates and keys from OpenSSL encode to the bytes they came from`(base64: String) throws {
        let bytes = [UInt8](try #require(Data(base64Encoded: base64)))

        #expect(try DER(decoding: bytes).encoded == bytes)
    }

    @Test
    func `A certificate decodes into its signed part, signature algorithm, and signature`() throws {
        let bytes = [UInt8](try #require(Data(base64Encoded: DERVectors.certificate)))

        let certificate = try DER(decoding: bytes)
        let fields = try #require(certificate.content.values)
        try #require(fields.map(\.identifier) == [.sequence, .sequence, .bitString])
        let signedFields = try #require(fields[0].content.values)

        #expect(certificate.identifier == .sequence)
        #expect(
            signedFields.map(\.identifier) == [
                DER.Identifier(tagWithNumber: 0, tagClass: .contextSpecific),
                .integer, .sequence, .sequence, .sequence, .sequence, .sequence,
                DER.Identifier(tagWithNumber: 3, tagClass: .contextSpecific),
            ]
        )
        #expect(fields[0].encoded == Array(bytes[4..<534]))
        #expect(fields[1].encoded == [0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03])
        #expect(fields[2].encoded == Array(bytes[546...]))
    }

    @Test(arguments: [
        [],
        [0x30],
        [0x02, 0x02, 0x01],
        [0x04, 0x81],
        [0x04, 0x82, 0x01],
        [0x04, 0x81, 0x80] + DERVectors.filler(count: 127),
        [0x30, 0x03, 0x02, 0x02, 0x01, 0x00],
        [0x30, 0x02, 0x04, 0x81, 0x80],
        [0x04, 0x88, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        [0x04, 0x88, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
    ] as [[UInt8]])
    func `Values that run past their input or their enclosing value are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.malformed) { try DER(decoding: bytes) }
    }

    @Test(arguments: [
        [0x04, 0x89, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80] + DERVectors.filler(count: 128),
        [0x04, 0xff] + DERVectors.filler(count: 127),
    ] as [[UInt8]])
    func `Lengths in more than eight octets are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.malformed) { try DER(decoding: bytes) }
    }

    @Test(arguments: [
        [0x05, 0x00, 0x00],
        [0x30, 0x00, 0x30, 0x00],
        [0x02, 0x01, 0x05, 0x00, 0x00],
    ] as [[UInt8]])
    func `Bytes after the value are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.trailingBytes) { try DER(decoding: bytes) }
    }

    @Test(arguments: [
        [0x30, 0x80, 0x05, 0x00, 0x00, 0x00],
        [0xa0, 0x80, 0x02, 0x01, 0x05, 0x00, 0x00],
        [0x04, 0x80],
        [0x30, 0x04, 0x30, 0x80, 0x00, 0x00],
    ] as [[UInt8]])
    func `Indefinite lengths are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.indefiniteLength) { try DER(decoding: bytes) }
    }

    @Test(arguments: [
        [0x30, 0x81, 0x00],
        [0x04, 0x81, 0x05] + DERVectors.filler(count: 5),
        [0x04, 0x81, 0x7f] + DERVectors.filler(count: 127),
        [0x04, 0x82, 0x00, 0x80] + DERVectors.filler(count: 128),
        [0x04, 0x82, 0x00, 0xc9] + DERVectors.filler(count: 201),
        [0x04, 0x83, 0x00, 0x01, 0x00] + DERVectors.filler(count: 256),
        [0x04, 0x89, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05] + DERVectors.filler(count: 5),
    ] as [[UInt8]])
    func `Long-form lengths that a shorter form could express are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.nonMinimalLength) { try DER(decoding: bytes) }
    }

    @Test(arguments: [
        [0x00, 0x00],
        [0x20, 0x00],
        [0x30, 0x02, 0x00, 0x00],
        [0x1f, 0x1f, 0x00],
        [0x3f, 0x22, 0x00],
        [0x9f, 0x64, 0x00],
        [0x7f, 0x81, 0x00, 0x00],
        [0xdf, 0x1f, 0x00],
    ] as [[UInt8]])
    func `High tag numbers and the end-of-contents tag are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.unsupportedTag) { try DER(decoding: bytes) }
    }

    @Test(arguments: [
        [0x21, 0x03, 0x01, 0x01, 0xff],
        [0x22, 0x03, 0x02, 0x01, 0x05],
        [0x23, 0x04, 0x03, 0x02, 0x00, 0x0a],
        [0x23, 0x80, 0x03, 0x03, 0x00, 0x0a, 0x3b, 0x03, 0x05, 0x04, 0x5f, 0x29, 0x1c, 0xd0, 0x00, 0x00],
        [0x24, 0x03, 0x04, 0x01, 0x05],
        [0x25, 0x00],
        [0x26, 0x03, 0x06, 0x01, 0x2a],
        [0x2c, 0x00],
        [0x37, 0x00],
        [0x08, 0x00],
        [0x10, 0x00],
        [0x11, 0x00],
        [0x10, 0x03, 0x02, 0x01, 0x05],
        [0x30, 0x02, 0x11, 0x00],
    ] as [[UInt8]])
    func `Universal values in a form DER doesn't use for their type are rejected`(bytes: [UInt8]) {
        #expect(throws: DER.ValidationError.invalidForm) { try DER(decoding: bytes) }
    }

    @Test
    func `Constructed values nest at most 16 deep, not counting empty ones`() {
        let sixteenAroundNull = Self.sequences(16, around: [0x05, 0x00])
        let sixteenAroundEmpty = Self.sequences(16, around: [0x30, 0x00])
        let seventeenAroundNull = Self.sequences(17, around: [0x05, 0x00])
        let seventeenAroundEmpty = Self.sequences(17, around: [0x30, 0x00])
        let sixteenAroundTagged = Self.sequences(16, around: [0xa0, 0x02, 0x05, 0x00])

        #expect(throws: Never.self) { try DER(decoding: sixteenAroundNull) }
        #expect(throws: Never.self) { try DER(decoding: sixteenAroundEmpty) }
        #expect(throws: DER.ValidationError.nestedTooDeep) { try DER(decoding: seventeenAroundNull) }
        #expect(throws: DER.ValidationError.nestedTooDeep) { try DER(decoding: seventeenAroundEmpty) }
        #expect(throws: DER.ValidationError.nestedTooDeep) { try DER(decoding: sixteenAroundTagged) }
    }

    private static func sequences(_ count: Int, around value: [UInt8]) -> [UInt8] {
        (0..<count).reduce(value) { inner, _ in [0x30, UInt8(inner.count)] + inner }
    }
}

private extension DER.Content {
    var values: [DER]? {
        guard case .constructed(let values) = self else { return nil }
        return values
    }
}
